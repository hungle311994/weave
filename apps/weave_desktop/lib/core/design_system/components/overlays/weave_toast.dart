import 'dart:async';

import 'package:flutter/material.dart';

import '../../icons/weave_icons.dart';
import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../buttons/weave_icon_button.dart';
import '../surfaces/weave_card.dart';

/// Visual meaning of a short-lived [WeaveToast].
enum WeaveToastTone {
  /// A completed action such as copying a setup command.
  success,

  /// Neutral progress or information.
  info,

  /// An action that failed and may need attention.
  danger,
}

/// A compact app notification designed for the bottom-right overlay.
class WeaveToast extends StatelessWidget {
  const WeaveToast({required this.message, required this.tone, required this.onDismiss, super.key});

  final String message;
  final WeaveToastTone tone;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (WeaveIcons icon, Color color) = switch (tone) {
      WeaveToastTone.success => (WeaveIcons.checkCircle, WeaveColors.green),
      WeaveToastTone.info => (WeaveIcons.info, WeaveColors.purpleSoft),
      WeaveToastTone.danger => (WeaveIcons.alertTriangle, WeaveColors.red),
    };
    return Material(
      type: MaterialType.transparency,
      child: WeaveCard(
        surface: WeaveSurface.elevated,
        padding: const EdgeInsets.all(WeaveSpacing.s16),
        borderColor: color,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WeaveIcon(icon, color: color),
            const SizedBox(width: WeaveSpacing.s12),
            Flexible(
              child: Semantics(
                liveRegion: true,
                label: message,
                excludeSemantics: true,
                child: Text(message, style: WeaveTypography.bodyStrong),
              ),
            ),
            const SizedBox(width: WeaveSpacing.s12),
            WeaveIconButton(icon: WeaveIcons.close, tooltip: 'Dismiss notification', onPressed: onDismiss, size: WeaveSpacing.s32, iconSize: WeaveIconSize.compact),
          ],
        ),
      ),
    );
  }
}

/// Handle returned by [showWeaveToast] for early dismissal.
final class WeaveToastController {
  WeaveToastController._(this._entry, this._toastKey, this._onDismiss);

  final OverlayEntry _entry;
  final GlobalKey<_TimedWeaveToastState> _toastKey;
  final VoidCallback _onDismiss;
  bool _dismissed = false;
  bool _removed = false;

  void dismiss() {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    final _TimedWeaveToastState? toast = _toastKey.currentState;
    if (toast == null) {
      _remove();
      return;
    }
    toast.dismiss();
  }

  void _remove() {
    if (_removed) {
      return;
    }
    _removed = true;
    _entry.remove();
    _entry.dispose();
    _onDismiss();
  }
}

class _TimedWeaveToast extends StatefulWidget {
  const _TimedWeaveToast({required this.message, required this.tone, required this.duration, required this.onDismiss, super.key});

  final String message;
  final WeaveToastTone tone;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<_TimedWeaveToast> createState() => _TimedWeaveToastState();
}

class _TimedWeaveToastState extends State<_TimedWeaveToast> {
  bool _dismissing = false;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, dismiss);
  }

  Future<void> dismiss() async {
    if (_dismissing) {
      return;
    }
    _dismissing = true;
    _timer.cancel();
    if (mounted) {
      setState(() {});
      await Future<void>.delayed(WeaveMotion.standard);
    }
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _dismissing ? 0 : 1,
    duration: WeaveMotion.standard,
    curve: WeaveMotion.curve,
    child: AnimatedSlide(
      // Exit travels back toward the same top edge used by the entrance.
      offset: _dismissing ? const Offset(0, -0.2) : Offset.zero,
      duration: WeaveMotion.standard,
      curve: WeaveMotion.curve,
      child: WeaveToast(message: widget.message, tone: widget.tone, onDismiss: dismiss),
    ),
  );
}

final Expando<WeaveToastController> _activeToasts = Expando<WeaveToastController>();

/// Shows one toast at the top centre of the app, below the window buttons,
/// where it never covers a page's primary action (e.g. Start workflow at the
/// bottom right). A new toast replaces the current one, and installers or
/// other commands are never run from here.
WeaveToastController showWeaveToast(
  BuildContext context, {
  required String message,
  WeaveToastTone tone = WeaveToastTone.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final OverlayState overlay = Overlay.of(context);
  _activeToasts[overlay]?.dismiss();
  final GlobalKey<_TimedWeaveToastState> toastKey = GlobalKey<_TimedWeaveToastState>();
  late final WeaveToastController controller;
  final OverlayEntry entry = OverlayEntry(
    builder: (BuildContext context) => Positioned(
      top: WeaveLayout.toastTop,
      left: (MediaQuery.sizeOf(context).width - WeaveLayout.toastWidth) / 2,
      width: WeaveLayout.toastWidth,
      child: TweenAnimationBuilder<double>(
        duration: WeaveMotion.standard,
        curve: WeaveMotion.curve,
        tween: Tween<double>(begin: 0, end: 1),
        builder: (BuildContext context, double progress, Widget? child) => Opacity(
          opacity: progress,
          child: Transform.translate(offset: Offset(0, -WeaveSpacing.s16 * (1 - progress)), child: child),
        ),
        child: _TimedWeaveToast(key: toastKey, message: message, tone: tone, duration: duration, onDismiss: () => controller._remove()),
      ),
    ),
  );
  controller = WeaveToastController._(entry, toastKey, () {
    if (_activeToasts[overlay] == controller) {
      _activeToasts[overlay] = null;
    }
  });
  _activeToasts[overlay] = controller;
  overlay.insert(entry);
  return controller;
}
