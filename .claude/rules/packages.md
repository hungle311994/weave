---
paths:
  - "packages/**/*.dart"
  - "apps/weave_cli/**/*.dart"
---

# Packages and CLI

Principles: `AGENTS.md` → Layout and Architecture rules. This file adds the operational details.

## Rules

- **Dependency direction** (enforced by review, not tooling): `weave_core` and `weave_security` depend on nothing internal; `weave_agents`, `weave_git`, `weave_storage` build on them; `weave_workflow` sits on top; apps use `weave_workflow` and below. Adding an import that points upward means the code belongs in a higher package.
- **Public surface**: add new files under `lib/src/` and export them from `lib/<package>.dart` only if other packages need them. Test doubles go in a separate library such as `lib/testing.dart`, never in the main export.
- **Provider-neutral agents**: Codex and Claude Code may be named only in `agent_definition.dart` (preset factories), their output parsers, the `AgentOutputFormat` switch in `command_agent_adapter.dart`, `AgentRegistry.builtInDefinitions`, doc comments, and user-facing help text listing examples. Everything else uses agent IDs from data. A new provider behaviour becomes a field on `AgentDefinition` (with `fromJson`/`toJson` and a placeholder if needed) or a new `AgentOutputFormat`. Run `/check-provider-neutral` after touching agent code.
- **Processes**: start with `Process.start(executable, List<String>.of(arguments), workingDirectory: …, environment: …, includeParentEnvironment: false)` — never `runInShell`, `sh -c`, or string concatenation of arguments. Strip inherited `GIT_*` variables. Pass prompts through stdin so they never appear in the process list.
- **Git**: reads go through `GitRepositoryService` (`--no-optional-locks`, `-c core.fsmonitor=false`; diffs add `--no-ext-diff --no-textconv`). The only state-changing Git code is the approval-gated commit in `GitWriteService`; add no other write path. `GitCommandClassifier` in `weave_security` is the reference for which Git commands count as read-only.
- **Storage**: everything Weave writes goes under `WeaveStoragePaths` (`~/Library/Application Support/Weave` or `WEAVE_HOME`). Never write into the repository a workflow runs on — not even a temp file.
- **Secrets**: run agent output, artifacts and log entries through the secret redactor before storing or displaying them. MCP headers and env values are `${VAR}` references resolved at launch and never persisted resolved.
- **Errors**: classify agent failures with `AgentFailureClassifier` (network, usage limit, sign-in) instead of string-matching at call sites; network errors retry with backoff, limits switch to the fallback agent.
- **CLI**: commands parse arguments explicitly, print through the injected output sink, and return an exit code; keep messages actionable (what failed and the exact command to fix it).
