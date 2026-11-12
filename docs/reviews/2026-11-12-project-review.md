# Project review — bugs and improvement points

- **Repo:** `pdm`
- **Baseline:** `bcb2e82` (the in-progress main-menu feature is excluded from scope)
- **Date:** 2026-11-12
- **Method:** read-only. No source file was modified; every conclusion comes
  from reading the source and from standalone probes under `/tmp/pdm-probe-*`.

## Baseline health (re-confirmed during the review)

| Item | Result |
|---|---|
| All package + engine + native host suites | 14/14 pass — `FAILED_SUITES=0` |
| Desktop widget/unit tests | 253/253 pass |
| Browser extension (JS) | 29/29 pass |
| `dart analyze` | exit 0, 7 info hints |

The bugs below therefore live in paths that have no test, or in
platform-specific code — not in what the current suite covers.

## Evidence labels

- **VERIFIED:** reproduced with a standalone Dart probe (loopback HTTP
  server, fake transport/sink, real SQLite) during this review.
- **CODE-READ:** source read and line numbers checked; not reproduced at
  runtime.

---

## P1 — Data loss or a stuck queue

### 1. A throwing `sink.close()` leaves the download "completed" with a `.partial` file and never frees the slot — VERIFIED

**Location:** `packages/download_core/lib/src/download_task.dart:178-181`,
`packages/download_scheduler/lib/src/download_scheduler.dart:608`

`finally { await _closeSink(); }` is not guarded. The task has already
emitted `completed` (`_finish`, lines 218-233) when `run()` throws the
`StateError`. Because `run()` throws, `_onTaskDone` never runs: `_onTaskEvent`
has already set `_infos[id] = completed`, but no `stateChanged(completed)` /
`completed` event is emitted, `sink.finish()` (the rename) never runs, and
`_pump()` never runs — the slot is held forever.

**Trigger:** disk full, or the partial file deleted externally while
`flush()` + `close()` run. `FileChunkSink.close()` can throw either way.

**Evidence (probe `sk3.dart`):** only `queued → downloading → progress` are
emitted; `downloads` reports `completed`; the file on disk is still the
`.partial` one.

**Suggested fix:** wrap `_closeSink()` in `try/catch` and `_fail(DownloadError('close-failed', ...))`
plus rethrow on failure. In the scheduler, add a `finally`/`catch` on the
`run()` future that always calls `_pump()` and always emits a terminal event.

### 2. Pausing during the probe marks the download paused in the DB while it keeps downloading and completes, and it exceeds `maxConcurrent` — VERIFIED

**Location:** `download_scheduler.dart:198-205`, `download_task.dart:184-191`
(`if (_status != DownloadStatus.downloading) return;`)

Inside `run()` the status stays `queued` for the whole probe/validate phase
(`download_task.dart:110` sets queued, line 127 sets downloading).
The scheduler's `pause()` already did `_running.remove(id)` +
`_pausedRunning[id] = ...` + `_pump()` — i.e. it released the slot — while
`task.pause()` returns early because the status is `queued`.

**Evidence (probe `pp.dart`):** with `maxConcurrent=1`, pausing `dl-1` while it
probes starts `dl-2` (two slots in use), and `dl-1` still goes
`downloading → completed`. The engine also writes `paused` to the store
(`pdm_engine.dart:457-458`), so the UI shows paused while the file is
finishing.

**Suggested fix:** let `DownloadTask.pause()` accept `queued`/probing (set the
flag, check it after probe before switching to `downloading`); have the
scheduler call `_pump()` only once the task actually stopped, or guard with a
`_starting`-style set.

### 3. The v1→v2 schema migration is not atomic: dying halfway bricks the DB permanently — VERIFIED

**Location:** `packages/download_recovery/lib/src/download_store.dart:75-78`

The two `ALTER TABLE ... ADD COLUMN` statements run outside a transaction,
do not check whether the column exists, and `userVersion` is set only after
both complete.

**Evidence (probe `pdm-probe-migrate`):** a v1 DB that already has a `mirrors`
column → `SqliteException(1): duplicate column name: mirrors` →
`DownloadStore.open()` throws → the app cannot start, and it stays that way.

