import 'agent_event.dart';

/// Maps failure text from any agent CLI to an [AgentFailureKind].
///
/// The built-in patterns cover common wording of network, quota, and sign-in
/// errors; [extraPatterns] lets an agent definition add its own.
final class AgentFailureClassifier {
  AgentFailureClassifier({Map<AgentFailureKind, List<String>> extraPatterns = const <AgentFailureKind, List<String>>{}})
    : _patterns = <AgentFailureKind, List<RegExp>>{
        for (final AgentFailureKind kind in _checkedKinds)
          kind: <RegExp>[
            for (final String pattern in <String>[...?_defaults[kind], ...?extraPatterns[kind]]) RegExp(pattern, caseSensitive: false),
          ],
      };

  /// Checked in this order: a quota message that mentions the network is
  /// still a quota problem.
  static const List<AgentFailureKind> _checkedKinds = <AgentFailureKind>[AgentFailureKind.authentication, AgentFailureKind.rateLimit, AgentFailureKind.network];

  static const Map<AgentFailureKind, List<String>> _defaults = <AgentFailureKind, List<String>>{
    AgentFailureKind.authentication: <String>[r'\b401\b', r'unauthori[sz]ed', r'not (logged|signed) in', r'please (run )?/?login', r'invalid (api[ _-]?key|x-api-key|token)', r'authentication (failed|error|required)', r'oauth token (has )?expired', r'credentials? (are )?(missing|invalid|expired)'],
    AgentFailureKind.rateLimit: <String>[r'\b429\b', r'rate[ _-]?limit', r'usage limit', r'quota', r'insufficient[ _-]credits?', r'credit balance', r'out of credits', r'too many requests', r'limit (reached|exceeded)'],
    AgentFailureKind.network: <String>[r'ENOTFOUND', r'ECONNRESET', r'ECONNREFUSED', r'ETIMEDOUT', r'EAI_AGAIN', r'getaddrinfo', r'socket hang up', r'network (error|is unreachable|request failed)', r'connection (reset|refused|closed|error|timed out)', r'stream (disconnected|error)', r'fetch failed', r'unable to connect', r'offline', r'overloaded', r'\b50[234]\b', r'\b529\b'],
  };

  final Map<AgentFailureKind, List<RegExp>> _patterns;

  AgentFailureKind classify(String text) {
    for (final AgentFailureKind kind in _checkedKinds) {
      if (_patterns[kind]!.any((RegExp pattern) => pattern.hasMatch(text))) {
        return kind;
      }
    }
    return AgentFailureKind.unknown;
  }
}
