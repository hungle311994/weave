import 'package:flutter/widgets.dart';

import '../../tokens/weave_colors.dart';
import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

/// A panel floating above the page, e.g. a hidden sidebar shown while the
/// pointer is over its rail item: rounded, outlined and lifted by a shadow.
class WeaveFloatingPanel extends StatelessWidget {
  const WeaveFloatingPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: WeaveRadii.panelAll,
      border: Border.all(color: WeaveColors.borderSubtle, width: WeaveLayout.divider),
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(borderRadius: WeaveRadii.panelAll, boxShadow: WeaveShadows.popover),
      child: ClipRRect(borderRadius: WeaveRadii.panelAll, child: child),
    ),
  );
}
