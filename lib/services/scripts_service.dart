import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vibe_store.dart';

class ScriptRun {
  final String name;
  final String command;
  final bool isStandard;
  bool running;
  int? exitCode;
  String? lastError;
  final List<String> logs;

  ScriptRun({
    required this.name,
    required this.command,
    this.isStandard = false,
    this.running = false,
    this.exitCode,
    this.lastError,
    List<String>? logs,
  }) : logs = logs ?? [];

  void logLine(String line) {
    for (final l in line.split('\n')) {
      logs.add(l);
    }
    if (logs.length > 1500) logs.removeRange(0, logs.length - 1500);
  }
}

/// Project run commands backed by real shell scripts in the project root:
/// `start.sh`, `stop.sh`, `migration.sh`.
///
/// The scripts are written by the AI (once — after that the app never asks
/// again; the commands are also cached in the VibeStudio database). "Run"
/// executes `bash start.sh`, "Stop" executes `bash stop.sh`, "Migration"
/// executes `bash migration.sh`.
class ScriptsService extends ChangeNotifier {
  ScriptsService({required this.store});

  final VibeStore store;

  static const fileNames = <String, String>{
    'Run': 'start.sh',
    'Stop': 'stop.sh',
    'Migration': 'migration.sh',
  };

  String? projectDir;
  final List<ScriptRun> scripts = [];

  bool bootstrapNeeded = false;
  bool bootstrapping = false;
  String? bootstrapError;
  String bootstrapLog = '';

  final Map<String, Process> _procs = {};
  final Map<String, StreamSubscription<String>?> _subs = {};

  File? scriptFile(String name) {
    final dir = projectDir;
    if (dir == null || dir.isEmpty) return null;
    final fname = fileNames[name];
    if (fname == null) return null;
    return File('$dir${Platform.pathSeparator}$fname');
  }

  /// True when start.sh (the main run script) is missing.
  bool _needsBootstrap(String dir) {
    return !File('$dir${Platform.pathSeparator}start.sh').existsSync();
  }

  ScriptRun? byName(String name) {
    for (final s in scripts) {
      if (s.name == name) return s;
    }
    return null;
  }

  ScriptRun? standardScript(String name) => byName(name);

  Future<void> setProjectDir(String dir) async {
    for (final s in List<ScriptRun>.from(scripts)) {
      await stop(s);
    }
    scripts.clear();
    projectDir = dir;
    bootstrapNeeded = false;
    bootstrapError = null;
    bootstrapLog = '';
    bootstrapping = false;
    if (dir.isNotEmpty) {
      bootstrapNeeded = _needsBootstrap(dir);
      if (!bootstrapNeeded) _loadStandardScripts(dir);
      for (final m in store.manualScriptsFor(dir)) {
        scripts.add(ScriptRun(
          name: m['name'] ?? 'script',
          command: m['command'] ?? '',
        ));
      }
    }
    notifyListeners();
  }

  void _loadStandardScripts(String dir) {
    for (final name in fileNames.keys) {
      final f = File('$dir${Platform.pathSeparator}${fileNames[name]}');
      if (f.existsSync()) {
        scripts.add(ScriptRun(
          name: name,
          command: 'bash ${fileNames[name]}',
          isStandard: true,
        ));
      }
    }
  }

  /// Re-reads the project scripts after the AI bootstrap writes them.
  void refreshFromStore() {
    scripts.clear();
    projectDir ??= '';
    if (projectDir!.isNotEmpty) {
      bootstrapNeeded = _needsBootstrap(projectDir!);
      if (!bootstrapNeeded) _loadStandardScripts(projectDir!);
      for (final m in store.manualScriptsFor(projectDir!)) {
        scripts.add(ScriptRun(
          name: m['name'] ?? 'script',
          command: m['command'] ?? '',
        ));
      }
    }
    notifyListeners();
  }

  Future<ScriptRun> addManual(String name, String command) async {
    final dir = projectDir;
    if (dir == null) throw StateError('no project open');
    final trimmedName = name.trim();
    final script = ScriptRun(
      name: trimmedName.isEmpty ? 'script-${scripts.length + 1}' : trimmedName,
      command: command.trim(),
    );
    scripts.add(script);
    await store.addManualScript(dir, script.name, script.command);
    notifyListeners();
    return script;
  }

  Future<void> removeManual(ScriptRun script) async {
    await stop(script);
    scripts.remove(script);
    final dir = projectDir;
    if (dir != null) await store.removeManualScript(dir, script.name);
    notifyListeners();
  }

  /// Runs, or restarts if it is already running.
  Future<void> runOrRestart(ScriptRun script) async {
    if (script.running) {
      await restart(script);
    } else {
      await run(script);
    }
  }

