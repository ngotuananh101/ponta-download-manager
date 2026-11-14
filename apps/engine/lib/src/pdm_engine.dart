import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_integrity/download_integrity.dart';
import 'package:download_core/download_core.dart';
import 'package:download_external/download_external.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_recovery/download_recovery.dart';
import 'package:download_scheduler/download_scheduler.dart';
import 'package:download_storage/download_storage.dart';
import 'package:download_transport/download_transport.dart';
import 'package:path/path.dart' as p;

import 'engine_config.dart';
import 'file_naming.dart';

/// Default database path: `$XDG_DATA_HOME/pdm/pdm.db` (Linux),
/// `~/.local/share/pdm/pdm.db` when XDG is unset, and
/// `%LOCALAPPDATA%\pdm\pdm.db` on Windows.
String defaultDatabasePath() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base =
        localAppData ??
        p.join(
          Platform.environment['USERPROFILE'] ?? '.',
          'AppData',
          'Local',
        );
    return p.join(base, 'pdm', 'pdm.db');
  }
  final xdg = Platform.environment['XDG_DATA_HOME'];
  final base =
      xdg ?? p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');
  return p.join(base, 'pdm', 'pdm.db');
}

/// Browser headers captured for one download at creation, with the
/// origin they were captured for.
typedef _RequestHeaders = ({
  String? cookie,
  String? referrer,
  String origin,
});

/// Cache key for a yt-dlp probe: the URL plus whether cookies were
/// supplied, so a login-state change re-probes instead of reusing a
/// result from the other state.
typedef _ProbeCacheKey = ({String url, bool hasCookies});

/// One cached probe result with its probe time (10 minute TTL).
class _CachedProbe {
  _CachedProbe(this.result, this.probedAt);

  final YtDlpProbeResult result;
  final DateTime probedAt;
}

/// The standalone download engine: the §16 DownloadEngine backed by
/// the scheduler, the SQLite checkpoint store and the bandwidth
/// limiter. Created with [PdmEngine.open]; shut down with [dispose].
class PdmEngine implements DownloadEngine {
  PdmEngine._({
    required this.config,
    required DownloadStore store,
    required DownloadScheduler scheduler,
    required CheckpointWriter writer,
    required BandwidthLimiter limiter,
    required DownloadTransport transport,
    ExternalTools? externalTools,
    Future<ExternalTools> Function()? resolveExternalTools,
    YtDlpDownloader? ytDlpDownloader,
  })  : _store = store,
        _scheduler = scheduler,
        _writer = writer,
        _limiter = limiter,
        _transport = transport,
        _externalTools = externalTools,
        _resolveExternalTools = resolveExternalTools ?? ExternalTools.resolve,
        _ytDlp = ytDlpDownloader;

  factory PdmEngine.open({
    EngineConfig config = const EngineConfig(),
    String? databasePath,
    BandwidthLimiter? limiter,
    ExternalTools? externalTools,
    Future<ExternalTools> Function()? resolveExternalTools,
    YtDlpDownloader? ytDlpDownloader,
  }) {
    final dbPath = databasePath ?? defaultDatabasePath();
    Directory(p.dirname(dbPath)).createSync(recursive: true);
    final store = DownloadStore.open(dbPath);
    final bandwidthLimiter = limiter ?? BandwidthLimiter();
    late final PdmEngine engine;
    final scheduler = DownloadScheduler(
      maxConcurrent: config.maxConcurrentDownloads,
      limiter: bandwidthLimiter,
      taskFactory: (job) => engine._taskFactory(job),
    );
    final writer = CheckpointWriter(store);
    engine = PdmEngine._(
      config: config,
      store: store,
      scheduler: scheduler,
      writer: writer,
      limiter: bandwidthLimiter,
      transport: HttpTransport(),
      externalTools: externalTools,
      resolveExternalTools: resolveExternalTools,
      ytDlpDownloader: ytDlpDownloader,
    );
    engine._schedulerSub = engine._scheduler.events.listen(
      engine._onSchedulerEvent,
    );
    engine._recover();
    return engine;
  }

  final EngineConfig config;
  final DownloadStore _store;
  final DownloadScheduler _scheduler;
  final CheckpointWriter _writer;
  final BandwidthLimiter _limiter;
  final DownloadTransport _transport;
  var _disposed = false;

  /// True from the moment [dispose] closes the store. Separate from
  /// [_disposed]: shutdown starts long before the store closes, and
  /// the yt-dlp events that land in that window still have a row to
  /// settle (a run reporting completion has its file on disk).
  var _storeClosed = false;

  /// Lazily resolved external tools (injected in tests).
  ExternalTools? _externalTools;

  /// How the tools are resolved when they were not injected.
  final Future<ExternalTools> Function() _resolveExternalTools;

  /// Lazily created yt-dlp downloader (injected in tests).
  YtDlpDownloader? _ytDlp;

  /// Merged event stream: scheduler events plus yt-dlp events.
  final _events = StreamController<DownloadEvent>.broadcast();
  StreamSubscription<DownloadEvent>? _schedulerSub;
  final _ytDlpSubs = <String, StreamSubscription<DownloadEvent>>{};

  /// Monotonic per-download sequence of yt-dlp intents (pause, resume,
  /// cancel, retry, delete, startup recovery).
  ///
  /// Every action bumps it synchronously before its first await, and a
  /// start-like action re-reads it after each await. That is what makes
  /// the later user action win: a resume or retry still resolving the
  /// tools when a cancel, pause, delete or another start is issued sees
  /// a newer sequence and aborts before it deletes an output or spawns
  /// a process. The sequence is not derived from the stored status: a
  /// retry of an already-cancelled row is legitimate, and a cancel of a
  /// completed row changes no status but must still stop a retry that
  /// began before it.
  final _intentSeq = <String, int>{};

  /// Counter for yt-dlp download ids (`yt-N`), a separate id space
  /// from the scheduler's `dl-N` so the two can never collide.
  var _ytCounter = 0;

  /// Which mirror a download is currently trying (-1 = the primary
  /// URL, 0..n-1 = the mirrors in record order). In-memory only: a
  /// restart always begins from the primary again.
  final _mirrorIndex = <String, int>{};

  /// Browser headers captured for one download at creation, keyed by
  /// download id. In-memory only: never written to the store, dropped
  /// on cancel/delete/dispose, and gone after a restart by design.
  final _requestHeaders = <String, _RequestHeaders>{};

  /// Chosen yt-dlp format id per download, keyed by download id.
  /// In-memory only, like [_requestHeaders]: dropped on cancel/delete/
  /// dispose, and gone after a restart (a resumed download then falls
  /// back to yt-dlp's default format selection).
  final _ytDlpFormats = <String, String>{};

  /// Probe results per URL and cookie state, 10 minute TTL. Probing
  /// spawns a yt-dlp process, so reopening the popup reuses the last
  /// probe instead of running yt-dlp again.
  final _probeCache = <_ProbeCacheKey, _CachedProbe>{};

  /// Headers stored for [downloadId] when [url] has the same origin
  /// they were captured for; null otherwise (unknown id, or another
  /// origin). A retry or failover re-sends a session cookie only to
  /// the origin it came from, never to a mirror or a changed URL.
  _RequestHeaders? _headersFor(String downloadId, String url) {
    final stored = _requestHeaders[downloadId];
    if (stored == null) return null;
    if (Uri.parse(url).origin != stored.origin) return null;
    return stored;
  }

  @override
  Stream<DownloadEvent> get events => _events.stream;

