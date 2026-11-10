# Plan: M2 — download_scheduler (2026-11-10)

Scope: `packages/download_scheduler` — global scheduler (§8.3,
§21.5): priority queue, limit on concurrent downloads (default 3),
per-job pause/resume/cancel, event forwarding, downloads snapshot.
In-memory only: no SQLite (`download_database`/`download_recovery`),
no bandwidth limiting (`download_limiter`), fixed limit — adaptive
concurrency later via `setMaxConcurrent`.

Branch `m1/download-scheduler` from `af99e44` (storage committed).
Baseline: storage 11, core 14, transport 10, api 3, engine 5,
desktop 2, analyze clean.

## Tasks

1. Branch `m1/download-scheduler`, this plan file.
2. RED: `test/download_scheduler_test.dart`. Unit tests use the real
   `DownloadTask` against a fake transport (controllable streams,
   per-URL probe failure) plus a null sink; one integration test uses
   the default factory (`HttpTransport` + `FileChunkSink`) against a
   local `HttpServer`. Covers: maxConcurrent, priority order, pause
   frees a slot + resume finishes (with `If-Range` recorded),
   pauseAll/resumeAll, cancel of a queued job, cancel of a running
   job, a failed job does not block the queue, `setMaxConcurrent`,
   snapshot state, dispose.
3. GREEN: implement
   - `lib/src/download_job.dart` — immutable `DownloadJob`
     (`id`, `url`, `fileName`, `directory`, `priority`,
     `maxConnections`, `sequence`).
   - `lib/src/download_scheduler.dart` — `DownloadScheduler`,
     `ScheduledTask` (task + sink), `DownloadTaskFactory`.
     `enqueue()` returns `dl-N`. Paused running jobs free their
     slot and resume re-enters the queue with the existing task.
     `pause()`/`resume()`/`cancel()` by id, `pauseAll()`/
     `resumeAll()`, `setMaxConcurrent()` (validates >= 1),
     `downloads` snapshot (enqueue order), `events` broadcast
     forwarding task events plus scheduler lifecycle events,
     `dispose()`.
   - Default factory builds `HttpTransport` (or the injected one)
     + `FileChunkSink.create` + `DownloadTask`. On a completed run
     the scheduler finishes the sink (renames `.partial` to the
     final path); failed/cancelled runs keep the partial file for
     resume. A factory/start failure marks the job failed with a
     `DownloadFailed` event. `_onTaskError` does not re-emit: the
     task already emits `DownloadFailed` before `run()` throws
     (verified in `download_task.dart`). Pause/cancel while a task
     is still being built are tracked with flags and applied when
     the task exists; the sink is closed directly when a
     never-started task is cancelled.
   - `lib/download_scheduler.dart` barrel; `pubspec.yaml` gains
     `download_api`, `download_core`, `download_storage`,
     `download_transport` (path), `logging`.
4. Verify: `flutter pub get`, `flutter analyze`, `dart test` in
   `packages/download_scheduler`, plus no regressions (storage 11,
   core 14, transport 10, api 3, engine 5, desktop 2).
5. Commit the part on `m1/download-scheduler`.

## Done when

- `flutter analyze` reports no issues.
- All `download_scheduler` tests pass.
- No file outside `packages/download_scheduler` and this plan changes.
