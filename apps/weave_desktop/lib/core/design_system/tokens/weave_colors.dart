import 'package:flutter/painting.dart';

/// Colour tokens of the Weave design (dark only), taken from the Figma spec.
abstract final class WeaveColors {
  // Backgrounds, from the window canvas up to raised controls.
  static const Color canvas = Color(0xFF090D16);
  static const Color sidebar = Color(0xFF0C111C);
  static const Color panel = Color(0xFF0F1625);
  static const Color surface = Color(0xFF101624);
  static const Color surfaceSunken = Color(0xFF121A29);
  static const Color surfaceRaised = Color(0xFF131B2C);
  static const Color surfaceElevated = Color(0xFF151D2E);
  static const Color surfaceSelected = Color(0xFF20234C);
  static const Color agentTile = Color(0xFF191426);
  static const Color stepActive = Color(0xFF183148);

  /// Enabled configurable setting in the Settings screen.
  static const Color settingEnabled = Color(0xFF213B36);

  // Borders and dividers.
  static const Color borderSubtle = Color(0xFF273249);
  static const Color border = Color(0xFF3A4660);
  static const Color borderDialog = Color(0xFF2B3650);
  static const Color borderStrong = Color(0xFF46516C);

  // Text and icons.
  static const Color textPrimary = Color(0xFFF2F0FF);
  static const Color textBody = Color(0xFFD6DAE8);
  static const Color textSecondary = Color(0xFFA9B0C7);
  static const Color textTertiary = Color(0xFF737C98);
  static const Color textDisabled = Color(0xFF5B6582);
  static const Color onAccent = Color(0xFFFFFFFF);

  // Accents.
  static const Color purple = Color(0xFF8B6CFF);
  static const Color purpleSoft = Color(0xFFB9A8FF);
  static const Color green = Color(0xFF45E6A8);
  static const Color greenBright = Color(0xFF65F0BB);
  static const Color greenDeep = Color(0xFF4FC797);
  static const Color blue = Color(0xFF5DA9FF);
  static const Color cyan = Color(0xFF54D8FF);
  static const Color red = Color(0xFFFF839A);
  static const Color redStrong = Color(0xFFFF6E85);
  static const Color redSurface = Color(0xFF321923);
  static const Color amber = Color(0xFFF7C768);
  static const Color coral = Color(0xFFFF735C);

  // Split diff.
  static const Color diffRemoved = Color(0xFF3A1822);
  static const Color diffRemovedGutter = Color(0xFF4A1E2B);
  static const Color diffAdded = Color(0xFF10372F);
  static const Color diffAddedGutter = Color(0xFF15473C);
  static const Color diffRemovedNumber = Color(0xFFE07A8E);

  /// Side without a matching line, so the two columns stay aligned.
  static const Color diffEmpty = Color(0xFF0B101B);
  static const Color diffHunk = Color(0xFF141D31);
  static const Color diffHunkText = Color(0xFF8C96B2);
  static const Color diffOriginalHeader = Color(0xFF25171F);
  static const Color diffUpdatedHeader = Color(0xFF10241F);
  static const Color diffColumnDivider = Color(0xFF33405E);

  /// Background of a status pill or tinted box in [accent] (10 % in the design).
  static Color tint(Color accent, [double opacity = 0.1]) => accent.withValues(alpha: opacity);

  /// Border of a status pill or tinted box in [accent] (35 % in the design).
  static Color tintBorder(Color accent, [double opacity = 0.35]) => accent.withValues(alpha: opacity);
}
