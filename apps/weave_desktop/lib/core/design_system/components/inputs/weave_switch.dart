import 'package:flutter/material.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

/// A binary switch for settings that users can actually configure.
class WeaveSwitch extends StatelessWidget {
  const WeaveSwitch({required this.value, required this.onChanged, required this.semanticLabel, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: value ? WeaveColors.settingEnabled : WeaveColors.surface,
            borderRadius: WeaveRadii.pillAll,
            border: Border.all(color: value ? WeaveColors.green : WeaveColors.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? () => onChanged!(!value) : null,
              mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              borderRadius: WeaveRadii.pillAll,
              splashFactory: NoSplash.splashFactory,
              hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
              focusColor: WeaveColors.purple.withValues(alpha: 0.22),
              child: SizedBox(
                width: WeaveLayout.switchWidth,
                height: WeaveLayout.switchHeight,
                child: Padding(
                  padding: const EdgeInsets.all(WeaveSpacing.s2),
                  child: AnimatedAlign(
                    duration: WeaveMotion.fast,
                    curve: WeaveMotion.curve,
                    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: WeaveColors.onAccent, shape: BoxShape.circle),
                      child: SizedBox.square(dimension: WeaveLayout.switchThumbSize),
                    ),
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
