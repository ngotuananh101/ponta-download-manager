# yt-dlp probe from the extension popup

Date: 2026-11-13
Status: In progress
Baseline: HEAD `c1befa9` (survey read at `d8d7045`; the submenu fix in between
touched only the desktop screen + widget test, no impact here)

## Goal

Two-way extension ↔ app communication for yt-dlp sites. When the user opens
the extension popup, the extension sends the current tab URL to the app; the
app runs yt-dlp to probe it and returns metadata + download formats; the popup
shows the formats; the user picks one; the extension sends the choice back and
the app downloads it with yt-dlp using that format. Browser cookies +
referrer are passed to yt-dlp for both the probe and the download, so
login-walled pages probe as supported.

## Decisions (user-confirmed)

- Probe only when the popup opens, never automatically on page load.
- Cookies + referrer go to yt-dlp for probe AND download.
- Single videos first; playlists are out of scope for this part.

## Decisions (Muse, recorded here)

- Probe flags: `yt-dlp -J --no-playlist`. A playlist URL probes as its first
  video in v1.
- Format list: show all formats (combined, video-only, audio-only). The
  engine builds `-f`: combined → `<id>`, video-only → `<id>+bestaudio`,
  audio-only → `<id>`. Cache miss → `<id>` verbatim.
- Timeouts: yt-dlp probe process 30 s; IPC probe timeout 60 s (the default
  10 s stays for everything else); popup shows a loading state.
- Probe cache: in-memory in the engine, keyed by URL + whether cookies were
  present, 10 min TTL.
- Temp cookie file: fresh `Directory.systemTemp.createTemp('pdm-cookies-')`
  (0700 dir on POSIX) + random file name; deleted as soon as the run reaches
  a terminal state (probe: right after the process exits; download: on finish
  / fail / pause / cancel / shutdown). Pause deletes, resume recreates from
  the in-memory headers.
- Referrer: the tab URL, for probe and download.
- Format id: in-memory only (like cookies). After a restart, a resumed
  yt-dlp download falls back to yt-dlp's default format.
- Probe result taxonomy: `yt-dlp-unsupported` (no extractor) vs `unavailable`
  (extractor matched, video private/removed/needs login) vs
  `yt-dlp-probe-failed` (network/timeout/other). The popup shows different
  copy for each.
- Format-count guard: the engine caps the list at the best 30 formats.
- App not running during probe: same as `download.create` today — the host
  returns an error and the popup shows the start-app hint. No auto-launch
  in this part.
- Do not carry yt-dlp's per-format direct `url` fields out of the engine.
  The popup only needs metadata to choose; the app re-resolves at download
  time.

## Background: two-way already exists

The host already replies to every extension message (length-prefixed JSON,
matched by `id`), and IPC is already request/response. No transport change
is needed. What is missing: a probe request type the host accepts, a probe
method on the engine + IPC, a popup → background probe message, and a
`download.create` variant carrying the chosen format.

## Parts

### P1 — download_api: probe models + interface + format field

Files: `packages/download_api/lib/src/models/yt_dlp_probe_result.dart` (new
freezed `YtDlpProbeResult` + `YtDlpFormat`), `download_engine.dart`
(`probeYtDlp(String url, {String? cookie, String? referrer})`),
`create_download_request.dart` (`String? ytDlpFormat`), barrel
`lib/download_api.dart`, regen via build_runner.

Model shape: `YtDlpProbeResult {required bool supported, String? title,
String? thumbnail, int? durationSeconds, @Default([]) List<YtDlpFormat>
formats, String? errorCode, String? errorMessage}`; `YtDlpFormat {required
String formatId, required String ext, String? resolution, int? width, int?
height, int? filesize, int? filesizeApprox, required String vcodec, required
String acodec, double? fps, String? note}`.

Tests (RED first): model JSON round-trip; `CreateDownloadRequest`
with/without `ytDlpFormat`. Gate: `dart test` in `packages/download_api`.

### P2 — download_external: probe runner + format + cookie file

