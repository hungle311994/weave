import 'workflow_status.dart';

/// Validates lifecycle transitions for a Weave workflow.
final class WorkflowStateMachine {
  const WorkflowStateMachine();

  static const Map<WorkflowStatus, Set<WorkflowStatus>> _transitions = <WorkflowStatus, Set<WorkflowStatus>>{
    WorkflowStatus.pending: <WorkflowStatus>{WorkflowStatus.planning, WorkflowStatus.cancelled},
    WorkflowStatus.planning: <WorkflowStatus>{WorkflowStatus.readyForImplementation, WorkflowStatus.failed, WorkflowStatus.cancelled},
    WorkflowStatus.readyForImplementation: <WorkflowStatus>{WorkflowStatus.implementing, WorkflowStatus.cancelled},
    WorkflowStatus.implementing: <WorkflowStatus>{WorkflowStatus.readyForReview, WorkflowStatus.failed, WorkflowStatus.cancelled},
    WorkflowStatus.readyForReview: <WorkflowStatus>{WorkflowStatus.reviewing, WorkflowStatus.cancelled},
    WorkflowStatus.reviewing: <WorkflowStatus>{WorkflowStatus.changesRequested, WorkflowStatus.completed, WorkflowStatus.failed, WorkflowStatus.cancelled},
    WorkflowStatus.changesRequested: <WorkflowStatus>{WorkflowStatus.implementing, WorkflowStatus.failed, WorkflowStatus.cancelled},
    WorkflowStatus.completed: <WorkflowStatus>{},
    WorkflowStatus.failed: <WorkflowStatus>{},
    WorkflowStatus.cancelled: <WorkflowStatus>{},
  };

  /// Returns all states that can immediately follow [status].
  Set<WorkflowStatus> allowedTransitionsFrom(WorkflowStatus status) => _transitions[status] ?? const <WorkflowStatus>{};

  /// Returns whether the transition from [from] to [to] is allowed.
  bool canTransition({required WorkflowStatus from, required WorkflowStatus to}) => allowedTransitionsFrom(from).contains(to);

  /// Returns [to] when valid, otherwise throws an
  /// [InvalidWorkflowTransition].
  WorkflowStatus transition({required WorkflowStatus from, required WorkflowStatus to}) {
    if (!canTransition(from: from, to: to)) {
      throw InvalidWorkflowTransition(from: from, to: to);
    }

    return to;
  }
}

/// Raised when a workflow attempts an unsupported lifecycle transition.
final class InvalidWorkflowTransition implements Exception {
  const InvalidWorkflowTransition({required this.from, required this.to});

  final WorkflowStatus from;
  final WorkflowStatus to;

  @override
  String toString() => 'Invalid workflow transition: ${from.name} -> ${to.name}';
}
