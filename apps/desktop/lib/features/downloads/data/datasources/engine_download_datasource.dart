import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pdm_engine/pdm_engine.dart';

import '../../domain/entities/download.dart';
import 'download_mapper.dart';

/// The downloads datasource backed by the engine running in this
/// process (§11.3: UI state is derived from engine snapshots and
/// events). It owns the [PdmEngine] — disposing the datasource
/// disposes the engine — and throttles high-frequency progress
/// events before emitting: progress only marks the list dirty and a
/// periodic timer flushes it, while state changes emit immediately.
class EngineDownloadDatasource {
  EngineDownloadDatasource({
    required this.engine,
    required this.downloadDirectory,
    this.progressEmitInterval = const Duration(milliseconds: 500),
  }) {
    _eventSub = engine.events.listen(_onEvent);
    _progressTimer = Timer.periodic(progressEmitInterval, (_) {
      if (_progressDirty) {
        _progressDirty = false;
        _emit();
      }
    });
    unawaited(_loadInitial());
  }

  final PdmEngine engine;
  final String downloadDirectory;
  final Duration progressEmitInterval;

  static final _log = Logger('EngineDownloadDatasource');

  final _downloads = <String, Download>{};
  final _controller = StreamController<List<Download>>.broadcast();
  StreamSubscription<DownloadEvent>? _eventSub;
  Timer? _progressTimer;
  var _progressDirty = false;
  var _disposed = false;
  final _refreshing = <String>{};

  /// The current list first, then every update.
  ///
  /// Each subscriber gets its own controller: the current list is
  /// added and the forwarding subscription is attached synchronously
  /// in `onListen`, so an update emitted right after subscribing
  /// cannot slip in before the forwarder is attached (a broadcast
  /// stream would drop it).
  Stream<List<Download>> watchDownloads() {
    late StreamSubscription<List<Download>> sub;
    final controller = StreamController<List<Download>>();
    controller.onListen = () {
      sub = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.add(_downloads.values.toList());
    };
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  /// Per-segment progress for the details panel's PROGRESS tab.
  Future<List<DownloadSegment>> getSegments(String downloadId) =>
      engine.getSegments(downloadId);

  Future<void> _loadInitial() async {
    try {
      final infos = await engine.listDownloads();
      for (final info in infos) {
        _downloads[info.id] = downloadFromInfo(info);
      }
      _emit();
    } catch (e) {
      _log.warning('Failed to load the initial download list: $e');
    }
  }

  // Downloads created outside this datasource (e.g. via the IPC
  // server when the browser extension adds one) are not in
  // [_downloads]: their events would be dropped and the row would
  // never appear until the next full reload. When an event arrives
  // for an unknown id, refresh that download from the engine.
  Future<void> _refreshDownload(String downloadId) async {
    if (!_refreshing.add(downloadId)) {
      return;
    }
    try {
      final infos = await engine.listDownloads();
      for (final info in infos) {
        if (info.id == downloadId) {
          _downloads[downloadId] = downloadFromInfo(info);
          _emit();
          break;
        }
      }
    } catch (e) {
      _log.warning('Failed to refresh download $downloadId: $e');
    } finally {
      _refreshing.remove(downloadId);
    }
  }

  void _onEvent(DownloadEvent event) {
    event.when(
      progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {
        final current = _downloads[downloadId];
        if (current == null) {
          unawaited(_refreshDownload(downloadId));
          return;
        }
        // A progress event must not revive a paused (or terminal)
        // download: after Pause, one in-flight chunk can still emit
        // progress, and forcing the state to downloading would flick
        // the row back to "Downloading" with the old % even though
        // the download has stopped. The bytes still update (that
        // chunk really was downloaded).
        final stopped = current.state == DownloadState.paused ||
            current.state == DownloadState.cancelled ||
            current.state == DownloadState.failed ||
            current.state == DownloadState.completed ||
            current.state == DownloadState.missing;
        _downloads[downloadId] = current.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          bytesPerSecond: bytesPerSecond,
          state: stopped ? current.state : DownloadState.downloading,
          // Progress means it is running again, so a previous
          // failure reason no longer applies.
          clearErrorMessage: !stopped,
        );
        _progressDirty = true;
      },
      stateChanged: (downloadId, status) {
        final current = _downloads[downloadId];
        if (current == null) {
          unawaited(_refreshDownload(downloadId));
          return;
        }
        final state = downloadStateFromStatus(status);
        // A download that is no longer running has no speed; reset it
        // so a paused/cancelled/failed row does not keep its last
        // measured rate.
        final stopped = state == DownloadState.paused ||
            state == DownloadState.cancelled ||
            state == DownloadState.failed;
        _downloads[downloadId] = current.copyWith(
          state: state,
          bytesPerSecond: stopped ? 0 : current.bytesPerSecond,
          // A state change away from failed clears the failure
          // reason; a change to failed keeps it until the failed
          // event below carries the message.
          clearErrorMessage: state != DownloadState.failed,
        );
        _emit();
      },
      completed: (downloadId, filePath) {
        final current = _downloads[downloadId];
        if (current == null) {
          unawaited(_refreshDownload(downloadId));
          return;
        }
        _downloads[downloadId] = current.copyWith(
          state: DownloadState.completed,
          bytesPerSecond: 0,
          clearErrorMessage: true,
        );
        _emit();
      },
      failed: (downloadId, code, message) {
        final current = _downloads[downloadId];
        if (current == null) {
          unawaited(_refreshDownload(downloadId));
          return;
        }
        _downloads[downloadId] = current.copyWith(
          state: DownloadState.failed,
          bytesPerSecond: 0,
          errorMessage: message,
        );
        _emit();
      },
    );
  }

