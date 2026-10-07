import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../overlays/weave_tooltip.dart';

/// A 48 px sidebar destination, rendered as a labelled row or icon rail item.
class WeaveNavigationItem extends StatelessWidget {
  const WeaveNavigationItem({required this.label, required this.icon, required this.onPressed, required this.expanded, this.selected = false, this.tooltip = true, super.key});

  final String label;
  final WeaveIcons icon;
  final VoidCallback? onPressed;
  final bool expanded;
  final bool selected;

  /// Whether the rail item names itself in a tooltip on hover; off when
  /// hovering it shows something richer, such as a floating sidebar.
  final bool tooltip;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Widget item = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: selected ? WeaveGradients.navSelected : null, borderRadius: WeaveRadii.controlAll),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              borderRadius: WeaveRadii.controlAll,
              splashFactory: NoSplash.splashFactory,
              hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
              focusColor: WeaveColors.purple.withValues(alpha: 0.22),
              child: SizedBox(
                height: WeaveLayout.sidebarItemHeight,
                width: expanded ? double.infinity : WeaveLayout.sidebarItemHeight,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s16),
                        child: Row(
                          children: <Widget>[
                            WeaveIcon(icon, size: WeaveSpacing.s24, color: WeaveColors.textSecondary),
                            const SizedBox(width: WeaveSpacing.s18),
                            Expanded(
                              child: Text(label, style: (selected ? WeaveTypography.titleSmall : WeaveTypography.bodyLarge), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      )
                    : Center(
                        child: WeaveIcon(icon, size: WeaveSpacing.s24, color: WeaveColors.textSecondary),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    return expanded || !tooltip ? item : WeaveTooltip(message: label, placement: WeaveTooltipPlacement.right, child: item);
  }
}
