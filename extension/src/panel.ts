import * as path from 'path';
import * as vscode from 'vscode';

import { Agent, ScriptRun, TodoItem } from './models';
import { AppState } from './state';

/** Serializable snapshot pushed to the webview on every change. */
export interface PanelState {
  projectDir: string | null;
  serverState: string;
  serverPort: number;
  agents: Agent[];
  todos: TodoItem[];
  scripts: ScriptRun[];
  scriptBootstrap: {
    needed: boolean;
    bootstrapping: boolean;
    error: string | null;
    log: string;
  };
  api: {
    sending: boolean;
    last: {
      statusLabel: string;
      success: boolean;
      body: string;
      error: string | null;
    } | null;
  };
  systemLog: Array<{ time: number; text: string; isError: boolean }>;
}

export function serializeState(state: AppState): PanelState {
  const apiLast = state.apiTester.last;
  return {
    projectDir: state.projectDir,
    serverState: state.server.state,
    serverPort: state.server.port,
    agents: state.agents,
    todos: state.todoItems,
    scripts: state.scripts.scripts,
    scriptBootstrap: {
      needed: state.scripts.bootstrapNeeded,
      bootstrapping: state.scripts.bootstrapping,
      error: state.scripts.bootstrapError,
      log: state.scripts.bootstrapLog.slice(-4000),
    },
    api: {
      sending: state.apiTester.sending,
      last: apiLast
        ? {
            statusLabel: apiLast.statusCode === null
              ? 'no response'
              : `${apiLast.statusCode} (${apiLast.elapsedMs ?? '?'}ms)`,
            success:
              apiLast.error === null &&
              apiLast.statusCode !== null &&
              apiLast.statusCode < 400,
            body: apiLast.body.slice(0, 20000),
            error: apiLast.error,
          }
        : null,
    },
    systemLog: state.systemLog.slice(-200),
  };
}

/** The ThunderClient-style sidebar panel (activity bar icon → Vibe Studio). */
export class PanelHost implements vscode.WebviewViewProvider {
  public static readonly viewType = 'vibeStudio.mainView';
  private view: vscode.WebviewView | null = null;
  private state: AppState;
  private extensionPath: string;

  constructor(state: AppState, extensionPath: string) {
    this.state = state;
    this.extensionPath = extensionPath;
    state.on('changed', () => this.push());
  }

  /** Focuses the sidebar view (opens the activity bar view if hidden). */
  reveal(): void {
    void vscode.commands.executeCommand(`${PanelHost.viewType}.focus`);
  }

  resolveWebviewView(webviewView: vscode.WebviewView): void {
    this.view = webviewView;
    webviewView.webview.options = { enableScripts: true };
    webviewView.webview.html = this.html(webviewView.webview);
    webviewView.webview.onDidReceiveMessage((msg) => void this.handle(msg));
    webviewView.onDidDispose(() => {
      if (this.view === webviewView) this.view = null;
    });
    this.push();
  }

  private push(): void {
    if (!this.view) return;
    void this.view.webview.postMessage({
      type: 'state',
      data: serializeState(this.state),
    });
  }

  private html(webview: vscode.Webview): string {
    const media = vscode.Uri.file(path.join(this.extensionPath, 'media'));
    const base = webview.asWebviewUri(media);
    return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="${base}/panel.css">
<title>Vibe Studio</title>
</head>
<body>
<div id="app"></div>
<script src="${base}/panel.js"></script>
</body>
</html>`;
  }

  private async handle(msg: {
    type: string;
    [k: string]: unknown;
  }): Promise<void> {
    const s = this.state;
    switch (msg.type) {
      case 'addTodo':
        s.addTodo(String(msg.title ?? ''), String(msg.description ?? ''));
        break;
      case 'deleteTodo':
        s.deleteTodo(String(msg.id));
        break;
      case 'toggleTodo': {
        const id = String(msg.id);
        const item = s.todoItems.find((t) => t.id === id);
        if (item) {
          s.updateTodo({
            ...item,
            status: item.status === 'done' ? 'todo' : 'done',
            updatedAt: Date.now(),
          });
        }
        break;
      }
      case 'addAgent':
        await s.addAgent({
          name: msg.name ? String(msg.name) : undefined,
          role: (msg.role as Agent['role']) ?? 'engineer',
          isMain: !!msg.isMain,
          runsInTerminal: !!msg.runsInTerminal,
        });
        break;
      case 'startAgent':
        {
          const a = s.agents.find((x) => x.id === msg.id);
          if (a) await s.startAgent(a);
        }
        break;
      case 'stopAgent':
        {
          const a = s.agents.find((x) => x.id === msg.id);
          if (a) await s.stopAgent(a);
        }
        break;
      case 'stopAll':
        await s.stopAll();
        break;
      case 'setMain':
        for (const a of s.agents) a.isMain = a.id === msg.id;
        s.notify();
        break;
      case 'sendMission':
        await s.sendToMain(String(msg.text ?? ''));
        break;
      case 'runScript': {
        const sc = s.scripts.byName(String(msg.name));
        if (sc) await s.scripts.runOrRestart(sc);
        s.notify();
        break;
      }
      case 'stopScript': {
        const sc = s.scripts.byName(String(msg.name));
        if (sc) await s.scripts.stop(sc);
        s.notify();
        break;
      }
      case 'addScript': {
        const sc = s.scripts.addManual(
          String(msg.name ?? ''),
          String(msg.command ?? ''),
        );
        s.notify();
        break;
      }
      case 'removeScript': {
        const sc = s.scripts.byName(String(msg.name));
        if (sc) {
          s.scripts.removeManual(sc);
          s.notify();
        }
        break;
      }
      case 'bootstrapScripts':
        await s.scripts.bootstrap(s.agentContext());
        s.notify();
        break;
      case 'apiSend': {
        const result = await s.apiTester.send({
          method: String(msg.method ?? 'GET'),
          url: String(msg.url ?? ''),
          headers: (msg.headers as Record<string, string>) ?? {},
          body: String(msg.body ?? ''),
        });
        void result;
        s.notify();
        break;
      }
      case 'apiClear':
        s.apiTester.clear();
        s.notify();
        break;
      case 'apiReport':
        await s.reportBackendResultToMain('', '');
        break;
      case 'serverStart':
        await s.startServer();
        break;
      case 'serverStop':
        await s.server.stop();
        s.notify();
        break;
      case 'openFreebuff':
        vscode.commands.executeCommand('vibeStudio.openFreebuff');
        break;
      case 'openSettings':
        vscode.commands.executeCommand(
          'workbench.action.openSettings',
          '@ext:vibestudio.vibe-studio',
        );
        break;
    }
  }

  dispose(): void {
    this.view = null;
  }
}
