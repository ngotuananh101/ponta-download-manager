import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_recovery/download_recovery.dart';
import 'package:download_scheduler/download_scheduler.dart';
import 'package:download_storage/download_storage.dart';
import 'package:download_transport/download_transport.dart';
import 'package:path/path.dart' as p;

import 'engine_config.dart';

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
  })  : _store = store,
        _scheduler = scheduler,
        _writer = writer,
        _limiter = limiter,
        _transport = transport;

  factory PdmEngine.open({
    EngineConfig config = const EngineConfig(),
    String? databasePath,
    BandwidthLimiter? limiter,
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

  @override
  Stream<DownloadEvent> get events => _scheduler.events;

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
    if (File(p.join(directory, fileName)).existsSync()) {
      throw DownloadError(
        'file-exists',
        'Destination already exists: ${p.join(directory, fileName)}',
      );
    }
    final id = _scheduler.enqueue(
      url: request.url,
      fileName: fileName,
      directory: directory,
      priority: request.priority ?? 0,
      maxConnections:
          request.maxConnections ?? config.maxConnectionsPerDownload,
    );
    final record = DownloadRecord(
      id: id,
      url: request.url,
      fileName: fileName,
      directory: directory,
      status: DownloadStatus.queued,
      priority: request.priority ?? 0,
      maxConnections:
          request.maxConnections ?? config.maxConnectionsPerDownload,
    );
    _store.upsertDownload(record);
    return _infoFromRecord(record);
  }

  @override
  Future<void> pauseDownload(String downloadId) async {
    _scheduler.pause(downloadId);
    _updateStatus(downloadId, DownloadStatus.paused);
  }

  @override
  Future<void> resumeDownload(String downloadId) async {
    _scheduler.resume(downloadId);
    _updateStatus(downloadId, DownloadStatus.queued);
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    _scheduler.cancel(downloadId);
    _updateStatus(downloadId, DownloadStatus.cancelled);
  }

  @override
  Future<void> retryDownload(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
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
    _scheduler.enqueue(
      id: downloadId,
      url: record.url,
      fileName: record.fileName,
      directory: record.directory,
      priority: record.priority,
      maxConnections: record.maxConnections,
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
      ),
    );
  }

  @override
  Future<void> deleteDownload(String downloadId) async {
    final record = _store.getDownload(downloadId);
    if (record == null) {
      return;
    }
    // Stop the download if it is running or queued. The scheduler
    // keeps a stale cancelled entry for the id, which is harmless:
    // the engine lists downloads from the store, not the scheduler.
    _scheduler.cancel(downloadId);
    // Drop the partial file so it does not linger as an orphan. The
    // finished file (if any) is kept on disk.
    final partial = File(record.partialPath);
    if (partial.existsSync()) {
      partial.deleteSync();
    }
    _store.deleteDownload(downloadId);
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
    await _scheduler.dispose();
    await _writer.dispose();
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

  void _recover() {
    // Seed the scheduler's id counter from every stored record, so a
    // generated id can never collide with a record recovery does not
    // re-enqueue. Recovery only re-enqueues non-terminal downloads;
    // with every download terminal the counter would restart at 0 and
    // the next retry (or new download) would overwrite dl-1, then
    // dl-2, and so on, with the retried file's data.
    for (final record in _store.listDownloads()) {
      _scheduler.reserveId(record.id);
    }
    for (final decision in Recovery(_store).reconcile()) {
      final record = decision.record;
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
          );
          _store.upsertDownload(
            record.copyWith(status: DownloadStatus.queued),
          );
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
          );
          _store.upsertDownload(
            record.copyWith(
              status: DownloadStatus.queued,
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
    );
  }
}
