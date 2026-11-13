import 'dart:async';

import 'package:download_api/download_api.dart';

import 'ipc_channel.dart';
import 'protocol.dart';

/// The UI side of the engine IPC (§4.2). Connects with a `hello`
/// handshake carrying the server token, matches responses to
/// requests by id, decodes engine events, and replays the latest
/// `download.sync` snapshot to every new subscriber, so a client
/// that (re)connects always learns the current state.
/// [reconnect] re-runs the handshake on a fresh channel from the
/// same factory; the server answers with a fresh sync snapshot.
class IpcClient {
  IpcClient._(this._requestTimeout);

  static Future<IpcClient> connect({
    required Future<IpcChannel> Function() channelFactory,
    required String token,
    Duration requestTimeout = const Duration(seconds: 10),
    Duration helloTimeout = const Duration(seconds: 5),
  }) async {
    final client = IpcClient._(requestTimeout)
      .._channelFactory = channelFactory
      .._token = token;
    try {
      await client._bind(await channelFactory(), helloTimeout);
    } catch (e) {
      await client.close();
      rethrow;
    }
    return client;
  }

  final Duration _requestTimeout;
  Future<IpcChannel> Function()? _channelFactory;
  String? _token;
  IpcChannel? _channel;
  StreamSubscription<Map<String, Object?>>? _subscription;
  Completer<void>? _helloCompleter;
  Timer? _helloTimer;
  final _pending = <String, _PendingRequest>{};
  final _events = StreamController<DownloadEvent>.broadcast();
  final _syncs = StreamController<List<DownloadInfo>>.broadcast();
  List<DownloadInfo>? _latestSync;
  var _counter = 0;
  var _closed = false;

  Stream<DownloadEvent> get events => _events.stream;

