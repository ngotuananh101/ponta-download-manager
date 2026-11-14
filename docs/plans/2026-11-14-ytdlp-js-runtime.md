# yt-dlp JavaScript runtime — bundle quickjs and enable node/bun

Status: DONE
Date: 2026-11-14

## Context

The popup failed on a YouTube video (`LftM_19IToM`) with:

```
ERROR: [youtube] LftM_19IToM: Requested format is not available.
Use --list-formats for a list of available formats
```

The same string had been seen before and was fixed once as a cookie
problem (`2026-11-13-ytdlp-cookie-fallback.md`). It was not a cookie
problem this time:

- The failure reproduces with anonymous cookies and with a
  login-shaped cookie file, and it goes away for other videos, so
  cookies are not the trigger.
- `yt-dlp 2026.10.26` (the bundled binary) ships the `yt_dlp_ejs`
  0.8.0 challenge-solver scripts but has **no JavaScript runtime of
  its own**; only `deno` is enabled by default, and the machine has no
  deno. Node and bun are installed but not enabled.
- Without a runtime the `web` client cannot solve the player's `n`
  challenge: extraction degrades to the image formats, and the format
  selector then fails with exactly the pasted error. Other clients
  fail earlier with `Sign in to confirm you're not a bot`.
- Measured impact: 19 of 20 sampled YouTube videos failed.

## Discovery (verified on the real binaries)

- Supported runtimes, highest priority first: `deno`, `node`,
  `quickjs`, `bun`. `--js-runtimes RUNTIME[:PATH]`, repeatable;
  `--no-js-runtimes` clears the defaults.
- The `PATH` part of `quickjs:<path>` may be the binary itself or its
  directory, and keeps a Windows drive letter (`split(':', 1)`).
- The binary must be named exactly `qjs` (`qjs.exe`). yt-dlp runs
  `<qjs> --script <file.js>` and reads the version from the tool.
- quickjs-ng v0.18.0 publishes bare executables (no archive), so the
  fetch script keeps its `curl` + `gzip`-only dependency set.
  `qjs --version` prints `0.18.0` and exits 0.
- A runtime that is enabled but unusable (old node, broken deno) is
  skipped with `(unsupported)` and yt-dlp falls through to the next
  one, so listing several is safe. A runtime that is simply missing
  only produces a warning; the run still exits 0.
- An **unknown option** makes yt-dlp exit 2, which would break every
  probe and download. `--version` still exits 0 on an unknown option,
  so only `--help` can tell whether a yt-dlp supports the flag.

## Decisions

- Bundle quickjs-ng v0.18.0 as `bin/qjs` / `bin/qjs.exe`, and also
  enable `node` and `bun`. quickjs guarantees the runtime exists on a
  machine with nothing installed; node and bun let a user who has them
  skip the slower quickjs. A machine with no runtime at all still
  works exactly as before the change (HLS/DASH, other sites).
- quickjs is optional in `ExternalTools`: it does **not** take part in
  `available`, so `.m3u8`/`.mpd` downloads and every existing test
  keep working when only ffmpeg and yt-dlp are present.
- The fingerprint check (`--help` contains `--js-runtimes`) runs only
  for a yt-dlp found on `PATH`. The bundled release is known to
  support the flag, and a ~0.5 s `--help` per resolve would be paid on
  every app start.
- The probe and the download share the same runtime list: the chosen
  format's signature still has to be solved after the probe.

## Changes

- `tools/fetch_external_tools.sh` — pinned `QJS_TAG`/URLs/SHA-256,
  installs `qjs` (Linux, version-checked) and `qjs.exe` (Windows,
  content-checked); `tools/THIRD_PARTY.md` and the README mention it.
- `packages/download_external/lib/src/external_tools.dart` —
  `qjsPath` / `qjsAvailable`, `ytDlpSupportsJsRuntimes`, and
  `ytDlpJsRuntimeArgs` (`quickjs:<path>`, `node`, `bun`).
- `packages/download_external/lib/src/yt_dlp_downloader.dart` —
  `jsRuntimes` on the downloader, emitted as repeated `--js-runtimes`
  pairs in both the probe argv (after `-J`, so the fake yt-dlp scripts
  in the engine tests still branch on `$1`) and the download argv.
- `apps/engine/lib/src/pdm_engine.dart` — passes
  `tools.ytDlpJsRuntimeArgs` to the downloader.
- `integrations/browser-extension/extension/popup_probe.js` —
  `probeErrorMessage` maps the two YouTube failures to actionable
  copy; any other error is still shown verbatim.

## Verification

- `packages/download_external`: 78 tests, `dart analyze` clean.
- `apps/engine`: 115 tests, `dart analyze` clean.
- `integrations/browser-extension/extension`: 81 tests (`node --test`).
- `integrations/browser-extension/host`: 47 tests.
- `apps/desktop`: `flutter analyze` clean.
- `tools/test_shell_scripts.py`: 7 tests (pytest installed in a temp
  venv — this machine's system Python has no pytest).
- Real binaries: `ExternalTools.resolve()` against
  `apps/desktop/bundle` resolves all three tools and yields
  `['quickjs:.../bin/qjs', 'node', 'bun']`; a probe through
  `YtDlpDownloader` with those args returns 43 formats for
  `LftM_19IToM` and 49 for `dQw4w9WgXcQ`, where the same probe failed
  before the change.
