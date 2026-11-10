# Plan: apps/desktop (§21 step 10) — real engine IPC datasource

Date: 2026-11-10. Branch: `m1/apps-desktop` (from `71d37b3`).
Scope: replace the in-memory downloads datasource with a real
engine IPC datasource, wire the UI to live engine state, and add
the pause/resume/cancel/retry actions. The desktop connects to a
running engine; it does not spawn one (that is M4/platform
integration, §13). No Download Details screen (§11.2), no
categories/scheduler/statistics/settings screens, no open-file
action — those are follow-ups.

## 1. Starting state (read from source 2026-11-10)

- `InMemoryDownloadDatasource`: `watchDownloads()` stream +
  `addDownload`/`updateDownload` on a local list; the stand-in to
  replace.
- `DownloadRepository` interface: `watchDownloads`,
  `addDownload(url)`, `pauseDownload`, `resumeDownload`,
  `cancelDownload` (all `Either<Failure, ...>`).
  `DownloadRepositoryImpl` validates http/https, derives the file
  name from the URL, creates the `Download` with a uuid, and flips
  state locally.
- `Download` entity (Equatable): `id, url, fileName, state
  (DownloadState: queued/downloading/paused/completed/failed/
  cancelled), downloadedBytes, totalBytes`, `progress` getter,
  `copyWith`. No speed field.
- `GetDownloads` usecase: one-shot `watchDownloads().first`.
- `Downloads` AsyncNotifier: `build()` calls `GetDownloads` once;
  `addDownload` invalidates self. The UI does NOT live-update today.
- `DownloadsScreen`: list (fileName/url/state), FAB + add dialog.
  No action buttons, no progress bar, no connection state.
- DI (`download_providers.dart`): `downloadDatasourceProvider`
  (in-memory), `downloadRepositoryProvider`,
  `getDownloadsProvider`.
- Existing tests: `get_downloads_test.dart` (mocks the repository
  with mocktail), `widget_test.dart` (pumps `PdmApp`, expects
  'Downloads' + 'No downloads yet.').
- Desktop pubspec already depends on `download_api` (path);
  `mocktail` is a dev dependency.

## 2. Shared default socket path (additive, `download_ipc`)

Move the default-path computation out of `apps/engine` into
`download_ipc` so both sides share it: `String
defaultSocketPath()` in a new `lib/src/paths.dart` (exported from
the barrel), same rules as `serve_command.dart` today
(`$XDG_RUNTIME_DIR/pdm/engine.sock`, else
`~/.local/share/pdm/engine.sock`; `%LOCALAPPDATA%\pdm\engine.sock`
on Windows). The token file is always `$socketPath.token`.
`apps/engine`'s `serve_command.dart` uses it; the desktop uses it
too. Add a unit test asserting the Linux default (with
`XDG_RUNTIME_DIR` set/unset via a `Platform.environment` override
is not possible — test only the shape: the path ends with
`pdm/engine.sock` and honours `XDG_RUNTIME_DIR` when present by
checking the returned string against the current environment).

## 3. `IpcDownloadDatasource` (new, data layer)

`apps/desktop/lib/features/downloads/data/datasources/ipc_download_datasource.dart`.
Constructor takes an `IpcClient` factory
(`Future<IpcClient> Function()`), a `downloadDirectory`, and an
optional `progressEmitInterval` (default 500 ms). The production
factory connects with `IpcClient.connect(channelFactory: () =>
UnixSocketTransport(socketPath: socketPath).connect(), token:
File('$socketPath.token').readAsString())`. Tests inject a
mocktail-mocked `IpcClient` (mocktail is already a dev dep).

- `Future<void> connect()`: connects once; on failure emits
  disconnected and retries every 5 s (a `Timer`, cancelled on
  dispose) until it succeeds. Reconnect after a dropped
  connection reuses `client.reconnect()`.
- `Stream<bool> watchConnected()`: `true` once the hello handshake
  succeeded, `false` otherwise. The UI shows a banner while false.
