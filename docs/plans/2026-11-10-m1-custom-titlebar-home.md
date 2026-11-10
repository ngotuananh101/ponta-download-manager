# Plan: Custom title bar + FDM-like home (2026-11-10)

## Goal

Port dev-stack's custom title bar to PDM and redesign the home screen
to look like Free Download Manager (screenshot 2026-11-10 21:47):
toolbar (select / sort / filter / Add / search / menu), a dashed
drop zone, and a bottom status bar. The drop zone accepts real
drags: URLs are added as downloads, `.torrent` files report
"torrent chưa hỗ trợ" (PDM has no torrent support).

## Research done

- dev-stack title bar: runner `gtk_window_set_decorated(window, FALSE)`
  + rounded-corner painting (RGBA visual, window_draw_cb, radius 6,
  background `#020617`); Dart `whenCurrentWindow` sets title/size/min/
  background transparent, show/focus; `AppHeader` (36px, brand +
  `DragToMoveArea` + min/max/close, 46px each, close red on hover);
  `VirtualWindowFrameInit()` in the MaterialApp builder; close goes
  through `window.close()` -> WindowService tray listener.
- desktop_drop 0.9.x (needs Flutter 3.47.7+, PDM has 3.47.9):
  `DropTarget({required child, required onDrop, acceptedKinds,
  onEnter/onLeave})`; `DropStringItem({mimeType, value})` carries
  `text/plain`, `text/html`, `text/uri-list`; `DropFileItem` has
  `name`, `mimeType`, `file` (XFile), `localPath`; a drag can carry
  the same content in several representations, so the app must
  choose and dedupe. `DropFileItem` has no public constructor.
- `DragToMoveArea` works standalone (GestureDetector -> `startDragging`
  on pan, `performTitleBarDoubleClick` on double-tap). No
  VirtualWindowFrame needed.

## Deviations from dev-stack (decided)

- **No rounded corners, no VirtualWindowFrameInit.** PDM supports
  light AND dark themes, so a runner that paints one background
  colour would mismatch one theme; the FDM reference is square
  anyway. The window is a plain undecorated rectangle; the Flutter
  view fills it. `DragToMoveArea` alone provides dragging.
- **Material icons** for the window controls (PDM has no lucide).
- **`.torrent` is not supported.** The drop zone text mirrors FDM,
  but a dropped `.torrent` shows "torrent chưa hỗ trợ" instead of
  silently failing.

## Part A: custom title bar

1. `apps/desktop/linux/runner/my_application.cc`:
   - Remove the GtkHeaderBar branch; `gtk_window_set_title(window,
     "Ponta Download Manager")`, `gtk_window_set_decorated(window,
     FALSE)`. Keep `--minimized`, default size 1280x720, black
     pre-frame background. Load the window icon from the bundle
     (`data/flutter_assets/assets/images/icon.png`), dev-stack style.
2. `apps/desktop/lib/main.dart`:
   - `main(List<String> args)`; `whenCurrentWindow`: non-Linux only
     `titleBarStyle = hidden` + `isWindowControlButtonsVisible =
     false` (Linux is undecorated by the runner); set title, size
     1280x720, minimumSize 960x540, `backgroundColor` transparent,
     `center()`; `show()` + `focus()` unless `--minimized` (the
     runner alone is not enough: a Dart `show()` would override it).
3. New `apps/desktop/lib/app/app_header.dart`:
   - `AppHeader`, 36px: icon (16px) + "Ponta Download Manager"
     (bold, xs) | `DragToMoveArea` | minimize (Icons.remove) /
     maximize-restore (Icons.crop_square / Icons.copy) / close
     (Icons.close), 46px wide, hover states, close red on hover.
   - Maximized state tracked via a window listener
     (`WindowMaximizedEvent` / `WindowRestoredEvent`, read back from
     the window). Close calls `currentWindow()?.close()` so the
     WindowService tray listener still decides hide-vs-quit.
   - Uses `window_api.dart` (`currentWindow`, `whenCurrentWindow`)
     and the app tokens. Renderable in a widget test (no window in
     a test => buttons are no-ops).
4. `DownloadsScreen` becomes the shell: `Scaffold` body is a
   `Column` [AppHeader, Toolbar, Expanded(body), StatusBar]; the
   old `AppBar` and FAB go away (Add moves to the toolbar).

## Part B: FDM-like home

