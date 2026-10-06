import 'agent_availability.dart';
import 'agent_event.dart';
import 'agent_run_request.dart';

/// A provider-neutral adapter for Codex, Claude Code, or another local agent.
abstract interface class AgentAdapter {
  String get id;

  String get displayName;

  /// Whether [AgentRunRequest.mcpServers] can be passed to this agent.
  bool get supportsMcp;

  Future<AgentAvailability> checkAvailability();

  Future<AgentExecution> start(AgentRunRequest request);
}

/// A running agent session controlled by Weave.
abstract interface class AgentExecution {
  String get executionId;

  Stream<AgentEvent> get events;

  Future<void> resolveApproval({
    required String approvalId,
    required ApprovalDecision decision,
  });

  Future<void> cancel();
}