**Suggested fix:** read `PRAGMA table_info(downloads)` and only ALTER when the
column is missing, or wrap `BEGIN … COMMIT` and set `userVersion` inside the
same transaction.

### 4. HEAD and Content-Range are never cross-checked, so a truncated file still reports `completed` — VERIFIED

**Location:** `packages/download_transport/lib/src/http_transport.dart:231-245`,
`packages/download_core/lib/src/download_task.dart:113-126`

`_total` comes from HEAD; `validateRange` returns `totalBytes` (from
Content-Range) but it is **ignored** (`segmented = validation.valid`). If HEAD
says 1024 while the representation is 2048, the segment plan covers only 1024
bytes, `_downloaded == _total`, and the download completes.

**Evidence (probe `c6.dart`):** `status=completed total=1024 dl=1024` while the
server has 2048 bytes; `content-equal=false`.

**Suggested fix:** if `validation.totalBytes != null && validation.totalBytes != _total`,
update `_total` (or fall back to single-stream) before `planSegments`.

### 5. A `Content-Length: 0` HEAD response completes immediately without ever issuing a GET — VERIFIED

**Location:** `download_task.dart:124-126` (`if (_total == 0) return _finish(completed);`)

A CDN or endpoint that answers HEAD with 0 (or a broken HEAD) makes the user
receive an empty file marked successful.

**Evidence (probe `head0.dart`):** HEAD `content-length: 0`, GET returns 100
bytes → `status=completed total=0 dl=0 sinkMax=0`.

**Suggested fix:** even when `_total == 0`, open the stream once (or restart
single-stream) and let the size check decide.

### 6. `HttpClient` defaults to `autoUncompress: true`, breaking every gzip server and every segmented download — VERIFIED

**Location:** `http_transport.dart:18`

Dart adds `accept-encoding: gzip` on its own (confirmed by probe `ae.dart`: the
server receives `accept-encoding=gzip`) and decompresses the body, so
`Content-Length` (compressed bytes) differs from the bytes received.

**Evidence:**
- `g2.dart` (single-stream, gzip body of 4096 bytes behind a 40-byte header):
  `DownloadError(size-mismatch): Downloaded 4096 bytes, expected 40`.
- `g1.dart` (server advertising `accept-ranges`):
  `DownloadError(internal): FormatException: Filter error, bad data` — the
  range cuts through the middle of the gzip stream.

**Suggested fix:** `HttpClient()..autoUncompress = false` (and/or send
`accept-encoding: identity`). File downloads do not want transfer encoding.

---

## P2 — User-visible incorrect behaviour

### 7. Checkpointing overwrites `tags` / `priority` / `mirrors` the user just changed — VERIFIED

**Location:** `packages/download_recovery/lib/src/checkpoint_writer.dart:197-213`

`_TrackedTask.record` is a snapshot taken at `track()`; every `_writeStatus`
writes **all** columns through `upsertDownload`, discarding changes made on
other paths (engine `addTag`, `setPriority`, `addMirror`).

**Evidence (probe `pdm-probe-clobber`):** `after user edit: tags=[iso] priority=1`
→ `after checkpoint: tags=[] priority=0`.

**Suggested fix:** have the checkpoint UPDATE only progress columns (`status`,
`downloaded_bytes`, `total_bytes`, `etag`, `last_modified`, `final_url`,
`updated_at`), or re-read the record from the store before writing.

### 8. `setPriority` drops `overwrite`, so retrying a completed download always fails with `file-exists` — VERIFIED

**Location:** `download_scheduler.dart:259-271` (`_withPriority` does not copy `overwrite`)

**Evidence (probe `ow.dart`):** enqueue with `overwrite: true` for an existing
file → `setPriority(id, 1)` → `failed:dl-9:file-exists:Destination already exists: data/a.bin`.

**Suggested fix:** add `overwrite: job.overwrite` to `_withPriority` — and audit
every `DownloadJob` field when rebuilding; this is the only one currently
missing.

### 9. `_pausedWhileStarting` leaks when the task factory throws, leaving a retry of the same id stuck in `queued` — VERIFIED

