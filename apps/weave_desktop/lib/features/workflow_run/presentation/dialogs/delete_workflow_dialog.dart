import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:weave_core/weave_core.dart';

import '../../../../core/design_system/design_system.dart';

/// Confirms deleting a workflow's history; says plainly that the repository
/// and its uncommitted changes stay as they are.
Future<bool> showDeleteWorkflowDialog(BuildContext context, {required WorkflowTask task}) async =>
    await showWeaveDialog<bool>(
      context: context,
      title: 'Delete this workflow?',
      subtitle: task.request.split('\n').first,
      accent: WeaveColors.redStrong,
      body: Column(
        children: <Widget>[
          const _DeleteFact(icon: WeaveIcons.history, title: 'Weave history is removed', subtitle: 'Its plan, activity log, reviews and settings are deleted from Weave.'),
          const SizedBox(height: WeaveSpacing.s12),
          _DeleteFact(icon: WeaveIcons.folder, title: 'Repository untouched', subtitle: 'Files and uncommitted changes in ${path.basename(task.repositoryPath)} stay as they are.'),
          const SizedBox(height: WeaveSpacing.s12),
          const _DeleteFact(icon: WeaveIcons.alertTriangle, title: 'Cannot be undone', subtitle: 'The workflow cannot be reopened or resumed afterwards.'),
        ],
      ),
      actions: <Widget>[
        WeaveButton(key: const Key('delete-keep'), label: 'Keep', onPressed: () => Navigator.of(context).pop(false)),
        WeaveButton.danger(key: const Key('delete-confirm'), label: 'Delete workflow', onPressed: () => Navigator.of(context).pop(true)),
      ],
    ) ??
    false;

class _DeleteFact extends StatelessWidget {
  const _DeleteFact({required this.icon, required this.title, required this.subtitle});

  final WeaveIcons icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => WeaveCard(
    surface: WeaveSurface.elevated,
    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
    child: Row(
      children: <Widget>[
        WeaveIcon(icon, size: WeaveSpacing.s24, color: WeaveColors.red),
        const SizedBox(width: WeaveSpacing.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: WeaveTypography.bodyStrong),
              Text(subtitle, style: WeaveTypography.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Asks for confirmation, then deletes [task]; reports a failure as a toast.
Future<void> confirmAndDeleteWorkflow(BuildContext context, {required WorkflowTask task, required Future<void> Function(String taskId) delete}) async {
  if (!await showDeleteWorkflowDialog(context, task: task) || !context.mounted) {
    return;
  }
  try {
    await delete(task.id);
  } on Object catch (error) {
    if (context.mounted) {
      showWeaveToast(context, message: error is StateError ? error.message : 'Could not delete the workflow: $error', tone: WeaveToastTone.danger);
    }
  }
}
