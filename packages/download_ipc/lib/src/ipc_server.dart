import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:logging/logging.dart';

import 'ipc_channel.dart';
import 'protocol.dart';

final _log = Logger('IpcServer');

/// Serves one [DownloadEngine] over IPC (§4.2). The server owns
/// neither the engine nor the transport: the caller supplies the
/// stream of accepted channels and disposes the engine itself after
/// [close] (the §16 [DownloadEngine] has no dispose method).
/// A client must send `hello` with the server token first; on
/// success it gets `hello-ok` plus a `download.sync` snapshot, and
/// from then on every engine event is broadcast to it. Events that
/// arrive while the snapshot is pending are buffered and sent right
/// after it, so the client always sees the snapshot first.
class IpcServer {
  IpcServer({
    required DownloadEngine engine,
    required Stream<IpcChannel> connections,
    required this.token,
  }) : _engine = engine {
    _eventsSubscription = _engine.events.listen(_broadcastEvent);
    _connectionsSubscription = connections.listen(_handleConnection);
  }

  final DownloadEngine _engine;
  final String token;
  late final StreamSubscription<DownloadEvent> _eventsSubscription;
  late final StreamSubscription<IpcChannel> _connectionsSubscription;
  final _clients = <_ClientConnection>[];
  var _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _connectionsSubscription.cancel();
    await _eventsSubscription.cancel();
    for (final client in _clients.toList()) {
      await client.close();
    }
    _clients.clear();
  }

  void _broadcastEvent(DownloadEvent event) {
    if (_closed) {
      return;
    }
    final message = downloadEventToMessage(event);
    for (final client in _clients.toList()) {
      if (client.authenticated) {
        client.sendBroadcast(message);
      }
    }
  }

  void _handleConnection(IpcChannel channel) {
    if (_closed) {
      unawaited(channel.close());
      return;
    }
    _clients.add(_ClientConnection(this, channel));
  }

  void _removeClient(_ClientConnection client) {
    _clients.remove(client);
  }
}

class _ClientConnection {
  _ClientConnection(this._server, this._channel) {
    _subscription = _channel.messages.listen(
      _onMessage,
      onDone: close,
      onError: (_) => close(),
    );
    _helloTimer = Timer(const Duration(seconds: 5), () {
      if (!_authenticated) {
        _sendError(
          IpcErrorCode.unauthorized,
          'Hello handshake timed out',
        );
        close();
      }
    });
  }

  final IpcServer _server;
  final IpcChannel _channel;
  late final StreamSubscription<Map<String, Object?>> _subscription;
  late final Timer _helloTimer;
  var _authenticated = false;

  /// True once the sync snapshot has been sent. Broadcasts that arrive
  /// before that are buffered in [_pendingBroadcasts] so a client never
  /// sees an event for a download it has not learned from the snapshot.
  var _synced = false;

  /// Broadcasts that arrived while the sync snapshot was pending, in
  /// arrival order. Flushed right after the snapshot.
  final _pendingBroadcasts = <Map<String, Object?>>[];
  var _closed = false;

  /// Requests on one connection run sequentially, in arrival order.
  Future<void> _queue = Future<void>.value();

  bool get authenticated => _authenticated;

  Future<void> send(Map<String, Object?> message) async {
    if (_closed) {
      return;
    }
    try {
      await _channel.send(message);
    } catch (_) {
      // A send that fails means the peer is gone; drop the client.
      await close();
    }
  }