**Location:** `download_scheduler.dart:479-552`

The flag is only removed on the success path. A throwing factory (e.g.
`file-exists`) lands in the `catch` at 545-552 and the flag survives. The next
`enqueue(id: 'dl-1')` — which is exactly what `retryDownload` does — is treated
by the branch at 499 as "paused while starting" and parked in `_pausedRunning`
without ever running.

**Evidence (probe `leak.dart`):** after the retry: `info: dl-1:queued`, and no
`downloading` event is ever emitted.

**Suggested fix:** clear `_pausedWhileStarting` / `_cancelledWhileStarting` for
the id in a `try/finally` inside `_start`; on the error path, report the
failure rather than honouring the pause.

### 10. `openExisting()` creates an empty partial when the file is gone, and `finish()` renames without checking the destination — VERIFIED

**Location:** `packages/download_storage/lib/src/file_chunk_sink.dart:56-62`, `:116-127`

`File(partialPath).open(mode: FileMode.append)` **creates** the file when it is
missing; `await File(partialPath).rename(filePath)` silently overwrites the
destination on POSIX.

**Evidence (probe `pdm-probe-append`):** `missing-created=true len=0`.

**Suggested fix:** `openExisting` should `existsSync()` first and throw
`partial-missing`; `finish()` should check for an existing destination or at
least log when it overwrites.

### 11. An `HttpException` mid-body is not retried (only `DownloadError` is) — VERIFIED

**Location:** `download_task.dart:302-353` + `http_transport.dart:126-165` (no `handleError`)

`_runSegment` catches only `_RangeIgnored` and `DownloadError`; an
`HttpException` escaping from the body stream propagates straight out of
`run()` as `internal`.

**Evidence (probe `r6.dart`):**
`DownloadError(internal): HttpException: Connection closed while receiving data retries(opens)=1`
— exactly one stream open, no retry.

**Suggested fix:** attach `handleError` in `openStream` to convert
`HttpException`/`SocketException` into `DownloadError('network')` so
`_isTransient` can retry them.

### 12. Cancel cannot interrupt a pending token-bucket wait — CODE-READ

**Location:** `download_task.dart:379-388`

`await throttle.acquire(...)` runs **before** the `_cancelled`/`_paused` check.
At a low rate, cancelling has to wait for a full chunk's worth of tokens.

**Suggested fix:** check `_cancelled` before `acquire`, or race `acquire`
against a cancellable future tied to the cancel gate.

### 13. Lowering the rate keeps the old burst and pre-accumulated tokens, so the bandwidth cap does not apply — VERIFIED

**Location:** `packages/download_limiter/lib/src/token_bucket.dart:45-52`

`setRate` only sets `_burst` when `_burst == 0`, and never clamps `_tokens`.

**Evidence (probe `pdm-probe-limit/p2.dart`):** after going 1 MiB/s → 1024 B/s,
`acquire(4096)` takes 0 ms and `burst=1048576`.

**Suggested fix:** on a rate change, `_burst = min(_burst, rate)` (or apply the
configured burst) and `_tokens = min(_tokens, _burst)`.

### 14. yt-dlp deletes and guesses files by stem prefix, so it can remove unrelated files — CODE-READ

**Location:** `packages/download_external/lib/src/yt_dlp_downloader.dart:234-256`, `:275-302`;
`apps/engine/lib/src/pdm_engine.dart:165-169`

`name.startsWith(stem)` matches `video_2.mp4` and `video-old.mkv` too. The
playlist template uses `basenameWithoutExtension`, so `clip.m3u8` yields the
stem `clip`, which collides easily. `deleteOutput` deletes all of them.

**Suggested fix:** match `name == stem + ext` against a known extension list, or
keep the exact path yt-dlp printed and delete only that file.

### 15. The failure reason is lost after a restart — CODE-READ

**Location:** `apps/engine/lib/src/pdm_engine.dart:1144-1157`

`_infoFromRecord` does not map `errorCode`/`errorMessage` (the record has both,
and the UI datasource reads `errorMessage` for its tooltip —
`downloads_screen.dart:828`). After a restart the failure tooltip is empty.