  Future<void> run(ScriptRun script) async {
    final dir = projectDir;
    if (dir == null || script.running) return;
    final cmd = script.command.trim();
    if (cmd.isEmpty) return;
    script.running = true;
    script.exitCode = null;
    script.lastError = null;
    script.logLine(r'$ ' + cmd);
    notifyListeners();
    try {
      final proc = await Process.start(
        'bash',
        ['-ic', cmd],
        workingDirectory: dir,
        environment: Platform.environment,
      );
      _procs[script.name] = proc;
      final out = proc.stdout.transform(utf8.decoder).transform(
            const LineSplitter(),
          );
      final err = proc.stderr.transform(utf8.decoder).transform(
            const LineSplitter(),
          );
      final outSub = out.listen(script.logLine, onError: (_) {});
      final errSub = err.listen(
        (l) => script.logLine('ERR: $l'),
        onError: (_) {},
      );
      _subs[script.name] = outSub;
      script.running = true;
      proc.exitCode.then((code) {
        script.running = false;
        script.exitCode = code;
        script.logLine(code == 0 ? 'exited 0' : 'exited $code');
        outSub.cancel();
        errSub.cancel();
        _subs.remove(script.name);
        _procs.remove(script.name);
        notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      script.running = false;
      script.lastError = '$e';
      script.logLine('failed to start: $e');
      notifyListeners();
    }
  }

  Future<void> stop(ScriptRun script) async {
    final proc = _procs[script.name];
    if (proc == null) {
      script.running = false;
      notifyListeners();
      return;
    }
    try {
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _procs.remove(script.name);
    script.running = false;
    script.logLine('stopped');
    notifyListeners();
  }

  Future<void> restart(ScriptRun script) async {
    await stop(script);
    await run(script);
  }

  Future<void> stopAll() async {
    for (final s in List<ScriptRun>.from(scripts)) {
      await stop(s);
    }
  }

  /// "Stop" runs the project's stop.sh and also force-stops the start process
  /// if it is somehow still alive.
  Future<void> stopProject() async {
    final stopScript = standardScript('Stop');
    if (stopScript != null) {
      await run(stopScript);
    }
    final start = standardScript('Run');
    if (start != null && start.running) {
      await stop(start);
    }
  }

  int? pidOf(ScriptRun script) => _procs[script.name]?.pid;

  // ------------------------------------------------------------- bootstrap

  /// Injected one-shot asker (the already-running opencode server). Set by the
  /// AppController so the bootstrap never spawns an extra process / random port.
  Future<String> Function(String prompt)? asker;

  /// Asks the already-running opencode server (HTTP API: create a session, post
  /// the prompt, read the text reply, delete the session) for the Run / Stop /
  /// Migration commands, writes them as real `.sh` scripts in the project root,
  /// and caches the commands permanently in the VibeStudio database.
  Future<void> bootstrap({
    required String context,
    Map<String, String> envVars = const {},
  }) async {
    if (bootstrapping) return;
    final dir = projectDir;
    if (dir == null || dir.isEmpty) return;
    final ask = asker;
    if (ask == null) {
      bootstrapError = 'opencode server is not running';
      notifyListeners();
      return;
    }
    bootstrapping = true;
    bootstrapError = null;
    bootstrapLog = '';
    notifyListeners();

    final prompt = '''
Analyze this project and figure out three commands:
1. "Run": the command to start the app for local development.
2. "Stop": the command to stop the running app (kill the server by port/pid if there is no npm script).
3. "Migration": the command to run the database migrations (skip/empty if none).

BEFORE answering, explore the WHOLE project — do not assume from a single file:
- List the full project tree (every folder and file) and read the top-level config files (package.json, pyproject.toml, requirements.txt, go.mod, docker-compose.yml, .env.example, README).
- Identify ALL parts of the stack: the backend server (framework, entry point, port), any frontend, and the database (ORM, schema files, migration folders, seed scripts).
- For "Migration", read the actual schema/migrations (e.g. prisma/schema.prisma, migrations/, alembic, etc.) so the command is correct.

Only after you have seen the whole project, reply with the commands.

Do NOT install dependencies. Use the environment variables of the server as-is.
Read the project memory (footprint) below first.

Environment / project context:
$context

Reply with ONLY a JSON object, exactly in this shape (no markdown, no extra text):
{"Run": "command", "Stop": "command", "Migration": "command"}
If a command does not apply, use an empty string.
''';

    try {
      final reply = await ask(prompt);
      _appendBootstrap(reply);
      final parsed = _parseBootstrapJson(reply);
      if (parsed.isEmpty) {
        bootstrapError = 'could not parse the AI commands from the reply: '
            '${reply.length > 300 ? reply.substring(0, 300) : reply}';
      } else {
        for (final name in fileNames.keys) {
          final cmd = parsed[name];
          if (cmd != null && cmd.trim().isNotEmpty) {
            await _writeScriptFile(dir, fileNames[name]!, cmd);
          }
        }
        await store.setCommands(dir, parsed);
      }
    } catch (e) {
      bootstrapError = 'failed to bootstrap: $e';
    }

    refreshFromStore();
    bootstrapping = false;
    notifyListeners();
  }

  /// Writes (or overwrites) a standard script in the project root.
  Future<void> _writeScriptFile(String dir, String fname, String command) async {
    final f = File('$dir${Platform.pathSeparator}$fname');
    final content = '#!/usr/bin/env bash\n'
        'set -e\n'
        '\n'
        '$command\n';
    await f.writeAsString(content, flush: true);
    try {
      await Process.run('chmod', ['+x', f.path]);
    } catch (_) {}
  }

  Map<String, String> _parseBootstrapJson(String reply) {
    final raw = reply.trim();
    if (raw.isEmpty) return {};
    // Try the whole reply first (cleanest case).
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
    // Fallback: strip a markdown code fence, then grab the last {...} block.
    var cleaned = raw;
    if (cleaned.startsWith('```')) {
      final first = cleaned.indexOf('\n');
      if (first >= 0) cleaned = cleaned.substring(first + 1);
      final last = cleaned.lastIndexOf('```');
      if (last >= 0) cleaned = cleaned.substring(0, last);
      cleaned = cleaned.trim();
      try {
        final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    final start = raw.lastIndexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return {};
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1))
          as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  void _appendBootstrap(String line) {
    bootstrapLog += '$line\n';
    if (bootstrapLog.length > 20000) {
      bootstrapLog = bootstrapLog.substring(bootstrapLog.length - 20000);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final proc in _procs.values) {
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _procs.clear();
    super.dispose();
  }
}
