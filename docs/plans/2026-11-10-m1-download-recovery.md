# Plan: M2 — download_recovery (2026-11-10)

Scope: `packages/download_recovery` — SQLite checkpoints and startup
reconciliation (§7.4, §9, §21.6), plus the small additive changes in
`download_core` that make resume possible. No Drift/codegen: a thin
repository over the `sqlite3` package.

Branch `m1/download-recovery` from `4679acd` (scheduler committed).
Baseline: scheduler 11, storage 11, core 14, transport 10, api 3,
engine 5, desktop 2, analyze clean.

## Tasks

1. Branch `m1/download-recovery`, this plan file.
2. RED: `test/download_recovery_test.dart`. Covers: store CRUD +
   non-terminal listing + delete, reopen persistence, checkpoint
   writer (completion, prompt write on pause, periodic write,
   flush), reconcile decisions (resume / restart / complete /
   unrecoverable), task resume from checkpointed progress (only the
   missing ranges are fetched), task `segments` getter.
3. GREEN: implement
   - `lib/src/download_record.dart` — `DownloadRecord` (plain value
     class with `copyWith`; `destinationPath`/`partialPath` derived
     from directory + file name) and `SegmentRecord`.
   - `lib/src/download_store.dart` — `DownloadStore` over
     `sqlite3` (sync API): `open(path)`, `inMemory()`,
     `upsertDownload`, `getDownload`, `listDownloads`,
     `listNonTerminal` (queued/downloading/paused),
     `deleteDownload`, `saveCheckpoint` (record + segments in one
     transaction), `getSegments`, `close`. Tables per §9.1
     (`downloads`, `segments`); `user_version` starts at 1 so later
     migrations have a base.
   - `lib/src/checkpoint_writer.dart` — `CheckpointWriter` tracks
     a `DownloadTask`: subscribes to its events, writes a
     checkpoint every second (timer) and promptly on pause or a
     terminal state, untracks on terminal states, `flush()`,
     `dispose()`.
   - `lib/src/recovery.dart` — `Recovery.reconcile()`, local only:
     final file already correct -> `complete` (and the store is
     updated); partial file missing/empty/larger than the download
     -> `restart`; segment checkpoint inconsistent with the partial
     file (a checkpointed range reaches past the file) ->
     `restart`; no segments and more than one connection ->
     `restart` (layout unknown); no segments and one connection ->
     `resume` from the file size; consistent segments -> `resume`
     with those segments. Empty URL/file name -> `unrecoverable`.
     Remote validation is not done here: the task re-probes and
     validates with `If-Range` on resume.
   - `download_core` additions: `SegmentProgress` (`segmentId`,
     `start`, `end`, `downloaded`); `DownloadTask.segments` getter
     (live snapshot), `resumeFrom` constructor parameter (matched
     by segment id + range, clamped to the segment length; the
     task starts each segment at its checkpointed offset and counts
     the resumed bytes in its total), `eTag` and `finalUrl`
     getters. On a mid-run range-ignored fallback the resumed
     progress is discarded with the rest, as before.
   - `lib/download_recovery.dart` barrel; `pubspec.yaml` gains
     `download_api`, `download_core`, `download_storage`,
     `download_transport`, `logging`, `path`, `sqlite3`.
4. Verify: `flutter pub get` (must resolve `sqlite3` and load the
   system library on his machine), `flutter analyze`, `dart test`
   in `packages/download_recovery` and `packages/download_core`,
   plus no regressions (scheduler 11, storage 11, transport 10,
   api 3, engine 5, desktop 2).
5. Commit the part on `m1/download-recovery`.

## Done when

- `flutter analyze` reports no issues.
- All `download_recovery` and `download_core` tests pass.
- No file outside `packages/download_recovery`,
  `packages/download_core` and this plan changes.
