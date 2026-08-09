import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/detail_tab.dart';
import '../models/file_change.dart';
import '../models/server_config.dart';
import '../models/todo.dart';
import '../services/backend_tester_service.dart';
import '../services/docker_service.dart';
import '../services/env_service.dart';
import '../services/footprint_service.dart';
import '../services/language_service.dart';
import '../services/orchestrator.dart';
import '../services/project_service.dart';
import '../services/port_service.dart';
import '../services/scripts_service.dart';
import '../services/server_service.dart';
import '../services/terminal_service.dart';
import '../services/todo_service.dart';
import '../services/vibe_store.dart';

class AppController extends ChangeNotifier {
  AppController({
    ServerService? server,
    TodoService? todos,
    ProjectService? project,
    TerminalService? terminal,
    EnvService? env,
    DockerService? docker,
    BackendTesterService? backendTester,
    ScriptsService? scripts,
    PortService? ports,
    FootprintService? footprint,
    VibeStore? store,
  })  : server = server ?? ServerService(),
        todos = todos ?? TodoService(),
        project = project ?? ProjectService(),
        terminal = terminal ?? TerminalService(),
        env = env ?? EnvService(),
        docker = docker ?? DockerService(),
        backendTester = backendTester ?? BackendTesterService(),
        store = store ?? VibeStore(),
        ports = ports ?? PortService() {
    this.scripts = scripts ?? ScriptsService(store: this.store);
    this.footprint = footprint ?? FootprintService(store: this.store);
    this.scripts.asker = this.server.askOnce;
    this.server.events.listen(_onServerEvent);
  }

  final ServerService server;
  final TodoService todos;
  final ProjectService project;
  final TerminalService terminal;
  final EnvService env;
  final DockerService docker;
  final BackendTesterService backendTester;
  late final ScriptsService scripts;
  final PortService ports;
  late final FootprintService footprint;
  final VibeStore store;

  /// Free-buffer of stopped worker servers (standby for failover / rate
  /// limits). A worker takes one per job and returns it (stopped, port freed)
  /// when the job finishes. Kept at most [_maxPooledServers] to bound memory.
  final List<ServerService> _serverPool = [];
  static const int _maxPooledServers = 1;
  final Map<ServerService, StreamSubscription<ServerEvent>> _workerSubs = {};
  final Set<int> _usedPorts = {};
  int _portCounter = 0;

  /// Completes when a session's turn goes idle; used by _ensureAgentServer to
  /// wait for the READY handshake before a task prompt is sent.
  final Map<String, Completer<void>> _idleWaiters = {};

  /// Number of standby servers currently in the free buffer (shown in the
  /// AI Team panel).
  int get freeBufferCount => _serverPool.length;

  /// The server an agent talks through: main AI shares the global server,
  /// workers own their short-lived one.
  ServerService _serverFor(Agent agent) => agent.server ?? server;

  ServerConfig serverConfig = ServerConfig();

  /// Whether the app may spawn engineer workers on its own (the "auto
  /// team"). When true, unassigned todos are picked up automatically by up
  /// to [maxAutoWorkers] auto-managed agents, and idle ones are retired again
  /// when the queue drains so their short-lived servers free up RAM.
  bool autoTeam = true;

  /// Cap on how many worker agents the auto team runs at once (bounds RAM and
  /// AI usage). Agents added manually are not counted against it.
  int maxAutoWorkers = 3;

  String? projectDir;
  List<FileNode> fileNodes = [];
  List<Agent> agents = [];

  /// Dominant language of the open project (e.g. "Dart", "Go", "JavaScript"),
  /// refreshed with the file tree. Empty when no project is open.
  String projectLanguage = '';
  final List<SystemLogEntry> systemLog = [];

  /// Directories currently expanded in the file tree. Folders stay collapsed
  /// by default so a big project doesn't explode into view at once.
  final Set<String> expandedDirs = {};

  void toggleDir(String path) {
    if (!expandedDirs.add(path)) {
      expandedDirs.remove(path);
    }
    notifyListeners();
  }

  void collapseAllDirs() {
    expandedDirs.clear();
    notifyListeners();
  }

  /// The single designated "main" AI, or null if none is set.
  Agent? get mainAgent {
    for (final a in agents) {
      if (a.isMain) return a;
    }
    return null;
  }

  /// Makes [agent] the main AI; only one main is allowed.
  void setMainAgent(Agent agent) {
    for (final a in agents) {
      a.isMain = a == agent;
    }
    notifyListeners();
  }

  /// A running tester (QA) agent, if any. "Running" means an active team
  /// member (it may be between jobs with no live server yet).
  Agent? get runningTester {
    for (final a in agents) {
      if (a.role == AgentRole.tester && a.status != AgentStatus.stopped) {
        return a;
      }
    }
    return null;
  }

  /// Short, safe summary of the project fed to every agent's system prompt.
  String _agentContext() {
    final b = StringBuffer();
    b.writeln('Working directory: ${projectDir ?? '.'}');
    b.writeln(
        'Databases detected: ${env.databases.isEmpty ? 'none' : env.databases.join(', ')}');
    b.writeln(
        'Environment variables available to shells: ${env.vars.isEmpty ? 'none' : env.vars.keys.join(', ')}');
    if (env.tables.isNotEmpty) {
      b.writeln('Database schema (tables and columns):');
      for (final t in env.tables) {
        b.writeln('- ${t.name}: ${t.columns.join(', ')}');
      }
    }
    if (env.composeFile != null) {
      b.writeln(
          'Docker compose file: ${env.composeFile} — start the stack before running tests that need it.');
    }
    if (footprint.exists) {
      b.writeln('');
      b.writeln('Project memory (footprint file):');
      b.writeln(footprint.content);
    }
    final pdir = projectDir;
    if (pdir != null) {
      final analysis = store.analysisFor(pdir);
      if (analysis != null && analysis.isNotEmpty) {
        b.writeln('');
        b.writeln('Stored project-analysis summary (produced on first open):');
        b.writeln(analysis);
      }
    }
    return b.toString().trimRight();
  }

