# Weave

Weave is a local-first macOS app and CLI that coordinates AI coding agents from one request: a **planner** writes a plan, an **implementer** edits the code and reviews its own work, Weave runs your checks, and a **reviewer** approves the change or sends it back. Any agent can play any role — Codex plans and reviews while Claude Code implements, the other way round, one agent for everything, or a CLI you add yourself.

Weave never writes planning, handoff, or state files into your repository. Everything lives in `~/Library/Application Support/Weave` (or `WEAVE_HOME`).

## Workflow

```
request ─▶ plan ─▶ implement ─▶ self-review ─▶ verify ─▶ review ─┬─▶ completed ─▶ commit (after approval)
            (read-only)   (workspace-write)    (Weave runs  (read-only)    │
                                                your checks)               └─▶ changes requested ─▶ implement …
```

Fixed guards, independent of any agent:

- Planners and reviewers are read-only. If the working tree changes while they run (status, size, or modification time of any reported path), the workflow fails.
- Implementers may only make uncommitted edits. If `HEAD` or the branch moves, the workflow fails.
- Verification commands run without a shell; a failing command never lets a review approve.
- The review loop stops after the configured number of reviews.
- Commits always require explicit approval of the exact file list. Push is not supported.

## Repository layout

| Package                   | Purpose                                                                                                         |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `packages/weave_core`     | Workflow task model and state machine.                                                                          |
| `packages/weave_security` | Sandbox modes, approval policy, Git command classification, workspace scope, secret redaction.                  |
| `packages/weave_agents`   | Provider-neutral agent contracts; agents and MCP servers as data; process execution; Codex/Claude Code presets. |
| `packages/weave_git`      | User-directed clone setup; read-only status and diff; approval-gated commit.                                    |
| `packages/weave_storage`  | Task, artifact, and event-log storage outside the repository.                                                   |
| `packages/weave_workflow` | Orchestrator, prompts, verification, settings, shared services.                                                 |
| `apps/weave_cli`          | `weave` command-line interface.                                                                                 |
| `apps/weave_desktop`      | Flutter macOS app.                                                                                              |

## Running it

```sh
# Desktop app, debug mode with hot reload (press r to reload, q to quit)
cd apps/weave_desktop && fvm flutter run -d macos

# Desktop app, release build
cd apps/weave_desktop && fvm flutter build macos --release
open build/macos/Build/Products/Release/weave.app

# CLI
fvm dart run weave_cli:weave doctor
fvm dart run weave_cli:weave run --repo /path/to/repo "Describe the change"
```

To try Weave without touching your real data, set `WEAVE_HOME` to an empty folder first (`WEAVE_HOME=/tmp/weave-demo fvm flutter run -d macos`). Workflows only edit the repository you point them at; use a scratch Git repository for a first try.

## Sign-in, tokens, checkpoints, and failures

- **Sign-in.** Weave never asks for or stores passwords or tokens. Each agent keeps its own sign-in (Claude Code: `claude auth login`, Codex: `codex login`); Weave only runs the agent's status command (`claude auth status`, `codex login status`) and, when signed out, shows the exact command to run. A sign-in that expires mid-run pauses the workflow until you retry or cancel.
- **Tokens.** Usage and cost (where the agent reports it) are tracked per role and shown live; `maxTokens` stops a runaway workflow. The reviewer is skipped while checks fail, the implementer resumes its session to reuse the provider's prompt cache, diffs sent to the reviewer are capped, and each role can use its own model (e.g. a cheaper planner). Note that agent CLIs add their own system prompt to every call (about 22K tokens for Claude Code), so fewer, larger steps are cheaper than many small ones.
- **Checkpoints.** Optionally pause for your approval of the plan and/or of the changes before review, with feedback that sends the step back; the reviewer can also check the plan before any code is written.
- **Network and limits.** Agent failures are classified (network, usage limit, sign-in). Network errors are retried with backoff and the same session; a usage limit or lost sign-in switches the role to its configured fallback agent, or pauses for you when none is left. If Weave is closed mid-run, the workflow shows as interrupted and resumes from where it stopped (`weave resume <id>` or the Resume button); a lock prevents two Weave processes from running the same workflow.
- **Checklist and test cases.** The planner writes tasks (`T1`) and test cases (`TC1`); the implementer reports each as done, and the reviewer marks each verified or needing changes. A review cannot approve while any item still needs changes, and the app shows every item with the agent that implemented and reviewed it.

