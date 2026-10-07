import 'package:flutter/widgets.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';
import '../../tokens/weave_typography.dart';
import '../feedback/weave_tone.dart';

/// One usage limit as a labelled bar, e.g. "Current session · 28% · resets
/// Oct 7 at 8:10pm". The bar turns amber from 70 % and red from 90 %; its
/// fill grows to a new value, and a highlight sweeps it while [refreshing].
class WeaveUsageMeter extends StatelessWidget {
  const WeaveUsageMeter({required this.label, required this.percentUsed, this.detail, this.refreshing = false, super.key});

  final String label;
  final int percentUsed;

  /// The value is being re-read; shows a moving highlight on the bar.
  final bool refreshing;

  /// Shown under the bar, e.g. when the limit resets.
  final String? detail;

  /// Colour of the bar for [percentUsed].
  static WeaveTone toneFor(int percentUsed) => percentUsed >= 90
      ? WeaveTone.danger
      : percentUsed >= 70
      ? WeaveTone.warning
      : WeaveTone.success;

  @override
  Widget build(BuildContext context) {
    final WeaveTone tone = toneFor(percentUsed);
    final double fraction = (percentUsed / 100).clamp(0, 1).toDouble();
    return Semantics(
      label: '$label: $percentUsed percent used${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: WeaveTypography.bodySmall.copyWith(color: WeaveColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: WeaveSpacing.s8),
              Text(
                '$percentUsed%',
                style: WeaveTypography.bodySmall.copyWith(color: tone.foreground, fontWeight: WeaveTypography.semiBold),
              ),
            ],
          ),
          const SizedBox(height: WeaveSpacing.s6),
          ClipRRect(
            borderRadius: WeaveRadii.pillAll,
            child: SizedBox(
              height: WeaveLayout.usageMeterHeight,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: WeaveColors.borderSubtle),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // Grows from 0 the first time, then from the old value.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: fraction),
                      duration: WeaveMotion.slow,
                      curve: WeaveMotion.curve,
                      builder: (BuildContext context, double value, Widget? child) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(key: const Key('weave-usage-meter-fill'), widthFactor: value, heightFactor: 1, child: child),
                      ),
                      child: DecoratedBox(decoration: BoxDecoration(color: tone.color)),
                    ),
                    if (refreshing && !MediaQuery.disableAnimationsOf(context)) const _RefreshSweep(key: Key('weave-usage-meter-sweep')),
                  ],
                ),
              ),
            ),
          ),
          if (detail case final String text) ...<Widget>[
            const SizedBox(height: WeaveSpacing.s4),
            Text(text, style: WeaveTypography.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// A soft highlight that sweeps across the track while a value refreshes.
class _RefreshSweep extends StatefulWidget {
  const _RefreshSweep({super.key});

  @override
  State<_RefreshSweep> createState() => _RefreshSweepState();
}

class _RefreshSweepState extends State<_RefreshSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: WeaveMotion.sweep)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) => FractionallySizedBox(
      alignment: Alignment(-2.5 + 5 * _controller.value, 0),
      widthFactor: 0.4,
      child: child,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: <Color>[WeaveColors.onAccent.withValues(alpha: 0), WeaveColors.onAccent.withValues(alpha: 0.35), WeaveColors.onAccent.withValues(alpha: 0)]),
      ),
    ),
  );
}
