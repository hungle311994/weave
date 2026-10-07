import 'dart:convert';

/// How an agent reports who it is signed in as, through
/// [AgentDefinition.accountArguments].
enum AgentAccountFormat {
  /// The agent cannot report its account.
  none('none'),

  /// The command prints a JSON object; [AgentDefinition.accountEmailJsonField]
  /// and [AgentDefinition.accountPlanJsonField] name its fields.
  authStatusJson('auth-status-json'),

  /// The command starts Codex's app server; Weave asks it for
  /// `account/read` over JSON-RPC on stdio.
  codexAppServer('codex-app-server');

  const AgentAccountFormat(this.jsonName);

  final String jsonName;

  static AgentAccountFormat fromJsonName(String name) => values.firstWhere((AgentAccountFormat format) => format.jsonName == name, orElse: () => throw FormatException('Unknown accountFormat "$name".'));
}

/// One more sign-in of an agent, e.g. a second subscription of the same CLI.
///
/// The agent keeps this sign-in in its own configuration folder, which Weave
/// creates for the account and passes through
/// [AgentDefinition.accountDirectoryVariable]; Weave stores no credentials.
final class AgentAccount {
  AgentAccount({required String id, required String agentId, required String name}) : id = _requireId(id, 'id'), agentId = _requireId(agentId, 'agentId'), name = name.trim().isEmpty ? throw ArgumentError.value(name, 'name', 'must not be empty') : name.trim();

  factory AgentAccount.fromJson(Map<String, Object?> json) => switch (json) {
    <String, Object?>{'id': final String id, 'agentId': final String agentId, 'name': final String name} => AgentAccount(id: id, agentId: agentId, name: name),
    _ => throw const FormatException('Each account needs an id, an agentId and a name.'),
  };

  /// The agent ID this account runs as, e.g. `claude-code-work`.
  final String id;

  /// The agent it is an account of, e.g. `claude-code`.
  final String agentId;

  /// What the user calls it, e.g. "Work".
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'agentId': agentId, 'name': name};

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  static String _requireId(String value, String name) => _idPattern.hasMatch(value) ? value : throw ArgumentError.value(value, name, 'must be 1-64 lowercase letters, digits, dots, underscores or dashes');
}

/// Who an agent is signed in as, as the agent itself reports it.
final class AgentAccountInfo {
  const AgentAccountInfo({this.email, this.plan});

  final String? email;

  /// The subscription, e.g. `team` or `plus`, as the agent names it.
  final String? plan;

  bool get isEmpty => email == null && plan == null;
}

/// Parses an `accounts.json` document:
/// `{"schemaVersion": 1, "accounts": [<AgentAccount>...]}`.
List<AgentAccount> decodeAgentAccounts(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded case <String, Object?>{'schemaVersion': 1, 'accounts': final List<Object?> accounts}) {
    final List<AgentAccount> parsed = <AgentAccount>[
      for (final Object? account in accounts)
        if (account is Map<String, Object?>) AgentAccount.fromJson(account) else throw const FormatException('Each account must be an object.'),
    ];
    if (parsed.map((AgentAccount account) => account.id).toSet().length != parsed.length) {
      throw const FormatException('accounts.json contains duplicate account IDs.');
    }
    return parsed;
  }
  throw const FormatException('accounts.json must use schemaVersion 1 and contain an accounts list.');
}

/// Serializes [accounts] as an `accounts.json` document.
String encodeAgentAccounts(Iterable<AgentAccount> accounts) =>
    '${const JsonEncoder.withIndent('  ').convert(<String, Object>{
      'schemaVersion': 1,
      'accounts': <Map<String, Object?>>[for (final AgentAccount account in accounts) account.toJson()],
    })}\n';

/// [value] quoted for a POSIX shell command line shown to the user, e.g. in
/// Terminal; Weave itself never runs commands through a shell.
String shellQuote(String value) => RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(value) ? value : "'${value.replaceAll("'", r"'\''")}'";