- `Stream<List<Download>> watchDownloads()`: a broadcast stream
  fed by the client's `syncSnapshots` (replace the local map,
  emit) and `events`:
  - `download.progress`: update the entry's bytes + speed, mark
    dirty; emit at most once per `progressEmitInterval` (a
    periodic timer flushes dirty state) — §11.3 throttling.
  - `download.stateChanged` / `download.completed` /
    `download.failed`: update the entry and emit immediately.
  - Unknown ids in events are ignored (a progress event for a
    download the sync has not shown yet is dropped).
  - The stream emits the current list immediately on subscribe
    (the latest snapshot, replayed like the client's).
- `Future<DownloadInfo> addDownload(String url)`: derives the
  file name from the URL (same rule as the repository has today),
  destination = `join(downloadDirectory, fileName)`, calls
  `client.createDownload`; the created download appears via the
  next sync/event, not by a local insert — the engine is the
  source of truth.
- `pauseDownload` / `resumeDownload` / `cancelDownload` /
  `retryDownload`: delegate to the client; no local state flip.
- `dispose()`: cancels the retry timer and the progress timer,
  closes the client.
- Mapping `DownloadInfo` → `Download`: status by name
  (`DownloadStatus` → `DownloadState`), `downloadedBytes`,
  `totalBytes`, `bytesPerSecond` (entity gains the field, default
  0; add it to `props` and `copyWith`).

## 4. Repository

- `DownloadRepository` gains `retryDownload(String id)`.
- `DownloadRepositoryImpl` now takes the `IpcDownloadDatasource`
  (constructor type changes; the in-memory datasource is deleted).
  `addDownload` keeps the http/https validation and returns the
  mapped `Download` from the client's `createDownload` result.
  Pause/resume/cancel/retry delegate to the datasource and map a
  `DownloadError` to `UnexpectedFailure(e.message)` (a
  `not-found` code maps to `ValidationFailure('Download not
  found')`). No local state flips anywhere.
- `GetDownloads` is removed (the live stream supersedes the
  one-shot load) together with `get_downloads_test.dart`; the
  usecase file and its provider are deleted.

## 5. Providers

- `downloadsProvider` becomes a `@riverpod
  Stream<List<Download>>` that yields
  `repository.watchDownloads()`. The screen's `ref.watch` usage
  and its `AsyncValue` handling stay the same.
- Actions move to a `downloadsActionsProvider` (a plain
  `Provider<DownloadsActions>` holding the repository): methods
  `addDownload`, `pauseDownload`, `resumeDownload`,
  `cancelDownload`, `retryDownload`, each returning
  `Either<Failure, ...>`; the screen shows a `SnackBar` on a
  `Left`.
- `engineConnectedProvider`: a `@riverpod Stream<bool>` from
  `datasource.watchConnected()`; the screen shows a banner while
  disconnected ("Engine not running — retrying…").
- DI (`download_providers.dart`): `downloadDatasourceProvider`
  now builds the `IpcDownloadDatasource` with the default socket
  path (via `defaultSocketPath()`), the default download
  directory (`~/Downloads` on Linux/macOS,
  `%USERPROFILE%\Downloads` on Windows), and the production
  client factory. `downloadRepositoryProvider` and the actions
  provider follow. The old `getDownloadsProvider` is deleted.

## 6. Screen

`DownloadsScreen`: each row shows fileName, url, a
`LinearProgressIndicator` + percentage + `downloaded/total`
bytes, and state text; trailing `IconButton`s by state —
downloading/queued: pause + cancel; paused: resume + cancel;
failed: retry + cancel; completed: no actions (open-file comes
with M4). The FAB + add dialog stay. A connection banner sits
above the list while disconnected; an `AsyncError` shows the
error text with a retry button that invalidates
`engineConnectedProvider`. Keep the layout to the existing
`ListView` + `ListTile` shape; no new screens.

## 7. Tests (TDD, RED first)

- `test/features/downloads/ipc_download_datasource_test.dart`
  (new): mocktail-mocked `IpcClient`.
  - Sync snapshot → the `watchDownloads` stream emits the mapped
    list; a second snapshot replaces it.
  - Progress events are throttled: 20 progress events in 100 ms
    produce at most 2 emissions (fake async with a 500 ms
    interval); a `stateChanged` event emits immediately even
    inside the throttle window.
  - `addDownload` calls `createDownload` with destination
    `join(dir, fileName)` and returns the mapped info.
  - Pause/resume/cancel/retry delegate with the right id.
  - A failed `connect()` emits disconnected and the retry timer
    reconnects (fake async).
- `test/features/downloads/download_repository_test.dart`
  (new): repository with a mocked datasource; URL validation
  rejects `ftp://`; a `DownloadError('not-found', ...)` from
  pause maps to `ValidationFailure`.
- `test/widget_test.dart` (updated): override the datasource
  provider with a fake that emits one queued download; the
  screen shows its file name, progress bar, and a pause button;
  tapping pause calls the fake. A disconnected override shows
  the banner. The old 'No downloads yet.' expectation moves to
  the empty-list case.
- `test/features/downloads/ipc_integration_test.dart` (new): a
  real `IpcServer` over an in-memory channel pair, backed by the
  ipc package's fake-engine shape (a small local fake engine in
  this test file — the ipc package's `test_helpers.dart` is not
  importable here), driving the real datasource + repository:
  create via the repository, progress + completed events flow
  through to `watchDownloads`.
