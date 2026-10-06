import 'package:flutter/painting.dart';

import 'weave_colors.dart';

/// Poppins type scale of the Weave design. Figma draws every line at 1.5× the
/// font size, which [_lineHeight] reproduces.
abstract final class WeaveTypography {
  static const String fontFamily = 'Poppins';
  static const double _lineHeight = 1.5;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  static TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: weight, height: _lineHeight, color: color, leadingDistribution: TextLeadingDistribution.even);

  /// Page title, e.g. "What should Weave build?" (Bold 34).
  static final TextStyle display = _style(34, bold, WeaveColors.textPrimary);

  /// Dialog title and brand name (SemiBold 20).
  static final TextStyle titleLarge = _style(20, semiBold, WeaveColors.textPrimary);

  /// Card title, e.g. "Workflow preview" (SemiBold 17).
  static final TextStyle titleMedium = _style(17, semiBold, WeaveColors.textPrimary);

  /// Item title inside a card, e.g. a step or agent role (SemiBold 14).
  static final TextStyle titleSmall = _style(14, semiBold, WeaveColors.textPrimary);

  /// Field label and button text (SemiBold 13).
  static final TextStyle label = _style(13, semiBold, WeaveColors.textPrimary);

  /// Page subtitle and composer text (Regular 14).
  static final TextStyle bodyLarge = _style(14, regular, WeaveColors.textSecondary);

  /// List item name, e.g. a recent workflow or agent (Medium 13).
  static final TextStyle bodyStrong = _style(13, medium, WeaveColors.textPrimary);

  /// Regular text in lists and cards (Regular 13).
  static final TextStyle body = _style(13, regular, WeaveColors.textSecondary);

  /// Dialog subtitle and secondary text (Regular 12).
  static final TextStyle bodySmall = _style(12, regular, WeaveColors.textSecondary);

  /// Breadcrumb (Medium 12).
  static final TextStyle breadcrumb = _style(12, medium, WeaveColors.textTertiary);

  /// Meta text under an item, e.g. a model name or path (Regular 11).
  static final TextStyle caption = _style(11, regular, WeaveColors.textTertiary);

  /// Upper-case section label, e.g. "RECENT WORKFLOWS" (SemiBold 11).
  static final TextStyle overline = _style(11, semiBold, WeaveColors.textTertiary);

  /// Badge and status pill text (Medium 10).
  static final TextStyle micro = _style(10, medium, WeaveColors.textSecondary);

  /// Code in diffs and logs; the design keeps Poppins here too (Regular 11).
  static final TextStyle code = _style(11, regular, WeaveColors.textBody);
}
