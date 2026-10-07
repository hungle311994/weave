import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';

/// A 16 px checkbox used by selectable file lists.
class WeaveCheckbox extends StatelessWidget {
  const WeaveCheckbox({required this.value, required this.onChanged, required this.semanticLabel, super.key});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      label: semanticLabel,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: value ? WeaveColors.purple : WeaveColors.surface,
            borderRadius: WeaveRadii.xsAll,
            border: value ? null : Border.all(color: WeaveColors.border),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? () => onChanged!(!value) : null,
              mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
              borderRadius: WeaveRadii.xsAll,
              splashFactory: NoSplash.splashFactory,
              hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
              focusColor: WeaveColors.purple.withValues(alpha: 0.22),
              child: SizedBox.square(
                dimension: WeaveLayout.checkboxSize,
                child: value
                    ? const Center(
                        child: WeaveIcon(WeaveIcons.check, size: WeaveIconSize.checkbox, color: WeaveColors.onAccent),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
