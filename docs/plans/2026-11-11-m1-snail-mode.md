# Snail mode — plan (2026-11-11)

## Correction (Tuấn Anh, 2026-11-11)

The bottom-left status-bar ON/OFF toggle is **snail mode**, not a global
pause/resume-all. When ON it limits the global download speed to
**8 KB/s (8192 B/s)** to keep the connection continuous with the server.
The current pause-all/resume-all behavior is wrong and is replaced.

## Wiring (already exists in the engine, missing in the desktop)

- `PdmEngine.setGlobalBandwidthLimit(int?)` exists
  (`apps/engine/lib/src/pdm_engine.dart:194`).
- No `setGlobalBandwidthLimit` anywhere in `apps/desktop/lib` yet.

## Tasks (TDD, small, in order)

1. **Datasource** — `EngineDownloadDatasource.setGlobalBandwidthLimit(int?)`
   delegates to `engine.setGlobalBandwidthLimit`. Test in
   `engine_download_datasource_test.dart` (MockPdmEngine): verify the
   engine receives 8192 and null.
2. **Repository** — add `setGlobalBandwidthLimit(int?)` to the
   `DownloadRepository` interface and to `DownloadRepositoryImpl` via
   the existing `_act` helper (DownloadError → Failure). Test in
   `download_repository_test.dart` (MockDatasource): delegates, and an
   engine error maps to a failure.
3. **Actions** — `DownloadsActions.setGlobalBandwidthLimit(int?)`
   delegates to the repository.
4. **Screen** — replace the pause-all toggle with snail mode:
   - `_globalPaused` → `_snailMode` (default false); delete
     `_globalPausedIds` and `_toggleGlobalPause`.
   - `_toggleSnailMode()`: if off, `setGlobalBandwidthLimit(8192)` and
     set `_snailMode = true`; if on, `setGlobalBandwidthLimit(null)`
     and set `_snailMode = false`. SnackBar on failure.
   - `_buildGlobalToggle()` no longer takes the download list; the
     `_buildStatusBar` call site (line 791) drops the argument.
   - Keep the pill visuals (speed icon + ON/OFF): ON (blue) = snail
     mode active, OFF (dark) = unlimited.
   - Snail speed constant: `8192` bytes/s, as a static const in the
     screen state.
   - Widget test: tapping the toggle calls `setGlobalBandwidthLimit(8192)`,
     tapping again calls `setGlobalBandwidthLimit(null)`. The existing
     'toolbar and status bar show the FDM layout' test (expects 'ON')
     still passes.
5. **Verify** — full desktop `flutter test`, `flutter analyze`,
   `flutter build linux --release`. Commit + push to main.

## Out of scope

- No per-download limit UI, no Settings screen, no persistence of the
  snail-mode choice across restarts (it resets to OFF on launch).
- No change to the engine limiter itself (the global token bucket
  already exists and `setGlobalBandwidthLimit` already wires it).
