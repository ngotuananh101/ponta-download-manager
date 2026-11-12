# Plan: Custom dialogs (template first) — 2026-11-12

## Goal
Replace the stock `AlertDialog`s with a custom dialog template
matching the New download design Tuấn Anh showed (dark rounded panel,
title + X on top, content in the middle, action buttons bottom
right: dark secondary pills, blue primary pill with an uppercase
label).

## Scope decisions
- Template first, features later: this step only builds the shared
  shell and moves the existing dialogs onto it. The New download
  dialog itself (Save to picker, File name field, Scheduler checkbox,
  Size / Disk space line, Download later) is a later step built on
  this shell; no dialog gains or loses behavior here.
- Existing dialogs in the app (verified by search): the Add download
  dialog (`_showAddDialog`) and the file-exists dialog
  (`showFileConflictDialog`). Nothing else opens a dialog.
- The shell owns the look: title style, X close button (pops null =
  cancelled), 480px fixed width, 12px radius, `surfaceContainerHigh`
  background with an `outlineVariant` border, 36px action pills.
  The primary button uppercases its own label, so callers pass
  plain labels ('Add', 'Download') and get 'ADD' / 'DOWNLOAD'.

## Work
- New `apps/desktop/lib/shared/widgets/pdm_dialog.dart`: `PdmDialog`
  (`title`, `child`, `actions`, `width` = 480) and
  `PdmDialogButton.primary` / `.secondary`.
- `file_conflict_dialog.dart`: same content (file name, RadioGroup,
  Remember checkbox), same Cancel / Download behavior, on the shell.
- `downloads_screen.dart` `_showAddDialog`: same URL field, same
  Cancel / Add behavior, on the shell.
- Widget tests: `find.byType(AlertDialog)` -> `find.byType(PdmDialog)`;
  primary labels are now uppercase ('ADD', 'DOWNLOAD'); new test
  that the X button closes the Add dialog without adding.
- Verify: full desktop suite, `flutter analyze` clean,
  `flutter build linux --release`.

## Status: DONE 2026-11-12. Desktop suite 126/126, analyze clean, release build succeeds. Note: an intermediate lint-fix script matched the wrong child: anchor in downloads_screen.dart and spliced the file; it was restored from git and the migration re-applied with an exact anchor.

## Sizing pass (Tuấn Anh's feedback, same day)
- Buttons were too small, inputs and option rows too big. Dialog text
  is now always xs (12px): title, file name, radio/checkbox labels,
  field text and hint, button labels. Buttons are 40px tall
  (`AppButtonSize.md.height`) with 20px horizontal padding.
- Primary buttons no longer uppercase their label.
- Option rows use `dense: true` + `VisualDensity.compact`; the Add
  dialog's URL field uses xs text with 12px/8px content padding.
- Tests updated to the plain labels, plus a test asserting the Add
  dialog's title and field text are 12px.
