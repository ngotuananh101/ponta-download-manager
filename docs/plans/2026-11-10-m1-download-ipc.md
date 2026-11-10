# Plan: download_ipc (§21 step 9) — engine ↔ UI socket protocol

Date: 2026-11-10. Branch: `m1/download-ipc` (from `62ca79e`).
Scope: new package `packages/download_ipc` + wire the `serve` daemon in
`apps/engine`. The desktop app (step 10) uses the client later; no UI
work in this part. `serve` stays a stub until this part lands.

## 1. Protocol (architecture.md §4.2, version 1)

- Transport-independent core: newline-delimited JSON (NDJSON), one
  message per line, UTF-8. The codec never knows about sockets.
- Every message carries `"v": 1` (protocol version). A message with a
  missing or unsupported version gets error `unsupported-version`.
- Categories:
  - `request`: `{"type":"request","v":1,"id":"req-1","method":"download.create","params":{...}}`
  - `response`: `{"type":"response","v":1,"id":"req-1","result":{...}}`
    or `{"type":"response","v":1,"id":"req-1","error":{"code":"...","message":"..."}}`
  - `event`: `{"type":"event","v":1,"event":"download.progress","data":{...}}`
  - `error`: `{"type":"error","v":1,"error":{"code":"...","message":"..."}}`
    (protocol-level, no request id; e.g. malformed line, bad version).
- First message on every connection is a handshake, not a request:
  client sends `{"type":"hello","v":1,"token":"<server token>"}`; server
  replies `{"type":"hello-ok","v":1}` and then a sync snapshot event
  (see §4), or closes the connection on a wrong/missing token
  (error `unauthorized`, connection closed, no retry by the server).
- Methods (all map 1:1 to `DownloadEngine`, §16):
  `download.create` `{url, destination, maxConnections?, priority?}`
  → `DownloadInfo` map;
  `download.pause` / `download.resume` / `download.cancel` /
  `download.retry` `{downloadId}` → `{ok:true}`;
  `download.setPriority` `{downloadId, priority}` → `{ok:true}`;
  `download.setGlobalBandwidthLimit` `{bytesPerSecond?}` → `{ok:true}`;
  `download.setDownloadBandwidthLimit` `{downloadId, bytesPerSecond?}`
  → `{ok:true}`;
  `download.list` `{}` → `{downloads:[DownloadInfo...]}`.
- `DownloadInfo` wire shape: `{id, url, fileName, status,
  downloadedBytes, totalBytes, bytesPerSecond}` (status is the §16
  enum name). Event names mirror the §4 example:
  `download.progress` `{downloadId, downloadedBytes, totalBytes,
  bytesPerSecond}`, `download.stateChanged` `{downloadId, status}`,
  `download.completed` `{downloadId, filePath}`,
  `download.failed` `{downloadId, code, message}`.
- Error codes (stable, deterministic): `invalid-message` (not JSON /
  not an object / missing type), `unsupported-version`,
  `unauthorized`, `unknown-method`, `invalid-params` (missing field,
  wrong type, bad enum value), `not-found` (unknown downloadId where
  the engine has no such record — note: pause/resume/cancel on an
  unknown id are no-ops in the engine, so they return `{ok:true}`),
  `internal` (engine threw `DownloadError`: its code/message are
  carried in the error object), `timeout` (client-side only).
- Validation: every message and every parameter is validated before
  dispatch; a request that fails validation gets a response with an
  error object, never a crash and never a silent drop. An unknown
  response id is ignored. A malformed line gets an `error` message
  and the connection stays open.

## 2. Transport

- `IpcChannel` (pure, no sockets): wraps a `Stream<List<int>>` +
  a byte sink; decodes NDJSON lines into maps, encodes maps to lines;
  splits lines on `\n`, tolerates `\r\n`, drops empty lines, enforces
  a 1 MiB per-line cap (a longer line → `invalid-message` and the
  connection is closed — a client cannot grow server memory
  unboundedly). Exposes `Stream<Map<String, Object?>> messages` and
  `send(Map)`. Owns nothing about engines or methods.
- `IpcTransport` abstraction: `serve()` → `Stream<IpcChannel>` of
  accepted connections, plus `connect()` → `IpcChannel`. Two
  implementations:
  - Unix domain socket (Linux/macOS, default): server binds
    `$XDG_RUNTIME_DIR/pdm/engine.sock` else
    `~/.local/share/pdm/engine.sock`; the parent dir is created with
    mode 0700, the socket file is removed on clean shutdown and
    unlinked before bind when stale. Client connects to the same
    path. (Dart: `InternetAddressType.unix`; verify on the Fedora
    machine in the tests — if unix sockets do not bind there, the
    fallback below becomes the default and the plan is updated.)
  - Loopback TCP fallback (Windows, and when unix bind fails):
    server binds `127.0.0.1` port 0; the chosen port is written next
    to the token file so a local client can find it. Never binds
    `0.0.0.0`.
- Token: the server generates 32 random bytes (hex) per run, writes
  them to `<socket>.token` (same directory, mode 0600), and prints
  the socket path on stdout at startup. The desktop app reads the
  token file; no token is ever logged. The token file is deleted on
  clean shutdown.

## 3. Server (`IpcServer`)

