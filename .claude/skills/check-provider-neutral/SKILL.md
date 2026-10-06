---
name: check-provider-neutral
description: Audit Weave code for agent-specific branching (Codex, Claude Code, or any provider named outside its preset, parser or docs), which would break the agents-as-data design. Read-only — reports each hit and how to move it into AgentDefinition data or an output format.
---

# Check provider neutrality

## Why this matters

Users add or swap agents per role through `agents.json` without code changes. Any `if (agentId == 'codex')` elsewhere silently breaks that promise for every other agent.

## Step 1 — Search

```sh
grep -rniE "codex|claude|gemini|openai|anthropic" packages/*/lib apps/*/lib --include=*.dart
```

## Step 2 — Allowed places

- `packages/weave_agents/lib/src/agent_definition.dart` — the preset factories (`AgentDefinition.codex()`, `.claudeCode()`).
- `packages/weave_agents/lib/src/codex_output_parser.dart`, `claude_code_output_parser.dart` — output formats.
- `packages/weave_agents/lib/src/command_agent_adapter.dart` — the `AgentOutputFormat` → parser switch.
- `packages/weave_agents/lib/src/agent_registry.dart` — `builtInDefinitions`.
- `packages/weave_agents/lib/weave_agents.dart` — exports.
- Doc comments and user-facing help text that lists agents as examples ("Install Claude Code, Codex, or another CLI agent").
- `apps/weave_desktop/lib/core/design_system/icons/weave_icons.dart` — brand marks are design assets selected by name from data.

## Step 3 — Report everything else

For each other hit: `file:line`, what it does, and the neutral alternative — a new `AgentDefinition` field (with `fromJson`/`toJson`, used by every agent), a placeholder in arguments, an `AgentOutputFormat`, or selection by agent ID from settings. Do not edit unless asked.
