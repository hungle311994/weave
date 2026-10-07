import 'dart:async';

import 'agent_account.dart';
import 'agent_adapter.dart';
import 'agent_availability.dart';
import 'agent_event.dart';
import 'agent_plan_usage.dart';
import 'agent_run_request.dart';

/// Produces the summary of one scripted run, or throws to fail it.
typedef ScriptedAgentHandler = FutureOr<String> Function(
  AgentRunRequest request,
  ScriptedAgentSession session,
);

/// An in-process agent for tests and demos; it never starts a process.
final class ScriptedAgentAdapter implements AgentAdapter {
  ScriptedAgentAdapter({
    required this.id,
    required this.handler,
    String? displayName,
    this.isAvailable = true,
    this.supportsMcp = true,
    this.usage,
    this.signInCommand,
    this.planUsage,
    this.account,
    this.supportsAccounts = false,
    this.accountInfo,
  }) : displayName = displayName ?? id;

  @override
  final AgentAccount? account;

  @override
  final bool supportsAccounts;

  /// Returned by [readAccount] while [isAvailable].
  AgentAccountInfo? accountInfo;

  @override
  Future<AgentAccountInfo?> readAccount() async => isAvailable ? accountInfo : null;

  @override
  final String id;

  @override
  final String displayName;

  final ScriptedAgentHandler handler;
  final bool isAvailable;

  @override
  final bool supportsMcp;

  /// Reported with every completed run.
  final AgentUsage? usage;

  /// When set and not [isAvailable], the agent reports that it needs this
  /// sign-in command instead of being missing.
  final String? signInCommand;

  /// Returned by [readPlanUsage]; null means the agent reports no plan usage.
  AgentPlanUsage? planUsage;

  /// How often [readPlanUsage] was called.
  int planUsageReads = 0;

  @override
  bool get reportsPlanUsage => planUsage != null;

  @override
  Future<AgentPlanUsage> readPlanUsage() async {
    planUsageReads++;
    return planUsage ?? (throw AgentPlanUsageException('$id does not report plan usage.'));
  }

  /// Every request this adapter has started, in order.
  final List<AgentRunRequest> requests = <AgentRunRequest>[];

  /// How often [checkAvailability] was called.
  int availabilityChecks = 0;

  @override
  Future<AgentAvailability> checkAvailability() async {
    availabilityChecks++;
    if (isAvailable) {
      return AgentAvailability.available(version: 'scripted', executablePath: 'scripted:$id');
    }
    final String? signIn = signInCommand;
    return signIn == null ? AgentAvailability.unavailable(reason: '$id is not available.') : AgentAvailability.signInRequired(version: 'scripted', executablePath: 'scripted:$id', signInCommand: signIn);
  }

  @override
  Future<AgentExecution> start(AgentRunRequest request) async {
    requests.add(request);
    final _ScriptedAgentExecution execution = _ScriptedAgentExecution(
      executionId: '$id-${requests.length}',
      sessionId: request.resumeSessionId ?? '$id-session-${requests.length}',
    );
    execution._run(() => handler(request, execution._session), usage);
    return execution;
  }
}

/// Lets a [ScriptedAgentHandler] stream output and request approvals.
final class ScriptedAgentSession {
  ScriptedAgentSession._(this._execution);

  final _ScriptedAgentExecution _execution;

  bool get isCancelled => _execution._cancelled;

  void write(String text, {AgentOutputChannel channel = .stdout}) => _execution._emit(AgentOutputEvent(timestamp: DateTime.now(), text: text, channel: channel));

  Future<ApprovalDecision> requestApproval({required String action, required String details}) {
    final String approvalId = 'approval-${++_execution._approvalCount}';
    final Completer<ApprovalDecision> decision = Completer<ApprovalDecision>();
    _execution._pendingApprovals[approvalId] = decision;
    _execution._emit(AgentApprovalRequestedEvent(timestamp: DateTime.now(), approvalId: approvalId, action: action, details: details));
    return decision.future;
  }
}

final class _ScriptedAgentExecution implements AgentExecution {
  _ScriptedAgentExecution({required this.executionId, required this.sessionId});

  @override
  final String executionId;
  final String sessionId;
  final StreamController<AgentEvent> _events = StreamController<AgentEvent>();
  final Map<String, Completer<ApprovalDecision>> _pendingApprovals = <String, Completer<ApprovalDecision>>{};
  late final ScriptedAgentSession _session = ScriptedAgentSession._(this);
  int _approvalCount = 0;
  bool _cancelled = false;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> resolveApproval({required String approvalId, required ApprovalDecision decision}) async {
    final Completer<ApprovalDecision>? pending = _pendingApprovals.remove(approvalId);
    if (pending == null) {
      throw StateError('No pending approval with ID $approvalId.');
    }
    pending.complete(decision);
  }

  @override
  Future<void> cancel() async {
    if (_cancelled || _events.isClosed) {
      return;
    }
    _cancelled = true;
    for (final Completer<ApprovalDecision> pending in _pendingApprovals.values) {
      pending.complete(ApprovalDecision.deny);
    }
    _pendingApprovals.clear();
    _finish(AgentFailedEvent(timestamp: DateTime.now(), message: 'Cancelled by user.'));
  }

  Future<void> _run(FutureOr<String> Function() body, AgentUsage? usage) async {
    await Future<void>.delayed(Duration.zero);
    try {
      final String summary = await body();
      _finish(AgentCompletedEvent(timestamp: DateTime.now(), summary: summary, sessionId: sessionId, usage: usage));
    } on ScriptedAgentFailure catch (failure) {
      _finish(AgentFailedEvent(timestamp: DateTime.now(), message: failure.message, kind: failure.kind, sessionId: failure.sessionId, usage: usage));
    } on Object catch (error) {
      _finish(AgentFailedEvent(timestamp: DateTime.now(), message: error.toString()));
    }
  }

  void _emit(AgentEvent event) {
    if (!_cancelled && !_events.isClosed) {
      _events.add(event);
    }
  }

  void _finish(AgentEvent event) {
    if (_events.isClosed) {
      return;
    }
    _events.add(event);
    _events.close();
  }
}

/// Thrown by a [ScriptedAgentHandler] to fail with a specific kind, e.g. a
/// network error or a usage limit.
final class ScriptedAgentFailure implements Exception {
  const ScriptedAgentFailure(this.message, {this.kind = AgentFailureKind.unknown, this.sessionId});

  final String message;
  final AgentFailureKind kind;
  final String? sessionId;
}
