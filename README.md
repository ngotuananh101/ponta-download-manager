# Ponta Download Manager (pdm)

Desktop download manager inspired by IDM. Windows and Linux, Flutter UI,
Dart download engine, SQLite persistence. Engine-first, UI-independent.

Architecture: `docs/architecture.md`. UI architecture follows
[ssoad/flutter_riverpod_clean_architecture](https://github.com/ssoad/flutter_riverpod_clean_architecture)
(Riverpod 3.x, clean architecture, fpdart).

## Layout

```text
apps/desktop/          Flutter desktop app (Windows, Linux)
apps/engine/           Standalone Dart engine (CLI / daemon)
packages/download_api/ Public engine API: models, commands, events
packages/download_*/   Engine packages (see docs/architecture.md §14, §21)
test/                  Cross-package integration / stress / benchmark tests
docs/                  architecture.md, plans
```

Implementation order is `docs/architecture.md` §21: `download_api` first,
then transport, core, storage, scheduler, recovery, limiter, engine,
IPC, desktop UI last. The desktop app currently runs against an
in-memory datasource as a stand-in for the engine IPC (M3).

## Prerequisites

Flutter SDK 3.35+ / Dart SDK 3.10+ (verified: Flutter 3.47.9, Dart 3.13.7).
Linux desktop toolchain for `flutter run -d linux` / `flutter build linux`.

## Commands

```sh
flutter pub get                                   # resolve the workspace
dart run build_runner build --delete-conflicting-outputs   # in packages/download_api and apps/desktop
flutter analyze                                   # from the root
flutter test                                      # desktop app tests
dart test                                         # engine + package tests
flutter run -d linux                              # run the desktop UI
dart run apps/engine/bin/engine.dart --help       # engine CLI
```

## Notes

- The app id is the `flutter create` default (`com.example.pdm`).
  Change it later with the template rename approach if needed.
- Generated files (`*.freezed.dart`, `*.g.dart`) are committed.
