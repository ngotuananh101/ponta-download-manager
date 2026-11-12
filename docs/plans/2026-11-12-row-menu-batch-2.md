# Plan: row menu Batch 2 — Rename file, Move to, Change URL, Check for update, Export — 2026-11-12

## Status: DONE 2026-11-12

Commits (all pushed): B2.1 Rename file `5465e9b`, B2.2 Move to
`95e0832`, B2.3 Change URL `5d2e3a3`, B2.4 Check for update
`7ea44f5`, B2.5 Export selected downloads `ecaae88`.

## Outcome notes

- Rename and Change URL share the new `showTextInputDialog`
  (one-field PdmDialog, prefilled, select-all, inline validation,
  OK disabled while invalid).
- Move to... opens the folder picker directly (no dialog);
  cross-filesystem moves fall back to copy + delete.
- Change URL is failed-rows only: the scheduler's queued/paused
  jobs carry their own URL, so a record-only change would not
  affect them. Retry re-enqueues from the record, so the new URL
  takes effect there.
- Check for update compares SIZES only (see the correction in
  B2.4): the engine never persists the server's eTag /
  lastModified, so no validator comparison is possible yet.
- Export writes plain text, one URL per line (IDM-compatible);
  the selection when non-empty, else the row the menu was opened
  on. Switching to JSON with metadata later is one function +
  its test.

## Goal

Batch 2 of the IDM row-menu research
(`docs/plans/2026-11-12-row-menu-options-research.md`). Tuấn Anh
said "Tiếp 2 luôn" (12:06). The five medium items, all needing new
engine methods.

## Decisions

- **Export format:** plain text, one URL per line (IDM-compatible).
  The JSON-with-metadata alternative from the research doc stays
  open — switching formats later is one function + its test. No
  decision was asked for, to keep the batch moving.
- **Rename / Move scope:** completed rows with a finished file on
  disk (`_hasFinishedFile`). A paused or failed row has no finished
  file to rename or move.
- **Change URL scope:** failed rows ONLY. The scheduler's queued
  and paused jobs carry their own URL (`DownloadJob.url`;
  `resume()` re-queues the stored job), so changing the record's
  URL would not change what a paused/queued download fetches.
  Failed rows have no live job, and Retry re-enqueues from the
  record's URL, so the new URL takes effect on Retry.
- **Check for update scope:** completed rows only; read-only (it
  never writes the record — the stored size/eTag stay as they are
  until a Retry re-downloads). A playlist URL is inconclusive
  (yt-dlp decides the size at download time).
- **Menu order** (final, after all five parts): Open, Show in
  folder, Set priority, Rename file, Move to..., the existing state
  actions, Copy link, Check for update, Change URL, Export selected
  downloads, Delete file, Delete.
