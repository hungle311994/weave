import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';

/// Circular initials for the local macOS user shown in the sidebar.
class WeaveAvatar extends StatelessWidget {
  const WeaveAvatar({required this.name, super.key});

  final String name;

  /// One initial for one word, otherwise the initials of the first two words.
  static String initialsFor(String name) {
    final List<String> words = name.trim().split(RegExp(r'\s+')).where((String word) => word.isNotEmpty).toList(growable: false);
    if (words.isEmpty) {
      return '?';
    }
    final Iterable<String> initials = words.take(2).map<String>((String word) => String.fromCharCode(word.runes.first).toUpperCase());
    return initials.join();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '$name avatar',
    child: SizedBox.square(
      dimension: WeaveLayout.accountAvatarSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: WeaveColors.purple, shape: BoxShape.circle),
        child: Center(
          child: Text(initialsFor(name), style: WeaveTypography.bodyStrong.copyWith(color: WeaveColors.onAccent)),
        ),
      ),
    ),
  );
}

/// Sidebar footer control that keeps the avatar visible in both layouts.
class WeaveAccountButton extends StatelessWidget {
  const WeaveAccountButton({required this.name, required this.expanded, required this.onPressed, super.key});

  final String name;
  final bool expanded;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Open account menu for $name',
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: expanded ? WeaveSpacing.s8 : WeaveSpacing.s4, vertical: WeaveSpacing.s4),
                child: Row(
                  mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                  children: <Widget>[
                    WeaveAvatar(name: name),
                    if (expanded) ...<Widget>[
                      const SizedBox(width: WeaveSpacing.s10),
                      Expanded(
                        child: Text(name, style: WeaveTypography.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: WeaveSpacing.s6),
                      const WeaveIcon(WeaveIcons.chevronUp, size: WeaveIconSize.checkbox, color: WeaveColors.textSecondary),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
