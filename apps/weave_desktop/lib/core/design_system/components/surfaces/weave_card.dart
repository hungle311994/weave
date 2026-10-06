import 'package:flutter/material.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

enum WeaveSurface {
  /// Gradient card with a drop shadow, e.g. "Execution timeline".
  card,

  /// Flat control background, e.g. the workspace selector.
  field,

  /// Recessed area inside a card, e.g. a context chip row.
  sunken,

  /// Option row in a dialog.
  elevated,

  /// The selected option row in a dialog.
  selected,
}

/// A bordered box in one of the design's [WeaveSurface]s. With [onTap] it
/// becomes a selectable row (hover, focus and keyboard activation included).
class WeaveCard extends StatelessWidget {
  const WeaveCard({required this.child, this.surface = WeaveSurface.card, this.padding = const EdgeInsets.all(WeaveSpacing.s24), this.radius, this.borderColor, this.onTap, super.key});

  final Widget child;
  final WeaveSurface surface;
  final EdgeInsetsGeometry padding;

  /// Defaults to 14 px for cards and 10 px for the other surfaces.
  final double? radius;

  /// Overrides the surface border, e.g. with an accent for the selected item.
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(radius ?? (surface == WeaveSurface.card ? WeaveRadii.panel : WeaveRadii.control));
    final (Color? color, Gradient? gradient, Color border, List<BoxShadow>? shadow) = switch (surface) {
      WeaveSurface.card => (null, WeaveGradients.card, WeaveColors.border, WeaveShadows.card),
      WeaveSurface.field => (WeaveColors.surface, null, WeaveColors.border, null),
      WeaveSurface.sunken => (WeaveColors.surfaceSunken, null, WeaveColors.borderSubtle, null),
      WeaveSurface.elevated => (WeaveColors.surfaceElevated, null, WeaveColors.borderDialog, null),
      WeaveSurface.selected => (WeaveColors.surfaceSelected, null, WeaveColors.purple, null),
    };
    final BoxDecoration decoration = BoxDecoration(
      color: color,
      gradient: gradient,
      borderRadius: corners,
      border: Border.all(color: borderColor ?? border),
      boxShadow: shadow,
    );
    final Widget content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: decoration,
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: corners,
                splashFactory: NoSplash.splashFactory,
                hoverColor: WeaveColors.onAccent.withValues(alpha: 0.04),
                focusColor: WeaveColors.purple.withValues(alpha: 0.18),
                child: content,
              ),
            ),
    );
  }
}
