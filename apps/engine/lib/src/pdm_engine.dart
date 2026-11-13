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
    YtDlpDownloader? ytDlpDownloader,
  })  : _store = store,
        _scheduler = scheduler,
        _writer = writer,
        _limiter = limiter,
        _transport = transport,
        _externalTools = externalTools,
        _ytDlp = ytDlpDownloader;

  factory PdmEngine.open({
    EngineConfig config = const EngineConfig(),
    String? databasePath,
    BandwidthLimiter? limiter,
    ExternalTools? externalTools,
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

  /// Lazily resolved external tools (injected in tests).
  ExternalTools? _externalTools;

  /// Lazily created yt-dlp downloader (injected in tests).
  YtDlpDownloader? _ytDlp;

  /// Merged event stream: scheduler events plus yt-dlp events.
  final _events = StreamController<DownloadEvent>.broadcast();
  StreamSubscription<DownloadEvent>? _schedulerSub;
  final _ytDlpSubs = <String, StreamSubscription<DownloadEvent>>{};

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
  Future<YtDlpDownloader?> _ytDlpDownloader() async {
    if (_ytDlp != null) {
      return _ytDlp;
    }
    final tools = _externalTools ?? await ExternalTools.resolve();
    _externalTools = tools;
    if (!tools.available) {
      return null;
    }
    _ytDlp = YtDlpDownloader(
      ytDlpPath: tools.ytDlpPath!,
      ffmpegDir: p.dirname(tools.ffmpegPath!),
    );
    return _ytDlp;
  }

  /// The yt-dlp `-o` template for a record: the file stem with
  /// `%(ext)s`, so yt-dlp chooses the container (mp4/mkv) itself.
  String _ytDlpTemplate(DownloadRecord record) {
    final stem = p.basenameWithoutExtension(record.fileName);
    return p.join(record.directory, '$stem.%(ext)s');
  }

  /// Starts a yt-dlp download for [record] and wires its events into
  /// the engine event stream and the store.
  void _startYtDlp(DownloadRecord record, YtDlpDownloader downloader) {
    final sub = downloader
        .start(
          downloadId: record.id,
          url: record.url,
          outputTemplate: _ytDlpTemplate(record),
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
        final record = _store.getDownload(downloadId);
        if (record != null) {
          final file = File(filePath);
          final size =
              file.existsSync() ? file.lengthSync() : record.totalBytes;
          // The file name is the real file yt-dlp produced, which
          // may differ from the playlist name (live.m3u8 -> live.mp4).
          // destinationPath is derived from directory + fileName, so
          // it follows automatically.
          _store.upsertDownload(
            record.copyWith(
              status: DownloadStatus.completed,
              fileName: p.basename(filePath),
              downloadedBytes: size,
              totalBytes: size,
            ),
          );
        }
        _pruneYtDlpSub(downloadId);
      },
      failed: (downloadId, code, message) {
        final record = _store.getDownload(downloadId);
        if (record != null) {
          _store.upsertDownload(
            record.copyWith(
              status: DownloadStatus.failed,
              errorCode: code,
              errorMessage: message,
            ),
          );
        }
        _pruneYtDlpSub(downloadId);
      },
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
    switch (request.conflictPolicy) {
      case FileConflictPolicy.overwrite:
        // Proceed: the sink rename at the end replaces the file.
        break;
      case FileConflictPolicy.rename:
        fileName = p.basename(
          resolveUniquePath(destPath, isTaken: _isDestinationTaken),
        );
      case null:
        if (File(destPath).existsSync()) {
          throw DownloadError(
            'file-exists',
            'Destination already exists: $destPath',
          );
        }
    }
    if (_isStreamingPlaylist(request.url)) {
      final downloader = await _ytDlpDownloader();
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to download streams. '
          'They are bundled with PDM; check the app bundle.',
        );
      }
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
    if (_isStreamingPlaylist(record.url)) {
      await _ytDlp?.pause(downloadId);
      _updateStatus(downloadId, DownloadStatus.paused);
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
    if (_isStreamingPlaylist(record.url)) {
      final downloader = await _ytDlpDownloader();
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to resume this download.',
        );
      }
      _updateStatus(downloadId, DownloadStatus.queued);
      _startYtDlp(record, downloader);
      return;
    }
    _scheduler.resume(downloadId);
    _updateStatus(downloadId, DownloadStatus.queued);
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    _requestHeaders.remove(downloadId);
    final record = _store.getDownload(downloadId);
    if (record != null && _isStreamingPlaylist(record.url)) {
      await _ytDlp?.cancel(downloadId);
      _updateStatus(downloadId, DownloadStatus.cancelled);
      return;
    }
    _scheduler.cancel(downloadId);
    _updateStatus(downloadId, DownloadStatus.cancelled);
  }

  @override
  Future<void> retryDownload(String downloadId) async {
    _mirrorIndex.remove(downloadId);
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isStreamingPlaylist(record.url)) {
      final downloader = await _ytDlpDownloader();
      if (downloader == null) {
        throw const DownloadError(
          'external-tools-missing',
          'ffmpeg and yt-dlp are required to retry this download.',
        );
      }
      downloader.deleteOutput(_ytDlpTemplate(record));
      final ytPartial = File(record.partialPath);
      if (ytPartial.existsSync()) {
        ytPartial.deleteSync();
      }
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
      _startYtDlp(record, downloader);
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
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isStreamingPlaylist(record.url)) {
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
    _store.deleteDownload(downloadId);
  }

  @override
  Future<void> deleteFile(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    if (_isStreamingPlaylist(record.url)) {
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
    if (_isStreamingPlaylist(record.url)) {
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
    if (_isStreamingPlaylist(record.url)) {
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
    for (final sub in _ytDlpSubs.values) {
      await sub.cancel();
    }
    await _schedulerSub?.cancel();
    await _scheduler.dispose();
    _requestHeaders.clear();
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
      return ScheduledTask(task, sink);
    } catch (e) {
      // The task never started, so no events will update the store.
      // Mark the record failed here so it does not stay queued forever.
      final record = _store.getDownload(job.id);
      if (record != null) {
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
  /// of staying queued forever.
  Future<void> _resumeYtDlp(DownloadRecord record) async {
    final downloader = await _ytDlpDownloader();
    if (downloader == null) {
      _store.upsertDownload(
        record.copyWith(
          status: DownloadStatus.failed,
          errorCode: 'external-tools-missing',
          errorMessage:
              'ffmpeg and yt-dlp are required to download streams.',
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
      if (_isStreamingPlaylist(decision.record.url)) {
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
    final record = _store.getDownload(id);
    if (record != null) {
      _store.upsertDownload(record.copyWith(status: status));
    }
  }

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
