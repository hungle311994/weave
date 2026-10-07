import 'package:flutter/material.dart';
import 'package:weave_core/weave_core.dart';

/// Human-readable label for a workflow status.
String statusLabel(WorkflowStatus status) => switch (status) {
  WorkflowStatus.pending => 'Pending',
  WorkflowStatus.planning => 'Planning',
  WorkflowStatus.readyForImplementation => 'Plan ready',
  WorkflowStatus.implementing => 'Implementing',
  WorkflowStatus.readyForReview => 'Ready for review',
  WorkflowStatus.reviewing => 'Reviewing',
  WorkflowStatus.changesRequested => 'Changes requested',
  WorkflowStatus.completed => 'Completed',
  WorkflowStatus.failed => 'Failed',
  WorkflowStatus.cancelled => 'Cancelled',
};

/// A compact colored label for a workflow status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final WorkflowStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (status) {
      WorkflowStatus.completed => (colors.primaryContainer, colors.onPrimaryContainer),
      WorkflowStatus.failed => (colors.errorContainer, colors.onErrorContainer),
      WorkflowStatus.cancelled || WorkflowStatus.pending => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
      _ => (colors.tertiaryContainer, colors.onTertiaryContainer),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(statusLabel(status), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
      ),
    );
  }
}
