/// The filesystem access an agent or command is granted.
enum SandboxMode {
  /// May read the workspace but never change it.
  readOnly,

  /// May change files inside the workspace only.
  workspaceWrite;

  bool get allowsWrites => this == workspaceWrite;
}
