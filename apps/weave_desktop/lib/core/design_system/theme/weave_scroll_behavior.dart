import 'package:flutter/material.dart';

import '../tokens/weave_spacing.dart';

/// The app's scroll behaviour. On desktop, Material lays the scrollbar thumb
/// over the right edge of every vertical scroll view; this reserves a fixed
/// [WeaveLayout.scrollbarGutter] beside the viewport instead and draws the
/// thumb there, so it never covers switches, fields or text that reach the edge.
class WeaveScrollBehavior extends MaterialScrollBehavior {
  const WeaveScrollBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    final bool desktop = switch (getPlatform(context)) {
      TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.windows => true,
      TargetPlatform.android || TargetPlatform.fuchsia || TargetPlatform.iOS => false,
    };
    // Multiline text fields scroll inside their own padded decoration; a gutter
    // there would only narrow the text.
    if (!desktop || axisDirectionToAxis(details.direction) != Axis.vertical || context.findAncestorStateOfType<EditableTextState>() != null) {
      return super.buildScrollbar(context, child, details);
    }
    return Scrollbar(
      controller: details.controller,
      child: Padding(
        key: const Key('weave-scrollbar-gutter'),
        padding: const EdgeInsetsDirectional.only(end: WeaveLayout.scrollbarGutter),
        child: child,
      ),
    );
  }
}
