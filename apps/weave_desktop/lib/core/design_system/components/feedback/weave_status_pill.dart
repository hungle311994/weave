import 'package:flutter/widgets.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import 'weave_tone.dart';

/// A 26 px status pill with a dot, e.g. "● Ready" or "● Needs review".
class WeaveStatusPill extends StatelessWidget {
  const WeaveStatusPill({required this.label, required this.tone, super.key}) : compact = false;

  /// A smaller status for dense card metadata.
  const WeaveStatusPill.compact({required this.label, required this.tone, super.key}) : compact = true;

  final String label;
  final WeaveTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? WeaveLayout.compactStatusPillHeight : WeaveLayout.statusPillHeight,
    padding: EdgeInsets.symmetric(horizontal: compact ? WeaveSpacing.s8 : WeaveSpacing.s12),
    decoration: BoxDecoration(
      color: WeaveColors.tint(tone.color),
      borderRadius: WeaveRadii.pillAll,
      border: Border.all(color: WeaveColors.tintBorder(tone.color)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: compact ? WeaveSpacing.s6 : 7,
          height: compact ? WeaveSpacing.s6 : 7,
          decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle),
        ),
        SizedBox(width: compact ? WeaveSpacing.s6 : WeaveSpacing.s8),
        Text(
          label,
          style: (compact ? WeaveTypography.micro : WeaveTypography.caption).copyWith(fontWeight: WeaveTypography.semiBold, color: tone.color),
        ),
      ],
    ),
  );
}
