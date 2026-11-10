# Plan: browser extension (§21 step 11) — WebExtension + Native Messaging host

Date: 2026-11-10. Branch: `m1/browser-extension` (from `aca8d8c`).
Scope: a WebExtension (one MV3 manifest for Chromium + Firefox)
that adds a "Download with PDM" context-menu entry, and a Native
Messaging host (Dart CLI) that forwards the request to the running
engine over IPC. The engine API and recovery are stable now
(download_ipc + apps/desktop done), so §21's gate for starting
browser integration is met.

Non-goals for this part: download interception (`chrome.downloads`
— no `downloads` permission, no intercepting every download);
cookies / request headers / referrer capture (needs extra
permissions + consent UI, and `CreateDownloadRequest` takes no
referrer today); a popup UI; icons (the extension loads without
them and shows the default puzzle icon); Windows host
registration (M4 platform integration, §13); auto-starting the
engine (M4 — the engine must be running; the host replies with a
clear error when it is not).

## 1. Starting state (read from source 2026-11-10)

- `integrations/` does not exist yet (the scaffold never created
  it). §14 lists `integrations/browser-extension` (chromium,
  firefox).
- §12: WebExtensions for Chromium + Firefox, Native Messaging host
  forwards download requests to the engine; capture only what a
  user-requested download needs (URL, suggested filename, referrer
  when required, necessary headers, cookies only with permission
  and consent); validate message origin and schema; restrict the
  host to the current user; never expose the engine on an
  unauthenticated public interface; redact credentials and cookies
  from logs; clear permission controls.
- The engine IPC surface (from the download_ipc part): `IpcClient`
  over a Unix socket at `defaultSocketPath()` with the token from
  `$socketPath.token`; `createDownload` takes a full destination
  path and returns the engine's `DownloadInfo` (id `dl-N`).
- The desktop's client factory (same shape the host will use) is
  in `apps/desktop/lib/features/downloads/providers/
  download_providers.dart`.

## 2. Extension ↔ host protocol (Native Messaging)

The browser spawns one host process per `connectNative` port and
kills it when the port closes. Each message is a 4-byte
little-endian length + UTF-8 JSON (the Native Messaging framing).

- Extension → host: `{"type": "download.create", "id": "<uuid>",
  "url": "<http(s) url>", "fileName": "<bare name, optional>"}`.
  The extension sets `id` (a random uuid) so it can match replies.
- Host → extension: `{"id": "<same>", "ok": true,
  "downloadId": "dl-N"}` or `{"id": "<same>", "ok": false,
  "code": "<engine code>", "message": "<short message>"}`.
