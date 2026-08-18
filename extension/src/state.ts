import { EventEmitter } from 'events';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import { ApiTester, buildBackendReport } from './apiTester';
import {
  ServerConfig,
  loadSettings,
  saveSettings,
} from './config';
import { Ledger, newId } from './ledger';
import {
  Agent,
  AgentRole,
  agentBusy,
  agentLogLine,
  TodoItem,
  TodoStatus,
} from './models';
import { OpenCodeClient, ServerEvent } from './opencode';
import {
  buildAnalysisPrompt,
  buildStallWarnPrompt,
  buildSystemPrompt,
  buildTaskPrompt,
  stallRequeueMinutes,
  stallWarnMinutes,
} from './prompts';
import { ScriptsManager } from './scripts';

export interface SystemLogEntry {
  time: number;
  text: string;
  isError: boolean;
}

const TICK_MS = 2500;
const maxAutoWorkers = 3;

/** The heart of the extension: one shared opencode server, a team of agent
 *  sessions working the shared todo ledger, the scripts manager, and the API
 *  tester. VS Code-agnostic (no `vscode` import) so it is unit-testable;
 *  the extension wires it to panels and terminals. */
export class AppState extends EventEmitter {
  server: OpenCodeClient;
  ledger: Ledger;
  scripts: ScriptsManager;
  apiTester: ApiTester;

  constructor(opts: {
    server?: OpenCodeClient;
    ledger?: Ledger;
    scripts?: ScriptsManager;
    apiTester?: ApiTester;
  } = {}) {
    super();
    this.server = opts.server ?? new OpenCodeClient();
    this.ledger = opts.ledger ?? new Ledger();
    this.scripts = opts.scripts ?? new ScriptsManager();
    this.apiTester = opts.apiTester ?? new ApiTester();
  }

  serverConfig: ServerConfig = defaultConfig();
  projectDir: string | null = null;
  agents: Agent[] = [];
  systemLog: SystemLogEntry[] = [];
  autoTeam = true;

  /** Injected by the extension host: types text into the freebuff terminal
   *  for a terminal-based main AI. */
  terminalWriter: ((text: string) => void) | null = null;

  private ticker: NodeJS.Timeout | null = null;
  private agentCounter = 0;
  private ledgerSig = -1;
  private idleWaiters = new Map<string, () => void>();
  private todoPushTimer: NodeJS.Timeout | null = null;
  private disposed = false;
  private lastServerErrorLog = 0;

  get todoItems(): TodoItem[] {
    return this.ledger.load().todos;
  }

  get mainAgent(): Agent | null {
    return this.agents.find((a) => a.isMain) ?? null;
  }

  notify(): void {
    if (this.disposed) return;
    this.emit('changed');
  }

  logSystem(text: string, isError = false): void {
    if (this.disposed) return;
    this.systemLog.push({ time: Date.now(), text, isError });
    if (this.systemLog.length > 1000) {
      this.systemLog.splice(0, this.systemLog.length - 1000);
    }
    this.notify();
  }

  // ------------------------------------------------------------- lifecycle

  /** Called by the extension when the workspace opens (or changes). */
  async openProjectAt(dir: string): Promise<void> {
    await this.closeProject();
    this.projectDir = dir;
    this.ledger.projectDir = dir;
    this.ledger.seedIfMissing();
    this.scripts.setProjectDir(dir);
    await this.startServer();

    if (!this.isAnalyzed(dir)) {
      void this.analyzeProject(dir);
    }

    this.ticker = setInterval(() => {
      void this.tick();
    }, TICK_MS);
    this.notify();
  }

  async closeProject(): Promise<void> {
    if (this.ticker) clearInterval(this.ticker);
    this.ticker = null;
    this.cancelTodoPush();
    for (const agent of [...this.agents]) {
      await this.stopAgent(agent, false);
    }
    this.agents = [];
    this.agentCounter = 0;
    await this.server.stop();
    this.scripts.setProjectDir('');
    this.projectDir = null;
    this.notify();
  }

