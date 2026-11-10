# Plan: project scaffold (2026-11-10)

Goal: a compiling monorepo skeleton per `docs/architecture.md` §14,
following the Riverpod clean-architecture template for `apps/desktop`,
ready for M1 (download core) work.

## Tasks

1. `git init`, branch `main`.
2. `flutter create apps/desktop --platforms=windows,linux --project-name pdm`.
3. Root workspace: `pubspec.yaml` (workspace members), `analysis_options.yaml`
   (template rules), `.gitignore`, `README.md`.
4. `apps/desktop`: template-style clean architecture skeleton
   (`core/error`, `features/downloads` domain/data/presentation,
   `providers/`, `shared/theme`), in-memory datasource as the IPC stand-in.
5. `apps/engine`: Dart CLI skeleton (`bin/engine.dart`, `parseCliArgs`,
   `EngineConfig`).
6. `packages/download_api`: public API from §16 (`DownloadEngine`,
   `DownloadInfo`, `CreateDownloadRequest`, `DownloadEvent`,
   `DownloadError`) with freezed/json codegen.
7. Stub shells for the other ten engine packages (§14) so the workspace
   shape is complete; real code lands in §21 order.

## Verification

- `flutter pub get` at the root resolves the workspace.
- `dart run build_runner build --delete-conflicting-outputs` in
  `packages/download_api` and `apps/desktop` generates `*.freezed.dart`
  / `*.g.dart`.
- `flutter analyze` at the root: no issues.
- `flutter test` in `apps/desktop` and `dart test` in `apps/engine`
  and `packages/download_api`: all pass.
- `flutter build linux`: desktop app builds.

## Done when

All verification commands pass on a clean checkout, and `git status`
shows only the scaffold files (uncommitted; the owner commits).