- The host validates the schema strictly and rejects anything
  else with `ok: false, code: "invalid-message"`: `type` must be
  exactly `download.create`; `url` must parse as http/https;
  `fileName`, when present, must be a bare name (no `/`, no `\`,
  no `..`). Unknown fields are ignored, unknown types are
  rejected. No cookies, headers, or credentials are ever sent.

## 3. Native Messaging host (`integrations/browser-extension/host/`)

A Dart package `pdm_native_host` (added to the workspace members
in the root `pubspec.yaml`; deps: `download_api`, `download_ipc`,
`path`, `logging`; dev: `test`, `flutter_lints` — same
conventions as `packages/download_recovery`).

- `lib/src/native_message_codec.dart`: `NativeMessageCodec`
  — `encode(Map<String, Object?>)` → length-prefixed bytes;
  `decode(Stream<List<int>>)` → a stream of decoded maps,
  tolerating split reads; a message over 1 MiB is rejected
  (the stream ends with a `StateError`); malformed JSON is
  dropped with a `FormatException` on the stream (the loop logs
  and keeps reading).
- `lib/src/native_host.dart`: `NativeHost({required
  Future<IpcClient> Function() clientFactory, required String
  downloadDirectory, StreamSink<List<int>>? out})` with
  `Future<void> run(Stream<List<int>> input, StreamSink<List<int>>
  output)`. The loop: decode messages, handle each
  `download.create` (validate → `_ensureClient()` → derive the
  destination from `downloadDirectory` + the file name → create
  → reply with the engine id), encode the reply. The client is
  created lazily and kept for the port's lifetime; a request
  that fails with `connection-closed` drops the client and
  retries once with a fresh client, then replies with the error.
  The loop ends when stdin closes (EOF) — that is the clean
  shutdown; the client is closed there. Logging: only a bounded
  summary (host + file name), never the full URL, never cookies.
- `bin/native_host.dart`: thin main — `NativeHost` with the
  production factory (Unix socket at `defaultSocketPath()`,
  token from the token file) and `~/Downloads` as the download
  directory, running over `stdin`/`stdout`.
- The file name rule (same as the desktop): the URL's last path
  segment, else `'download'`; the extension may supply a
  `fileName` instead. Known limitation, noted in the README: the
  destination is fixed before the probe, so a server
  `Content-Disposition` filename does not rename the file
  (follow-up: let the engine rename from the probe).

## 4. Extension (`integrations/browser-extension/extension/`)

Plain JS, no build step, no bundler. One MV3 manifest for both
browsers (`manifest.json` with `browser_specific_settings.gecko`
— `id: "pdm@ponta.dev"`, `strict_min_version: "109.0"`).

- `manifest.json`: `manifest_version: 3`, `name: "Ponta Download
  Manager"`, `version: "0.1.0"`, `permissions:
  ["contextMenus", "nativeMessaging", "notifications"]`,
  `background: { "service_worker": "background.js" }`,
  `action: { "default_title": "Ponta Download Manager" }`.
  No host permissions (the URL comes from the menu click, not
  from a page read).
- `background.js`: on install, creates context-menu items
  `pdm-download-link` (contexts `link`), `pdm-download-media`
  (contexts `image`, `video`, `audio`). On click: the URL is
  `info.linkUrl ?? info.srcUrl`; the suggested file name is the
  URL's last path segment (or undefined); it opens one native
  port (`chrome.runtime.connectNative('com.ponta.pdm')`) per
  click, posts `{type, id, url, fileName}`, and shows a
  notification on the reply (`Download added` with the file
  name, or `Failed: <message>`). A port error (host missing,
  not registered) shows `PDM native host is not installed —
  run install.sh`. The port is closed after the reply. All
  `chrome.*` access goes through a small `chromeApi` object
  passed in (so the tests can substitute a fake).
- `test/background.test.js`: `node --test` (built-in, no deps).
  A fake `chrome` object records menu creation, `connectNative`
  returns a fake port; tests: the link menu item is created on
  install; a click posts the right message (type, url, file
  name from the URL); a success reply shows a notification with
  the file name; a failure reply shows the error; a port error
  shows the install hint; a click with no URL posts nothing.

## 5. Install script + README (`integrations/browser-extension/`)

- `install.sh` (Linux, takes the Chrome extension id as
  `$1`): builds the host (`dart compile exe
  host/bin/native_host.dart -o ~/.local/bin/pdm-native-host`),
  writes the native-messaging manifest
  `com.ponta.pdm.json` for Chrome
  (`~/.config/google-chrome/NativeMessagingHosts/`, `path` =
  the binary, `type: "stdio"`, `allowed_origins:
  ["chrome-extension://<id>/"]`) and for Firefox
  (`~/.mozilla/native-messaging-hosts/`,
  `allowed_extensions: ["pdm@ponta.dev"]`), and prints what it
  did. The manifest name `com.ponta.pdm` matches the
  extension's `connectNative` call.
- `README.md`: setup — (1) start the engine (`dart run
  bin/engine.dart serve` from `apps/engine`); (2) load the
  unpacked extension in Chrome (`chrome://extensions` →
  Developer mode → Load unpacked → `extension/`) and copy its
  id; (3) run `./install.sh <chrome-extension-id>`; (4)
  right-click a link → "Download with PDM". Plus the known
  limitations (no interception, no cookies/headers, the
  Content-Disposition naming note, engine must be running).