## Development

The SDK is pinned with FVM (`.fvmrc`: Flutter 3.47.6, Dart 3.13.5). Always use `fvm`.

```sh
fvm flutter pub get
fvm dart analyze
(cd packages/weave_workflow && fvm dart test)          # likewise for every package and apps/weave_cli
(cd apps/weave_desktop && fvm flutter test --no-pub)
fvm dart run weave_cli:weave doctor
(cd apps/weave_desktop && fvm flutter run -d macos)
```

Icons: the desktop app's SVG icons are generated from `apps/weave_desktop/tool/icons/icon_sources.dart`. After editing it, run `fvm dart run tool/generate_icons.dart` from `apps/weave_desktop` (add `--brands <folder>` to rebuild the brand marks from their source SVGs); a test fails while any asset is stale.

Code style: `dart format` with a 390-column page width and preserved trailing commas, `always_specify_types`, and Prettier (`printWidth: 390`) for Markdown, JSON, and YAML. Open the repository folder in VS Code; `.vscode/settings.json` points the Dart extension at the FVM SDK.

## Agents

Built-in presets: `codex` (`codex exec --json`) and `claude-code` (`claude --print --output-format stream-json`). Each role's sandbox is passed to the agent: Codex uses `--sandbox read-only|workspace-write`; Claude Code runs with `--restricted --permission-prompts none --strict-mcp-config`, read-only roles lose every editing tool, and implementers use `--permission-mode acceptEdits`. Prompts go through stdin so they never appear in the process list.

Add or override agents in `agents.json`:

```json
{
  "schemaVersion": 1,
  "agents": [
    {
      "id": "my-agent",
      "displayName": "My Agent",
      "executable": "my-agent",
      "arguments": ["run", "--cwd", "{workingDirectory}"],
      "sandboxArguments": { "readOnly": ["--read-only"], "workspaceWrite": [] },
      "resumeArguments": ["--session", "{sessionId}"],
      "outputFormat": "text",
      "mcpFormat": "none"
    }
  ]
}
```

Placeholders (`{workingDirectory}`, `{model}`, `{sessionId}`, `{prompt}`, `{mcpConfigFile}`, `{mcpToolNames}`) are replaced inside single arguments; nothing passes through a shell. `outputFormat` is `text`, `codex-jsonl`, or `claude-stream-json`.

## MCP servers

Figma presets are built in: `figma` (hosted, `https://mcp.figma.com/mcp`) and `figma-desktop` (`http://127.0.0.1:3845/mcp`). When a request contains a link a server handles — such as a `figma.com/design/...` URL — the CLI and the app offer to enable it. Enable servers per run (`--mcp figma`), per repository (`weave config --mcp figma`), or add others with `weave mcp add` or the app's MCP screen; they are stored in `mcp.json`. Write tokens as `${VAR}` so they are read from the environment at launch and never stored. Claude Code receives a private temporary `--mcp-config` file that is deleted when the agent exits; Codex receives `-c mcp_servers.*` overrides.

## Security notes

- Every child process (Git, agents, verification) is started with an executable and argument list — never `sh -c`. Inherited `GIT_*` variables are removed.
- Git reads use `--no-optional-locks`, disable repository fsmonitor hooks, and diffs use `--no-ext-diff --no-textconv`; untracked symlinks are skipped.
- Remote repositories are cloned only after the user selects a destination folder. Clone URLs cannot contain embedded credentials, query parameters, or fragments, and clone never modifies an existing working tree.
- Agent output, artifacts, and logs pass through secret redaction (known token formats, credential assignments, credential-like environment values, MCP headers and env values). Diffs are sent to the reviewer but never logged.
- The macOS app runs **without App Sandbox** so it can start Git, agent CLIs, and checks in any repository. Distribute it outside the Mac App Store, signed with a Developer ID and notarized.

## Known limitations

- The Codex adapter follows the documented `codex exec --json` format but has not been run against a real Codex binary on this machine.
- Push and remote operations are not implemented.
