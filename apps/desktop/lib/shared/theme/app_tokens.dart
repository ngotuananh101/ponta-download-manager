import 'package:material_ui/material_ui.dart';

/// Tailwind-like design tokens. One place to change font sizes, spacing,
/// radii and button dimensions; the rest of the app reads these instead
/// of hardcoding numbers.
///
/// The scales mirror Tailwind CSS: font sizes are `text-*`, spacing is
/// the `p-*` / `m-*` scale (step * 4 = px), radii are `rounded-*`, and
/// button sizes are the `h-*` heights with matching padding.

/// A Tailwind `text-*` size: font size + line height.
enum AppTextSize {
  xs(12, 16),
  sm(14, 20),
  base(16, 24),
  lg(18, 28),
  xl(20, 28),
  x2l(24, 32),
  x3l(30, 36),
  x4l(36, 40);

  const AppTextSize(this.fontSize, this.lineHeight);

  final double fontSize;
  final double lineHeight;

  TextStyle textStyle({FontWeight? weight, Color? color}) {
    return TextStyle(
      fontSize: fontSize,
      height: lineHeight / fontSize,
      fontWeight: weight,
      color: color,
    );
  }
}

/// The Tailwind spacing scale. `s1` is 4px, `s2` is 8px, and so on:
/// every step is 4px.
class AppSpacing {
  const AppSpacing._();

  static const double px = 1;
  static const double s0 = 0;
  static const double s05 = 2;
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;
}

/// The Tailwind `rounded-*` scale.
class AppRadius {
  const AppRadius._();

  static const double none = 0;
  static const double sm = 2;
  static const double base = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double x2l = 16;
  static const double x3l = 24;
  static const double full = 9999;
}

/// The Tailwind `font-*` weight scale.
class AppFontWeight {
  const AppFontWeight._();

  static const FontWeight normal = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
}

/// A button size: fixed height, horizontal padding and text size.
/// `md` is the default used by the theme. Text is xs by the app
/// standard; only `lg` keeps a larger text, for emphasis.
enum AppButtonSize {
  sm(32, 12, AppTextSize.xs),
  md(40, 16, AppTextSize.xs),
  lg(48, 20, AppTextSize.lg);

  const AppButtonSize(this.height, this.horizontalPadding, this.textSize);

  final double height;
  final double horizontalPadding;
  final AppTextSize textSize;

  EdgeInsets get padding => EdgeInsets.symmetric(horizontal: horizontalPadding);

  TextStyle get textStyle => textSize.textStyle();
}
