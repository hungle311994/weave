# weave_workflow

Orchestration for Weave: plan → implement → self-review → verify → review, looping on requested changes until approval or the review limit.

- `WorkflowOrchestrator` / `WorkflowRun`: runs any agents from an `AgentRegistry`, persists every transition, streams `WorkflowEvent`s with replayable history, forwards approvals, supports cancellation, and enforces read-only and no-commit guards.
- `WorkflowSettings`: agent per role (by ID), verification commands, review limit, and MCP servers; stored as repository defaults and frozen per workflow.
- `VerificationCommand` / `ProcessVerificationRunner`: checks Weave runs itself, parsed without a shell.
- `DefaultWorkflowPrompts`: provider-neutral prompts; replace them by implementing `WorkflowPrompts`.
- `WeaveServices`: wires storage, agents (`agents.json`), MCP servers (`mcp.json`), and Git for the CLI and the desktop app.
