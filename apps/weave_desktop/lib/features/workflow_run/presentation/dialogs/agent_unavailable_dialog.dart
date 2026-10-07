import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weave_workflow/weave_workflow.dart';

import '../../../../core/design_system/design_system.dart';

/// Decision made from an authentication or connection/quota interruption.
enum AgentUnavailableDecision {
  /// Retry the same workflow step.
  retry,

  /// End the workflow.
  cancel,
}

/// Shows the product-appropriate recovery dialog for [checkpoint].
Future<AgentUnavailableDecision?> showAgentUnavailableDialog({required BuildContext context, required WorkflowCheckpoint checkpoint}) {
  final RegExp commandPattern = RegExp(r'Run `([^`]+)` in Terminal');
  final RegExpMatch? match = commandPattern.firstMatch(checkpoint.details);
  final String? signInCommand = match?.group(1);
  return signInCommand == null ? _showConnectionDialog(context, checkpoint) : _showAuthenticationDialog(context, checkpoint, signInCommand);
}

Future<AgentUnavailableDecision?> _showAuthenticationDialog(BuildContext context, WorkflowCheckpoint checkpoint, String signInCommand) => showWeaveDialog<AgentUnavailableDecision>(
  context: context,
  title: checkpoint.title,
  subtitle: 'Use the agent\'s own secure sign-in flow, then retry this step.',
  barrierDismissible: false,
  body: Column(
    children: <Widget>[
      const _RecoveryFact(icon: WeaveIcons.shield, title: 'Agent-managed sign-in', subtitle: 'Weave never asks for or stores your password.'),
      const SizedBox(height: WeaveSpacing.s12),
      _RecoveryFact(icon: WeaveIcons.terminal, title: 'Run in Terminal', subtitle: signInCommand),
      const SizedBox(height: WeaveSpacing.s12),
      const _RecoveryFact(icon: WeaveIcons.refresh, title: 'Retry after sign-in', subtitle: 'Weave checks the agent again before continuing.'),
    ],
  ),
  actions: <Widget>[
    WeaveButton.danger(key: const Key('agent-unavailable-cancel'), label: 'Cancel workflow', onPressed: () => Navigator.of(context).pop(AgentUnavailableDecision.cancel)),
    WeaveButton(
      label: 'Copy sign-in command',
      icon: WeaveIcons.terminal,
      onPressed: () => Clipboard.setData(ClipboardData(text: signInCommand)),
    ),
    WeaveButton.primary(key: const Key('agent-retry'), label: 'Retry', icon: WeaveIcons.refresh, onPressed: () => Navigator.of(context).pop(AgentUnavailableDecision.retry)),
  ],
);

Future<AgentUnavailableDecision?> _showConnectionDialog(BuildContext context, WorkflowCheckpoint checkpoint) => showWeaveDialog<AgentUnavailableDecision>(
  context: context,
  title: 'Connection or quota interrupted',
  subtitle: 'The workflow is waiting safely at its current checkpoint.',
  barrierDismissible: false,
  body: Column(
    children: <Widget>[
      _RecoveryFact(icon: WeaveIcons.alertTriangle, title: checkpoint.title, subtitle: checkpoint.details),
      const SizedBox(height: WeaveSpacing.s12),
      const _RecoveryFact(icon: WeaveIcons.refresh, title: 'Retry strategy', subtitle: 'Retry when the connection or usage limit is available again.'),
      const SizedBox(height: WeaveSpacing.s12),
      const _RecoveryFact(icon: WeaveIcons.bot, title: 'Fallback agents', subtitle: 'Configured fallbacks are tried automatically before Weave asks you.'),
    ],
  ),
  actions: <Widget>[
    WeaveButton.danger(key: const Key('agent-unavailable-cancel'), label: 'Cancel workflow', onPressed: () => Navigator.of(context).pop(AgentUnavailableDecision.cancel)),
    WeaveButton.primary(key: const Key('agent-retry'), label: 'Retry now', icon: WeaveIcons.refresh, onPressed: () => Navigator.of(context).pop(AgentUnavailableDecision.retry)),
  ],
);

class _RecoveryFact extends StatelessWidget {
  const _RecoveryFact({required this.icon, required this.title, required this.subtitle});

  final WeaveIcons icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => WeaveCard(
    surface: WeaveSurface.elevated,
    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16, vertical: WeaveSpacing.s12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WeaveIcon(icon, size: WeaveSpacing.s24, color: WeaveColors.amber),
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
