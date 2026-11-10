# Plan: Tailwind-like theme tokens (code-level only)

## Goal

Replace the minimal `AppTheme` (seed color only) with a Tailwind-like
design-token system, configured in code, so font sizes, button sizes,
spacing and radii are named constants in one place instead of hardcoded
numbers scattered through the UI. No runtime Settings UI (decided
2026-11-10).

## Starting state

- `apps/desktop/lib/shared/theme/app_theme.dart` exists: `AppTheme.light`
  / `AppTheme.dark`, both `ThemeData` with a teal seed `ColorScheme` and
  `useMaterial3: true`. Nothing else (no textTheme, button theme,
  spacing, radii).
- `apps/desktop/lib/app/app.dart` uses `AppTheme.light` / `dark`.
- `DownloadsScreen` hardcodes `SizedBox(height: 4)` twice; everything
  else uses Material defaults.

## Design

New file `apps/desktop/lib/shared/theme/app_tokens.dart`:

- `AppTextSize` enum (Tailwind `text-*`, each with fontSize + lineHeight):
  `xs(12, 16)`, `sm(14, 20)`, `base(16, 24)`, `lg(18, 28)`,
  `xl(20, 28)`, `x2l(24, 32)`, `x3l(30, 36)`, `x4l(36, 40)`.
  Helper `textStyle({FontWeight? weight, Color? color})`.
- `AppSpacing` (Tailwind spacing scale, step * 4 = px):
  `s0 = 0`, `s05 = 2`, `s1 = 4`, `s2 = 8`, `s3 = 12`, `s4 = 16`,
  `s5 = 20`, `s6 = 24`, `s8 = 32`, `s10 = 40`, `s12 = 48`, `s16 = 64`,
  plus `px = 1`.
- `AppRadius` (Tailwind `rounded-*`):
  `none = 0`, `sm = 2`, `base = 4`, `md = 6`, `lg = 8`, `xl = 12`,
  `x2l = 16`, `x3l = 24`, `full = 9999`.
- `AppFontWeight`: `normal = w400`, `medium = w500`, `semibold = w600`,
  `bold = w700`.
- `AppButtonSize` enum (Tailwind button heights/padding):
  `sm(32, 12, AppTextSize.sm)`, `md(40, 16, AppTextSize.base)`,
  `lg(48, 20, AppTextSize.lg)`; each with `height`,
  `horizontalPadding`, `textSize`, plus `padding` and `textStyle`
  getters.

Updated `apps/desktop/lib/shared/theme/app_theme.dart`:

- One private `_theme(Brightness)` shared by `light` / `dark`
  (keeps the teal seed `ColorScheme`).
- `textTheme` built from `AppTextSize` + `AppFontWeight` (bodyLarge =
  base, bodyMedium = sm, titleLarge = lg semibold, etc.).
- `appBarTheme` title = xl semibold.
- `elevatedButtonTheme` / `filledButtonTheme` / `textButtonTheme`
  default to `AppButtonSize.md` (height, padding, text size, md radius).
- Public `AppTheme.buttonStyle(AppButtonSize)` so any call site can
  build a sm/lg button style.
- `inputDecorationTheme`: content padding from `AppSpacing`,
  `md` radius border.
- `floatingActionButtonTheme`: `lg` radius shape.

Updated `apps/desktop/lib/features/downloads/presentation/screens/downloads_screen.dart`:

- The two `SizedBox(height: 4)` become `SizedBox(height: AppSpacing.s1)`.

## Tests (TDD, RED first)

New `apps/desktop/test/shared/theme/app_tokens_test.dart`:

- Text sizes: base = 16/24, xs = 12/16, x3l = 30/36; `textStyle`
  carries fontSize + height (lineHeight / fontSize).
- Spacing: s1 = 4, s4 = 16, s16 = 64, s05 = 2.
- Radius: sm = 2, md = 6, lg = 8, full = 9999.
- Button sizes: sm height 32 / padding 12 / text sm; md 40 / 16 /
  base; lg 48 / 20 / lg.
- Font weights: semibold = w600, bold = w700.

New `apps/desktop/test/shared/theme/app_theme_test.dart`:

- `AppTheme.light.textTheme.bodyLarge` fontSize 16, bodyMedium 14,
  titleLarge 18 semibold; dark brightness is dark.
- `AppTheme.buttonStyle(AppButtonSize.sm)` resolves minimumSize height
  32 and textStyle fontSize 14; the md default resolves height 40.
- Light theme's `elevatedButtonTheme` resolves to the md height (40).

## Verification

- `flutter test` in `apps/desktop` (existing 22 + new token/theme
  tests), `flutter analyze` clean.
- `flutter build linux --release` still succeeds (tokens are
  compile-time constants; no new dependency).
- Commit on `main` (branches were cleaned up 2026-11-10; work goes
  straight to main now) and report.

## Out of scope

- Runtime theme switching / Settings UI (decided against).
- Dark/light toggle UI (MaterialApp already has both themes; the OS
  picks).
- Changing the teal seed color or the overall look.