  /// A compact snapshot of the current todo ledger, fed to agents so the main
  /// AI can see the team's work and plan/assign.
  String _todosSnapshot() {
    final l = _ledger;
    if (l == null || l.todos.isEmpty) return '';
    final b = StringBuffer();
    for (final t in l.todos) {
      final who = t.assignee ?? 'unassigned';
      b.writeln(
          '- [${t.id}] (${t.status.wire}) assigned to $who: ${t.title}${t.description.isNotEmpty ? ' — ${t.description}' : ''}');
    }
    return b.toString().trimRight();
  }

  /// Sends a plain-language mission to the main AI (e.g. "UI is broken and
  /// server error"). The main AI explores the project and breaks it into todos
  /// the team then works.
  Future<bool> sendToMain(String text) async {
    final main = mainAgent;
    if (main == null || main.sessionId == null) return false;
    final t = text.trim();
    if (t.isEmpty) return false;
    try {
      await server.sendMessage(
        sessionId: main.sessionId!,
        text: 'MISSION from the user:\n$t\n\n'
            'Analyze the project and turn this into concrete todos in '
            'vibestudio.json (status "todo", assignee null) for the team. '
            'Workers will pick them up and report summaries back to you.',
      );
      main.logLine('⇐ mission: $t');
      notifyListeners();
      return true;
    } catch (e) {
      logSystem('Failed to send mission to main AI: $e', isError: true);
      return false;
    }
  }

  String? openFile;
  String editorContent = '';
  bool editorDirty = false;

  // Detail tabs opened in the center editor area (VS Code style, no popups or
  // modals). Multiple tabs can be open; the underlying processes keep running
  // when a tab is closed.
  final List<DetailTab> _detailTabs = [];
  DetailTab? _activeDetailTab;

  List<DetailTab> get detailTabs => List.unmodifiable(_detailTabs);

  DetailTab? get activeDetailTab => _activeDetailTab;

  /// The live port of the active port tab, or null.
  ListenPort? get activePort {
    final tab = _activeDetailTab;
    if (tab?.kind != DetailTabKind.port) return null;
    return ports.ports
        .where((p) => p.port == tab!.portNumber)
        .firstOrNull;
  }

  /// The live script run of the active script tab, or null.
  ScriptRun? get activeScript {
    final tab = _activeDetailTab;
    if (tab?.kind != DetailTabKind.script) return null;
    return scripts.scripts
        .where((s) => s.name == tab!.scriptName)
        .firstOrNull;
  }

  void openPortDetail(ListenPort port) {
    _addOrActivateTab(DetailTab.port(port.port));
  }

  void openScriptDetail(ScriptRun script) {
    _addOrActivateTab(DetailTab.script(script.name));
  }

  void openScriptComposer() {
    _addOrActivateTab(const DetailTab.composer());
  }

  void _addOrActivateTab(DetailTab tab) {
    final existing = _detailTabs.indexWhere((t) => t.id == tab.id);
    if (existing >= 0) {
      _activeDetailTab = _detailTabs[existing];
    } else {
      _detailTabs.add(tab);
      _activeDetailTab = tab;
    }
    notifyListeners();
  }

  void activateDetailTab(String id) {
    final found = _detailTabs.where((t) => t.id == id).firstOrNull;
    if (found == null) return;
    _activeDetailTab = found;
    notifyListeners();
  }

  /// Closes the active detail tab (the process keeps running).
  void closeDetail() {
    final active = _activeDetailTab;
    if (active != null) closeDetailTab(active.id);
  }

  /// Closes the tab with the given id (the process keeps running).
  void closeDetailTab(String id) {
    final idx = _detailTabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _detailTabs.removeAt(idx);
    if (_activeDetailTab?.id == id) {
      _activeDetailTab = _detailTabs.isEmpty
          ? null
          : _detailTabs[idx.clamp(0, _detailTabs.length - 1)];
    }
    notifyListeners();
  }
  final ValueNotifier<int> fileRefreshTick = ValueNotifier(0);

  Timer? _ticker;
  bool _disposed = false;
  int _agentCounter = 0;
  int _ledgerSig = -1;
  DateTime? _lastServerErrorLog;

  bool get isProjectOpen => projectDir != null;

  String get serverStatusLabel => switch (server.state) {
        ServerState.stopped => 'server stopped',
        ServerState.starting => 'server starting…',
        ServerState.running => 'server running (port ${server.port})',
        ServerState.error => 'server error',
      };

  void logSystem(String text, {bool isError = false}) {
    if (_disposed) return;
    systemLog.add(SystemLogEntry(text, isError: isError));
    if (systemLog.length > 1000) systemLog.removeRange(0, systemLog.length - 1000);
    notifyListeners();
  }

  // ---------------------------------------------------------------- settings

  static File _settingsFile() {
    final home = Platform.environment['HOME'] ?? '.';
    return File('$home/.vibestudio/settings.json');
  }

  Future<void> loadSettings() async {
    try {
      final f = _settingsFile();
      if (await f.exists()) {
        final json =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        serverConfig = ServerConfig.fromJson(json);
      }
    } catch (_) {}
    backendTester.setMigrateCommand(serverConfig.migrationCheckCommand);
  }

  /// App startup: load settings + the VibeStudio DB, then open the most recent
  /// project (the first one whose folder still exists).
  Future<void> bootstrapApp() async {
    await loadSettings();
    await store.load();
    for (final dir in store.recentProjects) {
      if (dir.isEmpty) continue;
      if (await Directory(dir).exists()) {
        await openProjectAt(dir);
        return;
      }
      await store.removeRecent(dir);
    }
  }

