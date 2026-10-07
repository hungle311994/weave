import 'package:flutter/widgets.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import 'weave_tone.dart';

/// A small borderless label, e.g. "3 folders", "Implementer" or "Modified".
class WeaveBadge extends StatelessWidget {
  const WeaveBadge({required this.label, this.tone = WeaveTone.accent, this.color, this.icon, super.key});

  final String label;
  final WeaveTone tone;

  /// Overrides [tone], e.g. with an agent's brand colour.
  final Color? color;
  final WeaveIcons? icon;

  @override
  Widget build(BuildContext context) {
    final Color base = color ?? tone.color;
    final Color foreground = color ?? tone.foreground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s8, vertical: WeaveSpacing.s2),
      decoration: BoxDecoration(color: WeaveColors.tint(base, 0.16), borderRadius: WeaveRadii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[WeaveIcon(icon!, size: 11, color: foreground), const SizedBox(width: WeaveSpacing.s4)],
          Text(label, style: WeaveTypography.micro.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

/// A 16 px purple circle with a count, e.g. the folder count on the collapsed rail.
class WeaveCountBubble extends StatelessWidget {
  const WeaveCountBubble({required this.count, super.key}) : planStep = false;

  /// Number marker used by an item in the Plan Approval screen.
  const WeaveCountBubble.plan({required this.count, super.key}) : planStep = true;

  final int count;
  final bool planStep;

  @override
  Widget build(BuildContext context) {
    final Widget label = Text(
      count > 99 ? '99+' : '$count',
      style: (planStep ? WeaveTypography.caption : WeaveTypography.micro.copyWith(fontSize: 9)).copyWith(fontWeight: WeaveTypography.semiBold, color: WeaveColors.onAccent, height: 1.2),
    );
    if (planStep) {
      return SizedBox.square(
        dimension: WeaveSpacing.s32,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: WeaveColors.surfaceSelected,
            borderRadius: WeaveRadii.pillAll,
            border: Border.all(color: WeaveColors.purple),
          ),
          child: Center(child: label),
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: WeaveSpacing.s16, minHeight: WeaveSpacing.s16),
      padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s4),
      decoration: const BoxDecoration(color: WeaveColors.purple, borderRadius: WeaveRadii.pillAll),
      alignment: Alignment.center,
      child: label,
    );
  }
}
