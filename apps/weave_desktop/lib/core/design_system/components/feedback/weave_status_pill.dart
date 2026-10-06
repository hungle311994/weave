import 'package:flutter/widgets.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import 'weave_tone.dart';

/// A 26 px status pill with a dot, e.g. "● Ready" or "● Needs review".
class WeaveStatusPill extends StatelessWidget {
  const WeaveStatusPill({required this.label, required this.tone, super.key});

  final String label;
  final WeaveTone tone;

  @override
  Widget build(BuildContext context) => Container(
    height: WeaveLayout.statusPillHeight,
    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12),
    decoration: BoxDecoration(
      color: WeaveColors.tint(tone.color),
      borderRadius: WeaveRadii.pillAll,
      border: Border.all(color: WeaveColors.tintBorder(tone.color)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: WeaveSpacing.s8),
        Text(
          label,
          style: WeaveTypography.caption.copyWith(fontWeight: WeaveTypography.semiBold, color: tone.color),
        ),
      ],
    ),
  );
}
