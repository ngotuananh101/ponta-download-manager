# Plan: IDM rework — single process, engine in the app, tray

Date: 2026-11-10. Branch: `m1/idm-rework` (from `383f23c`).
Goal (Tuấn Anh's decision): follow IDM — one process, UI + engine
together in the desktop app, downloads survive closing the window
because the app stays in the system tray. The browser extension
keeps working: the app hosts the IPC server the extension's native
host talks to.

## 1. Starting state (read from source 2026-11-10)

- Desktop (`apps/desktop`): `IpcDownloadDatasource` owns an
  `IpcClient` to a standalone engine daemon; `download_providers.dart`
  builds it with a client factory (Unix socket at
  `defaultSocketPath()` + token file), `downloadsProvider` is a live
  stream, `engineConnectedProvider` feeds the disconnected banner.
- Engine (`apps/engine`, package `pdm_engine`): `PdmEngine`
  implements `DownloadEngine`; `bin/engine.dart` has two
  subcommands, `download` (one-shot, in-process) and `serve`
  (daemon: `runServe` in `lib/src/serve_command.dart` — opens the
  engine, writes the per-run token via `writeTokenFile`, starts an
  `IpcServer` on `UnixSocketTransport`). Barrel
  `lib/pdm_engine.dart` exports cli, download_command,
  engine_config, pdm_engine, serve_command.
- `download_ipc` (protocol v1 + `IpcServer`/`IpcClient` +
  transports) is used by the daemon, the desktop client, and the
  extension's native host.
- Extension (`integrations/browser-extension`): the native host
  (`pdm_native_host`) connects to the daemon's socket + token.
  Its README says to start `dart run bin/engine.dart serve`.
- Architecture doc §4 says two processes (Flutter UI + standalone
  Dart engine); §13 lists tray/startup/lifecycle as platform
  integration; §21 is complete through step 11.

## 2. Desktop: embed the engine in-process

- `apps/desktop/pubspec.yaml`: add `pdm_engine` (path
  `../../apps/engine`); keep `download_ipc` (the app still hosts
  an `IpcServer`). For the tray, follow dev-stack exactly (see
  §4): `window_manager: ^0.6.0` plus `nativeapi` and
  `nativeapi_flutter` as direct deps (window_manager 0.6
  re-exports nativeapi's windowing API; `ImageAsset.fromAsset`
  lives in `nativeapi_flutter`). No `tray_manager` — dev-stack
  does the tray directly on nativeapi. `flutter pub get`
  resolves the versions; record them after.
  Add the tray icon asset (see §4).
- New `EngineDownloadDatasource` (data layer, replaces  `IpcDownloadDatasource`, which is deleted):
  - Constructor takes a `PdmEngine` (concrete — it can dispose
    it) and a `downloadDirectory`. The provider opens the engine
    once via `PdmEngine.open()` (default DB path) and the
    datasource disposes it.
  - `watchDownloads()`: the current list first (from
    `listDownloads()`), then updates from `engine.events` — the
    same 500 ms progress throttling as the IPC datasource
    (progress marks dirty, a timer flushes; state/completed/failed
    emit immediately). The `DownloadInfo` → `Download` mapping
    moves out of the deleted IPC datasource into a small
    `download_mapper.dart` (`downloadFromInfo`), reused here.
  - `addDownload(url)`: derives the file name + destination
    (`join(downloadDirectory, fileName)`), calls
    `engine.createDownload`, and adds the created download to the
    local map from the create response (same lesson as the IPC
    datasource — the engine sends no event for a download it just
    created).
  - Pause/resume/cancel/retry delegate to the engine; no local
    state flips. `dispose()` disposes the engine.
- `DownloadRepositoryImpl` takes the new datasource (same
  interface, same `Either`/`DownloadError` mapping). The
  repository interface is unchanged.
- Providers (`download_providers.dart`): `downloadDatasourceProvider`
  builds the `EngineDownloadDatasource` with the opened engine;
  `downloadsProvider` (live stream) and `downloadsActionsProvider`
  stay; `engineConnectedProvider` is deleted (the engine is
  in-process — there is no "disconnected" state) and the screen's
  disconnected banner + its retry button go with it.
- App startup/shutdown: the engine opens when the datasource
  provider is first read (the home screen watches it, so this is
  app startup); the provider's `onDispose` disposes the
  datasource (engine + IPC server, see §3). A real quit (tray
  menu, §4) is what triggers it — closing the window does not.

## 3. App hosts the IPC server (extension keeps working)

- New `EngineIpcHost` in the desktop app (`lib/app/` or
  `lib/core/`): given a `DownloadEngine`, it generates a per-run
  token (32 random bytes, hex), writes `<socket>.token` (creating
  the parent dir first — the `writeTokenFile` lesson from the
  extension part), starts an `IpcServer` on a
  `UnixSocketTransport` at `defaultSocketPath()`, and exposes
  `close()` (server → transport, token file deleted). The
  `_randomToken` + `writeTokenFile` helpers move here from
  `serve_command.dart`.
- The app starts the host during startup (in `PdmApp` init, after
  the engine provider is read) and closes it on real exit. The
  extension's native host connects to the same socket + token as
  before — no change to the extension, the host, or `install.sh`.
- The extension README changes one line: start the desktop app
  instead of `dart run bin/engine.dart serve`.

## 4. Tray (close to tray, downloads continue) — dev-stack's approach

Tuấn Anh pointed at his other app, dev-stack
(https://github.com/ngotuananh101/dev-stack), which already does
a native tray. PDM copies its stack and patterns exactly instead
of using `tray_manager`:

- Deps: `window_manager: ^0.6.0` + `nativeapi` +
  `nativeapi_flutter` (direct deps; 0.6 re-exports nativeapi's
  windowing API and uses FFI bindings instead of a platform
  channel). No `tray_manager`.
- `lib/core/services/window_api.dart` (ported from dev-stack):
  `currentWindow()` / `whenCurrentWindow()` — resolves the app's
  window, adopting it from nativeapi's `WindowCreatedEvent`
  when it is not discoverable yet (the Windows case; on Linux
  `getCurrent()` answers). Includes the
  `debugSetCurrentWindowResolver` hook so widget tests can hand
  in a fake window.
- `lib/core/services/linux_desktop_service.dart` (ported from
  dev-stack, adapted): appId `com.ponta.pdm`, appName 'Ponta
  Download Manager'. `ensureDesktopIntegration()` installs the
  `.desktop` file + hicolor icon into `~/.local/share` so GNOME
  resolves the app_id/name/icon (needed for the tray icon and
  the top bar to show correctly); `resolveIconPath()` finds the
  best absolute icon path (installed icon first, then the
  bundle's `data/flutter_assets/assets/images/icon.png`, then
  the working dir).
- `lib/core/services/window_service.dart` (ported from
  dev-stack's `WindowService`, adapted to PDM): a
  `@Riverpod(keepAlive: true)` provider that
  - registers the window close listener via `whenCurrentWindow`
    (`window.addListener(_onWindowEvent)`). window_manager 0.6
    has no `setPreventClose(true)` + `onWindowClose`: a
    `WindowCloseRequestedEvent` carries an `EventRequest` that
    the listener can `cancel()`; the request stays pending until
    the listener's future completes.
  - creates the tray icon (`TrayIcon.create()`, null-checked)
    with the image from `ImageAsset.fromAsset(iconPath) ??
    Image.fromFile(iconPath)`; the image wrapper must stay
    reachable for as long as the tray icon does (native handles
    are freed when collected). On Linux sets
    `setContextMenuTrigger(ContextMenuTrigger.clicked)` — the
    tray renders through StatusNotifierItem over D-Bus and the
    host only shows the exported menu for that trigger; any
    other value leaves the menu empty on GNOME's AppIndicator.
    `setVisible(true)`.
  - listens for `TrayIconClickedEvent` → show the window,
    `TrayIconRightClickedEvent` → `openContextMenu`,
    `TrayIconDoubleClickedEvent` → no-op.
  - owns the menu through a `_TrayMenu` holder (ported):
    `Menu.create()` + `MenuItem.createWithLabelAndType()`
    (both null on failure → `StateError`); `Menu.dispose()`
    does NOT free its items, so items and menus each need
    their own dispose pass, depth-first, listeners removed
    first; the previous menu is disposed via `Timer.run` after
    being replaced (a click callback runs inside the clicked
    item's own native callback). Menu actions run through
    `Timer.run(action)` — a native callback runs synchronously
    inside the native trampoline, and an async action's
    continuation is queued as a microtask that Flutter only
    drains after a task/frame; while the window is hidden there
    are no frames, so without the trampoline Quit does nothing
    until the window is shown again.
  - menu: **Show** (restore + show + focus the window —
    `show()` alone leaves a minimized window minimized),
    **Pause all** (pause all downloads via the repository),
    **Quit** (set `_isQuitting`, stop the engine + IPC server,
    then close the window).
  - `_isQuitting` flag: a close the app started itself passes
    through the close listener. The close handler: if quitting,
    return (accept); else cancel the request and hide the
    window (PDM always minimizes to tray on close — there is no
    minimizeToTray setting in this rework; the setting is a
    follow-up).
  - `onDispose` removes the window listener, the tray listener,
    and disposes the menu, the tray icon, and the image.
- Icon: `assets/images/icon.png` — copy the extension's
  `icons/icon48.png` (48×48 blue + white arrow) into the
  desktop assets for now; a proper 256×256 icon is a follow-up
  (the extension part already recorded that).
- Linux runner (`linux/runner/my_application.cc`): add the
  `--minimized` flag handling from dev-stack (start in the tray:
  the window stays hidden instead of being shown on the first
  frame), so the app can be launched minimized (autostart later).
  Autostart itself (`launch_at_startup` + a setting) is a
  follow-up, not in this rework.
- Manual verification (no headless test can cover a real tray):
  build + run the app on his machine, add a download, close the
  window — the tray icon appears, the download continues to
  completion, Show restores the window, Quit exits cleanly with
  the engine disposed. The `quitting` flag decision (hide vs
  close) gets a unit test (via the window_api resolver hook);
  the icon/menu wiring is manual-only.

## 5. Engine package: remove `serve`

- Delete `apps/engine/lib/src/serve_command.dart` and
  `apps/engine/test/serve_command_test.dart` (the writeTokenFile
  regression test moves to the desktop test dir with
  `EngineIpcHost`).
- `lib/src/cli.dart`: remove the `serve` subcommand, its parser,
  and its usage text; `CliResult` drops `socketPath`.
  `bin/engine.dart`: remove the `serve` case. The barrel drops
  the `serve_command` export. CLI `download` is unchanged.
- `apps/engine` keeps its `download_ipc` dep (its `ipc_test`
  still runs a real `IpcServer` over a real `PdmEngine` — that
  test stays and still passes; it does not depend on `serve`).
- The engine's CLI test (flags in `engine_download_test.dart`)
  is updated for the removed `serve` flags.

## 6. Docs

- `docs/architecture.md`: §4 (single process: the engine runs
  inside the desktop process; the IPC server is embedded in the
  app only for the extension), §11.3 (UI state from the
  in-process engine), §13 (tray + lifecycle now implemented for
  Linux; autostart/installer still open), §14 (the engine is a
  library the desktop uses; no daemon), §20/§21 (the rework;
  `serve` removed). Root README if it mentions `serve`.

## 7. Tests (TDD, RED first)

- `apps/desktop/test/features/downloads/engine_download_datasource_test.dart`
  (new): mocktail-mocked `PdmEngine` — sync via `listDownloads`
  + events, throttling (fakeAsync, as the IPC test), add/pause/
  resume/cancel/retry delegate, dispose disposes the engine.
- `apps/desktop/test/features/downloads/download_repository_test.dart`
  (updated): the mock is now `EngineDownloadDatasource`.
- `apps/desktop/test/features/downloads/engine_integration_test.dart`
  (new, replaces the IPC integration test): a real `PdmEngine`
  (temp DB dir) + the real datasource — create via the repository,
  progress + completed flow through to `watchDownloads`.
- `apps/desktop/test/app/engine_ipc_host_test.dart` (new): start
  the host with a fake engine + temp socket path, connect a real
  `IpcClient` with the token file's token, create a download,
  verify the reply + the fake engine recorded it; the token file
  exists and its parent dir was created.
- `apps/desktop/test/widget_test.dart` (updated): no
  `engineConnectedProvider` override, no disconnected-banner
  test; the pause-button + empty-state tests stay.
- `apps/desktop/test/core/services/window_service_test.dart`
  (new): the quit-flag decision — a close request hides the
  window by default and lets it close once quitting is set.
  The window is faked through the `debugSetCurrentWindowResolver`
  hook from `window_api.dart` (ported from dev-stack), so the
  test needs no native library. The tray icon/menu wiring is
  manual-only (see §4).
- Deleted: `ipc_download_datasource_test.dart`,
  `ipc_integration_test.dart` (desktop), `serve_command_test.dart`
  (engine, moved).
- Unchanged: `download_ipc` tests (14), extension host tests
  (13), node extension tests (8).

## 8. Files

- New: `apps/desktop/lib/features/downloads/data/datasources/engine_download_datasource.dart`,
  `apps/desktop/lib/features/downloads/data/datasources/download_mapper.dart`,
  `apps/desktop/lib/app/engine_ipc_host.dart`,
  `apps/desktop/lib/core/services/window_api.dart` (ported from
  dev-stack), `apps/desktop/lib/core/services/window_service.dart`
  (ported from dev-stack, adapted),
  `apps/desktop/lib/core/services/linux_desktop_service.dart`
  (ported from dev-stack, adapted),
  `apps/desktop/assets/images/icon.png` (copied from the
  extension's `icons/icon48.png`),
  the tests in §7,
  `docs/plans/2026-11-10-m1-idm-rework.md` (this file).
- Changed: `apps/desktop/lib/features/downloads/data/repositories/download_repository_impl.dart`,
  `apps/desktop/lib/features/downloads/providers/download_providers.dart`,
  `apps/desktop/lib/features/downloads/presentation/screens/downloads_screen.dart`,
  `apps/desktop/lib/main.dart`, `apps/desktop/lib/app/app.dart`,
  `apps/desktop/pubspec.yaml` (`pdm_engine`, `window_manager`
  0.6, `nativeapi`, `nativeapi_flutter`, tray icon asset),
  `apps/desktop/linux/runner/my_application.cc` (`--minimized`),
  `apps/engine/lib/src/cli.dart`, `apps/engine/bin/engine.dart`,
  `apps/engine/lib/pdm_engine.dart`,
  `apps/engine/test/engine_download_test.dart` (CLI flags),
  `integrations/browser-extension/README.md`,
  `docs/architecture.md` (§4, §11.3, §13, §14, §20/§21).
- Deleted: `apps/desktop/lib/features/downloads/data/datasources/ipc_download_datasource.dart`,
  `apps/desktop/test/features/downloads/ipc_download_datasource_test.dart`,
  `apps/desktop/test/features/downloads/ipc_integration_test.dart`,
  `apps/engine/lib/src/serve_command.dart`,
  `apps/engine/test/serve_command_test.dart`,
  `apps/engine/test/ipc_test.dart` only if it depends on `serve`
  (it does not — verify during implementation).

## 9. Done criteria

- `flutter analyze` clean.
- `flutter test` passes in `apps/desktop` (updated + new tests);
  `dart test` passes in `apps/engine` (minus the removed serve
  tests), `packages/download_ipc` (14), and the extension host
  (13); `node --test` passes for the extension (8); no
  regressions (scheduler 12, core 14, limiter 12, recovery 16,
  storage 11, transport 10, api 3).
- `flutter build linux --release` succeeds; the bundle runs
  standalone (no `dart run` needed for the engine).
- Manual check (on his machine): run the built app, add a
  download, close the window — the tray icon appears and the
  download completes; Show restores the window; Quit exits
  cleanly; the unpacked extension still creates downloads while
  the app is running (tray or window).
- Commit on `m1/idm-rework`; working tree clean.

## 10. Deviations decided during implementation

1. **Scheduler: `stateChanged(completed)` is held back too.** The task
   sets its status to completed (emitting `stateChanged(completed)`)
   before the scheduler finishes the sink, so the UI could report a
   download as completed before its file was renamed to the final path
   — the integration test caught this (the file did not exist yet when
   the state turned completed). `DownloadScheduler._onTaskEvent` now
   returns `false` for a completed `stateChanged` as well, and
   `_onTaskDone` emits `stateChanged(completed)` and then the
   `completed` event after `sink.finish()` succeeds. The scheduler's
   contract is now: either event means the file is final on disk.
2. **Datasource: `watchDownloads()` is a per-subscriber stream.** The
   original `async*` (`yield current; yield* _controller.stream`)
   attached the forwarding subscription only after the first yield was
   delivered, so an emission fired in between (the constructor's
   `_loadInitial`, or `addDownload`'s emit) was dropped. It now returns
   a fresh `StreamController` per subscriber whose `onListen`
   synchronously attaches the forwarder to the broadcast controller AND
   adds the current list, so no emission can slip in before the
   forwarder attaches. Tests: the addDownload test waits 50 ms after
   `addDownload` before asserting (the emission travels two async
   hops), and the integration test guards against an empty last
   emission in its `waitFor`.
3. **No `window_service_test.dart`.** The `WindowService.build()` calls
   real nativeapi (`TrayIcon.create()`) which needs a display; under
   headless `flutter test` it aborts the whole test shell with a Gtk
   SIGABRT (`Can't create a GtkStyleContext without a display
   connection`), which no try/catch can catch. dev-stack — the tray
   reference — has no `WindowService` test either. The close/quit/tray
   wiring is manual-only (see the manual check in §9). The
   `window_api_test.dart` (resolver logic) still runs.
4. **Riverpod 3.1.0 has no `AsyncValue.valueOrNull`.** `pauseAll()` uses
   `ref.read(downloadsProvider).value ?? const []`.