- **Rename / Change URL share one dialog:** a small reusable
  `showTextInputDialog` (PdmDialog + one TextField, prefilled,
  select-all, inline validation, OK disabled while invalid) in
  `apps/desktop/lib/features/downloads/presentation/text_input_dialog.dart`.
  Rename validates a file name (non-empty, no `/` or `\`);
  Change URL validates an http(s) URL.
- **Move to... has no dialog:** the row action opens the folder
  picker directly (file_picker, zenity on Linux), like the New
  download dialog's folder button. Cancel does nothing.
- **Export selection rule:** the row menu exports the multi-select
  selection when it is non-empty, otherwise just the row the menu
  was opened on.

## Survey (verified in code before writing this plan)

- `DownloadRecord` (`packages/download_recovery/lib/src/download_record.dart`):
  `url`, `fileName`, `directory`, `status`, `downloadedBytes`,
  `totalBytes` (-1 = unknown), `eTag`, `lastModified`, `finalUrl`,
  `supportsRange`, `priority`, `maxConnections`, `errorCode`,
  `errorMessage`; `destinationPath` is a getter
  (`p.join(directory, fileName)`); `copyWith` uses `?? this.field`
  and cannot clear nullable fields — construct a fresh record to
  clear `eTag`/`lastModified` (the retry code already does this).
- `PdmEngine.probeUrl` calls `_transport.probe(uri)` and maps it
  to `ProbeResult` (url, fileName, totalBytes), dropping the
  validators — so Check for update calls `_transport.probe`
  directly and compares with the stored record. `ResourceInfo`
  carries `contentLength`, `eTag`, `lastModified`.
- `PdmEngine.retryDownload` re-enqueues from the record
  (`url: record.url`, fresh `DownloadRecord`, same id), which is
  why Change URL on a failed row works on the next Retry.
- `FilePicker` seams: the New download dialog takes an injectable
  `pickDirectory` (`pickDirectory ?? () =>
  FilePicker.platform.getDirectoryPath()`); no test mocks
  `FilePickerPlatform` directly. The screen follows the
  `fileOpenerProvider` pattern instead: `directoryPickerProvider`
  and `saveFileProvider` (function-typed providers, overridden in
  widget tests with lambdas).
- Current row menu (after Batch 1): Open, Show in folder, Set
  priority submenu, state actions, Copy link, Delete file, Delete.

## Parts

### B2.1 — Rename file (engine + dialog + UI)

- Engine: `DownloadEngine.renameFile(String downloadId, String
  newFileName)`. Validates the name (non-empty, no `/` or `\` —
  `p.basename(name) == name`) → `DownloadError('invalid-name',
  ...)`; the target exists → `DownloadError('file-exists',
  'Destination already exists: <path>')` (the repository's
  `_toFailure` already maps that code to `FileExistsFailure`).
  Renames the file on disk (`File.renameSync`, same directory so
  no cross-filesystem case) and upserts the record with the new
  `fileName`. Works for yt-dlp records too: `destinationPath` is
  the produced file. Update the three FakeEngines.
- Desktop: datasource `renameFile(id, newName)` → engine call +
  `_refreshDownload(id)` (the row shows the new name);
  repository + actions passthrough.
- UI: menu item `Rename file` when `_hasFinishedFile(item)`;
  `showTextInputDialog` prefilled with the current name;
  `_onRowAction` case `rename` → `actions.renameFile` with the
  usual snackbar-on-failure.
- Tests: engine — rename works and the record follows, target
  exists throws `file-exists`, an invalid name throws, a yt-dlp
  produced file is renamed; datasource — calls the engine and
  refreshes; repository — passthrough; dialog — OK disabled when
  empty/invalid, returns the typed name; widget — the item appears
  for a completed row with a real file and calls `renameFile`,
  hidden for a downloading row.

### B2.2 — Move to... (engine + UI)

- Engine: `DownloadEngine.moveFile(String downloadId, String
  directory)`. The directory must exist →
  `DownloadError('invalid-directory', ...)` otherwise; the target
  file exists → `file-exists` as above. Moves the file: try
  `File.renameSync`, on failure copy + delete the original
  (cross-filesystem fallback, e.g. moving to a USB drive), then
  upserts the record with the new `directory`. Update the three
  FakeEngines.
- Desktop: datasource `moveFile(id, directory)` → engine call +
  `_refreshDownload(id)`; repository + actions passthrough;
  `directoryPickerProvider` in `download_providers.dart`.
- UI: menu item `Move to...` when `_hasFinishedFile(item)`;
  `_onRowAction` case `move` opens the picker via the provider
  (cancel → nothing), then `actions.moveFile` with the usual
  snackbar-on-failure.
- Tests: engine — move works and the record follows, target
  exists throws, a missing directory throws; datasource /
  repository passthrough; widget — the picker is called and its
  directory is passed to `moveFile`, a cancelled picker calls
  nothing, the item is hidden for a downloading row.

### B2.3 — Change URL (engine + dialog + UI)

- Engine: `DownloadEngine.changeUrl(String downloadId, String
  url)`. Validates http(s) → `DownloadError('invalid-url', ...)`
  (the same code/message as `probeUrl`). Updates the record with
  a fresh `DownloadRecord` carrying the new URL and cleared
  `eTag`/`lastModified` (stale validators would send a wrong
  `If-Range` on Retry); status, bytes, size and `createdAt` are
  kept. Update the three FakeEngines.
- Desktop: datasource `changeUrl(id, url)` → engine call +
  `_refreshDownload(id)`; repository + actions passthrough.
- UI: menu item `Change URL` for failed rows;
  `showTextInputDialog` prefilled with the current URL;
  `_onRowAction` case `change_url` → `actions.changeUrl` with the
  usual snackbar-on-failure. After changing, Retry uses the new
  URL.
- Tests: engine — the URL changes and the validators are
  cleared, an invalid URL throws, an unknown id is a no-op;
  datasource / repository passthrough; dialog — OK disabled for
  a non-http(s) URL; widget — the item appears for a failed row
  and calls `changeUrl`, hidden for a completed row.

### B2.4 — Check for update (engine + UI)

- Engine: `DownloadEngine.checkForUpdate(String downloadId)` →
  `Future<UpdateCheckResult>`. New freezed model in
  `download_api` (`UpdateCheckResult`: `required bool hasUpdate`,
  `required bool inconclusive`, `required int newTotalBytes`,
  -1 = unknown) + barrel export + `dart run build_runner build`
  in `packages/download_api`. Unknown id → `DownloadError`
  with the not-found code the repository already maps. A
  playlist URL → inconclusive (no size signal). Otherwise probe
  with `_transport.probe` and compare SIZES ONLY: `hasUpdate`
  when the server's size differs from the record's `totalBytes`
  (both known); `inconclusive` when the server reports no size
  or the record has none. Probe errors propagate. Read-only: the
  record is never written.
  - CORRECTION 2026-11-12 (found while implementing): the record
  never stores the server's eTag / lastModified — the engine
  never persists response validators — so no eTag/lastModified
  comparison is possible yet. Comparing them is a follow-up once
  the engine stores response headers. The research doc's "record
  stores eTag" was wrong.
- Desktop: datasource `checkForUpdate(id)` → engine call;
  repository + actions passthrough (returns
  `Either<Failure, UpdateCheckResult>`).
- UI: menu item `Check for update` for completed rows;
  `_onRowAction` case `check_for_update` → up to date: snackbar
  `You have the latest version`; update available: snackbar
  `A newer version is available (X)` with a `Download`
  SnackBarAction that calls `actions.retryDownload`; inconclusive:
  snackbar `Could not determine whether an update is available`;
  probe error: the usual error snackbar.
- Tests: engine — up to date when the eTag matches, update when
  the size differs, update when the eTag differs, inconclusive
  with no signals, a playlist URL is inconclusive, a probe
  failure throws (needs a test server that 404s / a failing
  transport — mirror the existing probe tests); datasource /
  repository passthrough; widget — each outcome shows its
  snackbar, and the Download action retries.

### B2.5 — Export selected downloads (service + UI)

- New pure function `exportUrls(Iterable<Download> downloads)`
  in `apps/desktop/lib/features/downloads/data/services/download_export.dart`:
  the URLs joined with `\n`, one per line, with a trailing
  newline when non-empty.
- Screen: menu item `Export selected downloads` on every row;
  `_onRowAction` case `export` builds the id set (the
  multi-select selection when non-empty, else the row), resolves
  the downloads from the provider list, calls `saveFileProvider`
  (`fileName: 'downloads.txt'`, cancel → nothing), writes the
  text, snackbar `Exported N downloads`. Write failure → the
  usual error snackbar.
- Tests: pure function — urls joined, empty input → empty
  string; widget — with a fake save path the file is written
  with the selected rows' URLs, a cancelled picker writes
  nothing, with no selection only the row is exported.

## Gates + finish

Per part: the part's tests + `flutter analyze` in the touched
package(s); after B2.5, full desktop suite + engine suite +
download_ipc + host suites + `flutter build linux --release`;
clean dotfiles; one commit per part with push; update this plan's
Status; update `~/memory/2026-11-12.md` + `~/MEMORY.md`; final
report in Vietnamese.

## Manual checks (owed by Tuấn Anh after re-running the app)

- Rename a completed file → the file on disk and the row show
  the new name; renaming to an existing name shows the error.
- Move a completed file to another folder → the file moves and
  the row's Path follows; cancelling the picker does nothing.
- Change URL on a failed download → Retry fetches the new link.
- Check for update on a completed download → up-to-date or the
  newer-version snackbar with a working Download action.
- Export with several rows selected → the saved file lists their
  URLs, one per line; with nothing selected only the row is
  exported.
