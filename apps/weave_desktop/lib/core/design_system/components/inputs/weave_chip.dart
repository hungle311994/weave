import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

enum WeaveChipShape {
  /// 8 px corners on a recessed background, e.g. a context file in the composer.
  rounded,

  /// Fully rounded, e.g. a branch name.
  pill,
}

/// A compact label with an optional icon and remove button.
class WeaveChip extends StatelessWidget {
  const WeaveChip({required this.label, this.icon, this.onRemove, this.shape = WeaveChipShape.rounded, super.key});

  final String label;
  final WeaveIcons? icon;

  /// Shows a remove button when set.
  final VoidCallback? onRemove;
  final WeaveChipShape shape;

  @override
  Widget build(BuildContext context) {
    final bool pill = shape == WeaveChipShape.pill;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: pill ? WeaveSpacing.s10 : WeaveSpacing.s8, vertical: WeaveSpacing.s4),
      decoration: BoxDecoration(
        color: pill ? WeaveColors.panel : WeaveColors.surfaceSunken,
        borderRadius: pill ? WeaveRadii.pillAll : WeaveRadii.mdAll,
        border: Border.all(color: WeaveColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[WeaveIcon(icon!, size: 12, color: WeaveColors.textSecondary), const SizedBox(width: WeaveSpacing.s6)],
          Flexible(
            child: Text(
              label,
              style: WeaveTypography.caption.copyWith(fontWeight: WeaveTypography.medium, color: pill ? WeaveColors.textSecondary : WeaveColors.textBody),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null) ...<Widget>[
            const SizedBox(width: WeaveSpacing.s6),
            Tooltip(
              message: 'Remove $label',
              child: InkWell(
                onTap: onRemove,
                borderRadius: WeaveRadii.xsAll,
                splashFactory: NoSplash.splashFactory,
                child: const Padding(
                  padding: EdgeInsets.all(WeaveSpacing.s2),
                  child: WeaveIcon(WeaveIcons.close, size: 10, color: WeaveColors.textDisabled),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
