import { spawn, ChildProcess } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

import { ScriptRun } from './models';

/** Standard script file names in the project root. */
export const standardScriptFiles: Record<string, string> = {
  Run: 'start.sh',
  Stop: 'stop.sh',
  Migration: 'migration.sh',
};

/** Project run commands backed by real shell scripts in the project root:
 *  `start.sh`, `stop.sh`, `migration.sh`. Run executes `bash start.sh`, etc.
 *  The scripts are written once by the AI bootstrap. */
export class ScriptsManager {
  projectDir: string | null = null;
  scripts: ScriptRun[] = [];

  bootstrapNeeded = false;
  bootstrapping = false;
  bootstrapError: string | null = null;
  bootstrapLog = '';

  /** Injected one-shot asker (the already-running opencode server). */
  asker: ((prompt: string) => Promise<string>) | null = null;

  private procs = new Map<string, ChildProcess>();

  scriptFile(name: string): string | null {
    const fname = standardScriptFiles[name];
    if (!this.projectDir || !fname) return null;
    return path.join(this.projectDir, fname);
  }

  setProjectDir(dir: string): void {
    for (const s of [...this.scripts]) this.stop(s);
    this.scripts = [];
    this.projectDir = dir || null;
    this.bootstrapNeeded = false;
    this.bootstrapError = null;
    this.bootstrapLog = '';
    this.bootstrapping = false;
    if (this.projectDir) {
      this.bootstrapNeeded = this.needsBootstrap(this.projectDir);
      if (!this.bootstrapNeeded) this.loadStandardScripts();
    }
  }

  private needsBootstrap(dir: string): boolean {
    return !fs.existsSync(path.join(dir, 'start.sh'));
  }

  private loadStandardScripts(): void {
    if (!this.projectDir) return;
    for (const name of Object.keys(standardScriptFiles)) {
      const f = path.join(this.projectDir, standardScriptFiles[name]);
      if (fs.existsSync(f)) {
        this.scripts.push({
          name,
          command: `bash ${standardScriptFiles[name]}`,
          isStandard: true,
          running: false,
          exitCode: null,
          lastError: null,
          logs: [],
          pid: null,
        });
      }
    }
  }

  byName(name: string): ScriptRun | null {
    return this.scripts.find((s) => s.name === name) ?? null;
  }

  standardScript(name: string): ScriptRun | null {
    return this.byName(name);
  }

  addManual(name: string, command: string): ScriptRun {
    const script: ScriptRun = {
      name: name.trim() || `script-${this.scripts.length + 1}`,
      command: command.trim(),
      isStandard: false,
      running: false,
      exitCode: null,
      lastError: null,
      logs: [],
      pid: null,
    };
    this.scripts.push(script);
    return script;
  }

  removeManual(script: ScriptRun): void {
    this.stop(script);
    this.scripts = this.scripts.filter((s) => s !== script);
  }

  async run(script: ScriptRun): Promise<void> {
    if (!this.projectDir || script.running) return;
    const cmd = script.command.trim();
    if (!cmd) return;
    script.running = true;
    script.exitCode = null;
    script.lastError = null;
    logLine(script, `$ ${cmd}`);
    const proc = spawn('bash', ['-ic', cmd], {
      cwd: this.projectDir,
      env: process.env as Record<string, string>,
    });
    this.procs.set(script.name, proc);
    script.pid = proc.pid ?? null;
    proc.stdout?.on('data', (d: Buffer) => logLines(script, d.toString('utf8')));
    proc.stderr?.on('data', (d: Buffer) =>
      logLines(script, d.toString('utf8').split('\n').map((l) => `ERR: ${l}`).join('\n')),
    );
    proc.on('error', (e) => {
      script.running = false;
      script.lastError = String(e);
      logLine(script, `failed to start: ${e}`);
    });
    proc.on('exit', (code) => {
      script.running = false;
      script.exitCode = code;
      script.pid = null;
      logLine(script, code === 0 ? 'exited 0' : `exited ${code}`);
      this.procs.delete(script.name);
    });
  }

  async stop(script: ScriptRun): Promise<void> {
    const proc = this.procs.get(script.name);
    this.procs.delete(script.name);
    if (!proc) {
      script.running = false;
      return;
    }
    proc.kill('SIGTERM');
    await new Promise<void>((resolve) => {
      const t = setTimeout(() => {
        try {
          proc.kill('SIGKILL');
        } catch {
          /* gone */
        }
        resolve();
      }, 3000);
      proc.once('exit', () => {
        clearTimeout(t);
        resolve();
      });
    });
    script.running = false;
    script.pid = null;
    logLine(script, 'stopped');
  }

  async restart(script: ScriptRun): Promise<void> {
    await this.stop(script);
    await this.run(script);
  }

