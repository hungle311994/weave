import 'package:flutter/widgets.dart';
import 'package:weave_agents/weave_agents.dart';

import '../../../../core/design_system/design_system.dart';

/// One selectable role in the New Task agent pipeline.
class AgentPipelineCard extends StatelessWidget {
  const AgentPipelineCard({required this.number, required this.roleLabel, required this.agent, required this.model, required this.available, required this.onTap, this.onClear, this.hasError = false, super.key});

  final int number;
  final String roleLabel;
  final AgentAdapter? agent;
  final String? model;
  final bool available;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool hasError;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: WeaveLayout.newTaskAgentCardHeight,
    child: WeaveCard(
      padding: const EdgeInsets.all(WeaveSpacing.s14),
      borderColor: hasError ? WeaveColors.red : null,
      onTap: onTap,
      child: Column(
        children: <Widget>[
          // Fixed height and a reserved slot for the remove button, so the
          // number and role line up across cards with and without an agent.
          SizedBox(
            height: WeaveLayout.statusPillHeight,
            child: Row(
              children: <Widget>[
                WeaveBadge(label: '$number'),
                const SizedBox(width: WeaveSpacing.s12),
                Expanded(
                  child: Text(roleLabel, style: WeaveTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: WeaveSpacing.s8),
                SizedBox.square(
                  dimension: WeaveLayout.statusPillHeight,
                  child: onClear == null
                      ? null
                      : WeaveIconButton(
                          key: Key('clear-agent-${roleLabel.toLowerCase().replaceAll(' & ', '-').replaceAll(' ', '-')}'),
                          icon: WeaveIcons.close,
                          tooltip: 'Remove $roleLabel agent',
                          onPressed: onClear,
                          size: WeaveLayout.statusPillHeight,
                          iconSize: WeaveSpacing.s14,
                        ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              const WeaveCard(
                surface: WeaveSurface.sunken,
                padding: EdgeInsets.all(WeaveSpacing.s8),
                child: WeaveIcon(WeaveIcons.bot, size: WeaveSpacing.s24),
              ),
              const SizedBox(width: WeaveSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(agent?.displayName ?? 'Select agent', style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(model?.isNotEmpty == true ? model! : 'Default model', style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: WeaveSpacing.s8),
              WeaveStatusPill.compact(
                label: hasError
                    ? 'Required'
                    : agent == null
                    ? 'Choose'
                    : available
                    ? 'Ready'
                    : 'Setup',
                tone: hasError
                    ? WeaveTone.danger
                    : agent == null
                    ? WeaveTone.neutral
                    : available
                    ? WeaveTone.success
                    : WeaveTone.warning,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
