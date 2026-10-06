import 'package:flutter/painting.dart';

/// Spacing scale used for gaps and padding in the design.
abstract final class WeaveSpacing {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s10 = 10;
  static const double s12 = 12;
  static const double s14 = 14;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s28 = 28;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
}

/// Corner radii used in the design.
abstract final class WeaveRadii {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double control = 10;
  static const double card = 12;
  static const double panel = 14;
  static const double dialog = 16;
  static const double window = 20;
  static const double pill = 999;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius controlAll = BorderRadius.all(Radius.circular(control));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelAll = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius dialogAll = BorderRadius.all(Radius.circular(dialog));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Fixed sizes of the app layout.
abstract final class WeaveLayout {
  static const Size minimumWindow = Size(1100, 720);
  static const Size defaultWindow = Size(1600, 1000);

  static const double sidebarExpanded = 288;
  static const double sidebarCollapsed = 72;

  /// Window width from which the sidebar starts expanded.
  static const double sidebarExpandBreakpoint = 1360;

  static const double chatPanelWidth = 440;
  static const double pageGutter = 34;
  static const double controlHeight = 44;
  static const double statusPillHeight = 26;
}
