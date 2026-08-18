import * as assert from 'node:assert';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { test } from 'node:test';

import { Ledger } from '../ledger';
import { TodoItem } from '../models';

test('ledger seeds a first todo when the file is missing', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vibe-ledger-'));
  const ledger = new Ledger(dir);
  ledger.seedIfMissing();
  const loaded = ledger.load();
  assert.equal(loaded.todos.length, 1);
  assert.equal(loaded.todos[0].status, 'todo');
  fs.rmSync(dir, { recursive: true, force: true });
});

test('ledger update preserves unrelated todos', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vibe-ledger-'));
  const ledger = new Ledger(dir);
  const a: TodoItem = {
    id: 'a',
    title: 'A',
    description: '',
    status: 'todo',
    assignee: null,
    createdAt: 1,
    updatedAt: 1,
  };
  const b: TodoItem = { ...a, id: 'b', title: 'B' };
  ledger.update((l) => l.todos.push(a, b));
  ledger.update((l) => {
    const i = l.todos.findIndex((t) => t.id === 'a');
    l.todos[i] = { ...l.todos[i], status: 'done' };
  });
  const loaded = ledger.load();
  assert.equal(loaded.todos.length, 2);
  assert.equal(loaded.todos.find((t) => t.id === 'a')?.status, 'done');
  assert.equal(loaded.todos.find((t) => t.id === 'b')?.status, 'todo');
  fs.rmSync(dir, { recursive: true, force: true });
});
