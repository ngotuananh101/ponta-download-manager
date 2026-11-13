# Browser extension

Send a download from the browser to the PDM engine: right-click a
link (or an image, video, audio) and choose **Download with PDM**.
The extension forwards the URL to the native host, which creates
the download in the running engine over IPC.

## Setup (Linux)

1. Start the desktop app (`flutter run -d linux` from
   `apps/desktop`, or the built `bundle/pdm`). The engine runs
   inside the app now, and the app hosts the IPC server the
   native host talks to.
2. Load the unpacked extension in Chrome: `chrome://extensions` →
   Developer mode → Load unpacked → pick `extension/`. Copy the
   extension id shown on its card. (Firefox: `about:debugging` →
   This Firefox → Load Temporary Add-on → pick `extension/manifest.json`.)
3. Run `./install.sh <chrome-extension-id>`. It builds the native
   host to `~/.local/bin/pdm-native-host` and registers it for
   Chrome (with your id) and Firefox (id `pdm@ponta.dev`, fixed in
   the extension manifest).
4. Right-click a link → **Download with PDM**. A notification
   confirms the download was added, or reports the error.

## Behaviour

- Download interception is on by default (toggle in the popup): every
  http(s) browser download is paused, cancelled in the browser, and
  sent to PDM instead. `blob:` and `data:` downloads stay in the
  browser.
- The popup lists the video/audio the content script found on the
  active tab (including `.m3u8`/`.mpd` streams); each row has a
  Download button.
- Opening the popup also probes the active tab with yt-dlp: if the
  site is supported, the popup lists the video's formats (resolution,
  size, video-only/audio-only markers) and the chosen one downloads
  through yt-dlp. The probe runs only when the popup opens, never on
  page load.
- The desktop app is auto-launched when needed: the native host
  starts it and waits up to 15 s for the IPC endpoint. Only when it
  cannot be started does the extension report "Engine is not running".

## Known limitations

- Cookies and the referrer are sent with every download the extension hands over — the cookies the browser would send for that URL, plus the page the download came from — so login-walled links work. They live in memory only: after an app restart they are gone, and a login-walled download must be re-added from the browser. Cookies and the referrer are also passed to yt-dlp for the probe and the download (via a temporary Netscape-format file that is deleted right after use), so login-walled pages probe as supported. The chosen format id is in-memory only too: after a restart, a resumed yt-dlp download falls back to yt-dlp's default format. Other request headers are still not sent.
- The file name comes from the URL (or the link target); a server
  `Content-Disposition` filename does not rename the file, because
  the destination is fixed before the engine probes the URL.
