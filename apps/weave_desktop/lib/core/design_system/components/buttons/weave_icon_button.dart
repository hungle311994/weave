import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../overlays/weave_tooltip.dart';

/// A square icon-only button with a tooltip, e.g. the sidebar toggle.
class WeaveIconButton extends StatelessWidget {
  const WeaveIconButton({required this.icon, required this.tooltip, required this.onPressed, this.size = 32, this.iconSize = 16, this.bordered = false, this.selected = false, this.color, this.tooltipPlacement = WeaveTooltipPlacement.below, super.key});

  final WeaveIcons icon;

  /// Shown on hover and read by screen readers.
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool bordered;
  final bool selected;
  final Color? color;
  final WeaveTooltipPlacement tooltipPlacement;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final BorderRadius radius = size >= 40 ? WeaveRadii.controlAll : WeaveRadii.mdAll;
    return WeaveTooltip(
      message: tooltip,
      placement: tooltipPlacement,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? WeaveColors.surfaceSelected : null,
              borderRadius: radius,
              border: bordered || selected ? Border.all(color: selected ? WeaveColors.purple : WeaveColors.borderSubtle) : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPressed,
                mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
                borderRadius: radius,
                splashFactory: NoSplash.splashFactory,
                hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
                focusColor: WeaveColors.purple.withValues(alpha: 0.22),
                child: SizedBox.square(
                  dimension: size,
                  child: Center(
                    child: WeaveIcon(icon, size: iconSize, color: color ?? (selected ? WeaveColors.textPrimary : WeaveColors.textSecondary)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
