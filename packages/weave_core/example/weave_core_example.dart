import 'package:weave_core/weave_core.dart';

void main() {
  const WorkflowStateMachine stateMachine = WorkflowStateMachine();
  final WorkflowStatus nextStatus = stateMachine.transition(from: WorkflowStatus.pending, to: WorkflowStatus.planning);

  print('Workflow status: ${nextStatus.name}');
}
