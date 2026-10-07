import 'package:flutter/widgets.dart';

import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

/// The soft purple ellipse behind the top of every product screen. It is
/// decorative: it ignores the pointer and is hidden from screen readers.
class WeaveAmbientGlow extends StatelessWidget {
  const WeaveAmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    const Size size = WeaveLayout.ambientGlowSize;
    // A radial gradient is circular, so draw it in a square and stretch the
    // square horizontally into the design's ellipse.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.fromSize(
          size: size,
          child: Transform.scale(
            scaleX: size.width / size.height,
            child: Center(
              child: SizedBox.square(
                dimension: size.height,
                child: const DecoratedBox(
                  decoration: BoxDecoration(gradient: WeaveGradients.ambientGlow),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
