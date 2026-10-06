import 'package:test/test.dart';
import 'package:weave_core/weave_core.dart';

void main() {
  const WorkflowStateMachine stateMachine = WorkflowStateMachine();

  group('WorkflowStateMachine', () {
    const Map<WorkflowStatus, Set<WorkflowStatus>> expectedTransitions = <WorkflowStatus, Set<WorkflowStatus>>{
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

    for (final MapEntry<WorkflowStatus, Set<WorkflowStatus>>(key: WorkflowStatus from, value: Set<WorkflowStatus> allowed) in expectedTransitions.entries) {
      test('defines transitions from ${from.name}', () {
        expect(stateMachine.allowedTransitionsFrom(from), equals(allowed));
      });
    }

    test('returns the destination for a valid transition', () {
      final WorkflowStatus result = stateMachine.transition(from: WorkflowStatus.pending, to: WorkflowStatus.planning);

      expect(result, WorkflowStatus.planning);
    });

    test('rejects an invalid transition', () {
      expect(() => stateMachine.transition(from: WorkflowStatus.pending, to: WorkflowStatus.completed), throwsA(isA<InvalidWorkflowTransition>().having((InvalidWorkflowTransition error) => error.from, 'from', WorkflowStatus.pending).having((InvalidWorkflowTransition error) => error.to, 'to', WorkflowStatus.completed)));
    });

    test('does not allow a transition from a terminal state', () {
      for (final WorkflowStatus status in WorkflowStatus.values.where((WorkflowStatus status) => status.isTerminal)) {
        expect(stateMachine.allowedTransitionsFrom(status), isEmpty);
      }
    });
  });

  group('WorkflowStatus', () {
    test('identifies terminal states', () {
      expect(WorkflowStatus.completed.isTerminal, isTrue);
      expect(WorkflowStatus.failed.isTerminal, isTrue);
      expect(WorkflowStatus.cancelled.isTerminal, isTrue);
    });

    test('identifies active states', () {
      final Iterable<WorkflowStatus> activeStatuses = WorkflowStatus.values.where((WorkflowStatus status) => !status.isTerminal);

      expect(activeStatuses, isNotEmpty);
      expect(activeStatuses, isNot(contains(WorkflowStatus.completed)));
      expect(activeStatuses, isNot(contains(WorkflowStatus.failed)));
      expect(activeStatuses, isNot(contains(WorkflowStatus.cancelled)));
    });
  });
}