  async startServer(): Promise<void> {
    const dir = this.projectDir;
    if (!dir) return;
    try {
      await this.server.start({
        projectDir: dir,
        config: this.serverConfig,
        overridePort: this.serverConfig.port > 0 ? this.serverConfig.port : undefined,
      });
      this.logSystem(`Server ready on port ${this.server.port} for ${dir}`);
    } catch (e) {
      this.logSystem(`Failed to start server: ${e}`, true);
    }
  }

  async applySettings(config: ServerConfig): Promise<void> {
    const wasOpen = !!this.projectDir;
    const dir = this.projectDir;
    this.serverConfig = config;
    saveSettings(config);
    this.notify();
    if (wasOpen && dir) {
      this.logSystem('Restarting server with new settings…');
      await this.closeProject();
      await this.openProjectAt(dir);
    }
  }

  // ----------------------------------------------------------- project AI

  private analysisFile(): string {
    return path.join(os.homedir(), '.vibestudio', 'analysis.json');
  }

  private isAnalyzed(dir: string): boolean {
    try {
      const json = JSON.parse(fs.readFileSync(this.analysisFile(), 'utf8')) as Record<
        string,
        unknown
      >;
      return !!json[dir];
    } catch {
      return false;
    }
  }

  async analyzeProject(dir: string): Promise<void> {
    try {
      this.logSystem('Analyzing the whole project (first open)…');
      const summary = await this.server.askOnce(
        buildAnalysisPrompt(dir, this.agentContext()),
        'vibe-studio project analysis',
      );
      try {
        const file = this.analysisFile();
        fs.mkdirSync(path.dirname(file), { recursive: true });
        const json = fs.existsSync(file)
          ? (JSON.parse(fs.readFileSync(file, 'utf8')) as Record<string, unknown>)
          : {};
        json[dir] = summary;
        fs.writeFileSync(file, JSON.stringify(json, null, 2), 'utf8');
      } catch {
        // best effort
      }
      this.logSystem('Project analysis stored');
      this.notify();
    } catch (e) {
      this.logSystem(`Project analysis failed: ${e}`, true);
    }
  }

  private storedAnalysis(dir: string): string {
    try {
      const json = JSON.parse(fs.readFileSync(this.analysisFile(), 'utf8')) as Record<
        string,
        unknown
      >;
      return (json[dir] as string) ?? '';
    } catch {
      return '';
    }
  }

  agentContext(): string {
    const b: string[] = [];
    b.push(`Working directory: ${this.projectDir ?? '.'}`);
    const analysis = this.projectDir ? this.storedAnalysis(this.projectDir) : '';
    if (analysis) {
      b.push('');
      b.push('Stored project-analysis summary (produced on first open):');
      b.push(analysis);
    }
    return b.join('\n').trimEnd();
  }

  todosSnapshot(): string {
    const l = this.ledger.load();
    if (l.todos.length === 0) return '';
    const b: string[] = [];
    for (const t of l.todos) {
      const who = t.assignee ?? 'unassigned';
      b.push(
        `- [${t.id}] (${t.status}) assigned to ${who}: ${t.title}${t.description ? ` — ${t.description}` : ''}`,
      );
    }
    return b.join('\n').trimEnd();
  }

  // ----------------------------------------------------------------- agents

  async addAgent(opts: {
    name?: string;
    role?: AgentRole;
    isMain?: boolean;
    runsInTerminal?: boolean;
    autoManaged?: boolean;
  }): Promise<Agent> {
    this.agentCounter++;
    const agent: Agent = {
      id: `agent-${this.agentCounter}`,
      name: opts.name ?? `Agent ${this.agentCounter}`,
      role: opts.role ?? 'engineer',
      isMain: opts.isMain ?? false,
      runsInTerminal: opts.runsInTerminal ?? false,
      autoManaged: opts.autoManaged ?? false,
      sessionId: null,
      status: 'stopped',
      currentTask: null,
      currentTaskId: null,
      taskStartedAt: null,
      lastStallWarnAt: null,
      lastError: null,
      log: [],
      tasksCompleted: 0,
    };
    if (agent.isMain) {
      for (const a of this.agents) a.isMain = false;
    }
    this.agents.push(agent);
    this.notify();
    await this.startAgent(agent);
    return agent;
  }

