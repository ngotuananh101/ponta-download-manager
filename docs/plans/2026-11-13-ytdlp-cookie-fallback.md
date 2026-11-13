# yt-dlp cookie fallback — probe + download retry without cookies

Status: IN PROGRESS
Date: 2026-11-13

## Context

Tuấn Anh opened the extension popup on a YouTube video
(`https://www.youtube.com/watch?v=h_DdeF0QN3U`) without picking any
format. The probe failed with:

`ERROR: [youtube] h_DdeF0QN3U: Requested format is not available.`

Investigation (all runs on his machine with the bundled yt-dlp):

- The video has 47 formats. Without cookies, every selector the engine
  can build (all 42 format ids, with and without `+bestaudio`, plus the
  storyboard `sb0`) resolves fine.
- The probe command reproduced exactly as the engine runs it
  (`-J --no-playlist [--cookies <file>] [--referer <url>] <url>`)
  succeeds with 47 formats in every combination tried: baseline,
  + referer, + a Netscape cookie file with realistic anonymous YouTube
  cookies, + fake session cookies (SID/HSID/SSID/`__Secure-1PSID`).
- The engine code path is clean: the probe argv in
  `YtDlpDownloader.probe()` matches the reproduction, the popup sends
  `format.formatId`, the engine's `_formatArgFor` builds the selector.
- Conclusion: the failure is specific to his real browser cookie
  values (most likely a stale/invalid session or consent cookie making
  YouTube return a player response with no formats), or a transient
  YouTube response. His session cookies cannot and must not be
  inspected: they are credentials, kept in-memory only by design.

Two more defects found while investigating (not the cause, fixed here
only where the fix overlaps — see P2):

- `PdmEngine.probeYtDlp` caches FAILED probe results for 10 minutes,
  so a transient failure keeps showing the same error on every popup
  open until the TTL expires.
- The popup's format list can contain a YouTube storyboard (`sb0`,
  shown as "180p · audio only · mhtml") while all real audio-only
  formats are cut by the best-30 trim. Out of scope for this plan;
  tracked separately.

## Decision

Cookies must only ever ADD capability (login-walled videos). They
must never make a public video un-probeable or un-downloadable. So
when a yt-dlp run WITH cookies fails, retry ONCE without cookies:

- Probe: retry when the with-cookies run fails, except when the site
  is genuinely unsupported (`Unsupported URL` — extractor matching is
  by URL pattern, cookies cannot change it) and except on timeout
  (a retry would double the wait to ~60s against the 60s IPC probe
  timeout). If the retry succeeds, return its result. If it also
  fails, return the ORIGINAL (with-cookies) error, never the retry's:
  for a login-walled video with bad cookies the original error is the
  honest one.
- Download: retry when the run fails with `Requested format is not
  available` (format selection happens before any transfer, so no
  partial file exists) and cookies were used. Same error rule: both
  fail → report the first error. Pause/cancel/shutdown during the
  first attempt must NOT trigger a retry. The referrer stays on the
  retry; only `--cookies` is dropped.
- Probe cache: only cache `supported: true` results. A failed probe
  is re-run on the next popup open, so a transient failure self-heals.

## Parts

### P1 — download_external: probe fallback

`YtDlpDownloader.probe()`: extract one attempt into a helper, call
it with the cookie file, then without `--cookies` when the first
result is a retryable failure (`supported: false`, error code other
than `yt-dlp-unsupported`; timeouts never reach the retry). The temp
cookie file is still created once and deleted in `finally`.

Tests (fake `ProcessStarter`):
- cookie run fails with the format error, retry succeeds → supported
  result, second call has no `--cookies`.
- both runs fail → original (first) error reported.
- `Unsupported URL` → single call, no retry.
- no cookie given → single call.

### P2 — engine: do not cache failed probes

`PdmEngine.probeYtDlp`: cache only when `result.supported` is true.

Tests:
- a failing probe runs the downloader on every call (no caching).
- a successful probe is still cached (existing test).

### P3 — download_external: download fallback

`YtDlpDownloader._run`: after a non-zero exit with cookies used and
the last error line containing `Requested format is not available`,
delete the cookie file, reset the error state and re-spawn once
without `--cookies`. Pause/cancel/shutdown checks stay before the
retry decision. If the retry also fails, report the FIRST error.

Tests (fake `ProcessStarter`, two fake processes in order):
- cookie run fails with the format error, retry succeeds → completed
  event, second call has no `--cookies`.
- both fail → failed event carries the first run's message.
- a non-format failure → single call, no retry.
- no cookie given → single call.

## Verification

- `dart test` in `packages/download_external` and `apps/engine`.
- `dart analyze` at repo root, `flutter analyze`.
- Manual (Tuấn Anh): restart the app, open the popup on the same
  video → formats list appears; pick a format → download completes.
