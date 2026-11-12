import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/shared/theme/app_tokens.dart';

void main() {
  group('AppTextSize', () {
    test('base is 16/24, xs is 12/16, x3l is 30/36', () {
      expect(AppTextSize.base.fontSize, 16);
      expect(AppTextSize.base.lineHeight, 24);
      expect(AppTextSize.xs.fontSize, 12);
      expect(AppTextSize.xs.lineHeight, 16);
      expect(AppTextSize.x3l.fontSize, 30);
      expect(AppTextSize.x3l.lineHeight, 36);
    });

    test('textStyle carries fontSize and line height', () {
      final style = AppTextSize.base.textStyle();
      expect(style.fontSize, 16);
      expect(style.height, 24 / 16);
      expect(
        AppTextSize.sm.textStyle(weight: FontWeight.w600).fontWeight,
        FontWeight.w600,
      );
    });
  });

  group('AppSpacing', () {
    test('follows the Tailwind scale (step * 4 = px)', () {
      expect(AppSpacing.s0, 0);
      expect(AppSpacing.s05, 2);
      expect(AppSpacing.s1, 4);
      expect(AppSpacing.s2, 8);
      expect(AppSpacing.s4, 16);
      expect(AppSpacing.s8, 32);
      expect(AppSpacing.s16, 64);
    });
  });

  group('AppRadius', () {
    test('follows the Tailwind rounded scale', () {
      expect(AppRadius.none, 0);
      expect(AppRadius.sm, 2);
      expect(AppRadius.md, 6);
      expect(AppRadius.lg, 8);
      expect(AppRadius.xl, 12);
      expect(AppRadius.full, 9999);
    });
  });

  group('AppButtonSize', () {
    test('sm/md/lg carry height, padding and text size', () {
      expect(AppButtonSize.sm.height, 32);
      expect(AppButtonSize.sm.horizontalPadding, 12);
      expect(AppButtonSize.sm.textSize, AppTextSize.xs);
      expect(AppButtonSize.md.height, 40);
      expect(AppButtonSize.md.horizontalPadding, 16);
      expect(AppButtonSize.md.textSize, AppTextSize.xs);
      expect(AppButtonSize.lg.height, 48);
      expect(AppButtonSize.lg.horizontalPadding, 20);
      expect(AppButtonSize.lg.textSize, AppTextSize.lg);
    });
  });

  group('AppFontWeight', () {
    test('matches the Tailwind weight scale', () {
      expect(AppFontWeight.normal, FontWeight.w400);
      expect(AppFontWeight.medium, FontWeight.w500);
      expect(AppFontWeight.semibold, FontWeight.w600);
      expect(AppFontWeight.bold, FontWeight.w700);
    });
  });
}
