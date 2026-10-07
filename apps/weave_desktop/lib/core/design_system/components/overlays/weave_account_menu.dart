import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../navigation/weave_account_button.dart';

/// Actions exposed by the local account menu.
enum WeaveAccountAction {
  /// Opens application settings.
  settings,
}

/// Account summary and the actions that currently exist in Weave.
class WeaveAccountMenu extends StatelessWidget {
  const WeaveAccountMenu({required this.name, required this.onSelected, super.key});

  final String name;
  final ValueChanged<WeaveAccountAction> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: WeaveLayout.accountMenuWidth,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: WeaveColors.surfaceElevated,
        borderRadius: WeaveRadii.panelAll,
        border: Border.all(color: WeaveColors.borderSubtle),
        boxShadow: WeaveShadows.popover,
      ),
      child: Padding(
        padding: const EdgeInsets.all(WeaveSpacing.s12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                WeaveAvatar(name: name),
                const SizedBox(width: WeaveSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(name, style: WeaveTypography.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Local profile', style: WeaveTypography.caption),
                    ],
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: WeaveSpacing.s10),
              child: Divider(),
            ),
            Semantics(
              button: true,
              label: 'Settings, Command comma',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => onSelected(WeaveAccountAction.settings),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: WeaveRadii.controlAll,
                  splashFactory: NoSplash.splashFactory,
                  hoverColor: WeaveColors.onAccent.withValues(alpha: 0.06),
                  focusColor: WeaveColors.purple.withValues(alpha: 0.22),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s12, vertical: WeaveSpacing.s10),
                    child: Row(
                      children: <Widget>[
                        const WeaveIcon(WeaveIcons.settings, size: WeaveSpacing.s20),
                        const SizedBox(width: WeaveSpacing.s12),
                        Expanded(child: Text('Settings', style: WeaveTypography.bodyStrong)),
                        Text('⌘,', style: WeaveTypography.caption),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens the account menu above its sidebar [anchor].
Future<WeaveAccountAction?> showWeaveAccountMenu({required BuildContext context, required Rect anchor, required String name}) {
  final Size viewport = MediaQuery.sizeOf(context);
  final double left = math.max(WeaveSpacing.s8, math.min(anchor.left, viewport.width - WeaveLayout.accountMenuWidth - WeaveSpacing.s8));
  return showGeneralDialog<WeaveAccountAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss account menu',
    barrierColor: WeaveColors.canvas.withValues(alpha: 0),
    transitionDuration: WeaveMotion.fast,
    pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => Stack(
      children: <Widget>[
        Positioned(
          left: left,
          bottom: viewport.height - anchor.top + WeaveSpacing.s4,
          child: Material(
            type: MaterialType.transparency,
            child: WeaveAccountMenu(name: name, onSelected: (WeaveAccountAction action) => Navigator.of(context).pop<WeaveAccountAction>(action)),
          ),
        ),
      ],
    ),
  );
}
