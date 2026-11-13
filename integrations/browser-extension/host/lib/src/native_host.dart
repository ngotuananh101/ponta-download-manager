import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'native_message_codec.dart';

/// The Native Messaging host: reads length-prefixed JSON messages
/// from the browser extension, forwards `download.create` and
/// `ytdlp.probe` to the running engine over IPC, and writes a
/// length-prefixed reply.
/// The host is long-lived for one native port; the loop ends when
/// stdin closes (EOF). Only a bounded summary (host + file name)
/// is ever logged — never the full URL, never cookies.
class NativeHost {
  NativeHost({
    required Future<IpcClient> Function() clientFactory,
    required this.downloadDirectory,
  }) : _clientFactory = clientFactory;

  final Future<IpcClient> Function() _clientFactory;
  final String downloadDirectory;
  final _log = Logger('NativeHost');

  IpcClient? _client;

  Future<void> run(Stream<List<int>> input, StreamSink<List<int>> output) async {
    var queue = Future<void>.value();
    final done = Completer<void>();
    final subscription = NativeMessageCodec.decode(input).listen(
      (message) {
        queue = queue.then((_) async {
          final reply = await _handle(message);
          output.add(NativeMessageCodec.encode(reply));
        });
      },
      onError: (Object e) {
        _log.warning('Dropping malformed native message: $e');
      },
      onDone: () async {
        await queue;
        done.complete();
      },
      cancelOnError: false,
    );
    await done.future;
    await subscription.cancel();
    await _client?.close();
  }

  Future<Map<String, Object?>> _handle(Map<String, Object?> message) async {
    final id = message['id'];
    if (id is! String) {
      return _error(id, IpcErrorCode.invalidMessage, 'Unknown message');
    }
    final type = message['type'];
    if (type == 'download.create') {
      return _handleCreate(id, message);
    }
    if (type == 'ytdlp.probe') {
      return _handleProbe(id, message);
    }
    return _error(id, IpcErrorCode.invalidMessage, 'Unknown message');
  }

  Future<Map<String, Object?>> _handleCreate(
    String id,
    Map<String, Object?> message,
  ) async {
    final url = message['url'];
    if (url is! String) {
      return _error(id, IpcErrorCode.invalidParams, 'Missing url');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'URL must start with http:// or https://',
      );
    }
    final fileName = _fileName(message, uri);
    if (fileName == null) {
      return _error(id, IpcErrorCode.invalidParams, 'Invalid fileName');
    }
    final cookie = message['cookie'];
    if (cookie != null && cookie is! String) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'cookie must be a string',
      );
    }
    final referrer = message['referrer'];
    if (referrer != null && referrer is! String) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'referrer must be a string',
      );
    }
    final ytDlpFormat = message['ytDlpFormat'];
    if (ytDlpFormat != null && ytDlpFormat is! String) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'ytDlpFormat must be a string',
      );
    }
    try {
      final info = await _create(
        url,
        fileName,
        cookie as String?,
        referrer as String?,
        ytDlpFormat as String?,
      );
      _log.info('Created ${info.id} for ${uri.host} ($fileName)');
      return {'id': id, 'ok': true, 'downloadId': info.id};
    } on DownloadError catch (e) {
      return _error(id, e.code, e.message);
    } catch (e) {
      // A factory failure (e.g. the token file missing because the
      // app is not running) is not a DownloadError; it still needs an
      // error reply instead of hanging the host.
      return _error(id, IpcErrorCode.internal, 'Failed to create download: $e');
    }
  }

  Future<Map<String, Object?>> _handleProbe(
    String id,
    Map<String, Object?> message,
  ) async {
    final url = message['url'];
    if (url is! String) {
      return _error(id, IpcErrorCode.invalidParams, 'Missing url');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'URL must start with http:// or https://',
      );
    }
    final cookie = message['cookie'];
    if (cookie != null && cookie is! String) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'cookie must be a string',
      );
    }
    final referrer = message['referrer'];
    if (referrer != null && referrer is! String) {
      return _error(
        id,
        IpcErrorCode.invalidParams,
        'referrer must be a string',
      );
    }
    try {
      final client = await _ensureClient();
      final probe = await client.probeYtDlp(
        url: url,
        cookie: cookie as String?,
        referrer: referrer as String?,
      );
      _log.info('Probed ${uri.host}');
      return {'id': id, 'ok': true, 'probe': probe.toJson()};
    } on DownloadError catch (e) {
      return _error(id, e.code, e.message);
    } catch (e) {
      // A factory failure (e.g. the token file missing because the
      // app is not running) is not a DownloadError; it still needs an
      // error reply instead of hanging the host.
      return _error(id, IpcErrorCode.internal, 'Failed to probe URL: $e');
    }
  }

  String? _fileName(Map<String, Object?> message, Uri uri) {
    final supplied = message['fileName'];
    if (supplied != null) {
      if (supplied is! String || supplied.isEmpty) {
        return null;
      }
      if (supplied.contains('/') ||
          supplied.contains(r'\') ||
          supplied.contains('..')) {
        return null;
      }
      return supplied;
    }
    final segments = uri.pathSegments;
    final last = segments.isNotEmpty ? segments.last : '';
    return last.isNotEmpty ? last : 'download';
  }

  Future<DownloadInfo> _create(
    String url,
    String fileName,
    String? cookie,
    String? referrer,
    String? ytDlpFormat,
  ) async {
    // The extension cannot show the app's file-exists dialog, so a
    // browser download never overwrites and never fails on an
    // existing file: it renames to the first free name instead.
    final request = CreateDownloadRequest(
      url: url,
      destination: p.join(downloadDirectory, fileName),
      conflictPolicy: FileConflictPolicy.rename,
      cookie: cookie,
      referrer: referrer,
      ytDlpFormat: ytDlpFormat,
    );
    try {
      final client = await _ensureClient();
      return await client.createDownload(request);
    } on DownloadError catch (e) {
      if (e.code != IpcErrorCode.connectionClosed) {
        rethrow;
      }
      // The engine went away mid-port: drop the client and retry
      // once with a fresh connection.
      _client = null;
      final fresh = await _ensureClient();
      return fresh.createDownload(request);
    }
  }

  Future<IpcClient> _ensureClient() async {
    final client = _client;
    if (client != null) {
      return client;
    }
    final fresh = await _clientFactory();
    _client = fresh;
    return fresh;
  }

  Map<String, Object?> _error(Object? id, String code, String message) {
    return {'id': id, 'ok': false, 'code': code, 'message': message};
  }
}
