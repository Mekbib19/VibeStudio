import { spawn, ChildProcess } from 'child_process';
import { EventEmitter } from 'events';

import { ServerConfig, opencodeConfigContent, messageModel } from './config';

export type ServerState = 'stopped' | 'starting' | 'running' | 'error';

export interface ServerEvent {
  type: string;
  properties: Record<string, unknown>;
}

/** Talks to a headless `opencode serve` process over its HTTP API: create
 *  sessions, send messages, listen to SSE events, one-shot asks. Ported from
 *  the Vibe Studio app's ServerService. */
export class OpenCodeClient extends EventEmitter {
  state: ServerState = 'stopped';
  errorMessage: string | null = null;
  port = 0;

  private proc: ChildProcess | null = null;
  private stopping = false;
  private config: ServerConfig | null = null;
  private eventStreamActive = false;

  get isRunning(): boolean {
    return this.state === 'running';
  }

  baseUrl(): string {
    return `http://127.0.0.1:${this.port}`;
  }

  async start(opts: {
    projectDir: string;
    config?: ServerConfig;
    environment?: Record<string, string>;
    overridePort?: number;
  }): Promise<void> {
    await this.stop();
    this.stopping = false;
    this.state = 'starting';
    this.config = opts.config ?? null;

    this.port =
      opts.overridePort ??
      (opts.config && opts.config.port > 0
        ? opts.config.port
        : 4100 + (Date.now() % 800));

    const env: Record<string, string> = {
      ...process.env as Record<string, string>,
      OPENCODE_DEBUG: 'false',
      ...(opts.environment ?? {}),
    };
    const cfgContent = this.config ? opencodeConfigContent(this.config) : null;
    if (cfgContent) env.OPENCODE_CONFIG_CONTENT = cfgContent;

    const proc = spawn('opencode', ['serve', '--port', `${this.port}`], {
      cwd: opts.projectDir,
      env,
    });
    this.proc = proc;

    proc.on('exit', (code) => {
      if (this.stopping) return;
      if (this.state !== 'error') {
        this.state = 'error';
        this.errorMessage = `opencode server exited (code ${code})`;
      }
      this.emit('event', { type: 'server.exit', properties: { code } } as ServerEvent);
    });
    proc.stderr?.on('data', (chunk: Buffer) => {
      this.emit('event', {
        type: 'server.stderr',
        properties: { text: chunk.toString('utf8') },
      } as ServerEvent);
    });

    await this.waitUntilReady(45_000);
    void this.streamEvents();

    this.state = 'running';
    this.errorMessage = null;
    this.emit('event', { type: 'server.ready', properties: { port: this.port } } as ServerEvent);
  }

  private async waitUntilReady(timeoutMs: number): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (this.proc?.exitCode !== null && this.proc?.exitCode !== undefined) {
        throw new Error(
          `opencode server failed to start (exit code ${this.proc.exitCode})`,
        );
      }
      try {
        const res = await fetch(`${this.baseUrl()}/session`, {
          signal: AbortSignal.timeout(2000),
        });
        if (res.status === 200) return;
      } catch {
        // not ready yet
      }
      await sleep(500);
    }
    throw new Error('opencode server did not become ready in time');
  }

  /** Streams the SSE /event endpoint and reconnects when it drops. */
  private async streamEvents(): Promise<void> {
    if (this.eventStreamActive) return;
    this.eventStreamActive = true;
    while (!this.stopping) {
      try {
        const res = await fetch(`${this.baseUrl()}/event`);
        if (res.status !== 200 || !res.body) {
          await sleep(2000);
          continue;
        }
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          let idx: number;
          while ((idx = buffer.indexOf('\n\n')) >= 0) {
            const chunk = buffer.slice(0, idx);
            buffer = buffer.slice(idx + 2);
            const line = chunk
              .split('\n')
              .find((l) => l.startsWith('data:'))
              ?.slice(5)
              .trim();
            if (line) this.tryParseEvent(line);
          }
        }
      } catch {
        // stream dropped; retry
      }
      await sleep(1500);
    }
    this.eventStreamActive = false;
  }

  private tryParseEvent(raw: string): void {
    try {
      const json = JSON.parse(raw) as { type: string; properties?: Record<string, unknown> };
      this.emit('event', {
        type: json.type ?? 'unknown',
        properties: json.properties ?? {},
      } as ServerEvent);
    } catch {
      // incomplete / invalid chunk
    }
  }

  async createSession(title: string): Promise<string> {
    const res = await fetch(`${this.baseUrl()}/session`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ title }),
    });
    if (res.status !== 200) {
      throw new Error(`createSession failed: ${await res.text()}`);
    }
    const json = (await res.json()) as { id: string };
    return json.id;
  }

  async sendMessage(opts: {
    sessionId: string;
    text: string;
    model?: Record<string, string> | null;
  }): Promise<void> {
    const body: Record<string, unknown> = {
      parts: [{ type: 'text', text: opts.text }],
    };
    const resolved = opts.model !== undefined ? opts.model : this.config ? messageModel(this.config) : null;
    if (resolved) body.model = resolved;
    const res = await fetch(`${this.baseUrl()}/session/${opts.sessionId}/message`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (res.status !== 200) {
      throw new Error(`sendMessage failed (${res.status}): ${await res.text()}`);
    }
  }

  async deleteSession(sessionId: string): Promise<void> {
    try {
      await fetch(`${this.baseUrl()}/session/${sessionId}`, {
        method: 'DELETE',
        headers: { 'content-type': 'application/json' },
        body: '{}',
      });
    } catch {
      // ignore
    }
  }

  /** One-shot ask to the already-running server: create a session, post the
   *  prompt, read the text reply, and delete the session. */
  async askOnce(prompt: string, title = 'vibe-studio ask'): Promise<string> {
    if (this.state !== 'running') throw new Error('opencode server is not running');
    const sessionId = await this.createSession(title);
    try {
      const res = await fetch(`${this.baseUrl()}/session/${sessionId}/message`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          parts: [{ type: 'text', text: prompt }],
        }),
      });
      if (res.status !== 200) {
        throw new Error(`askOnce failed (${res.status}): ${await res.text()}`);
      }
      const data = (await res.json()) as { parts?: Array<{ type?: string; text?: string }> };
      const text = (data.parts ?? [])
        .filter((p) => p.type === 'text' && p.text)
        .map((p) => p.text)
        .join('\n')
        .trim();
      if (!text) throw new Error('no text reply from opencode');
      return text;
    } finally {
      await this.deleteSession(sessionId);
    }
  }

  async stop(): Promise<void> {
    this.stopping = true;
    const proc = this.proc;
    this.proc = null;
    if (proc) {
      proc.kill('SIGTERM');
      await new Promise<void>((resolve) => {
        const t = setTimeout(() => {
          try {
            proc.kill('SIGKILL');
          } catch {
            /* already gone */
          }
          resolve();
        }, 4000);
        proc.once('exit', () => {
          clearTimeout(t);
          resolve();
        });
      });
    }
    if (this.state !== 'error') this.state = 'stopped';
    this.stopping = false;
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
