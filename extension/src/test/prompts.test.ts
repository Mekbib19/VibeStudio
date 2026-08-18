import * as assert from 'node:assert';
import { test } from 'node:test';

import { Agent } from '../models';
import {
  buildStallWarnPrompt,
  buildSystemPrompt,
  buildTaskPrompt,
  buildVerifyPrompt,
} from '../prompts';

function agent(over: Partial<Agent> = {}): Agent {
  return {
    id: 'a1',
    name: 'Architect',
    role: 'engineer',
    isMain: false,
    runsInTerminal: false,
    autoManaged: false,
    sessionId: null,
    status: 'idle',
    currentTask: null,
    currentTaskId: null,
    taskStartedAt: null,
    lastStallWarnAt: null,
    lastError: null,
    log: [],
    tasksCompleted: 0,
    ...over,
  };
}

test('engineer system prompt includes the ledger rules and work rules', () => {
  const p = buildSystemPrompt(agent(), '/proj', { todos: '- [t1] (todo) assigned to unassigned: thing' });
  assert.match(p, /vibestudio\.json/);
  assert.match(p, /Work rules \(REQUIRED\)/);
  assert.match(p, /Do NOT run any dependency-install command/);
  assert.match(p, /Current todo list:\n- \[t1\]/);
});

test('coordinator gets coordinator rules, not work rules', () => {
  const p = buildSystemPrompt(
    agent({ role: 'coordinator', name: 'Manager' }),
    '/proj',
  );
  assert.match(p, /Coordinator rules \(REQUIRED\)/);
  assert.doesNotMatch(p, /Work rules \(REQUIRED\)/);
});

test('tester gets QA rules', () => {
  const p = buildSystemPrompt(agent({ role: 'tester' }), '/proj');
  assert.match(p, /QA rules \(REQUIRED\)/);
  assert.match(p, /VERDICT: PASS/);
});

test('task prompt names the todo and demands the ledger update', () => {
  const p = buildTaskPrompt(agent(), {
    id: 'x1',
    title: 'Fix login',
    description: 'Broken',
    status: 'todo',
    assignee: 'a1',
    createdAt: 1,
    updatedAt: 1,
  });
  assert.match(p, /todo id: x1/);
  assert.match(p, /Fix login/);
  assert.match(p, /Re-read vibestudio\.json/);
});

test('verify prompt wants a VERDICT line', () => {
  const p = buildVerifyPrompt('Fix login', 'Broken');
  assert.match(p, /VERDICT: PASS/);
});

test('stall warn mentions the task and how long', () => {
  const p = buildStallWarnPrompt(
    {
      id: 'x1',
      title: 'Fix login',
      description: '',
      status: 'in_progress',
      assignee: 'a1',
      createdAt: 1,
      updatedAt: 1,
    },
    9,
  );
  assert.match(p, /9 minutes/);
  assert.match(p, /Fix login/);
});