  async startAgent(agent: Agent): Promise<void> {
    if (agent.isMain) {        if (agent.runsInTerminal) {
          agent.status = 'starting';
          agentLogLine(agent, 'launching freebuff in a terminal…');
          this.notify();
          if (this.terminalWriter) {
            this.terminalWriter('freebuff');
            agent.status = 'idle';
            agent.lastError = null;
            agentLogLine(
              agent,
              'freebuff running in the terminal — talk to your main AI there',
            );
            this.logSystem(
              `Main AI ${agent.name} launched as freebuff in a terminal`,
            );
          } else {
            agent.status = 'error';
            agent.lastError = 'no terminal available';
            agentLogLine(agent, 'failed to launch freebuff: no terminal', true);
          }
          this.notify();
          return;
        }
        if (!this.server.isRunning) {
          agent.status = 'error';
          agent.lastError = 'server not running';
          agentLogLine(agent, 'cannot start: server not running', true);
          this.notify();
          return;
        }
        agent.status = 'starting';
        agentLogLine(agent, 'creating session…');
        this.notify();
        try {
          agent.sessionId ??= await this.server.createSession(agent.name);
          await this.server.sendMessage({
            sessionId: agent.sessionId!,
            text: buildSystemPrompt(agent, this.projectDir ?? '.', {
              context: this.agentContext(),
              todos: this.todosSnapshot(),
            }),
          });
          agent.status = 'idle';
          agentLogLine(agent, 'READY — waiting for tasks');
          agent.lastError = null;
        } catch (e) {
          agent.status = 'error';
          agent.lastError = String(e);
          agentLogLine(agent, `start failed: ${e}`, true);
        }
        this.notify();
        return;
      }
      // Worker: no session yet — one is created per job (see ensureReady).
      agent.status = 'idle';
      agent.lastError = null;
      agentLogLine(agent, 'ready — creates a session per job');
      this.notify();
    }

  async stopAgent(agent: Agent, requeue = true): Promise<void> {
    if (agent.sessionId) {
      await this.server.deleteSession(agent.sessionId).catch(() => {});
      agent.sessionId = null;
    }
    if (requeue && agent.currentTaskId) {
      const taskId = agent.currentTaskId;
      this.ledger.update((l) => {
        for (const t of l.todos) {
          if (t.id === taskId && t.status === 'in_progress') {
            t.status = 'todo';
            t.assignee = null;
            t.updatedAt = Date.now();
          }
        }
      });
      this.reloadTodos();
    }
    agent.currentTask = null;
    agent.currentTaskId = null;
    agent.taskStartedAt = null;
    agent.lastStallWarnAt = null;
    agent.status = 'stopped';
    agentLogLine(agent, 'stopped');
    this.notify();
  }

  async stopAll(): Promise<void> {
    for (const agent of [...this.agents]) await this.stopAgent(agent);
  }

