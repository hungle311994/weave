import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../buttons/weave_icon_button.dart';

/// The shared dialog frame used by Weave flows.
class WeaveDialog extends StatelessWidget {
  const WeaveDialog({required this.title, required this.body, this.subtitle, this.actions = const <Widget>[], this.accent = WeaveColors.purple, this.onClose, super.key});

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Color accent;

  /// Defaults to popping the current route.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final VoidCallback close = onClose ?? () => Navigator.of(context).maybePop();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{const SingleActivator(LogicalKeyboardKey.escape): close},
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: title,
          child: SizedBox(
            width: WeaveLayout.dialogWidth,
            height: WeaveLayout.dialogHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: WeaveColors.surface,
                borderRadius: WeaveRadii.dialogAll,
                border: Border.all(color: WeaveColors.borderStrong),
                boxShadow: WeaveShadows.dialog(accent),
              ),
              child: ClipRRect(
                borderRadius: WeaveRadii.dialogAll,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(WeaveSpacing.s24, WeaveSpacing.s20, WeaveSpacing.s24, WeaveSpacing.s20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(title, style: WeaveTypography.titleLarge),
                                if (subtitle != null) ...<Widget>[const SizedBox(height: WeaveSpacing.s2), Text(subtitle!, style: WeaveTypography.bodySmall)],
                              ],
                            ),
                          ),
                          WeaveIconButton(icon: WeaveIcons.close, tooltip: 'Close dialog', onPressed: close),
                        ],
                      ),
                      const SizedBox(height: WeaveSpacing.s24),
                      Expanded(child: SingleChildScrollView(primary: true, child: body)),
                      if (actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: WeaveSpacing.s20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions
                              .map<Widget>(
                                (Widget action) => Padding(
                                  padding: const EdgeInsets.only(left: WeaveSpacing.s12),
                                  child: action,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
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

/// Shows a modal [WeaveDialog] with closed-loop focus traversal.
Future<T?> showWeaveDialog<T>({required BuildContext context, required String title, required Widget body, String? subtitle, List<Widget> actions = const <Widget>[], Color accent = WeaveColors.purple, bool barrierDismissible = true}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  requestFocus: true,
  builder: (BuildContext context) => Dialog(
    backgroundColor: WeaveColors.surface.withValues(alpha: 0),
    elevation: 0,
    insetPadding: const EdgeInsets.all(WeaveSpacing.s24),
    child: WeaveDialog(title: title, subtitle: subtitle, body: body, actions: actions, accent: accent),
  ),
);
