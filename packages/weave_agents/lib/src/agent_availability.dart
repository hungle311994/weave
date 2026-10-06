/// The result of checking whether an agent adapter can run locally.
final class AgentAvailability {
  AgentAvailability._({required this.isAvailable, required this.version, required this.executablePath, required this.reason, this.signInCommand});

  factory AgentAvailability.available({required String version, required String executablePath}) => AgentAvailability._(isAvailable: true, version: _requireText(version, 'version'), executablePath: _requireText(executablePath, 'executablePath'), reason: null);

  factory AgentAvailability.unavailable({required String reason}) => AgentAvailability._(isAvailable: false, version: null, executablePath: null, reason: _requireText(reason, 'reason'));

  /// Installed but not signed in; the user must run [signInCommand] in a
  /// terminal. Weave never handles the credentials itself.
  factory AgentAvailability.signInRequired({required String version, required String executablePath, required String signInCommand}) => AgentAvailability._(
    isAvailable: false,
    version: _requireText(version, 'version'),
    executablePath: _requireText(executablePath, 'executablePath'),
    reason: 'Not signed in. Run `${_requireText(signInCommand, 'signInCommand')}` in Terminal, then check again.',
    signInCommand: signInCommand.trim(),
  );

  final bool isAvailable;
  final String? version;
  final String? executablePath;
  final String? reason;

  /// Set when the agent is installed but needs the user to sign in.
  final String? signInCommand;

  bool get needsSignIn => signInCommand != null;

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}
