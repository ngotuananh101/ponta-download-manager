import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/shared/theme/app_theme.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

void main() {
  group('AppTheme', () {
    test('light textTheme uses the token sizes', () {
      final textTheme = AppTheme.light.textTheme;
      expect(textTheme.bodyLarge?.fontSize, 16);
      expect(textTheme.bodyMedium?.fontSize, 14);
      expect(textTheme.bodySmall?.fontSize, 12);
      expect(textTheme.titleLarge?.fontSize, 18);
      expect(textTheme.titleLarge?.fontWeight, FontWeight.w600);
    });

    test('dark theme is dark', () {
      expect(AppTheme.dark.brightness, Brightness.dark);
      expect(AppTheme.light.brightness, Brightness.light);
    });

    test('buttonStyle resolves height and text size per size', () {
      final sm = AppTheme.buttonStyle(AppButtonSize.sm);
      expect(sm.minimumSize?.resolve({})?.height, 32);
      expect(sm.textStyle?.resolve({})?.fontSize, 14);

      final lg = AppTheme.buttonStyle(AppButtonSize.lg);
      expect(lg.minimumSize?.resolve({})?.height, 48);
      expect(lg.textStyle?.resolve({})?.fontSize, 18);
    });

    test('the default button theme uses the md size', () {
      final style = AppTheme.light.elevatedButtonTheme.style;
      expect(style?.minimumSize?.resolve({})?.height, 40);
      expect(style?.textStyle?.resolve({})?.fontSize, 16);
    });
  });

  group('AppTheme FDM palette', () {
    test('dark theme uses the FDM colors', () {
      final scheme = AppTheme.dark.colorScheme;
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, const Color(0xFF4DA3FF));
      expect(scheme.secondary, const Color(0xFF4ADE80));
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