  Future<void> saveSettings() async {
    serverConfig = serverConfig.copyWith(
      migrationCheckCommand: backendTester.migrateCommand,
    );
    try {
      final f = _settingsFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(serverConfig.toJson()));
      logSystem(
          'Settings saved (port ${serverConfig.port}, model ${serverConfig.modelID.isEmpty ? "builtin" : serverConfig.modelID})');
    } catch (e) {
      logSystem('Failed to save settings: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------- project

  Future<bool> openProject() async {
    final dir = await project.pickFolder();
    if (dir == null) return false;
    return openProjectAt(dir);
  }

  /// Persist settings and restart the server so they take effect.
  Future<void> applySettings(ServerConfig config) async {
    final wasOpen = isProjectOpen;
    final dir = projectDir;
    serverConfig = config;
    await saveSettings();
    notifyListeners();
    if (wasOpen && dir != null) {
      logSystem('Restarting server with new settings…');
      await closeProject();
      await openProjectAt(dir);
    }
  }

  /// Programmatic project open (used by tests and the folder picker).
  Future<bool> openProjectAt(String dir) async {
    await closeProject();
    await store.addRecent(dir);

    projectDir = dir;
    todos.projectDir = dir;
    await todos.seedIfMissing();
    await env.load(dir);
    await footprint.load(dir, env);
    await docker.setComposeFile(env.composeFile);
    await scripts.setProjectDir(dir);
    if (backendTester.migrateCommand.isEmpty) {
      backendTester.setMigrateCommand(
        BackendTesterService.guessMigrationCommand(dir, env),
      );
    }
    fileNodes = project.scanTree(dir);
    projectLanguage = detectProjectLanguage(fileNodes) ?? '';
    _resetActivity();
    terminal.start(projectDir: dir, environment: env.vars);
    try {
      await server.start(
        projectDir: dir,
        config: serverConfig,
        environment: env.vars,
      );
      logSystem('Server ready on port ${server.port} for $dir');
    } catch (e) {
      logSystem('Failed to start server: $e', isError: true);
      notifyListeners();
      return false;
    }

    if (env.vars.isNotEmpty || env.databases.isNotEmpty) {
      logSystem('Loaded ${env.envCount} env var(s); '
          'databases: ${env.databases.isEmpty ? 'none' : env.databases.join(', ')}');
    }

    // First open: ask the AI to analyze the whole project once and store the
    // summary in the VibeStudio DB; later opens reuse it (see _agentContext).
    if (!store.isAnalyzed(dir)) {
      unawaited(_analyzeProject(dir));
    }

    _ticker = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) {
        if (_disposed) return;
        _tick();
      },
    );
    notifyListeners();
    return true;
  }

  /// Re-reads `.env`, redetects databases, and restarts the terminal with the
  /// new variables. (The server keeps its original env until it restarts.)
  Future<void> reloadEnv() async {
    await env.reload();
    await docker.setComposeFile(env.composeFile);
    await terminal.restart(environment: env.vars);
    logSystem('Reloaded .env (${env.envCount} var(s), '
        'databases: ${env.databases.isEmpty ? 'none' : env.databases.join(', ')})');
    notifyListeners();
  }

  /// Opens opencode itself to write the missing standard run scripts
  /// (start.sh / stop.sh / migration.sh).
  Future<void> bootstrapScripts() {
    return scripts.bootstrap(context: _agentContext(), envVars: env.vars);
  }

  /// Fire-and-forget whole-project analysis on first open: one throwaway
  /// session asks the AI to explore everything, then the summary is stored in
  /// the VibeStudio DB and injected into every later agent context.
  Future<void> _analyzeProject(String dir) async {
    try {
      logSystem('Analyzing the whole project (first open)…');
      final summary = await server.askOnce(
        buildAnalysisPrompt(dir, context: _agentContext()),
        title: 'vibestudio project analysis',
      );
      await store.setAnalysis(dir, summary);
      logSystem('Project analysis stored for $dir');
      notifyListeners();
    } catch (e) {
      logSystem('Project analysis failed: $e', isError: true);
    }
  }

  Future<void> closeProject() async {
    _ticker?.cancel();
    _ticker = null;
    for (final agent in List<Agent>.from(agents)) {
      await stopAgent(agent, requeue: false);
    }
    agents.clear();
    _agentCounter = 0;
    _clearWorkerPool();
    await server.stop();
    await terminal.stop();
    await docker.setComposeFile(null);
    await scripts.setProjectDir('');
    await env.reset();
    projectDir = null;
    fileNodes = [];
    projectLanguage = '';
    _resetActivity();
    openFile = null;
    editorContent = '';
    editorDirty = false;
    _detailTabs.clear();
    _activeDetailTab = null;
    notifyListeners();
  }

  void _clearWorkerPool() {
    for (final sub in _workerSubs.values) {
      sub.cancel();
    }
    _workerSubs.clear();
    for (final s in _serverPool) {
      s.dispose();
    }
    _serverPool.clear();
    _usedPorts.clear();
    _portCounter = 0;
  }

  // ----------------------------------------------------------------- agents

  /// Spawns (or takes from the free buffer) a short-lived worker server and
  /// reserves a free port so two servers never collide.
  Future<ServerService> _acquireWorkerServer() async {
    var s = _serverPool.isNotEmpty ? _serverPool.removeLast() : ServerService();
    final port = _nextWorkerPort();
    try {
      await s.start(
        projectDir: projectDir!,
        config: serverConfig,
        environment: env.vars,
        overridePort: port,
      );
    } catch (e) {
      _usedPorts.remove(port);
      rethrow;
    }
    _wireWorkerServer(s);
    return s;
  }

  int _nextWorkerPort() {
    var p = 4200 + _portCounter++ % 700;
    while (_usedPorts.contains(p) || p == server.port) {
      p = 4200 + _portCounter++ % 700;
    }
    _usedPorts.add(p);
    return p;
  }

  /// A worker finished its job: stop its server (frees the port) and return
  /// the stopped instance to the free buffer as a standby, if there is room.
  void _releaseWorkerServer(ServerService s) {
    _unwireWorkerServer(s);
    _usedPorts.remove(s.port);
    unawaited(s.stop());
    if (_serverPool.length < _maxPooledServers) {
      _serverPool.add(s);
    } else {
      s.dispose();
    }
    notifyListeners();
  }

  /// A server failed or hit rate limits: kill it and never reuse it.
  void _discardWorkerServer(ServerService s) {
    _unwireWorkerServer(s);
    _usedPorts.remove(s.port);
    unawaited(s.stop());
    s.dispose();
    notifyListeners();
  }

