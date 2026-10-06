# weave_security

Sandbox, approval, workspace scope, and secret redaction rules for Weave.

- `SandboxMode`: planners and reviewers run `readOnly`; implementers run
  `workspaceWrite`.
- `SecurityPolicy`: allows, denies, or requires approval for an operation.
  Commits, pushes, destructive Git operations, deletions, network access, and
  paths outside the workspace always require approval.
- `classifyGitArguments`: maps a Git argument list to a guarded operation;
  unknown subcommands are treated as destructive.
- `WorkspaceScope`: lexical and symlink-aware containment checks.
- `SecretRedactor`: removes tokens, keys, and credentials from text before it
  is logged, stored, or displayed.
