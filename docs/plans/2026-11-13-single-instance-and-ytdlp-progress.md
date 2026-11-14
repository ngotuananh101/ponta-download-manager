# Single instance + yt-dlp run progress + one popup list

Status: DONE
Date: 2026-11-13

## Context

Three reports from Tuấn Anh:

1. A download's row does not appear right after pressing Download;
   restarting the app makes it show.
2. The extension popup shows the yt-dlp formats and the media scanned
   from the page as two separate lists.
3. A yt-dlp download never completes: it reaches 100% and then
   downloads again.

## Root causes

- P1: the runner registered the application with
  `G_APPLICATION_NON_UNIQUE`, so every launch started a full second
  instance with its own engine over the same database and IPC socket.
  The browser extension's download went to whichever instance won the
  socket, while the visible window belonged to the other one — its row
  only appeared after a restart, when a single instance reloaded the
  database. Two instances also made P3 worse: each recovered the same
  non-terminal yt-dlp records and started its own run for them.
- P2: the popup rendered yt-dlp formats into `#probe-formats` and page
  media into `#list`, each with its own empty state.
- P3: yt-dlp downloads a `<video>+bestaudio` pick as two passes, each
  printing its own 0→100% from the default `[download]` lines. The row
  folded those raw percents straight into one download, so it hit 100%
  after the video stream and then dropped back to 0% for the audio
  stream. A second cause: `retryDownload` on a still-running record
  handed the same output to a second yt-dlp process.

## Decision

- P1: one instance per user session, native, at the runner:
  - Linux: GApplication's unique mode (`G_APPLICATION_DEFAULT_FLAGS`).
    A second launch becomes remote, forwards `activate` over D-Bus and
    exits; `activate` presents the existing window instead of creating
    a second one (close-to-tray only hides it). `--minimized` forwards
    nothing, so an autostart at login cannot pop the window up. The GTK
    application id becomes `com.ponta.pdm` so it matches the installed
    `.desktop` file and cannot collide with another template app.
  - Windows: a `Local\com.ponta.pdm.single-instance` named mutex; a
    launch that finds it held shows/restores the running window (found
    by an app-specific window class name) and exits. The window class
    is renamed from the Flutter template default for the same reason.
- P2: one unified list — yt-dlp formats on top, page media below, one
  empty state that appears only after both sources answered.
- P3: stream-aware progress. The downloader asks yt-dlp for a
  machine-readable line per update carrying the stream's format id
  (`--progress-template`) and for the run's stream plan printed before
  the first transfer (`--print before_dl:`). A tracker folds the
  streams into one run: bytes of the finished streams plus the current
  one, sized from the bytes actually transferred (the plan's
  `filesize` is only an estimate — a real 5 MB entry transferred
  2.7 MB), with the plan supplying the streams not started yet.
  Plus: one live yt-dlp run per record — `_startYtDlp` and
  `retryDownload` are no-ops while the record already has a live run.

## Verification

- P1, Linux, real binary: three relaunches → one process, one window;
  with the window hidden (close-to-tray), a relaunch presents it; a
  `--minimized` relaunch leaves it hidden. `WM_CLASS` is
  `com.ponta.pdm`.
- P1, Windows: code only (no Windows host here); the mutex and
  `FindWindow` path follow the same one-instance rule.
- P2: extension `node --test` 78/78.
- P3: download_external 66/66 (incl. a fixture captured from the
  bundled yt-dlp 2026.10.26 downloading a real two-stream pick through
  the package's flags: video 0→73% of the run, audio 73→100%, never
  backwards), engine 114/114 (two-stream run through `engine.events`,
  and "retrying a running download does not spawn a second yt-dlp").
- Gates: `flutter analyze` clean, `dart analyze` clean for engine and
  download_external, desktop 275/275, engine 114/114, every package
  suite green, extension host 47/47.

Notes:
- Windows `Local\` mutex means one instance per session, not per
  machine: a second user session gets its own instance, which is the
  intent (separate databases, separate trays).
