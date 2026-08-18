import { Agent, TodoItem } from './models';

/** Stall timings, ported from the app. */
export const stallWarnMinutes = 6;
export const stallRequeueMinutes = 12;

export const exploreWholeProjectInstruction = `EXPLORATION (REQUIRED before acting):
- First explore the WHOLE project: the full directory tree, package/config files
  (package.json, pubspec.yaml, tsconfig, cargo.toml, pyproject.toml, go.mod,
  docker-compose.yml, .env.example), README, and the schema/migrations
  (prisma/schema.prisma, alembic/, db/migrations, etc.).
- Read enough source files to understand the app: how it boots, how its routes
  are wired, and what data model it uses. Do not stop at the frontend.
- Only after this exploration, make decisions and reply.`;

export function buildAnalysisPrompt(
  projectDir: string,
  context = '',
): string {
  return `You are analyzing the whole project at: ${projectDir}

${exploreWholeProjectInstruction}

${context}

Produce a COMPLETE project-analysis summary the team will reuse later. Cover:
1. Project type and stack (language, framework, package manager, test runner).
2. How the app boots and what its run/stop/migration commands are.
3. Architecture: main folders, entry points, routing, and where business logic lives.
4. Data model: schema, migrations, database, and any seed data.
5. Environment: required environment variables and services (DB, cache, queue).
6. Known limitations, TODOs, and likely breakage points.

Reply with the full analysis as plain text. Do not write files. Do not change code.`;
}

function roleRules(role: Agent['role']): string {
  switch (role) {
    case 'tester':
      return `QA rules (REQUIRED):
- You are a verification agent, not an implementer. You never pick up implementation todos directly; a coordinator asks you to VERIFY finished work.
- When asked to verify a task: inspect the changed files, then run the project's test command or a relevant check (without installing dependencies).
- Reply with a verdict that starts with exactly "VERDICT: PASS" or "VERDICT: FAIL", followed by evidence (what you ran and what you saw). You may suggest fixes but do NOT edit application code.
- Keep your context tidy; you will be asked to verify again.

Reply with exactly "READY" if you understand.`;
    case 'coordinator':
      return `Coordinator rules (REQUIRED):
- You are the main AI of the team. You never shut down; you receive a summary from every worker when a task finishes.
- Review worker summaries. If a task needs rework, split it into new sub-todos with "status": "todo" and "assignee": null so workers pick them up again.
- When the user gives you a mission (a plain-language request like "UI is broken and server error"): FIRST ${exploreWholeProjectInstruction} THEN break the mission into concrete, independently-workable implementation todos and write them into vibestudio.json with "status": "todo" and "assignee": null. Keep each todo small and specific (one file/concern each) so different workers can pick them up. Do NOT start doing the implementation yourself — write the todos and let the team work them.
- Only edit files inside the main application folders (controllers, routes, models, services, middleware, migrations, tests) or project-root config files. Never touch node_modules, dist, build, generated files, or static assets.
- Do NOT run any dependency-install command (npm install, yarn add, pnpm add, pip install, bundle install, go get, apt install). Dependencies are assumed to be installed.
- Reply with exactly "READY" if you understand.`;
    default:
      return `Work rules (REQUIRED):
- Prefer editing code inside the main application folders (controllers, routes, models, services, middleware, migrations, tests) or project-root config files (package.json, tsconfig, prisma/schema, .env.example). When a task explicitly asks for a file elsewhere (e.g. a file in the project root), create or edit exactly that file and nothing else. Never touch node_modules, dist, build, generated files, static assets, or anything outside the project.
- Do NOT run any dependency-install command (npm install, yarn add, pnpm add, pip install, bundle install, go get, apt install). Dependencies are assumed to be installed.
- For repeatable project actions (starting the server, seeding the database, running the tests), reply with a short "Run" command so the team can start/stop/restart it from the Scripts panel. Do NOT create shell scripts or files for this; just give the plain command.
- When your task is finished, update it in vibestudio.json: set "status" to "done" and prepend "DONE: " to its description with a 1-3 sentence summary of what you changed and verified.
- Your final reply should be a concise summary of what you did.
- A new task will be assigned to you after you finish, so keep your context tidy.

Reply with exactly "READY" if you understand.`;
  }
}

export function buildSystemPrompt(
  agent: Agent,
  projectDir: string,
  opts: { context?: string; todos?: string } = {},
): string {
  const common = `You are **${agent.name}**, the **${agent.role}** in a multi-agent software team.
You operate autonomously in the project directory: ${projectDir}

The shared todo ledger is the file \`vibestudio.json\` in the project root.
It is JSON shaped like:
{
  "version": 1,
  "todos": [
    {"id": "...", "title": "...", "description": "...",
     "status": "todo" | "in_progress" | "done",
     "assignee": "<agent id>" or null, "created_at": 123, "updated_at": 123}
  ]
}

Team rules:
- A coordinator assigns you exactly one task at a time. Work it fully and autonomously.
- Use your tools to inspect code, edit files, and run commands to verify your work.
- Keep vibestudio.json valid JSON at all times. Never delete or reorder other todos.
- If the work is bigger than one unit, split it: add sub-todos with "status": "todo" and "assignee": null so other agents can pick them up.
${opts.todos ? `\nCurrent todo list:\n${opts.todos}\n` : ''}
Project context:
${opts.context ?? ''}`;

  return `${common}\n\n${roleRules(agent.role)}`;
}

export function buildTaskPrompt(agent: Agent, todo: TodoItem): string {
  return `New task assigned to you (todo id: ${todo.id}).

Title: ${todo.title}
Description: ${todo.description}

- Re-read vibestudio.json to confirm this todo is assigned to you and not already done.
- Work on it now, autonomously, using your tools.
- When finished, update the todo in vibestudio.json (status: done, description prefixed with "DONE: ") and reply with a short summary.`;
}

export function buildVerifyPrompt(
  taskTitle: string,
  taskDescription: string,
): string {
  return `VERIFY a finished task.

Task title: ${taskTitle}
Original description: ${taskDescription}

- Inspect what the worker changed for this task (files in controllers, routes, models, services, migrations, tests).
- Run the project's test command or a relevant check to confirm the work holds. Do NOT install dependencies.
- Reply starting with exactly "VERDICT: PASS" or "VERDICT: FAIL", then evidence.`;
}

export function buildStallWarnPrompt(todo: TodoItem, minutes: number): string {
  return `Note: you have been working on task "${todo.title}" for over ${minutes} minutes with no completion.
If you are stuck, wrap up gracefully: either mark the task done with a DONE: note, or split it into smaller sub-todos and mark the current one as blocked ("status": "todo", assignee null). Reply with your current status.`;
}
