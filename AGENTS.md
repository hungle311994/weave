# Weave — guide for coding agents

Weave is a local-first macOS app and CLI that coordinates AI coding agents (planner → implementer → self-review → verify → reviewer). This file is the source of truth for how to work in this repository; `CLAUDE.md` imports it. Read `README.md` for the product and security model.

## Toolchain

- The SDK is pinned with FVM (`.fvmrc`: Flutter 3.47.6, Dart 3.13.5). **Always prefix commands with `fvm`** (`fvm dart …`, `fvm flutter …`); never use a global `dart`/`flutter`.
- The repo is a Dart pub workspace (`pubspec.yaml` → `apps/*`, `packages/*`). Run `fvm flutter pub get` once at the root.
- Do not add Node, Python or other runtimes as project dependencies. Prettier is run ad hoc through `npx --yes prettier@3`.

## Layout and dependency direction

| Package                   | Depends on (internal)                | Purpose                                                                              |
| ------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------ |
| `packages/weave_core`     | —                                    | Workflow task model and state machine.                                               |
| `packages/weave_security` | —                                    | Sandbox modes, approval policy, Git command classification, scope, secret redaction. |
| `packages/weave_agents`   | core, security                       | Provider-neutral agent contracts; agents and MCP servers as data; process execution. |
| `packages/weave_git`      | security                             | Read-only status/diff; approval-gated commit.                                        |
| `packages/weave_storage`  | core, security                       | Task, artifact and event-log storage outside the repository.                         |
| `packages/weave_workflow` | agents, core, git, security, storage | Orchestrator, prompts, verification, settings, shared services.                      |
| `apps/weave_cli`          | workflow and below                   | `weave` CLI.                                                                         |
| `apps/weave_desktop`      | workflow and below                   | Flutter macOS app — see `apps/weave_desktop/AGENTS.md`.                              |

- Keep this direction: lower packages never import higher ones. Packages are pure Dart; only `apps/weave_desktop` uses Flutter.
- Each package exposes its API through `lib/<package>.dart` and keeps implementation in `lib/src/`. Test doubles live in a separate library (e.g. `package:weave_agents/testing.dart`).

## Code style (enforced)

- `dart format` with `page_width: 390` and `trailing_commas: preserve` (set in every `analysis_options.yaml`). A trailing comma after the last argument forces one-argument-per-line; use it to split long calls by hand.
- `always_specify_types: true`: write the type on every variable, field, loop variable and closure parameter, and give generic constructors and literals explicit type arguments (`<String, Object?>{}`, `List<String>.unmodifiable(…)`). Never use `var`, untyped `final`, or `dynamic`.
- New packages must copy the `formatter` block and the `always_specify_types` rule into their `analysis_options.yaml`.
- Markdown, JSON and YAML use the root `.prettierrc` (`printWidth: 390`): `npx --yes prettier@3 --write <files>` on the files you changed.
- Match the surrounding code: public APIs get `///` doc comments; inline comments only explain non-obvious reasons.

## Architecture rules

- **Provider-neutral agents.** Agents are data (`AgentDefinition`: executable, per-sandbox arguments, placeholders, output format) run by one `CommandAgentAdapter`. Codex and Claude Code are only presets. Never branch on a specific agent ID or name outside the preset factories and their output parsers; new provider behaviour goes into definition data or a new output format. Workflow, CLI and desktop code refer to agents by ID only.
- **Never write into the user's repository.** Plans, handoffs, state and logs live under `~/Library/Application Support/Weave` (or `WEAVE_HOME`). Never create `.agents` or similar folders in a repository Weave works on.
- **No shell.** Start every child process with an executable and an argument list (`Process.start(executable, arguments)`); never `sh -c` or `runInShell`. Remove inherited `GIT_*` variables. Git reads use `--no-optional-locks`.
- **Secrets.** Pass agent output, artifacts and logs through the secret redactor. MCP tokens are written as `${VAR}` and read from the environment at launch — Weave stores no credentials. Diffs may go to the reviewer but are never logged.
- **Guards stay independent of agents:** read-only roles fail the workflow if the working tree changes; implementers may only leave uncommitted edits; commits need explicit approval of the exact file list; push is not supported.

## Testing

- Every change ships with tests in the package it touches. Run, from the package folder:
  - pure Dart packages and `apps/weave_cli`: `fvm dart test`
  - `apps/weave_desktop`: `fvm flutter test --no-pub`
- Run `fvm dart analyze` at the root and fix every issue (including infos) before finishing.
- When a change crosses packages, also run the tests of every package that depends on the changed one.

## Working agreement

- Work in small, reviewable steps; state the goal before changing code, and report the verification results (format, analyze, tests) honestly — including failures.
- Never commit, push, or rewrite history unless the user asks.
- Commit messages have a title and a body:
  - **Title**: `<Type>: <short summary>` in English, ≤ 72 characters, where `<Type>` is exactly one of `Update` (change to existing behaviour, logic or UI), `Fix` (bug fix), `Feat` (new feature), `Refactor` (restructuring with no behaviour change).
  - **Body** (after a blank line): what changed and why; when one commit holds several changes, list each as a `- ` bullet.
  - **No `Co-Authored-By` or other AI attribution lines** in commit messages or PR descriptions.
- Only edit files inside this repository.

## Supporting files

These live under `.claude/` so Claude Code loads them automatically, but they are plain Markdown — any agent should read the relevant one before working in that area.

- **Rules** (`.claude/rules/`, loaded for matching paths): `dart-style.md` (all Dart), `packages.md` (packages and CLI), `desktop-ui.md` (desktop `lib/`), `testing.md` (all tests), `docs-and-config.md` (Markdown, YAML, JSON).
- **Skills** (`.claude/skills/<name>/SKILL.md`, invoked as `/<name>`):
  - `verify-step` — format changed files, analyze, run affected tests, report.
  - `new-component` — add a design-system component with tests.
  - `new-feature` — scaffold a clean-architecture desktop feature.
  - `add-icon` — add an icon or brand mark through the generator.
  - `design-spec` — look up exact values in the Figma design or its JSON export.
  - `check-copy` — audit UI text against the product truth.
  - `check-provider-neutral` — audit for agent-specific branching.
- **Agent** (`.claude/agents/design-reviewer.md`): read-only review of UI code against the design and rules.
- **Settings** (`.claude/settings.json`, shared): allows the routine `fvm`/Prettier commands, asks before commits, pushes and new dependencies, and runs `.claude/hooks/format-edited-file.sh` after every edit to format Dart, Markdown, JSON and YAML files. Personal overrides go in `.claude/settings.local.json`.
