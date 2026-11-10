# Plan: M1 — download_storage (2026-11-10)

Scope: `packages/download_storage` — the file-backed `ChunkSink`
(§6, §6.4): serialized random-access writes to a partial file,
exclusive creation, atomic rename on finish, discard, reopen for
resume. No SQLite (`download_database`), no checkpoints
(`download_recovery`), no disk-space check (no `dart:io` API for it;
deferred to `download_platform`).

Branch `m1/download-storage` from `5aeb1f4` (core committed).
Baseline: core 14, transport 10, api 3, engine 5, desktop 2,
analyze clean.

## Tasks

1. Branch `m1/download-storage`, this plan file.
2. RED: `test/download_storage_test.dart` — temp dirs only, no
   network. Covers: out-of-order writes, concurrent writes from
   many workers, exclusive creation, reopen-and-resume, finish
   rename, discard, write-after-close, idempotent close, `filePath`
   vs `partialPath`, length with a sparse gap.
3. GREEN: implement
   - `lib/src/file_chunk_sink.dart` — `FileChunkSink implements
     ChunkSink`. One coordinated writer (§6.2): concurrent `write`
     calls are serialized through a future chain, so no two writes
     touch the `RandomAccessFile` at once. `write(offset, bytes)`
     validates the offset and positions before writing; empty
     writes are a no-op. `close()` drains pending writes, flushes
     and closes the handle (idempotent). `finish()` closes and
     atomically renames the partial file to the final path.
     `discard()` closes and deletes the partial file. `create()`
     makes parent dirs, refuses when the final path or the partial
     file already exists (`DownloadError` `file-exists`, §6.4).
     `openExisting()` reopens a partial file without truncating
     (resume). `filePath` is the final destination;
     `partialPath` is the in-progress file. `length` reports the
     current file size.
   - `lib/download_storage.dart` barrel; `pubspec.yaml` gains
     `download_api`, `download_core` (path), `logging`, `path`.
4. Verify: `flutter pub get`, `flutter analyze`, `dart test` in
   `packages/download_storage`, plus no regressions (core 14,
   transport 10, api 3, engine 5, desktop 2).
5. Commit the part on `m1/download-storage`.

## Done when

- `flutter analyze` reports no issues.
- All `download_storage` tests pass.
- No file outside `packages/download_storage` and this plan changes.
