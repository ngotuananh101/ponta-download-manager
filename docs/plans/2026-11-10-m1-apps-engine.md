# Plan: M2 — apps/engine (2026-11-10)

Scope: `apps/engine` — wire the §16 `DownloadEngine` and the CLI
`download` command so the M1 exit criteria (the CLI downloads
correctly, single-stream and segmented) can be smoke-tested end to
end, plus the small scheduler additions this needs. `serve` stays a
stub: IPC is step 9 (`download_ipc`).

Branch `m1/apps-engine` from `4e0f15d` (limiter committed).
Baseline: limiter 12, scheduler 12, recovery 16, storage 11, core 14,
transport 10, api 3, engine 5, desktop 2, analyze clean.

## Tasks

1. Branch `m1/apps-engine`, this plan file.
2. RED: `test/engine_download_test.dart`. Covers: CLI flags
   (`--dir`, `--connections`, `--db`, `--limit`); end-to-end
   download through `PdmEngine` (segmented, exact bytes, store
   record completed, `listDownloads`); pause/resume; startup
   recovery (engine 1 pauses mid-download and disposes, engine 2
   on the same DB and directory resumes it to exact bytes);
   retry after a failing first probe; priority reorder of queued
   jobs; global limit throttling; the CLI `download` command
   end to end against a local server.
3. GREEN: implement
   - `lib/src/pdm_engine.dart` — `PdmEngine implements
     DownloadEngine`. `PdmEngine.open({config, databasePath,
     limiter})` builds the store (default path:
     `$XDG_DATA_HOME/pdm/pdm.db`, else `~/.local/share/pdm/
     pdm.db` on Linux, `%LOCALAPPDATA%\pdm\pdm.db` on Windows),
     the scheduler with a custom factory (transport, sink,
     limiter, job priority, resume state), the checkpoint
     writer, and a limiter (unlimited unless given). `open`
     runs `Recovery.reconcile()` and requeues: resume ->
     enqueue with the same id, `resumeFrom` and
     `resumeExisting`; restart -> delete the partial file and
     enqueue fresh with the same id; unrecoverable -> marked
     failed with errorCode `unrecoverable`.
   - `createDownload`: splits `request.destination` into
     directory + file name (a bare file name goes under
     `config.downloadDirectory`); maxConnections/priority from
     the request or the config; enqueues, upserts the record,
     returns the queued info.
   - `pauseDownload`/`resumeDownload`/`cancelDownload`:
     delegate to the scheduler and update the store record to
     the requested status, so the state is current at once
     (the writer confirms it on the next event).
   - `retryDownload`: a fresh download of the same URL (new
     id); the old record stays failed; the partial file is
     deleted first.
   - `setPriority`: scheduler `setPriority` (queued and
     paused-running jobs; a running download keeps the
     priority it started with) plus the store record update.
   - `setGlobalBandwidthLimit`/`setDownloadBandwidthLimit`:
     forward to the limiter via the scheduler.
   - `listDownloads`: from the store, mapped to
     `DownloadInfo`. `events`: forwarded from the scheduler.
   - `dispose`: scheduler -> writer -> limiter -> store.
   - `lib/src/download_command.dart` — `runDownload` for the
     CLI: opens the engine, creates the download, waits for
     its terminal event, prints the result, returns the exit
     code. `bin/engine.dart` becomes a thin wrapper over it.
   - `lib/src/cli.dart`: `download` subcommand gains `--dir`,
     `--connections`, `--db`, `--limit`; `serve` usage notes
     IPC comes later.
   - `download_scheduler` additions: `DownloadJob` gains
     optional `resumeFrom` (`List<SegmentProgress>`) and
     `resumeExisting`; `enqueue` gains optional `id` (recovery
     requeues reuse the record id; the id counter skips past
     an explicit `dl-N` id so later generated ids never
     collide), `resumeFrom`, `resumeExisting`; `setPriority`
     rebuilds queued and paused-running jobs with the new
     priority (running jobs are untouched).
4. Verify: `dart pub get`, `flutter analyze`, `dart test` in
   `apps/engine`, `packages/download_scheduler` and
   `packages/download_core`, plus no regressions (limiter 12,
   recovery 16, storage 11, transport 10, api 3, desktop 2).
   Then a manual CLI smoke test: a local file server on his
   machine, `dart run bin/engine.dart download <url> --dir
   <tmp>`, and the downloaded file compared byte for byte.
5. Commit the part on `m1/apps-engine`.

## Done when

- `flutter analyze` reports no issues.
- All `apps/engine`, `download_scheduler` and
  `download_core` tests pass.
- The CLI smoke test downloads a real file end to end.
- No file outside `apps/engine`,
  `packages/download_scheduler` and this plan changes.
