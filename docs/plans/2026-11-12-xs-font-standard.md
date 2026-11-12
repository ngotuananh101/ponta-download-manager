# Plan: xs is the standard font size — 2026-11-12

## Goal
Settle the app's standard font size as xs (12px), with a few places
allowed to be bigger or smaller.

## Audit (verified 2026-11-12)
- Explicit `AppTextSize` uses in `apps/desktop/lib` were already xs
  almost everywhere (toolbar, table rows, menus, status bar, bulk
  bar, details panel rows, dialogs). The exceptions:
  - Details panel GENERAL tab file name: `base` (16px).
  - Drop zone hint: `base` (16px).
  - The theme itself: bodyLarge `base`, bodyMedium `sm`, titleLarge
    `lg`, titleMedium `base`, titleSmall `sm`, labelLarge `sm`.
  - `AppButtonSize` text: sm `sm`, md `base`, lg `lg`.
- Nothing in lib reads `textTheme.` directly: the theme styles are
  consumed implicitly by plain `Text`, `TextField`, `ListTile` and
  `SnackBar`, so changing the theme moves them all to xs at once.

## Decisions
- Theme `_textTheme`: bodyLarge/bodyMedium/titleLarge/titleMedium/
  titleSmall/labelLarge all become xs (bodySmall/labelMedium/
  labelSmall already xs). Display (`x3l`/`x2l`/`xl`) and headline
  (`xl`/`lg`/`base`) stay larger: they are the slots for the few
  places that need bigger text. The `AppBarTheme` title (`xl`) is
  untouched: the app has no `AppBar` (custom `AppHeader`, already xs).
- `AppButtonSize`: sm and md text become xs; lg keeps `lg` text as
  the bigger-button option. Heights and paddings unchanged.
- Details panel file name and drop zone hint become xs (semibold /
  muted as before). No bigger exception is kept in the current UI:
  even the dialog and panel titles are xs semibold.
- Tests: theme/token tests updated to the xs values; new widget
  tests assert the snackbar error (theme default), the details panel
  file name and the drop zone hint are 12px.

## Verify
- Full desktop suite, `flutter analyze` clean,
  `flutter build linux --release`.

## Status: DONE 2026-11-12 (commit + push pending at plan time)
