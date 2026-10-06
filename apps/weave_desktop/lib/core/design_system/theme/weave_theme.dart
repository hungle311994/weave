import 'package:flutter/material.dart';

import '../tokens/weave_colors.dart';
import '../tokens/weave_spacing.dart';
import '../tokens/weave_typography.dart';

/// The app's only theme: Weave is dark-only. Material widgets that screens
/// still use pick up the design tokens through this [ThemeData].
abstract final class WeaveTheme {
  static ThemeData dark() {
    const ColorScheme colors = ColorScheme.dark(
      primary: WeaveColors.purple,
      onPrimary: WeaveColors.onAccent,
      primaryContainer: WeaveColors.surfaceSelected,
      onPrimaryContainer: WeaveColors.textPrimary,
      secondary: WeaveColors.green,
      onSecondary: WeaveColors.canvas,
      secondaryContainer: WeaveColors.stepActive,
      onSecondaryContainer: WeaveColors.textPrimary,
      tertiary: WeaveColors.blue,
      onTertiary: WeaveColors.canvas,
      tertiaryContainer: WeaveColors.surfaceElevated,
      onTertiaryContainer: WeaveColors.textPrimary,
      error: WeaveColors.red,
      onError: WeaveColors.canvas,
      errorContainer: WeaveColors.redSurface,
      onErrorContainer: WeaveColors.red,
      surface: WeaveColors.surface,
      onSurface: WeaveColors.textPrimary,
      onSurfaceVariant: WeaveColors.textSecondary,
      surfaceContainerLowest: WeaveColors.canvas,
      surfaceContainerLow: WeaveColors.sidebar,
      surfaceContainer: WeaveColors.surface,
      surfaceContainerHigh: WeaveColors.surfaceRaised,
      surfaceContainerHighest: WeaveColors.surfaceElevated,
      outline: WeaveColors.border,
      outlineVariant: WeaveColors.borderSubtle,
      shadow: Color(0xFF000000),
      scrim: Color(0xB3000000),
    );
    final TextTheme text = TextTheme(
      displaySmall: WeaveTypography.display,
      headlineSmall: WeaveTypography.titleLarge,
      titleLarge: WeaveTypography.titleLarge,
      titleMedium: WeaveTypography.titleMedium,
      titleSmall: WeaveTypography.titleSmall,
      bodyLarge: WeaveTypography.bodyLarge,
      bodyMedium: WeaveTypography.body,
      bodySmall: WeaveTypography.bodySmall,
      labelLarge: WeaveTypography.label,
      labelMedium: WeaveTypography.bodySmall,
      labelSmall: WeaveTypography.micro,
    );
    const OutlineInputBorder idleBorder = OutlineInputBorder(
      borderRadius: WeaveRadii.controlAll,
      borderSide: BorderSide(color: WeaveColors.border),
    );
    final ButtonStyle controlShape = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, WeaveLayout.controlHeight)),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.symmetric(horizontal: WeaveSpacing.s20)),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder(borderRadius: WeaveRadii.controlAll)),
      textStyle: WidgetStatePropertyAll<TextStyle>(WeaveTypography.label),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colors,
      fontFamily: WeaveTypography.fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: WeaveColors.canvas,
      canvasColor: WeaveColors.canvas,
      dividerColor: WeaveColors.borderSubtle,
      visualDensity: VisualDensity.compact,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: const DividerThemeData(color: WeaveColors.borderSubtle, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: WeaveColors.textSecondary, size: 20),
      cardTheme: const CardThemeData(
        color: WeaveColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: WeaveRadii.panelAll,
          side: BorderSide(color: WeaveColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: WeaveColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: WeaveRadii.dialogAll,
          side: BorderSide(color: WeaveColors.borderStrong),
        ),
        titleTextStyle: WeaveTypography.titleLarge,
        contentTextStyle: WeaveTypography.bodySmall,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: WeaveColors.surfaceElevated,
          borderRadius: WeaveRadii.mdAll,
          border: Border.all(color: WeaveColors.borderSubtle),
        ),
        textStyle: WeaveTypography.bodySmall.copyWith(color: WeaveColors.textPrimary, fontWeight: WeaveTypography.medium),
        padding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s10, vertical: WeaveSpacing.s6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: WeaveColors.surface,
        hintStyle: WeaveTypography.body.copyWith(color: WeaveColors.textDisabled),
        labelStyle: WeaveTypography.body,
        helperStyle: WeaveTypography.caption,
        errorStyle: WeaveTypography.caption.copyWith(color: WeaveColors.red),
        contentPadding: const EdgeInsets.symmetric(horizontal: WeaveSpacing.s14, vertical: WeaveSpacing.s12),
        border: idleBorder,
        enabledBorder: idleBorder,
        focusedBorder: const OutlineInputBorder(
          borderRadius: WeaveRadii.controlAll,
          borderSide: BorderSide(color: WeaveColors.purple),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: WeaveRadii.controlAll,
          borderSide: BorderSide(color: WeaveColors.redStrong),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: WeaveRadii.controlAll,
          borderSide: BorderSide(color: WeaveColors.redStrong),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: WeaveColors.purple, selectionColor: WeaveColors.purple.withValues(alpha: 0.35), selectionHandleColor: WeaveColors.purple),
      filledButtonTheme: FilledButtonThemeData(
        style: controlShape.merge(FilledButton.styleFrom(backgroundColor: WeaveColors.purple, foregroundColor: WeaveColors.onAccent, disabledBackgroundColor: WeaveColors.surfaceRaised, disabledForegroundColor: WeaveColors.textDisabled)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: controlShape.merge(
          OutlinedButton.styleFrom(
            backgroundColor: WeaveColors.surfaceRaised,
            foregroundColor: WeaveColors.textPrimary,
            disabledForegroundColor: WeaveColors.textDisabled,
            side: const BorderSide(color: WeaveColors.border),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WeaveColors.purpleSoft,
          textStyle: WeaveTypography.label,
          shape: const RoundedRectangleBorder(borderRadius: WeaveRadii.controlAll),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((Set<WidgetState> states) => states.contains(WidgetState.selected) ? WeaveColors.purple : WeaveColors.surface),
        checkColor: const WidgetStatePropertyAll<Color>(WeaveColors.onAccent),
        side: const BorderSide(color: WeaveColors.border),
        shape: const RoundedRectangleBorder(borderRadius: WeaveRadii.xsAll),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: WeaveColors.surfaceSunken,
        selectedColor: WeaveColors.surfaceSelected,
        side: const BorderSide(color: WeaveColors.borderSubtle),
        shape: const RoundedRectangleBorder(borderRadius: WeaveRadii.mdAll),
        labelStyle: WeaveTypography.bodySmall.copyWith(color: WeaveColors.textBody, fontWeight: WeaveTypography.medium),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: WeaveColors.surfaceElevated,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: WeaveRadii.panelAll,
          side: BorderSide(color: WeaveColors.borderSubtle),
        ),
        textStyle: WeaveTypography.bodyStrong,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: WeaveColors.purple, linearTrackColor: WeaveColors.borderSubtle, circularTrackColor: WeaveColors.borderSubtle),
      scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll<Color>(WeaveColors.border.withValues(alpha: 0.8)), radius: const Radius.circular(WeaveRadii.pill), thickness: const WidgetStatePropertyAll<double>(6)),
    );
  }
}