  void _wireWorkerServer(ServerService s) {
    _workerSubs[s] = s.events.listen((e) {
      if (_disposed) return;
      switch (e.type) {
        case 'session.status':
          _handleSessionStatus(e);
        case 'message.part.updated':
          _handleMessagePart(e);
        case 'server.exit':
          for (final a in agents) {
            if (identical(a.server, s) && a.status != AgentStatus.stopped) {
              a.status = AgentStatus.error;
              a.lastError = 'worker server exited';
              a.logLine('worker server exited', isError: true);
            }
          }
          notifyListeners();
      }
    });
  }

  void _unwireWorkerServer(ServerService s) {
    _workerSubs.remove(s)?.cancel();
  }

  /// Makes sure the agent has a live server + session with its system prompt.
  /// Workers spawn a short-lived server on demand; if it fails or rate-limits,
  /// the free-buffer standby takes over.
  Future<bool> _ensureAgentServer(Agent agent) async {
    if (agent.sessionId != null) return true;
    var srv = agent.server;
    if (srv == null) {
      try {
        srv = await _acquireWorkerServer();
      } catch (e) {
        agent.status = AgentStatus.error;
        agent.lastError = '$e';
        agent.logLine('failed to start worker server: $e', isError: true);
        notifyListeners();
        return false;
      }
      agent.server = srv;
      agent.logLine('server ready on port ${srv.port}');
      notifyListeners();
    }
    final prompt = buildSystemPrompt(agent, projectDir ?? '.',
        context: _agentContext(), todos: _todosSnapshot());
    try {
      agent.sessionId = await srv.createSession(title: agent.name);
      var gaveUp = false;
      final ready = Completer<void>();
      _idleWaiters[agent.sessionId!] = ready;
      await srv.sendMessage(sessionId: agent.sessionId!, text: prompt);
      // Wait for the READY turn to go idle so the later task prompt's idle
      // event is the one that counts as task completion. If the handshake
      // never completes, this server is unhealthy — fail over.
      try {
        await ready.future.timeout(const Duration(seconds: 180), onTimeout: () {
          gaveUp = true;
        });
      } finally {
        _idleWaiters.remove(agent.sessionId);
      }
      if (gaveUp) throw StateError('READY handshake timed out');
      agent.lastError = null;
      agent.logLine('READY — waiting for tasks');
      notifyListeners();
      return true;
    } catch (e) {
      // Failover: the free-buffer standby server takes over this job.
      _idleWaiters.remove(agent.sessionId);
      if (agent.sessionId != null) {
        unawaited(srv.deleteSession(agent.sessionId!));
      }
      agent.logLine('server failed on port ${srv.port}: $e — failover',
          isError: true);
      _discardWorkerServer(srv);
      agent.server = null;
      agent.sessionId = null;
      try {
        final backup = await _acquireWorkerServer();
        agent.server = backup;
        agent.logLine('failover: server ready on port ${backup.port}');
        agent.sessionId = await backup.createSession(title: agent.name);
        var gaveUp = false;
        final ready = Completer<void>();
        _idleWaiters[agent.sessionId!] = ready;
        await backup.sendMessage(sessionId: agent.sessionId!, text: prompt);
        try {
          await ready.future.timeout(const Duration(seconds: 180),
              onTimeout: () {
            gaveUp = true;
          });
        } finally {
          _idleWaiters.remove(agent.sessionId);
        }
        if (gaveUp) throw StateError('READY handshake timed out');
        agent.lastError = null;
        agent.logLine('READY — waiting for tasks');
        notifyListeners();
        return true;
      } catch (e2) {
        _idleWaiters.remove(agent.sessionId);
        agent.status = AgentStatus.error;
        agent.lastError = '$e2';
        agent.logLine('failover failed: $e2', isError: true);
        notifyListeners();
        return false;
      }
    }
  }

  /// Deletes the agent's session and releases its short-lived server back to
  /// the free buffer (main AI keeps the shared global server).
  Future<void> _releaseAgentServer(Agent agent) async {
    final srv = _serverFor(agent);
    if (agent.sessionId != null) {
      try {
        await srv.deleteSession(agent.sessionId!);
      } catch (_) {}
      agent.sessionId = null;
    }
    final worker = agent.server;
    if (worker != null && !identical(worker, server)) {
      agent.server = null;
      _releaseWorkerServer(worker);
    }
  }

  /// A worker finished its job: its short-lived server stops (port freed) and
  /// returns to the free buffer; the agent stays active for the next job.
  Future<void> _finishWorkerJob(Agent agent) async {
    await _releaseAgentServer(agent);
    agent.currentTask = null;
    agent.currentTaskId = null;
    agent.taskStartedAt = null;
    agent.lastStallWarnAt = null;
    agent.status = AgentStatus.idle;
    agent.logLine('server stopped — ready for next job');
    notifyListeners();
  }

  Future<Agent> addAgent({
    String? name,
    AgentRole role = AgentRole.engineer,
    bool isMain = false,
    bool autoManaged = false,
  }) async {
    _agentCounter++;
    final agent = Agent(
      id: 'agent-$_agentCounter',
      name: name ?? 'Agent $_agentCounter',
      role: role,
      isMain: isMain,
      autoManaged: autoManaged,
    );
    if (isMain) {
      for (final a in agents) {
        a.isMain = false;
      }
    }
    agents.add(agent);
    notifyListeners();
    await startAgent(agent);
    return agent;
  }