- Constructor takes a `DownloadEngine` and an `IpcTransport`.
  `serve()` starts accepting; `close()` stops accepting, closes all
  client channels, then closes the engine (engine disposal order is
  the engine's own `dispose()`).
- Per connection: wait for `hello` (5s timeout, then close); on a
  bad token close immediately. On success: send `hello-ok`, then a
  sync snapshot — one `event` of type `download.sync` with
  `data: {downloads: [...]}` from `engine.listDownloads()` — so a
  (re)connecting client resynchronizes without a separate call.
- Request routing: validate → call the engine method → reply with
  `result` (or `error` on `DownloadError`/unexpected throw). Calls
  run sequentially per connection (a slow `createDownload` does not
  reorder later requests on the same connection); different
  connections run concurrently.
- Events: subscribe once to `engine.events`; broadcast every event
  to every connected client (a slow client must not block the
  engine: drop the connection when its outbound buffer exceeds
  1 MiB of queued bytes — the client reconnects and resyncs).
- `serve` wiring in `apps/engine`: `serve` gains options `--socket`
  and `--db` (reuse the download flags' parsing shape); it opens a
  `PdmEngine`, starts an `IpcServer` on the default socket path,
  prints `Listening on <path>`, and waits for SIGINT/SIGTERM, then
  shuts down cleanly (server → engine). Exit code 0 on a clean
  signal shutdown.

## 4. Client (`IpcClient`)

- `IpcClient.connect({required socketPath, required token,
  Duration requestTimeout = 10s})`: connects, sends `hello`, waits
  for `hello-ok` (timeout → `DownloadError('timeout',...)`).
- Requests: `request(method, params)` → `Future<Map>`; ids are
  `req-1`, `req-2`, … per client; a pending map matches responses by
  id; a response carrying `error` throws `DownloadError(code,
  message)`; a timeout completes with `DownloadError('timeout',...)`
  and drops the pending entry. Typed helpers mirror the methods:
  `createDownload`, `pauseDownload`, `resumeDownload`,
  `cancelDownload`, `retryDownload`, `setPriority`,
  `setGlobalBandwidthLimit`, `setDownloadBandwidthLimit`,
  `listDownloads`. All return decoded `DownloadInfo`/maps, never raw
  JSON strings.
- `Stream<DownloadEvent> get events`: engine events decoded from
  `event` messages (the `download.sync` snapshot is exposed as a
  separate `Stream<List<DownloadInfo>> get syncSnapshots`, not as a
  `DownloadEvent`). Unknown event names are ignored, never thrown.
- Reconnect: `reconnect()` closes the current channel and connects
  again (same token/path); the server sends a fresh sync snapshot,
  so no state is lost. Automatic reconnect is NOT done in this part
  (the desktop app decides its policy in step 10); `reconnect()` is
  the primitive it will use. `close()`/`dispose()` cancels pending
  requests with `StateError('IpcClient closed')`.

## 5. Tests (TDD, RED first)

New file `packages/download_ipc/test/download_ipc_test.dart`
(in-memory transport: two `StreamChannel`s wired together, so the
codec/server/client tests need no socket at all) plus
`packages/download_ipc/test/download_ipc_socket_test.dart` (real Unix
socket on Linux, skipped elsewhere):
- Codec: request/response/event/error/hello round-trip through
  `IpcChannel` over an in-memory byte stream; a line split across
  two chunks decodes once complete; `\r\n` tolerated; a line over
  the 1 MiB cap closes the channel.
- Validation: malformed JSON → `invalid-message`; missing `v` →
  `unsupported-version`; unknown method → `unknown-method`;
  `download.create` without `url` → `invalid-params`; a response
  with an unknown id is ignored.
- Server+client (in-memory): `create` returns the info and the
  client sees `download.progress` + `download.completed` events;
  `pause`/`resume`/`cancel`/`retry`/`setPriority`/limits round-trip;
  `list` returns the created download; a second client connecting
  gets the `download.sync` snapshot with the current downloads.
- Auth: a client with a wrong token is closed without `hello-ok`
  and cannot issue requests.
- Socket test: server binds the real Unix socket path, a client
  connects with the token file's token, creates a download served
  by a local `HttpServer`, file lands byte-exact; the socket file
  and token file are gone after `close()`.
- `serve` smoke (manual, in the plan's verification step, not a
  unit test): start `dart run bin/engine.dart serve --db <tmp>` as
  a subprocess, connect with a small Dart client script, create a
  download via IPC, verify the file, SIGINT the server, verify the
  socket/token files are removed.

## 6. Files

- New: `packages/download_ipc/{pubspec.yaml, lib/download_ipc.dart,
  lib/src/{ipc_channel.dart, ipc_transport.dart, ipc_server.dart,
  ipc_client.dart, protocol.dart}, test/download_ipc_test.dart,
  test/download_ipc_socket_test.dart}`.
- Changed: `apps/engine/lib/src/cli.dart` (serve options),
  `apps/engine/bin/engine.dart` (serve runs the daemon),
  root `pubspec.yaml` (add `packages/download_ipc` to the
  workspace), `apps/engine/pubspec.yaml` (add `download_ipc` path
  dep), `docs/plans/2026-11-10-m1-download-ipc.md` (this file).
- Nothing outside `packages/download_ipc`, `apps/engine`, and the
  plan doc.

## 7. Deviations decided during implementation

- The server does **not** dispose the engine on `close()`: the §16
  `DownloadEngine` has no dispose method, so the caller (the `serve`
  command) disposes the engine after the server closes.
- No 1 MiB outbound drop: `Socket` exposes no queued-bytes count,
  and a send that fails (broken pipe) already drops the client; a
  local client that stops reading is repaired by reconnect + resync.
- The real-download-over-IPC test lives in
  `apps/engine/test/ipc_test.dart` (it needs the real `PdmEngine`),
  not in the package socket test, which uses the fake engine.

## 8. Done criteria

- `flutter analyze` clean.
- `dart test` passes in `packages/download_ipc`,
  `apps/engine` (14 existing), `packages/download_scheduler` (12),
  `packages/download_core` (14); no regressions (limiter 12,
  recovery 16, storage 11, transport 10, api 3, desktop 2).
- Manual `serve` smoke passes (see §5).
- Commit on `m1/download-ipc`; working tree clean.
