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

  void _onEvent(DownloadEvent event) {
    event.when(
      progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {
        final current = _downloads[downloadId];
        if (current == null) {
          return;
        }
        _downloads[downloadId] = current.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          bytesPerSecond: bytesPerSecond,
          state: DownloadState.downloading,
        );
        _progressDirty = true;
      },
      stateChanged: (downloadId, status) {
        final current = _downloads[downloadId];
        if (current == null) {
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
        );
        _emit();
      },
      completed: (downloadId, filePath) {
        final current = _downloads[downloadId];
        if (current == null) {
          return;
        }
        _downloads[downloadId] = current.copyWith(
          state: DownloadState.completed,
          bytesPerSecond: 0,
        );
        _emit();
      },
      failed: (downloadId, code, message) {
        final current = _downloads[downloadId];
        if (current == null) {
          return;
        }
        _downloads[downloadId] = current.copyWith(
          state: DownloadState.failed,
          bytesPerSecond: 0,
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

  Future<DownloadInfo> addDownload(String url) async {
    final fileName = _fileNameFromUrl(url);
    final info = await engine.createDownload(
      CreateDownloadRequest(
        url: url,
        destination: p.join(downloadDirectory, fileName),
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

  Future<void> deleteDownload(String id) async {
    await engine.deleteDownload(id);
    // The delete is the source of truth for removing the row, like
    // the create response is for adding one.
    _downloads.remove(id);
    _emit();
  }

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
