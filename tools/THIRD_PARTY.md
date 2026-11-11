# Third-party tools bundled with PDM

PDM bundles two external command-line tools so it can download HLS
(.m3u8) and DASH (.mpd) streams. They are **not committed to git**;
fetch them with `tools/fetch_external_tools.sh` before building. The
script records each binary's version in a `<name>.version` file next
to it.

## ffmpeg

- **What it does:** merges the separate video/audio streams yt-dlp
  downloads into one file, and remuxes containers.
- **License:** GPL (v2 or later, depending on the build). The static
  builds used here are GPL-licensed; distributing the PDM bundle
  therefore distributes GPL code. See https://ffmpeg.org/legal.html.
- **Linux x64:** static build from
  https://johnvansickle.com/ffmpeg/ (`ffmpeg-release-amd64-static.tar.xz`).
- **Windows x64:** essentials build from https://www.gyan.dev/ffmpeg/builds/
  (`ffmpeg-release-essentials.zip`).

## yt-dlp

- **What it does:** extracts the real media URLs from HLS/DASH
  playlists and downloads the segments, then hands the merge to
  ffmpeg.
- **License:** The Unlicense (public domain).
- **Source:** GitHub releases, https://github.com/yt-dlp/yt-dlp
  (`yt-dlp_linux` / `yt-dlp.exe` standalone binaries).
