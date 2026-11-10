import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/download.dart';

Download downloadFromInfo(DownloadInfo info) {
  return Download(
    id: info.id,
    url: info.url,
    fileName: info.fileName,
    state: _stateFromStatus(info.status),
    downloadedBytes: info.downloadedBytes,
    totalBytes: info.totalBytes,
    bytesPerSecond: info.bytesPerSecond,
  );
}

DownloadState _stateFromStatus(DownloadStatus status) {
  return switch (status) {
    DownloadStatus.queued => DownloadState.queued,
    DownloadStatus.downloading => DownloadState.downloading,
    DownloadStatus.paused => DownloadState.paused,
    DownloadStatus.completed => DownloadState.completed,
    DownloadStatus.failed => DownloadState.failed,
    DownloadStatus.cancelled => DownloadState.cancelled,
  };
}

/// The downloads datasource backed by a real engine over IPC (§11.3:
/// UI state is derived from engine snapshots and events). It owns
/// one [IpcClient], reconnects with backoff while the engine is
/// down, and throttles high-frequency progress events before
/// emitting: progress only marks the list dirty and a periodic timer
/// flushes it, while state changes emit immediately.
class IpcDownloadDatasource {
  IpcDownloadDatasource({
    required Future<IpcClient> Function() clientFactory,
    required this.downloadDirectory,
    this.progressEmitInterval = const Duration(milliseconds: 500),
    this.reconnectInterval = const Duration(seconds: 5),
  }) : _clientFactory = clientFactory;

  final Future<IpcClient> Function() _clientFactory;
  final String downloadDirectory;
  final Duration progressEmitInterval;
  final Duration reconnectInterval;

  IpcClient? _client;
  final _downloads = <String, Download>{};
  final _controller = StreamController<List<Download>>.broadcast();
  final _connectedController = StreamController<bool>.broadcast();
  StreamSubscription<DownloadEvent>? _eventSub;
  StreamSubscription<List<DownloadInfo>>? _syncSub;
  Timer? _progressTimer;
  Timer? _retryTimer;
  var _progressDirty = false;
  var _connected = false;
  var _disposed = false;

  /// The current list first, then every update.
  Stream<List<Download>> watchDownloads() async* {
    yield _downloads.values.toList();
    yield* _controller.stream;
  }

  /// The current connection state first, then every change.
  Stream<bool> watchConnected() async* {
    yield _connected;
    yield* _connectedController.stream;
  }

  /// Connects once; on failure schedules a retry every
  /// [reconnectInterval] until it succeeds.
  Future<void> connect() async {
    if (_disposed || _client != null) {
      return;
    }
    try {
      final client = await _clientFactory();
      if (_disposed) {
        await client.close();
        return;
      }
      _attach(client);
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _attach(IpcClient client) {
    _client = client;
    _setConnected(true);
    _syncSub = client.syncSnapshots.listen((infos) {
      _downloads.clear();
      for (final info in infos) {
        _downloads[info.id] = downloadFromInfo(info);
      }
      _emit();
    });
    _eventSub = client.events.listen(
      _onEvent,
      onDone: _onClientDone,
      onError: (_) => _onClientDone(),
    );
    _progressTimer ??= Timer.periodic(progressEmitInterval, (_) {
      if (_progressDirty) {
        _progressDirty = false;
        _emit();
      }
    });
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
        _downloads[downloadId] = current.copyWith(
          state: _stateFromStatus(status),
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
        );
        _emit();
      },
    );
  }

  void _onClientDone() {
    if (_disposed) {
      return;
    }
    _detach();
    _scheduleRetry();
  }

  void _detach() {
    final eventSub = _eventSub;
    final syncSub = _syncSub;
    _eventSub = null;
    _syncSub = null;
    _client = null;
    _setConnected(false);
    unawaited(eventSub?.cancel());
    unawaited(syncSub?.cancel());
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) {
      return;
    }
    _retryTimer = Timer(reconnectInterval, () {
      _retryTimer = null;
      unawaited(connect());
    });
  }

  void _setConnected(bool value) {
    if (_connected == value) {
      return;
    }
    _connected = value;
    if (!_connectedController.isClosed) {
      _connectedController.add(value);
    }
  }

  void _emit() {
    if (_disposed || _controller.isClosed) {
      return;
    }
    _controller.add(_downloads.values.toList());
  }

  Future<DownloadInfo> addDownload(String url) async {
    final client = _requireClient();
    final fileName = _fileNameFromUrl(url);
    final info = await client.createDownload(
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

  Future<void> pauseDownload(String id) async {
    await _requireClient().pauseDownload(id);
  }

  Future<void> resumeDownload(String id) async {
    await _requireClient().resumeDownload(id);
  }

  Future<void> cancelDownload(String id) async {
    await _requireClient().cancelDownload(id);
  }

  Future<void> retryDownload(String id) async {
    await _requireClient().retryDownload(id);
  }

  IpcClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw const DownloadError(
        IpcErrorCode.connectionClosed,
        'Engine is not connected',
      );
    }
    return client;
  }

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
    _retryTimer?.cancel();
    _progressTimer?.cancel();
    await _eventSub?.cancel();
    await _syncSub?.cancel();
    await _client?.close();
    // Fire-and-forget: a StreamController.close() future only
    // completes once a listener consumes the done event.
    unawaited(_controller.close());
    unawaited(_connectedController.close());
  }
}