  Future<void> startAgent(Agent agent) async {
    if (agent.isMain) {
      if (!server.isRunning) {
        agent.status = AgentStatus.error;
        agent.lastError = 'server not running';
        agent.logLine('cannot start: server not running', isError: true);
        notifyListeners();
        return;
      }
      agent.status = AgentStatus.starting;
      agent.logLine('creating session…');
      notifyListeners();
      try {
        agent.sessionId ??= await server.createSession(title: agent.name);
        agent.logLine('session ${agent.sessionId} created');
        await server.sendMessage(
          sessionId: agent.sessionId!,
          text: buildSystemPrompt(agent, projectDir ?? '.',
              context: _agentContext(), todos: _todosSnapshot()),
        );
        agent.status = AgentStatus.idle;
        agent.logLine('READY — waiting for tasks');
        agent.lastError = null;
      } catch (e) {
        agent.status = AgentStatus.error;
        agent.lastError = '$e';
        agent.logLine('start failed: $e', isError: true);
        logSystem('Agent ${agent.name} failed to start: $e', isError: true);
      }
      notifyListeners();
      return;
    }
    // Worker: no server yet — a short-lived one is spawned per job (see
    // _ensureAgentServer) and stopped when the job finishes.
    agent.status = AgentStatus.idle;
    agent.lastError = null;
    agent.logLine('ready — spawns a short-lived server per job');
    notifyListeners();
  }

  Future<void> stopAgent(Agent agent, {bool requeue = true}) async {
    await _releaseAgentServer(agent);
    if (requeue && agent.currentTaskId != null) {
      final taskId = agent.currentTaskId!;
      await todos.update((ledger) {
        for (final t in ledger.todos) {
          if (t.id == taskId && t.status == TodoStatus.inProgress) {
            t.status = TodoStatus.todo;
            t.assignee = null;
            t.updatedAt = DateTime.now().millisecondsSinceEpoch;
          }
        }
      });
    }
    agent.currentTask = null;
    agent.currentTaskId = null;
    agent.taskStartedAt = null;
    agent.lastStallWarnAt = null;
    agent.status = AgentStatus.stopped;
    agent.logLine('stopped');
    notifyListeners();
  }

  Future<void> stopAll() async {
    for (final agent in List<Agent>.from(agents)) {
      await stopAgent(agent);
    }
  }

  // ------------------------------------------------------------------ todos

  Future<void> addTodo(String title, String description) async {
    final item = TodoItem(
      id: TodoService.newId(),
      title: title,
      description: description,
    );
    await todos.update((ledger) => ledger.todos.add(item));
    _ledgerSig = -1;
    await _reloadTodos();
    notifyListeners();
  }

  Future<void> updateTodo(TodoItem item) async {
    await todos.update((ledger) {
      final i = ledger.todos.indexWhere((t) => t.id == item.id);
      if (i >= 0) ledger.todos[i] = item;
    });
    _ledgerSig = -1;
    await _reloadTodos();
    notifyListeners();
  }

  Future<void> deleteTodo(String id) async {
    await todos.update((ledger) => ledger.todos.removeWhere((t) => t.id == id));
    _ledgerSig = -1;
    await _reloadTodos();
    notifyListeners();
  }

  TodoLedger? _ledger;
  List<TodoItem> get todoItems => _ledger?.todos ?? [];

  Future<void> _reloadTodos() async {
    final fresh = await todos.load();
    final changed = _ledgerSig != _computeSig(fresh);
    _ledger = fresh;
    _ledgerSig = _computeSig(fresh);
    if (changed) {
      _pushTodosToMain();
    }
  }

  /// Sends the current todo list to the main AI so it always sees the team's
  /// work after the user (or a worker) changes vibestudio.json.
  void _pushTodosToMain() {
    final main = mainAgent;
    if (main == null || main.sessionId == null) return;
    if (!server.isRunning || main.status != AgentStatus.idle) return;
    final snapshot = _todosSnapshot();
    if (snapshot.isEmpty) return;
    unawaited(_sendTodosToMain(main, snapshot));
  }

  Future<void> _sendTodosToMain(Agent main, String snapshot) async {
    try {
      await server.sendMessage(
        sessionId: main.sessionId!,
        text: 'UPDATED TODO LIST\n\n$snapshot\n\n'
            "This is the team's current work. Plan and assign as needed.",
      );
      main.logLine('⇐ updated todo list');
      notifyListeners();
    } catch (e) {
      logSystem('Failed to send todo list to main AI: $e', isError: true);
    }
  }

  int _computeSig(TodoLedger ledger) {
    var h = 0;
    for (final t in ledger.todos) {
      h = h * 31 + t.id.hashCode;
      h = h * 31 + t.status.hashCode;
      h = h * 31 + (t.assignee?.hashCode ?? 0);
      h = h * 31 + t.title.hashCode;
    }
    return h;
  }

  // ----------------------------------------------------------------- editor

  Future<void> openFileAt(String path) async {
    openFile = path;
    editorContent = await project.readFile(path);
    editorDirty = false;
    _activeDetailTab = null;
    fileRefreshTick.value++;
    notifyListeners();
  }

  void markEditorDirtyQuiet(String content) {
    editorContent = content;
    editorDirty = true;
  }

  Future<void> saveEditor() async {
    if (openFile == null) return;
    await project.writeFile(openFile!, editorContent);
    editorDirty = false;
    fileRefreshTick.value++;
    notifyListeners();
  }

  // ------------------------------------------------------------------ tick

  /// GitHub-like feed of project changes (added / modified / deleted files)
  /// so the user can notice what the AI team did.
  final List<FileChangeEvent> activity = [];
  Map<String, int> _fileSnapshot = {};

  void clearActivity() {
    activity.clear();
    notifyListeners();
  }

  /// Baseline the snapshot so the first tick does not report every file as new.
  void _resetActivity() {
    activity.clear();
    _fileSnapshot = {};
    _snapshotFiles();
  }

  void _snapshotFiles() {
    final files = <String>[];
    for (final n in fileNodes) {
      _collectFiles(n, files);
    }
    _fileSnapshot = {
      for (final f in files)
        f: project.fileModified(f)?.millisecondsSinceEpoch ?? 0,
    };
  }

