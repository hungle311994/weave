import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

enum WeaveButtonVariant {
  /// Purple gradient, e.g. "Start workflow" or "Approve".
  primary,

  /// Raised surface with a border, e.g. "Cancel" or "Change…".
  secondary,

  /// Red outline for destructive actions, e.g. "Cancel workflow".
  danger,

  /// Text only, for low-emphasis actions.
  ghost,
}

enum WeaveButtonSize {
  /// 44 px, used on screens and in dialogs.
  regular,

  /// 32 px, used inside cards and the chat panel.
  small,
}

/// The design's button. A null [onPressed] disables it.
class WeaveButton extends StatelessWidget {
  const WeaveButton({required this.label, required this.onPressed, this.icon, this.variant = WeaveButtonVariant.secondary, this.size = WeaveButtonSize.regular, this.expand = false, super.key});

  const WeaveButton.primary({required this.label, required this.onPressed, this.icon, this.size = WeaveButtonSize.regular, this.expand = false, super.key}) : variant = WeaveButtonVariant.primary;

  const WeaveButton.danger({required this.label, required this.onPressed, this.icon, this.size = WeaveButtonSize.regular, this.expand = false, super.key}) : variant = WeaveButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final WeaveIcons? icon;
  final WeaveButtonVariant variant;
  final WeaveButtonSize size;

  /// Fills the available width instead of hugging the label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bool regular = size == WeaveButtonSize.regular;
    final bool enabled = onPressed != null;
    final BorderRadius radius = regular ? WeaveRadii.controlAll : WeaveRadii.mdAll;
    final (Color? background, Gradient? gradient, Color? border, Color foreground) = switch (variant) {
      WeaveButtonVariant.primary => (null, WeaveGradients.primary, WeaveColors.purple, WeaveColors.onAccent),
      WeaveButtonVariant.secondary => (WeaveColors.surfaceRaised, null, WeaveColors.border, WeaveColors.textPrimary),
      WeaveButtonVariant.danger => (WeaveColors.redSurface, null, WeaveColors.redStrong, WeaveColors.red),
      WeaveButtonVariant.ghost => (null, null, null, WeaveColors.textSecondary),
    };
    final TextStyle text = (regular ? WeaveTypography.label : WeaveTypography.caption.copyWith(fontWeight: variant == WeaveButtonVariant.primary ? WeaveTypography.semiBold : WeaveTypography.medium)).copyWith(color: foreground);

    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        // The decoration sits under a transparent Material so hover and focus
        // overlays paint on top without the border padding Ink would add.
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            gradient: gradient,
            borderRadius: radius,
            border: border == null ? null : Border.all(color: border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: radius,
              splashFactory: NoSplash.splashFactory,
              hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
              highlightColor: WeaveColors.onAccent.withValues(alpha: 0.04),
              focusColor: WeaveColors.purple.withValues(alpha: 0.22),
              child: SizedBox(
                height: regular ? WeaveLayout.controlHeight : 32,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: regular ? WeaveSpacing.s20 : WeaveSpacing.s12),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (icon != null) ...<Widget>[
                        WeaveIcon(icon!, size: regular ? 18 : 14, color: foreground),
                        SizedBox(width: regular ? WeaveSpacing.s10 : WeaveSpacing.s6),
                      ],
                      Flexible(
                        child: Text(label, style: text, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
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