  /// Number of yt-dlp event subscriptions currently held. Test-only
  /// seam: the subscriptions are pruned when their download reaches
  /// a terminal event, and this count is how the tests observe that.
  int get ytDlpSubscriptionCount => _ytDlpSubs.length;

  /// True for HLS (.m3u8) and DASH (.mpd) playlist URLs, which the
  /// native segment downloader cannot handle (it would save the
  /// playlist file itself). These go to the yt-dlp downloader.
  bool _isStreamingPlaylist(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8') || path.endsWith('.mpd');
  }

  /// True for downloads the yt-dlp branch owns: streaming playlists,
  /// or any download created with a chosen yt-dlp format. The `yt-`
  /// id prefix is the persisted marker — the yt-dlp branch always
  /// creates `yt-N` ids while the scheduler creates `dl-N` — so this
  /// also holds after a restart, when the in-memory format map is gone.
  bool _isYtDlpDownload(DownloadRecord record) =>
      _isStreamingPlaylist(record.url) || record.id.startsWith('yt-');

  /// True when the download reached an end state of its own, so no
  /// user action may move it again (pause/cancel/resume are no-ops).
  static bool _isTerminalStatus(DownloadStatus status) =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  /// Advances the yt-dlp id counter past [id] (e.g. 'yt-7'), so a
  /// later generated id never collides with one already in the store.
  void _reserveYtId(String id) {
    final match = RegExp(r'^yt-(\d+)$').firstMatch(id);
    if (match != null) {
      final n = int.parse(match.group(1)!);
      if (n >= _ytCounter) {
        _ytCounter = n + 1;
      }
    }
  }

  /// The yt-dlp downloader, resolved lazily (tools are only needed
  /// when a playlist URL is added). Returns null when ffmpeg or
  /// yt-dlp is missing.
  ///
  /// Concurrent callers share one resolution. Two playlist downloads
  /// added before the tools resolve each used to build their own
  /// downloader, and the second became the one the engine holds: the
  /// first run was then invisible to pause, cancel and dispose, which
  /// kept transferring after the UI said cancelled.
  Future<YtDlpDownloader?> _ytDlpDownloader() {
    return _ytDlpResolution ??= _resolveYtDlpDownloader();
  }

  Future<YtDlpDownloader?>? _ytDlpResolution;

  Future<YtDlpDownloader?> _resolveYtDlpDownloader() async {
    if (_ytDlp != null) {
      return _ytDlp;
    }
    final tools = _externalTools ?? await _resolveExternalTools();
    _externalTools = tools;
    if (!tools.available) {
      return null;
    }
    _ytDlp ??= YtDlpDownloader(
      ytDlpPath: tools.ytDlpPath!,
      ffmpegDir: p.dirname(tools.ffmpegPath!),
      jsRuntimes: tools.ytDlpJsRuntimeArgs,
    );
    return _ytDlp;
  }

  /// The yt-dlp `-o` template for a record: the file stem with
  /// `%(ext)s`, so yt-dlp chooses the container (mp4/mkv) itself.
  String _ytDlpTemplate(DownloadRecord record) {
    final stem = p.basenameWithoutExtension(record.fileName);
    return p.join(record.directory, '$stem.%(ext)s');
  }

  /// Caps a probe result at the best 30 formats (best first), so the
  /// IPC line stays far under the 1 MiB cap and the popup stays usable.
  YtDlpProbeResult _trimProbeResult(YtDlpProbeResult result) {
    if (result.formats.length <= 30) {
      return result;
    }
    final sorted = [...result.formats]..sort(_compareFormats);
    return result.copyWith(formats: sorted.take(30).toList());
  }

  /// Best first: taller, then larger, then by format id for stability.
  int _compareFormats(YtDlpFormat a, YtDlpFormat b) {
    final height = (b.height ?? 0).compareTo(a.height ?? 0);
    if (height != 0) return height;
    final size = _formatSize(b).compareTo(_formatSize(a));
    if (size != 0) return size;
    return a.formatId.compareTo(b.formatId);
  }

  int _formatSize(YtDlpFormat format) =>
      format.filesize ?? format.filesizeApprox ?? 0;

  /// The yt-dlp `-f` argument for [record]: the chosen format id, with
  /// `+bestaudio` appended for video-only picks (the cached probe says
  /// which formats carry audio). Without a cached probe the id is
  /// passed verbatim. Null when no format was chosen, so yt-dlp picks
  /// its default format.
  String? _formatArgFor(DownloadRecord record) {
    final formatId = _ytDlpFormats[record.id];
    if (formatId == null) return null;
    final cookie = _headersFor(record.id, record.url)?.cookie;
    final key = (
      url: record.url,
      hasCookies: cookie != null && cookie.trim().isNotEmpty,
    );
    final cached = _probeCache[key];
    YtDlpFormat? format;
    if (cached != null) {
      for (final candidate in cached.result.formats) {
        if (candidate.formatId == formatId) {
          format = candidate;
          break;
        }
      }
    }
    if (format == null) return formatId;
    if (format.vcodec != 'none' && format.acodec == 'none') {
      return '$formatId+bestaudio';
    }
    return formatId;
  }

  /// Starts a yt-dlp download for [record] and wires its events into
  /// the engine event stream and the store.
  ///
  /// A record that already has a live run is not started again: the
  /// second process would write the same output file and restart the
  /// transfer from the beginning, which the user sees as a download
  /// that reaches 100% and then downloads again. The downloader
  /// refuses the duplicate id anyway, so this keeps the call a no-op
  /// instead of an unhandled error.
  void _startYtDlp(DownloadRecord record, YtDlpDownloader downloader) {
    if (_disposed) {
      // Every start path awaits before it gets here (the tools, the
      // run teardown). Once the engine shut down, the downloader was
      // shut down with it: a process spawned now would belong to
      // nothing and outlive the app.
      return;
    }
    if (_ytDlpSubs.containsKey(record.id)) {
      return;
    }
    final headers = _headersFor(record.id, record.url);
    final sub = downloader
        .start(
          downloadId: record.id,
          url: record.url,
          outputTemplate: _ytDlpTemplate(record),
          format: _formatArgFor(record),
          cookie: headers?.cookie,
          referrer: headers?.referrer,
        )
        .listen(_onYtDlpEvent);
    _ytDlpSubs[record.id] = sub;
  }

  /// Forwards scheduler events to the engine stream and finalizes
  /// native downloads in the store. The scheduler emits completed
  /// only after the sink rename, so this is where the writer learns
  /// the final file exists; the writer deliberately ignores the
  /// task's own (pre-rename) completed events.
  void _onSchedulerEvent(DownloadEvent event) {
    // A failed download with mirrors left tries the next mirror
    // instead of failing: the failed event is swallowed and the
    // download restarts from the mirror URL.
    final failedOver = event.maybeWhen(
      failed: (downloadId, _, _) => _tryFailOver(downloadId),
      orElse: () => false,
    );
    if (failedOver) return;
    // The task reports a failure twice: stateChanged(failed), then a
    // failed event with the message. When a failover is coming it is
    // the failed event that is swallowed, so forwarding this state
    // change would leave the UI on Failed with no reason until the
    // mirror's queued event arrives. Hold it back too: the failed
    // event that follows is the one that decides.
    if (event.maybeWhen(
      stateChanged: (downloadId, status) =>
          status == DownloadStatus.failed && _canFailOver(downloadId),
      orElse: () => false,
    )) {
      return;
    }
    _events.add(event);
    event.when(
      progress: (_, _, _, _) {},
      stateChanged: (downloadId, status) {
        if (status == DownloadStatus.completed) {
          _mirrorIndex.remove(downloadId);
          _writer.complete(downloadId);
        }
      },
      completed: (downloadId, _) {
        _mirrorIndex.remove(downloadId);
        _writer.complete(downloadId);
      },
      failed: (downloadId, code, message) {
        _mirrorIndex.remove(downloadId);
        _writer.fail(downloadId, code, message);
      },
    );
  }

