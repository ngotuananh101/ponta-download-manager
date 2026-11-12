# Plan: delete dialog + missing-file status — 2026-11-12

## Status: DONE 2026-11-12

All parts committed and pushed: D1 `cf0cbd4`, D2 `ff022ee`, D3 `62648c0`, D4 `7e59959`, M1 (this commit). Gates: desktop 179/179, analyze clean, `flutter build linux --release` OK.

## Goal

Two features the user asked for in one message:

1. Deleting a download asks, in a dialog, whether to also delete the
   file on disk.
2. Every time the app starts, a download whose file is no longer on
   disk changes status to Missing instead of being hidden or
   auto-deleted.

## Decisions (settled with the user 2026-11-12 11:08)

- **Missing status is computed at app load, UI-only** (the lighter
  option). The engine, DB and IPC keep reporting `completed`; the
  desktop maps a completed download whose file is gone to a new
  UI-only `DownloadState.missing` when the list is loaded. A file
  that is put back shows Completed again on the next app start, and
  Retry already works on a completed record in the engine, so no
  retry plumbing is needed. The heavier option (a persisted `missing`
  value in the engine enum, DB and IPC, with the reverse check when
  the file comes back) was offered and not chosen.
- **Delete dialog: one checkbox, unchecked by default.** Title
  `Delete download` / `Delete N downloads`, a
  `Also delete the file from disk` checkbox (unchecked = keep the
  file, as today), Cancel / Delete buttons. The dialog shows only
  when at least one selected download has a finished file on disk;
  a download with only a `.partial` deletes directly as today (the
  partial is still dropped). Bulk delete shows one dialog and the
  choice applies to every selected download that has a file.
- **Scope: app entry only for the missing check.** A file deleted
  while the app is running keeps showing its loaded status until the
  next start. The `Missing Files` filter becomes state-based (see
  M1), so it agrees with the Status column.

## Survey (verified in code before writing this plan)

- Engine `PdmEngine.deleteDownload` (`apps/engine/lib/src/pdm_engine.dart:492`):
  cancels the job, drops the `.partial`, deletes the record, keeps
  the finished file. The interface is
  `DownloadEngine.deleteDownload(String downloadId)` in
  `packages/download_api/lib/src/download_engine.dart:28`. Three
  hand-written FakeEngines implement it (desktop
  `engine_ipc_host_test.dart`, `download_ipc` test_helpers, native
  host integration test). IPC has no `download.delete` method, so no
  IPC change. `IpcClient` is a plain class, not a `DownloadEngine`.
- Desktop chain: `DownloadsActions.deleteDownload(id)` →
  repository → `EngineDownloadDatasource.deleteDownload(id)` →
  `engine.deleteDownload(id)` + removes the row locally.
- Screen delete paths: row menu `_onRowAction` (`delete` case) and
  bulk `_bulkDelete` (loops `deleteDownload` per id). Row menu by
  state: downloading/queued → Pause, Cancel; paused → Resume,
  Cancel; failed → Retry, Cancel; completed/cancelled → Delete only.
  Existing test `deleting a row calls deleteDownload` verifies the
  direct call — it must be updated for the dialog flow.
- Retry works on any stored record, including completed
  (`PdmEngine.retryDownload`: deletes the partial, re-enqueues with
  the same id, resets the record to queued).
- `DownloadState` is a one-line UI enum
  (`queued, downloading, paused, completed, failed, cancelled`).
  `downloadStatusText` renders `state.name` capitalized, so a
  `missing` value shows as `Missing` with no extra code.
  `downloadStateIcon` and `downloadStatusColor` are exhaustive
  switches over `DownloadState` — the compiler forces a new arm for
  `missing`. `downloadStateFromStatus` switches over
  `DownloadStatus` (engine enum, unchanged), so it is unaffected.
- The `Missing Files` filter already computes missing live
  (`_isMissing`: completed + `filePath != null` +
  `!File(path).existsSync()`). It becomes state-based in M1 and the
  helper goes away.
- `YtDlpDownloader.deleteOutput(template)` already deletes a
  playlist's produced output (used by retry).

## Parts

### D1 — engine: `deleteFile` flag (download_api + engine)

- `DownloadEngine.deleteDownload(String downloadId, {bool deleteFile = false})`.
- `PdmEngine.deleteDownload`: when `deleteFile` is true, delete
  `record.destinationPath` if it exists (best-effort: a missing or
  undeletable file never blocks deleting the record). yt-dlp path:
  also `downloader.deleteOutput(_ytDlpTemplate(record))` so the
  produced `.mp4` goes too (the playlist-name destination path
  itself never exists as a file — the known yt-dlp name gap). The
  partial cleanup stays exactly as today.
- Update the three FakeEngines with the new parameter.
- Tests (TDD RED first): engine delete with `deleteFile: true`
  removes the finished file; `false` (and the default) keeps it;
  `true` with an already-missing file still removes the record
  without error; a yt-dlp download's produced file is removed.
  Watch the known teardown race (open the engine with
  `maxConcurrent: 0` for create-time-only assertions).