Files: `yt_dlp_downloader.dart` — new `probe({required String url, String?
cookie, String? referrer, Duration timeout}) → Future<YtDlpProbeResult>`
reusing the injected `ProcessStarter`; `start()` gains `{String? format,
String? cookie, String? referrer}`; new cookie-file helper (write
Netscape-format file, delete after use — see Security rules).

Probe command: `yt-dlp -J --no-playlist [--cookies <tmpfile>] [--referer
<url>] <url>`, stdout JSON parsed and trimmed to the P1 model. Exit 0 +
parseable JSON with formats → supported; non-zero + stderr matching
"Unsupported URL" → `supported: false, errorCode: 'yt-dlp-unsupported'`;
other non-zero → `'yt-dlp-probe-failed'` with the last stderr line
(scrubbed); timeout → kill process, `'yt-dlp-timeout'`. `start()` adds `-f
<format>` before the URL when `format != null`.

Tests (RED first, fake `ProcessStarter` + existing fake-script pattern):
probe success parses title/formats; unsupported URL maps to
`supported:false`; timeout kills the process; cookie file is created with
the right Netscape content and deleted after probe and after a download
reaches a terminal state; `-f` appears in the download args. Gate: `dart
test` in `packages/download_external`.

### P3 — apps/engine: engine probe + chosen-format download

Files: `apps/engine/lib/src/pdm_engine.dart` — `probeYtDlp` (in-memory cache
`Map<String, _CachedProbe>` keyed by URL + cookies-present, 10 min TTL;
resolves the downloader via existing `_ytDlpDownloader()`; maps downloader
errors to `DownloadError` codes; no cookies stored); `createDownload`
routes to the yt-dlp branch when `_isStreamingPlaylist(url) ||
request.ytDlpFormat != null`; the yt-dlp branch stores `_requestHeaders`
(same as the scheduler branch) and a new in-memory `_ytDlpFormats` map (id
→ format id, mirroring `_requestHeaders`, for retry/resume); `_startYtDlp`
passes `format` (combined → `<id>`, video-only → `<id>+bestaudio`,
audio-only → `<id>`, cache miss → `<id>` verbatim) plus `cookie`/`referrer`
via `_headersFor(id, record.url)`; retry/resume of a yt-dlp download reuses
the stored format + headers.

Tests (RED first, `engine_download_test.dart`, fake yt-dlp via
`makeFakeYtDlp` / injected downloader): probe returns formats and is served
from cache on the second call without re-running yt-dlp; probe with cookies
passes them through; `createDownload` with `ytDlpFormat` on a YouTube-style
URL creates a `yt-N` record and the downloader receives `-f`; retry reuses
the format; missing tools → `external-tools-missing`. Gate: `dart test` in
`apps/engine`.

### P4 — download_ipc: ytdlp.probe method + format on create

Files: `ipc_server.dart` (`_dispatch` case `'ytdlp.probe'`: validate `url`
non-empty string, `cookie`/`referrer` optional strings →
`engine.probeYtDlp` → JSON result; `download.create` accepts optional
string `ytDlpFormat`), `ipc_client.dart` (`probeYtDlp({required url, cookie,
referrer})` with a longer timeout — add an optional `timeout` parameter to
`request()`, probe uses 60 s, default stays 10 s), `protocol.dart` (manual
`ytDlpProbeResultToJson`/`ytDlpFormatToJson` + `fromJson`, same manual style
as `downloadInfoToJson`; trimmed so the line stays far under the 1 MiB cap).

Tests (RED first, `download_ipc_test.dart` + `test_helpers.dart` FakeEngine
gains `probeYtDlp`): probe round-trips through server+client;
`invalid-params` on bad types; unknown method still errors; probe timeout
is longer than the default. Gate: `dart test` in `packages/download_ipc`.

### P5 — host: probe message + format on create

Files: `host/lib/src/native_host.dart` — `_handle` accepts `type ==
'ytdlp.probe'` (validate id/url/cookie/referrer as for create; `await
_ensureClient()` then `client.probeYtDlp(...)`; reply `{id, ok: true, probe:
{...}}`, `DownloadError` → error reply); `download.create` accepts optional
string `ytDlpFormat` → `CreateDownloadRequest`. No change to `bin/` main
(same client factory, same token/socket path). App-not-running behaves as
today: factory failure → `{ok:false, code:'internal', ...}` → popup shows
the install/start hint.

