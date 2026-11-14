# Browser extension

Send a download from the browser to the PDM engine: right-click a
link (or an image, video, audio) and choose **Download with PDM**.
The extension forwards the URL to the native host, which creates
the download in the running engine over IPC.

## Release setup (Linux and Windows)

Release bundles include `bin/pdm-native-host[.exe]` and the unpacked
`extension/` folder. Start PDM once under your own desktop account: it
registers `com.ponta.pdm` for detected browser installations. Native host
registration needs no terminal commands or extension-id copying, and is
retried on every app launch for newly installed browsers or a moved app.

- **Linux Chromium browsers:** enable **Developer mode** in the browser once.
  PDM can then add the unpacked extension to existing profiles while the
  browser is closed. If it is running, quit it fully and choose
  **Menu → Browser integration → Check again**, then reopen it.
  PDM never enables Developer mode or re-enables an extension you or the
  browser disabled. This uses Chromium's profile format, not a stable browser
  installation API; browser updates or enterprise policies may require
  **Load unpacked**. AppImages stage the host and extension under
  `$XDG_DATA_HOME/pdm/browser-integration/` (default
  `~/.local/share/pdm/browser-integration/`) so paths survive the mount closing.
- **Windows Chromium browsers:** open `chrome://extensions` (or
  `edge://extensions`), enable **Developer mode**, choose **Load unpacked**,
  and select `extension/` next to `pdm.exe`. This browser-controlled step
  remains manual; PDM does not tamper with authenticated browser preferences
  or force enterprise policies on a personal browser.
- **Firefox:** the native host is registered, but a permanent extension
  installation needs a Mozilla-signed add-on. No signed release is published
  yet. Temporary loading via `about:debugging` is for development only.

Check **Menu → Browser integration** for status and retry instructions.
Standard browser profile locations are detected; custom `--user-data-dir`,
Snap/Flatpak browser sandboxes and policy-managed installations are not
supported automatically.

## Source checkout setup (Linux)

1. From the repository root, run `flutter pub get` and
   `bash tools/build_native_host.sh linux`, then build the app with
   `flutter build linux --release` from `apps/desktop`.
2. Start the release bundle to use automatic registration and setup above.
   Debug builds do not register a native host pointing at a disposable build.
3. For development with `flutter run`, load
   `integrations/browser-extension/extension/` through **Load unpacked**,
   then run `bash integrations/browser-extension/install.sh` to compile
   the host to `~/.local/bin/pdm-native-host` and register detected browsers.
   Alternatively, use `install.sh --host /absolute/path/to/pdm-native-host`
   to register an existing executable. The pinned Chrome id is
   `hiojpajnfchdajfiegibmklalpgndono`; Firefox's id is `pdm@ponta.dev`.
4. Right-click a link → **Download with PDM**. A notification confirms
   the download was added or reports the error.

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
