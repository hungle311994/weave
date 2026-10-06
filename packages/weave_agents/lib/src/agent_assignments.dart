import 'agent_role.dart';

/// Maps every workflow role to an interchangeable agent adapter ID.
final class AgentAssignments {
  AgentAssignments({
    required String plannerAgentId,
    required String implementerAgentId,
    required String reviewerAgentId,
  }) : _agentIds = Map<AgentRole, String>.unmodifiable(
         <AgentRole, String>{
           AgentRole.planner: _requireText(plannerAgentId, 'plannerAgentId'),
           AgentRole.implementer: _requireText(implementerAgentId, 'implementerAgentId'),
           AgentRole.reviewer: _requireText(reviewerAgentId, 'reviewerAgentId'),
         },
       );

  final Map<AgentRole, String> _agentIds;

  String agentIdFor(AgentRole role) => _agentIds[role]!;

  Map<AgentRole, String> toMap() => _agentIds;

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}