  /** Ensures the agent has a session with its system prompt and waits for the
   *  READY handshake so the task prompt's idle event is the one that counts
   *  as completion. */
  private async ensureReady(agent: Agent): Promise<boolean> {
    if (agent.sessionId) return true;
    let timer: NodeJS.Timeout | null = null;
    const sessionId = await this.server.createSession(agent.name).catch((e) => {
      agentLogLine(agent, `session failed: ${e}`, true);
      this.notify();
      return null;
    });
    if (!sessionId) return false;
    agent.sessionId = sessionId;
    const prompt = buildSystemPrompt(agent, this.projectDir ?? '.', {
      context: this.agentContext(),
      todos: this.todosSnapshot(),
    });
    const ready = new Promise<void>((resolve) => {
      this.idleWaiters.set(sessionId, resolve);
    });
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(
        () => reject(new Error('READY handshake timed out')),
        180_000,
      );
    });
    try {
      await this.server.sendMessage({ sessionId, text: prompt });
      await Promise.race([ready, timeout]);
      agent.lastError = null;
      agentLogLine(agent, 'READY — waiting for tasks');
      this.notify();
      return true;
    } catch (e) {
      if (agent.sessionId) {
        await this.server.deleteSession(agent.sessionId).catch(() => {});
      }
      agent.sessionId = null;
      agentLogLine(agent, `server failed: ${e}`, true);
      this.notify();
      return false;
    } finally {
      if (timer) clearTimeout(timer);
      this.idleWaiters.delete(sessionId);
    }
  }

  private async assignNext(agent: Agent): Promise<void> {
    if (agent.role === 'tester') return; // QA never picks up implementation todos
    const ledger = this.ledger.load();
    const next = pickNextTodo(ledger);
    if (!next) return;

    const claimed: TodoItem = {
      ...next,
      status: 'in_progress',
      assignee: agent.id,
      updatedAt: Date.now(),
    };
    this.ledger.update((l) => {
      const i = l.todos.findIndex((t) => t.id === next.id);
      if (i < 0 || l.todos[i].status !== 'todo') return;
      l.todos[i] = claimed;
    });

    agent.currentTask = next.title;
    agent.currentTaskId = next.id;
    agent.taskStartedAt = Date.now();
    agent.lastStallWarnAt = null;
    agent.status = 'starting';
    agentLogLine(agent, `assigned: "${next.title}"`);
    this.notify();

    const ok = await this.ensureReady(agent);
    if (!ok) {
      this.ledger.update((l) => {
        for (const t of l.todos) {
          if (t.id === next.id) {
            t.status = 'todo';
            t.assignee = null;
          }
        }
      });
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.status = 'error';
      this.notify();
      return;
    }

    agent.status = 'busy';
    this.notify();
    try {
      await this.server.sendMessage({
        sessionId: agent.sessionId!,
        text: buildTaskPrompt(agent, claimed),
      });
    } catch (e) {
      agent.status = 'error';
      agent.lastError = String(e);
      agentLogLine(agent, `send failed: ${e}`, true);
      this.ledger.update((l) => {
        for (const t of l.todos) {
          if (t.id === next.id) {
            t.status = 'todo';
            t.assignee = null;
          }
        }
      });
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.status = 'idle';
      this.notify();
    }
  }

  private async checkStall(agent: Agent): Promise<void> {
    const started = agent.taskStartedAt ?? 0;
    const elapsedMin = (Date.now() - started) / 60000;
    const taskId = agent.currentTaskId;

    if (elapsedMin >= stallRequeueMinutes) {
      this.ledger.update((l) => {
        for (const t of l.todos) {
          if (t.id === taskId) {
            t.status = 'todo';
            t.assignee = null;
          }
        }
      });
      agentLogLine(
        agent,
        `STALL: requeued "${agent.currentTask}" after ${elapsedMin.toFixed(0)} min`,
        true,
      );
      agent.currentTask = null;
      agent.currentTaskId = null;
      agent.taskStartedAt = null;
      agent.lastStallWarnAt = null;
      agent.status = 'idle';
      this.notify();
    } else if (elapsedMin >= stallWarnMinutes) {
      const lastWarn = agent.lastStallWarnAt ?? 0;
      if (Date.now() - lastWarn > stallWarnMinutes * 60000) {
        agent.lastStallWarnAt = Date.now();
        agentLogLine(
          agent,
          `nudging: "${agent.currentTask}" running ${elapsedMin.toFixed(0)} min`,
        );
        const todo = this.ledger
          .load()
          .todos.find((t) => t.id === agent.currentTaskId);
        if (todo && agent.sessionId) {
          try {
            await this.server.sendMessage({
              sessionId: agent.sessionId,
              text: buildStallWarnPrompt(todo, Math.round(elapsedMin)),
            });
          } catch {
            // ignore
          }
        }
        this.notify();
      }
    }
  }

  // ---------------------------------------------------------------- main AI

  /** Sends a plain-language mission to the main AI. For a terminal-based main
   *  it types the mission into the freebuff terminal; otherwise it posts to
   *  the main's opencode session. */
  async sendToMain(text: string): Promise<boolean> {
    const main = this.mainAgent;
    if (!main) return false;
    const t = text.trim();
    if (!t) return false;
    if (main.runsInTerminal) {
      if (!this.terminalWriter) return false;
      this.terminalWriter(flattenToLine(t));
      agentLogLine(main, `⇐ mission: ${t}`);
      this.notify();
      return true;
    }
    if (!main.sessionId || !this.server.isRunning) return false;
    try {
      await this.server.sendMessage({
        sessionId: main.sessionId,
        text:
          'MISSION from the user:\n' +
          t +
          '\n\n' +
          'Analyze the project and turn this into concrete todos in ' +
          'vibestudio.json (status "todo", assignee null) for the team. ' +
          'Workers will pick them up and report summaries back to you.',
      });
      agentLogLine(main, `⇐ mission: ${t}`);
      this.notify();
      return true;
    } catch (e) {
      this.logSystem(`Failed to send mission to main AI: ${e}`, true);
      return false;
    }
  }

  private pushTodosToMain(): void {
    const main = this.mainAgent;
    if (!main) return;
    if (main.runsInTerminal) {
      this.scheduleTodosToTerminalMain(main);
      return;
    }
    if (!main.sessionId) return;
    if (!this.server.isRunning || main.status !== 'idle') return;
    const snapshot = this.todosSnapshot();
    if (!snapshot) return;
    void this.sendTodosToMain(main, snapshot);
  }

  private scheduleTodosToTerminalMain(main: Agent): void {
    this.cancelTodoPush();
    this.todoPushTimer = setTimeout(() => {
      this.todoPushTimer = null;
      if (this.disposed || main.status === 'stopped') return;
      if (!this.terminalWriter) return;
      const snapshot = this.todosSnapshot();
      if (!snapshot) return;
      this.typeToMain(main, `UPDATED TODO LIST — ${snapshot}`);
    }, 3000);
  }

  private typeToMain(main: Agent, text: string): void {
    if (this.disposed || main.status === 'stopped') return;
    if (!this.terminalWriter) {
      this.logSystem(
        `Main AI ${main.name} runs in a terminal but no terminal is available — report not delivered`,
        true,
      );
      return;
    }
    let line = flattenToLine(text);
    if (line.length > 2000) line = line.slice(0, 2000);
    this.terminalWriter(line);
    agentLogLine(main, `⇐ ${line}`);
    this.notify();
  }

  private async sendTodosToMain(main: Agent, snapshot: string): Promise<void> {
    try {
      await this.server.sendMessage({
        sessionId: main.sessionId!,
        text:
          'UPDATED TODO LIST\n\n' +
          snapshot +
          '\n\n' +
          "This is the team's current work. Plan and assign as needed.",
      });
      agentLogLine(main, '⇐ updated todo list');
      this.notify();
    } catch (e) {
      this.logSystem(`Failed to send todo list to main AI: ${e}`, true);
    }
  }

  private summaryMessage(agent: Agent, task: string, summary: string): string {
    return (
      `Task complete — summary from ${agent.name} (${agent.role}).\n\n` +
      `Task: ${task || '(unknown)'}\n\n` +
      `Summary:\n${summary}\n\n` +
      '— Vibe Studio (automatic worker report)'
    );
  }

  // ------------------------------------------------------------- todo feed

  reloadTodos(): void {
    const fresh = this.ledger.load();
    const sig = computeSig(fresh);
    if (sig !== this.ledgerSig) {
      this.ledgerSig = sig;
      this.pushTodosToMain();
      this.notify();
    }
  }

  addTodo(title: string, description: string): void {
    const item: TodoItem = {
      id: newId(),
      title,
      description,
      status: 'todo',
      assignee: null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    this.ledger.update((l) => l.todos.push(item));
    this.reloadTodos();
  }

  updateTodo(item: TodoItem): void {
    this.ledger.update((l) => {
      const i = l.todos.findIndex((t) => t.id === item.id);
      if (i >= 0) l.todos[i] = item;
    });
    this.reloadTodos();
  }

  deleteTodo(id: string): void {
    this.ledger.update((l) => {
      l.todos = l.todos.filter((t) => t.id !== id);
    });
    this.reloadTodos();
  }

  // ------------------------------------------------------------- tick loop

  async tick(): Promise<void> {
    if (this.disposed) return;
    try {
      if (this.projectDir) {
        this.reloadTodos();
      }
      if (!this.projectDir) return;

      await this.autoScaleWorkers();
      for (const agent of [...this.agents]) {
        if (agent.role === 'tester') {
          if (agent.status === 'busy' && agent.currentTaskId) {
            await this.checkStall(agent);
          }
          continue;
        }
        if (agent.isMain) continue;
        if (agentBusy(agent) && agent.currentTaskId) {
          await this.checkStall(agent);
        } else if (!agent.currentTaskId && agent.status !== 'error') {
          await this.assignNext(agent);
        }
      }
    } catch (e) {
      this.logSystem(`tick error: ${e}`, true);
    }
  }

  private async autoScaleWorkers(): Promise<void> {
    if (!this.projectDir || !this.autoTeam) return;
    const pending = this.ledger
      .load()
      .todos.filter((t) => t.status === 'todo').length;

    const activeAuto = this.agents.filter(
      (a) =>
        a.autoManaged &&
        !a.isMain &&
        a.role === 'engineer' &&
        (a.status === 'idle' || a.status === 'busy' || a.status === 'starting'),
    ).length;

    if (pending > 0) {
      // Replace broken auto workers so they never hog a slot.
      for (const a of [...this.agents]) {
        if (
          a.autoManaged &&
          !a.isMain &&
          a.role === 'engineer' &&
          a.status === 'error'
        ) {
          await this.stopAgent(a, true);
          this.agents = this.agents.filter((x) => x !== a);
          this.logSystem(`Auto team: replaced broken worker ${a.name}`);
        }
      }
      const needed = pending < maxAutoWorkers ? pending : maxAutoWorkers;
      const toSpawn = needed - activeAuto;
      if (toSpawn <= 0) return;
      for (let i = 0; i < toSpawn; i++) {
        this.logSystem(
          `Auto team: ${pending} task(s) queued, spawning worker ${activeAuto + i + 1}/${maxAutoWorkers}`,
        );
        await this.addAgent({ role: 'engineer', autoManaged: true });
      }
    } else {
      // Queue drained: retire idle/broken/stopped auto workers.
      const retiring = this.agents.filter(
        (a) =>
          a.autoManaged &&
          !a.isMain &&
          a.role === 'engineer' &&
          (a.status === 'idle' || a.status === 'error' || a.status === 'stopped'),
      );
      for (const a of retiring) {
        await this.stopAgent(a, true);
        this.agents = this.agents.filter((x) => x !== a);
        this.logSystem(`Auto team: queue empty, retired worker ${a.name}`);
      }
    }
  }

  // --------------------------------------------------------- server events

  /** Handles a session.status event: busy → working; idle while busy with a
   *  task → task done; idle while starting → READY handshake done. */
  async handleSessionStatus(
    sessionId: string,
    status: string,
  ): Promise<void> {
    const agent = this.agents.find((a) => a.sessionId === sessionId);
    if (!agent) return;
    if (status === 'busy') {
      if (agent.status === 'idle') agent.status = 'busy';
      this.notify();
    } else if (status === 'idle') {
      this.idleWaiters.get(sessionId)?.();
      this.idleWaiters.delete(sessionId);
      if (agent.status === 'busy' && agent.currentTaskId) {
        agent.tasksCompleted++;
        agentLogLine(agent, `DONE: "${agent.currentTask}"`);
        await this.afterTaskDone(agent);
      } else if (agent.status !== 'starting') {
        agent.currentTask = null;
        agent.currentTaskId = null;
        agent.taskStartedAt = null;
        agent.lastStallWarnAt = null;
        agent.status = 'idle';
        this.notify();
      }
    }
  }

  onServerEvent(event: ServerEvent): void {
    if (this.disposed) return;
    switch (event.type) {
      case 'server.ready':
        this.logSystem(`Server ready (port ${event.properties['port']})`);
        break;
      case 'server.exit':
        if (this.server.state === 'error') {
          this.logSystem('Server exited unexpectedly', true);
        }
        break;
      case 'server.stderr': {
        const text = String(event.properties['text'] ?? '').trim();
        if (text) {
          const now = Date.now();
          if (now - this.lastServerErrorLog > 5000) {
            this.lastServerErrorLog = now;
            this.logSystem(`server: ${text}`);
          }
        }
        break;
      }
      case 'session.status': {
        const sid = String(event.properties['sessionID'] ?? '');
        const status = (event.properties['status'] as { type?: string } | null)
          ?.type;
        if (sid && status) void this.handleSessionStatus(sid, status);
        break;
      }
      case 'message.part.updated': {
        const sid = String(event.properties['sessionID'] ?? '');
        const agent = this.agents.find((a) => a.sessionId === sid);
        if (!agent) break;
        const text = (event.properties['text'] as string) ?? '';
        if (text.trim()) {
          agent.log.push({ time: Date.now(), text: text.trim(), isError: false });
          if (agent.log.length > 500) {
            agent.log.splice(0, agent.log.length - 500);
          }
          this.notify();
        }
        break;
      }
    }
  }

  /** Called when an agent marks a task done (session goes idle after work). */
  private async afterTaskDone(agent: Agent): Promise<void> {
    const task = agent.currentTask ?? '';
    const summary = this.agentSummary(agent);

    if (agent.isMain) return;

    const main = this.mainAgent;
    if (main && main.runsInTerminal) {
      this.typeToMain(main, this.summaryMessage(agent, task, summary));
    } else if (main && main.sessionId && this.server.isRunning) {
      try {
        await this.server.sendMessage({
          sessionId: main.sessionId,
          text: this.summaryMessage(agent, task, summary),
        });
        agentLogLine(main, `⇐ summary from ${agent.name}`);
        this.notify();
      } catch (e) {
        this.logSystem(`Failed to send summary to main AI: ${e}`, true);
      }
    }

    // Reset the worker for its next job.
    agent.currentTask = null;
    agent.currentTaskId = null;
    agent.taskStartedAt = null;
    agent.lastStallWarnAt = null;
    agent.status = 'idle';
    agentLogLine(agent, 'ready for next job');
    this.notify();
  }

  /** Reports an API tester result to the main AI. */
  async reportBackendResultToMain(
    method: string,
    url: string,
  ): Promise<void> {
    const result = this.apiTester.last;
    const main = this.mainAgent;
    if (!result || !main) return;
    const text = buildBackendReport(result, { tables: [] });
    if (main.runsInTerminal) {
      this.typeToMain(main, text);
      return;
    }
    if (!main.sessionId || !this.server.isRunning) return;
    try {
      await this.server.sendMessage({ sessionId: main.sessionId, text });
      agentLogLine(main, '⇐ backend tester report');
      this.notify();
    } catch (e) {
      this.logSystem(`Failed to send backend tester report: ${e}`, true);
    }
  }

  /** The worker's final reply (the tail of its log) is its summary. */
  agentSummary(agent: Agent): string {
    const texts = agent.log
      .filter((e) => !e.isError && e.text.trim())
      .map((e) => e.text.trim());
    const markers = ['READY', 'assigned:', 'DONE:', 'verify:'];
    const buf: string[] = [];
    for (const t of texts) {
      if (markers.some((m) => t.startsWith(m))) continue;
      buf.push(t);
    }
    let s = buf.join('\n').trim();
    if (s.length > 900) s = s.slice(s.length - 900);
    return s || '(no reply recorded)';
  }

  private cancelTodoPush(): void {
    if (this.todoPushTimer) clearTimeout(this.todoPushTimer);
    this.todoPushTimer = null;
  }

  dispose(): void {
    this.disposed = true;
    if (this.ticker) clearInterval(this.ticker);
    this.cancelTodoPush();
    void this.server.stop();
  }
}

function defaultConfig(): ServerConfig {
  return loadSettings();
}

/** Picks the next unassigned task, oldest first. */
export function pickNextTodo(ledger: { todos: TodoItem[] }): TodoItem | null {
  const pending = ledger.todos
    .filter((t) => t.status === 'todo')
    .sort((a, b) => a.createdAt - b.createdAt);
  return pending.length ? pending[0] : null;
}

function computeSig(ledger: { todos: TodoItem[] }): number {
  let h = 0;
  for (const t of ledger.todos) {
    h = h * 31 + hash(t.id);
    h = h * 31 + hash(t.status);
    h = h * 31 + hash(t.assignee ?? '');
    h = h * 31 + hash(t.title);
  }
  return h;
}

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) {
    h = (h * 31 + s.charCodeAt(i)) | 0;
  }
  return h;
}

function flattenToLine(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

export { flattenToLine };
