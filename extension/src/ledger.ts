import * as fs from 'fs';
import * as path from 'path';

import { emptyLedger, TodoItem, TodoLedger } from './models';

/** The shared ledger file both the extension and the agents read/write.
 *  Same JSON format as the original Vibe Studio app, so an existing project
 *  ledger keeps working. All mutations go through [update] so concurrent
 *  agent edits are preserved (read-modify-write + atomic rename). */
export class Ledger {
  constructor(public projectDir: string | null = null) {}

  filePath(): string | null {
    return this.projectDir ? path.join(this.projectDir, 'vibestudio.json') : null;
  }

  load(): TodoLedger {
    const p = this.filePath();
    if (!p || !fs.existsSync(p)) return emptyLedger();
    try {
      const raw = JSON.parse(fs.readFileSync(p, 'utf8')) as TodoLedger;
      return { version: raw.version ?? 1, todos: raw.todos ?? [] };
    } catch {
      return emptyLedger();
    }
  }

  save(ledger: TodoLedger): void {
    const p = this.filePath();
    if (!p) return;
    const tmp = `${p}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(ledger, null, 2), 'utf8');
    fs.renameSync(tmp, p);
  }

  /** Loads the current on-disk ledger, applies [mutate], writes back atomically. */
  update(mutate: (ledger: TodoLedger) => void): TodoLedger {
    const ledger = this.load();
    mutate(ledger);
    this.save(ledger);
    return ledger;
  }

  seedIfMissing(): void {
    const p = this.filePath();
    if (!p || fs.existsSync(p)) return;
    this.save({
      version: 1,
      todos: [
        {
          id: newId(),
          title: 'Explore the project and summarize its structure',
          description:
            'Read the codebase, understand the stack, and leave a short ' +
            'summary of the project in the description (prefix DONE:).',
          status: 'todo',
          assignee: null,
          createdAt: Date.now(),
          updatedAt: Date.now(),
        },
      ],
    });
  }

  static newId(): string {
    return `${Date.now().toString(16)}-${(Date.now() % 100000).toString(16)}`;
  }
}

export const newId = Ledger.newId;

export function todoStatusWire(status: TodoItem['status']): string {
  return status;
}
