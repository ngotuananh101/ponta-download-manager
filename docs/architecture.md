# Download Manager --- Architecture

> **Project:** Desktop download manager inspired by IDM\
> **Target platforms:** Windows and Linux\
> **UI:** Flutter\
> **Download engine:** Dart\
> **Persistence:** SQLite\
> **Architecture principle:** Engine-first, UI-independent,
> performance-oriented

------------------------------------------------------------------------

## 1. Goals and non-goals

### 1.1 Goals

Build a desktop download manager with:

-   Multi-connection HTTP/HTTPS downloads using HTTP Range.
-   Pause, resume, cancel, retry, and crash recovery.
-   Concurrent downloads and priority-based queues.
-   Adaptive per-file connection scheduling and global connection
    limits.
-   Per-task and global bandwidth limiting.
-   Streaming writes with bounded memory usage.
-   Persistent task metadata and reliable recovery.
-   Flutter desktop UI for Windows and Linux.
-   Browser integration through WebExtensions and Native Messaging.
-   A standalone engine process that can later be reused by CLI or other
    frontends.

### 1.2 Non-goals for the initial release

Defer these until the core is stable:

-   Video-site extraction and DRM-related functionality.
-   FTP/SFTP.
-   HTTP/3 and custom transport implementations.
-   Mobile platforms.
-   Cloud synchronization.
-   Complex browser automation.

The engine should be extensible enough to add these later without
changing its core download model.

------------------------------------------------------------------------

## 2. Architectural principles

1.  **Engine-first:** prove download correctness and performance before
    investing heavily in UI.
2.  **UI-independent:** the engine must continue operating without
    Flutter attached.
3.  **Streaming-first:** never load an entire download into memory.
4.  **Bounded concurrency:** every queue, buffer, and connection pool
    must have explicit limits.
5.  **Correctness before speed:** never combine segments from different
    representations of a remote file.
6.  **Recoverability:** persist enough state to resume safely after
    process or machine failure.
7.  **Transport abstraction:** keep HTTP implementation details behind
    interfaces.
8.  **Observable by design:** expose structured events, metrics, and
    diagnostics.
9.  **Portable core:** platform-specific behavior belongs behind
    platform adapters.
10. **Measured optimization:** tune concurrency and buffering using
    repeatable benchmarks, not assumptions.

------------------------------------------------------------------------

## 3. High-level architecture

``` mermaid
flowchart TB
    UI[Flutter Desktop Application]
    IPC[Engine Client / IPC]
    APP[Download Application Layer]
    SCHED[Global Scheduler]
    CORE[Download Core]
    TRANSPORT[HTTP Transport]
    SEG[Segment Manager]
    WRITER[File Writer]
    RECOVERY[Recovery Manager]
    DB[(SQLite)]
    FS[(File System)]
    OS[Windows / Linux Integration]
    EXT[Browser Extension]

    UI <--> IPC
    EXT <--> IPC
    IPC <--> APP
    APP --> SCHED
    SCHED --> CORE
    CORE --> TRANSPORT
    CORE --> SEG
    SEG --> WRITER
    APP <--> RECOVERY
    RECOVERY <--> DB
    APP <--> DB
    WRITER --> FS
    APP <--> OS
```

### 3.1 Logical layers

  -----------------------------------------------------------------------
  Layer                               Responsibilities
  ----------------------------------- -----------------------------------
  Presentation                        Flutter screens, user interaction,
                                      view state

  Application                         Commands, task lifecycle, queue
                                      orchestration, event dispatch

  Scheduling                          Global limits, priorities,
                                      bandwidth allocation

  Download core                       Probing, segments, retries,
                                      pause/resume

  Transport                           HTTP requests, redirects, headers,
                                      streaming responses

  Storage                             File writing, metadata, checkpoints

  Recovery                            Startup reconciliation and safe
                                      resume

  Platform                            Tray, autostart, notifications,
                                      paths, native messaging
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 4. Runtime and process model

### 4.1 Process model

