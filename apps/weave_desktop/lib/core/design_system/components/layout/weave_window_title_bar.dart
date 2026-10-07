import 'package:flutter/widgets.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_spacing.dart';

/// Full-width macOS title-bar surface behind the native window controls.
///
/// Keeping this surface independent from the columns below prevents their
/// dividers from running through the close, minimise, and zoom controls.
/// [leading] (e.g. back, forward and sidebar buttons) sits right of the
/// traffic lights. Given [trafficLightCenter], the bar is twice that tall,
/// so the traffic lights and [leading] share its centre line.
class WeaveWindowTitleBar extends StatelessWidget {
  const WeaveWindowTitleBar({this.leading, this.trafficLightCenter, super.key});

  final Widget? leading;

  /// Distance from the window top to the traffic lights' centre, from macOS.
  final double? trafficLightCenter;

  /// The bar height for [trafficLightCenter], or the default when unknown.
  static double heightFor(double? trafficLightCenter) => trafficLightCenter == null ? WeaveLayout.windowTitleBarHeight : (trafficLightCenter * 2).clamp(WeaveLayout.windowTitleBarMinHeight, WeaveLayout.windowTitleBarMaxHeight);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: heightFor(trafficLightCenter),
    child: DecoratedBox(
      key: const Key('window-title-bar-surface'),
      decoration: const BoxDecoration(
        color: WeaveColors.sidebar,
        border: Border(
          bottom: BorderSide(color: WeaveColors.borderSubtle, width: WeaveLayout.divider),
        ),
      ),
      child: leading == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: WeaveLayout.windowControlsInset),
              child: Align(alignment: Alignment.centerLeft, child: leading),
            ),
    ),
  );
}
