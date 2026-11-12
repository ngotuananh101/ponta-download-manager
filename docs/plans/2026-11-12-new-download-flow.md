# Plan: two-step Add download flow — 2026-11-12

## Goal
Replace the single Add download dialog with the flow the user asked
for: input the URL, press OK, the app checks the URL (reachable +
size), then a New download dialog lets the user pick the save
location and file name and choose immediate vs scheduled download.

His screenshots: the first is the OLD Add dialog (pre custom-dialog
migration: Browse button, OK button, "Enter URL or choose torrent
file" label — that dialog no longer exists in the code); the second
is the target New download design (Save to dropdown + folder button,
File name, Scheduler checkbox, "Size: 100 MB (Disk space: 144 GB)",
Cancel / Download later / DOWNLOAD).

## Decisions
- **Input size.** The old screenshot's input was ~42px (theme default
  padding). The current dialog's input is already ~34px (xs text +
  12/8 padding). Step 1 keeps that size; a widget test locks the URL
  field height to <= 36px.
- **Clipboard.** On opening step 1, read the clipboard; if it holds
  an http(s) URL, prefill the field and select it (typing replaces
  it). Best-effort: a clipboard failure leaves the field empty.
- **Probe.** The engine reuses the transport's existing `probe()`
  (HEAD, range-GET fallback, follows redirects): file name from
  Content-Disposition or the URL segment, size from Content-Length.
  Playlists (.m3u8/.mpd) are NOT probed — yt-dlp decides the size at
  download time, so they report size unknown (-1). An unreachable
  URL or bad status returns a DownloadError; step 1 stays open and
  shows the error inline.
- **Scheduler checkbox.** Checked means DOWNLOAD creates the
  download paused (scheduled for later; the future Scheduler screen
  owns start times). Unchecked means DOWNLOAD starts it now.
  "Download later" always creates it paused. No time picker in this
  part — flag this if a start time is wanted instead.
- **Save to.** A dropdown of the default download directory plus
  recently picked directories (max 5, persisted in settings.json),
  and a folder button opening a directory picker (`file_picker`
  `getDirectoryPath`, zenity on Linux — zenity is installed at
  `/usr/bin/zenity`). `file_selector` was tried first but cannot
  resolve: it needs `cross_file ^0.3.0` while `desktop_drop` needs
  `cross_file ^0.4.0`.
- **Disk space.** Free bytes of the save directory (`df` on Linux,
  `fsutil` on Windows), shown as "Size: X (Disk space: Y)"; unknown
  shows a dash. Re-queried when the directory changes.
- **Conflict.** Unchanged: creating may return FileExistsFailure,
  the conflict dialog asks overwrite/rename, the retry reuses the
  same directory, file name and paused flag.
- **IPC.** No new IPC method: probing is UI-only; the browser
  extension adds downloads without probing, as today.

## Parts
- **P1 — download_api:** `ProbeResult` (`url`, `fileName`,
  `totalBytes`, -1 = unknown), `DownloadEngine.probeUrl`, and
  `CreateDownloadRequest.paused` (`@Default(false)` so old IPC JSON
  without the key still parses). Codegen. Every hand-written
  FakeEngine in the repo gains `probeUrl`.
- **P2 — engine:** `PdmEngine.probeUrl` (playlist → unknown size,
  else transport probe mapped to ProbeResult; invalid URL →
  DownloadError) and `createDownload` honoring `paused` (scheduler
  `enqueue(paused:)` for HTTP; for yt-dlp, store the record paused
  and do not start it — `resumeDownload` already starts a paused
  playlist). Tests in apps/engine.
- **P3 — desktop data layer:** datasource `probeUrl` + `addDownload`
  with `directory`/`fileName`/`paused`; repository `probeUrl` (same
  http(s) validation as add) + passthrough; `DownloadsActions`
  exposes both. Tests + fakes.
- **P4 — step-1 dialog:** clipboard autofill, compact input, OK
  probes with a loading state and an inline error on failure.
  Widget tests (clipboard mocked via the platform channel).
- **P5 — step-2 dialog:** new `NewDownloadDialog` widget (Save to
  dropdown + recent dirs in settings + folder picker, File name,
  Scheduler checkbox, Size + Disk space via `DiskSpaceService`,
  Cancel / Download later / DOWNLOAD). Widget tests with stubbed
  picker and disk-space callbacks.
- **P6 — wiring:** `_showAddDialog` runs probe → step 2 →
  `_addDownload` with directory/fileName/paused and the conflict
  retry. Gates per part; commit each part.

## Verify
- Per part: the owning package's tests + `flutter analyze`; desktop
  parts also `flutter build linux --release` at the end.
- Manual (user): copy a URL, open Add download (field prefilled);
  OK on a good URL shows the New download dialog with the real size
  and free disk space; Download later leaves the row paused;
  Scheduler checked + DOWNLOAD also leaves it paused.

## Status: IN PROGRESS 2026-11-12 (P1-P3 done, P5 next — the step-2 dialog is built before the step-1 wiring so the flow has something to call)
