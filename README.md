# Vibe Studio

A **team of AI agents** that works through a **shared todo list** together. You
write the todos; the agents claim them, work autonomously on your code, mark
them done, and pick up the next ones — all in parallel. Built as a **VS Code
extension**: VS Code provides the editor, Vibe Studio provides the
orchestration, the scripts (start/stop) panel, and a ThunderClient-style API
tester.

## How it works

- The extension starts a headless **`opencode serve`** inside your workspace
  folder.
- A shared ledger file **`vibestudio.json`** in the project root holds the
  todo list. Both the app and the agents read/write it, so the state is always
  visible and durable.
- Each agent is a persistent opencode **session**. An orchestrator tick
  assigns unclaimed todos to idle agents, one at a time; agents mark tasks
  done with a `DONE:` summary, split oversized work into sub-todos, and report
  back to the main AI.
- The **main / manager AI** can run as a real **`freebuff`** process in a
  VS Code terminal (free, no API key) — worker summaries and todo updates are
  typed straight into its prompt.
- The **Scripts** tab runs/restarts/stops `start.sh`, `stop.sh`,
  `migration.sh` (or any manual command) with live output, and can ask the AI
  to write those scripts once.
- The **API** tab is a ThunderClient-style tester: method, URL, headers, body,
  send, pretty-printed response — then report the result to the main AI so
  failures become new todos.

## Features

- Multi-agent orchestration: spawn any number of agents; they work in
  parallel on separate todos.
- Shared, human-editable todo ledger (`vibestudio.json`).
- Stall detection: agents that run long get a nudge; past the timeout their
  task is requeued so the team isn't blocked.
- Auto team: unassigned todos are picked up by up to 3 auto-managed workers,
  retired again when the queue drains.
- Run / Stop / Migration `.sh` script management with the AI bootstrap.
- ThunderClient-style API tester with report-to-main-AI.
- Main AI on FreeBuff: missions and reports are typed into a real `freebuff`
  TUI in an integrated terminal.

## Requirements

- [opencode](https://opencode.ai) CLI on PATH (logged in with a model
  provider, or an OpenAI-compatible endpoint such as a FreeBuff proxy).
- `freebuff` CLI if you want the manager AI to run on FreeBuff.

## Run (development)

```bash
cd extension
npm install
npm run compile     # tsc -> dist/
npm test            # compile + node:test unit tests
```

Open the folder in VS Code and press **F5** (extension host). Open a workspace
folder and the extension starts the opencode server automatically; open the
panel with the **`Vibe Studio: Open AI Team panel`** command.

## Commands

| Command | What it does |
| --- | --- |
| `Vibe Studio: Open AI Team panel` | Opens the side panel (Team / Todos / Scripts / API) |
| `Vibe Studio: Start opencode server` | Starts `opencode serve` in the workspace |
| `Vibe Studio: Stop opencode server` | Stops it |
| `Vibe Studio: Open FreeBuff in a terminal` | Launches `freebuff` in an integrated terminal |

## Package

```bash
cd extension
npm install -g @vscode/vsce
vsce package
```

## Tests

- `ledger` — vibestudio.json load/save/seed/update.
- `prompts` — system/task/verify/stall prompt content per role.
- `orchestrator` — the agent state machine (claim → work → complete on idle,
  summaries to main AI, stall requeue) against a fake opencode server.
- `opencode` — the HTTP client against a stub `opencode serve` API.
- `apiTester` / `scripts` — request sending + pretty-printing and the
  bootstrap-JSON parser.

> The original Flutter desktop app was removed when the product moved into
> this extension; it lives on in git history for reference.
