import 'package:weave_agents/weave_agents.dart';
import 'package:weave_core/weave_core.dart';
import 'package:weave_storage/weave_storage.dart';

import 'verification.dart';
import 'workflow_checklist.dart';
import 'workflow_repositories.dart';

/// Progress of a running workflow, for the CLI, the desktop app, and logs.
sealed class WorkflowEvent {
  WorkflowEvent({DateTime? timestamp}) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  final DateTime timestamp;

  /// `weave` or the role that produced the event.
  String get source => 'weave';

  /// One-line description for logs.
  String get message;
}

final class WorkflowStatusChanged extends WorkflowEvent {
  WorkflowStatusChanged(this.task, {super.timestamp});

  final WorkflowTask task;

  @override
  String get message => 'Status: ${task.status.name}${task.reviewCycle > 0 ? ' (review round ${task.reviewCycle})' : ''}';
}

final class WorkflowAgentStarted extends WorkflowEvent {
  WorkflowAgentStarted({required this.role, required this.agentId, required this.phase, super.timestamp});

  final AgentRole role;
  final String agentId;

  /// `plan`, `implement`, `self-review`, or `review`.
  final String phase;

  @override
  String get source => role.name;

  @override
  String get message => '$agentId started $phase';
}

final class WorkflowAgentOutput extends WorkflowEvent {
  WorkflowAgentOutput({required this.role, required this.text, required this.channel, super.timestamp});

  final AgentRole role;
  final String text;
  final AgentOutputChannel channel;

  @override
  String get source => role.name;

  @override
  String get message => text;
}

final class WorkflowApprovalRequested extends WorkflowEvent {
  WorkflowApprovalRequested({required this.role, required this.approvalId, required this.action, required this.details, super.timestamp});

  final AgentRole role;
  final String approvalId;
  final String action;
  final String details;

  @override
  String get source => role.name;

  @override
  String get message => 'Approval requested ($approvalId): $action';
}

final class WorkflowApprovalResolved extends WorkflowEvent {
  WorkflowApprovalResolved({required this.approvalId, required this.decision, super.timestamp});

  final String approvalId;
  final ApprovalDecision decision;

  @override
  String get message => 'Approval $approvalId: ${decision.name}';
}

final class WorkflowArtifactSaved extends WorkflowEvent {
  WorkflowArtifactSaved(this.artifact, {super.timestamp});

  final WorkflowArtifact artifact;

  @override
  String get message => 'Saved ${artifact.kind.name} (round ${artifact.cycle})';
}

final class WorkflowVerificationFinished extends WorkflowEvent {
  WorkflowVerificationFinished(this.results, {super.timestamp});

  final List<VerificationResult> results;

  bool get passed => results.every((VerificationResult result) => result.passed);

  @override
  String get message => 'Verification ${passed ? 'passed' : 'failed'} (${results.length} command(s))';
}

/// The last event of every run.
final class WorkflowFinished extends WorkflowEvent {
  WorkflowFinished(this.task, {this.reason, super.timestamp});

  final WorkflowTask task;

  /// Why the workflow failed or was cancelled.
  final String? reason;

  @override
  String get message => 'Finished: ${task.status.name}${reason == null ? '' : ' — $reason'}';
}

/// An agent run ended successfully, with what it cost.
final class WorkflowAgentFinished extends WorkflowEvent {
  WorkflowAgentFinished({required this.role, required this.agentId, required this.phase, required this.usage, required this.totalUsage, super.timestamp});

  final AgentRole role;
  final String agentId;
  final String phase;

  /// This run's usage, or `null` when the agent reports none.
  final AgentUsage? usage;

  /// Everything the workflow has used so far.
  final AgentUsage totalUsage;

  @override
  String get source => role.name;

  @override
  String get message => '$agentId finished $phase${usage == null ? '' : ' — $usage'}';
}

/// A failed agent run will be tried again after [delay].
final class WorkflowRetryScheduled extends WorkflowEvent {
  WorkflowRetryScheduled({required this.role, required this.agentId, required this.attempt, required this.maxAttempts, required this.delay, required this.reason, super.timestamp});

  final AgentRole role;
  final String agentId;

  /// The attempt about to start, counting from 2.
  final int attempt;
  final int maxAttempts;
  final Duration delay;
  final String reason;

  @override
  String get source => role.name;

  @override
  String get message => 'Retrying $agentId in ${delay.inSeconds}s (attempt $attempt of $maxAttempts): $reason';
}

/// A role moved to a fallback agent, e.g. after a usage limit.
final class WorkflowAgentSwitched extends WorkflowEvent {
  WorkflowAgentSwitched({required this.role, required this.fromAgentId, required this.toAgentId, required this.reason, super.timestamp});

  final AgentRole role;
  final String fromAgentId;
  final String toAgentId;
  final String reason;

  @override
  String get source => role.name;

  @override
  String get message => 'Switched from $fromAgentId to $toAgentId: $reason';
}

/// Where the workflow pauses for the user.
enum WorkflowCheckpointKind {
  /// Approve, revise, or cancel the plan before any code changes.
  plan,

  /// Approve or revise the implementer's changes before review.
  changes,

  /// An agent cannot continue (usage limit or sign-in); retry or cancel.
  agentUnavailable,

  /// Choose which repositories of a multi-repository workflow the
  /// implementer may edit; revise asks the planner for a new plan.
  repositories,
}

/// The user's answer to a [WorkflowCheckpoint].
enum CheckpointDecision {
  /// Continue; for [WorkflowCheckpointKind.agentUnavailable], retry now.
  approve,

  /// Redo the step with the user's feedback.
  revise,

  /// End the workflow.
  cancel,
}

/// A pause waiting for the user.
final class WorkflowCheckpoint {
  const WorkflowCheckpoint({required this.id, required this.kind, required this.title, required this.details, this.role, this.repositories = const <WorkflowRepositoryChoice>[]});

  final String id;
  final WorkflowCheckpointKind kind;
  final String title;

  /// What the user decides on: the plan, a change summary, or the error.
  final String details;
  final AgentRole? role;

  /// The choices of a [WorkflowCheckpointKind.repositories] checkpoint.
  final List<WorkflowRepositoryChoice> repositories;

  bool get allowsRevision => kind != WorkflowCheckpointKind.agentUnavailable;
}

final class WorkflowCheckpointRequested extends WorkflowEvent {
  WorkflowCheckpointRequested(this.checkpoint, {super.timestamp});

  final WorkflowCheckpoint checkpoint;

  @override
  String get message => 'Waiting for you: ${checkpoint.title}';
}

final class WorkflowCheckpointResolved extends WorkflowEvent {
  WorkflowCheckpointResolved({required this.checkpointId, required this.decision, this.feedback, super.timestamp});

  final String checkpointId;
  final CheckpointDecision decision;
  final String? feedback;

  @override
  String get message => 'Checkpoint ${decision.name}${feedback == null ? '' : ': $feedback'}';
}

/// The plan's task and test case list changed.
final class WorkflowChecklistUpdated extends WorkflowEvent {
  WorkflowChecklistUpdated(this.checklist, {super.timestamp});

  final WorkflowChecklist checklist;

  @override
  String get message {
    final int done = checklist.items.where((ChecklistItem item) => item.status == ChecklistItemStatus.done || item.status == ChecklistItemStatus.verified).length;
    return 'Checklist: $done of ${checklist.items.length} done${checklist.needingChanges.isEmpty ? '' : ', ${checklist.needingChanges.length} need changes'}';
  }
}
