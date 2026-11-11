# Plan: bundle ffmpeg + yt-dlp, download m3u8/mpd as real video

Date: 2026-11-11. User decision: bundle both tools directly into the
app; integrate yt-dlp so an m3u8/mpd URL downloads as the real video
(not just the playlist file). yt-dlp self-update is deferred (later).

## Scope

In scope:
- Bundle ffmpeg (static) + yt-dlp (standalone binary) into the app
  bundle, Linux x64 first, Windows x64 in the same script.
- `download_external` package: locate + verify the two binaries
  (bundled next to the app exe, fallback to system PATH).
- `YtDlpDownloader`: run yt-dlp as a subprocess for m3u8/mpd URLs,
  parse its progress output, emit the same `DownloadEvent` union the
  UI already renders (progress / stateChanged / completed / failed).
- Engine routing: a `.m3u8` / `.mpd` URL goes to the yt-dlp path
  instead of the native segment downloader. Same store record, same
  UI list. Pause = kill the process, resume = re-run yt-dlp.
- Missing-tools error: a clear `DownloadError` when a yt-dlp download
  is attempted without the binaries; surfaced in the UI like other
  failures.
- Build script that fetches the binaries (not committed to git).

Out of scope (deferred):
- yt-dlp self-update (`-U`) and any update UI.
- Routing site URLs (YouTube, Facebook, TikTok, ...) to yt-dlp.
  The downloader itself is URL-agnostic, so this is a routing-only
  follow-up once the m3u8/mpd path works.
- Format selection (best / audio-only / specific quality).
- Native HLS/DASH segment downloading in the Dart engine.
- The extension needs no change: it already sends m3u8/mpd URLs to
  `download.create`, which flows through the same engine path.

## Design

### Binary resolution (`ExternalTools`)

- Search order for each tool: (1) bundled, next to the app exe
  (`<exe_dir>/bin/ffmpeg`, `<exe_dir>/bin/yt-dlp`, `.exe` on
  Windows); (2) system PATH (`which ffmpeg` / `which yt-dlp`).
- `ExternalTools.resolve()` returns `{ffmpeg: path?, ytDlp: path?}`
  plus an `available` flag per tool. Verification runs
  `<tool> --version` and checks exit code 0.
- yt-dlp is told where ffmpeg lives via `--ffmpeg-location <dir>`,
  so it never depends on ffmpeg being on PATH.

### yt-dlp downloader (`YtDlpDownloader`)

- Invoked as: `yt-dlp --ffmpeg-location <dir> --newline
  --print after_move:filepath -o <dest-template> <url>`.
  `--newline` forces one progress line per update (parseable).
  `--print after_move:filepath` reports the final file path, because
  yt-dlp may choose the extension (mp4/mkv) itself.
- Progress parsing (`YtDlpProgress`, pure): lines matching
  `[download] 45.2% of 123.45MiB at 1.23MiB/s ETA 00:30` give
  percent, total bytes and speed. Also handles the
  `[download] Destination: ...` and `[Merger] Merging formats ...`
  lines (merging = still downloading, no percent).
- Emits `DownloadEvent.progress` (bytes, total, bytesPerSecond),
  `stateChanged`, `completed(downloadId, filePath)` and `failed`.
  The engine merges these into its `events` stream, so the desktop
  datasource and the IPC server see yt-dlp downloads exactly like
  native ones.
- Pause: kill the subprocess, keep the partial output, mark paused.
  Resume: re-run yt-dlp with the same output template; yt-dlp
  resumes/merges as it can. Cancel: kill + delete the output/partial.
- Concurrency: the yt-dlp manager runs at most 1 yt-dlp download at
  a time (yt-dlp + ffmpeg are CPU/network heavy); native downloads
  are unaffected.
- The final file path from `--print after_move:filepath` updates the
  store record (`destinationPath` / fileName) so the UI shows the
  real file.

### Engine routing (`PdmEngine`)

- `createDownload`: if the URL path ends in `.m3u8` or `.mpd`
  (case-insensitive), route to the yt-dlp manager; otherwise the
  scheduler as today. If the tools are missing, throw
  `DownloadError('external-tools-missing', ...)` before creating
  the record.
- The store record is created the same way (status queued). The
  yt-dlp manager owns the record's status/bytes from then on and
  updates the store on progress/completion/failure.
- `events`: the engine owns a broadcast controller and forwards
  both the scheduler events and the yt-dlp manager events into it.
- `pause/resume/cancel/retry/delete`: dispatch by owner — the
  engine knows from the URL (or a record flag) whether a download
  is a yt-dlp one and calls the matching manager.
- Recovery (`_recover`): a non-terminal yt-dlp record (by URL) is
  re-enqueued to the yt-dlp manager, paused if it was paused,
  queued otherwise. Native records keep the current path.

### Bundling (build script)