**Suggested fix:** add both fields to `DownloadInfo` (the model is freezed;
this needs a protocol bump), or at least carry the message through
`download.sync`.

### 16. Resume/pause have no terminal-state guards — CODE-READ

**Location:** `pdm_engine.dart:450-479`

`resumeDownload` on a `completed` record sets `queued` and then either
`_startYtDlp` (playlists) or a no-op `_scheduler.resume` — leaving the stored
status wrong. `pauseDownload` on a finished record also writes `paused`.

**Suggested fix:** allow only `paused → queued` and `queued/downloading → paused`;
otherwise no-op or return `invalid-state`.

### 17. `_ytDlpSubs` is never pruned, leaking a subscription on every resume — CODE-READ

**Location:** `pdm_engine.dart:181-182` (cancelled only in `dispose`, line 933)

**Suggested fix:** in `_onYtDlpEvent`, on a terminal event (completed/failed/
cancelled) call `cancel()` and `remove(id)`.

### 18. The Windows paths cannot work — CODE-READ (the review host is Linux)

- `apps/desktop/lib/app/engine_ipc_host.dart:25` hardcodes `UnixSocketTransport`;
  `packages/download_ipc/lib/src/paths.dart:10-26` returns
  `%LOCALAPPDATA%\pdm\engine.sock`, and Dart cannot bind a Unix socket on
  Windows (only Linux/macOS/Android).
- `apps/desktop/lib/main.dart:22` awaits unconditionally with no
  `runZonedGuarded`/try-catch, so the app dies before the first frame with no
  message.
- `apps/desktop/lib/features/downloads/data/services/disk_space_service.dart:14`
  runs `fsutil volume diskfree` (needs admin) → free space is null for a
  standard user.
- `apps/desktop/lib/features/downloads/data/services/file_opener.dart:25,38`:
  `explorer` commonly exits non-zero, and `'/select,$path'` breaks on paths
  containing spaces (it must be `['/select,', path]`).

**Suggested fix:** pick the transport by `Platform` (`LoopbackTcpTransport`
already exists but is used nowhere), wrap startup in try-catch and surface the
error in the UI, use a different free-space API, and split the explorer
arguments.

### 19. IPC line limits only apply when a chunk contains no newline — CODE-READ

**Location:** `packages/download_ipc/lib/src/ipc_channel.dart:84-102`

`maxLineBytes` is checked only in the `newline == -1` branch; a single huge
line that arrives with its `\n` in the same chunk is never checked
(`_emitLine` does not check either). `send()` has no size limit at all.

**Suggested fix:** check `_buffer.length` after each `addAll` and before
`jsonDecode`; cap the outbound direction too.

### 20. Hello sends its snapshot out of order — CODE-READ (race)

**Location:** `packages/download_ipc/lib/src/ipc_server.dart:161-163`

`send(hello-ok)` is followed by an **un-awaited** `_sendSync()`. An engine
event emitted in the meantime can overtake the snapshot, so the client applies
a stale snapshot on top of a newer event.

**Suggested fix:** `await _sendSync()`, or buffer broadcasts until the snapshot
has been sent.

---

## P3 — Quality, consistency, documentation

