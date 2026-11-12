# Ponta Download Manager (pdm)

Desktop download manager inspired by IDM. Windows and Linux, Flutter UI,
Dart download engine, SQLite persistence. Engine-first, UI-independent.

Architecture: `docs/architecture.md`. UI architecture follows
[ssoad/flutter_riverpod_clean_architecture](https://github.com/ssoad/flutter_riverpod_clean_architecture)
(Riverpod 3.x, clean architecture, fpdart).

## Layout

```text
apps/desktop/          Flutter desktop app (Windows, Linux)
apps/engine/           Standalone Dart engine (CLI only: the download subcommand)
packages/download_api/ Public engine API: models, commands, events
packages/download_*/   Engine packages (see docs/architecture.md §14, §21)
integrations/          Browser extension + native host
tools/                 fetch_external_tools.sh (ffmpeg + yt-dlp, not committed)
docs/                  architecture.md, plans
```

The engine runs in-process in the desktop app (`PdmEngine`); the app
also hosts the IPC server the browser extension talks to. The engine
CLI (`apps/engine/bin/engine.dart`) only offers the `download`
subcommand for headless use; there is no engine daemon.

## Prerequisites

Flutter SDK 3.35+ / Dart SDK 3.10+ (verified: Flutter 3.47.9, Dart 3.13.7).
Linux desktop toolchain for `flutter run -d linux` / `flutter build linux`.
Bundled tools: run `tools/fetch_external_tools.sh` once before building —
ffmpeg + yt-dlp are fetched into `apps/desktop/bundle/bin/` and are not
committed (see `tools/THIRD_PARTY.md`).

## Commands

```sh
flutter pub get                                   # from the repo root
flutter analyze                                   # from the repo root
flutter test                                      # from apps/desktop
dart test                                         # per package: apps/engine, packages/<name>
flutter run -d linux                              # from apps/desktop
dart run apps/engine/bin/engine.dart --help       # engine CLI, from the repo root
```

Freezed/json_serializable codegen, when a model changes (in
`packages/download_api` or `apps/desktop`):

```sh
dart run build_runner build --delete-conflicting-outputs
```

## Notes

- The app id is the `flutter create` default (`com.example.pdm`).
  Change it later with the template rename approach if needed.
- Generated files (`*.freezed.dart`, `*.g.dart`) are committed.
