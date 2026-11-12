import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/shared/theme/app_theme.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

void main() {
  group('AppTheme', () {
    test('light textTheme uses the xs standard', () {
      // The standard text size is xs (12px); display/headline stay
      // larger for the few places that need bigger text.
      final textTheme = AppTheme.light.textTheme;
      expect(textTheme.bodyLarge?.fontSize, 12);
      expect(textTheme.bodyMedium?.fontSize, 12);
      expect(textTheme.bodySmall?.fontSize, 12);
      expect(textTheme.titleLarge?.fontSize, 12);
      expect(textTheme.titleMedium?.fontSize, 12);
      expect(textTheme.titleSmall?.fontSize, 12);
      expect(textTheme.labelLarge?.fontSize, 12);
      expect(textTheme.titleLarge?.fontWeight, FontWeight.w600);
      expect(textTheme.displayLarge?.fontSize, 30);
      expect(textTheme.headlineMedium?.fontSize, 18);
    });

    test('dark theme is dark', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.brightness, Brightness.light);
    });

    test('buttonStyle resolves height and text size per size', () {
      final sm = AppTheme.buttonStyle(AppButtonSize.sm);
      expect(sm.minimumSize?.resolve({})?.height, 32);
      expect(sm.textStyle?.resolve({})?.fontSize, 12);

      final lg = AppTheme.buttonStyle(AppButtonSize.lg);
      expect(lg.minimumSize?.resolve({})?.height, 48);
      expect(lg.textStyle?.resolve({})?.fontSize, 18);
    });

    test('the default button theme uses the md size', () {
      final style = AppTheme.light.elevatedButtonTheme.style;
      expect(style?.minimumSize?.resolve({})?.height, 40);
      expect(style?.textStyle?.resolve({})?.fontSize, 12);
    });
  });

  group('AppTheme FDM palette', () {
    test('dark theme uses the FDM colors', () {
      final scheme = AppTheme.dark.colorScheme;
      expect(scheme.brightness, Brightness.dark);
      // Sampled from the FDM screenshots: the Add button is light sky
      // blue with dark text; the green is #4EC284.
      expect(scheme.primary, const Color(0xFF73CEFC));
      expect(scheme.onPrimary, const Color(0xFF141415));
      expect(scheme.secondary, const Color(0xFF4EC284));
      expect(scheme.surface, const Color(0xFF121212));
      expect(scheme.surfaceContainer, const Color(0xFF1E1E1E));
      expect(scheme.surfaceContainerHighest, const Color(0xFF2A2A2A));
      expect(scheme.onSurface, const Color(0xFFF2F2F2));
      expect(scheme.onSurfaceVariant, const Color(0xFF9A9A9A));
      expect(scheme.outline, const Color(0xFF555555));
      expect(scheme.outlineVariant, const Color(0xFF333333));
      expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF121212));
    });

    test('the default button theme is rounded like FDM', () {
      final style = AppTheme.dark.elevatedButtonTheme.style;
      final borderRadius =
          (style?.shape?.resolve({}) as RoundedRectangleBorder?)
                  ?.borderRadius
              as BorderRadius?;
      expect(borderRadius?.topLeft.x, 8);
    });

    test('text fields are filled dark pills', () {
      final decoration = AppTheme.dark.inputDecorationTheme;
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, const Color(0xFF2A2A2A));
    });
  });
}
