import 'workflow_state_machine.dart';
import 'workflow_status.dart';

/// A single user request moving through the Weave workflow.
final class WorkflowTask {
  WorkflowTask._({required this.id, required this.request, required this.repositoryPath, required this.status, required this.createdAt, required this.updatedAt, required this.reviewCycle});

  /// Creates a new task in the [WorkflowStatus.pending] state.
  factory WorkflowTask.create({required String id, required String request, required String repositoryPath, required DateTime createdAt}) => WorkflowTask.restore(id: id, request: request, repositoryPath: repositoryPath, status: WorkflowStatus.pending, createdAt: createdAt, updatedAt: createdAt, reviewCycle: 0);

  /// Rehydrates a task from persisted state.
  factory WorkflowTask.restore({required String id, required String request, required String repositoryPath, required WorkflowStatus status, required DateTime createdAt, required DateTime updatedAt, required int reviewCycle}) {
    final DateTime normalizedCreatedAt = createdAt.toUtc();
    final DateTime normalizedUpdatedAt = updatedAt.toUtc();

    if (normalizedUpdatedAt.isBefore(normalizedCreatedAt)) {
      throw ArgumentError.value(updatedAt, 'updatedAt', 'must not be before createdAt');
    }
    if (reviewCycle < 0) {
      throw ArgumentError.value(reviewCycle, 'reviewCycle', 'must not be negative');
    }

    return WorkflowTask._(id: _requireText(id, 'id'), request: _requireText(request, 'request'), repositoryPath: _requireText(repositoryPath, 'repositoryPath'), status: status, createdAt: normalizedCreatedAt, updatedAt: normalizedUpdatedAt, reviewCycle: reviewCycle);
  }

  final String id;
  final String request;
  final String repositoryPath;
  final WorkflowStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int reviewCycle;

  bool get isTerminal => status.isTerminal;

  /// Returns a new task after applying a valid workflow transition.
  WorkflowTask transitionTo(WorkflowStatus nextStatus, {required DateTime at, WorkflowStateMachine stateMachine = const WorkflowStateMachine()}) {
    final DateTime normalizedAt = at.toUtc();
    if (normalizedAt.isBefore(updatedAt)) {
      throw ArgumentError.value(at, 'at', 'must not be before the current updatedAt');
    }

    final WorkflowStatus validatedStatus = stateMachine.transition(from: status, to: nextStatus);

    return WorkflowTask._(id: id, request: request, repositoryPath: repositoryPath, status: validatedStatus, createdAt: createdAt, updatedAt: normalizedAt, reviewCycle: reviewCycle + (validatedStatus == WorkflowStatus.changesRequested ? 1 : 0));
  }

  static String _requireText(String value, String name) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}
