# Third-party tools bundled with PDM

PDM bundles three external command-line tools: ffmpeg and yt-dlp for
downloading HLS (.m3u8) and DASH (.mpd) streams and for extracting
video sites, and quickjs as the JavaScript runtime yt-dlp needs for
YouTube. They are **not committed to git**; fetch them with
`tools/fetch_external_tools.sh` before building. The script records
each binary's version in a `<name>.version` file next to it.

## ffmpeg

- **What it does:** merges the separate video/audio streams yt-dlp
  downloads into one file, and remuxes containers.
- **License:** GPL (v2 or later, depending on the build). The static
  builds used here are GPL-licensed; distributing the PDM bundle
  therefore distributes GPL code. See https://ffmpeg.org/legal.html.
- **Linux x64:** static build 7.0.2 from https://johnvansickle.com/ffmpeg/.
- **Windows x64:** essentials build 6.1.1 from https://www.gyan.dev/ffmpeg/builds/.

  Both are fetched from the GitHub release assets that
  https://github.com/eugeneware/ffmpeg-static republishes
  (`ffmpeg-linux-x64.gz`, `ffmpeg-win32-x64.gz`, release `b6.1.1`):
  the original hosts are slow to unreachable from CI (johnvansickle.com
  stalls outright), and a pinned tag keeps the build reproducible. The
  fetch script pins each asset's SHA-256, so a bump means updating the
  URL and the digest together.

## yt-dlp

- **What it does:** extracts the real media URLs from HLS/DASH
  playlists and downloads the segments, then hands the merge to
  ffmpeg.
- **License:** The Unlicense (public domain).
- **Source:** GitHub releases, https://github.com/yt-dlp/yt-dlp
  (`yt-dlp_linux` / `yt-dlp.exe` standalone binaries). The fetch
  script verifies each against the release's `SHA2-256SUMS`.

## quickjs (quickjs-ng)

- **What it does:** the JavaScript runtime yt-dlp uses to solve
  YouTube's player challenges. Without it yt-dlp cannot produce most
  YouTube formats and fails with "Requested format is not available".
  yt-dlp looks the binary up by the exact name `qjs` (`qjs.exe` on
  Windows) when given `--js-runtimes quickjs:<dir>`.
- **License:** MIT.
- **Source:** GitHub releases, https://github.com/quickjs-ng/quickjs,
  tag `v0.18.0` (`qjs-linux-x86_64` / `qjs-windows-x86_64.exe`). Both
  are bare executables (no archive), and the fetch script pins each
  asset's SHA-256.
- **Optional at runtime:** PDM still downloads HLS/DASH and other
  sites when qjs is missing; only YouTube extraction degrades.

## Mirrors

Anonymous GitHub downloads from CI runners are throttled and can
stall indefinitely, so `fetch_external_tools.sh` fetches github.com
assets through public mirrors (`ghfast.top`, then `gh-proxy.com`)
and falls back to github.com itself. Mirrors are third parties, so
every asset is checked against a pinned or published SHA-256 before
it is installed; a mirror that alters or truncates a file is
skipped rather than trusted.
