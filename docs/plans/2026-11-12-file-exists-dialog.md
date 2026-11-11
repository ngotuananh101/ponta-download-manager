# Plan: File-exists dialog (overwrite / rename + remember) — 2026-11-12

## Goal
When a download starts and the destination file already exists, ask the
user what to do instead of failing silently with a snackbar.

## Current state (verified 2026-11-12)
- `PdmEngine.createDownload` already throws
  `DownloadError('file-exists', 'Destination already exists: <path>')`
  when the final file exists (before the playlist/native branch).
- The UI (`_showAddDialog`, `_onDrop`) calls
  `actions.addDownload(url)` and shows any failure as a SnackBar.
- `Failure` carries only a message; the repository's `_toFailure`
  drops the error code, so the UI cannot tell `file-exists` apart.
- `CreateDownloadRequest` (freezed, `download_api`) has no policy
  field: `{url, destination, maxConnections?, priority?}`.
- IPC `download.create` carries `{url, destination, maxConnections?,
  priority?}` (client + server in `download_ipc`); the native host
  never sends a policy.
- No settings persistence exists in the desktop app (no
  `shared_preferences` dep). `ThumbnailService` resolves the app data
  dir inline (Windows `LOCALAPPDATA`, else `XDG_DATA_HOME` or
  `~/.local/share`, + `pdm/thumbs`).

## Scope decisions
- The dialog appears for downloads started from the app UI (Add
  dialog and drag-and-drop). Both call sites share one screen helper.
- Rename: `file.ext` -> `file (1).ext` -> `file (2).ext` (first free
  name; an existing ` (N)` suffix is stripped first so a re-download
  of `file (1).ext` starts from `file`). No extension (`README`) ->
  `README (1)`; `archive.tar.gz` -> `archive.tar (1).gz`.
- Remember checkbox: persists the chosen policy (overwrite or
  rename) in a small JSON settings file under the app data dir
  (`<data>/pdm/settings.json`). While set, the dialog is skipped and
  the remembered policy is applied to UI adds. There is no Settings
  screen yet (M3), so there is no in-app reset for now; the choice
  can be cleared by deleting that file. The Settings screen will add
  a reset.
- Browser-extension downloads cannot show a dialog: the native host
  always sends `conflictPolicy: rename` for IPC creates, so a
  browser download never overwrites and never fails on an existing
  file. The remembered choice applies to UI adds only.
- The engine owns the unique-name computation (same function the UI
  uses for the dialog preview, so the preview is exact).
- Out of scope: a Settings-screen reset UI, CLI flags for the
  `download` subcommand, retry-path handling (retry reuses its
  record and never re-checks), and the yt-dlp name gap (the exists
  check is on the playlist name, e.g. `x36xhzz.m3u8`, not the
  produced `x36xhzz.mp4` — a pre-existing gap, not widened here).

## Parts (commit each when done)

### P1 — download_api: the policy type + request field
- New `FileConflictPolicy` enum (`overwrite`, `rename`) in
  `packages/download_api/lib/src/models/file_conflict_policy.dart`,
  exported from the barrel.
- `CreateDownloadRequest` gains `FileConflictPolicy? conflictPolicy`
  (null = ask/fail, today's behavior). Regenerate with
  `dart run build_runner build --delete-conflicting-outputs` in
  `packages/download_api`.
- Verify: `dart analyze` in the package; JSON round-trip keeps the
  field (a request with `conflictPolicy: rename` serializes and
  parses back).

### P2 — engine: unique names + policy handling
- New pure helper in the engine (exported from the `pdm_engine`
  barrel): `resolveUniquePath(destination, {exists})` — first free
  name per the rename rules above; `exists` injectable for tests.
- `createDownload`: `null` -> throw `file-exists` (unchanged);
  `overwrite` -> skip the check and enqueue with `overwrite: true`;
  `rename` -> replace the destination with `resolveUniquePath`
  before the playlist/native branch (so the yt-dlp template follows
  the renamed stem).
- The policy reaches the file writer: `FileChunkSink.create` gains
  `overwrite` (skips its own final-path `file-exists` throw; the
  partial is still created exclusively), `DownloadJob` + `enqueue`
  carry `overwrite`, and the scheduler's default factory and the
  engine's factory both forward it. (Found during implementation:
  the sink is a second `file-exists` gate — the engine check alone
  left overwrite downloads failing at task start.)
