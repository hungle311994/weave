import 'agent_account.dart';
import 'agent_plan_usage.dart';

/// JSON-RPC lines Weave sends to `codex app-server` to read rate limits; the
/// request runs no model and changes nothing.
const List<Map<String, Object?>> codexPlanUsageRequests = <Map<String, Object?>>[
  <String, Object?>{
    'id': 1,
    'method': 'initialize',
    'params': <String, Object?>{
      'clientInfo': <String, Object?>{'name': 'weave', 'version': '1.0.0'},
    },
  },
  <String, Object?>{'method': 'initialized'},
  <String, Object?>{'id': codexPlanUsageRequestId, 'method': 'account/rateLimits/read'},
];

/// The id of the `account/rateLimits/read` request in [codexPlanUsageRequests].
const int codexPlanUsageRequestId = 2;

/// JSON-RPC lines Weave sends to `codex app-server` to read who is signed
/// in; the request runs no model and changes nothing.
const List<Map<String, Object?>> codexAccountRequests = <Map<String, Object?>>[
  <String, Object?>{
    'id': 1,
    'method': 'initialize',
    'params': <String, Object?>{
      'clientInfo': <String, Object?>{'name': 'weave', 'version': '1.0.0'},
    },
  },
  <String, Object?>{'method': 'initialized'},
  <String, Object?>{'id': codexAccountRequestId, 'method': 'account/read', 'params': <String, Object?>{}},
];

/// The id of the `account/read` request in [codexAccountRequests].
const int codexAccountRequestId = 2;

/// The email and plan from an `account/read` response message, or `null`
/// when nobody is signed in or the sign-in has neither (e.g. an API key).
AgentAccountInfo? parseCodexAccount(Map<String, Object?> message) {
  if (message case <String, Object?>{'result': <String, Object?>{'account': final Map<String, Object?> account}}) {
    final AgentAccountInfo info = AgentAccountInfo(email: account['email'] is String ? account['email']! as String : null, plan: account['planType'] is String ? account['planType']! as String : null);
    return info.isEmpty ? null : info;
  }
  return null;
}

/// Reads the windows from an `account/rateLimits/read` response message.
/// Account identifiers in the message are ignored.
List<AgentPlanUsageWindow> parseCodexPlanUsage(Map<String, Object?> message) {
  if (message['error'] case final Map<String, Object?> error) {
    throw AgentPlanUsageException('Codex could not report its usage: ${error['message'] ?? 'unknown error'}.');
  }
  final Object? result = message['result'];
  final Object? limits = result is Map<String, Object?> ? result['rateLimits'] : null;
  if (limits is! Map<String, Object?>) {
    return const <AgentPlanUsageWindow>[];
  }
  return <AgentPlanUsageWindow>[
    for (final String key in const <String>['primary', 'secondary'])
      if (limits[key] case <String, Object?>{'usedPercent': final num used} && final Map<String, Object?> window)
        AgentPlanUsageWindow(
          label: _label(window['windowDurationMins']),
          percentUsed: used.round(),
          resetTime: window['resetsAt'] is num ? DateTime.fromMillisecondsSinceEpoch((window['resetsAt']! as num).toInt() * 1000, isUtc: true) : null,
        ),
  ];
}

/// "5-hour limit", "Weekly limit", from the window length in minutes.
String _label(Object? minutes) {
  if (minutes is! num || minutes <= 0) {
    return 'Usage limit';
  }
  final int total = minutes.toInt();
  if (total == 7 * 24 * 60) {
    return 'Weekly limit';
  }
  if (total % (24 * 60) == 0) {
    return '${total ~/ (24 * 60)}-day limit';
  }
  if (total % 60 == 0) {
    return '${total ~/ 60}-hour limit';
  }
  return '$total-minute limit';
}
