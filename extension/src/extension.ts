import * as vscode from 'vscode';

import { AiProviderMode, ServerConfig, loadSettings } from './config';
import { AppState } from './state';
import { PanelHost } from './panel';

let state: AppState | null = null;
let panelHost: PanelHost | null = null;
let managerTerminal: vscode.Terminal | null = null;

/** VS Code settings win over the legacy ~/.vibestudio/settings.json file. */
function configFromSettings(): ServerConfig {
  const file = loadSettings();
  const cfg = vscode.workspace.getConfiguration('vibeStudio');
  return {
    port: cfg.get<number>('port', file.port),
    mode: cfg.get<string>('mode', file.mode) as AiProviderMode,
    providerID: cfg.get<string>('providerID', file.providerID),
    baseURL: cfg.get<string>('baseURL', file.baseURL),
    apiKey: cfg.get<string>('apiKey', file.apiKey),
    modelID: cfg.get<string>('modelID', file.modelID),
  };
}

export function activate(context: vscode.ExtensionContext): void {
  state = new AppState();
  state.serverConfig = configFromSettings();
  state.autoTeam = vscode.workspace
    .getConfiguration('vibeStudio')
    .get<boolean>('autoTeam', true);

  panelHost = new PanelHost(state, context.extensionPath);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(PanelHost.viewType, panelHost, {
      webviewOptions: { retainContextWhenHidden: true },
    }),
  );

  // Route the opencode server's events into the state machine (session
  // busy/idle, message parts, server exit, ...).
  state.server.on('event', (e) => state!.onServerEvent(e));

  // The freebuff manager AI runs in a real VS Code terminal; this writer
  // types commands/missions into it (creating the terminal on first use).
  state.terminalWriter = (text: string) => {
    if (!managerTerminal) {
      managerTerminal = vscode.window.createTerminal({
        name: 'Vibe Studio — Manager (freebuff)',
        cwd: state?.projectDir ?? undefined,
      });
    }
    managerTerminal.show();
    managerTerminal.sendText(text);
  };
  vscode.window.onDidCloseTerminal((t) => {
    if (managerTerminal === t) managerTerminal = null;
  });

  const openPanel = vscode.commands.registerCommand('vibeStudio.openPanel', () => {
    panelHost?.reveal();
  });
  const startServer = vscode.commands.registerCommand(
    'vibeStudio.startServer',
    () => state?.startServer(),
  );
  const stopServer = vscode.commands.registerCommand(
    'vibeStudio.stopServer',
    () => {
      void state?.server.stop();
    },
  );
  const openFreebuff = vscode.commands.registerCommand(
    'vibeStudio.openFreebuff',
    () => {
      state?.terminalWriter?.('freebuff');
    },
  );
  context.subscriptions.push(openPanel, startServer, stopServer, openFreebuff);

  // Settings changed → restart the server with the new config.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (!e.affectsConfiguration('vibeStudio')) return;
      if (state) {
        state.autoTeam = vscode.workspace
          .getConfiguration('vibeStudio')
          .get<boolean>('autoTeam', true);
      }
      void state?.applySettings(configFromSettings());
    }),
  );

  // Open the first workspace folder on activation.
  const folders = vscode.workspace.workspaceFolders;
  if (folders && folders.length > 0) {
    void state.openProjectAt(folders[0].uri.fsPath);
  }

  // Follow workspace folder changes (open/close/reopen).
  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders((e) => {
      const f = e.added.length > 0 ? e.added[0] : null;
      if (f) {
        void state?.openProjectAt(f.uri.fsPath);
      } else if (e.removed.length > 0) {
        void state?.closeProject();
      }
    }),
  );
}

export function deactivate(): void {
  managerTerminal?.dispose();
  managerTerminal = null;
  panelHost?.dispose();
  panelHost = null;
  state?.dispose();
  state = null;
}
