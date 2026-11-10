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
   extension id shown on its card.
3. Run `./install.sh <chrome-extension-id>`. It builds the native
   host to `~/.local/bin/pdm-native-host` and registers it for
   Chrome (with your id) and Firefox (id `pdm@ponta.dev`, fixed in
   the extension manifest).
4. Right-click a link → **Download with PDM**. A notification
   confirms the download was added, or reports the error.

## Known limitations

- No download interception: the extension only acts on an explicit
  context-menu click; it never takes over the browser's own
  downloads.
- No cookies, request headers, or referrer are sent to the engine.
- The file name comes from the URL (or the link target); a server
  `Content-Disposition` filename does not rename the file, because
  the destination is fixed before the engine probes the URL.
- The desktop app must be running. When it is not, the
  extension reports "Engine is not running".
- The icon is a generated placeholder; proper icons are a
  follow-up.