Tests (RED first, `native_host_test.dart`): probe forwards url+cookie+referrer
and returns the probe JSON; probe error → error reply; bad types →
`invalid-params`; `download.create` with `ytDlpFormat` forwards it.
FakeEngine in `native_host_integration_test.dart` gains a `probeYtDlp` stub.
Gate: `dart test` in `integrations/browser-extension/host`.

### P6 — extension background: probe + chosen-format download

Files: `extension/background.js` — `handleMessage` case `'ytdlp.probe'`:
resolve the active tab URL via `tabs.query` (same as `media.list`); fetch
cookies via `chrome.cookies.getAll({url})` (same as `sendDownload`); open a
native port, post `{type:'ytdlp.probe', id, url, cookie?, referrer: <tab
URL>}`, await the reply by id, `sendResponse({ok:true, probe})` or
`{ok:false, code, message}`; `return true` (async response). Dedupe
in-flight probes per URL (a second popup open while one is running joins the
same reply list). New case `'ytdlp.download'` (`{url, formatId, fileName,
referrer}`) → `sendDownload` with an extra `ytDlpFormat` argument: the
posted message gains `ytDlpFormat: formatId` (cookies fetched the same way).
`fileName` comes from the popup (sanitized probe title + `.` + format ext;
the host already rejects `/`, `\`, `..`).

Tests (RED first, `extension/test/background.test.js`, existing
`fakeChrome()`): probe posts the right native message with cookies + tab URL
as referrer; the host reply is forwarded to the popup's `sendResponse`; a
host error reaches the popup as `{ok:false}`; two concurrent probes for the
same URL post once; `ytdlp.download` posts `download.create` with
`ytDlpFormat`. Gate: `node --test` in
`integrations/browser-extension/extension`.

### P7 — extension popup: probe UI + format choice

Files: `extension/popup.html` (new probe section above the media list:
status line + formats list) and `popup.js` (on open, send
`{type:'ytdlp.probe'}`; render states loading / not-supported / error /
formats; each format row shows resolution/ext/size with a Download button →
send `{type:'ytdlp.download', url, formatId, fileName}`). **Refactor for
testability first**: extract pure helpers (`formatBytes`, `formatLabel`,
probe-state rendering) into a module under the same `typeof module !==
'undefined' && module.exports` guard pattern as `background.js`/`content.js`,
with a new `extension/test/popup.test.js` (fake `document`/`chrome`,
mirroring the `content.test.js` fake-DOM style).

Tests (RED first): loading → formats rendered with the right labels;
unsupported → not-supported message; error → error message; clicking a
format's Download posts `ytdlp.download` with that `formatId`. Gate: `node
--test` in the extension.

### P8 — docs + manual verification

Files: this plan (Status DONE at the end), extension README (probe flow,
cookies-to-yt-dlp, temp file, restart limitation). Manual checks (Tuấn Anh):
open a YouTube page, open the popup, probe lists formats, pick one,
download completes with audio+video; a login-walled page probes as
supported with cookies; an unsupported site shows not-supported; a public
link still works unchanged. Final gates: desktop `flutter test` (FakeEngine
in `engine_ipc_host_test.dart` gains the `probeYtDlp` stub), root `dart
analyze` + `flutter analyze` clean.

## Security rules (hard)

- Cookie/referrer are in-memory only: never in `pdm.db`, never logged,
  never in error messages; dropped on cancel/delete/dispose/restart.
- The temp cookie file never has its path or its content logged; error lines
  surfaced to the UI are scrubbed of any `Cookie:` material.
- The extension supplies only a `name=value;...` header string (no
  domain/path/expiry/secure flags), so the downloader synthesizes Netscape
  lines per cookie: `<host>\tTRUE\t/\t<TRUE if https else FALSE>\t0\t<name>\t<value>`
  (leading-dot domain for subdomain matching).
- Probe/download without cookies (desktop Add flow) runs yt-dlp without
  them, as today.

## Completion

(To be filled when P1–P8 are done, with commit hashes + gates.)
