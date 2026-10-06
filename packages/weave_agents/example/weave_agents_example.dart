import 'package:weave_agents/weave_agents.dart';

void main() {
  final AgentAssignments assignments = AgentAssignments(plannerAgentId: 'codex', implementerAgentId: 'claude-code', reviewerAgentId: 'codex');

  print('Planner: ${assignments.agentIdFor(AgentRole.planner)}');
}
