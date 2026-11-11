# Plan: Extension — chặn download, bắt media, tự mở app

Ngày: 2026-11-11. Phạm vi do Tuấn Anh chốt: chuột phải đã có; chặn TẤT CẢ
download của trình duyệt; bắt + list media video và audio trên trang (không
ảnh); tự mở app khi chưa chạy; làm Chrome + Firefox cùng lúc. Không làm:
Windows Named Pipe, tiến độ realtime, pause/resume/cancel từ ext, history,
các hardening Phase 0/2 trong doc kiến trúc.

## Part A — Chặn download tự động

Files:
- `integrations/browser-extension/extension/manifest.json`
- `integrations/browser-extension/extension/background.js`
- `integrations/browser-extension/extension/test/background.test.js`

Work:
- Manifest: thêm quyền `downloads`.
- background.js: `chrome.downloads.onCreated` → chỉ http/https (bỏ qua
  blob:, data:, chrome:, about:, file: vì PDM không tải được blob/data),
  lấy tên file từ `downloadItem.filename` (basename) nếu có, không thì từ
  URL. Hủy ngay download của trình duyệt (`cancel` + `erase` khỏi kệ),
  rồi gửi `download.create` sang PDM bằng đường native host hiện có
  (dùng chung helper với context menu). Lỗi thì hiện notification như
  context menu.
- Công tắc chặn: lưu `chrome.storage.local` key `pdmIntercept`, mặc định
  BẬT. background cache giá trị lúc khởi động, cập nhật qua
  `storage.onChanged`. Tắt thì onCreated không làm gì.
- Guard khi `chrome.downloads` không tồn tại.

Verification:
- `node --test` trong `extension/`: onCreated http → cancel + erase +
  post download.create; blob: → không làm gì; tắt công tắc → không làm
  gì; reply lỗi → notification lỗi; tên file từ filename basename.

Done: chặn được download http/https trên Chrome, không chặn blob, công tắc
hoạt động, test xanh.

## Part B — Bắt + list media video/audio

Files:
- `integrations/browser-extension/extension/content.js` (mới)
- `integrations/browser-extension/extension/popup.html` (mới)
- `integrations/browser-extension/extension/popup.js` (mới)
- `integrations/browser-extension/extension/background.js`
- `integrations/browser-extension/extension/manifest.json`
- `integrations/browser-extension/extension/test/content.test.js` (mới)
- `integrations/browser-extension/extension/test/background.test.js`

Work:
- content.js: quét `<video>`/`<audio>` (attr `src` + con `<source src>`),
  và `<a href>` có đuôi media (video: mp4, webm, mkv, mov, avi, m4v, mpg,
  mpeg, 3gp; audio: mp3, flac, wav, ogg, m4a, aac, wma, opus). Resolve
  URL tương đối thành tuyệt đối, dedup theo URL. MutationObserver quét
  lại khi DOM đổi (debounce). Gửi `{type:'media.found', items}` về
  background qua `runtime.sendMessage`. Export `collectMedia(doc)`,
  `isMediaUrl`, `mediaType` cho test.
- background.js: map media theo tabId (nhận `media.found`, xóa khi tab
  đóng `tabs.onRemoved`, xóa khi tab điều hướng `tabs.onUpdated`).
  Trả `media.list` cho popup, nhận `media.download` → gửi
  `download.create` qua native host. Nhận `intercept.get/set` cho công
  tắc.
- popup.html/popup.js: mở lên hỏi background media của tab đang active,
  liệt kê từng dòng (tên file + badge video/audio + nút Download), trạng
  thái rỗng khi không có media, công tắc chặn download.
- Manifest: `content_scripts` matches `<all_urls>` (content.js,
  run_at document_idle), `host_permissions` `<all_urls>`, `action`
  `default_popup` popup.html.

Verification:
- `node --test`: content.test.js — quét video/audio/source/link media,
  bỏ qua ảnh và link thường, dedup, resolve URL tương đối; background
  test — media.found lưu theo tab, media.list trả đúng tab, media.download
  post download.create, công tắc get/set.

Done: mở trang có video/audio → popup liệt kê đúng URL, bấm Download
tạo download trong PDM; không liệt kê ảnh.

## Part C — Tự mở app khi chưa chạy

Files:
- `integrations/browser-extension/host/lib/src/app_launcher.dart` (mới)
- `integrations/browser-extension/host/bin/native_host.dart`
- `integrations/browser-extension/host/lib/src/native_host.dart`
- `integrations/browser-extension/host/test/native_host_test.dart`
- `integrations/browser-extension/host/test/app_launcher_test.dart` (mới)
- `integrations/browser-extension/install.sh`

Work:
- app_launcher.dart (Linux): `resolveAppPath()` đọc
  `~/.local/share/applications/com.ponta.pdm.desktop`, parse dòng
  `Exec=` (bỏ quote và `%u`), trả đường dẫn binary. Fallback env
  `PDM_APP_PATH`. `waitForApp(timeout ~15s)` poll token file + socket
  tới khi xuất hiện.
- bin/native_host.dart: clientFactory khi đọc token/connect thất bại
  (app chưa chạy) → resolve app path → `Process.start` detached →
  `waitForApp` → connect lại. Chỉ thử launch một lần mỗi process.
- native_host.dart: `_handle` bắt cả lỗi không phải DownloadError để
  trả error reply thay vì crash (token file missing là FileSystemException).
- install.sh: xóa dòng stale `dart run bin/engine.dart serve`, ghi chú
  app tự mở khi cần.

Verification:
- `dart test` trong `host/`: factory lỗi + launcher thành công → tạo
  được download; launcher thất bại/timeout → trả error; chỉ launch một
  lần; resolveAppPath parse đúng Exec= (cả dạng có quote và %u).
- Manual: tắt app, bấm chuột phải Download with PDM → app tự mở và
  download được tạo.

Done: app chưa chạy vẫn tạo được download qua ext (app tự mở), lỗi
launch trả về rõ ràng, test xanh.

## Gates chung
- `node --test` trong `extension/` (background + content).
- `dart test` trong `host/`.
- `dart analyze` host.
- Commit từng part lên main + push (không có `;` trong message).
