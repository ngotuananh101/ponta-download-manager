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
tools/                 fetch_external_tools.sh (ffmpeg + yt-dlp + quickjs, not committed)
docs/                  architecture.md, plans
```

The engine runs in-process in the desktop app (`PdmEngine`); the app
also hosts the IPC server the browser extension talks to. The engine
CLI (`apps/engine/bin/engine.dart`) only offers the `download`
subcommand for headless use; there is no engine daemon.

## Prerequisites

Flutter SDK 3.47+ / Dart SDK 3.13+ (verified: Flutter 3.50.0, Dart 3.14.0).
Linux desktop toolchain for `flutter run -d linux` / `flutter build linux`.
Bundled tools: run `tools/fetch_external_tools.sh` once before building —
ffmpeg, yt-dlp and quickjs are fetched into `apps/desktop/bundle/bin/` and
are not committed (see `tools/THIRD_PARTY.md`).

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

## Release

Releases are built by GitHub Actions (`.github/workflows/release.yml`).
Pushing a tag `v*` runs the tests, builds all 7 artifacts and creates a
GitHub Release; a manual run (`workflow_dispatch`) builds the same
artifacts without creating a release.

```sh
# 1. Bump the version in apps/desktop/pubspec.yaml (e.g. 0.1.0+1 -> 0.2.0+1)
#    and keep kAppVersion in apps/desktop/lib/app/app_info.dart in sync.
# 2. Commit and push, then tag:
git tag v0.2.0
git push origin v0.2.0
```

Artifacts (all for x64):

| File | Platform |
|---|---|
| `pdm-<version>-windows-x64-setup.exe` | Windows installer (Inno Setup) |
| `pdm-<version>-windows-x64.msi` | Windows installer (WiX) |
| `pdm-<version>-windows-x64-portable.zip` | Windows portable |
| `pdm-<version>-linux-x64.deb` | Debian/Ubuntu |
| `pdm-<version>-linux-x64.rpm` | Fedora/RHEL |
| `pdm-<version>-linux-x64.AppImage` | Linux portable |
| `pdm-<version>-linux-x64-portable.tar.gz` | Linux portable |

The installers are unsigned (no code signing certificate yet): Windows
shows a SmartScreen warning on first run.

## Notes

- The app id is `com.ponta.pdm`, matching the installed `.desktop` file
  (`StartupWMClass`) and the native messaging host. It is also what makes a
  second launch a remote activation of the running instance (Linux: GApplication
  unique mode; Windows: a named mutex) instead of a second app over the same
  download database.
- Generated files (`*.freezed.dart`, `*.g.dart`) are committed.
