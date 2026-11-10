# Plan: M1 — download_core (2026-11-10)

Scope: `packages/download_core` — segment planning (§5.4), single-task
execution (§6, §7.1–§7.4): probe → validate → plan → concurrent segment
workers → progress/pause/resume/cancel → completion. Plus one small
additive change to `download_transport`: optional `ifRange` on
`openStream` (needed for §7.4 safe resume). No SQLite, no scheduler,
no engine wiring — those are the next parts.

Branch `m1/download-core` from `4aff79e` (transport committed).
Baseline: transport 10 pass, api 3, engine 5, desktop 2, analyze clean.

## Tasks

1. Branch `m1/download-core`, this plan file.
2. RED: `test/download_core_test.dart` — planner unit tests plus task
   tests against a local `HttpServer` (`/file` range-capable with
   recorded ranges, `/no-range`, `/flaky` 500-on-first-GET, `/slow-big`
   5 MB drip, `/not-found`). Covers: planner invariants, single-stream
   exact bytes, segmented exact bytes with several ranges used,
   pause/resume, cancel, range-fallback to single-stream, retry after
   a transient 500, 404 failure, If-Range header sent on resume.
3. GREEN: implement
   - `lib/src/segment.dart` — `Segment` (stable id, start, end or null
     for unknown length).
   - `lib/src/segment_planner.dart` — `planSegments` (§5.4: no gaps,
     no overlaps, stable ids; unknown length → one open segment;
     zero length → no segments).
   - `lib/src/chunk_sink.dart` — `ChunkSink` interface (`write(offset,
     bytes)`, `close`); the writer coordinator owns writes (§6.2);
     the file-backed sink lives in `download_storage` (next part).
   - `lib/src/download_task.dart` — `DownloadTask`: `run()` returns
     `DownloadInfo`; `pause()`, `resume()`, `cancel()`; `events`
     stream (`DownloadEvent` from `download_api`). Flow: probe →
     validate range → plan → segment workers (each re-opens its
     range from its current offset; `await for` over the stream so
     `sink.write` applies backpressure, §6.1). A segment is complete
     only after its bytes are written (§6.3). Pause cancels active
     subscriptions and waits on a resume gate; resume re-opens ranges
     from current offsets with `If-Range` when an ETag is known (§7.4).
     A range request answered with more bytes than requested means
     the server ignored Range: restart the segment once, then fall
     back the whole task to single-stream. Transient errors
     (network, timeout, 429, 5xx) retry with exponential backoff up
     to `maxRetries` (§7.3); other errors fail the task.
   - `lib/download_core.dart` barrel; `pubspec.yaml` gains
     `download_api`, `download_transport` (path), `logging`.
4. Verify: `flutter pub get`, `flutter analyze`, `dart test` in
   `packages/download_core`, plus no regressions (transport 10,
   api 3, engine 5, desktop 2).
5. Commit the part on `m1/download-core`.

## Done when

- `flutter analyze` reports no issues.
- All `download_core` tests pass, including pause/resume/cancel
  against the local server.
- No file outside `packages/download_core`, the `ifRange` addition in
  `packages/download_transport`, and this plan changes.
