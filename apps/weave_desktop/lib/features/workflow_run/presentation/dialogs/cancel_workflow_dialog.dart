import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Confirms stopping a run without making claims about worktrees or resume.
Future<bool> showCancelWorkflowDialog(BuildContext context) async =>
    await showWeaveDialog<bool>(
      context: context,
      title: 'Cancel this workflow?',
      subtitle: 'Active agent work will stop. Uncommitted repository changes are not discarded.',
      barrierDismissible: false,
      body: const Column(
        children: <Widget>[
          _CancelFact(icon: WeaveIcons.stop, title: 'Workflow stops', subtitle: 'This run cannot be resumed after cancellation.'),
          SizedBox(height: WeaveSpacing.s12),
          _CancelFact(icon: WeaveIcons.fileCode, title: 'Working tree preserved', subtitle: 'Existing uncommitted changes remain in the repository.'),
          SizedBox(height: WeaveSpacing.s12),
          _CancelFact(icon: WeaveIcons.gitBranch, title: 'Nothing is pushed', subtitle: 'Weave never pushes repository changes.'),
        ],
      ),
      actions: <Widget>[
        WeaveButton(label: 'Keep running', onPressed: () => Navigator.of(context).pop(false)),
        WeaveButton.danger(key: const Key('cancel-confirm'), label: 'Cancel workflow', onPressed: () => Navigator.of(context).pop(true)),
      ],
    ) ??
    false;

class _CancelFact extends StatelessWidget {
  const _CancelFact({required this.icon, required this.title, required this.subtitle});

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