  /// Sends a broadcast engine event, or buffers it until the sync
  /// snapshot has been sent: a client must see the snapshot before
  /// any event, and the snapshot is taken after the event, so nothing
  /// is lost by holding it back.
  void sendBroadcast(Map<String, Object?> message) {
    if (_synced) {
      send(message);
    } else {
      _pendingBroadcasts.add(message);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _helloTimer.cancel();
    await _subscription.cancel();
    await _channel.close();
    _server._removeClient(this);
  }

  void _onMessage(Map<String, Object?> message) {
    if (_closed) {
      return;
    }
    if (!_authenticated) {
      unawaited(_handleHello(message));
      return;
    }
    _queue = _queue.then((_) => _handleRequest(message)).catchError((_) {});
  }

  Future<void> _handleHello(Map<String, Object?> message) async {
    if (message['type'] != 'hello') {
      _sendError(
        IpcErrorCode.invalidMessage,
        'First message must be hello',
      );
      close();
      return;
    }
    if (message['v'] != ipcProtocolVersion) {
      _sendError(
        IpcErrorCode.unsupportedVersion,
        'Unsupported protocol version: ${message['v']}',
      );
      close();
      return;
    }
    if (message['token'] != _server.token) {
      _sendError(IpcErrorCode.unauthorized, 'Bad token');
      close();
      return;
    }
    _authenticated = true;
    _helloTimer.cancel();
    await send({'type': 'hello-ok', 'v': ipcProtocolVersion});
    await _sendSync();
    // Events that arrived while the snapshot was pending are sent now,
    // in arrival order, so the client sees the snapshot first and no
    // event is lost.
    for (final pending in _pendingBroadcasts) {
      send(pending);
    }
    _pendingBroadcasts.clear();
    _synced = true;
  }

  Future<void> _sendSync() async {
    try {
      final downloads = await _server._engine.listDownloads();
      await send({
        'type': 'event',
        'v': ipcProtocolVersion,
        'event': 'download.sync',
        'data': {
          'downloads': downloads.map(downloadInfoToJson).toList(),
        },
      });
    } catch (e) {
      _log.warning('Failed to send sync snapshot: $e');
    }
  }

  Future<void> _handleRequest(Map<String, Object?> message) async {
    if (_closed) {
      return;
    }
    if (message['type'] != 'request') {
      _sendError(
        IpcErrorCode.invalidMessage,
        'Expected a request message',
      );
      return;
    }
    final id = message['id'];
    final method = message['method'];
    if (id is! String || method is! String) {
      _sendError(
        IpcErrorCode.invalidMessage,
        'Request needs a string id and method',
      );
      return;
    }
    if (message['v'] != ipcProtocolVersion) {
      await _replyError(
        id,
        IpcErrorCode.unsupportedVersion,
        'Unsupported protocol version: ${message['v']}',
      );
      return;
    }
    final params = message['params'];
    if (params != null && params is! Map<String, Object?>) {
      await _replyError(
        id,
        IpcErrorCode.invalidParams,
        'params must be an object',
      );
      return;
    }
    final p = (params as Map<String, Object?>?) ?? const {};
    try {
      final result = await _dispatch(method, p);
      await _reply(id, result);
    } on DownloadError catch (e) {
      await _replyError(id, e.code, e.message);
    } catch (e) {
      await _replyError(id, IpcErrorCode.internal, e.toString());
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String method,
    Map<String, Object?> params,
  ) async {
    final engine = _server._engine;
    switch (method) {
      case 'download.create':
        final url = params['url'];
        final destination = params['destination'];
        if (url is! String ||
            url.isEmpty ||
            destination is! String ||
            destination.isEmpty) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'download.create needs a non-empty url and destination',
          );
        }
        final maxConnections = params['maxConnections'];
        final priority = params['priority'];
        if (maxConnections != null &&
            (maxConnections is! int || maxConnections < 1)) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'maxConnections must be an int >= 1',
          );
        }
        if (priority != null && priority is! int) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'priority must be an int',
          );
        }
        final conflictPolicy = params['conflictPolicy'];
        FileConflictPolicy? policy;
        if (conflictPolicy != null) {
          if (conflictPolicy is! String ||
              (conflictPolicy != 'overwrite' && conflictPolicy != 'rename')) {
            throw DownloadError(
              IpcErrorCode.invalidParams,
              'conflictPolicy must be overwrite or rename',
            );
          }
          policy = conflictPolicy == 'overwrite'
              ? FileConflictPolicy.overwrite
              : FileConflictPolicy.rename;
        }
        final cookie = params['cookie'];
        if (cookie != null && cookie is! String) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'cookie must be a string',
          );
        }
        final referrer = params['referrer'];
        if (referrer != null && referrer is! String) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'referrer must be a string',
          );
        }
        final ytDlpFormat = params['ytDlpFormat'];
        if (ytDlpFormat != null && ytDlpFormat is! String) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'ytDlpFormat must be a string',
          );
        }
        final info = await engine.createDownload(
          CreateDownloadRequest(
            url: url,
            destination: destination,
            maxConnections: maxConnections as int?,
            priority: priority as int?,
            conflictPolicy: policy,
            cookie: cookie as String?,
            referrer: referrer as String?,
            ytDlpFormat: ytDlpFormat as String?,
          ),
        );
        return downloadInfoToJson(info);
      case 'ytdlp.probe':
        final url = params['url'];
        if (url is! String || url.isEmpty) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'ytdlp.probe needs a non-empty url',
          );
        }
        final cookie = params['cookie'];
        if (cookie != null && cookie is! String) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'cookie must be a string',
          );
        }
        final referrer = params['referrer'];
        if (referrer != null && referrer is! String) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'referrer must be a string',
          );
        }
        final probe = await engine.probeYtDlp(
          url,
          cookie: cookie as String?,
          referrer: referrer as String?,
        );
        return ytDlpProbeResultToJson(probe);
      case 'download.pause':
        await engine.pauseDownload(_downloadId(params));
        return const {'ok': true};
      case 'download.resume':
        await engine.resumeDownload(_downloadId(params));
        return const {'ok': true};
      case 'download.cancel':
        await engine.cancelDownload(_downloadId(params));
        return const {'ok': true};
      case 'download.retry':
        await engine.retryDownload(_downloadId(params));
        return const {'ok': true};
      case 'download.setPriority':
        final priority = params['priority'];
        if (priority is! int) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'priority must be an int',
          );
        }
        await engine.setPriority(_downloadId(params), priority);
        return const {'ok': true};
      case 'download.setGlobalBandwidthLimit':
        final limit = params['bytesPerSecond'];
        if (limit != null && (limit is! int || limit < 0)) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'bytesPerSecond must be a non-negative int or null',
          );
        }
        await engine.setGlobalBandwidthLimit(limit as int?);
        return const {'ok': true};
      case 'download.setDownloadBandwidthLimit':
        final limit = params['bytesPerSecond'];
        if (limit != null && (limit is! int || limit < 0)) {
          throw DownloadError(
            IpcErrorCode.invalidParams,
            'bytesPerSecond must be a non-negative int or null',
          );
        }
        await engine.setDownloadBandwidthLimit(
          _downloadId(params),
          limit as int?,
        );
        return const {'ok': true};
      case 'download.list':
        final downloads = await engine.listDownloads();
        return {
          'downloads': downloads.map(downloadInfoToJson).toList(),
        };
      case 'download.segments':
        final segments = await engine.getSegments(_downloadId(params));
        return {
          'segments': segments.map(downloadSegmentToJson).toList(),
        };
      default:
        throw DownloadError(
          IpcErrorCode.unknownMethod,
          'Unknown method: $method',
        );
    }
  }

  String _downloadId(Map<String, Object?> params) {
    final id = params['downloadId'];
    if (id is! String || id.isEmpty) {
      throw DownloadError(
        IpcErrorCode.invalidParams,
        'downloadId must be a non-empty string',
      );
    }
    return id;
  }

  Future<void> _reply(String id, Map<String, Object?> result) async {
    await send(ipcResponse(id, result));
  }

  Future<void> _replyError(String id, String code, String message) async {
    await send(ipcErrorResponse(id, code, message));
  }

  void _sendError(String code, String message) {
    send(ipcErrorMessage(code, message));
  }
}
