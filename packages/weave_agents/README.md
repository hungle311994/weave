# weave_agents

Provider-neutral contracts and adapters for running AI coding agents from
Weave.

The package models interchangeable planner, implementer, and reviewer roles;
local agent availability; streamed output; approval requests; completion; and
failure without coupling the workflow to Codex, Claude Code, or another
provider.

- Each `AgentRole` has a fixed `SandboxMode`: planners and reviewers are
  read-only, implementers may write inside the workspace.
- `ProcessAgentExecution` runs an agent CLI with a separate executable and
  argument list, sends the prompt on stdin, redacts secrets from every event,
  and supports cancellation and timeouts.
- Agents are data: an `AgentDefinition` (executable, per-sandbox arguments,
  placeholders, output format) runs through the single `CommandAgentAdapter`.
  Codex and Claude Code are built-in presets; `AgentRegistry` adds custom
  agents from `agents.json`.
- `package:weave_agents/testing.dart` provides `ScriptedAgentAdapter` for
  tests and demos.
- `McpServerDefinition` / `McpRegistry` describe MCP servers (stdio or HTTP) as data, with Figma presets and link patterns. Each `AgentDefinition` declares how it receives them (`mcpFormat`): a private temporary `--mcp-config` file for Claude Code, `-c mcp_servers.*` overrides for Codex.