  /// Compares the current tree against the last snapshot and records events.
  void _diffProjectFiles() {
    if (projectDir == null) return;
    final root = projectDir!;
    final files = <String>[];
    for (final n in fileNodes) {
      _collectFiles(n, files);
    }

    final now = DateTime.now();
    final current = <String, int>{
      for (final f in files) f: project.fileModified(f)?.millisecondsSinceEpoch ?? 0,
    };

    for (final f in files) {
      if (!_fileSnapshot.containsKey(f)) {
        _addEvent(FileChangeEvent(
          type: FileChangeType.added,
          path: f,
          relPath: _rel(f, root),
          time: now,
          newSize: _sizeOf(f),
        ));
      }
    }
    for (final entry in _fileSnapshot.entries) {
      if (!current.containsKey(entry.key)) {
        _addEvent(FileChangeEvent(
          type: FileChangeType.deleted,
          path: entry.key,
          relPath: _rel(entry.key, root),
          time: now,
          oldSize: entry.value > 0 ? _sizeOf(entry.key) : 0,
        ));
      }
    }
    for (final f in files) {
      final prev = _fileSnapshot[f];
      final nowMs = current[f];
      if (prev != null && nowMs != null && nowMs > prev) {
        _addEvent(FileChangeEvent(
          type: FileChangeType.modified,
          path: f,
          relPath: _rel(f, root),
          time: now,
          oldSize: prev > 0 ? prev : 0,
          newSize: _sizeOf(f),
        ));
      }
    }
    _fileSnapshot = current;
  }

  void _addEvent(FileChangeEvent event) {
    activity.insert(0, event);
    if (activity.length > 500) activity.removeRange(500, activity.length);
  }

  static String _rel(String path, String root) {
    final p = path.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    return p.startsWith(r) ? p.substring(r.length).replaceFirst('/', '') : p;
  }