  /// The latest sync snapshot first (when one was already received),
  /// then every snapshot that follows.
  ///
  /// The replay and the live subscription happen in one synchronous
  /// step: a sync arriving between a replayed snapshot and the live
  /// stream would otherwise be lost on the broadcast [_syncs] stream
  /// (it updates [_latestSync] but the subscriber never sees it).
  Stream<List<DownloadInfo>> get syncSnapshots {
    final controller = StreamController<List<DownloadInfo>>();
    StreamSubscription<List<DownloadInfo>>? sub;
    controller.onListen = () {
      if (_latestSync != null) {
        controller.add(_latestSync!);
      }
      sub = _syncs.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    };
    controller.onCancel = () => sub?.cancel();
    return controller.stream;
  }

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_closed) {
      throw StateError('IpcClient is closed');
    }
    final channel = _channel;
    if (channel == null || channel.isClosed) {
      throw DownloadError(
        IpcErrorCode.connectionClosed,
        'Not connected',
      );
    }
    final id = 'req-${++_counter}';
    final completer = Completer<Map<String, Object?>>();
    late final Timer timer;
    timer = Timer(_requestTimeout, () {
      if (_pending.remove(id) != null && !completer.isCompleted) {
        completer.completeError(
          DownloadError(
            IpcErrorCode.timeout,
            'Request $method timed out',
          ),
        );
      }
    });
    _pending[id] = _PendingRequest(completer, timer);
    try {
      await channel.send({
        'type': 'request',
        'v': ipcProtocolVersion,
        'id': id,
        'method': method,
        'params': params,
      });
    } catch (e) {
      final pending = _pending.remove(id);
      pending?.timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
    return completer.future;
  }

  Future<DownloadInfo> createDownload(CreateDownloadRequest request) async {
    final result = await this.request('download.create', {
      'url': request.url,
      'destination': request.destination,
      if (request.maxConnections != null)
        'maxConnections': request.maxConnections,
      if (request.priority != null) 'priority': request.priority,
      if (request.conflictPolicy != null)
        'conflictPolicy': request.conflictPolicy!.name,
      if (request.cookie != null) 'cookie': request.cookie,
      if (request.referrer != null) 'referrer': request.referrer,
    });
    return downloadInfoFromJson(result);
  }

  Future<void> pauseDownload(String downloadId) async {
    await request('download.pause', {'downloadId': downloadId});
  }

  Future<void> resumeDownload(String downloadId) async {
    await request('download.resume', {'downloadId': downloadId});
  }

  Future<void> cancelDownload(String downloadId) async {
    await request('download.cancel', {'downloadId': downloadId});
  }

  Future<void> retryDownload(String downloadId) async {
    await request('download.retry', {'downloadId': downloadId});
  }

  Future<void> setPriority(String downloadId, int priority) async {
    await request('download.setPriority', {
      'downloadId': downloadId,
      'priority': priority,
    });
  }

  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {
    await request('download.setGlobalBandwidthLimit', {
      'bytesPerSecond': bytesPerSecond,
    });
  }

  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {
    await request('download.setDownloadBandwidthLimit', {
      'downloadId': downloadId,
      'bytesPerSecond': bytesPerSecond,
    });
  }

  Future<List<DownloadInfo>> listDownloads() async {
    final result = await request('download.list', {});
    final downloads = result['downloads'];
    if (downloads is! List) {
      throw DownloadError(
        IpcErrorCode.invalidMessage,
        'download.list returned no downloads list',
      );
    }
    return downloads
        .whereType<Map<String, Object?>>()
        .map(downloadInfoFromJson)
        .toList();
  }

  Future<List<DownloadSegment>> getSegments(String downloadId) async {
    final result = await request('download.segments', {
      'downloadId': downloadId,
    });
    final segments = result['segments'];
    if (segments is! List) {
      throw DownloadError(
        IpcErrorCode.invalidMessage,
        'download.segments returned no segments list',
      );
    }
    return segments
        .whereType<Map<String, Object?>>()
        .map(downloadSegmentFromJson)
        .toList();
  }

  /// Drops the current channel and connects again with the same
  /// factory and token. The server answers with a fresh sync
  /// snapshot, so no state is lost.
  Future<void> reconnect({
    Duration helloTimeout = const Duration(seconds: 5),
  }) async {
    if (_closed) {
      throw StateError('IpcClient is closed');
    }
    final factory = _channelFactory;
    if (factory == null) {
      throw StateError('IpcClient cannot reconnect without a channel factory');
    }
    await _bind(await factory(), helloTimeout);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _helloTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.close();
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(StateError('IpcClient closed'));
      }
    }
    _pending.clear();
    await _events.close();
    await _syncs.close();
  }

  Future<void> _bind(IpcChannel channel, Duration helloTimeout) async {
    await _subscription?.cancel();
    await _channel?.close();
    _channel = channel;
    _helloCompleter = Completer<void>();
    _subscription = channel.messages.listen(
      _onMessage,
      onDone: _handleChannelClosed,
      onError: (_) => _handleChannelClosed(),
    );
    _helloTimer = Timer(helloTimeout, () {
      final hello = _helloCompleter;
      if (hello != null && !hello.isCompleted) {
        _helloCompleter = null;
        hello.completeError(
          DownloadError(
            IpcErrorCode.timeout,
            'Hello handshake timed out',
          ),
        );
      }
    });
    await channel.send({
      'type': 'hello',
      'v': ipcProtocolVersion,
      'token': _token,
    });
    await _helloCompleter!.future;
  }

  void _onMessage(Map<String, Object?> message) {
    if (_closed) {
      return;
    }
    final hello = _helloCompleter;
    if (hello != null && !hello.isCompleted) {
      final type = message['type'];
      if (type == 'hello-ok') {
        _helloTimer?.cancel();
        _helloCompleter = null;
        hello.complete();
      } else if (type == 'error') {
        _helloTimer?.cancel();
        _helloCompleter = null;
        final error = message['error'] as Map<String, Object?>?;
        hello.completeError(
          DownloadError(
            error?['code'] as String? ?? IpcErrorCode.connectionClosed,
            error?['message'] as String? ?? 'Handshake failed',
          ),
        );
      }
      return;
    }
    final type = message['type'];
    if (type == 'response') {
      final id = message['id'];
      if (id is! String) {
        return;
      }
      final pending = _pending.remove(id);
      if (pending == null) {
        return;
      }
      pending.timer.cancel();
      final error = message['error'];
      if (error is Map<String, Object?>) {
        pending.completer.completeError(
          DownloadError(
            error['code'] as String? ?? IpcErrorCode.internal,
            error['message'] as String? ?? 'Request failed',
          ),
        );
      } else {
        final result = message['result'];
        if (result is Map<String, Object?>) {
          pending.completer.complete(result);
        } else {
          pending.completer.completeError(
            DownloadError(
              IpcErrorCode.invalidMessage,
              'Response has no result object',
            ),
          );
        }
      }
      return;
    }
    if (type == 'event') {
      final name = message['event'];
      final data = message['data'];
      if (name is! String || data is! Map<String, Object?>) {
        return;
      }
      if (name == 'download.sync') {
        final downloads = data['downloads'];
        if (downloads is List) {
          try {
            final infos = downloads
                .whereType<Map<String, Object?>>()
                .map(downloadInfoFromJson)
                .toList();
            _latestSync = infos;
            _syncs.add(infos);
          } catch (_) {
            // A malformed snapshot is ignored; the next sync repairs it.
          }
        }
        return;
      }
      try {
        final event = downloadEventFromMessage(name, data);
        if (event != null) {
          _events.add(event);
        }
      } catch (_) {
        // An unknown or malformed event is ignored, never thrown.
      }
      return;
    }
    // Bare errors and unknown types are ignored.
  }

  void _handleChannelClosed() {
    if (_closed) {
      return;
    }
    final error = DownloadError(
      IpcErrorCode.connectionClosed,
      'Connection closed',
    );
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
    _pending.clear();
    final hello = _helloCompleter;
    if (hello != null && !hello.isCompleted) {
      _helloCompleter = null;
      hello.completeError(error);
    }
  }
}

/// One in-flight request: its completer plus the timer that fails it
/// on timeout. The timer is cancelled when the response arrives, so
/// no second future is left holding the error.
class _PendingRequest {
  _PendingRequest(this.completer, this.timer);

  final Completer<Map<String, Object?>> completer;
  final Timer timer;
}
