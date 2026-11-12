# Review fixes — plan

Status: IN PROGRESS

## Source

`docs/reviews/2026-11-12-project-review.md` (2026-11-12, baseline `bcb2e82`,
main menu excluded). Read-only review + standalone probes under
`/tmp/pdm-probe-*`. 40 findings: P1 items 1–6 (data loss / stuck queue,
all VERIFIED), P2 items 7–20 (user-visible incorrect behaviour), P3 items
21–40 (quality, consistency, documentation). 16 items VERIFIED by probe,
the rest CODE-READ.

## His decision 2026-11-12 15:33

"Làm dần hết nhé" — fix all 40, gradually, P1 first, then P2, then P3.

## Method (Superpowers)

Plan first (this doc), then per item: verify the code at the cited
location, RED test reproducing the finding (a probe-style test in the
owning package, following the review's suggested regression tests),
GREEN fix, REFACTOR if needed. Gates per item: the owning package's
`dart test` (or `flutter test` for desktop, `node --test` for the
extension), `flutter analyze` clean for desktop changes. Commit per
item (small related items in one commit when they share one file and one
test run, e.g. items 4+5). Report per batch, then continue. Release
build once after P1 and once at the end.

## Batches

### Batch R-P1a — transport probe phase (items 4, 5, 6)

- 6. `HttpClient` `autoUncompress: true` breaks gzip + segmented
  downloads. Fix: `HttpClient()..autoUncompress = false` (and/or
  `accept-encoding: identity`) in `http_transport.dart:18`. Tests: a
  compressing server (single-stream size-mismatch gone) + a server
  advertising `accept-ranges` with a gzip body (no `FormatException`).
- 4. HEAD and Content-Range never cross-checked. Fix: if
  `validation.totalBytes != null && validation.totalBytes != _total`,
  update `_total` (or fall back to single-stream) before `planSegments`
  (`download_task.dart:113-126`). Test: HEAD says 1024, representation
  2048 → full 2048 bytes downloaded.
- 5. `Content-Length: 0` HEAD completes without GET. Fix: even when
  `_total == 0`, open the stream once and let the size check decide
  (`download_task.dart:124-126`). Test: HEAD 0, GET 100 bytes → 100
  bytes downloaded, not an empty completed file.

### Batch R-P1b — scheduler / task lifecycle (items 1, 2)

- 1. Throwing `sink.close()` leaves a fake `completed` + held slot.
  Fix: guard `_closeSink()` in `download_task.dart:178-181` (try/catch +
  `_fail(DownloadError('close-failed', ...))` + rethrow); scheduler adds
  a `finally`/`catch` on the `run()` future that always calls `_pump()`
  and always emits a terminal event (`download_scheduler.dart:608`).
  Test: close throws → failed event emitted, slot freed (next job
  starts), no `completed` on disk state.
- 2. Pause during the probe keeps downloading + exceeds
  `maxConcurrent`. Fix: `DownloadTask.pause()` accepts `queued`/probing
  (set the flag, check it after probe before switching to
  `downloading`); scheduler calls `_pump()` only once the task actually
  stopped, or guards with a `_starting`-style set
  (`download_scheduler.dart:198-205`, `download_task.dart:184-191`).
  Test: `maxConcurrent=1`, pause dl-1 while probing → dl-2 does NOT
  start, dl-1 ends paused, never completes.

### Batch R-P1c — store migration (item 3)

- 3. v1→v2 migration not atomic. Fix: read
  `PRAGMA table_info(downloads)` and only ALTER when the column is
  missing, and/or wrap `BEGIN … COMMIT` with `userVersion` set inside
  the same transaction (`download_store.dart:75-78`). Test: open a v1 DB
  that already has a `mirrors` column → opens fine, app starts.

### Batch R-P2a — scheduler / checkpoint consistency (items 7, 8, 9, 11, 12, 13)

- 7. Checkpointing overwrites tags/priority/mirrors the user just
  changed. Fix: checkpoint UPDATEs only progress columns, or re-reads
  the record before writing (`checkpoint_writer.dart:197-213`). Test:
  addTag/setPriority while running → checkpoint keeps them.
- 8. `setPriority` drops `overwrite`. Fix: add
  `overwrite: job.overwrite` to `_withPriority`
  (`download_scheduler.dart:259-271`); audit every `DownloadJob` field
  when rebuilding. Test: enqueue overwrite + setPriority → retry works.
- 9. `_pausedWhileStarting` leaks when the task factory throws. Fix:
  clear `_pausedWhileStarting` / `_cancelledWhileStarting` in a
  `try/finally` inside `_start`; on the error path report the failure
  rather than honouring the pause (`download_scheduler.dart:479-552`).
  Test: factory throws → retry of the same id runs.
- 11. `HttpException` mid-body is not retried. Fix: `handleError` in
  `openStream` converting `HttpException`/`SocketException` to
  `DownloadError('network')` (`download_task.dart:302-353`,
  `http_transport.dart:126-165`). Test: connection closed mid-body →
  retried, completes.
- 12. Cancel cannot interrupt a pending token-bucket wait (CODE-READ).
  Fix: check `_cancelled` before `acquire`, or race `acquire` against a
  cancellable future (`download_task.dart:379-388`). Test: cancel during
  a throttled wait returns promptly.
- 13. Lowering the rate keeps the old burst + tokens. Fix: on a rate
  change, `_burst = min(_burst, rate)` and
  `_tokens = min(_tokens, _burst)` (`token_bucket.dart:45-52`). Test:
  1 MiB/s → 1024 B/s → `acquire(4096)` takes ~4 s, burst is 1024.

### Batch R-P2b — engine / storage / yt-dlp / IPC (items 10, 14, 15, 16, 17, 19, 20)

- 10. `openExisting()` creates an empty partial when the file is gone;
  `finish()` renames without checking the destination. Fix:
  `existsSync()` first, throw `partial-missing`; `finish()` checks for
  an existing destination or logs the overwrite
  (`file_chunk_sink.dart:56-62`, `:116-127`). Test: missing partial →
  `partial-missing`, not an empty file.
- 14. yt-dlp deletes/guesses files by stem prefix. Fix: match
  `name == stem + ext` against a known extension list, or keep the exact
  path yt-dlp printed and delete only that file
  (`yt_dlp_downloader.dart:234-256`, `:275-302`,
  `pdm_engine.dart:165-169`). Test: `video_2.mp4` next to `video.mp4`
  survives `deleteOutput`.
- 15. Failure reason lost after a restart (CODE-READ). Fix: add
  `errorCode`/`errorMessage` to `DownloadInfo` (freezed; needs a
  protocol bump) or carry the message through `download.sync`
  (`pdm_engine.dart:1144-1157`). Test: restart → failed row still shows
  its tooltip.
- 16. Resume/pause have no terminal-state guards (CODE-READ). Fix:
  allow only `paused → queued` and `queued/downloading → paused`;
  otherwise no-op or `invalid-state` (`pdm_engine.dart:450-479`).
  Test: resume on completed → no-op, stored status stays completed.
- 17. `_ytDlpSubs` never pruned (CODE-READ). Fix: in `_onYtDlpEvent`,
  on a terminal event cancel + `remove(id)`
  (`pdm_engine.dart:181-182`). Test: resume twice → one subscription.
- 19. IPC line limits only apply when a chunk has no newline
  (CODE-READ). Fix: check `_buffer.length` after each `addAll` and
  before `jsonDecode`; cap outbound too (`ipc_channel.dart:84-102`).
  Test: one huge line arriving with its newline in the same chunk →
  rejected.
- 20. Hello sends its snapshot out of order (CODE-READ, race). Fix:
  `await _sendSync()`, or buffer broadcasts until the snapshot is sent
  (`ipc_server.dart:161-163`). Test: events during hello do not
  overtake the snapshot.

### Batch R-P2c — Windows paths (item 18)

- 18. Windows paths cannot work (CODE-READ, Linux host). Pick the
  transport by `Platform` (`LoopbackTcpTransport` exists but is unused);
  wrap startup in try-catch and surface the error in the UI
  (`main.dart:22`); fix `disk_space_service.dart:14` (`fsutil` needs
  admin); split the explorer args in `file_opener.dart:25,38`
  (`['/select,', path]`). Tests where possible on Linux (arg
  splitting, transport selection); the rest is code-verified + manual
  check on Windows deferred to Tuấn Anh.

### Batch R-P3a — table / engine consistency (items 21–29)

- 21. "Yesterday" wrong across a DST change: use
  `DateTime(y, m, d - 1)` (`download_table.dart:58`). Test with a DST
  date (Europe/Berlin, 30 Mar).
- 22. `%` in Content-Disposition throws `ArgumentError`: wrap
  `Uri.decodeComponent` in try/catch with a path-segment fallback
  (`http_transport.dart:260`).
- 23. `_finalUrl` can be a relative URI: use
  `url.resolveUri(location)` (`http_transport.dart:247-252`).
- 24. Per-segment Content-Range never validated: validate `start`/`end`
  on every 206 (`http_transport.dart:141-142`).
- 25. No global connection cap: spec (`docs/architecture.md:326`)
  requires "Maximum total connections"; only `maxConcurrent ×
  maxConnections` exists. Decision needed on the cap value during
  execution (propose a single global cap, default 16, configurable
  later via Settings).
- 26. `renameFile`/`moveFile` skip `_isDestinationTaken`: use it
  (`pdm_engine.dart:669,697`, helper at `:328`).
- 27. Recovery treats "size matches" as done: delete the leftover
  `.partial` / verify content; no orphaned `.partial` files
  (`recovery.dart:47-63`).
- 28. "Set priority" offered for `downloading` rows: hide/disable it —
  the scheduler ignores a running job's priority
  (`downloads_screen.dart:865-870`).
- 29. Hardcoded colour `0xFFF4F5F5`: use a theme colour
  (`downloads_screen.dart:182,211`).

### Batch R-P3b — extension / scripts / docs (items 30–40)

- 30. `mediaByTab` is a `Map` in an MV3 service worker: use
  `chrome.storage.session` (`background.js:14`).
- 31. `loadInterceptSetting` sets `interceptEnabled = true` before the
  storage callback: read the stored value first
  (`background.js:174-176`).
- 32. Manifest cannot run on Firefox: only
  `background.service_worker`; README + `install.sh` still advertise
  Firefox — add the Firefox background script or drop the claim.
- 33. `endpointExists()` = token + socket both present: leftovers from
  a crash make `launchAndWait()` return true without launching
  (`app_launcher.dart:93-95`).
- 34. `install.sh` has no `mkdir -p`: `dart compile exe` fails without
  `~/.local/bin` (`install.sh:13`).
- 35. `linux_usable` calls `--version`: ffmpeg exits 8 for `--version`,
  0 for `-version` → re-downloads every time
  (`tools/fetch_external_tools.sh:55-57`). (Note: the `-version` rule is
  already known from the yt-dlp work; verify which call still uses
  `--version`.)
- 36. `download_platform` / `download_database` are TODO stubs: decide
  during execution — implement the minimal real content or delete the
  packages.
- 37. README is stale: root + desktop READMEs (in-memory datasource M3
  claim, nonexistent root `test/`).
- 38. `.gitignore` excludes `apps/desktop/bundle/`: a clean clone has no
  ffmpeg/yt-dlp; test the tool-fetch path.
- 39. `TokenBucket._pump` is head-of-line: a large request blocks
  smaller ones; burst can grow to the largest pending request.
- 40. `verifyFile` passes `expectedBytes: record.totalBytes` which can
  be `-1`, skipping the size check (`pdm_engine.dart:838-849`).

## Verification (manual, by Tuấn Anh after re-running)

- P1: a gzip-served file downloads byte-correct; a lying HEAD no longer
  truncates; a download that fails on close reports failed and frees
  the slot; pausing during the probe pauses for real.
- P2/P3 spot checks per item as listed in each batch.

## Follow-ups (not in this plan)

- Item 25's global-cap default value if the proposed 16 is wrong.
- Item 36 if deleting the stub packages is preferred over implementing
  them.
- Item 18's Windows behaviour still needs a real Windows run.