- `download_ipc` test: `defaultSocketPath()` ends with
  `pdm/engine.sock`.
- Delete `get_downloads_test.dart` with the usecase.

## 8. Files

- New: `apps/desktop/lib/features/downloads/data/datasources/ipc_download_datasource.dart`,
  `apps/desktop/lib/features/downloads/presentation/providers/downloads_actions.dart`
  (or the actions live in `download_providers.dart` — decide
  during implementation; keep providers in one place),
  `apps/desktop/test/features/downloads/ipc_download_datasource_test.dart`,
  `apps/desktop/test/features/downloads/download_repository_test.dart`,
  `apps/desktop/test/features/downloads/ipc_integration_test.dart`.
- Changed: `packages/download_ipc/lib/src/paths.dart` (new) +
  barrel, `packages/download_ipc/test/` (path test),
  `apps/engine/lib/src/serve_command.dart` (use
  `defaultSocketPath()`), `apps/desktop/lib/features/downloads/
  data/repositories/download_repository_impl.dart`,
  `domain/repositories/download_repository.dart`,
  `domain/entities/download.dart` (+ `bytesPerSecond`),
  `presentation/providers/downloads_provider.dart`,
  `presentation/screens/downloads_screen.dart`,
  `providers/download_providers.dart`,
  `apps/desktop/pubspec.yaml` (add `download_ipc` path dep),
  `apps/desktop/test/widget_test.dart`,
  `docs/plans/2026-11-10-m1-apps-desktop.md` (this file).
- Deleted: `apps/desktop/lib/features/downloads/data/datasources/in_memory_download_datasource.dart`,
  `apps/desktop/lib/features/downloads/domain/usecases/get_downloads.dart`,
  `apps/desktop/test/features/downloads/get_downloads_test.dart`.

## 9. Done criteria

- `flutter analyze` clean.
- `flutter test` passes in `apps/desktop` (existing tests updated
  + new ones); `dart test` passes in `packages/download_ipc`
  (13 existing + path test); no regressions (engine 15, scheduler
  12, core 14, limiter 12, recovery 16, storage 11, transport 10,
  api 3).
- Manual check: run `dart run bin/engine.dart serve` from
  `apps/engine`, run the desktop app, add a download from the UI
  — it appears, progresses, and completes; pause/resume from the
  UI work; killing the engine shows the disconnected banner, and
  restarting it reconnects.
- Commit on `m1/apps-desktop`; working tree clean.


## Deviations decided during implementation

- `IpcDownloadDatasource.addDownload` adds the created download to
  the local map from the create response and emits immediately,
  instead of waiting for the next sync/event as the plan said: the
  engine sends no event for a download it just created, so without
  this the new row would not appear until an event arrived for it.
  The create response is still the engine's own data, so the engine
  remains the source of truth.
- `fake_async` added to the desktop dev dependencies (1.3.3, already
  in the lock as a transitive dep of `flutter_test`): the datasource
  test imports it for the throttling test, and the analyzer's
  `depend_on_referenced_packages` rule requires a direct dep.
- A duplicated `export 'src/paths.dart';` line in the `download_ipc`
  barrel (from re-running the deploy script) was removed; analyze
  is clean after.
