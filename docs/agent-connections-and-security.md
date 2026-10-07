# Agent connections and credential security

Status: product and architecture decision recorded for implementation after the Codex and Claude Code usage limits reset. This document describes planned behaviour, not functionality that is already complete.

## Product decisions

- A new Weave installation starts with no configured agents.
- Codex and Claude Code remain reusable presets in an agent catalog, but they are not automatically added to the user's active agent registry.
- The Agents screen starts with **Scan this Mac**. Scanning discovers supported local CLIs and checks agents already configured by the user. Discovery never activates an agent automatically.
- A user must explicitly choose **Add to Weave** before an agent can be assigned to a workflow.
- The configured-agent list reports distinct states: Ready, Sign-in required, Not found, and Invalid configuration.
- Custom agents are added through the Weave UI. Editing `agents.json` manually remains an advanced fallback, not the primary experience.

## Supported connection types

Weave should eventually support these provider-neutral transports behind the common `AgentAdapter` contract:

1. **Command-line agent** — a local executable with argument lists, sandbox arguments, structured output, resume arguments, authentication checks, and a sign-in command.
2. **API agent** — an HTTP model/agent API. Weave must supply the tool loop, repository tools, sandboxing, approvals, cancellation, usage accounting, and session handling before an API model can act as an implementer.
3. **Agent endpoint** — a local or remote agent daemon using a structured, versioned protocol and explicit capabilities.
4. **Hosted coding agent** — a future remote-job variant. Its remote repository/branch behaviour must be clearly separated from Weave's local-first working-tree workflow.

MCP servers are tools and context sources for agents; they are not agents.

Each configured agent declares capabilities such as planning, repository reading, repository editing, tool calling, streaming, approvals, resume, MCP, and structured usage. Role pickers only offer agents with the capabilities required by that role.

## Authentication experience

- Authentication does not belong in workflow chat. Chat history may be persisted or sent to an agent, while authentication output can contain device codes or other sensitive information.
- The Agents screen uses a dedicated, ephemeral **Agent Setup Console**.
- The console may run only the exact executable and argument list defined by the agent's `signInCommand`; it never invokes `sh -c`, accepts arbitrary shell commands, or becomes a general terminal.
- Console output is never added to workflow history, artifacts, prompts, or normal application logs.
- After the sign-in process exits, Weave runs the configured authentication-status check again and updates the agent state.
- If a CLI requires a real interactive terminal, Weave provides **Copy command** and **Open Terminal** as a safe fallback.

## Installation guidance

- Every command-line `AgentDefinition` may declare one or more labelled `installOptions`. Presets expose only installation commands published by the provider (for example Homebrew and npm); custom agents can declare the package managers they actually support. The legacy `installCommand` field remains accepted as a single option.
- When the executable is not found, onboarding and the Agents screen show **Not installed**, each supported command, and a copy icon beside it. Weave does not rewrite an npm command into yarn, pnpm, or another package manager because their global-install behaviour may differ. After installing, the user explicitly chooses **Scan again**.
- Weave never runs an installer, invokes a shell, requests administrator access, or treats an installation as consent to activate an agent.
- A failed version or health check is distinct from **Not installed** when Weave already resolved the executable path.

## Non-negotiable credential rules

- Weave never stores passwords, access tokens, refresh tokens, session cookies, API keys, or private keys.
- Secret values must never be written to the repository, `agents.json`, `mcp.json`, application preferences, workflow state, artifacts, logs, crash reports, tests, fixtures, screenshots, commit messages, or pull-request descriptions.
- Configuration stores only an environment-variable reference such as `${OPENAI_API_KEY}` or the variable name `OPENAI_API_KEY`, never its value.
- Secret values must never be committed or pushed. Before any future commit, inspect the exact staged file list and run the repository's secret checks.
- Agent output, setup-console output, errors, artifacts, and logs pass through the secret redactor before display or persistence where applicable.
- Authentication remains owned by the corresponding CLI/provider. Weave orchestrates the setup flow but does not become a credential vault.
- No provider-specific authentication branches are allowed in workflow code. Provider differences belong in preset data or a transport adapter.

## Planned implementation order

1. Separate `AgentCatalog` discovery candidates from the user-controlled `AgentRegistry`.
2. Introduce a backward-compatible `agents.json` schema that records explicitly enabled presets and custom definitions. A missing file means an empty configured registry.
3. Add **Scan this Mac**, discovery results, **Add to Weave**, and the four availability states.
4. Add the custom command-line agent form.
5. Add the constrained Agent Setup Console and external-Terminal fallback.
6. Add a provider-neutral capability model and enforce it in role selection.
7. Add API agents only after the sandboxed tool runtime and approval loop are complete.
8. Add the structured endpoint transport, then evaluate hosted coding agents separately.

## Continuation notes

- Preserve the repository's local-first guarantees: implementers leave only uncommitted working-tree edits, HEAD and branch must not move, commits require approval, and push is unsupported.
- Preserve the process rule: start an executable with an argument list and remove inherited `GIT_*` variables; never invoke a shell.
- Do not add a PTY or terminal dependency without explicit user approval.
- Update tests for discovery, registry persistence, authentication-state transitions, redaction, role capability filtering, cancellation, and the guarantee that no secret value reaches disk.

## Additional UX decisions and known gaps

- Discovery uses a hybrid model: run a non-mutating background scan on first launch and when the app becomes active, with throttling and cached results; always keep a visible **Scan again** action. Discovery never adds or enables an agent without confirmation.
- The New Task draft belongs to its controller rather than the page widget. Repository, request, role assignments, models, fallbacks, MCP selections, verification commands, checkpoints, and token budget survive navigation within the app. Saving repository defaults remains an explicit action.
- Every selected primary or fallback agent has a remove/clear action. Replacing an agent is not the only way to clear a role.
- Start Workflow validates every required role. The current implementation already returns `Choose an agent for every role.`, but the redesigned form must also mark each missing role inline and move focus to the first invalid role.
- Usage accounting and provider quota are different. Weave may aggregate usage it actually observes per agent for daily and weekly views. Remaining provider quota and reset time are shown only when the provider reports them through a supported API; Weave must not invent these values from local token counts.
- Custom MCP servers can currently be removed from `mcp.json`; built-in presets cannot. The redesigned Integrations screen distinguishes Remove custom configuration, Disable for a workflow/repository, and Disconnect authentication where supported.
- `⌘B` is implemented. `⌘N` is currently missing and must navigate to New Task without discarding the existing draft. Starting a deliberately blank draft requires a separate explicit action.
- New Task already suggests an MCP server when the request contains a matching link pattern and requires confirmation before enabling it. Future chat may propose an MCP server from an explicit user request such as “add the Figma MCP”, but it must never install, persist, authenticate, or enable a server without a confirmation step.
