/** Shared data models for the extension. No VS Code imports here so these
 *  are unit-testable in plain Node. */

export type TodoStatus = 'todo' | 'in_progress' | 'done';

export interface TodoItem {
  id: string;
  title: string;
  description: string;
  status: TodoStatus;
  assignee: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface TodoLedger {
  version: number;
  todos: TodoItem[];
}

export type AgentRole = 'engineer' | 'tester' | 'coordinator';
export type AgentStatus = 'stopped' | 'starting' | 'idle' | 'busy' | 'error';

export interface AgentLogEntry {
  time: number;
  text: string;
  isError: boolean;
}

export interface Agent {
  id: string;
  name: string;
  role: AgentRole;
  isMain: boolean;
  /** Runs as a `freebuff` TUI in a VS Code terminal instead of an opencode
   *  session. Only meaningful for the main agent. */
  runsInTerminal: boolean;
  autoManaged: boolean;
  sessionId: string | null;
  status: AgentStatus;
  currentTask: string | null;
  currentTaskId: string | null;
  taskStartedAt: number | null;
  lastStallWarnAt: number | null;
  lastError: string | null;
  log: AgentLogEntry[];
  tasksCompleted: number;
}

export interface ScriptRun {
  name: string;
  command: string;
  isStandard: boolean;
  running: boolean;
  exitCode: number | null;
  lastError: string | null;
  logs: string[];
  pid: number | null;
}

export interface ApiRequestSpec {
  method: string;
  url: string;
  headers: Record<string, string>;
  body: string;
}

export interface ApiRequestResult {
  method: string;
  url: string;
  statusCode: number | null;
  headers: Record<string, string>;
  body: string;
  elapsedMs: number | null;
  error: string | null;
}

export function newAgentId(counter: number): string {
  return `agent-${counter}`;
}

export function emptyLedger(): TodoLedger {
  return { version: 1, todos: [] };
}

/** Appends a line to the agent's log, trimming it to the last 500 entries. */
export function agentLogLine(
  agent: Agent,
  text: string,
  isError = false,
): void {
  agent.log.push({ time: Date.now(), text, isError });
  if (agent.log.length > 500) {
    agent.log.splice(0, agent.log.length - 500);
  }
}

/** True while the agent is actively working (or spinning up a session). */
export function agentBusy(agent: Agent): boolean {
  return agent.status === 'busy' || agent.status === 'starting';
}