  void _emit() {
    if (_disposed || _controller.isClosed) {
      return;
    }
    _controller.add(_downloads.values.toList());
  }

  /// Probes a URL before creating a download: the file name the
  /// server reports (or the URL's last segment) and the total size.
  Future<ProbeResult> probeUrl(String url) => engine.probeUrl(url);

  Future<DownloadInfo> addDownload(
    String url, {
    String? directory,
    String? fileName,
    FileConflictPolicy? conflictPolicy,
    bool paused = false,
  }) async {
    final info = await engine.createDownload(
      CreateDownloadRequest(
        url: url,
        destination: p.join(
          directory ?? downloadDirectory,
          fileName ?? _fileNameFromUrl(url),
        ),
        conflictPolicy: conflictPolicy,
        paused: paused,
      ),
    );
    // The create response is the source of truth for the new
    // download: it joins the list now, and later events update it.
    _downloads[info.id] = downloadFromInfo(info);
    _emit();
    return info;
  }

  Future<void> pauseDownload(String id) => engine.pauseDownload(id);

  Future<void> resumeDownload(String id) => engine.resumeDownload(id);

  Future<void> cancelDownload(String id) => engine.cancelDownload(id);

  Future<void> retryDownload(String id) => engine.retryDownload(id);

  /// Queue priority: the engine emits no event for a priority
  /// change, so the local row is updated here, like delete removes
  /// it.
  Future<void> setPriority(String id, int priority) async {
    await engine.setPriority(id, priority);
    final current = _downloads[id];
    if (current != null) {
      _downloads[id] = current.copyWith(priority: priority);
      _emit();
    }
  }

  Future<void> deleteDownload(String id, {bool deleteFile = false}) async {
    await engine.deleteDownload(id, deleteFile: deleteFile);
    // The delete is the source of truth for removing the row, like
    // the create response is for adding one.
    _downloads.remove(id);
    _emit();
  }

  /// Deletes the finished file and keeps the row: the refresh
  /// re-reads the record, so the mapper shows it as Missing.
  Future<void> deleteFile(String id) async {
    await engine.deleteFile(id);
    await _refreshDownload(id);
  }

  /// Renames the finished file: the refresh re-reads the record,
  /// so the row shows the new name.
  Future<void> renameFile(String id, String newFileName) async {
    await engine.renameFile(id, newFileName);
    await _refreshDownload(id);
  }

  /// Moves the finished file: the refresh re-reads the record, so
  /// the row shows the new path.
  Future<void> moveFile(String id, String directory) async {
    await engine.moveFile(id, directory);
    await _refreshDownload(id);
  }

  /// Changes the download's URL: the refresh re-reads the record.
  Future<void> changeUrl(String id, String url) async {
    await engine.changeUrl(id, url);
    await _refreshDownload(id);
  }

  /// Checks the server for a newer version. Read-only: nothing is
  /// written, so no refresh is needed.
  Future<UpdateCheckResult> checkForUpdate(String id) =>
      engine.checkForUpdate(id);

  Future<IntegrityResult> verifyFile(String id) => engine.verifyFile(id);

  /// Snail mode: a global speed cap (null = unlimited). Forwarded to
  /// the engine's token-bucket limiter.
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) =>
      engine.setGlobalBandwidthLimit(bytesPerSecond);

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const [];
    final last = segments.isNotEmpty ? segments.last : '';
    return last.isNotEmpty ? last : 'download';
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _progressTimer?.cancel();
    await _eventSub?.cancel();
    await engine.dispose();
    // Fire-and-forget: a StreamController.close() future only
    // completes once a listener consumes the done event.
    unawaited(_controller.close());
  }
}
