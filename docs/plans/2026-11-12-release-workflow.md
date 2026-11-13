# Release workflow — plan

Status: DONE

## Source

Tuấn Anh 2026-11-12 22:16: "thêm workflow build app cho: windows EXE / MSI /
Portable; linux RPM / DEB / Appimage / Portable". Đề xuất (GitHub Actions,
1 file workflow, tag `v*` + chạy tay) đã duyệt 2026-11-12 22:20 ("Làm theo
đề xuất này").

## Decisions (đã duyệt)

- Chạy trên GitHub Actions, vì máy anh là Fedora nên không build installer
  Windows local được.
- Không ký số (chưa có cert): Windows sẽ cảnh báo SmartScreen, MSI/EXE
  unsigned. Ghi rõ trong README + release notes.
- Windows native host (browser extension) KHÔNG nằm trong phạm vi — chỉ
  đóng gói desktop app.
- Version lấy từ `apps/desktop/pubspec.yaml` (hiện `0.1.0+1` → version
  `0.1.0`, build `1`; MSI cần 4 phần → `0.1.0.1`). `kAppVersion`
  (`apps/desktop/lib/app/app_info.dart`) giữ đồng bộ bằng tay như hiện tại.
- Action versions kiểm tra qua web search 2026-11-12 (các major cũ v4/v2 đã
  lỗi thời, chạy Node 20 deprecated): `actions/checkout@v7`,
  `actions/upload-artifact@v7`, `actions/download-artifact@v8`,
  `softprops/action-gh-release@v3`, `subosito/flutter-action@v2`
  (composite, không có Node runtime riêng, vẫn v2).

## Tools

- EXE installer: Inno Setup 6 (`choco install innosetup`, `iscc`).
- MSI: WiX v4 schema (`dotnet tool install --global wix`, `wix build`),
  `.wxs` viết tay theo mẫu minimal đã verify (Package / MajorUpgrade /
  Feature / StandardDirectory / ComponentGroup).
- DEB + RPM: fpm (`gem install fpm`, một tool làm cả 2).
- AppImage: linuxdeploy (continuous) + linuxdeploy-plugin-gtk +
  appimagetool (continuous), chạy qua `--appimage-extract` để khỏi cần FUSE.
- Portable: Windows zip, Linux tar.gz.

## Findings from survey (code-verified 2026-11-12)

- Repo chưa có `.github/` — workflow viết từ đầu.
- `apps/desktop/windows/CMakeLists.txt` KHÔNG có rule cài `bundle/bin`
  (chỉ Linux có, `apps/desktop/linux/CMakeLists.txt:102-105`). Windows
  build hiện tại không kèm ffmpeg.exe/yt-dlp.exe — `ExternalTools` chỉ
  tìm ở `<exe_dir>/bin/<name>` rồi PATH
  (`packages/download_external/lib/src/external_tools.dart:51`). P1 thêm
  rule tương tự cho Windows (guard `if(EXISTS ...)`, không
  `USE_SOURCE_PERMISSIONS` vì Windows không có khái niệm +x).
- Icon: `apps/desktop/assets/images/icon.ico` (multi-size 16/32/48/256)
  dùng cho `SetupIconFile` của Inno; exe đã nhúng
  `apps/desktop/windows/runner/resources/app_icon.ico` qua `Runner.rc`
  nên shortcut trỏ thẳng `{app}\pdm.exe`. Không có file
  `assets/images/app_icon.ico` như dự kiến ban đầu.
- `.desktop` cho DEB/RPM/AppImage lấy nội dung từ
  `LinuxDesktopService.generateDesktopEntryContent` (Name "Ponta Download
  Manager", Comment "Download manager with segmented downloads",
  Categories `Network;FileTransfer;`, StartupWMClass `com.ponta.pdm`),
  với `Exec=pdm %u` (một file dùng chung: DEB/RPM có symlink
  `/usr/bin/pdm`, AppImage có `usr/bin/pdm` trong PATH của AppRun).
- `tools/fetch_external_tools.sh` đã hỗ trợ `windows` (cần `curl`,
  `tar`, `unzip` trên Git Bash) và `linux`; không sửa script trừ khi lần
  chạy workflow đầu tiên chứng minh nó lỗi.
- WiX UpgradeCode (sinh một lần, KHÔNG bao giờ đổi):
  `6df68f12-0032-4d3a-bb94-5cd8200181d2`.

## Artifacts (7)

| File | Nguồn |
|---|---|
| `pdm-<version>-windows-x64-setup.exe` | Inno Setup |
| `pdm-<version>-windows-x64.msi` | WiX |
| `pdm-<version>-windows-x64-portable.zip` | zip của `build/windows/x64/runner/Release` |
| `pdm-<version>-linux-x64.deb` | fpm, `/opt/pdm` + symlink `/usr/bin/pdm` |
| `pdm-<version>-linux-x64.rpm` | fpm, như trên |
| `pdm-<version>-linux-x64.AppImage` | linuxdeploy + appimagetool |
| `pdm-<version>-linux-x64-portable.tar.gz` | tar.gz của `build/linux/x64/release/bundle` |

## Workflow (.github/workflows/release.yml)

- Trigger: push tag `v*` + `workflow_dispatch`.
- Job `test` (ubuntu-latest): checkout, flutter-action
  (`flutter-version: '3.47.9'` khớp máy local), `flutter pub get`,
  `flutter test` + `flutter analyze` (apps/desktop), `dart test` +
  `dart analyze` (apps/engine, từng `packages/*`,
  `integrations/browser-extension/host`), `node --test` (extension),
  `pytest tools/`.
- Job `build-windows` (windows-latest, needs test): đọc version
  (`packaging/read_version.py`), `flutter build windows --release`,
  `bash tools/fetch_external_tools.sh windows`, copy không cần thêm
  (CMake rule đã đưa bin/ vào Release), `iscc` → setup.exe,
  `python packaging/windows/generate_wix_files.py` → `Files.wxs` rồi
  `wix build` → .msi, zip bundle → portable. Upload 3 artifact.
- Job `build-linux` (ubuntu-latest, needs test): đọc version,
  `sudo apt-get install libgtk-3-dev`, `flutter build linux --release`,
  `fetch_external_tools.sh linux`, staging `/opt/pdm` + symlink +
  `.desktop` + icon rồi fpm → .deb + .rpm, linuxdeploy → .AppImage,
  tar.gz bundle → portable. Upload 4 artifact.
- Job `release` (needs cả 2 build, chỉ khi ref là tag `v*`):
  `actions/download-artifact` (pattern `pdm-*`, merge-multiple) +
  `softprops/action-gh-release@v3` (`generate_release_notes: true`).
  Chạy tay thì không tạo release, artifact vẫn xem được từ run.

## Parts

- P0. Plan doc này. Commit riêng.
- P1. Packaging sources: `packaging/windows/pdm.iss`,
  `packaging/windows/pdm.wxs`, `packaging/windows/generate_wix_files.py`,
  `packaging/read_version.py`, `packaging/linux/com.ponta.pdm.desktop`,
  `packaging/linux/after-install.sh`, rule `bundle/bin` cho
  `apps/desktop/windows/CMakeLists.txt`, `.gitignore`
  (`packaging/windows/Files.wxs`, `dist/`). Commit riêng.
- P2. `.github/workflows/release.yml`. Commit riêng.
- P3. Verify trên máy Linux của anh: YAML parse + đọc lại từng step,
  `.wxs` well-formed XML, `.iss` khớp layout `flutter build windows`,
  `flutter build linux --release` + đóng gói portable tar.gz thật, giải
  nén kiểm tra. fpm / linuxdeploy thử nếu cài được nhanh bằng lệnh có
  trong allowlist; nếu không thì ghi rõ chưa verify. Tuyệt đối không tạo
  tag `v*` thật, không tạo GitHub Release thật.
- P4. README root: mục release (bump version, push tag, artifact ở đâu,
  unsigned + SmartScreen). Commit riêng.

## Done criteria

- Plan doc Status DONE.
- Cả 7 artifact được định nghĩa trong workflow, tên file khớp bảng trên.
- YAML parse được; `.wxs` well-formed; `.iss` khớp layout build Windows.
- `flutter build linux --release` + portable tar.gz thật chạy kiểm tra
  trên máy anh (file đầy đủ, binary là ELF).
- Mọi commit đã push lên `main`, cây làm việc sạch.
- Chưa verify (cần lần chạy workflow đầu tiên trên GitHub): toàn bộ job
  Windows (Inno, WiX, fetch tools trên Git Bash), fpm DEB/RPM,
  AppImage, và job release thật.

## Fixes after the first run

- 2026-11-12 ~23:54 (job `test`, ubuntu-26.04): `flutter test` failed
  because the cnativeapi 0.5.10 native-assets hook runs
  `pkg-config --cflags gtk+-3.0 x11 xi` and the runner image has no GTK3
  dev packages ("Package gtk+-3.0 was not found"). Fix: install the
  standard Flutter Linux deps (`clang cmake ninja-build pkg-config
  libgtk-3-dev liblzma-dev`) in the `test` job before the desktop tests;
  the `build-linux` job's install step got the same set.
  `libstdc++-12-dev` is NOT included: version-pinned, does not exist
  on Ubuntu 26.04; the image already ships build-essential/gcc.
  The `test` job had no install step at all before this fix, while
  `build-linux` already installed `libgtk-3-dev`.

- 2026-11-13 ~00:02 (second run, job `test`): the GTK fix worked, but
  the engine suite failed 97 passed / 2 failed — both failures were
  the known teardown race (`FileSystemException: Directory not empty`
  at `engine_download_test.dart:176`, tests 'listDownloads carries
  the priority' and 'a retry after a restart does not overwrite
  other downloads'). Both tests dispose the engine, but dispose
  returns before cancelled tasks finish unwinding, so a file can
  still appear while the recursive delete runs. Fix: the group
  tearDown now retries the temp-dir delete (10 x 100ms) and only
  rethrows after the last attempt. Verified with 3 consecutive
  full engine runs on his machine (exit 0 each) + `dart analyze`
  clean. Making `dispose` itself await task quiescence is still an
  open production-side improvement if the flake ever returns.

- 2026-11-13 ~01:34 (third run, build jobs): two failures, both in
  the workflow itself, not the app.
  * Windows: `iscc` failed with `No files found matching
    "...\build\windows\x64\runner\Release\*"`. The packaging
    steps run at the repo root, but the real output is
    `apps/desktop/build/windows/...`. Same wrong path also lived in
    the `pdm.iss` default SourceDir, the `pdm.wxs` comment, and
    `generate_wix_files.py` DEFAULT_SOURCE (the workflow calls it
    with no args) — all fixed to `apps/desktop/build/...`.
  * Both jobs: "Fetch external tools" ran AFTER the flutter build.
    The fetch script writes to `apps/desktop/bundle/bin/` and the
    CMake bundle/bin rule copies it into the release bundle AT
    BUILD TIME, so the built bundle had no bin/. The Linux DEB/RPM
    were created without ffmpeg/yt-dlp, and the AppImage step died
    on `ln: failed to create symbolic link 'AppDir/usr/bin/pdm'`.
    Fix: fetch BEFORE the build in both jobs; the AppImage step
    also does `mkdir -p AppDir/usr/bin` before the ln.

- 2026-11-13 ~08:23 (fourth run): two more failures.
  * Windows MSI: `wix.exe : error WIX7015: You must accept the Open
    Source Maintenance Fee (OSMF) EULA to use WiX Toolset v7`.
    Unpinned `dotnet tool install --global wix` now pulls WiX v7
    (7.0.0 Apr 2026, 7.0.1 Oct 2026), which gates builds behind the
    OSMF EULA. Fix: `wix build ... -acceptEula wix7` — the documented
    non-interactive CI acceptance; OSMF v1.1 charges no fee below
    $10,000/year revenue. (`generate_wix_files.py` itself worked:
    18 files, 15 directories.)
  * Linux AppImage: `./linuxdeploy-plugin-gtk-x86_64.AppImage:
    line 1: Not: command not found` (exit 127). The gtk plugin is
    no longer published as an AppImage — the `continuous` asset
    404s, and plain `curl -L` silently saved the 404 page. Fix:
    download the upstream shell script instead, pinned to commit
    `3b67a1d` (verified: resolves to the real 704-line plugin),
    pass `--plugin ./linuxdeploy-plugin-gtk.sh`, set
    `DEPLOY_GTK_VERSION=3`, and use `curl -fL` on all three
    downloads so an HTTP error fails the step immediately.
  * Verified on this run: the Windows fetch branch works on a real
    runner (ffmpeg.exe 105 MB + yt-dlp.exe 23 MB into
    `apps/desktop/bundle/bin/`, unzip present in Git Bash); the
    Windows CMakeLists bundle/bin rule exists (lines 84-87).

- 2026-11-13 ~09:00 (fifth run, build jobs): `-acceptEula wix7`
  worked, both remaining failures were new.
  * Linux AppImage: `-- Running input plugin:
    ./linuxdeploy-plugin-gtk.sh -- ERROR: Could not find plugin:
    ./linuxdeploy-plugin-gtk.sh`. linuxdeploy does not accept a path
    for `--plugin`: it scans $PATH plus the CWD for entries matching
    `^linuxdeploy-plugin-([^\s\.-]+)`, registers them by *name*, and
    then looks the argument up in that map. A path can never match
    the map key. Fix: `--plugin gtk` (the file is already in the CWD,
    which linuxdeploy searches). Reproduced both forms locally against
    linuxdeploy continuous + the pinned script: path fails with the
    exact CI message, `gtk` runs all five plugin stages and produces
    a working 108 MB AppImage.
    Follow-on: once the plugin actually runs it needs
    `dpkg-architecture` (multiarch libdir) and `file`, neither of
    which `libgtk-3-dev` pulls in and neither of which is in the base
    image. Without them the step dies on "dpkg-architecture not found"
    (gtk) or "file command is missing but required" (appimage). Fix:
    add `dpkg-dev file` to the build-linux apt line.
  * Windows MSI: five `error WIX0091: Duplicate Directory with
    identifier 'dir_data_...'`, e.g. `dir_data_flutter_assets`
    referenced from line 40. Root cause in
    `generate_wix_files.py:collect()`: `rel` is always posix, but the
    parent was computed with `str(Path(rel).parent)`. On the Windows
    runner `Path` is `WindowsPath`, so that returns
    `data\flutter_assets`. The backslash string went into the
    directory set, where `build_tree` splits on `/` and finds one node
    literally named `data\flutter_assets`; `make_id` maps `\` to `_`,
    producing `dir_data_flutter_assets` — the same id as the real
    nested `data/flutter_assets`. Fix: `rel.rpartition("/")[0]`, no
    pathlib flavour involved. Emulating `PureWindowsPath` reproduced
    exactly the five CI ids. New `tools/test_wix_files.py` pins this
    (fails 3/5 on the old code, passes on the new).
  * Verified end to end: the workflow's `Build AppImage` script run
    verbatim in ubuntu:24.04 with only the packaged deps produces
    `dist/pdm-0.1.0-linux-x64.AppImage`, and the extracted AppImage
    contains the gtk apprun hook, compiled GLib schemas, typelibs,
    the desktop file and the icon. `wix build` on the regenerated
    Files.wxs reports zero WIX0091.

- 2026-11-13 ~10:30 (sixth run, build-linux): `--plugin gtk`, the WiX
  ids and Windows were all fine; Linux died inside the gtk plugin.
  * Linux AppImage: `cp: cannot stat 'gdk-pixbuf-2.0/2.10.0'` right
    after the plugin's "Installing GDK PixBufs" stage.
    `get_pkgconf_variable gdk_pixbuf_binarydir gdk-pixbuf-2.0` returns
    `/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0`, and
    `copy_lib_tree` does `pushd` into it before copying. On Ubuntu
    26.04 (`ubuntu-latest` now resolves there) no package in the
    workflow's apt set creates that directory: `libgdk-pixbuf-2.0-0`
    ships only the query tool, `libgdk-pixbuf2.0-bin` only man pages
    and the csource/pixdata tools. The one package that puts a loader
    in `2.10.0/loaders` is `librsvg2-common`, and it arrives as a
    *Recommends* of the pixbuf runtime, which the runner's apt has
    disabled. Reproduced the exact failure in an ubuntu:26.04
    container with `--no-install-recommends` (exit 1 at the same
    line) and the success with `librsvg2-common` added (exit 0,
    pixbuf cache written). Fix: add `librsvg2-common` to the
    build-linux apt line; the app also needs it at runtime for the
    SVG icons.
  * Not a CI issue, done while this run was in flight: whole-workspace
    dependency bump (`flutter pub get` no longer prints the 41
    outdated packages) and, because `file_picker` 13 cannot share
    `cross_file ^0.4.0` with `desktop_drop` 0.9, the drop zone moved
    into the runners — `linux/runner/drop_target.cc` (GTK
    `gtk_drag_dest_*`) and `windows/runner/drop_target.cpp` (OLE
    `IDropTarget`), both driving the `pdm/drop_target` method channel
    from `apps/desktop/lib/core/services/drop_target_channel.dart`.
    Windows builds must be confirmed in CI: the runner code cannot be
    compiled on this Fedora machine.

- 2026-11-13 ~11:00 (seventh run): both build jobs were cancelled
  while stuck in `Fetch external tools`.
  * Evidence: build-windows fetched its two binaries (105 MB + 23 MB)
    and was cancelled a minute later, so the fetch itself works from
    GitHub-hosted runners. build-linux logged "Downloading
    https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz",
    showed 0% for 1:56 and was cancelled by hand. Root cause: the
    Linux ffmpeg did not come from GitHub, and johnvansickle.com stalls
    from CI egress; nothing timed out, so the job hung instead of
    failing.
  * Fix in `tools/fetch_external_tools.sh`: both ffmpeg builds are
    now the GitHub release assets `eugeneware/ffmpeg-static` republishes
    at a pinned tag (`b6.1.1`): `ffmpeg-linux-x64.gz` (29 MB, the
    johnvansickle 7.0.2 static build) and `ffmpeg-win32-x64.gz` (30 MB,
    gyan.dev's 6.1.1 essentials build). Their sha256 digests are
    pinned in the script, so both platforms follow one code path and
    neither depends on a non-GitHub host.
    github.com assets are fetched through public mirrors
    (`ghfast.top`, then `gh-proxy.com`) with github.com itself as the
    last candidate, so anonymous-download throttling cannot stall the
    job. Every asset is verified: the ffmpeg digest is pinned in the
    script, yt-dlp against the release's `SHA2-256SUMS` --
    checksums themselves are fetched from GitHub directly first, so a
    mirror is never the only source for the digest it is checked
    against. A
    mismatch moves on to the next candidate instead of installing.
    `--connect-timeout 20 --max-time 1800
    --speed-limit 10240 --speed-time 60` turn a stalled transfer (the
    exact failure mode here) into a fast, retried failure.
  * Verified locally in scratch trees: `linux` produced a working
    ffmpeg (7.0.2, renders a test frame) and yt-dlp (2026.10.26) in
    19 s; `windows` produced a PE32+ ffmpeg.exe (82 MB) and
    yt-dlp.exe (23 MB) in 7 s. pytest `tools/` covers the mirror
    order, the fallback to the next mirror and the checksum-mismatch
    rejection.
