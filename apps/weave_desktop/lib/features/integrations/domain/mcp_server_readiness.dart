/// Whether an MCP server can start on this Mac, checked locally without
/// connecting to it: its `${NAME}` variables are set and its command exists.
final class McpServerReadiness {
  const McpServerReadiness.ready({this.detail}) : missingVariables = const <String>[], missingCommand = null;

  const McpServerReadiness.notReady({this.missingVariables = const <String>[], this.missingCommand, this.detail});

  /// Environment variables the server references but that are not set.
  final List<String> missingVariables;

  /// The stdio command when it was not found on this Mac.
  final String? missingCommand;

  /// What is ready, e.g. the URL or the resolved command path.
  final String? detail;

  bool get isReady => missingVariables.isEmpty && missingCommand == null;

  /// What to fix, in one line, or null when ready.
  String? get problem {
    if (missingCommand case final String command) {
      return '$command was not found on this Mac.';
    }
    if (missingVariables.isNotEmpty) {
      return 'Set ${missingVariables.map((String name) => '\$$name').join(', ')} in the environment Weave starts from, then reopen Weave.';
    }
    return null;
  }
}
