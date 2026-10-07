import 'agent_account.dart';
import 'agent_availability.dart';
import 'agent_event.dart';
import 'agent_plan_usage.dart';
import 'agent_run_request.dart';

/// A provider-neutral adapter for Codex, Claude Code, or another local agent.
abstract interface class AgentAdapter {
  String get id;

  String get displayName;

  /// Whether [AgentRunRequest.mcpServers] can be passed to this agent.
  bool get supportsMcp;

  Future<AgentAvailability> checkAvailability();

  /// Whether [readPlanUsage] can report this agent's subscription limits.
  bool get reportsPlanUsage;

  /// Reads the agent's plan usage without running a model.
  ///
  /// Throws [AgentPlanUsageException] when it cannot be read or the agent
  /// does not report it.
  Future<AgentPlanUsage> readPlanUsage();

  /// Set when this adapter is one more account of another agent.
  AgentAccount? get account;

  /// Whether more accounts of this agent can be added.
  bool get supportsAccounts;

  /// Who the agent is signed in as, without running a model; `null` when it
  /// cannot tell (not signed in, or the agent does not report it).
  Future<AgentAccountInfo?> readAccount();

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