### D2 — desktop data layer: passthrough

- `EngineDownloadDatasource.deleteDownload(id, {bool deleteFile = false})`,
  repository interface + impl, `DownloadsActions.deleteDownload`
  pass the flag through.
- Tests: repository + datasource passthrough (mocktail verify with
  `deleteFile: any(named: 'deleteFile')` — a stub/verify that omits
  a named argument only matches calls where it is null/absent).

### D3 — delete dialog widget

- New `apps/desktop/lib/features/downloads/presentation/delete_download_dialog.dart`
  on the `PdmDialog` shell:
  `showDeleteDownloadDialog({required context, required int count, String? fileName})`
  → `Future<DeleteDownloadDecision?>` (`{required bool deleteFile}`,
  null = Cancel). Title `Delete download` / `Delete N downloads`;
  body names the file when `count == 1`; checkbox
  `Also delete the file from disk` / `Also delete the files from disk`
  (unchecked by default); Cancel / Delete actions.
- Tests in a new `test/features/downloads/delete_download_dialog_test.dart`
  (harness like `new_download_dialog_test.dart`): shows the file
  name, checkbox starts unchecked, Delete returns the checked value,
  Cancel returns null.

### D4 — screen wiring: row menu + bulk delete

- New screen helper `_deleteDownloads(List<Download> items)`:
  `hasFile` = any item with `state == completed` (a missing row's
  file is already gone, so it never counts) and `filePath != null`
  and `File(filePath).existsSync()`. When false, delete every id
  directly. When true, show the dialog (`count` = items.length,
  `fileName` when one item) and on a decision delete every id with
  `deleteFile: decision.deleteFile`; on Cancel do nothing. The
  selection is cleared after a bulk delete, as today.
- Row-menu `delete` and `_bulkDelete` both go through the helper.
  The row-menu comment saying the finished file is kept is updated
  to the new behavior.
- Tests in `widget_test.dart`: update `deleting a row calls
  deleteDownload` (completed row → dialog → confirm keeps the file
  by default); new tests: checking the box deletes the file too;
  Cancel deletes nothing; deleting a downloading row asks nothing
  and deletes directly; bulk delete shows one dialog for the whole
  selection.

### M1 — missing status at load (desktop only)

- `DownloadState.missing`, inserted right after `completed` (so it
  sorts between completed and failed by the enum-index status
  order).
- `downloadFromInfo` (the one mapping used by `_loadInitial`,
  `_refreshDownload` and unknown-id events): when the mapped state
  is `completed` and `filePath != null` and
  `!File(filePath).existsSync()`, return the row with state
  `missing`. The `existsSync` check runs only for completed infos,
  never on the progress-event path. `downloadStateFromStatus` is
  unchanged.
- `DownloadFilter.missing` becomes `d.state == DownloadState.missing`;
  the live `_isMissing` helper is removed (one source of truth: the
  state computed at load).
- Row menu for `missing`: Retry + Delete (Retry re-downloads the
  lost file via the engine's existing retry). Status icon
  `Icons.folder_off`, Status color `scheme.error`.
- Update every other exhaustive `DownloadState` switch the compiler
  flags (table icon/color are known; check the details panel and
  thumbnail service at implementation time).
- Tests (TDD RED first): mapper — completed + file exists →
  completed, completed + file missing → missing, downloading with no
  file → downloading (and no crash when `filePath` is null);
  filter — missing filter matches a missing row and not a completed
  one; table — Status cell shows `Missing`; row menu — a missing row
  offers Retry and Delete. Fixture file I/O inside
  `tester.runAsync()`; deletions synchronous in tearDown.

## Edge cases (decided, do not reopen without new information)

- A file deleted between the dialog's existence check and the
  delete call: best-effort, the record is still deleted.
- A missing row's file coming back mid-session: status stays
  Missing until the next app start (load-time scope).
- A missing row deleted from the UI: no dialog (its file is already
  gone), the row is removed directly.
- yt-dlp playlists: `deleteFile` removes the produced output via
  `deleteOutput`; the playlist-name path itself never exists.
- No new IPC method and no `remember my choice` on the delete
  dialog (not asked for).

## Gates + finish

Per part: the part's tests + `flutter analyze` in the touched
package(s); after M1, full desktop suite + `flutter build linux
--release`; clean dotfiles; one commit per part with push; update
this plan's Status; update `~/memory/2026-11-12.md` +
`~/MEMORY.md`; final report in Vietnamese.

## Manual checks (owed by Tuấn Anh after re-running the app)

- Delete a completed download → dialog appears, file stays on disk
  by default; check the box → the file is gone from ~/Downloads.
- Delete a downloading row → no dialog, the partial is dropped.
- Select several rows (one completed, one downloading) → one
  dialog; confirm → completed file deleted only if the box was
  checked.
- Delete a file in ~/Downloads by hand, restart the app → the row
  shows Missing; Retry re-downloads it; the Missing Files filter
  shows it.
- Put the file back, restart → the row shows Completed again.
