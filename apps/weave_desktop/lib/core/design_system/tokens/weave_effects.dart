import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

import 'weave_colors.dart';

/// Drop shadows used in the design (Figma blur maps to [BoxShadow.blurRadius]).
abstract final class WeaveShadows {
  /// Cards and panels.
  static const List<BoxShadow> card = <BoxShadow>[BoxShadow(color: Color(0x4D000000), blurRadius: 30, offset: Offset(0, 14))];

  /// Popover menus such as the workspace switcher.
  static const List<BoxShadow> popover = <BoxShadow>[BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 16))];

  /// Tooltips.
  static const List<BoxShadow> tooltip = <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8))];

  /// Dialogs, with a soft glow in the dialog's [accent] colour.
  static List<BoxShadow> dialog([Color accent = WeaveColors.purple]) => <BoxShadow>[
    const BoxShadow(color: Color(0x94000000), blurRadius: 60, offset: Offset(0, 24)),
    BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 28),
  ];
}

/// Gradients used in the design.
abstract final class WeaveGradients {
  /// Primary buttons, e.g. "Start workflow".
  static const LinearGradient primary = LinearGradient(colors: <Color>[Color(0xFFA68DFF), Color(0xFF6955F5)]);

  /// Card and panel backgrounds.
  static const LinearGradient card = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFF182236), Color(0xFF0F1523)]);

  /// The selected sidebar item.
  static const LinearGradient navSelected = LinearGradient(colors: <Color>[Color(0xFF403C82), Color(0xFF252758)]);

  /// The Weave logo mark.
  static const LinearGradient logo = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[Color(0xFFAA8EFF), Color(0xFF54D8FF)]);

  /// The purple glow behind the top of each screen.
  static const RadialGradient ambientGlow = RadialGradient(colors: <Color>[Color(0x3D6D56DF), Color(0x006D56DF)]);
}

/// Animation durations and curves.
abstract final class WeaveMotion {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);

  /// Sidebar width changes and panel transitions.
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);

  /// One pass of a loading highlight, e.g. over a refreshing usage bar.
  static const Duration sweep = Duration(milliseconds: 1200);

  /// How long a floating sidebar stays after the pointer leaves it or its
  /// rail item, so the pointer can move from one to the other.
  static const Duration peekHideDelay = Duration(milliseconds: 220);

  /// A floating sidebar fading and sliding in, and out a little faster.
  static const Duration peekIn = Duration(milliseconds: 260);
  static const Duration peekOut = Duration(milliseconds: 180);

  /// How far, as a share of its width, a floating sidebar slides in from.
  static const double peekSlide = 0.06;

  /// Pause in typing before a search that leaves the Mac, e.g. the MCP Registry.
  static const Duration searchDebounce = Duration(milliseconds: 400);

  /// How long an overflowing title waits under the pointer before it
  /// scrolls, and how long it rests at each end of a pass.
  static const Duration marqueeDelay = Duration(milliseconds: 700);
  static const Duration marqueePause = Duration(milliseconds: 1200);

  /// Scroll speed of an overflowing title, in logical pixels per second;
  /// slow enough to read, whatever the title's length.
  static const double marqueeSpeed = 36;
  static const Curve curve = Curves.easeOutCubic;
}
