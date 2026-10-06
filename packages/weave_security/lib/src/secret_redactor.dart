/// Removes credentials from text before it is logged, stored, or displayed.
final class SecretRedactor {
  SecretRedactor({Iterable<String> knownSecrets = const <String>[]})
    : _knownSecrets = List<String>.unmodifiable(
        knownSecrets.where((String secret) => secret.length >= _minimumSecretLength).toSet().toList()
          // Longer values first so a secret containing another stays hidden.
          ..sort((String left, String right) => right.length.compareTo(left.length)),
      );

  /// Treats the values of credential-like environment variables, plus
  /// [additionalSecrets] such as configured request headers, as secrets.
  factory SecretRedactor.fromEnvironment(Map<String, String> environment, {Iterable<String> additionalSecrets = const <String>[]}) => SecretRedactor(
    knownSecrets: <String>[
      for (final MapEntry<String, String>(:String key, :String value) in environment.entries)
        if (_secretEnvironmentName.hasMatch(key)) value,
      ...additionalSecrets,
    ],
  );

  static const String placeholder = '[REDACTED]';
  static const int _minimumSecretLength = 8;

  final List<String> _knownSecrets;

  String redact(String input) {
    String output = input;
    for (final String secret in _knownSecrets) {
      output = output.replaceAll(secret, placeholder);
    }
    for (final RegExp pattern in _tokenPatterns) {
      output = output.replaceAll(pattern, placeholder);
    }
    output = output.replaceAllMapped(_bearerPattern, (Match match) => '${match[1]}$placeholder');
    output = output.replaceAllMapped(_urlCredentialPattern, (Match match) => '${match[1]}$placeholder@');
    return output.replaceAllMapped(_assignmentPattern, (Match match) => '${match[1]}${match[2]}${match[3]}$placeholder${match[3]}');
  }
}

final RegExp _secretEnvironmentName = RegExp(r'(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL)', caseSensitive: false);

final List<RegExp> _tokenPatterns = <RegExp>[
  RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'),
  RegExp(r'sk-ant-[A-Za-z0-9_\-]{10,}'),
  RegExp(r'sk-(?:proj-)?[A-Za-z0-9_\-]{20,}'),
  RegExp(r'gh[pousr]_[A-Za-z0-9]{20,}'),
  RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
  RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'),
  RegExp(r'xox[abprs]-[A-Za-z0-9\-]{10,}'),
  RegExp(r'AIza[0-9A-Za-z_\-]{35}'),
  RegExp(r'eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'),
];

final RegExp _bearerPattern = RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=\-]{16,}', caseSensitive: false);

final RegExp _urlCredentialPattern = RegExp(r'([a-z][a-z0-9+.\-]*://[^:/\s@]+:)[^@\s/]+@');

/// `password=...`, `api_key: "..."`, and similar literal assignments.
///
/// The value must end at whitespace, a quote, or punctuation, so code such as
/// `token = readToken()` is left alone.
final RegExp _assignmentPattern = RegExp(r'''([A-Za-z0-9_\-]*(?:password|passwd|secret|token|api[_\-]?key|access[_\-]?key)[A-Za-z0-9_\-]*)(\s*[:=]\s*)(["']?)(?!\[REDACTED\])[A-Za-z0-9_\-./+=~]{8,}\3(?=[\s"',;]|$)''', caseSensitive: false);
