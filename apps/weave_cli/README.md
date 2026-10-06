# weave_cli

Command-line interface for Weave: one request is planned, implemented, self-reviewed, verified, and reviewed by the coding agents you assign to each role.

```sh
fvm dart run weave_cli:weave doctor                      # Git, storage, and agent availability
fvm dart run weave_cli:weave agents                      # assignable agent IDs
fvm dart run weave_cli:weave config --planner codex --implementer claude-code --reviewer codex --verify "fvm dart analyze" --verify "fvm dart test"
fvm dart run weave_cli:weave run "Add input validation to the signup form"
fvm dart run weave_cli:weave list
fvm dart run weave_cli:weave show --log <workflow-id>
```

- Any agent can play any role; `--agent <id>` assigns one agent to all roles. Without saved defaults, the first available agent plays every role.
- `--verify` commands are run by Weave itself (no shell) before every review; a failing command always sends the work back to the implementer.
- MCP servers (Figma presets built in, others via `weave mcp add`) are passed to every agent with `--mcp <id>` or `weave config --mcp <id>`. When a request contains a link a server handles, such as a Figma design URL, `weave run` offers to enable it; `--no-mcp-prompt` skips the offer. Use `${VAR}` in headers and env values so tokens stay in the environment.
- Approval requests are answered on the terminal; Ctrl+C cancels the running workflow.
- Exit codes: `0` completed, `1` failed, `64` usage error, `130` cancelled.
- State lives in `~/Library/Application Support/Weave` (or `WEAVE_HOME`), never in the repository. Custom agents go in `agents.json` there.
