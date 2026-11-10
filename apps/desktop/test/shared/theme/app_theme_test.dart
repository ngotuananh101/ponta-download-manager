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
}