  /// True when a failure of [downloadId] has a mirror left to try, so
  /// the failure is not the row's outcome and must not be announced.
  bool _canFailOver(String downloadId) {
    final record = _store.getDownload(downloadId);
    if (record == null) return false;
    if (_isStreamingPlaylist(record.url)) return false;
    return (_mirrorIndex[downloadId] ?? -1) + 1 < record.mirrors.length;
  }

  /// Tries the next mirror URL for a failed download. Returns true
  /// when the download was re-enqueued with a mirror (the failed
  /// event is then swallowed); false when there is no mirror left.
  bool _tryFailOver(String downloadId) {
    final record = _store.getDownload(downloadId);
    if (record == null) return false;
    // Playlists fail through yt-dlp's own path, not the scheduler.
    if (_isStreamingPlaylist(record.url)) return false;
    final next = (_mirrorIndex[downloadId] ?? -1) + 1;
    if (next >= record.mirrors.length) return false;
    _mirrorIndex[downloadId] = next;
    final mirrorUrl = record.mirrors[next];
    // A resume would need the primary's validators, which the
    // mirror may not honour: restart from scratch.
    final partial = File(record.partialPath);
    if (partial.existsSync()) {
      partial.deleteSync();
    }
    // Same destination as the failed attempt: overwrite, or the
    // sink factory refuses it when a finished file is already
    // there (a retry of a completed download failing over).
    final headers = _headersFor(downloadId, mirrorUrl);
    _scheduler.enqueue(
      id: downloadId,
      url: mirrorUrl,
      fileName: record.fileName,
      directory: record.directory,
      priority: record.priority,
      maxConnections: record.maxConnections,
      overwrite: true,
      cookie: headers?.cookie,
      referrer: headers?.referrer,
    );
    _store.upsertDownload(
      DownloadRecord(
        id: record.id,
        url: record.url,
        fileName: record.fileName,
        directory: record.directory,
        status: DownloadStatus.queued,
        priority: record.priority,
        maxConnections: record.maxConnections,
        createdAt: record.createdAt,
        mirrors: record.mirrors,
        tags: record.tags,
      ),
    );
    return true;
  }

  /// Drops the yt-dlp event subscription for [downloadId]. The
  /// downloader closes the stream after its terminal event, so the
  /// subscription can never deliver another event; keeping it would
  /// retain the engine and the stream forever (review item 17).
  void _pruneYtDlpSub(String downloadId) {
    final sub = _ytDlpSubs.remove(downloadId);
    if (sub != null) {
      unawaited(sub.cancel());
    }
  }

  /// Forwards a yt-dlp event to the engine stream and updates the
  /// store record the same way the scheduler's writer does for
  /// native downloads.
  void _onYtDlpEvent(DownloadEvent event) {
    if (_storeClosed) {
      // The app has finished shutting down: no row left to settle and
      // no consumer for the event.
      return;
    }
    if (_disposed) {
      // Shutdown is under way. The event stream is closed or about to
      // be, so nothing is forwarded — but a run that already finished
      // has its file on disk, and its row has to say so. Dropping that
      // leaves the record downloading, and the next startup downloads
      // the finished file again. Only terminal outcomes are settled:
      // a pause or cancel arriving here is an artefact of the
      // teardown, not a user intent.
      event.when(
        progress: (_, _, _, _) {},
        stateChanged: (_, _) {},
        completed: (downloadId, filePath) =>
            _recordYtDlpCompleted(downloadId, filePath),
        failed: (downloadId, code, message) =>
            _recordYtDlpFailed(downloadId, code, message),
      );
      return;
    }
    _events.add(event);
    event.when(
      progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {
        final record = _store.getDownload(downloadId);
        if (record != null) {
          _store.upsertDownload(
            record.copyWith(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              // The record is created queued; the first progress event
              // is what moves it to downloading.
              status: DownloadStatus.downloading,
            ),
          );
        }
      },
      stateChanged: (downloadId, status) {
        _updateStatus(downloadId, status);
        // The downloader closes the stream after a paused or
        // cancelled event, so this subscription is done.
        if (status == DownloadStatus.paused ||
            status == DownloadStatus.cancelled) {
          _pruneYtDlpSub(downloadId);
        }
      },
      completed: (downloadId, filePath) {
        _recordYtDlpCompleted(downloadId, filePath);
        _pruneYtDlpSub(downloadId);
      },
      failed: (downloadId, code, message) {
        _recordYtDlpFailed(downloadId, code, message);
        _pruneYtDlpSub(downloadId);
      },
    );
  }

  /// Stores the finished file of a yt-dlp run: the file name is the
  /// real file yt-dlp produced, which may differ from the playlist
  /// name (live.m3u8 -> live.mp4), and destinationPath is derived
  /// from directory + fileName, so it follows automatically.
  void _recordYtDlpCompleted(String downloadId, String filePath) {
    final record = _storedRecord(downloadId);
    if (record == null) {
      return;
    }
    final file = File(filePath);
    final size = file.existsSync() ? file.lengthSync() : record.totalBytes;
    _store.upsertDownload(
      record.copyWith(
        status: DownloadStatus.completed,
        fileName: p.basename(filePath),
        downloadedBytes: size,
        totalBytes: size,
      ),
    );
  }

  void _recordYtDlpFailed(String downloadId, String code, String message) {
    final record = _storedRecord(downloadId);
    if (record == null) {
      return;
    }
    _store.upsertDownload(
      record.copyWith(
        status: DownloadStatus.failed,
        errorCode: code,
        errorMessage: message,
      ),
    );
  }

  /// A destination is taken when the file is on disk or a stored
  /// download already claims it. The store check closes the race
  /// where two renames pick the same free name while neither file
  /// exists yet (the first download is still in flight).
  bool _isDestinationTaken(String path) {
    if (File(path).existsSync()) return true;
    return _store.listDownloads().any((r) => r.destinationPath == path);
  }

