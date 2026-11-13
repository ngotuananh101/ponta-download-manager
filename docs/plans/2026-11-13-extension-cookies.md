# Extension downloads: send browser cookies + referrer to the engine

Date: 2026-11-13
Status: In progress

## Problem

When the browser extension intercepts a download and hands the URL to the
app, the engine downloads with a bare `HttpClient`: no cookies, no
referrer, no other browser headers. Public links work; any link behind a
login fails with 401/403 or redirects to the login page (and can even
"download" the login page HTML as the file).

Data path today (verified in code 2026-11-13):

1. Extension `background.js` `sendDownload(chromeApi, url, fileName)` posts
   only `{type, id, url, fileName}` to the native host. Manifest has no
   `cookies` permission, so the extension cannot read cookies at all.
2. Native host `native_host.dart` `_handle`/`_create` reads only url +
   fileName and builds `CreateDownloadRequest(url, destination,
   conflictPolicy: rename)`.
3. IPC `download.create` params are url, destination, maxConnections?,
   priority?, conflictPolicy? (`ipc_client.dart:122`,
   `ipc_server.dart:266`).
4. `CreateDownloadRequest` has no header fields. `HttpTransport` builds
   requests itself with only `accept-encoding: identity` + Range/If-Range.
5. `integrations/browser-extension/README.md` documents this as a known
   limitation: "No cookies, request headers, or referrer are sent to the
   engine."

## Decisions (Tuấn Anh, 2026-11-13)

- **Send cookie + referrer, always** — for every download the extension
  hands over, not only after a failure. This matches what the browser
  itself would send.
- **In-memory only.** Cookie/referrer are never written to `pdm.db`
  (no `DownloadRecord` fields), never logged anywhere, never put in a
  `DownloadError` message. They live on the job/task and in one
  engine-side map, and are dropped on cancel/delete/dispose. Consequence:
  after an app restart the headers are gone; resuming a login-walled
  download then fails and the user re-adds it from the browser.
- **Explicit fields, not a generic headers map**, on the request/job/task
  (`String? cookie`, `String? referrer`). The transport interface takes a
  `Map<String, String>? headers` because it already merges a headers map
  into `_request`.

## Field contract (fixed — every part uses exactly these names)

- Extension → host message: optional `cookie` (full header value,
  `name=value; name2=value2`), optional `referrer` (page URL string).
- IPC `download.create` params: optional `cookie`, `referrer` strings.
- `CreateDownloadRequest`, `DownloadJob`, `enqueue()`, `DownloadTask`:
  optional `String? cookie`, `String? referrer`.
- `DownloadTransport.probe` / `validateRange` / `openStream`: optional
  named `Map<String, String>? headers`. The task builds it once as
  `{'cookie': cookie, 'referer': referrer}` (HTTP spells the header
  `referer`; the Dart field stays `referrer`), omitting absent entries.
- Validation: host and IPC server reject a non-string `cookie`/`referrer`
  with `invalid-params`. The IPC line cap (1 MiB) is far above any cookie
  header, so no extra size cap.

## Parts

### P1 — download_api: request fields

- `CreateDownloadRequest` gains `String? cookie`, `String? referrer`.
- Regenerate with `dart run build_runner build` in `packages/download_api`
  (freezed + json). `download_engine.dart` imports models individually,
  so no import change is needed unless a new model file appears (none).
- Test: JSON round-trip carries both fields; absent fields stay null.

### P2 — download_transport: headers on every request

- `DownloadTransport` interface: `probe`, `validateRange`, `openStream`
  gain optional named `Map<String, String>? headers`.
- `HttpTransport` merges them into `_request` (the existing
  `headers?.forEach(request.headers.set)` mechanism) on every path,
  including `_probeWithRange` — a probe without the cookie would 401
  before the segments ever start.
- Update the 3 test fakes implementing the interface
  (`download_limiter/test`, `download_scheduler/test`,
  `download_recovery/test`).
- Tests: the loopback harness records the Cookie/Referer headers the
  server saw (same pattern as the existing `lastAcceptEncoding` capture);
  probe, validateRange and a segment stream all send them.

### P3 — download_core + download_scheduler: task carries the headers

- `DownloadTask` gains `cookie`/`referrer` constructor fields, builds the
  headers map once, and passes it to `transport.probe`, `validateRange`
  and `openStream` (probe call site is line 116; validate/openStream call
  sites are in `run()` / `_pumpSegment`).