## 6. Tests (TDD, RED first)

- `host/test/native_message_codec_test.dart`: encode/decode
  round-trip; a message split across chunks decodes; two
  messages in one chunk both decode; a message over 1 MiB is
  rejected; malformed JSON is dropped and the stream continues.
- `host/test/native_host_test.dart`: the host loop over
  in-memory byte streams with a mocktail-mocked `IpcClient`:
  a valid `download.create` calls `createDownload` with
  `join(dir, fileName)` and replies `{ok: true, downloadId}`;
  an invalid type / non-http url / file name with a separator
  replies `ok: false, code: "invalid-message"` and never calls
  the client; a client that throws `connection-closed` once
  is retried and then succeeds; a client that always fails
  replies with the engine's code; stdin EOF ends the loop and
  closes the client.
- `host/test/native_host_integration_test.dart`: a real
  `IpcServer` over an in-memory channel pair with a fake
  engine (same shape as the desktop integration test), the real
  host loop over in-memory byte streams: one framed
  `download.create` → the fake engine records the create and
  the reply carries its id.
- `extension/test/background.test.js`: as §4 above
  (`node --test extension/test/`).
- `install.sh`: no automated test; the manual check covers it.

## 7. Files

- New: `integrations/browser-extension/extension/manifest.json`,
  `extension/background.js`, `extension/test/background.test.js`,
  `host/pubspec.yaml`, `host/lib/src/native_message_codec.dart`,
  `host/lib/src/native_host.dart`, `host/bin/native_host.dart`,
  `host/test/native_message_codec_test.dart`,
  `host/test/native_host_test.dart`,
  `host/test/native_host_integration_test.dart`,
  `integrations/browser-extension/install.sh`,
  `integrations/browser-extension/README.md`,
  `docs/plans/2026-11-10-m1-browser-extension.md` (this file).
- Changed: root `pubspec.yaml` (workspace member
  `integrations/browser-extension/host`).

## 8. Done criteria

- `node --test integrations/browser-extension/extension/test/`
  passes.
- `dart test` passes in `integrations/browser-extension/host`.
- `flutter analyze` clean; no regressions (desktop 15, ipc 14,
  engine 15, scheduler 12, core 14, limiter 12, recovery 16,
  storage 11, transport 10, api 3).
- Manual check: a script pipes one length-prefixed
  `download.create` message into the compiled host binary while
  `serve` runs against a local HTTP server — the engine creates
  the download (byte-exact); the unpacked extension loads in
  Chrome without errors and its context menu appears on a link
  (verified in the browser by Tuấn Anh, or documented as the
  remaining manual step).
- Commit on `m1/browser-extension`; working tree clean.


## Deviations decided during implementation

- `writeTokenFile` in `apps/engine` did not create the socket's
  parent directory before writing the token, so `serve` crashed
  with `PathNotFoundException` on a first run when the directory
  did not exist yet (found by the extension smoke test, which uses
  a fresh temp `XDG_RUNTIME_DIR`). Fixed: the function now creates
  its parent dir (`Directory(...).create(recursive: true)`), with
  a regression test in `apps/engine/test/serve_command_test.dart`.
  The engine test count is now 16 (was 15).
- The plan listed icons as a non-goal, but `chrome.notifications`
  requires an `iconUrl`, so a generated 48x48 placeholder icon
  (blue square + white down arrow, produced by a Python script
  during implementation) is included at
  `extension/icons/icon48.png`. Proper icons remain a follow-up.
- The host pubspec's path deps need three levels up
  (`../../../packages/...`), not two: the host lives at
  `integrations/browser-extension/host/`.
- Test lesson: `StreamSubscription.asFuture()` rethrows stream
  errors even when an `onError` handler is set, so the codec
  tests wait on a done `Completer` instead of `asFuture()`.
