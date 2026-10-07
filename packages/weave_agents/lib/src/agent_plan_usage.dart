/// How an agent reports its plan usage through [AgentDefinition.planUsageArguments].
enum AgentPlanUsageFormat {
  /// The command prints a report with lines such as
  /// `Current session: 28% used · resets Oct 7 at 8:10pm`, optionally inside
  /// a JSON field ([AgentDefinition.planUsageJsonField]).
  text('text'),

  /// The command starts Codex's app server; Weave asks it for
  /// `account/rateLimits/read` over JSON-RPC on stdio.
  codexAppServer('codex-app-server');

  const AgentPlanUsageFormat(this.jsonName);

  final String jsonName;

  static AgentPlanUsageFormat fromJsonName(String name) => values.firstWhere((AgentPlanUsageFormat format) => format.jsonName == name, orElse: () => throw FormatException('Unknown planUsageFormat "$name".'));
}

/// One limit window of an agent's subscription plan, e.g. the current
/// session or the current week, as the agent's own CLI reports it.
final class AgentPlanUsageWindow {
  AgentPlanUsageWindow({required String label, required this.percentUsed, this.resetsAt, DateTime? resetTime}) : label = label.trim(), resetTime = resetTime?.toUtc() {
    if (this.label.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (percentUsed < 0) {
      throw ArgumentError.value(percentUsed, 'percentUsed', 'must not be negative');
    }
  }

  /// The CLI's own name for the window, e.g. "Current week (all models)".
  final String label;
  final int percentUsed;

  /// When the window resets, worded as the CLI words it (with its time zone).
  final String? resetsAt;

  /// When the window resets, when the CLI gives an exact time.
  final DateTime? resetTime;
}

/// Plan usage read from an agent's CLI at [checkedAt].
final class AgentPlanUsage {
  AgentPlanUsage({required List<AgentPlanUsageWindow> windows, required DateTime checkedAt}) : windows = List<AgentPlanUsageWindow>.unmodifiable(windows), checkedAt = checkedAt.toUtc();

  final List<AgentPlanUsageWindow> windows;
  final DateTime checkedAt;

  static final RegExp _line = RegExp(r'^\s*(.+?):\s*(\d{1,3})(?:\.\d+)?%\s+used(?:\s*[·•,-]\s*resets\s+(.+?))?\s*$', multiLine: true);

  /// Reads lines such as `Current session: 28% used · resets Oct 7 at 8:10pm`
  /// from a usage report; other lines are ignored.
  static List<AgentPlanUsageWindow> parseWindows(String report) => <AgentPlanUsageWindow>[
    for (final RegExpMatch match in _line.allMatches(report)) AgentPlanUsageWindow(label: match.group(1)!, percentUsed: int.parse(match.group(2)!), resetsAt: match.group(3)),
  ];
}

/// The agent's plan usage could not be read; [message] is safe to show.
final class AgentPlanUsageException implements Exception {
  const AgentPlanUsageException(this.message);

  final String message;

  @override
  String toString() => 'AgentPlanUsageException: $message';
}
