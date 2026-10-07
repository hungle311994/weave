/// Opens a command in the user's Terminal, e.g. an agent's sign-in, so the
/// user signs in with the agent itself and Weave never sees credentials.
abstract interface class TerminalLauncher {
  /// Opens a new Terminal window that runs [command]; [name] identifies it.
  Future<void> run(String command, {required String name});
}
