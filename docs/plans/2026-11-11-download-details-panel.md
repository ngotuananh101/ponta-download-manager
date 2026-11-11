# Download details panel (FDM-style)

Status: planned 2026-11-11, approved by Tuấn Anh ("Làm đủ cả 3 tab luôn").
Reference: his three FDM screenshots (GENERAL / PROGRESS / CONNECTIONS).

## Goal

The file name at the bottom-right of the status bar becomes a button.
Clicking it toggles a details panel below the table/drop zone (above the
status bar), showing the selected download. The panel has three tabs,
like FDM: GENERAL, PROGRESS, CONNECTIONS, with an X to close it.

## Tabs and data

### GENERAL
- File icon + name, path (destination directory) with a copy button.
- Progress bar + %.
- Downloaded: X / Y, Added at (createdAt), Priority, File URL (link).
- Data: all from `Download` except Priority. Priority lives in the
  engine record (default 0) but is not exposed in `DownloadInfo`.
  Label mapping: >0 high, 0 normal, <0 low (queue order: higher first).

### PROGRESS
- Segment bitmap: a grid of small squares. Blue = downloaded, dark =
  not yet. Each cell covers an equal slice of the file.
- Data: per-segment progress. `DownloadTask.segments` (live,
  `List<SegmentProgress>`) and `DownloadStore.getSegments` (checkpointed,
  `List<SegmentRecord>`) both carry `{segmentId, start, end, downloaded}`.
  The engine must expose them; the API has no segment type yet.

### CONNECTIONS
- A small table: Host, Port, Connection count.
- Host/Port come from the URL (`Uri.host`, `Uri.port` which defaults to
  443 for https / 80 for http). Connection count = number of segments
  from the same segment data (1 for a single-stream / yt-dlp download).

## Parts

### Part 1 — download_api
- `DownloadInfo` gains `priority` (`@Default(0) int`). Regenerate freezed.
- New freezed model `DownloadSegment` (`segmentId`, `start`, `end?`,
  `downloaded` default 0) with JSON support.
- `DownloadEngine` gains `Future<List<DownloadSegment>> getSegments(id)`.
- Update every hand-written `FakeEngine` / test double (download_ipc
  test_helpers, host integration test, desktop engine_ipc_host test,
  api tests) or its test file fails to load.

### Part 2 — engine (PdmEngine)
- Fill `priority` in `_infoFromRecord` from `record.priority`.
- Implement `getSegments(id)`:
  - yt-dlp record: one synthetic segment `[0, total)` with
    `downloadedBytes` (yt-dlp has no segments).
  - Native record: live segments from the scheduler when the download
    is running/paused there, else checkpointed segments from the store.
    Needs a scheduler accessor for a held task's live segments
    (e.g. `liveSegments(id)` reading `_running` / `_pausedRunning`).
  - Empty when the download has no segments yet (queued).

### Part 3 — IPC (download_ipc)
- Carry `priority` in `downloadInfoToJson` / `downloadInfoFromJson`.
- New method `download.segments` (server dispatches to
  `engine.getSegments`, client method `getSegments`), with
  `downloadSegmentToJson` / `downloadSegmentFromJson` in protocol.dart.

### Part 4 — desktop entity / datasource
- `Download` entity gains `priority` (default 0); mapper carries it.
- `EngineDownloadDatasource` (and the repository) expose `getSegments`.

### Part 5 — UI (downloads_screen)
- Status bar file name becomes a button (TextButton, xs, right-aligned,
  no padding/minimum size) that toggles the details panel.
- Details panel widget below the table/drop zone, above the status bar,
  with a tab bar (GENERAL / PROGRESS / CONNECTIONS) and an X.
- GENERAL: as above. PROGRESS: bitmap grid from segments (cell = equal
  slice; blue when its start byte is inside a downloaded range).
  CONNECTIONS: Host / Port / connection count table.
- The panel refreshes segments while open (poll ~500ms) and on tab
  switch; it follows the selected download.

## Verification
- Per part: the owning package's `dart test` + `flutter analyze`
  (desktop), plus the new tests for that part.
- Full gates before each commit: desktop `flutter test` + analyze,
  engine `dart test`, ipc `dart test`, api `dart test`.
- Manual (Tuấn Anh): re-run the app, select a download, click the
  status bar name, check all three tabs; check the bitmap fills as a
  download progresses.

## Out of scope
- Changing priority from the panel (no priority control UI).
- Download Details as a separate window or route (it is a panel).
- Segment data in the progress events (the panel polls instead).
