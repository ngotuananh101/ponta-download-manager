import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _theme(Brightness.light);

  static ThemeData get dark => _theme(Brightness.dark);

  /// Builds a [ButtonStyle] for a button of the given size, from the
  /// tokens. The theme uses [AppButtonSize.md] by default.
  static ButtonStyle buttonStyle(AppButtonSize size) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, size.height)),
      padding: WidgetStatePropertyAll(size.padding),
      textStyle: WidgetStatePropertyAll(size.textStyle),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
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