- Tests (engine suite, TDD RED first): overwrite proceeds when the
  file exists; rename picks `(1)` then `(2)`; null still throws
  `file-exists`; the helper strips an existing ` (N)` suffix and
  handles extension-less names.
- Verify: `dart test` in `packages/download_storage`,
  `packages/download_scheduler` and `apps/engine`;
  `dart analyze` clean.

### P3 — IPC: carry the policy through the protocol
- `IpcClient.createDownload` sends `conflictPolicy` when set;
  `IpcServer` `download.create` parses it (`overwrite`/`rename`,
  anything else -> `invalidParams`) into the request.
- Tests: IPC suite round-trip (client sends rename, server creates
  with the renamed destination; unknown value rejected).
- Verify: `dart test` in `packages/download_ipc`, `dart analyze`
  clean.

### P4 — native host: browser downloads always rename
- `integrations/browser-extension/host`: `createDownload` sends
  `conflictPolicy: 'rename'`.
- Tests: host suite asserts the param is sent.
- Verify: `dart test` in the host, `dart analyze` clean.

### P5 — desktop: failure type, plumbing, settings, dialog, wiring
- `FileExistsFailure extends Failure` carrying the destination
  (parsed from the engine's `Destination already exists: <path>`
  message in `DownloadRepositoryImpl._toFailure`).
- Policy plumbing: `DownloadRepository.addDownload(url,
  {FileConflictPolicy? conflictPolicy})`, same for
  `EngineDownloadDatasource.addDownload` and
  `DownloadsActions.addDownload` (all optional, default null).
- Settings service
  `apps/desktop/lib/features/downloads/data/services/file_conflict_settings.dart`:
  `load()` (sync, null on missing/corrupt) / `save(policy)` writing
  `{"fileConflictPolicy": "overwrite"|"rename"}` to
  `<data>/pdm/settings.json`; default path injectable for tests.
  Extract the app-data-dir rule into a tiny shared helper used by
  both this service and `ThumbnailService`.
  Provider `fileConflictSettingsProvider`.
- Dialog
  `apps/desktop/lib/features/downloads/presentation/file_conflict_dialog.dart`:
  `showFileConflictDialog({context, fileName, renamedName})` ->
  `FileConflictDecision({policy, remember})?` (null = cancelled).
  Layout: title `File already exists`, file name, radio
  Overwrite (`Replace the existing file`) / Rename (`Save as
  "<renamedName>"`), checkbox `Remember my choice`, actions
  Cancel / Download.
- Screen helper `_addDownload(url)` in `downloads_screen.dart`
  used by `_showAddDialog` and `_onDrop`: remembered policy ->
  pass it; else try plain -> on `FileExistsFailure` show the
  dialog -> on choice, save if remembered, retry with the policy;
  other failures -> SnackBar as today.
- Widget tests (TDD RED first): dialog appears on file-exists with
  the right file name and rename preview; Overwrite retries with
  `overwrite`; Rename retries with `rename`; checking Remember
  saves the setting and the next add skips the dialog; a remembered
  policy is passed without any dialog; Cancel adds nothing.
- Verify: full desktop suite, `flutter analyze` clean.
- Status: DONE 2026-11-12. Desktop 125/125, analyze clean, release
  build succeeds. Implementation notes: `save()` is synchronous —
  an async save never completes in a widget test's FakeAsync zone.
  The dialog uses `RadioGroup` (per-tile `groupValue`/`onChanged`
  are deprecated). Mocktail: `any(named:)` matches a call that
  omits the named argument, and later-registered stubs win — the
  conflict tests share one answer queue across both stubs.

## Final verification
- Full desktop suite + `flutter analyze` + `flutter build linux
  --release` (release bundle still builds).
- Manual check by Tuấn Anh after re-running the app: add a download
  whose file already exists in `~/Downloads` -> dialog appears;
  Rename -> row shows `file (1).ext`; add again -> `file (2).ext`;
  check Remember + Overwrite -> next conflict downloads without
  asking; download the same file from the browser -> it renames
  automatically.
