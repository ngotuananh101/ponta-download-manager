import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// The FDM color scheme: a near-black dark theme with a sky-blue
/// primary (the "+ Add download" button) and a bright-green secondary
/// (the HIGH badge and the "Support the project" button), sampled from
/// the Free Download Manager screenshot.
const _fdmScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF4DA3FF),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF1E3A5F),
  onPrimaryContainer: Color(0xFFBDD8FF),
  secondary: Color(0xFF4ADE80),
  onSecondary: Color(0xFF0E0E0E),
  secondaryContainer: Color(0xFF1A3A24),
  onSecondaryContainer: Color(0xFFB8F5CC),
  tertiary: Color(0xFF4DA3FF),
  onTertiary: Color(0xFFFFFFFF),
  error: Color(0xFFFF6B6B),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF5A1F1F),
  onErrorContainer: Color(0xFFFFC9C9),
  // Uniform background: the scaffold, the title bar, the toolbar and
  // the status bar are all the same color, so nothing separates them.
  surface: Color(0xFF121212),
  onSurface: Color(0xFFF2F2F2),
  surfaceContainerLowest: Color(0xFF0E0E0E),
  surfaceContainerLow: Color(0xFF161616),
  surfaceContainer: Color(0xFF1E1E1E),
  surfaceContainerHigh: Color(0xFF232323),
  surfaceContainerHighest: Color(0xFF2A2A2A),
  onSurfaceVariant: Color(0xFF9A9A9A),
  outline: Color(0xFF555555),
  outlineVariant: Color(0xFF333333),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFF2F2F2),
  onInverseSurface: Color(0xFF0E0E0E),
  inversePrimary: Color(0xFF2B6CB0),
  surfaceTint: Color(0xFF4DA3FF),
);

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _theme(
    ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: Brightness.light,
    ),
  );

  static ThemeData get dark =>
      _theme(_fdmScheme, scaffoldBackground: const Color(0xFF121212));

  /// Builds a [ButtonStyle] for a button of the given size, from the
  /// tokens. The theme uses [AppButtonSize.md] by default.
  static ButtonStyle buttonStyle(AppButtonSize size) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, size.height)),
      padding: WidgetStatePropertyAll(size.padding),
      textStyle: WidgetStatePropertyAll(size.textStyle),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
    );
  }

  static ThemeData _theme(
    ColorScheme colorScheme, {
    Color? scaffoldBackground,
  }) {
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBackground ?? colorScheme.surface,
      canvasColor: colorScheme.surfaceContainer,
      textTheme: _textTheme(colorScheme),
      appBarTheme: AppBarTheme(
        titleTextStyle: AppTextSize.xl.textStyle(
          weight: AppFontWeight.semibold,
          color: colorScheme.onSurface,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle(AppButtonSize.md),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(AppButtonSize.md),
      ),
      textButtonTheme: TextButtonThemeData(
        style: buttonStyle(AppButtonSize.md),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    final onSurface = colorScheme.onSurface;
    return TextTheme(
      displayLarge: AppTextSize.x3l.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      displayMedium: AppTextSize.x2l.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      displaySmall: AppTextSize.xl.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      headlineLarge: AppTextSize.xl.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      headlineMedium: AppTextSize.lg.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      headlineSmall: AppTextSize.base.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      titleLarge: AppTextSize.lg.textStyle(
        weight: AppFontWeight.semibold,
        color: onSurface,
      ),
      titleMedium: AppTextSize.base.textStyle(
        weight: AppFontWeight.medium,
        color: onSurface,
      ),
      titleSmall: AppTextSize.sm.textStyle(
        weight: AppFontWeight.medium,
        color: onSurface,
      ),
      bodyLarge: AppTextSize.base.textStyle(color: onSurface),
      bodyMedium: AppTextSize.sm.textStyle(color: onSurface),
      bodySmall: AppTextSize.xs.textStyle(color: onSurface),
      labelLarge: AppTextSize.sm.textStyle(
        weight: AppFontWeight.medium,
        color: onSurface,
      ),
      labelMedium: AppTextSize.xs.textStyle(
        weight: AppFontWeight.medium,
        color: onSurface,
      ),
      labelSmall: AppTextSize.xs.textStyle(
        weight: AppFontWeight.medium,
        color: onSurface,
      ),
    );
  }
}
