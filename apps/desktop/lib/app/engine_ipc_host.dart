import 'dart:io';
import 'dart:math';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;

/// The IPC server the desktop app hosts for the browser extension's
/// native host. The engine runs in this process now (IDM direction),
/// so the app — not a separate daemon — serves the same protocol on
/// the same socket + token file the extension already talks to.
class EngineIpcHost {
  EngineIpcHost._(
    this._server,
    this._transport,
    this._tokenPath,
    this._portPath,
  );

  /// Starts the server for [engine] on [socketPath] (default:
  /// [defaultSocketPath]) with a fresh per-run token written to
  /// `<socket>.token`. On Windows the server listens on loopback TCP
  /// instead (Dart cannot bind a Unix socket there) and writes the
  /// bound port to `<socket>.port`. [isWindows] is a test seam,
  /// defaulting to [Platform.isWindows].
  static Future<EngineIpcHost> start({
    required DownloadEngine engine,
    String? socketPath,
    bool? isWindows,
  }) async {
    final path = socketPath ?? defaultSocketPath();
    final token = _randomToken();
    final tokenPath = await writeTokenFile(path, token);
    final transport = createIpcServerTransport(
      socketPath: path,
      isWindows: isWindows,
    );
    final server = IpcServer(
      engine: engine,
      connections: await transport.listen(),
      token: token,
    );
    String? portPath;
    if (transport is LoopbackTcpTransport) {
      portPath = portFilePath(path);
      await File(portPath).writeAsString('${transport.boundPort}');
    }
    return EngineIpcHost._(server, transport, tokenPath, portPath);
  }

  final IpcServer _server;
  final IpcServerTransport _transport;
  final String _tokenPath;
  final String? _portPath;
  var _closed = false;

  /// Stops the server, removes the socket (and the port file on
  /// Windows), and deletes the token file. Idempotent.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close();
    await _transport.close();
    final tokenFile = File(_tokenPath);
    if (await tokenFile.exists()) {
      await tokenFile.delete();
    }
    final portPath = _portPath;
    if (portPath != null) {
      final portFile = File(portPath);
      if (await portFile.exists()) {
        await portFile.delete();
      }
    }
  }
}

String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Writes the per-run client token next to the socket and restricts
/// it to the owner on POSIX systems (best effort).
Future<String> writeTokenFile(String socketPath, String token) async {
  final tokenPath = '$socketPath.token';
  // The socket's parent directory may not exist yet on a first run
  // (the transport creates it only when it binds, which happens
  // after the token is written).
  await Directory(p.dirname(tokenPath)).create(recursive: true);
  await File(tokenPath).writeAsString(token);
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      await Process.run('chmod', ['600', tokenPath]);
    } catch (_) {
      // The token file is only ever read by this user's processes;
      // a failed chmod does not block startup.
    }
  }
  return tokenPath;
}
