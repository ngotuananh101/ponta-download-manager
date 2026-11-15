# Default download directory follows the OS

2026-11-15

## Intent

A Windows user moved their Downloads folder (right-click the folder →
Properties → Location → Move). PDM keeps downloading into
`%USERPROFILE%\Downloads` anyway, and because `FileChunkSink.create` does
`Directory(directory).create(recursive: true)`, the old folder comes back on
the next download.

The cause is that PDM never asks the OS: both entry points concatenate the
path themselves.

- `apps/desktop/lib/features/downloads/providers/download_providers.dart`
  (`_defaultDownloadDirectory`) — Add download, drop, clipboard paste, bulk
  add, and the engine's `downloadDirectory` fallback.
- `integrations/browser-extension/host/bin/native_host.dart` — downloads
  intercepted from the browser.

Linux has the same defect: `$HOME/Downloads` is hardcoded, so a user whose
`XDG_DOWNLOAD_DIR` points elsewhere gets the wrong folder too.

Goal: PDM writes to whatever folder the OS reports as the user's Downloads
directory, from both entry points, with one implementation.

## Non-goals

- A settings screen to override the directory. The New download dialog's
  "Save to" already allows a per-download choice, and that choice is
  remembered in `FileConflictSettings`' recent directories.
- Changing the engine CLI default: `runDownload` keeps `downloads` relative
  to the working directory, and `EngineConfig.downloadDirectory` (`'downloads'`)
  is only a fallback for a destination with no directory part.
- Migrating files already written to the old folder, or repairing rows whose
  recorded destination no longer exists (Missing + Retry already covers that).

## Approaches considered

**A — new pure-Dart package `packages/download_platform` (chosen).** One
synchronous `defaultDownloadDirectory()` used by both the Flutter app and the
native host. The host is `dart compile exe` with no Flutter dependency, so
`path_provider` is not available there; a shared non-Flutter package is the
only way to have one implementation. Sync keeps the existing
`Provider<String> downloadDirectoryProvider` and the synchronous
`EngineDownloadDatasource` construction unchanged.

**B — `path_provider` in the app, inline `win32` in the host.** Free XDG
support from `path_provider_linux`, but its API is async, so the provider
becomes a `FutureProvider` and the datasource construction has to await; and
the host still needs its own Windows code, which is the two-copies problem
this fix removes.

**C — the host asks the app for the path over IPC.** One source of truth, but
it adds a protocol method, a round trip, and a dependency of the host on a
running app for something it can answer locally. Larger than the defect.

## Design

New package `packages/download_platform` (workspace member, no Flutter):

```dart
String defaultDownloadDirectory({
  Map<String, String>? environment,
  bool? isWindows,
  String? Function()? windowsDownloads,
});

String? windowsKnownDownloads();
String? xdgDownloadDirectory({required String home, String? configHome});
```

`environment`, `isWindows` and `windowsDownloads` are test seams (defaulting to
`Platform.environment`, `Platform.isWindows`, and the win32 call) — the same
shape as `isWindows` in `packages/download_ipc/lib/src/ipc_transport.dart`. CI
runs on Linux, so the Windows branch is only reachable through the seam.
The POSIX side needs no read seam: its tests point `XDG_CONFIG_HOME` at a temp
directory and write a real `user-dirs.dirs` there. (A `readFile` seam was
prototyped and dropped — it made the public signature noisier than the temp
file it replaced.)

**Windows branch.** `SHGetKnownFolderPath(FOLDERID_Downloads, KF_FLAG_DEFAULT)`
from `package:win32`, freeing the result with `CoTaskMemFree`. That API
resolves whatever the Location tab (or a group-policy redirect) configured.
If it throws or returns empty — the documented failure cases — fall back to
`%USERPROFILE%\Downloads`. `package:win32` is pure Dart FFI and its DLLs are
resolved lazily; verified that a win32 importer both AOT-compiles and runs on
Linux, so the package stays testable on the Linux CI runner.

**POSIX branch.** Read `${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs` and
take `XDG_DOWNLOAD_DIR="..."`, expanding `$HOME` / `${HOME}`, stripping the
quotes, and resolving a relative value against `$HOME`. Fall back to
`$HOME/Downloads` when the file is missing or unreadable (including invalid
UTF-8), the key is absent, the value is empty, or it resolves to `$HOME` itself
(how `xdg-user-dirs` marks the directory as disabled). Parsing the file
directly rather than shelling out to `xdg-user-dir` keeps this a pure sync
function with no subprocess at app startup.

**Path shapes.** Both branches normalize with `p.windows.normalize` /
`p.posix.normalize` rather than the host's context: the Windows fallback built
on a Linux test host would otherwise mix `\` and `/`, and a known folder that
comes back with a trailing separator (`D:\Downloads\`) would reach
`p.join(directory, fileName)` as a doubled separator. A UNC value
(`\\nas\share\Downloads`) survives normalization intact.

**Call sites.** `_defaultDownloadDirectory()` in `download_providers.dart` is
deleted and the provider returns `defaultDownloadDirectory()`;
`bin/native_host.dart` does the same instead of its inline expression. Both
keep their current signatures, so nothing downstream changes.

**Packaging.** `packages/download_platform` joins the root `workspace:` list
and the pubspecs of `apps/desktop` and `integrations/browser-extension/host`
get a path dependency. (A `download_platform` stub existed in the scaffold and
was deleted in 9065317 for having no purpose; it now has one.)

**Docs.** `apps/desktop/README.md` currently says "Downloads default to
`~/Downloads`" — update it to say the OS's configured Downloads folder.

**Tests.** `packages/download_platform/test/download_directory_test.dart`:
Windows with a moved known folder wins over `%USERPROFILE%`; a known folder
that is null, empty or throws falls back; the fallback is a Windows path on
any host; a trailing separator is stripped and UNC / non-ASCII values survive;
POSIX reads `XDG_DOWNLOAD_DIR` from a temp `user-dirs.dirs` with `$HOME` and
`${HOME}` expanded, absolute and relative values, and falls back on a missing
file, a missing key, an empty value, a disabled directory, a directory in
place of the file, and invalid UTF-8.

## Left to the builder

- Whether the resolved directory should be created eagerly. It should not:
  `FileChunkSink.create` already creates it recursively, and a sync `create`
  at startup would touch disk in widget tests.
- Any logging on the fallback path: the package has no logger today; a silent
  fallback is acceptable because the fallback is the pre-existing behaviour.
