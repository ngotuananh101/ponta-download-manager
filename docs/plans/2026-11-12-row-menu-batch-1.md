# Plan: row menu Batch 1 — Copy link, Open, Show in folder, Set priority, Delete file — 2026-11-12

## Status: IN PROGRESS 2026-11-12

## Goal

Batch 1 of the IDM row-menu research
(`docs/plans/2026-11-12-row-menu-options-research.md`): the five
quick wins. Tuấn Anh chose "Làm Batch 1 trước" (11:38). "Remove
from list" is NOT in scope: the delete dialog's keep-file choice
already does it, and he did not contradict that recommendation.

## Decisions

- **Menu order** (final, after all four parts): Open, Show in
  folder, Set priority, the existing state actions (Pause / Resume /
  Retry / Cancel), Copy link, Delete file, Delete. File actions
  first, as in IDM; the state-action block keeps its place.
- **Visibility, not disabled items:** an item only appears when it
  applies (the existing menu's pattern). Open: the finished file
  exists on disk. Show in folder: `filePath != null` (opens the
  containing folder even when the file itself is gone). Set
  priority: queued / downloading / paused (the scheduler only
  reorders queued and paused jobs; a running job keeps the priority
  it started with — see below). Copy link: every row. Delete file:
  the finished file exists.
- **Priority values:** High = 1, Normal = 0, Low = -1 (matches
  `priorityLabel`: >0 high, <0 low; the scheduler orders higher
  first, ties by enqueue order).
- **Set priority presentation:** a submenu (as in IDM) is the goal,
  via `SubmenuButton` inside a `PopupMenuItem`. Risk: Flutter's
  popup menu does not nest submenus cleanly — the submenu may open
  but leave the parent menu open after a choice. Fallback, decided
  in advance: three flat items (Priority: High / Normal / Low) with
  a check on the current value. If the submenu does not behave in
  the first widget-test run, go flat immediately and note it in the
  final report; do not burn the session on menu nesting.
- **Open / Show in folder implementation:** `Process.run`
  (following `DiskSpaceService`), no new dependency. Linux:
  `xdg-open <file>` / `xdg-open <dir>`; macOS: `open <file>` /
  `open -R <file>`; Windows: `explorer <file>` /
  `explorer /select,<file>`.
- **Delete file semantics:** deletes the finished file (and any
  partial) and KEEPS the record; the row becomes Missing through
  the M1 mapping. No IPC method (desktop-only, like probing).

## Survey (verified in code before writing this plan)

- Row menu: `_buildRowMenu` in `downloads_screen.dart` (a
  `PopupMenuButton<String>`, items via `_menuItem` — xs text, 32px
  rows); `_onRowAction(item, action)` switches on the action string
  and shows a snackbar on failure. `Clipboard` is already imported
  (`package:flutter/services.dart`).
- `DiskSpaceService` (`features/downloads/data/services/`) is the
  style model for shelling out: const class, `Platform.isWindows`
  branch, `Process.run`, null/exception on failure.
- Priority: `PdmEngine.setPriority` (`apps/engine/lib/src/pdm_engine.dart:523`)
  calls `scheduler.setPriority` + upserts the record;
  `DownloadScheduler.setPriority` reorders queued/paused jobs only
  ("A running download keeps the priority it started with");
  `setPriority` is also an IPC method (`download.setPriority`).
  The desktop chain has NO setPriority anywhere (no matches in
  `apps/desktop/lib`): datasource, repository and actions all need
  it. The UI only displays priority (details panel
  `priorityLabel`).
- `DownloadRecord` has `eTag`; `upsertDownload` + `copyWith` are
  the record-update mechanism the engine already uses.
- The screen already has `_hasFinishedFile` (D4): `filePath !=
  null && File(filePath).existsSync()`.

## Parts

### B1.1 — Copy link (UI only)

- Menu item `Copy link` after the state actions, for every row.
- `_onRowAction` case `copy_link`: `await Clipboard.setData(
  ClipboardData(text: item.url))`, then a snackbar `Link copied
  to clipboard`.
- Tests: widget test with a platform-channel mock that records
  `Clipboard.setData` calls (the existing `mockClipboard` only
  handles getData); tap Copy link → the recorded text is the row's
  URL and the snackbar shows. Commit with the (still uncommitted)
  research doc.

### B1.2 — Open + Show in folder (service + UI)

- New `FileOpener` in
  `apps/desktop/lib/features/downloads/data/services/file_opener.dart`,
  following `DiskSpaceService`: `const FileOpener({run,
  operatingSystem})` where `run` defaults to `Process.run` and
  `operatingSystem` defaults to `Platform.operatingSystem` (both
  seams exist so tests can drive every platform branch).
  `openFile(path)` / `showInFolder(path)` → `Future<void>`,
  throwing an `Exception` with a plain message on a non-zero exit
  or an unsupported platform. `showInFolder` opens `p.dirname`
  of the file on Linux, `open -R` on macOS,
  `explorer /select,<path>` on Windows.
- Screen: `fileOpenerProvider = Provider<FileOpener>((ref) =>
  const FileOpener())` in `download_providers.dart`; menu items
  `Open` / `Show in folder` at the top of `_buildRowMenu` per the
  visibility rules; `_onRowAction` cases `open` /
  `show_in_folder` call the provider's opener and show a snackbar
  on failure.
- Tests: service unit tests with a fake `run` (records executable
  + args, returns exitCode 0 / 1) for all three platforms;
  widget tests with the provider overridden by a recording
  `FileOpener` — Open appears only for a completed row with a
  real file and calls `xdg-open` with the file; Show in folder
  calls `xdg-open` with the directory; neither appears for a
  downloading row.

### B1.3 — Set priority (data plumbing + submenu UI)

- Desktop chain: `EngineDownloadDatasource.setPriority(id,
  priority)` → `engine.setPriority` + updates the local row
  (`copyWith(priority:)` + `_emit()` — the engine emits no event
  for a priority change, so the row would otherwise keep the old
  value until the next reload); repository interface + impl and
  `DownloadsActions.setPriority` passthrough.
- UI: submenu in `_buildRowMenu` for queued / downloading /
  paused rows: `PopupMenuItem` wrapping a `SubmenuButton` with
  High / Normal / Low `MenuItemButton`s, a check icon on the
  current value; choosing one calls `_onRowAction(item,
  'priority_high' | 'priority_normal' | 'priority_low')`, which
  calls `actions.setPriority` (1 / 0 / -1) with the usual
  snackbar-on-failure. See the submenu risk + flat fallback in
  Decisions.
- Tests: datasource test (mock engine; verify the call + the
  local row's priority updates) and repository passthrough test;
  widget tests — the submenu opens, choosing High calls
  `setPriority('dl-1', 1)`, the current value shows the check,
  the submenu does not appear for a completed row.

### B1.4 — Delete file, keep the row (engine + desktop)

- Engine: `DownloadEngine.deleteFile(String downloadId)` (new
  interface method) + `PdmEngine` implementation: HTTP path
  deletes `destinationPath` + the partial when they exist;
  yt-dlp path calls `downloader.deleteOutput(template)` + the
  partial; the record stays, status unchanged. Best-effort: a
  missing file is not an error. Update the three FakeEngines.
  No IPC method.
- Desktop: `EngineDownloadDatasource.deleteFile(id)` →
  `engine.deleteFile` + `_refreshDownload(id)` (re-reads the
  list, so `downloadFromInfo` re-maps the row to Missing);
  repository + actions passthrough.
- UI: menu item `Delete file` when `_hasFinishedFile(item)`;
  `_onRowAction` case `delete_file` → `actions.deleteFile` with
  the usual snackbar-on-failure.
- Tests (TDD RED first): engine — deleteFile removes the
  finished file and keeps the record, a missing file is not an
  error, a yt-dlp produced file is removed; datasource —
  deleteFile calls the engine and the row becomes Missing;
  widget — the item appears for a completed row with a real
  file and calls `deleteFile`, hidden for a downloading row.

## Gates + finish

Per part: the part's tests + `flutter analyze` in the touched
package(s); after B1.4, full desktop suite + engine suite +
`flutter build linux --release`; clean dotfiles; one commit per
part with push; update this plan's Status; update
`~/memory/2026-11-12.md` + `~/MEMORY.md`; final report in
Vietnamese.

## Manual checks (owed by Tuấn Anh after re-running the app)

- Copy link on any row → pasting gives the download URL, and the
  "Link copied to clipboard" snackbar shows.
- Open on a completed file → the file opens in its default app;
  Show in folder → the file manager opens at the download
  folder. Neither item shows on a downloading row.
- Set priority High on a queued download → the details panel
  shows "high", and it jumps ahead of normal-priority queued
  downloads. The submenu does not show on a completed row.
- Delete file on a completed download → the file disappears from
  ~/Downloads and the row shows Missing; Retry re-downloads it.
