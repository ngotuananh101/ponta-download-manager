# Row-menu Batch 3 — File integrity, Add mirror, Add tag, Virus check (disabled)

## Status: IN PROGRESS 2026-11-12

## Context

His message 2026-11-12 12:40: "Tiếp phần 3 nhé nhưng virus check
thì tạm bỏ qua bạn cứ thêm vào menu nhưng disable" — do Batch 3,
but skip virus check for now: add it to the menu, disabled.

Batch 3 is the last group from the row-menu research
(`docs/plans/2026-11-12-row-menu-options-research.md`): File
integrity, Perform virus check, Add mirror, Add tag.

## Decisions

### File integrity (B3.1)

- Implements the `download_integrity` stub (architecture §5.1:
  `IntegrityVerifier` — "Validate final size and available
  checksums").
- The check verifies the finished file on disk: it exists, and —
  when the record knows the size — its size matches
  `record.totalBytes`. A record with an unknown total (-1) is
  existence-only.
- The verifier also accepts an optional expected SHA-256
  (`expectedSha256`): the architecture's "available checksums"
  hook. No checksum source exists today (the engine never stores
  one), so the engine passes none; the parameter is the API for a
  future checksum source (e.g. a `.sha256` sidecar), not dead
  code.
- Engine method `DownloadEngine.verifyFile(id)` returns an
  `IntegrityResult` union (download_api): `ok(bytes)`,
  `missing()`, `sizeMismatch(expectedBytes, actualBytes)`,
  `checksumMismatch(expectedSha256, actualSha256)`,
  `unreadable(message)`. Unknown id throws `not-found` (the
  repository maps it to ValidationFailure, as with
  checkForUpdate). Playlists need no special case: the record's
  totalBytes is the produced file's size, so the same path
  verifies it.
- Menu item 'File integrity' for completed rows only (a partial
  is not a file to verify; a Missing row already says the file
  is gone). Result shown in a snackbar, read-only, never writes
  the record.

### Add mirror (B3.2)

- A mirror is an alternative URL for the same file, stored on
  the record: `DownloadRecord.mirrors` (List<String>, default
  []), persisted as a JSON TEXT column (`mirrors`) via a
  `user_version` 1 → 2 migration (ALTER TABLE; the v1 CREATE
  TABLE gains the column too).
- Engine method `DownloadEngine.addMirror(id, url)`: validates
  http(s) (same `invalid-url` error as probeUrl/changeUrl),
  unknown id returns silently (like setPriority), duplicate
  URLs are ignored.
- Failover is automatic, on final failure only: when a native
  download fails and the record has mirrors, the engine
  re-enqueues with the next mirror URL instead of emitting the
  failed event. The partial is deleted and the download restarts
  from scratch with the mirror (a resume would need the
  primary's validators, which the mirror may not honour). An
  in-memory map tracks which mirror is active per id
  (-1 = primary); a manual Retry always restarts from the
  primary, and the entry is cleared on completion / final
  failure / cancel / delete. The record's `url` stays the
  primary throughout, so Copy link still shows it.
- Playlists (yt-dlp) are excluded from failover: their failure
  path is separate (`_onYtDlpEvent`), and a mirror of a
  playlist URL would need yt-dlp to pick it up.
- No mirror list UI in this batch: there is no way to remove a
  mirror yet, and mirrors are not shown anywhere. Removal +
  a details-panel mirrors section is a follow-up.
- The fresh-record constructions in `retryDownload` (both
  branches) and `changeUrl` must carry `mirrors`/`tags`
  forward, or a retry / URL change would silently wipe them
  (the fresh record drops every field not listed).

### Add tag (B3.3)

- A tag is a short label on a download, stored on the record:
  `DownloadRecord.tags` (List<String>, default []), persisted
  as a JSON TEXT column (`tags`) in the same v2 migration.
- Engine methods `DownloadEngine.addTag(id, tag)` /
  `removeTag(id, tag)`: tag is trimmed, must be non-empty
  (`invalid-tag` error); unknown id returns silently; adding a
  tag that is already there / removing one that is not are
  no-ops.
- Tags reach the UI: `DownloadInfo.tags` (download_api,
  `@Default([])` — backward-compatible over IPC JSON) and the
  desktop `Download.tags`. The engine's list path populates it
  from the record.
- Menu item 'Add tag' on every row: a submenu (same pattern as
  Set priority) listing every known tag across all downloads,
  with a check on the ones this row has; tapping one toggles it
  (then pops the parent menu, like the priority items). A
  'New tag...' item at the bottom opens `showTextInputDialog`
  (non-empty validation) and adds the tag. The dialog opens
  after popping the menu, so the menu is not left open behind
  it.
- The details panel's GENERAL tab gains a Tags row (comma
  separated, '—' when none): the only place tags are visible
  in this batch.
- No tag filter in this batch: the filter menu is static, and
  dynamic per-tag filter entries are a follow-up.

### Perform virus check (B3.4)

- His instruction: add it to the menu, disabled, for now.
- `_menuItem` gains an optional `{bool enabled = true}` and
  the item is added as `_menuItem('virus_check',
  'Perform virus check', enabled: false)`. A disabled
  PopupMenuItem is greyed out and never fires `onSelected`,
  so no action case and no engine method exist for it.
- The scanner choice (ClamAV `clamscan` on Linux, Windows
  Defender `MpCmdRun` on Windows) is still open, from the
  research doc. Enabling it later is one menu change + the
  engine scan method.

### Final menu order

Open, Show in folder, Set priority, Rename file, Move to...,
state actions, Copy link, Check for update, Change URL, Add
mirror, Export selected downloads, File integrity, Perform virus
check (disabled), Add tag, Delete file, Delete.

## Parts

### B3.1 — File integrity

Files:

- `packages/download_api/lib/src/models/integrity_result.dart`
  (new freezed union) + barrel export + import in
  `download_engine.dart` + `dart run build_runner build` in
  packages/download_api.
- `packages/download_integrity/lib/src/integrity_verifier.dart`
  (new) + barrel export + pubspec deps (`download_api`,
  `crypto`) + `dart pub get`.
- `packages/download_api/lib/src/download_engine.dart`:
  `verifyFile` interface.
- `apps/engine/lib/src/pdm_engine.dart`: `verifyFile`
  implementation.
- `apps/engine/pubspec.yaml`: add the `download_integrity`
  path dep.
- Desktop: datasource → repository → actions passthrough
  (value-returning: the getSegments inline try/catch, NOT
  `_act`); screen item + `_onRowAction` case with snackbars.
- Tests: download_integrity unit tests (ok / missing /
  size-mismatch / unknown total / unreadable / checksum
  match + mismatch), engine tests (unknown id throws,
  completed file ok, missing file, size mismatch), datasource,
  repository, widget tests (completed row shows the result
  snackbar; hidden on a downloading row).
- FakeEngines (3) gain `verifyFile` (return a const neutral
  `IntegrityResult.ok(bytes: 0)`).

### B3.2 — Add mirror

Files:

- `packages/download_recovery/lib/src/download_record.dart`:
  `mirrors` + `tags` fields, copyWith, ==, hashCode.
- `packages/download_recovery/lib/src/download_store.dart`:
  v2 migration (ALTER TABLE ADD COLUMN `mirrors` TEXT,
  `tags` TEXT), CREATE TABLE gains both columns, upsert
  column list + params + ON CONFLICT SET, `_recordFromRow`
  decodes both (null → []).
- `packages/download_api/lib/src/download_engine.dart`:
  `addMirror` interface (`addTag` / `removeTag` come in B3.3).
- `apps/engine/lib/src/pdm_engine.dart`: `addMirror`
  (validate + dedupe + upsert), the `_mirrorIndex` map,
  `_tryFailOver` hooked into `_onSchedulerEvent` before the
  event is forwarded, `_mirrorIndex` cleanup on completion /
  final failure / retry / cancel / delete, fresh-record
  constructions carry `mirrors`/`tags`.
- Desktop: datasource → repository → actions passthrough
  for `addMirror`; screen item + `_onRowAction` early
  handler with `showTextInputDialog` (http(s) validation).
- Tests: store migration test (a v1 DB gains the columns
  and keeps its rows), record/store round-trip for mirrors
  + tags, engine tests (addMirror stores + dedupes + rejects
  a bad URL, failover tries the mirror after the primary
  fails and completes, all mirrors failing emits failed,
  manual retry restarts from the primary, retry/changeUrl
  preserve mirrors/tags), datasource, repository, widget
  tests (dialog + engine call; cancelled dialog calls
  nothing).
- FakeEngines (3) gain `addMirror`, `addTag`, `removeTag`
  (no-op stubs).

### B3.3 — Add tag

Files:

- `packages/download_api/lib/src/models/download_info.dart`:
  `tags` field (`@Default([])`) + build_runner.
- `apps/engine/lib/src/pdm_engine.dart`: `addTag` /
  `removeTag` implementations + list path populates
  `info.tags` from the record.
- `apps/desktop/lib/features/downloads/domain/entities/download.dart`:
  `tags` field, copyWith, props.
- `apps/desktop/lib/features/downloads/data/datasources/download_mapper.dart`:
  map `info.tags`.
- Desktop: datasource → repository → actions passthrough
  for `addTag`/`removeTag`; screen `_tagSubmenu(item)` +
  `_tagItem` (same pattern as Set priority); details panel
  GENERAL tab Tags row.
- Tests: engine tests (add/remove/trim/empty/dedupe),
  datasource, repository, mapper, widget tests (submenu
  toggles a tag, 'New tag...' adds one, details panel shows
  the tags).

### B3.4 — Virus check (disabled menu item)

Files:

- `apps/desktop/lib/features/downloads/presentation/screens/downloads_screen.dart`:
  `_menuItem` gains `{bool enabled = true}`; the
  'Perform virus check' item added after File integrity
  with `enabled: false`.
- Tests: the row-menu count test gains the two new
  always-visible items (virus check + Add tag); a widget
  test taps the disabled item and asserts nothing happens
  (no snackbar, no action).

## Verification (per part, then the batch)

- `flutter test` in apps/desktop, `dart test` in
  apps/engine, each `packages/<name>` suite touched
  (download_integrity, download_recovery, download_api),
  download_ipc + host suites, `flutter analyze` in
  apps/desktop (+ api/engine on interface changes),
  `flutter build linux --release` at the end.
- Commit per part, push, report when each part is done.

## Follow-ups (not in this batch)

- Mirror removal + a mirrors section in the details panel.
- Tag filter (dynamic per-tag entries in the filter menu).
- Virus-check scanner choice + engine scan method.
- A checksum source for the integrity verifier (e.g. a
  `.sha256` sidecar file).
- The engine teardown race (`Directory not empty`) and the
  stale-partial re-add edge remain open from before.