  static int _sizeOf(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.lengthSync() : 0;
    } catch (_) {
      return 0;
    }
  }

  static void _collectFiles(FileNode node, List<String> out) {
    if (node.isDir) {
      for (final c in node.children) {
        _collectFiles(c, out);
      }
    } else {
      out.add(node.path);
    }
  }

  Future<void> _tick() async {
    if (_disposed) return;
    try {
      if (isProjectOpen && server.isRunning) {
        fileNodes = project.scanTree(projectDir!);
        projectLanguage = detectProjectLanguage(fileNodes) ?? '';
        fileRefreshTick.value++; // repaint file tree
        _diffProjectFiles();
        if (activity.isNotEmpty) notifyListeners();
      }

      if (openFile != null && !editorDirty) {
        final mtime = project.fileModified(openFile!);
        if (mtime != null &&
            mtime.isAfter(_lastKnownMtime ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          final fresh = await project.readFile(openFile!);
          if (fresh != editorContent) {
            editorContent = fresh;
            fileRefreshTick.value++;
          }
        }
        _lastKnownMtime = mtime;
      }

      await _reloadTodos();
      if (_disposed) return;
      if (_ledgerSig != _computeSig(_ledger ?? const TodoLedger(todos: []))) {
        notifyListeners();
      }

      if (!isProjectOpen) return;

      await _autoScaleWorkers();
      if (_disposed) return;

      for (final agent in List<Agent>.from(agents)) {
        if (_disposed) return;
        if (agent.role == AgentRole.tester) {
          if (agent.status == AgentStatus.busy && agent.currentTaskId != null) {
            await _checkStall(agent);
          }
          continue;
        }
        if (agent.isMain) continue;
        if (agent.busy && agent.currentTaskId != null) {
          await _checkStall(agent);
        } else if (agent.currentTaskId == null &&
            agent.status != AgentStatus.error) {
          await _assignNext(agent);
        }
      }
    } catch (e) {
      logSystem('tick error: $e', isError: true);
    }
  }

  DateTime? _lastKnownMtime;

  /// Auto team: while unassigned todos exist, top up auto-managed engineer
  /// workers to [maxAutoWorkers] (never more, and never more than the number
  /// of pending tasks). Once the queue drains, retire idle (or broken) auto
  /// workers so their sessions and short-lived servers stop and RAM is freed.
  Future<void> _autoScaleWorkers() async {
    if (!isProjectOpen || !autoTeam) return;
    final ledger = _ledger;
    if (ledger == null) return;

    final pending = ledger.todos
        .where((t) => t.status == TodoStatus.todo)
        .length;

    final activeAuto = agents
        .where((a) =>
            a.autoManaged &&
            !a.isMain &&
            a.role == AgentRole.engineer &&
            (a.status == AgentStatus.idle ||
                a.status == AgentStatus.busy ||
                a.status == AgentStatus.starting))
        .length;

    if (pending > 0) {
      // A broken auto worker must not hog a slot forever: replace it. Its
      // in-progress task (if any) is requeued so it is never lost.
      for (final a in List<Agent>.from(agents)) {
        if (a.autoManaged &&
            !a.isMain &&
            a.role == AgentRole.engineer &&
            a.status == AgentStatus.error) {
          await stopAgent(a, requeue: true);
          agents.remove(a);
          logSystem('Auto team: replaced broken worker ${a.name}');
        }
      }
      // Only spawn to the number of tasks still needing a worker, and never
      // past the cap — idle workers are counted, so no over-spawn.
      final needed = maxAutoWorkers < pending ? maxAutoWorkers : pending;
      final toSpawn = needed - activeAuto;
      if (toSpawn <= 0) return;
      for (var i = 0; i < toSpawn; i++) {
        logSystem('Auto team: $pending task(s) queued, spawning worker '
            '${activeAuto + i + 1}/$maxAutoWorkers');
        await addAgent(role: AgentRole.engineer, autoManaged: true);
      }
    } else {
      // Queue drained: retire idle, broken, or manually-stopped auto workers
      // so their short-lived servers stop and RAM is freed. requeue is a no-op
      // for agents without a current task and rescues any in-progress one.
      final retiring = <Agent>[];
      for (final a in List<Agent>.from(agents)) {
        if (a.autoManaged &&
            !a.isMain &&
            a.role == AgentRole.engineer &&
            (a.status == AgentStatus.idle ||
                a.status == AgentStatus.error ||
                a.status == AgentStatus.stopped)) {
          retiring.add(a);
        }
      }
      for (final a in retiring) {
        await stopAgent(a, requeue: true);
        agents.remove(a);
        logSystem('Auto team: queue empty, retired worker ${a.name}');
      }
    }
  }

  Future<void> _assignNext(Agent agent) async {
    // QA testers never pick up implementation todos; they only get verify
    // requests dispatched by _afterTaskDone.
    if (agent.role == AgentRole.tester) return;
    final ledger = await todos.load();
    final next = pickNextTodo(ledger);
    if (next == null) return;

    final claimed = TodoItem(
      id: next.id,
      title: next.title,
      description: next.description,
      status: TodoStatus.inProgress,
      assignee: agent.id,
      createdAt: next.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await todos.update((l) {
      final i = l.todos.indexWhere((t) => t.id == next.id);
      if (i < 0 || l.todos[i].status != TodoStatus.todo) return;
      l.todos[i] = claimed;
    });

    agent.currentTask = next.title;
    agent.currentTaskId = next.id;
    agent.taskStartedAt = DateTime.now().millisecondsSinceEpoch;
    agent.lastStallWarnAt = null;
    agent.status = AgentStatus.starting;
    agent.logLine('assigned: "${next.title}"');
    notifyListeners();

    final ok = await _ensureAgentServer(agent);
    if (!ok) {
      await todos.update((l) {
        for (final t in l.todos) {
          if (t.id == next.id) {
            t.status = TodoStatus.todo;
            t.assignee = null;
          }
        }
      });
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.status = AgentStatus.error;
      notifyListeners();
      return;
    }

    agent.status = AgentStatus.busy;
    notifyListeners();
    try {
      await _serverFor(agent).sendMessage(
        sessionId: agent.sessionId!,
        text: buildTaskPrompt(agent, claimed),
      );
    } catch (e) {
      agent.status = AgentStatus.error;
      agent.lastError = '$e';
      agent.logLine('send failed: $e', isError: true);
      await todos.update((l) {
        for (final t in l.todos) {
          if (t.id == next.id) {
            t.status = TodoStatus.todo;
            t.assignee = null;
          }
        }
      });
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.status = AgentStatus.idle;
      notifyListeners();
    }
  }

  Future<void> _checkStall(Agent agent) async {
    final started = agent.taskStartedAt ?? 0;
    final elapsedMin = (DateTime.now().millisecondsSinceEpoch - started) / 60000;
    final todo = _ledger?.todos
        .where((t) => t.id == agent.currentTaskId)
        .firstOrNull;

    if (elapsedMin >= stallRequeueMinutes) {
      await todos.update((l) {
        for (final t in l.todos) {
          if (t.id == agent.currentTaskId) {
            t.status = TodoStatus.todo;
            t.assignee = null;
          }
        }
      });
      agent.logLine(
        'STALL: requeued "${agent.currentTask}" after ${elapsedMin.toStringAsFixed(0)} min',
        isError: true,
      );
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.lastStallWarnAt = null;
      agent.status = AgentStatus.idle;
      notifyListeners();
    } else if (elapsedMin >= stallWarnMinutes) {
      final lastWarn = agent.lastStallWarnAt ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - lastWarn > stallWarnMinutes * 60000) {
        agent.lastStallWarnAt = DateTime.now().millisecondsSinceEpoch;
        agent.logLine(
          'nudging: "${agent.currentTask}" running ${elapsedMin.toStringAsFixed(0)} min',
        );
        if (todo != null) {
          try {
            await _serverFor(agent).sendMessage(
              sessionId: agent.sessionId!,
              text: buildStallWarnPrompt(todo, elapsedMin.round()),
            );
          } catch (_) {}
        }
        notifyListeners();
      }
    }
  }

  // ----------------------------------------------- summary, verify, shutdown

  /// Called when an agent marks a task done (session goes idle after work).
  ///
  /// Flow:
  /// - The main AI stays alive and just receives reports.
  /// - A tester finishing a VERIFY request forwards its verdict to the main
  ///   AI and stops its short-lived server (returns to the free buffer).
  /// - A worker that finishes an implementation task gets its summary sent to
  ///   the main AI, triggers a QA verification when a tester exists, then its
  ///   short-lived server stops (frees the port, returns to the buffer). The
  ///   worker stays active and spawns a server again for its next job.
  Future<void> _afterTaskDone(Agent agent) async {
    final task = agent.currentTask ?? '';
    final taskId = agent.currentTaskId;
    final summary = _agentSummary(agent);

    if (agent.isMain) return;

    if (agent.role == AgentRole.tester && taskId?.startsWith('verify:') == true) {
      await _forwardVerificationResult(agent, task, summary);
      await _finishWorkerJob(agent);
      return;
    }

    final tester = runningTester;
    if (tester != null && tester != agent && !tester.busy) {
      unawaited(_enqueueVerification(tester, task, taskId));
    }

    final main = mainAgent;
    if (main != null && main.sessionId != null) {
      try {
        await _serverFor(main).sendMessage(
          sessionId: main.sessionId!,
          text: _summaryMessage(agent, task, summary),
        );
        main.logLine('⇐ summary from ${agent.name}');
        notifyListeners();
      } catch (e) {
        logSystem('Failed to send summary to main AI: $e', isError: true);
      }
    }
    await _finishWorkerJob(agent);
  }

  Future<void> _enqueueVerification(
    Agent tester,
    String task,
    String? taskId,
  ) async {
    tester.currentTask = 'VERIFY: $task';
    tester.currentTaskId = 'verify:${taskId ?? 'task'}';
    tester.taskStartedAt = DateTime.now().millisecondsSinceEpoch;
    tester.lastStallWarnAt = null;
    tester.status = AgentStatus.starting;
    tester.logLine('verify: "$task"');
    notifyListeners();
    final ok = await _ensureAgentServer(tester);
    if (!ok) {
      tester.status = AgentStatus.idle;
      tester.currentTask = null;
      tester.currentTaskId = null;
      tester.logLine('verify aborted: no server', isError: true);
      notifyListeners();
      return;
    }
    tester.status = AgentStatus.busy;
    notifyListeners();
    try {
      await _serverFor(tester).sendMessage(
        sessionId: tester.sessionId!,
        text: buildVerifyPrompt(task, task),
      );
    } catch (e) {
      tester.status = AgentStatus.idle;
      tester.currentTask = null;
      tester.currentTaskId = null;
      tester.logLine('verify send failed: $e', isError: true);
      notifyListeners();
    }
  }

  /// Reports a Backend Tester request to the main AI so it can turn what the
  /// tester learned (working endpoints, DB errors, missing columns, ...) into
  /// improved tasks for the workers.
  Future<void> reportBackendResultToMain(BackendRequestResult result) async {
    final main = mainAgent;
    if (main == null || main.sessionId == null) return;

    final schema = StringBuffer();
    if (env.tables.isNotEmpty) {
      schema.writeln('\nCurrent database schema (tables and columns):');
      for (final t in env.tables) {
        schema.writeln('- ${t.name}: ${t.columns.join(', ')}');
      }
    }

    final text = StringBuffer()
      ..writeln('Backend tester result.')
      ..writeln('Request: ${result.method} ${result.url}')
      ..writeln('Result: ${result.statusLabel}')
      ..writeln('Outcome: ${result.success ? 'OK' : 'FAILURE'}');
    if (result.body.trim().isNotEmpty) {
      final body = result.body.length > 1200
          ? result.body.substring(0, 1200)
          : result.body;
      text.writeln('Response body:\n$body');
    }
    if (result.error != null) text.writeln('Transport error: ${result.error}');
    text.write(schema.toString());
    text.writeln(
        '\nIf this reveals a problem or an improvement (e.g. a missing table/column, a failing endpoint), split it into new todos with "status": "todo" and "assignee": null so the team works them.');

    try {
      await server.sendMessage(sessionId: main.sessionId!, text: text.toString());
      main.logLine('⇐ backend tester report');
      notifyListeners();
    } catch (e) {
      logSystem('Failed to send backend tester report: $e', isError: true);
    }
  }

  Future<void> _forwardVerificationResult(
    Agent tester,
    String task,
    String summary,
  ) async {
    final main = mainAgent;
    if (main != null && main.sessionId != null) {
      try {
        await server.sendMessage(
          sessionId: main.sessionId!,
          text: 'Verification report for task "$task" from QA '
              '(${tester.name}).\n\n$summary\n\n— Vibe Studio (QA report)',
        );
        main.logLine('⇐ QA verdict from ${tester.name}');
      } catch (e) {
        logSystem('Failed to send QA report: $e', isError: true);
      }
    }
    notifyListeners();
  }

  /// The worker's final reply (the tail of its log) is its summary.
  String _agentSummary(Agent agent) {
    final texts = agent.log
        .where((e) => !e.isError && e.text.trim().isNotEmpty)
        .map((e) => e.text.trim())
        .toList();
    const markers = {'READY', 'assigned:', 'DONE:', 'verify:'};
    final buf = StringBuffer();
    for (final t in texts) {
      if (markers.any((m) => t.startsWith(m))) continue;
      buf.writeln(t);
    }
    var s = buf.toString().trim();
    if (s.length > 900) s = s.substring(s.length - 900);
    return s.isEmpty ? '(no reply recorded)' : s;
  }

  String _summaryMessage(Agent agent, String task, String summary) {
    return 'Task complete — summary from ${agent.name} (${agent.role}).\n\n'
        'Task: ${task.isEmpty ? '(unknown)' : task}\n\n'
        'Summary:\n$summary\n\n'
        '— Vibe Studio (automatic worker report)';
  }

  // ----------------------------------------------------------- server events

  void _onServerEvent(ServerEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case 'server.ready':
        logSystem('Server ready (port ${event.properties['port']})');
      case 'server.exit':
        if (server.state == ServerState.error) {
          logSystem('Server exited unexpectedly', isError: true);
        }
      case 'server.stderr':
        final text = (event.properties['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          final now = DateTime.now();
          if (_lastServerErrorLog == null ||
              now.difference(_lastServerErrorLog!) > const Duration(seconds: 5)) {
            _lastServerErrorLog = now;
            logSystem('server: $text');
          }
        }
      case 'session.status':
        _handleSessionStatus(event);
      case 'message.part.updated':
        _handleMessagePart(event);
    }
  }

  /// Shared by the main server and every short-lived worker server.
  Future<void> _handleSessionStatus(ServerEvent event) async {
    final sid = event.properties['sessionID'] as String?;
    final status = (event.properties['status'] as Map?)?['type'];
    final agent = _agentForSession(sid);
    if (agent == null || status == null) return;
    if (status == 'busy') {
      if (agent.status == AgentStatus.idle) {
        agent.status = AgentStatus.busy;
      }
      notifyListeners();
    } else if (status == 'idle') {
      _idleWaiters.remove(sid)?.complete();
      // Only a turn while the agent was actively working a task counts as
      // completion. The system-prompt READY turn (status "starting") must not
      // complete the task nor clear its fields.
      if (agent.status == AgentStatus.busy && agent.currentTaskId != null) {
        agent.tasksCompleted++;
        agent.logLine('DONE: "${agent.currentTask}"');
        await _afterTaskDone(agent); // resets the agent + frees its server
      } else if (agent.status != AgentStatus.starting) {
        agent.currentTask = null;
        agent.currentTaskId = null;
        agent.taskStartedAt = null;
        agent.lastStallWarnAt = null;
        agent.status = AgentStatus.idle;
        notifyListeners();
      }
    }
  }

  /// Shared by the main server and every short-lived worker server.
  void _handleMessagePart(ServerEvent event) {
    final sid = event.properties['sessionID'] as String?;
    final part = event.properties['part'] as Map?;
    if (part?['type'] != 'text') return;
    final text = (part?['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return;
    final agent = _agentForSession(sid);
    if (agent != null) {
      agent.logLine(text);
      notifyListeners();
    }
  }

  Agent? _agentForSession(String? sessionId) {
    if (sessionId == null) return null;
    for (final a in agents) {
      if (a.sessionId == sessionId) return a;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _clearWorkerPool();
    server.dispose();
    terminal.dispose();
    scripts.dispose();
    fileRefreshTick.dispose();
    super.dispose();
  }
}

extension FirstOrNullExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