| # | Issue | Location | Suggestion |
|---|---|---|---|
| 21 | "Yesterday" is wrong across a DST change | `download_table.dart:58` — `today.subtract(Duration(days: 1))` | Use `DateTime(y, m, d - 1)`. Probe `dst.dart` (Europe/Berlin, 30 Mar): `today-24h = 28 Mar 23:00`, so 29 Mar renders as a regular date |
| 22 | A `%` in `Content-Disposition` throws `ArgumentError` | `http_transport.dart:260` | Wrap `Uri.decodeComponent` in try/catch with a path-segment fallback. Probe `c1.dart`: `Invalid URL encoding` |
| 23 | `_finalUrl` can be a relative URI | `http_transport.dart:247-252` | Use `url.resolveUri(location)`. Probe `redir.dart`: `redirects=[/sub/b]` |
| 24 | Per-segment Content-Range is never validated | `http_transport.dart:141-142` | A server returning the wrong range writes wrong offsets yet still completes — validate `start`/`end` on every 206 |
| 25 | No global connection cap | `docs/architecture.md:326` | The spec requires "Maximum total connections"; the repo only has `maxConcurrent × maxConnections` |
| 26 | `renameFile`/`moveFile` skip `_isDestinationTaken` | `pdm_engine.dart:669,697` | They only check `File(target).existsSync()`, missing the race with an in-flight download; `_isDestinationTaken` already exists at :328 |
| 27 | Recovery treats "size matches" as done | `recovery.dart:47-63` | It does not delete the leftover `.partial` or verify content; orphaned `.partial` files stay forever |
| 28 | "Set priority" is offered for `downloading` rows | `downloads_screen.dart:865-870` | The scheduler ignores the priority of a running job → hide or disable the entry |
| 29 | Hardcoded colour `0xFFF4F5F5` | `downloads_screen.dart:182,211` | Breaks light/dark theming |
| 30 | `mediaByTab` is a `Map` inside an MV3 service worker | `background.js:14` | Lost when the worker sleeps; use `chrome.storage.session` |
| 31 | `loadInterceptSetting` sets `interceptEnabled = true` before the storage callback | `background.js:174-176` | Right after a cold start a download can be intercepted despite the user having turned it off |
| 32 | The manifest cannot run on Firefox | `extension/manifest.json` | Only `background.service_worker`; README and `install.sh` still advertise Firefox |
| 33 | `endpointExists()` = token + socket both present | `app_launcher.dart:93-95` | Leftovers from a previous crash make `launchAndWait()` return `true` without launching the app |
| 34 | `install.sh` has no `mkdir -p` | `install.sh:13` | `dart compile exe` fails on a machine without `~/.local/bin` |
| 35 | `linux_usable` calls `--version` | `tools/fetch_external_tools.sh:55-57` | ffmpeg exits 8 for `--version` and 0 for `-version` → it re-downloads every time (confirmed: 8 vs 0) |
| 36 | `download_platform` / `download_database` are TODOs | `lib/*.dart`, pubspec | One-line placeholder, `expect(true, isTrue)` test, pubspec says "TODO" |
| 37 | README is stale | `README.md:20-23`, `apps/desktop/README.md` | It still says "runs against an in-memory datasource (M3)" though the engine now runs in-process; it mentions a root `test/` that does not exist; the desktop README is the Flutter template |
| 38 | `.gitignore` excludes `apps/desktop/bundle/` | `.gitignore:19` | `ExternalTools.resolve` looks in `dirname(resolvedExecutable)/bin`, so a clean clone has no ffmpeg/yt-dlp and the tool-fetch path is untested |
| 39 | `TokenBucket._pump` is head-of-line | `token_bucket.dart` | A large request blocks smaller ones behind it; burst can grow to the largest pending request |
| 40 | `verifyFile` passes `expectedBytes: record.totalBytes` | `pdm_engine.dart:838-849` | That can be `-1`, skipping the size check |

---

## Confidence notes

- **VERIFIED by probe:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 21, 22, 23, 35.
- **CODE-READ:** 12, 14, 15, 16, 17, 18, 19, 20, 24–34, 36–40. Item 20 is a timing
  race inferred from call order.
- **Correction made during the review:** the `type 'Null' is not a subtype of
  type 'int'` error seen in some early probes was a **bug in the throwaway probe
  sink**, not in the product. With a correct sink the real behaviour is described
  in items 4 and 5 — not a crash, but a *silent `completed`*, which is worse.

## Suggested regression tests, in priority order

1. `HttpTransport` with `autoUncompress` (item 6) and with a HEAD/Content-Range
   mismatch (items 4 and 5) — no transport test currently uses a compressing
   server or a lying HEAD.
2. `DownloadScheduler`: pause during the probe, factory failure followed by a
   retry of the same id, and a throwing `sink.close()` (items 1, 2, 9).
3. `DownloadStore`: opening a v1 DB that already has one of the new columns
   (item 3).
4. `CheckpointWriter`: changing tags/priority while a download is running
   (item 7).
