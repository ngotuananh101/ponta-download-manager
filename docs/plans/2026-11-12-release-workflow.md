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