`DownloadsScreen` becomes a `ConsumerStatefulWidget` with state:
sort, filter, search query, selected ids, drag-over flag,
global-pause flag + the ids it paused.

- **Toolbar** (~48px, padding s3/s4): select-all `Checkbox`
  (tristate over the visible list) | sort `DropdownButton`
  (Newest, Oldest, Name A-Z, Size) | filter `DropdownButton`
  (All files, Downloading, Completed, Failed, Paused, Queued) |
  spacer | `+ Add download` FilledButton (md, opens the existing
  dialog) | search TextField (~240px, "Search in downloads...") |
  menu `PopupMenuButton` (Pause all, Resume all).
- **List**: `visibleDownloads(items, sort, filter, query)` — a pure
  function, unit-tested. Rows keep the current content + progress
  + status and gain a leading `Checkbox`. When `_selected` is
  non-empty, a bulk bar appears (count, Pause, Cancel, clear);
  bulk actions loop the existing per-download actions.
- **Empty state**: when the full list is empty (and no filter/search
  active) show the drop zone; when a filter/search yields nothing
  show "No downloads match.".
- **Drop zone**: dashed rounded border (a small `DashedBorder`
  CustomPainter, no new dependency for the border), centered
  `Drag-and-drop URL or torrent file`, click opens the add dialog.
  The whole body is wrapped in a `DropTarget`
  (`acceptedKinds: {file, string}`); `onEnter`/`onLeave` set the
  drag-over flag; while dragging, a full-body overlay says "Drop
  to add download".
- **Drop parsing** — pure `parseDroppedContent({strings,
  fileNames}) -> DropParseResult{urls, hasTorrent, hasOtherFile}`:
  prefer `text/uri-list` (skip `#` comments/blanks, http/https
  only), else `text/plain` lines that parse as URLs, skip
  `text/html`, dedupe; `.torrent` (case-insensitive) sets
  `hasTorrent`, other files set `hasOtherFile`. `onDrop` converts
  `details.items` to those two lists, adds each URL via
  `DownloadsActions.addDownload`, snackbars for failures and for
  the torrent/unsupported cases.
- **Status bar** (~36px): global pause toggle (a pill button
  ON/OFF; OFF pauses all downloading/queued downloads and records
  their ids, ON resumes exactly those) | `↓ <total>/s` (sum of
  `bytesPerSecond` over downloading items, real) | `↑ 0 B/s`
  (PDM does not upload) | green `HIGH` badge (static visual, the
  FDM priority indicator; no priority mode exists yet) |
  `Support the project` button (heart icon, opens
  `https://github.com/ngotuananh101/ponta-download-manager` via
  `url_launcher`).

## Deps

- `flutter pub add desktop_drop url_launcher` in `apps/desktop`
  (lets pub pick the latest compatible versions; desktop_drop
  0.9.x needs Flutter 3.47.7+, PDM has 3.47.9). Rebuild regenerates
  the Linux plugin registrant.

## Tests (TDD, RED first where new logic)

- `test/shared/theme/app_header_test.dart` (widget): AppHeader
  renders the title and the three window-control buttons.
- `test/features/downloads/downloads_filter_test.dart` (unit):
  `visibleDownloads` — sort (newest/oldest/name/size), filter by
  state, search by file name and URL, combined.
- `test/features/downloads/drop_parse_test.dart` (unit):
  `parseDroppedContent` — uri-list with comments, plain-text URL,
  HTML skipped, dedupe across representations, non-http skipped,
  `.torrent` flagged, other files flagged.
- Update the existing `test/widget_test.dart` to the new screen
  (no AppBar/FAB; drop zone when empty; toolbar present).

## Verification

- `flutter test` in `apps/desktop` (all suites), `flutter analyze`
  clean, `flutter build linux --release` succeeds (exercises the
  runner change + new plugins).
- Manual (his machine): run the app — no native title bar, drag
  the header to move, double-click toggles maximize, close hides
  to tray, tray Quit exits; drag a URL from the browser onto the
  drop zone and a download starts; drag a `.torrent` and the
  message appears.
- Commit on `main`, push, report in Vietnamese.

## Out of scope

- Torrent support (message only).
- Rounded window corners / VirtualWindowFrame.
- Multi-window, minimize-to-tray setting, proper 256px icon,
  single-instance enforcement (existing follow-ups).
