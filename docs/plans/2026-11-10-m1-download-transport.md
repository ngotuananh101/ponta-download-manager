# Plan: M1 — download_transport (2026-11-10)

Scope: `packages/download_transport` only — HTTP probing, range validation,
and byte streaming behind an interface (§5.2, §5.3, §8, §15 of
`docs/architecture.md`). No segment planning, no file writing, no
scheduler — those are `download_core` / `download_storage` / `download_scheduler`.

Note on process: the Superpowers workflow wants a git worktree, but the
bridge is locked to the project root, so a worktree outside the root is
unreachable. This task works on branch `m1/download-transport` in the
same tree instead. Baseline is the scaffold commit `76d2a7b` (analyze
clean, all tests green).

## Tasks

1. Branch `m1/download-transport` (from `76d2a7b`), this plan file.
2. RED: `test/download_transport_test.dart` — local `HttpServer` fixtures
   (`/file` range-capable, `/no-range`, `/no-head` 405, `/not-found` 404,
   `/redirect` 302). Covers probe, range validation, streaming, errors,
   cancel. Run `dart test` in the package, expect compile failures.
3. GREEN: implement
   - `lib/src/resource_info.dart` — `ResourceInfo` (final URL, status,
     content length, range support, ETag, Last-Modified, Content-Disposition,
     content type, file name).
   - `lib/src/range_validation.dart` — `RangeValidation` (valid, reason,
     total bytes).
   - `lib/src/download_transport.dart` — `DownloadTransport` interface:
     `probe`, `validateRange`, `openStream`, `close`.
   - `lib/src/http_transport.dart` — `HttpTransport` on `dart:io`
     `HttpClient`. HEAD with GET/Range fallback on 405/501. Range
     validation per §5.3 (206 + Content-Range match + total consistent).
     A 200 answer to a Range request is reported invalid, never written
     into a segment offset. Errors are `DownloadError` from
     `download_api` with stable codes (`http-<status>`, `network`,
     `timeout`).
   - `lib/download_transport.dart` barrel; `pubspec.yaml` gains
     `download_api` (path) and `logging`.
4. Verify: `flutter pub get` (root), `flutter analyze`, `dart test` in
   `packages/download_transport`.
5. Review: report results to the owner; merge only on his decision.

## Done when

- `flutter analyze` reports no issues.
- `dart test` in `packages/download_transport` passes all tests,
  including the local-server probe/range/stream/error/cancel cases.
- No file outside `packages/download_transport` and this plan changes.