  async runOrRestart(script: ScriptRun): Promise<void> {
    if (script.running) await this.restart(script);
    else await this.run(script);
  }

  async stopAll(): Promise<void> {
    for (const s of [...this.scripts]) await this.stop(s);
  }

  async stopProject(): Promise<void> {
    const stop = this.standardScript('Stop');
    if (stop) await this.run(stop);
    const start = this.standardScript('Run');
    if (start && start.running) await this.stop(start);
  }

  /** Asks the already-running opencode server for the Run / Stop / Migration
   *  commands and writes them as real `.sh` scripts in the project root. */
  async bootstrap(context: string): Promise<void> {
    if (this.bootstrapping || !this.projectDir) return;
    const ask = this.asker;
    if (!ask) {
      this.bootstrapError = 'opencode server is not running';
      return;
    }
    this.bootstrapping = true;
    this.bootstrapError = null;
    this.bootstrapLog = '';

    const prompt = `Analyze this project and figure out three commands:
1. "Run": the command to start the app for local development.
2. "Stop": the command to stop the running app (kill the server by port/pid if there is no npm script).
3. "Migration": the command to run the database migrations (skip/empty if none).

BEFORE answering, explore the WHOLE project — do not assume from a single file:
- List the full project tree (every folder and file) and read the top-level config files (package.json, pyproject.toml, requirements.txt, go.mod, docker-compose.yml, .env.example, README).
- Identify ALL parts of the stack: the backend server (framework, entry point, port), any frontend, and the database (ORM, schema files, migration folders, seed scripts).
- For "Migration", read the actual schema/migrations (e.g. prisma/schema.prisma, migrations/, alembic, etc.) so the command is correct.

Only after you have seen the whole project, reply with the commands.
Do NOT install dependencies.
Environment / project context:
${context}

Reply with ONLY a JSON object, exactly in this shape (no markdown, no extra text):
{"Run": "command", "Stop": "command", "Migration": "command"}
If a command does not apply, use an empty string.`;

    try {
      const reply = await ask(prompt);
      this.bootstrapLog += `${reply}\n`;
      const parsed = parseBootstrapJson(reply);
      if (Object.keys(parsed).length === 0) {
        this.bootstrapError =
          'could not parse the AI commands from the reply: ' +
          (reply.length > 300 ? reply.slice(0, 300) : reply);
      } else {
        for (const name of Object.keys(standardScriptFiles)) {
          const cmd = parsed[name];
          if (cmd && cmd.trim()) {
            this.writeScriptFile(this.projectDir, standardScriptFiles[name], cmd);
          }
        }
      }
    } catch (e) {
      this.bootstrapError = `failed to bootstrap: ${e}`;
    }

    this.refresh();
    this.bootstrapping = false;
  }

  private writeScriptFile(dir: string, fname: string, command: string): void {
    const content =
      '#!/usr/bin/env bash\nset -e\n\n' + command + '\n';
    fs.writeFileSync(path.join(dir, fname), content, 'utf8');
    try {
      fs.chmodSync(path.join(dir, fname), 0o755);
    } catch {
      // best effort
    }
  }

  refresh(): void {
    this.scripts = [];
    if (this.projectDir) {
      this.bootstrapNeeded = this.needsBootstrap(this.projectDir);
      if (!this.bootstrapNeeded) this.loadStandardScripts();
    }
  }
}

function logLines(script: ScriptRun, text: string): void {
  for (const line of text.split('\n')) logLine(script, line);
}

function logLine(script: ScriptRun, line: string): void {
  for (const l of line.split('\n')) {
    script.logs.push(l);
  }
  if (script.logs.length > 1500) {
    script.logs.splice(0, script.logs.length - 1500);
  }
}

/** Parses the AI's bootstrap reply into a {Run, Stop, Migration} map. */
export function parseBootstrapJson(reply: string): Record<string, string> {
  const raw = reply.trim();
  if (!raw) return {};
  try {
    const decoded = JSON.parse(raw) as Record<string, unknown>;
    return mapToStrings(decoded);
  } catch {
    // fall through
  }
  let cleaned = raw;
  if (cleaned.startsWith('```')) {
    const first = cleaned.indexOf('\n');
    if (first >= 0) cleaned = cleaned.slice(first + 1);
    const last = cleaned.lastIndexOf('```');
    if (last >= 0) cleaned = cleaned.slice(0, last);
    cleaned = cleaned.trim();
    try {
      return mapToStrings(JSON.parse(cleaned) as Record<string, unknown>);
    } catch {
      // fall through
    }
  }
  const start = raw.lastIndexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return {};
  try {
    return mapToStrings(
      JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>,
    );
  } catch {
    return {};
  }
}

function mapToStrings(m: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(m)) out[k] = String(v);
  return out;
}