- `tools/fetch_external_tools.sh`: downloads the ffmpeg static
  build (johnvansickle, Linux x64; gyan.dev, Windows x64) and the
  yt-dlp standalone binary (GitHub releases, `yt-dlp_linux` /
  `yt-dlp.exe`), verifies the download is non-empty and executable,
  places them in `apps/desktop/linux/bundle/bin/` and
  `apps/desktop/windows/bundle/bin/` (or the equivalent source
  dir the Flutter build copies). Idempotent: skips when the exact
  version is already present.
- The binaries are NOT committed to git (`.gitignore`).
  `flutter build linux` / the CMake install step copies
  `bundle/bin/` into the release bundle next to the app exe.
- Dev: `flutter run -d linux` needs the binaries in the dev bundle
  too; the script (or a documented step) covers it.

## Parts

### 1. `download_external`: tool resolution
- Files: `packages/download_external/` (new workspace package).
  `lib/src/external_tools.dart` (`ExternalTools`, resolution +
  `--version` check), `lib/src/tool_paths.dart` if needed.
- Work: bundled path from `Platform.resolvedExecutable`, PATH
  fallback, `--version` verification, `available` flags.
- Verify: `dart test` — resolution prefers bundled, falls back to
  PATH, reports missing cleanly, `--version` failure = unavailable.
- Done: tests pass, `dart analyze` clean.

### 2. `YtDlpProgress` parser (pure)
- Files: `packages/download_external/lib/src/yt_dlp_progress.dart`.
- Work: parse `[download]` lines into percent/total/speed; handle
  `Destination:` and `[Merger]` lines; return null for anything
  else.
- Verify: `dart test` — percent/total/speed extraction, KiB/MiB/GiB
  units, merging line, garbage lines ignored.
- Done: tests pass, analyzer clean.

### 3. `YtDlpDownloader` (subprocess + events)
- Files: `packages/download_external/lib/src/yt_dlp_downloader.dart`.
- Work: `start(url, outputTemplate)` spawns yt-dlp with
  `--newline --print after_move:filepath --ffmpeg-location`,
  parses stdout into `DownloadEvent`s, `pause` kills the process,
  `cancel` kills + deletes output, `resume` re-runs.
  Injectable process starter so tests use a fake yt-dlp script.
- Verify: `dart test` — fake yt-dlp prints progress lines, the
  downloader emits progress/completed with the printed final path;
  a failing fake emits failed; pause kills the process; cancel
  deletes the output.
- Done: tests pass, analyzer clean.

### 4. Engine routing + event merge + recovery
- Files: `apps/engine/lib/src/pdm_engine.dart`,
  `apps/engine/test/engine_download_test.dart` (and a new
  yt-dlp engine test file).
- Work: URL routing in `createDownload`, engine-owned broadcast
  event controller merging scheduler + yt-dlp events, dispatch in
  pause/resume/cancel/retry/delete, recovery routing by URL,
  `external-tools-missing` error when the tools are absent.
- Verify: `dart test` in `apps/engine` — an m3u8 URL uses the
  yt-dlp manager (fake), a normal URL still uses the scheduler,
  missing tools throws the clear error, pause/resume/cancel work
  on a yt-dlp download, recovery re-enqueues it correctly.
- Done: engine tests pass (watch the known flake), analyzer clean.

### 5. Bundling script + CMake + gitignore
- Files: `tools/fetch_external_tools.sh`,
  `apps/desktop/linux/CMakeLists.txt` (install `bundle/bin/`),
  `.gitignore`.
- Work: download ffmpeg + yt-dlp for Linux x64 (and Windows x64),
  place in the bundle source dir, wire the install step, ignore
  the binaries in git.
- Verify: run the script, `flutter build linux`, confirm
  `bundle/bin/ffmpeg` and `bundle/bin/yt-dlp` exist next to `pdm`
  and are executable; `ExternalTools` resolves them from the built
  app.
- Done: script runs, bundle contains both binaries, app resolves
  them.

### 6. Desktop UI: missing-tools error + manual check
- Files: desktop datasource / screen only if a new error string is
  needed; the `failed` event already surfaces in the UI.
- Work: confirm the `external-tools-missing` failure shows as a
  failed row with a readable message. No new UI unless the message
  is unclear.
- Verify: manual — add an m3u8 download with the binaries present
  (real video file appears, progress shows), then with the binaries
  removed (clear failed state). Run the full desktop test suite.
- Done: manual check passes, desktop tests green.

## Risks

- yt-dlp progress output format can change between versions; the
  parser must ignore lines it does not understand, never crash on
  them.
- A yt-dlp download's final extension is chosen by yt-dlp; the
  record's fileName must be updated from the printed final path,
  or the UI shows a name that does not match the file on disk.
- Pause/resume for HLS is best-effort: yt-dlp re-downloads segments
  it has not finished. It must never corrupt or duplicate the file.
- The ffmpeg static build is ~70-80MB and GPL; yt-dlp ~10MB,
  Unlicense. Keep the license note in the repo (third-party notice)
  when bundling.
- `flutter build linux` must actually copy `bin/` into the bundle;
  verify the CMake install step, do not assume.
