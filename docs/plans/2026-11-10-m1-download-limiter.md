# Plan: M2 — download_limiter (2026-11-10)

Scope: `packages/download_limiter` — token-bucket bandwidth limiting
(§10, §21.7), plus the small additive wiring in `download_core` and
`download_scheduler` that makes a limit actually throttle a download.
No new external dependency: the bucket is pure Dart.

Branch `m1/download-limiter` from `5344f92` (recovery committed).
Baseline: recovery 16, scheduler 11, storage 11, core 14, transport 10,
api 3, engine 5, desktop 2, analyze clean.

## Tasks

1. Branch `m1/download-limiter`, this plan file.
2. RED: `test/download_limiter_test.dart`. Covers: token bucket
   (unlimited, rate enforcement, runtime `setRate` waking waiters,
   priority order, burst), limiter (per-download limit, global limit
   across downloads, runtime `setGlobalLimit`, per-download override
   surviving a default change, `removeDownload`), task throttle
   (a task with a limiter downloads at the limited rate with exact
   bytes), scheduler wiring (a scheduler with a limiter completes a
   real local download, and the limiter is engaged).
3. GREEN: implement
   - `lib/src/token_bucket.dart` — `TokenBucket`: queue-based token
     bucket. Tokens refill from a `Stopwatch` at the configured
     rate, capped at the burst (default: one second of rate).
     Requests wait in a queue ordered by priority desc, arrival
     asc; the head is served when its bytes are available, and a
     timer wakes the pump when they will be. `setRate`/`setBurst`
     take effect at once (pending waiters are re-evaluated).
     `rateBytesPerSecond: null` is unlimited. `dispose` cancels
     the timer and fails pending requests.
   - `lib/src/bandwidth_limiter.dart` — `BandwidthLimiter`: a
     global bucket plus one bucket per download id. `acquire(id,
     bytes, {priority})` waits on both buckets at once, so neither
     limit can be exceeded. `setGlobalLimit`,
     `setPerDownloadLimit` (updates the default and every bucket
     without an explicit override), `setDownloadLimit` (override
     for one download), `removeDownload`, `dispose`. The limiter
     is owned by its caller, never by the scheduler.
   - `lib/src/bandwidth_unit.dart` — `BandwidthUnit` (bytes/s,
     KiB/s, MiB/s) with `toBytesPerSecond`.
   - `download_core` additions: `DownloadTask` gains optional
     `limiter` (`BandwidthLimiter?`) and `priority` (default 0);
     each received chunk waits on the limiter before it is
     written. `download_core` depends on `download_limiter`
     (one-way; the limiter package itself has no engine deps).
   - `download_scheduler` additions: optional `limiter`
     constructor parameter; the default factory passes it and the
     job priority to the task; `setGlobalBandwidthLimit` and
     `setPerDownloadBandwidthLimit` forward to it (no-op without
     a limiter). A custom `taskFactory` wires its own limiter —
     that is the engine's job later.
   - `lib/download_limiter.dart` barrel; `pubspec.yaml` with
     `resolution: workspace` (required, see AGENTS.md).
4. Verify: `flutter pub get`, `flutter analyze`, `dart test` in
   `packages/download_limiter`, `packages/download_core` and
   `packages/download_scheduler`, plus no regressions (recovery 16,
   storage 11, transport 10, api 3, engine 5, desktop 2).
5. Commit the part on `m1/download-limiter`.

## Done when

- `flutter analyze` reports no issues.
- All `download_limiter`, `download_core` and
  `download_scheduler` tests pass.
- No file outside `packages/download_limiter`,
  `packages/download_core`, `packages/download_scheduler` and
  this plan changes.