  @override
  Future<ProbeResult> probeUrl(String url) async {
    _throwIfDisposed();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const DownloadError(
        'invalid-url',
        'URL must start with http:// or https://',
      );
    }
    if (_isStreamingPlaylist(url)) {
      // yt-dlp decides the size at download time; probing the playlist
      // file itself would report the playlist's own (tiny) size.
      final segments = uri.pathSegments;
      final fileName = segments.isNotEmpty && segments.last.isNotEmpty
          ? segments.last
          : 'download';
      return ProbeResult(url: url, fileName: fileName, totalBytes: -1);
    }
    final info = await _transport.probe(uri);
    return ProbeResult(
      url: url,
      fileName: info.fileName,
      totalBytes: info.contentLength ?? -1,
    );
  }

  @override
  Future<YtDlpProbeResult> probeYtDlp(
    String url, {
    String? cookie,
    String? referrer,
  }) async {
    _throwIfDisposed();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const DownloadError(
        'invalid-url',
        'URL must start with http:// or https://',
      );
    }
    // The downloader never throws for a yt-dlp failure: it returns a
    // supported:false result carrying the error code, so the popup can
    // show the right copy. Only a bad URL or missing tools throw here.
    final hasCookies = cookie != null && cookie.trim().isNotEmpty;
    final key = (url: url, hasCookies: hasCookies);
    final cached = _probeCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.probedAt) <
            const Duration(minutes: 10)) {
      return cached.result;
    }
    final downloader = await _ytDlpDownloader();
    if (downloader == null) {
      throw const DownloadError(
        'external-tools-missing',
        'ffmpeg and yt-dlp are required to probe this page. '
        'They are bundled with PDM; check the app bundle.',
      );
    }
    final result = await downloader.probe(
      url: url,
      cookie: cookie,
      referrer: referrer,
    );
    final trimmed = _trimProbeResult(result);
    // Only successful probes are cached: a failed probe is re-run on
    // the next call, so a transient failure (bad cookies, a YouTube
    // hiccup) can heal on its own instead of showing the same error
    // until the TTL expires.
    if (trimmed.supported) {
      _probeCache[key] = _CachedProbe(trimmed, DateTime.now());
    }
    return trimmed;
  }

  @override
  Future<DownloadInfo> createDownload(CreateDownloadRequest request) async {
    _throwIfDisposed();
    final destination = request.destination;
    var directory = p.dirname(destination);
    if (directory == '.') {
      directory = config.downloadDirectory;
    }
    var fileName = p.basename(destination);
    if (fileName.isEmpty) {
      final segments = Uri.parse(request.url).pathSegments;
      fileName = segments.isNotEmpty ? segments.last : 'download';
      if (fileName.isEmpty) {
        fileName = 'download';
      }
    }
    final destPath = p.join(directory, fileName);
    String resolveName(String candidatePath) {
      switch (request.conflictPolicy) {
        case FileConflictPolicy.overwrite:
          // Proceed: the sink rename at the end replaces the file.
          return p.basename(candidatePath);
        case FileConflictPolicy.rename:
          return p.basename(
            resolveUniquePath(candidatePath, isTaken: _isDestinationTaken),
          );
        case null:
          if (File(candidatePath).existsSync()) {
            throw DownloadError(
              'file-exists',
              'Destination already exists: $candidatePath',
            );
          }
          return p.basename(candidatePath);
      }
    }

    fileName = resolveName(destPath);
    if (_isStreamingPlaylist(request.url) || request.ytDlpFormat != null) {
      final downloader = await _ytDlpDownloader();
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to download streams. '
          'They are bundled with PDM; check the app bundle.',
        );
      }
      // Resolve the conflict again: the check above ran before the
      // tools were awaited, so another playlist download added in that
      // window saw the same free name and both would write one file.
      fileName = resolveName(p.join(directory, fileName));
      final id = 'yt-${++_ytCounter}';
      final record = DownloadRecord(
        id: id,
        url: request.url,
        fileName: fileName,
        directory: directory,
        status: request.paused
            ? DownloadStatus.paused
            : DownloadStatus.queued,
        priority: request.priority ?? 0,
        maxConnections:
            request.maxConnections ?? config.maxConnectionsPerDownload,
      );
      _store.upsertDownload(record);
      // Announce the new row before yt-dlp produces anything. The
      // scheduler branch emits stateChanged(queued) from enqueue(); the
      // UI only learns about a download created elsewhere (the browser
      // extension, over IPC) from an engine event, so without this the
      // row stayed hidden until the first progress line arrived.
      _events.add(
        DownloadEvent.stateChanged(downloadId: id, status: record.status),
      );
      // The yt-dlp branch stores the browser headers and the chosen
      // format in memory, like the scheduler branch stores headers:
      // retry/resume re-send them, and they never reach the store.
      if (request.cookie != null || request.referrer != null) {
        _requestHeaders[id] = (
          cookie: request.cookie,
          referrer: request.referrer,
          origin: Uri.parse(request.url).origin,
        );
      }
      if (request.ytDlpFormat != null) {
        _ytDlpFormats[id] = request.ytDlpFormat!;
      }
      // A paused playlist is stored paused and starts only on resume
      // (resumeDownload starts it through the downloader).
      if (!request.paused) {
        _startYtDlp(record, downloader);
      }
      return _infoFromRecord(record);
    }
    final id = _scheduler.enqueue(
      url: request.url,
      fileName: fileName,
      directory: directory,
      priority: request.priority ?? 0,
      maxConnections:
          request.maxConnections ?? config.maxConnectionsPerDownload,
      overwrite: request.conflictPolicy == FileConflictPolicy.overwrite,
      paused: request.paused,
      cookie: request.cookie,
      referrer: request.referrer,
    );
    if (request.cookie != null || request.referrer != null) {
      _requestHeaders[id] = (
        cookie: request.cookie,
        referrer: request.referrer,
        origin: Uri.parse(request.url).origin,
      );
    }
    final record = DownloadRecord(
      id: id,
      url: request.url,
      fileName: fileName,
      directory: directory,
      status: request.paused
          ? DownloadStatus.paused
          : DownloadStatus.queued,
      priority: request.priority ?? 0,
      maxConnections:
          request.maxConnections ?? config.maxConnectionsPerDownload,
    );
    _store.upsertDownload(record);
    return _infoFromRecord(record);
  }

  @override
  Future<void> pauseDownload(String downloadId) async {
    final record = _store.getDownload(downloadId);
    // Only a queued or downloading download can be paused. Pausing a
    // terminal download (completed/failed/cancelled) or an already
    // paused one is a no-op: the record must keep its real status.
    if (record == null ||
        (record.status != DownloadStatus.queued &&
            record.status != DownloadStatus.downloading)) {
      return;
    }
    if (_isYtDlpDownload(record)) {
      // The pause is a stop intent: a start that is still resolving
      // the tools (startup recovery is the common case) must not
      // spawn a run after it. Claim the intent before the first await
      // so that start sees a newer intent and gives up.
      final seq = _claimIntent(downloadId);
      final hadLiveRun = _ytDlpSubs.containsKey(downloadId);
      await _ytDlp?.pause(downloadId);
      if (!_intentCurrent(downloadId, seq)) {
        // A later cancel, delete or retry took over: it owns the
        // outcome and this pause must not write over it.
        return;
      }
      // The pause waits for the downloader to tear the run down, and
      // the run can reach a terminal state in that window: a short
      // stream finishes between the status check above and the kill,
      // and its completed event lands in the store. Writing paused
      // here would overwrite a finished download (and deny the user
      // the file it just produced).
      final current = _liveRecord(downloadId);
      if (current != null && _isTerminalStatus(current.status)) {
        return;
      }
      _updateStatus(downloadId, DownloadStatus.paused);
      if (!hadLiveRun) {
        // A live run announces its own paused state; with none, the
        // store would say paused while the UI still showed the row
        // running, since it learns state only from events.
        _events.add(
          DownloadEvent.stateChanged(
            downloadId: downloadId,
            status: DownloadStatus.paused,
          ),
        );
      }
      return;
    }
    _scheduler.pause(downloadId);
    _updateStatus(downloadId, DownloadStatus.paused);
  }

  @override
  Future<void> resumeDownload(String downloadId) async {
    final record = _store.getDownload(downloadId);
    // Only a paused download can be resumed. Resuming a terminal
    // download must not re-queue it (or restart a finished playlist),
    // and resuming a running one must not reset it to queued.
    if (record == null || record.status != DownloadStatus.paused) {
      return;
    }
    if (_isYtDlpDownload(record)) {
      // Every start is an intent of its own, recorded before the first
      // await. A pause, cancel or delete issued while the tools resolve
      // bumps the sequence, and any *other* start still resolving sees
      // that and gives up. This resume re-checks the store instead of
      // its own sequence: every stop action writes its status
      // synchronously before it awaits, so the store is the record of
      // "a later stop already happened".
      _claimIntent(downloadId);
      final downloader = await _ytDlpDownloader();
      // Re-read the record: an edit made while the tools resolved (a
      // rename, move or URL change writes only the store) must be the
      // one the run uses, or yt-dlp fetches the address the user
      // replaced.
      final current = _liveRecord(downloadId);
      if (current == null || current.status != DownloadStatus.paused) {
        return;
      }
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to resume this download.',
        );
      }
      _updateStatus(downloadId, DownloadStatus.queued);
      // Announce the new state before yt-dlp prints anything. The UI
      // deliberately holds a paused row at Paused when progress
      // arrives (an in-flight chunk must not revive it), so without
      // this event the row stayed "Paused 93%" while the resumed
      // transfer's bytes kept climbing. The scheduler branch already
      // emits stateChanged(queued) from resume().
      _events.add(
        DownloadEvent.stateChanged(
          downloadId: downloadId,
          status: DownloadStatus.queued,
        ),
      );
      _startYtDlp(current, downloader);
      return;
    }
    _scheduler.resume(downloadId);
    _updateStatus(downloadId, DownloadStatus.queued);
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    final record = _store.getDownload(downloadId);
    // A completed or cancelled download is not cancelled again: there is
    // nothing to stop and the status is already what cancel means. A
    // failed one is different — the row menu offers Cancel there to
    // dismiss the error — so it is allowed through. No-op means no-op,
    // including the in-memory headers and format: those are the only
    // record of what the user picked, and retry reuses them.
    if (record != null &&
        (record.status == DownloadStatus.completed ||
            record.status == DownloadStatus.cancelled)) {
      // Even as a status no-op the intent matters: a retry of a
      // completed row is in flight and would replace the finished
      // file. Bumping the sequence stops it before it deletes
      // anything. A cancelled row's own retry is issued after this
      // call, so it claims a newer sequence and still runs.
      _claimIntent(downloadId);
      return;
    }
    _requestHeaders.remove(downloadId);
    _ytDlpFormats.remove(downloadId);
    if (record != null && _isYtDlpDownload(record)) {
      // The cancel is the stop intent: claim it before the first await
      // so a resume or retry still resolving the tools gives up
      // instead of spawning a run for a row the user just stopped. The
      // sequence is re-read after the await below, because the row can
      // be taken over in that window too.
      final seq = _claimIntent(downloadId);
      // A live run emits its own cancelled state from the downloader.
      // A paused (or not yet started) one has no live run, so
      // YtDlpDownloader.cancel has nothing to kill and emits nothing:
      // without the event below the store said cancelled while the UI
      // kept showing Paused.
      final hadLiveRun = _ytDlpSubs.containsKey(downloadId);
      if (!hadLiveRun) {
        // With no live run there is no progress or terminal event to
        // wait for and no run whose completion must win, so the status
        // can be written now, before the first await. Writing it after
        // the await let a resume that was resolving the tools slip
        // through and spawn a transfer for a cancelled row.
        _updateStatus(downloadId, DownloadStatus.cancelled);
        _events.add(
          DownloadEvent.stateChanged(
            downloadId: downloadId,
            status: DownloadStatus.cancelled,
          ),
        );
      }
      await _ytDlp?.cancel(downloadId);
      if (!_intentCurrent(downloadId, seq)) {
        // A retry (or another start) claimed the row while this cancel
        // waited for the run to be torn down: it is the later intent
        // and may already be transferring. Writing cancelled over it
        // would lock the UI on Cancelled under a live run.
        return;
      }
      // The cancel waits for the run to be torn down, and the run can
      // reach a terminal state in that window (the process exits with
      // the final file while the kill is in flight). Its own event
      // already told the UI the download finished or was cancelled;
      // rewriting the store to cancelled would leave the two
      // disagreeing.
      final current = _liveRecord(downloadId);
      if (current != null &&
          (current.status == DownloadStatus.completed ||
              current.status == DownloadStatus.cancelled)) {
        return;
      }
      _updateStatus(downloadId, DownloadStatus.cancelled);
      if (hadLiveRun) {
        // The run ended as failed (its event left the UI on Failed)
        // or was killed before it could announce anything. Either
        // way the last event the UI saw is not cancelled, so it must
        // be told: the store now says cancelled.
        _events.add(
          DownloadEvent.stateChanged(
            downloadId: downloadId,
            status: DownloadStatus.cancelled,
          ),
        );
      }
      return;
    }
    // The scheduler emits cancelled for every job it still holds
    // (running, paused, starting or pending), so no event is added
    // here for those. A failed job is the exception: the scheduler
    // already dropped it, so its cancel() is a silent no-op. Cancel on
    // a failed row is how the user dismisses the error, and the UI
    // learns state only from events, so without one the store says
    // cancelled while the row stays Failed.
    final wasFailed = record?.status == DownloadStatus.failed;
    _scheduler.cancel(downloadId);
    _updateStatus(downloadId, DownloadStatus.cancelled);
    if (wasFailed) {
      _events.add(
        DownloadEvent.stateChanged(
          downloadId: downloadId,
          status: DownloadStatus.cancelled,
        ),
      );
    }
  }

  @override
  Future<void> retryDownload(String downloadId) async {
    _mirrorIndex.remove(downloadId);
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isYtDlpDownload(record)) {
      // A retry of a download that is still running would reset the
      // row and hand yt-dlp the same output again: the transfer
      // restarts mid-flight (the "100% then download again" report)
      // and the running process would race the new one for the file.
      if (_ytDlpSubs.containsKey(record.id)) {
        return;
      }
      // The retry is an intent of its own, claimed before the first
      // await. A cancel, pause, delete or another retry that lands
      // while the tools resolve bumps the sequence, and the earlier
      // retry then gives up before it deletes an output or spawns a
      // run: two retries still start only one.
      final seq = _claimIntent(record.id);
      final downloader = await _ytDlpDownloader();
      if (!_intentCurrent(record.id, seq)) {
        // A later pause, cancel, delete or retry owns the row: it may
        // already be writing the output this retry would delete.
        return;
      }
      if (_ytDlpSubs.containsKey(record.id)) {
        // The sequence still says this retry is the latest intent, yet
        // a resume claimed *before* it has just started a run: its
        // await resumed first and wrote the store. Deleting the output
        // now would wipe the file that run is writing, and resetting
        // the row would make the store claim a fresh 0% download while
        // the process keeps transferring (the "100% then download
        // again" report).
        return;
      }
      // Re-read the store: a record edited while the tools resolved
      // (a rename or move updates only the store, not this action) must
      // be retried as it is now. Deleting the old template would leave
      // the renamed file orphaned and write the old name back.
      final current = _liveRecord(record.id);
      if (current == null) {
        // Deleted while the tools were resolving.
        return;
      }
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to retry this download.',
        );
      }
      downloader.deleteOutput(_ytDlpTemplate(current));
      final ytPartial = File(current.partialPath);
      if (ytPartial.existsSync()) {
        ytPartial.deleteSync();
      }
      _store.upsertDownload(
        DownloadRecord(
          id: current.id,
          url: current.url,
          fileName: current.fileName,
          directory: current.directory,
          status: DownloadStatus.queued,
          priority: current.priority,
          maxConnections: current.maxConnections,
          mirrors: current.mirrors,
          tags: current.tags,
          createdAt: current.createdAt,
        ),
      );
      // Announce the restart before the first progress line, for the
      // same reason as resume: the UI keeps a failed row at Failed
      // when progress arrives.
      _events.add(
        DownloadEvent.stateChanged(
          downloadId: current.id,
          status: DownloadStatus.queued,
        ),
      );
      _startYtDlp(current, downloader);
      return;
    }
    if (record.status == DownloadStatus.queued ||
        record.status == DownloadStatus.downloading) {
      // Same rule as the yt-dlp branch above, for a job that has not
      // settled yet: still queued (waiting for a slot, or still in its
      // factory) or already transferring. Re-enqueueing it would start
      // a second run for the same file on the same partial — the row
      // visibly restarts from 0% while the first run keeps writing.
      // Retry is for a settled row.
      return;
    }
    final partial = File(record.partialPath);
    if (partial.existsSync()) {
      partial.deleteSync();
    }
    // Retry reuses the same id: the same row restarts (like IDM/FDM),
    // so no fresh id is generated and no other download can be
    // overwritten. The scheduler's explicit-id path also advances its
    // counter past this id. The record is reset to a fresh queued
    // download, keeping its createdAt so the Added column does not
    // move and the old error is cleared.
    // A retry of a completed download replaces the finished file:
    // without overwrite the sink factory refuses the destination
    // (`file-exists`) and the retry fails before its first request.
    // The old file stays until the new download renames over it, so
    // a failed retry keeps it.
    final headers = _headersFor(downloadId, record.url);
    _scheduler.enqueue(
      id: downloadId,
      url: record.url,
      fileName: record.fileName,
      directory: record.directory,
      priority: record.priority,
      maxConnections: record.maxConnections,
      overwrite: true,
      cookie: headers?.cookie,
      referrer: headers?.referrer,
    );
    _store.upsertDownload(
      DownloadRecord(
        id: record.id,
        url: record.url,
        fileName: record.fileName,
        directory: record.directory,
        status: DownloadStatus.queued,
        priority: record.priority,
        maxConnections: record.maxConnections,
        mirrors: record.mirrors,
        tags: record.tags,
        createdAt: record.createdAt,
      ),
    );
  }

  @override
  Future<void> deleteDownload(
    String downloadId, {
    bool deleteFile = false,
  }) async {
    _requestHeaders.remove(downloadId);
    _ytDlpFormats.remove(downloadId);
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isYtDlpDownload(record)) {
      // Delete the record before the first await. A resume or retry
      // suspended while the tools resolve re-reads the store when it
      // continues: a row that is already gone stops it before it
      // deletes output or spawns a run. Leaving the delete for after
      // the await let that start slip through.
      //
      // The delete is also an intent of its own: a pause or cancel
      // suspended in an await re-reads the sequence when it continues
      // and must not announce a status for a row that is gone.
      _claimIntent(downloadId);
      _store.deleteDownload(downloadId);
      final downloader = await _ytDlpDownloader();
      await downloader?.cancel(downloadId);
      if (deleteFile) {
        // Delete the produced file (and any partial) too.
        downloader?.deleteOutput(_ytDlpTemplate(record));
      } else {
        // Drop yt-dlp partials; the finished file (if any) is kept.
        downloader?.deletePartial(_ytDlpTemplate(record));
      }
      final ytPartial = File(record.partialPath);
      if (ytPartial.existsSync()) {
        ytPartial.deleteSync();
      }
    } else {
      // Stop the download if it is running or queued. The scheduler
      // keeps a stale cancelled entry for the id, which is harmless:
      // the engine lists downloads from the store, not the scheduler.
      _scheduler.cancel(downloadId);
      // Drop the partial file so it does not linger as an orphan. The
      // finished file (if any) is kept on disk unless deleteFile.
      final partial = File(record.partialPath);
      if (partial.existsSync()) {
        partial.deleteSync();
      }
    }
    if (deleteFile) {
      // Best-effort: a missing or undeletable file never blocks
      // deleting the record. For a completed playlist this is the
      // produced file (the record's fileName was updated on
      // completion); for an incomplete one the playlist-name path
      // never exists as a file.
      try {
        final finished = File(record.destinationPath);
        if (finished.existsSync()) {
          finished.deleteSync();
        }
      } catch (_) {
        // Ignore: the record is deleted below regardless.
      }
    }
    if (!_disposed) {
      // The yt-dlp branch deleted the record before its await; this
      // second delete is for the scheduler branch. The app can quit in
      // the window the yt-dlp branch waits in, and dispose() closes
      // the store: writing it afterwards throws out of a
      // fire-and-forget UI action.
      _store.deleteDownload(downloadId);
    }
  }

  @override
  Future<void> deleteFile(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isYtDlpDownload(record)) {
      final downloader = await _ytDlpDownloader();
      // Delete the produced file (and any partial) too.
      downloader?.deleteOutput(_ytDlpTemplate(record));
      final ytPartial = File(record.partialPath);
      if (ytPartial.existsSync()) {
        ytPartial.deleteSync();
      }
    } else {
      // Drop the partial file so it does not linger as an orphan.
      final partial = File(record.partialPath);
      if (partial.existsSync()) {
        partial.deleteSync();
      }
    }
    // Best-effort: a missing or undeletable file is not an error.
    // For a completed playlist this is the produced file (the
    // record's fileName was updated on completion); for an
    // incomplete one the playlist-name path never exists as a file.
    try {
      final finished = File(record.destinationPath);
      if (finished.existsSync()) {
        finished.deleteSync();
      }
    } catch (_) {
      // Ignore: the record is kept regardless.
    }
  }

  @override
  Future<void> renameFile(String downloadId, String newFileName) async {
    if (newFileName.isEmpty || p.basename(newFileName) != newFileName) {
      throw const DownloadError(
        'invalid-name',
        'A file name cannot be empty or contain a path separator.',
      );
    }
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    final target = p.join(record.directory, newFileName);
    if (_isDestinationTaken(target)) {
      throw DownloadError(
        'file-exists',
        'Destination already exists: $target',
      );
    }
    try {
      File(record.destinationPath).renameSync(target);
    } on FileSystemException catch (e) {
      throw DownloadError('rename-failed', e.message);
    }
    _store.upsertDownload(record.copyWith(fileName: newFileName));
  }

  @override
  Future<void> moveFile(String downloadId, String directory) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (!Directory(directory).existsSync()) {
      throw DownloadError(
        'invalid-directory',
        'The directory does not exist: $directory',
      );
    }
    final target = p.join(directory, record.fileName);
    if (_isDestinationTaken(target)) {
      throw DownloadError(
        'file-exists',
        'Destination already exists: $target',
      );
    }
    final source = File(record.destinationPath);
    try {
      source.renameSync(target);
    } on FileSystemException {
      // Cross-filesystem move (e.g. a USB drive): copy, then delete
      // the original. A failed copy leaves the original in place.
      try {
        await source.copy(target);
      } on FileSystemException catch (e) {
        final partial = File(target);
        if (partial.existsSync()) {
          partial.deleteSync();
        }
        throw DownloadError('move-failed', e.message);
      }
      source.deleteSync();
    }
    _store.upsertDownload(record.copyWith(directory: directory));
  }

  @override
  Future<void> changeUrl(String downloadId, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const DownloadError(
        'invalid-url',
        'URL must start with http:// or https://',
      );
    }
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    // A fresh record clears the stale validators: the old eTag /
    // lastModified belong to the old URL and would send a wrong
    // If-Range on Retry. Status, bytes and size are kept.
    _store.upsertDownload(
      DownloadRecord(
        id: record.id,
        url: url,
        fileName: record.fileName,
        directory: record.directory,
        status: record.status,
        downloadedBytes: record.downloadedBytes,
        totalBytes: record.totalBytes,
        priority: record.priority,
        maxConnections: record.maxConnections,
        mirrors: record.mirrors,
        tags: record.tags,
        createdAt: record.createdAt,
      ),
    );
  }

  @override
  Future<void> addMirror(String downloadId, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const DownloadError(
        'invalid-url',
        'URL must start with http:// or https://',
      );
    }
    final record = _store.getDownload(downloadId);
    if (record == null) return;
    if (record.mirrors.contains(url)) return;
    _store.upsertDownload(
      record.copyWith(mirrors: [...record.mirrors, url]),
    );
  }

  @override
  Future<void> addTag(String downloadId, String tag) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) {
      throw const DownloadError('invalid-tag', 'A tag cannot be empty.');
    }
    final record = _store.getDownload(downloadId);
    if (record == null) return;
    if (record.tags.contains(trimmed)) return;
    _store.upsertDownload(
      record.copyWith(tags: [...record.tags, trimmed]),
    );
  }

  @override
  Future<void> removeTag(String downloadId, String tag) async {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) {
      throw const DownloadError('invalid-tag', 'A tag cannot be empty.');
    }
    final record = _store.getDownload(downloadId);
    if (record == null) return;
    if (!record.tags.contains(trimmed)) return;
    _store.upsertDownload(
      record.copyWith(
        tags: record.tags.where((t) => t != trimmed).toList(),
      ),
    );
  }

  @override
  Future<UpdateCheckResult> checkForUpdate(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      throw const DownloadError('not-found', 'Download not found');
    }
    if (_isYtDlpDownload(record)) {
      // yt-dlp decides the size at download time; probing the
      // playlist file itself would report the playlist's own size.
      return const UpdateCheckResult(
        hasUpdate: false,
        inconclusive: true,
        newTotalBytes: -1,
      );
    }
    final info = await _transport.probe(Uri.parse(record.url));
    final newSize = info.contentLength;
    // The record does not store the server's eTag / lastModified
    // (the engine never persists response validators), so the size
    // is the only comparable signal.
    if (newSize == null || record.totalBytes < 0) {
      return UpdateCheckResult(
        hasUpdate: false,
        inconclusive: true,
        newTotalBytes: newSize ?? -1,
      );
    }
    return UpdateCheckResult(
      hasUpdate: newSize != record.totalBytes,
      inconclusive: false,
      newTotalBytes: newSize,
    );
  }

  @override
  Future<IntegrityResult> verifyFile(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      throw const DownloadError('not-found', 'Download not found');
    }
    return const IntegrityVerifier().verify(
      path: record.destinationPath,
      expectedBytes: record.totalBytes,
    );
  }

  @override
  Future<void> setPriority(String downloadId, int priority) async {
    _scheduler.setPriority(downloadId, priority);
    final record = _store.getDownload(downloadId);
    if (record != null) {
      _store.upsertDownload(record.copyWith(priority: priority));
    }
  }

  @override
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {
    _limiter.setGlobalLimit(bytesPerSecond);
  }

  @override
  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {
    _limiter.setDownloadLimit(downloadId, bytesPerSecond);
  }

  @override
  Future<List<DownloadInfo>> listDownloads() async {
    return _store.listDownloads().map(_infoFromRecord).toList();
  }

  @override
  Future<List<DownloadSegment>> getSegments(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return [];
    }
    if (_isYtDlpDownload(record)) {
      // yt-dlp downloads have no segments: report the whole file as
      // one segment so the PROGRESS tab still shows a bitmap.
      return [
        DownloadSegment(
          segmentId: 0,
          start: 0,
          end: record.totalBytes > 0 ? record.totalBytes - 1 : null,
          downloaded: record.downloadedBytes,
        ),
      ];
    }
    final live = _scheduler.liveSegments(downloadId);
    if (live != null) {
      return live
          .map(
            (s) => DownloadSegment(
              segmentId: s.segmentId,
              start: s.start,
              end: s.end,
              downloaded: s.downloaded,
            ),
          )
          .toList();
    }
    return _store
        .getSegments(downloadId)
        .map(
          (s) => DownloadSegment(
            segmentId: s.segmentId,
            start: s.start,
            end: s.end,
            downloaded: s.downloaded,
          ),
        )
        .toList();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // The scheduler's shutdown cancels paused tasks; remember them so
    // their records stay paused and the next startup can resume them.
    final paused = _store
        .listNonTerminal()
        .where((r) => r.status == DownloadStatus.paused)
        .toList();
    await _ytDlp?.shutdown();
    // Iterate a snapshot: the map is not touched again below, and a
    // subscription cancelled here can deliver a last event. Clearing
    // it is what leaves the count at zero after shutdown.
    final subs = _ytDlpSubs.values.toList();
    _ytDlpSubs.clear();
    for (final sub in subs) {
      await sub.cancel();
    }
    await _schedulerSub?.cancel();
    await _scheduler.dispose();
    _requestHeaders.clear();
    _ytDlpFormats.clear();
    _intentSeq.clear();
    _probeCache.clear();
    await _writer.dispose();
    await _events.close();
    for (final record in paused) {
      final current = _store.getDownload(record.id);
      if (current != null && current.status == DownloadStatus.cancelled) {
        _store.upsertDownload(
          current.copyWith(status: DownloadStatus.paused),
        );
      }
    }
    _limiter.dispose();
    _transport.close();
    _storeClosed = true;
    _store.close();
  }

  Future<ScheduledTask> _taskFactory(DownloadJob job) async {
    try {
      final sink = job.resumeExisting
          ? await FileChunkSink.openExisting(
              partialPath: p.join(job.directory, '${job.fileName}.partial'),
              filePath: p.join(job.directory, job.fileName),
            )
          : await FileChunkSink.create(
              directory: job.directory,
              fileName: job.fileName,
              overwrite: job.overwrite,
            );
      final task = DownloadTask(
        transport: _transport,
        sink: sink,
        url: Uri.parse(job.url),
        id: job.id,
        maxConnections: job.maxConnections,
        limiter: _limiter,
        priority: job.priority,
        resumeFrom: job.resumeFrom,
        cookie: job.cookie,
        referrer: job.referrer,
      );
      _writer.track(
        task,
        directory: job.directory,
        fileName: job.fileName,
        priority: job.priority,
      );
      return ScheduledTask(
        task,
        sink,
        // The scheduler may throw this task away without running it (a
        // retry replaced the attempt, or the user cancelled while the
        // factory was building). Untrack it then: its snapshot says
        // queued with zero bytes, and every checkpoint tick would write
        // that over the row — a cancelled download came back as queued,
        // and the next startup downloaded it again.
        onAbandoned: () => _writer.untrack(job.id),
      );
    } catch (e) {
      // The task never started, so no events will update the store.
      // Mark the record failed here so it does not stay queued forever
      // — unless the user cancelled the row while the factory was
      // running: the scheduler already announced cancelled for it, and
      // the failure of a start nobody waits for any more must not put
      // Failed on a row the user dismissed.
      final record = _store.getDownload(job.id);
      if (record != null && record.status != DownloadStatus.cancelled) {
        _store.upsertDownload(
          record.copyWith(
            status: DownloadStatus.failed,
            errorCode: 'factory-failed',
            errorMessage: e.toString(),
          ),
        );
      }
      rethrow;
    }
  }

  /// Resumes a yt-dlp record after a restart. If the tools are
  /// missing the record is marked failed with a clear error instead
  /// of staying queued forever. A pause, cancel or delete that landed
  /// while the tools were resolving wins: recovery started on its own,
  /// before the user could act, so their later action is the intent
  /// that must stick.
  Future<void> _resumeYtDlp(DownloadRecord record) async {
    // Claim the recovery's intent synchronously, before its first
    // await. Recovery starts on its own at open, before the user can
    // act; any later pause, cancel, delete or start bumps the sequence
    // and wins.
    final seq = _claimIntent(record.id);
    final downloader = await _ytDlpDownloader();
    if (!_intentCurrent(record.id, seq)) {
      return;
    }
    final current = _liveRecord(record.id);
    if (current == null) {
      // Deleted while the tools were resolving.
      return;
    }
    if (current.status == DownloadStatus.paused ||
        _isTerminalStatus(current.status)) {
      // Paused, cancelled or finished in the meantime: leave it alone
      // rather than start a transfer the user already stopped.
      return;
    }
    if (downloader == null) {
      _store.upsertDownload(
        record.copyWith(
          status: DownloadStatus.failed,
          errorCode: 'external-tools-missing',
          errorMessage:
              'ffmpeg and yt-dlp are required to download streams.',
        ),
      );
      // The UI learns state only from events, and the initial snapshot
      // showed this row queued: without this event it would sit there
      // as a download that never starts. A `failed` event (not just a
      // state change) is what carries the error message, so the row
      // does not show Failed with an empty reason.
      _events.add(
        DownloadEvent.failed(
          downloadId: record.id,
          code: 'external-tools-missing',
          message: 'ffmpeg and yt-dlp are required to download streams.',
        ),
      );
      return;
    }
    _startYtDlp(record, downloader);
  }

  void _recover() {
    // Seed the scheduler's id counter from every stored record, so a
    // generated id can never collide with a record recovery does not
    // re-enqueue. Recovery only re-enqueues non-terminal downloads;
    // with every download terminal the counter would restart at 0 and
    // the next retry (or new download) would overwrite dl-1, then
    // dl-2, and so on, with the retried file's data.
    for (final record in _store.listDownloads()) {
      _scheduler.reserveId(record.id);
      _reserveYtId(record.id);
    }
    // yt-dlp records are recovered separately: the segment-based
    // Recovery does not understand yt-dlp partials, so its decisions
    // for them would be wrong. A paused yt-dlp download stays paused;
    // a queued/downloading one is resumed through the downloader
    // (yt-dlp resumes from its partial when present). Terminal
    // records are left alone.
    final ytDlpRecords = <DownloadRecord>[];
    final nativeDecisions = <RecoveryDecision>[];
    for (final decision in Recovery(_store).reconcile()) {
      if (_isYtDlpDownload(decision.record)) {
        ytDlpRecords.add(decision.record);
      } else {
        nativeDecisions.add(decision);
      }
    }
    for (final record in ytDlpRecords) {
      final paused = record.status == DownloadStatus.paused;
      if (record.status == DownloadStatus.completed ||
          record.status == DownloadStatus.failed ||
          record.status == DownloadStatus.cancelled) {
        continue;
      }
      _store.upsertDownload(
        record.copyWith(
          status: paused ? DownloadStatus.paused : DownloadStatus.queued,
        ),
      );
      if (!paused) {
        unawaited(_resumeYtDlp(record));
      }
    }
    for (final decision in nativeDecisions) {
      final record = decision.record;
      // A paused download is a deliberate user state, not a crash:
      // it is restored as a paused job so it does not start again on
      // restart. The resume/restart setup still applies, so resuming
      // it later resumes from the right place. Only queued and
      // downloading records resume automatically.
      final paused = record.status == DownloadStatus.paused;
      switch (decision.action) {
        case RecoveryAction.resume:
          _scheduler.enqueue(
            id: record.id,
            url: record.url,
            fileName: record.fileName,
            directory: record.directory,
            priority: record.priority,
            maxConnections: record.maxConnections,
            resumeFrom: decision.segments
                .map(
                  (s) => SegmentProgress(
                    segmentId: s.segmentId,
                    start: s.start,
                    end: s.end,
                    downloaded: s.downloaded,
                  ),
                )
                .toList(),
            resumeExisting: true,
            paused: paused,
          );
          if (!paused) {
            _store.upsertDownload(
              record.copyWith(status: DownloadStatus.queued),
            );
          }
        case RecoveryAction.restart:
          final partial = File(record.partialPath);
          if (partial.existsSync()) {
            partial.deleteSync();
          }
          _scheduler.enqueue(
            id: record.id,
            url: record.url,
            fileName: record.fileName,
            directory: record.directory,
            priority: record.priority,
            maxConnections: record.maxConnections,
            paused: paused,
          );
          _store.upsertDownload(
            record.copyWith(
              status:
                  paused ? DownloadStatus.paused : DownloadStatus.queued,
              downloadedBytes: 0,
              totalBytes: -1,
            ),
          );
        case RecoveryAction.complete:
          break;
        case RecoveryAction.unrecoverable:
          _store.upsertDownload(
            record.copyWith(
              status: DownloadStatus.failed,
              errorCode: 'unrecoverable',
              errorMessage: decision.reason,
            ),
          );
      }
    }
  }

  void _updateStatus(String id, DownloadStatus status) {
    final record = _liveRecord(id);
    if (record != null) {
      _store.upsertDownload(record.copyWith(status: status));
    }
  }

  /// The stored record for [downloadId], or null once the engine has
  /// been disposed.
  ///
  /// Every action awaits at least once, and the app can quit during
  /// that await: [dispose] closes the store, so reading it afterwards
  /// throws out of a fire-and-forget UI action. A disposed engine has
  /// no row to act on, which is what null already means to the
  /// callers.
  DownloadRecord? _liveRecord(String downloadId) {
    if (_disposed) return null;
    return _store.getDownload(downloadId);
  }

  /// The stored record for [downloadId] while the store is still
  /// open, or null once [dispose] closed it.
  ///
  /// For event handlers only: they run after [_disposed] is set but
  /// before the store closes, and a terminal event of a finished run
  /// still has to settle its row (see [_onYtDlpEvent]). Unlike
  /// [_liveRecord], this does not pretend a disposing engine has no
  /// row — an action must not write one.
  DownloadRecord? _storedRecord(String downloadId) {
    if (_storeClosed) return null;
    return _store.getDownload(downloadId);
  }

  /// Records a new intent for [downloadId] and returns its sequence.
  ///
  /// Synchronous by design: every action calls this before its first
  /// await, so an action that is still resolving knows, the moment it
  /// resumes, whether a later action took the download over.
  int _claimIntent(String downloadId) {
    final next = (_intentSeq[downloadId] ?? 0) + 1;
    _intentSeq[downloadId] = next;
    return next;
  }

  /// True when [seq] is still the latest intent for [downloadId]: no
  /// pause, resume, cancel, retry, delete or recovery has been issued
  /// since. A finishing action that sees false must not touch the
  /// store, the output or the run: the newer action owns the outcome.
  bool _intentCurrent(String downloadId, int seq) =>
      _intentSeq[downloadId] == seq;

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('PdmEngine disposed');
    }
  }

  DownloadInfo _infoFromRecord(DownloadRecord record) {
    return DownloadInfo(
      id: record.id,
      url: record.url,
      fileName: record.fileName,
      status: record.status,
      downloadedBytes: record.downloadedBytes,
      totalBytes: record.totalBytes,
      createdAt: record.createdAt,
      filePath: record.destinationPath,
      priority: record.priority,
      tags: record.tags,
      errorCode: record.errorCode,
      errorMessage: record.errorMessage,
    );
  }
}
