import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// Visual state of a workflow step.
enum WeaveStepStatus {
  /// The step completed successfully.
  done,

  /// The step is currently running.
  active,

  /// The step has not started.
  pending,

  /// The step stopped with an error.
  failed,
}

/// One entry in a [WeaveStepTimeline].
final class WeaveStep {
  const WeaveStep({required this.title, required this.subtitle, required this.status, this.child});

  final String title;
  final String subtitle;
  final WeaveStepStatus status;
  final Widget? child;
}

/// Vertical workflow timeline used by previews and live execution.
class WeaveStepTimeline extends StatelessWidget {
  const WeaveStepTimeline({required this.steps, super.key});

  final List<WeaveStep> steps;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: 'Workflow steps',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int index = 0; index < steps.length; index++) _TimelineRow(step: steps[index], index: index, last: index == steps.length - 1),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step, required this.index, required this.last});

  final WeaveStep step;
  final int index;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color border, Color foreground, WeaveIcons? icon) = switch (step.status) {
      WeaveStepStatus.done => (WeaveColors.surface, WeaveColors.green, WeaveColors.green, WeaveIcons.check),
      WeaveStepStatus.active => (WeaveColors.stepActive, WeaveColors.green, WeaveColors.green, null),
      WeaveStepStatus.pending => (WeaveColors.surface, WeaveColors.border, WeaveColors.textSecondary, null),
      WeaveStepStatus.failed => (WeaveColors.redSurface, WeaveColors.redStrong, WeaveColors.red, WeaveIcons.close),
    };
    return Semantics(
      container: true,
      label: 'Step ${index + 1}: ${step.title}, ${step.status.name}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: WeaveLayout.timelineMarkerSize,
              child: Column(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                      border: Border.all(color: border, width: WeaveLayout.timelineStrokeWidth),
                    ),
                    child: SizedBox.square(
                      dimension: WeaveLayout.timelineMarkerSize,
                      child: Center(
                        child: icon == null ? Text('${index + 1}', style: WeaveTypography.titleSmall.copyWith(color: foreground)) : WeaveIcon(icon, size: WeaveIconSize.compact, color: foreground),
                      ),
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: WeaveLayout.timelineStrokeWidth,
                        constraints: const BoxConstraints(minHeight: WeaveSpacing.s40),
                        color: WeaveColors.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: WeaveSpacing.s16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: WeaveSpacing.s6, bottom: last ? 0 : WeaveSpacing.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(step.title, style: WeaveTypography.titleSmall),
                    Text(step.subtitle, style: WeaveTypography.caption.copyWith(color: WeaveColors.textSecondary)),
                    if (step.child != null) ...<Widget>[const SizedBox(height: WeaveSpacing.s12), step.child!],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
