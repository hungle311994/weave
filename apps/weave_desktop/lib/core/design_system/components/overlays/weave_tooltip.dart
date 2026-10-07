import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../tokens/weave_spacing.dart';

/// Where a [WeaveTooltip] appears relative to its element.
enum WeaveTooltipPlacement {
  /// Below the element, or above it when there is no room below.
  below,

  /// To the right, vertically centred — used by the collapsed sidebar rail.
  right,
}

/// A tooltip that consistently uses the Weave tooltip theme and keeps a gap
/// from the element's edge (Material measures its offset from the centre, so a
/// 48 px item would touch its tooltip).
class WeaveTooltip extends StatelessWidget {
  const WeaveTooltip({required this.message, required this.child, this.placement = WeaveTooltipPlacement.below, super.key});

  final String message;
  final Widget child;
  final WeaveTooltipPlacement placement;

  @override
  Widget build(BuildContext context) => Tooltip(message: message, positionDelegate: (TooltipPositionContext position) => positionFor(position, placement), child: child);

  /// The tooltip's top-left corner in the overlay for [placement].
  static Offset positionFor(TooltipPositionContext position, WeaveTooltipPlacement placement) {
    const double margin = WeaveLayout.tooltipScreenMargin;
    if (placement == WeaveTooltipPlacement.right) {
      final double targetEdge = position.target.dx + position.targetSize.width / 2;
      final double x = targetEdge + WeaveLayout.railTooltipGap;
      if (x + position.tooltipSize.width <= position.overlaySize.width - margin) {
        final double maxY = math.max(margin, position.overlaySize.height - position.tooltipSize.height - margin);
        return Offset(x, (position.target.dy - position.tooltipSize.height / 2).clamp(margin, maxY));
      }
    }
    return positionDependentBox(
      size: position.overlaySize,
      childSize: position.tooltipSize,
      target: position.target,
      verticalOffset: position.targetSize.height / 2 + WeaveLayout.tooltipGap,
      preferBelow: position.preferBelow,
      margin: margin,
    );
  }
}
