import 'package:flutter/material.dart';

import '../../tokens/weave_effects.dart';
import '../../tokens/weave_spacing.dart';

/// The interlocking-loop mark used to identify Weave across the app.
class WeaveLogoMark extends StatelessWidget {
  const WeaveLogoMark({this.size = WeaveLayout.sidebarLogoSize, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Weave logo',
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _WeaveLogoPainter()),
    ),
  );
}

class _WeaveLogoPainter extends CustomPainter {
  const _WeaveLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final Paint paint = Paint()
      ..shader = WeaveGradients.logo.createShader(bounds)
      ..style = PaintingStyle.stroke
      ..strokeWidth = WeaveSpacing.s4;
    final double ovalWidth = size.width * 0.53;
    final double ovalHeight = size.height * 0.79;
    final double top = (size.height - ovalHeight) / 2;
    canvas.drawOval(Rect.fromLTWH(WeaveSpacing.s2, top, ovalWidth, ovalHeight), paint);
    canvas.drawOval(Rect.fromLTWH(size.width - ovalWidth - WeaveSpacing.s2, top, ovalWidth, ovalHeight), paint);
  }

  @override
  bool shouldRepaint(covariant _WeaveLogoPainter oldDelegate) => false;
}
