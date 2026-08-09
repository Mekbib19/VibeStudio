# Vibe Studio

A desktop code editor where a **team of AI agents** works through a **shared todo list**
together. You write the todos; the agents claim them, work autonomously on your code,
mark them done, and pick up the next ones — all in parallel.

Built with **Flutter** (Linux desktop) and **opencode's headless server**
(`opencode serve`).

## How it works

- You open a project folder. Vibe Studio starts a headless `opencode serve` inside it.
- A shared ledger file `vibestudio.json` in the project root holds the todo list.
  Both the app and the agents read/write it, so the state is always visible and durable.
- Each agent is a persistent opencode **session** (it keeps its own context across tasks).
- An **orchestrator** (a timer inside the app) watches the ledger and assigns unclaimed
  todos to idle agents, one task at a time. Agents mark tasks done in the ledger with a
  `DONE:` summary, split oversized work into sub-todos (assignee `null`), and report back.
- The app live-streams each agent's output, shows task status, and auto-refreshes the
  file tree and editor as agents modify files.

## Features

- Multi-agent orchestration: spawn any number of agents (3 is the sweet spot), they
  work in parallel on separate todos.
- Shared, human-editable todo ledger (`vibestudio.json`).
- Stall detection: agents that run long get a nudge; past the timeout their task is
  requeued so the team isn't blocked.
- Built-in syntax-highlighting code editor (view/edit + save; Ctrl+S), with live reload
  when agents change files on disk.
- File tree, agent cards with streaming output, and a system log.
- **Agent Terminal**: a real interactive shell (PTY) embedded in the app, rooted at the
  project folder. Type anything there — `opencode serve --port 4066`, `freebuff`
  (FreeBuff opens as its interactive TUI inside the panel), or any other command —
  and use the `▶ opencode serve` / `▶ freebuff` quick buttons with your own port.

## Agent Terminal

The **⌨ terminal button** in the toolbar toggles the embedded terminal at the bottom.

- It is a full PTY (bash) running in your project folder — full-screen TUIs like
  `freebuff` and `opencode` render correctly.
- **Set the port**: type the port into the small field (defaults to your settings
  port) and hit **`▶ opencode serve`** to start `opencode serve --port <port>`.
- **`▶ freebuff`** launches the FreeBuff CLI interactively — no API key needed, it
  opens exactly like typing `freebuff` in a real terminal.
- `^C` sends Ctrl+C, `Clear` wipes the screen, `Replay` restarts/exit the shell.

The shell starts automatically when you open a project (or on the welcome screen it
starts in your home folder).

## Requirements

- Flutter (Linux desktop toolchain enabled)
- [opencode](https://opencode.ai) CLI on PATH. Either:
  - logged in with a model provider (default "opencode built-in" mode), or
  - an OpenAI-compatible endpoint such as a FreeBuff proxy (see below).

## Connecting FreeBuff (or any OpenAI-compatible provider)

The **⚙️ Settings** button in the toolbar lets you point the agents at any
OpenAI-compatible endpoint instead of opencode's built-in auth.

1. Run an OpenAI-compatible proxy locally (FreeBuff's CLI is interactive-only, so
   route it through a proxy such as `freebuff2api`, default `http://127.0.0.1:8080/v1`).
2. Open **Settings** → set AI backend to **OpenAI-compatible (FreeBuff…)**.
3. Fill in:
   - **Provider ID** — an opencode provider id, e.g. `freebuff`.
   - **Base URL** — your proxy, e.g. `http://127.0.0.1:8080/v1`.
   - **API key** — optional; sent as a `Bearer` token.
   - **Model ID** — e.g. `deepseek-v4-flash`.
4. Optionally set a fixed **Server port** for `opencode serve` (empty = automatic).
5. **Save** — the server restarts with the new settings.

Vibe Studio registers the provider as an `@ai-sdk/openai-compatible` provider via
`OPENCODE_CONFIG_CONTENT`, and sends `{modelID, providerID}` on every message so the
custom model is used. Settings are persisted to `~/.vibestudio/settings.json`.

## Run

```bash
flutter pub get
flutter run -d linux
```

Debug/build:

```bash
flutter build linux --release
# binary: build/linux/x64/release/bundle/vibe_studio
```

## Usage

1. **Open Project** → pick a folder.
2. A first todo ("explore the project") is seeded automatically.
3. Add more todos (top of the Todo List panel, `+`).
4. **Add Agent** → name it (e.g. `Architect`, `Tester`, `Refactorer`). Repeat for more.
5. Watch the team work: todos flip to *in progress* with the agent's id, then *done*.
6. Stop individual agents or **Stop All** anytime; their in-flight tasks are requeued.

Tip: all agents share the same folder and ledger, so they can pick up each other's
sub-todos. Give agents distinct roles via the prompt in
`lib/services/orchestrator.dart`.

## Ledger format

```json
{
  "version": 1,
  "todos": [
    {
      "id": "…",
      "title": "…",
      "description": "…",
      "status": "todo",
      "assignee": null,
      "created_at": 0,
      "updated_at": 0
    }
  ]
}
```

## Tests

- `test/home_smoke_test.dart` — UI renders (no network).
- `test/server_config_test.dart` — settings model JSON + provider config generation.
- `test/agent_workflow_test.dart` — full end-to-end: starts a real `opencode serve`,
  spawns two agents, verifies they work three todos in parallel and mark them done.
  A second test routes an agent through a local OpenAI-compatible stub to verify the
  custom-provider settings. Requires a live model provider for the first test;
  both run fine under `flutter test` (timeouts are set per-test).
- `integration_test/terminal_test.dart` — runs the app on the Linux device and verifies
  the embedded terminal starts a bash shell, renders `freebuff`, and runs
  `opencode serve --port <port>` without crashing:
  `flutter test integration_test/terminal_test.dart -d linux`