- `DownloadJob` (const class, no copyWith) gains both fields;
  `DownloadScheduler.enqueue` gains both params and forwards them onto
  the job; `_defaultTaskFactory` (line 441) passes them to the task.
  `_withPriority` copies all fields — include the new ones.
- Tests: core — a task sends Cookie/Referer on probe and on segment
  streams; scheduler — the default factory builds a task carrying the
  job's headers (FakeTransport records them).

### P4 — apps/engine: thread through create, keep for retry

- `PdmEngine.createDownload` passes `request.cookie`/`request.referrer`
  into `_scheduler.enqueue`. The stored `DownloadRecord` is unchanged
  (no header fields, no migration).
- Engine keeps an in-memory map `id -> (cookie, referrer)` (same pattern
  as the existing `_mirrorIndex`): populated at create, consulted by
  `retryDownload` (line 531, re-enqueues from the stored record) and by
  `changeUrl` (fresh record path), dropped on cancel/delete/dispose.
  Failover re-enqueues from the `DownloadJob`, which already carries the
  headers after P3 — verify, don't re-add.
- Playlists (`.m3u8`/`.mpd` via yt-dlp) explicitly do NOT get the headers
  in this part — yt-dlp needs a `--cookies` file, which is separate work.
- Tests: engine — a created download's requests carry the Cookie header
  at the loopback server; a manual retry inside the same session re-sends
  it; after a reopen (restart) the headers are gone.

### P5 — download_ipc: carry the fields over the socket

- `IpcClient.createDownload` sends `cookie`/`referrer` when non-null
  (same conditional-entry style as `maxConnections`/`priority`).
- `IpcServer` `_dispatch` `download.create` validates both as optional
  strings and passes them into `CreateDownloadRequest`. No protocol
  version bump (additive optional fields, same as item 15).
- Tests: `download_ipc_test.dart` — create round-trips both fields; a
  non-string value is rejected with `invalid-params`.

### P6 — native host: forward the fields

- `NativeHost._handle` reads optional `cookie`/`referrer` (String when
  present, else `invalid-params`), `_create` passes them into
  `CreateDownloadRequest`. Logging stays host + file name only.
- Tests: `native_host_test.dart` — a message with both fields creates a
  download carrying them (FakeEngine records the request); a non-string
  value is rejected.

### P7 — extension: read the cookies, pass the referrer

- `manifest.json`: add `"cookies"` to `permissions` (host_permissions
  already `<all_urls>`). Firefox MV3 supports the same `cookies`
  permission.
- `background.js` `sendDownload(chromeApi, url, fileName, referrer)`:
  before `postMessage`, call `chromeApi.cookies.getAll({url}, cb)` when
  the API exists and build `cookie` as
  `cookies.map(c => \`${c.name}=${c.value}\`).join('; ')`. Omit the field
  when the list is empty or the API is absent (older browser) — the
  download still goes through, just without cookies. `getAll({url})`
  returns exactly the cookies the browser would send for that URL
  (domain/path/secure matching done by the API, HttpOnly included).
- Referrer sources: intercept path — `item.referrer` when present
  (Chrome `DownloadItem` carries it; omit when absent); context menu —
  `info.pageUrl`; media downloads — the content script attaches the page
  URL to each media item and the popup forwards it as `referrer`.
- Tests (`node --test`): fake `chromeApi` gains `cookies.getAll`;
  sendDownload builds the cookie string and includes referrer; empty
  cookie list omits the field; missing cookies API still sends the
  download. `manifest.test.js`: permissions include `cookies`.

### P8 — docs + close-out

- `integrations/browser-extension/README.md`: replace the "No cookies..."
  limitation line with the new behavior + the restart limitation.
- Mark this plan DONE. Gates: desktop `flutter test`, `dart test` in
  every touched package + host, extension `node --test`, root
  `dart analyze`, `flutter analyze`.

## Out of scope

- yt-dlp cookies (`--cookies` file) for login-walled playlists.
- User-Agent spoofing (engine still sends Dart's default UA).
- The desktop Add-download flow (no browser cookies exist there).
- `checkForUpdate` re-probe without headers.
- Persisting cookies across restarts.

## Manual check owed (Tuấn Anh)

- Intercept a real login-walled download in the browser (a file that
  401s without a session) and confirm it completes in PDM; confirm a
  public link still works unchanged.
