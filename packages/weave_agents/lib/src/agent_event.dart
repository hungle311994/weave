/// The output channel used by a streamed agent message.
enum AgentOutputChannel { stdout, stderr }

/// A user's response to an agent approval request.
enum ApprovalDecision { approve, deny }

/// Why an agent execution failed, so Weave can retry, switch agents, or ask
/// the user to sign in.
enum AgentFailureKind {
  unknown,

  /// Connection lost or unreachable; retrying later usually helps.
  network,

  /// Rate limit, usage limit, or quota exhausted for this agent.
  rateLimit,

  /// Not signed in or the credentials were rejected.
  authentication,

  /// Weave stopped the agent after its time limit.
  timeout,

  /// The user cancelled the execution.
  cancelled,
}

/// Tokens and cost reported by an agent for one execution.
final class AgentUsage {
  const AgentUsage({this.inputTokens = 0, this.outputTokens = 0, this.cachedInputTokens = 0, this.costUsd});

  factory AgentUsage.fromJson(Map<String, Object?> json) => AgentUsage(
    inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
    outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
    cachedInputTokens: (json['cachedInputTokens'] as num?)?.toInt() ?? 0,
    costUsd: (json['costUsd'] as num?)?.toDouble(),
  );

  static const AgentUsage zero = AgentUsage();

  /// Fresh input tokens, excluding [cachedInputTokens].
  final int inputTokens;
  final int outputTokens;

  /// Input served from the provider's prompt cache, usually much cheaper.
  final int cachedInputTokens;

  /// `null` when the agent does not report cost.
  final double? costUsd;

  int get totalTokens => inputTokens + outputTokens + cachedInputTokens;

  AgentUsage operator +(AgentUsage other) => AgentUsage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
    costUsd: costUsd == null && other.costUsd == null ? null : (costUsd ?? 0) + (other.costUsd ?? 0),
  );

  Map<String, Object?> toJson() => <String, Object?>{'inputTokens': inputTokens, 'outputTokens': outputTokens, 'cachedInputTokens': cachedInputTokens, 'costUsd': costUsd};

  @override
  String toString() => '$totalTokens tokens (${inputTokens + cachedInputTokens} in, $outputTokens out)${costUsd == null ? '' : ', \$${costUsd!.toStringAsFixed(4)}'}';
}

/// A structured event emitted during an agent execution.
sealed class AgentEvent {
  AgentEvent({required DateTime timestamp}) : timestamp = timestamp.toUtc();

  final DateTime timestamp;
}

/// Incremental text emitted by an agent process.
final class AgentOutputEvent extends AgentEvent {
  AgentOutputEvent({required super.timestamp, required String text, this.channel = AgentOutputChannel.stdout}) : text = _requireContent(text, 'text');

  final String text;
  final AgentOutputChannel channel;
}

/// A sensitive action that must pause until the user approves or denies it.
final class AgentApprovalRequestedEvent extends AgentEvent {
  AgentApprovalRequestedEvent({required super.timestamp, required String approvalId, required String action, required String details}) : approvalId = _requireText(approvalId, 'approvalId'), action = _requireText(action, 'action'), details = _requireContent(details, 'details');

  final String approvalId;
  final String action;
  final String details;
}

/// The successful terminal event of an agent execution.
final class AgentCompletedEvent extends AgentEvent {
  AgentCompletedEvent({required super.timestamp, required String summary, String? sessionId, this.usage}) : summary = _requireContent(summary, 'summary'), sessionId = _optionalText(sessionId, 'sessionId');

  final String summary;
  final String? sessionId;
  final AgentUsage? usage;
}

/// The failed terminal event of an agent execution.
final class AgentFailedEvent extends AgentEvent {
  AgentFailedEvent({required super.timestamp, required String message, this.exitCode, this.kind = AgentFailureKind.unknown, String? sessionId, this.usage}) : message = _requireText(message, 'message'), sessionId = _optionalText(sessionId, 'sessionId');

  final String message;
  final int? exitCode;
  final AgentFailureKind kind;

  /// The session to resume when retrying, if the agent started one.
  final String? sessionId;
  final AgentUsage? usage;
}

String _requireText(String value, String name) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return normalized;
}

String _requireContent(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
  return value;
}

String? _optionalText(String? value, String name) => value == null ? null : _requireText(value, name);