Use a single process, following IDM: the Flutter desktop application
embeds the Dart download engine in-process.

-   **Flutter desktop process:** owns the UI and the engine. The engine
    (`PdmEngine`) runs in the same process, so downloads live and die
    with the app — closing the window hides it to the system tray
    instead of exiting, and the app only ends from the tray menu's Quit.
-   **CLI:** `apps/engine` keeps a thin `download` subcommand for
    headless use; it creates its own in-process engine. There is no
    separate engine daemon and no `serve` subcommand.

The engine must not depend on Flutter packages.

### 4.2 IPC

The desktop app hosts the IPC server itself, so external clients (the
browser extension's native host) talk to the app over the same local
socket protocol. Use a local IPC abstraction: a local socket with
newline-delimited JSON messages. Keep the protocol
transport-independent so it can later use named pipes on Windows or Unix
domain sockets on Linux.

Recommended message categories:

-   `request`: command with request ID.
-   `response`: command result with matching request ID.
-   `event`: asynchronous engine event.
-   `error`: structured error with stable error code.

Example command:

``` json
{
  "type": "request",
  "id": "req-001",
  "method": "download.create",
  "params": {
    "url": "https://example.com/archive.zip",
    "destination": "/downloads/archive.zip"
  }
}
```

Example event:

``` json
{
  "type": "event",
  "event": "download.progress",
  "data": {
    "downloadId": "download-001",
    "downloadedBytes": 52428800,
    "totalBytes": 104857600,
    "bytesPerSecond": 5242880
  }
}
```

IPC requirements:

-   Validate every message and parameter.
-   Use request IDs and deterministic error responses.
-   Authenticate local clients where the platform supports it.
-   Restrict access to the current user.
-   Avoid exposing an unauthenticated network listener.
-   Version the protocol.
-   Support reconnect and state resynchronization.

------------------------------------------------------------------------

## 5. Download engine design

### 5.1 Core modules

  Module                Responsibility
  --------------------- ----------------------------------------------------
  `DownloadManager`     Public orchestration API
  `DownloadTask`        Runtime state of one download
  `DownloadProbe`       Discover size, validators, range support, filename
  `SegmentPlanner`      Divide a representation into byte ranges
  `SegmentWorker`       Fetch and report segment progress
  `ConnectionPool`      Reuse and bound HTTP connections
  `RetryController`     Retry transient failures with backoff
  `FileWriter`          Write chunks to the correct offsets
  `CheckpointManager`   Persist safe progress
  `RecoveryManager`     Reconcile tasks and partial files at startup
  `IntegrityVerifier`   Validate final size and available checksums
  `BandwidthLimiter`    Enforce per-task and global limits
  `GlobalScheduler`     Allocate tasks and connections

### 5.2 HTTP probing

Before parallelizing a download, probe the resource using HEAD where
useful, with a GET/range fallback when HEAD is unsupported or
misleading.

Collect:

-   Final URL after redirects.
-   HTTP status.
-   `Content-Length`, if known.
-   `Accept-Ranges`.
-   `ETag`.
-   `Last-Modified`.
-   `Content-Disposition`.
-   Content type.
-   Authentication and request-header requirements.

Do not assume that `Accept-Ranges: bytes` alone guarantees correct range
behavior. Validate an actual range response before enabling segmented
mode.

### 5.3 Range validation

A valid segment response should normally return:

``` http
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1048575/10485760
```

Validate:

-   Status is `206 Partial Content`.
-   `Content-Range` matches the requested interval.
-   Total representation length is consistent.
-   The body length matches the expected range length.
-   The remote representation has not changed.

If the server ignores Range and returns `200 OK`, do not write that full
response into a segment offset. Fall back to single-stream mode or fail
safely.

### 5.4 Segment planning

For a known file length `L` and `N` segments, plan non-overlapping
inclusive ranges that cover `[0, L-1]`.

Invariants:

-   No gaps.
-   No overlaps.
-   Every segment has a stable ID.
-   Segment boundaries remain stable during a resumable session unless a
    controlled re-plan occurs.
-   A segment is complete only after all its bytes have been written and
    checkpointed safely.

Unknown-length resources should initially use single-stream mode.
Dynamic segmentation can be considered later.

### 5.5 Adaptive concurrency

Provide configurable presets, but treat them as upper bounds rather than
guaranteed optimal values.

  Preset           Initial per-file connection cap
  -------------- ---------------------------------
  Conservative                                   2
  Balanced                                       4
  Aggressive                                     8
  Maximum                                       16
  Custom                                     1--32

The scheduler should consider:

-   Per-connection throughput.
-   Aggregate throughput.
-   Time to first byte and latency.
-   Retry and timeout rates.
-   HTTP `429` and `503` responses.
-   Disk write pressure.
-   Global connection budget.
-   User-configured limits.

Increase concurrency cautiously. Reduce it when additional connections
fail to improve throughput or cause throttling. Never use aggressive
retry loops against a server that is rate-limiting the client.

### 5.6 Global scheduling

Use two scheduling levels:

**Global scheduler**

-   Maximum concurrent downloads.
-   Priority and queue ordering.
-   Global bandwidth budget.
-   Fairness between downloads.

There is no total connection cap: only the per-download connection
limit and the maximum concurrent downloads apply.

**Per-download scheduler**

-   Segment assignment.
-   Per-file connection cap.
-   Segment retry.
-   Progress aggregation.
-   Adaptive concurrency.

Suggested initial defaults (all configurable):

  Setting                          Initial value
  ------------------------------ ---------------
  Concurrent downloads                         4
  Connections per file                         8
  Maximum connections per file                16
  Retry attempts                              10
  Initial retry delay                   1 second
  Maximum retry delay                 60 seconds

These are starting defaults for testing, not universal performance
recommendations.

------------------------------------------------------------------------

## 6. File writing and memory management

### 6.1 Streaming

The engine must stream response chunks directly to storage. Memory use
must be bounded independently of total file size.

Use bounded queues between network readers and storage writers. Apply
backpressure when disk writes cannot keep up with network reads.

### 6.2 Random-access writes

Each segment writes to its assigned offset. Do not let concurrent
workers mutate a shared file handle without a clear synchronization
strategy.

Recommended initial design:

-   A writer coordinator owns file-writing operations.
-   Segment workers submit bounded chunk messages containing segment ID,
    offset, and bytes.
-   The writer validates offsets and writes data.
-   Checkpointing records only bytes confirmed written.
-   Benchmark a single coordinated writer against independent handles
    before choosing a more complex implementation.

A single writer may become a bottleneck on some systems. Do not assume
it is always fastest; measure it.

### 6.3 Partial writes and checkpoints

Track separately:

-   Bytes received from the network.
-   Bytes queued for disk.
-   Bytes confirmed written.
-   Bytes safely checkpointed.

Never report a segment as complete merely because its HTTP response
finished. The bytes must be written and the completion state persisted
in the correct order.

### 6.4 Disk-space and file safety

Before starting:

-   Check available disk space when possible.
-   Create a temporary or partial file safely.
-   Avoid overwriting an existing destination without explicit policy.
-   Use exclusive file creation or collision-safe naming.
-   Clean up temporary files only when ownership is known.

On completion:

1.  Verify total size.
2.  Verify checksum if a trusted checksum is available.
3.  Flush data as required by the durability policy.
4.  Atomically rename the partial file to its final name where
    supported.
5.  Persist the completed state.

------------------------------------------------------------------------

## 7. Pause, resume, retry, and recovery

### 7.1 Task state machine

``` mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Preparing
    Preparing --> Downloading
    Preparing --> Failed
    Downloading --> Paused
    Downloading --> Retrying
    Downloading --> Completed
    Downloading --> Failed
    Retrying --> Downloading
    Retrying --> Failed
    Paused --> Downloading
    Failed --> Retrying
    Completed --> [*]
```

### 7.2 Suggested task states

-   `pending`
-   `preparing`
-   `downloading`
-   `paused`
-   `retrying`
-   `completed`
-   `failed`
-   `cancelled`
-   `verifying`

### 7.3 Retry policy

Use exponential backoff with jitter for transient errors.

Potentially retry:

-   Connection reset.
-   Temporary DNS or network errors.
-   Timeout.
-   HTTP `408`.
-   HTTP `429`, respecting `Retry-After`.
-   Selected `5xx` responses.

Do not blindly retry:

-   Invalid URL.
-   Unsupported protocol.
-   Persistent authorization failure.
-   Invalid range response.
-   Representation validator mismatch.
-   Destination permission errors.

### 7.4 Safe resume

Resume only when the remote representation is sufficiently consistent
with the original download.

Use validators:

-   Prefer strong ETag with conditional range requests (`If-Range`).
-   Use Last-Modified only as a weaker fallback.
-   If the validator changes or the server returns a full response
    instead of the requested range, discard incompatible partial
    progress or restart safely.

On engine startup:

1.  Load non-terminal tasks from SQLite.
2.  Inspect their partial files.
3.  Reconcile persisted and actual file state.
4.  Validate remote representation when resuming.
5.  Requeue recoverable tasks.
6.  Mark unrecoverable tasks with actionable errors.

A crash can occur between writing bytes and committing metadata.
Recovery must therefore be conservative and must never trust metadata
without reconciling it with the partial file.

------------------------------------------------------------------------

## 8. Dart concurrency model

### 8.1 Use async I/O for network concurrency

Dart's asynchronous I/O is appropriate for managing many concurrent HTTP
requests. Do not create one Isolate per connection.

### 8.2 Use Isolates for CPU-bound work

Potential Isolate workloads:

-   Large-file hashing.
-   Compression or decompression.
-   Expensive parsing.
-   Other CPU-heavy processing.

Keep the main engine event loop responsive. Use a small, bounded worker
pool if profiling shows CPU-bound tasks are affecting responsiveness.

### 8.3 Suggested logical runtime

``` text
Engine Process
│
├── Main Engine Isolate
│   ├── Command handling
│   ├── Global scheduler
│   ├── Task lifecycle
│   └── Event aggregation
│
├── Async Network Operations
│   ├── HTTP requests
│   ├── Segment streams
│   └── Retry timers
│
├── Storage Coordinator
│   ├── Bounded write queue
│   ├── Random-access writes
│   └── Checkpoint coordination
│
└── Optional Worker Isolates
    ├── Hashing
    └── CPU-intensive processing
```

This is a logical ownership model. Components may initially run in the
main Isolate if they are non-blocking; split them only when justified by
profiling.

------------------------------------------------------------------------

## 9. Persistence model

Use SQLite for task metadata, settings, and recovery state. A single
database writer or transaction coordinator simplifies consistency.

### 9.1 Suggested tables

**downloads**

  Column               Purpose
  -------------------- -------------------------
  `id`                 Primary key
  `url`                Original URL
  `final_url`          URL after redirects
  `destination_path`   Final destination
  `partial_path`       Temporary file path
  `file_name`          Resolved filename
  `total_bytes`        Total size, nullable
  `downloaded_bytes`   Confirmed written bytes
  `etag`               Remote validator
  `last_modified`      Remote validator
  `supports_range`     Range capability
  `status`             Current state
  `priority`           Scheduling priority
  `created_at`         Creation timestamp
  `updated_at`         Update timestamp

**segments**

  Column            Purpose
  ----------------- -----------------
  `id`              Primary key
  `download_id`     Parent download
  `segment_index`   Stable ordering
  `start_byte`      Inclusive start
  `end_byte`        Inclusive end
  `written_bytes`   Confirmed bytes
  `status`          Segment state
  `updated_at`      Last checkpoint

**download_headers**

Stores only necessary request headers. Treat cookies and authorization
values as secrets; do not store them in plaintext logs or ordinary
diagnostics. Prefer OS credential storage or an encrypted secret store.

**settings**

Stores user preferences and engine defaults.

### 9.2 Persistence rules

-   Use database transactions for related state changes.
-   Batch progress updates to avoid writing to SQLite for every network
    chunk.
-   Persist lifecycle transitions promptly.
-   Persist checkpoints at controlled intervals and on pause/shutdown.
-   Do not claim durability beyond what the file system and flush policy
    provide.
-   Add schema migrations from the beginning.

------------------------------------------------------------------------

## 10. Bandwidth limiting

Implement a token-bucket limiter with two levels:

-   Global limiter: maximum bandwidth for the whole application.
-   Per-download limiter: maximum bandwidth for an individual task.

The scheduler should coordinate both limits so that per-task limits
cannot exceed the global budget.

Requirements:

-   Configurable units (bytes/s, KiB/s, MiB/s).
-   Unlimited mode.
-   Fair allocation between active tasks.
-   Priority-aware allocation.
-   Runtime updates without restarting downloads.

------------------------------------------------------------------------

## 11. Flutter desktop application

### 11.1 Main screens

1.  All Downloads
2.  In Progress
3.  Queue
4.  Completed
5.  Failed
6.  Categories
7.  Scheduler
8.  Statistics
9.  Settings
10. Download Details

### 11.2 Download details

Show:

-   Overall progress and percentage.
-   Current and average speed.
-   Downloaded and total bytes.
-   Estimated remaining time.
-   Per-segment progress.
-   Connection count.
-   Retry history.
-   Destination and source.
-   Pause, resume, retry, cancel, and open-file actions.

### 11.3 UI architecture

Use a feature-oriented Flutter structure. Riverpod is a reasonable
state-management choice. The engine runs in-process: the UI subscribes
to the embedded engine's events and snapshots through a datasource
(`EngineDownloadDatasource`) instead of talking to a separate process
over IPC. The UI still must not own download execution.

Throttle high-frequency progress events before rendering. For example,
aggregate progress updates and publish at a configurable UI refresh
interval rather than rebuilding the widget tree for every received
chunk.

------------------------------------------------------------------------

## 12. Browser integration

Use WebExtensions for Chromium-based browsers and Firefox, with a Native
Messaging host that forwards download requests to the local engine.

``` mermaid
flowchart TD
    B[Browser] --> E[WebExtension]
    E --> N[Native Messaging Host]
    N --> I[Engine IPC]
    I --> S[Download Scheduler]
    S --> D[Download Core]
    D --> F[File System]
    I --> U[Flutter UI]
```

Capture only the information needed for a user-requested download:

-   URL.
-   Suggested filename.
-   Referrer when required.
-   Necessary request headers.
-   Cookies only with appropriate permissions and user consent.

Security requirements:

-   Validate message origin and schema.
-   Restrict native host access to the current user.
-   Never expose the engine on an unauthenticated public interface.
-   Redact credentials and cookies from logs.
-   Provide clear controls for permissions and browser integration.

------------------------------------------------------------------------

## 13. Platform integration

### Windows

-   System tray (via `window_manager` + `nativeapi`; implemented in the
    desktop app, not yet verified on Windows).
-   Startup registration.
-   Installer and updater.
-   Native Messaging host registration.
-   Windows path and file-lock handling.
-   Graceful shutdown: quitting from the tray disposes the in-process
    engine and closes the IPC server.

### Linux

-   System tray where supported by the desktop environment. Implemented:
    closing the window hides the app to the tray (downloads keep running
    in the same process), and the tray menu offers Show, Pause all, and
    Quit. The tray uses `window_manager` 0.6 + `nativeapi` (no
    `tray_manager`); on Linux the menu trigger must be
    `ContextMenuTrigger.clicked`, otherwise GNOME's AppIndicator shows an
    empty menu.
-   XDG autostart (open; the Linux runner already accepts a `--minimized`
    flag for it).
-   Desktop entry and package formats. The app installs its own
    `.desktop` file and 256x256 icon into `~/.local/share` on startup
    (`LinuxDesktopService`).
-   Native Messaging host registration (via `install.sh`).
-   Unix domain sockets: the app hosts the IPC server on a Unix socket
    for the browser extension's native host.
-   Graceful shutdown: quitting from the tray disposes the in-process
    engine and closes the IPC server; a second app instance fails fast
    (single-instance enforcement is still open).

Keep these behind a platform interface so the core engine remains
portable.

------------------------------------------------------------------------

## 14. Repository structure

Use a Dart/Flutter monorepo with clear package boundaries.

``` text
download-manager/
├── apps/
│   ├── desktop/
│   │   ├── lib/
│   │   │   ├── app/
│   │   │   ├── features/
│   │   │   │   ├── downloads/
│   │   │   │   ├── queue/
│   │   │   │   ├── browser/
│   │   │   │   ├── settings/
│   │   │   │   └── statistics/
│   │   │   ├── shared/
│   │   │   └── main.dart
│   │   └── test/
│   └── engine/
│       ├── bin/
│       │   └── engine.dart
│       ├── lib/
│       └── test/
├── packages/
│   ├── download_api/
│   ├── download_core/
│   ├── download_scheduler/
│   ├── download_transport/
│   ├── download_storage/
│   ├── download_recovery/
│   ├── download_limiter/
│   ├── download_integrity/
│   ├── download_ipc/
│   └── download_external/
├── integrations/
│   └── browser-extension/
│       ├── chromium/
│       └── firefox/
├── test/
│   ├── integration/
│   ├── stress/
│   └── benchmark/
├── docs/
│   ├── architecture.md
│   ├── engine-api.md
│   └── ipc-protocol.md
├── pubspec.yaml
└── README.md
```

Each package should expose a small public API and keep implementation
details private. Avoid circular package dependencies.

`apps/engine` is a plain Dart package (no Flutter dependency): the
desktop app imports `PdmEngine` from it and runs the engine in-process.
Its `bin/engine.dart` is only a CLI (`download` subcommand) for headless
use; there is no engine daemon. The SQLite store lives inside
`download_recovery` as a thin repository; there is no separate
`download_database` package.

------------------------------------------------------------------------

## 15. Proposed technology stack

  Area               Choice
  ------------------ -------------------------------------------
  Desktop UI         Flutter
  Language/runtime   Dart SDK
  HTTP transport     `dart:io` `HttpClient` initially
  Database           SQLite
  Database access    Drift or a thin repository layer
  Serialization      `json_serializable`
  Immutable models   Freezed, if useful
  UI state           Riverpod
  File paths         `path`
  Logging            `logging` or structured logger
  IPC                Local socket with versioned JSON protocol
  Browser            WebExtensions + Native Messaging

Keep HTTP transport behind an interface so another implementation can be
introduced later if HTTP/2 or HTTP/3 requirements justify it.

------------------------------------------------------------------------

## 16. API boundaries

The UI should interact with application-level commands, not internal
segment workers.

Suggested public API:

``` dart
abstract interface class DownloadEngine {
  Future<DownloadInfo> createDownload(CreateDownloadRequest request);

  Future<void> pauseDownload(String downloadId);

  Future<void> resumeDownload(String downloadId);

  Future<void> cancelDownload(String downloadId);

  Future<void> retryDownload(String downloadId);

  Future<void> setPriority(String downloadId, int priority);

  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond);

  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  );

  Future<List<DownloadInfo>> listDownloads();

  Stream<DownloadEvent> get events;
}
```

The exact types should live in `download_api`, with no Flutter
dependencies.

------------------------------------------------------------------------

## 17. Error model and observability

Use stable error codes rather than relying on human-readable exception
strings.

Example categories:

-   `invalid_url`
-   `unsupported_scheme`
-   `network_timeout`
-   `connection_reset`
-   `http_rate_limited`
-   `http_server_error`
-   `range_not_supported`
-   `range_response_invalid`
-   `remote_file_changed`
-   `destination_permission_denied`
-   `insufficient_disk_space`
-   `disk_write_failed`
-   `integrity_check_failed`
-   `recovery_failed`

Expose structured metrics:

-   Bytes received and written.
-   Current and average throughput.
-   Active connections.
-   Retry count.
-   Time spent waiting for network and disk.
-   Queue wait time.
-   Recovery result.
-   Per-task and global resource usage.

Logs must redact cookies, authorization headers, signed URL query
parameters, and other secrets.

------------------------------------------------------------------------

## 18. Testing strategy

### Unit tests

-   Segment boundary calculation.
-   State transitions.
-   Retry/backoff decisions.
-   Bandwidth token bucket.
-   Filename sanitization.
-   Validator comparison.
-   Progress aggregation.

### Integration tests

Build a local test HTTP server that can simulate:

-   Correct and incorrect Range responses.
-   Servers without Range support.
-   Redirects.
-   Slow responses.
-   Connection resets.
-   `429`, `503`, and `5xx`.
-   Changed ETag.
-   Truncated bodies.
-   Unknown content length.
-   Authentication requirements.

### Recovery tests

-   Pause and resume.
-   Kill engine during download.
-   Kill engine during a file write.
-   Kill engine after writing but before metadata commit.
-   Restart with missing or truncated partial file.
-   Resume after remote representation changes.

### Cross-platform tests

Run the same engine suite on Windows and Linux, including file locking,
rename behavior, path handling, and shutdown behavior.

------------------------------------------------------------------------

## 19. Benchmark plan

Benchmark against a controlled local or remote server with identical
conditions.

  Scenario                     Purpose
  ---------------------------- -------------------------
  1 connection                 Baseline
  2 connections                Initial scaling
  4 connections                Moderate parallelism
  8 connections                Higher parallelism
  16 connections               High parallelism
  32 connections               Limit and overhead test
  10 concurrent files          Scheduler fairness
  100 concurrent connections   Stress and resource use
  10--50 GB file               Long-running stability
  Interrupted network          Recovery correctness

Record:

-   Average and peak throughput.
-   CPU utilization.
-   Peak RSS memory.
-   Disk write throughput.
-   Connection count.
-   Retry count.
-   Time to recover.
-   Final file hash.

Do not claim that a multi-connection mode is faster unless the benchmark
demonstrates it under controlled conditions. Compare against a single
connection and, where possible, an established downloader.

------------------------------------------------------------------------

## 20. Development roadmap

### M1 --- Download Core

-   HTTP/HTTPS transport.
-   Resource probing.
-   Range validation.
-   Segment planning.
-   Streaming file writes.
-   Pause, resume, cancel.

**Exit criteria:** CLI can download files correctly in single-stream and
segmented modes.

### M2 --- Reliability and performance

-   Retry and backoff.
-   SQLite persistence.
-   Crash recovery.
-   Global scheduler.
-   Adaptive concurrency.
-   Bandwidth limiter.
-   Benchmark harness.

**Exit criteria:** downloads recover safely from process and network
failures, with bounded memory usage.

### M3 --- Flutter desktop

-   Dashboard and download list.
-   Queue controls.
-   Download details.
-   Settings.
-   Statistics.
-   In-process engine (no IPC between UI and engine); the app hosts the
    IPC server for the browser extension.

**Exit criteria:** the UI can manage engine tasks without owning
download execution.

### M4 --- Background and OS integration

-   System tray.
-   Autostart.
-   Engine lifecycle management (the engine runs in-process, so its
    lifecycle is the app's; closing the window hides to the tray).
-   Windows and Linux packaging.
-   Startup recovery.

**Exit criteria:** closing the window hides the app to the tray and
downloads keep running; quitting from the tray ends the app cleanly,
and downloads can recover after reboot.

### M5 --- Browser integration

-   Chromium extension.
-   Firefox extension.
-   Native Messaging.
-   Permission-aware cookie/header handling.
-   Download handoff.

**Exit criteria:** users can send browser downloads to the engine
reliably.

### M6 --- Advanced features

-   FTP/SFTP.
-   HTTP/2 and HTTP/3 evaluation.
-   Advanced scheduling.
-   Additional diagnostics.
-   Installer and updater improvements.

**Exit criteria:** advanced features are added without destabilizing the
core engine.

------------------------------------------------------------------------

## 21. Initial implementation priorities

Implement in this order:

1.  `download_api`: shared models, commands, events, error types.
2.  `download_transport`: HTTP client and streaming response
    abstraction.
3.  `download_core`: probing, single-stream download, segment planning.
4.  `download_storage`: safe random-access writes and bounded buffering.
5.  `download_scheduler`: per-file and global scheduling.
6.  `download_recovery`: SQLite checkpoints and startup reconciliation.
7.  `download_limiter`: global and per-task bandwidth limits.
8.  `apps/engine`: in-process engine library + CLI `download`
    subcommand (no daemon, no `serve`).
9.  `download_ipc`: versioned local protocol, hosted by the desktop app
    for the browser extension.
10. `apps/desktop`: Flutter UI with the engine embedded and a system
    tray.
11. `integrations/browser-extension`: browser handoff.

Do not start browser integration before the engine API and recovery
behavior are stable.

**IDM rework (2026-11-10):** the original plan had the engine as a
separate daemon process (`serve`) with the UI talking to it over IPC.
That was reworked to the IDM direction — a single process with the
engine embedded in the desktop app — so the release bundle is one app,
downloads survive closing the window via the tray, and the extension
still works through the IPC server the app hosts. Steps 8–11 above
reflect the reworked order.

------------------------------------------------------------------------

## 22. Key architectural decisions

  -----------------------------------------------------------------------
  Decision                Initial choice          Reason
  ----------------------- ----------------------- -----------------------
  UI and engine           Separate processes      UI crashes must not
                                                  stop downloads

  Engine language         Dart                    Shared language and
                                                  ecosystem with Flutter

  Network concurrency     Async I/O               Avoid one Isolate per
                                                  connection

  CPU-heavy tasks         Bounded Isolate workers Keep event loop
                                                  responsive

  Database                SQLite                  Local persistence and
                                                  transactions

  File writes             Streaming, bounded      Predictable memory
                          queues                  usage

  Segmentation            HTTP Range              Parallel downloads
                                                  where supported

  Resume safety           ETag / Last-Modified    Avoid mixing file
                          validation              versions

  Browser integration     WebExtension + Native   Standard desktop
                          Messaging               integration path

  Optimization            Benchmark-driven        Avoid premature
                                                  complexity
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 23. Definition of done for the first usable release

The first usable release is complete when:

-   Users can add HTTP/HTTPS URLs.
-   The engine probes resources safely.
-   Supported files can download in multiple segments.
-   Unsupported servers fall back safely to single-stream mode.
-   Users can pause, resume, retry, and cancel.
-   Multiple downloads can run concurrently under global limits.
-   Per-task and global speed limits work.
-   Downloads recover after engine restart.
-   Large files do not cause memory usage to grow with file size.
-   Flutter can close while the engine continues downloading.
-   The final file is validated before being marked complete.
-   The same core integration tests pass on Windows and Linux.

------------------------------------------------------------------------

## 24. Final recommendation

Build the product as a **Dart download engine with a Flutter desktop
frontend**, not as a Flutter application that happens to download files.

The highest-risk engineering areas are:

1.  Correct HTTP Range handling across real-world servers.
2.  Safe concurrent random-access file writing.
3.  Crash-consistent checkpoints and recovery.
4.  Fair global scheduling and adaptive concurrency.
5.  Reliable engine lifecycle and IPC on Windows and Linux.

Prove these five areas with a CLI engine and automated tests first. Once
they are stable, Flutter becomes a relatively independent presentation
layer and the project can evolve toward a full IDM-style desktop
product.
