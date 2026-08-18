# Vibe Studio — AI Team

A team of AI agents that works your **shared todo list**, manages your
project's **start/stop scripts**, and **tests your API** — all inside VS Code.

Open the **Vibe Studio** icon in the activity bar (left sidebar) to open the
panel with the **AI Team / Todos / Scripts / API** tabs.

## Features

- **AI Team** — spawn any number of agents (or let the auto team spawn up to
  3 workers when todos are queued). Each agent is a persistent
  [opencode](https://opencode.ai) session; an orchestrator assigns unclaimed
  todos, agents mark them done with a `DONE:` summary, and reports flow back
  to your **main / manager AI**.
- **Main AI on FreeBuff** — the manager can run as a real **`freebuff`**
  process in a VS Code terminal (free, no API key): missions and worker
  reports are typed straight into its prompt.
- **Todos** — a shared, human-editable ledger file (`vibestudio.json`) in
  your project root that both you and the agents read/write.
- **Scripts** — run/restart/stop `start.sh`, `stop.sh`, `migration.sh` (or
  any manual command) with live output, and let the AI write those scripts
  once ("bootstrap").
- **API** — ThunderClient-style tester: method, URL, headers, body, send,
  pretty-printed response — then report the result to the main AI so
  failures become new todos.
- **Stall detection** — long-running agents get a nudge; past the timeout
  their task is requeued so the team isn't blocked.

## Requirements

- [opencode](https://opencode.ai) CLI on `PATH` (logged in with a model
  provider, or an OpenAI-compatible endpoint such as a FreeBuff proxy).
- `freebuff` CLI if you want the manager AI to run on FreeBuff.

## Install the extension

### Option 1 — from a `.vsix` file (no marketplace needed)

1. Build it (or download a released `.vsix`):
   ```bash
   cd extension
   npm install
   npx --yes @vscode/vsce package
   ```
   This produces `vibe-studio-0.2.0.vsix`.
2. In VS Code: open the **Extensions** view (`Ctrl+Shift+X`), click the
   **⋯** menu at the top right → **Install from VSIX...** → pick the file.
   Or from a terminal:
   ```bash
   code --install-extension vibe-studio-0.2.0.vsix
   ```
3. Reload the window (**Developer: Reload Window**). The **Vibe Studio**
   icon appears in the activity bar.

### Option 2 — publish to the VS Code Marketplace

Then it shows up in the Extensions view search like any other extension:

1. Create a publisher at
   [marketplace.visualstudio.com/manage](https://marketplace.visualstudio.com/manage)
   (sign in with a Microsoft/Azure account, pick a publisher ID such as
   `vibestudio`).
2. Create a Personal Access Token with the **Marketplace → Manage** scope at
   [dev.azure.com](https://dev.azure.com), and log in:
   ```bash
   npx --yes @vscode/vsce login <publisher-id>
   ```
3. Publish (the README, icon, and metadata are already configured):
   ```bash
   cd extension
   npx --yes @vscode/vsce publish
   ```
4. The extension is then listed in the marketplace and installable from
   the Extensions view by searching **"Vibe Studio"**. After the first
   publish, update releases with `vsce publish patch/minor/major`.

## Commands

| Command | What it does |
| --- | --- |
| `Vibe Studio: Open AI Team panel` | Opens the sidebar panel (Team / Todos / Scripts / API) |
| `Vibe Studio: Start opencode server` | Starts `opencode serve` in the workspace |
| `Vibe Studio: Stop opencode server` | Stops it |
| `Vibe Studio: Open FreeBuff in a terminal` | Launches `freebuff` in an integrated terminal |

## Settings

Search **"Vibe Studio"** in VS Code Settings (`Ctrl+,`): `autoTeam`,
`port`, `mode` (builtin / custom OpenAI-compatible endpoint), `providerID`,
`baseURL`, `apiKey`, `modelID`. Changes restart the server automatically.
(Legacy settings in `~/.vibestudio/settings.json` are still honored as
fallbacks.)

## Development

```bash
cd extension
npm install
npm run compile     # tsc -> dist/
npm test            # compile + node:test unit tests
```

Press **F5** in VS Code (extension host) to try it out.

## Tests

- `ledger` — vibestudio.json load/save/seed/update.
- `prompts` — system/task/verify/stall prompt content per role.
- `orchestrator` — the agent state machine (claim → work → complete on idle,
  summaries to main AI, stall requeue) against a fake opencode server.
- `opencode` — the HTTP client against a stub `opencode serve` API.
- `apiTester` / `scripts` — request sending + pretty-printing and the
  bootstrap-JSON parser.
