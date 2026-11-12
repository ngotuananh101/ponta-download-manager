# pdm (desktop)

Flutter desktop app for Ponta Download Manager (Windows, Linux).
Dark-only, FDM-style UI: downloads table, per-row menu, details panel,
main menu, tray. The download engine runs in-process (`PdmEngine`);
the app also hosts the IPC server the browser extension talks to.

## Run

```sh
flutter run -d linux
```

Or run the release build: `build/linux/x64/release/bundle/pdm`.

Before building, fetch the bundled ffmpeg/yt-dlp binaries (not
committed): `tools/fetch_external_tools.sh` from the repo root.

## Tests

```sh
flutter test
flutter analyze
```

Downloads default to `~/Downloads`.
