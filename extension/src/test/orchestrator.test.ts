import * as assert from 'node:assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { test } from 'node:test';

import { Ledger } from '../ledger';
import { TodoItem } from '../models';
import { OpenCodeClient } from '../opencode';
import { AppState, pickNextTodo } from '../state';

/** Fake opencode server that records messages and lets tests emit idle. */
class FakeServer extends OpenCodeClient {
  sessions = new Map<string, string[]>();
  sent: Array<{ sessionId: string; text: string }> = [];
  nextSession = 0;

  override get isRunning(): boolean {
    return this.state === 'running';
  }

  override async createSession(title: string): Promise<string> {
    const id = `s-${++this.nextSession}`;
    this.sessions.set(id, []);
    return id;
  }

  override async sendMessage(opts: {
    sessionId: string;
    text: string;
  }): Promise<void> {
    this.sessions.get(opts.sessionId)?.push(opts.text);
    this.sent.push({ sessionId: opts.sessionId, text: opts.text });
    // The READY turn (system prompt) completes immediately: emit idle so the
    // handshake resolves without waiting for the real model.
    if (opts.text.includes('You are **')) {
      this.emitIdle(opts.sessionId);
    }
  }

  override async deleteSession(sessionId: string): Promise<void> {
    this.sessions.delete(sessionId);
  }

  /** Simulates the opencode server finishing the session's turn. */
  emitIdle(sessionId: string): void {
    this.emit('event', {
      type: 'session.status',
      properties: { sessionID: sessionId, status: { type: 'idle' } },
    } as never);
  }
}

function tmpProject(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'vibe-orch-'));
}

/** Wires server events into the state machine, like extension.ts does. */
function wire(state: AppState, server: FakeServer): void {
  server.on('event', (e) => state.onServerEvent(e as never));
}

function todo(id: string, title: string, createdAt: number): TodoItem {
  return {
    id,
    title,
    description: '',
    status: 'todo',
    assignee: null,
    createdAt,
    updatedAt: createdAt,
  };
}

test('pickNextTodo returns the oldest unassigned todo', () => {
  const ledger = {
    todos: [
      todo('b', 'B', 20),
      todo('a', 'A', 10),
      { ...todo('c', 'C', 30), status: 'in_progress' as const },
      { ...todo('d', 'D', 40), status: 'done' as const },
    ],
  };
  const next = pickNextTodo(ledger);
  assert.equal(next?.id, 'a');
});

test('worker claims a todo, works it, and completes on idle', async () => {
  const dir = tmpProject();
  const ledger = new Ledger(dir);
  ledger.update((l) => l.todos.push(todo('t1', 'Fix the bug', 1)));

  const server = new FakeServer();
  server.state = 'running';
  const state = new AppState({ server, ledger });
  wire(state, server);
  state.projectDir = dir;
  state.autoTeam = false;

  await state.addAgent({ name: 'E1', role: 'engineer' });
  const agent = state.agents[0];
  assert.equal(agent.status, 'idle');

  await state.tick();

  assert.equal(agent.status, 'busy');
  assert.equal(agent.currentTaskId, 't1');
  const claimed = ledger.load().todos.find((t) => t.id === 't1');
  assert.equal(claimed?.status, 'in_progress');
  assert.equal(claimed?.assignee, agent.id);
  assert.ok(agent.sessionId);
  assert.ok(
    server.sent.some((m) => m.sessionId === agent.sessionId && /New task assigned/.test(m.text)),
  );

  // The server finishes the turn: idle → the orchestrator notices completion
  // and resets the worker for its next job.
  await state.handleSessionStatus(agent.sessionId!, 'idle');
  assert.equal(agent.status, 'idle');
  assert.equal(agent.tasksCompleted, 1);
  assert.equal(agent.currentTaskId, null);
  assert.equal(agent.currentTask, null);

  // The agent itself marks the todo done in the ledger (as its prompt
  // instructs); the orchestrator picks up the change on the next tick.
  ledger.update((l) => {
    const i = l.todos.findIndex((t) => t.id === 't1');
    l.todos[i] = { ...l.todos[i], status: 'done' };
  });
  await state.tick();
  assert.equal(state.todoItems.find((t) => t.id === 't1')?.status, 'done');

  fs.rmSync(dir, { recursive: true, force: true });
});

test('worker summary is forwarded to the main AI', async () => {
  const dir = tmpProject();
  const ledger = new Ledger(dir);
  ledger.update((l) => l.todos.push(todo('t1', 'Fix the bug', 1)));

  const server = new FakeServer();
  server.state = 'running';
  const state = new AppState({ server, ledger });
  wire(state, server);
  state.projectDir = dir;
  state.autoTeam = false;

  await state.addAgent({ name: 'Manager', role: 'coordinator', isMain: true });
  const main = state.mainAgent!;
  await state.addAgent({ name: 'E1', role: 'engineer' });
  const worker = state.agents[1];

  await state.tick();
  await state.handleSessionStatus(worker.sessionId!, 'idle');

  assert.equal(main.sessionId, 's-1');
  const summaryMsg = server.sent.find(
    (m) => m.sessionId === main.sessionId && /Task complete — summary from E1/.test(m.text),
  );
  assert.ok(summaryMsg, 'main AI did not receive the worker summary');
  assert.match(summaryMsg!.text, /Task: Fix the bug/);

  fs.rmSync(dir, { recursive: true, force: true });
});

test('stalled tasks are requeued after the stall timeout', async () => {
  const dir = tmpProject();
  const ledger = new Ledger(dir);
  ledger.update((l) => l.todos.push(todo('t1', 'Slow task', 1)));

  const server = new FakeServer();
  server.state = 'running';
  const state = new AppState({ server, ledger });
  wire(state, server);
  state.projectDir = dir;
  state.autoTeam = false;

  await state.addAgent({ name: 'E1', role: 'engineer' });
  const agent = state.agents[0];
  await state.tick();
  assert.equal(agent.status, 'busy');

  // Pretend the task has been running for 13 minutes.
  agent.taskStartedAt = Date.now() - 13 * 60_000;
  await state.tick();

  assert.equal(agent.status, 'idle');
  assert.equal(agent.currentTaskId, null);
  assert.equal(ledger.load().todos.find((t) => t.id === 't1')?.status, 'todo');
  assert.equal(ledger.load().todos.find((t) => t.id === 't1')?.assignee, null);

  fs.rmSync(dir, { recursive: true, force: true });
});
