import 'package:test/test.dart';
import 'package:weave_core/weave_core.dart';

void main() {
  final DateTime createdAt = DateTime.utc(2026, 10, 6, 10);

  WorkflowTask createTask() => WorkflowTask.create(id: 'task-1', request: 'Build the Weave workflow', repositoryPath: '/projects/weave', createdAt: createdAt);

  group('WorkflowTask.create', () {
    test('creates a pending task with normalized values', () {
      final WorkflowTask task = WorkflowTask.create(id: '  task-1  ', request: '  Build the Weave workflow  ', repositoryPath: '  /projects/weave  ', createdAt: createdAt.toLocal());

      expect(task.id, 'task-1');
      expect(task.request, 'Build the Weave workflow');
      expect(task.repositoryPath, '/projects/weave');
      expect(task.status, WorkflowStatus.pending);
      expect(task.createdAt, createdAt);
      expect(task.updatedAt, createdAt);
      expect(task.reviewCycle, 0);
      expect(task.isTerminal, isFalse);
    });

    test('rejects empty required text', () {
      expect(() => WorkflowTask.create(id: ' ', request: 'Build Weave', repositoryPath: '/projects/weave', createdAt: createdAt), throwsArgumentError);
      expect(() => WorkflowTask.create(id: 'task-1', request: ' ', repositoryPath: '/projects/weave', createdAt: createdAt), throwsArgumentError);
      expect(() => WorkflowTask.create(id: 'task-1', request: 'Build Weave', repositoryPath: ' ', createdAt: createdAt), throwsArgumentError);
    });
  });

  group('WorkflowTask.restore', () {
    test('restores persisted workflow state', () {
      final DateTime updatedAt = createdAt.add(const Duration(minutes: 5));
      final WorkflowTask task = WorkflowTask.restore(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.changesRequested, createdAt: createdAt, updatedAt: updatedAt, reviewCycle: 2);

      expect(task.status, WorkflowStatus.changesRequested);
      expect(task.updatedAt, updatedAt);
      expect(task.reviewCycle, 2);
    });

    test('rejects a negative review cycle', () {
      expect(() => WorkflowTask.restore(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.pending, createdAt: createdAt, updatedAt: createdAt, reviewCycle: -1), throwsArgumentError);
    });

    test('rejects an update before creation', () {
      expect(() => WorkflowTask.restore(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.pending, createdAt: createdAt, updatedAt: createdAt.subtract(const Duration(seconds: 1)), reviewCycle: 0), throwsArgumentError);
    });
  });

  group('WorkflowTask.transitionTo', () {
    test('returns a new task with the next status and update time', () {
      final WorkflowTask task = createTask();
      final DateTime transitionedAt = createdAt.add(const Duration(minutes: 1));
      final WorkflowTask transitioned = task.transitionTo(WorkflowStatus.planning, at: transitionedAt);

      expect(transitioned, isNot(same(task)));
      expect(task.status, WorkflowStatus.pending);
      expect(transitioned.status, WorkflowStatus.planning);
      expect(transitioned.updatedAt, transitionedAt);
      expect(transitioned.createdAt, createdAt);
    });

    test('increments the review cycle when changes are requested', () {
      final WorkflowTask reviewingTask = WorkflowTask.restore(id: 'task-1', request: 'Build Weave', repositoryPath: '/projects/weave', status: WorkflowStatus.reviewing, createdAt: createdAt, updatedAt: createdAt, reviewCycle: 0);

      final WorkflowTask result = reviewingTask.transitionTo(WorkflowStatus.changesRequested, at: createdAt.add(const Duration(minutes: 1)));

      expect(result.reviewCycle, 1);
    });

    test('keeps the review cycle for other transitions', () {
      final WorkflowTask result = createTask().transitionTo(WorkflowStatus.planning, at: createdAt.add(const Duration(minutes: 1)));

      expect(result.reviewCycle, 0);
    });

    test('rejects an invalid state transition', () {
      expect(() => createTask().transitionTo(WorkflowStatus.completed, at: createdAt.add(const Duration(minutes: 1))), throwsA(isA<InvalidWorkflowTransition>()));
    });

    test('rejects a timestamp before the current update', () {
      expect(() => createTask().transitionTo(WorkflowStatus.planning, at: createdAt.subtract(const Duration(seconds: 1))), throwsArgumentError);
    });
  });
}
