import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ipc_channel.dart';

/// Server side of a local transport: binds and yields one
/// [IpcChannel] per accepted connection.
abstract interface class IpcServerTransport {
  Future<Stream<IpcChannel>> listen();
  Future<void> close();
}

/// Client side of a local transport: connects and yields a channel.
abstract interface class IpcClientTransport {
  Future<IpcChannel> connect();
}

/// Unix domain socket transport (Linux/macOS). The socket file lives
/// in a user-private directory (`$XDG_RUNTIME_DIR` or
/// `~/.local/share`); a stale socket file is unlinked before bind
/// and removed again on [close].
class UnixSocketTransport
    implements IpcServerTransport, IpcClientTransport {
  UnixSocketTransport({required this.socketPath});

  final String socketPath;
  ServerSocket? _server;

  @override
  Future<Stream<IpcChannel>> listen() async {
    final file = File(socketPath);
    if (await file.exists()) {
      await file.delete();
    }
    await Directory(p.dirname(socketPath)).create(recursive: true);
    _server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    return _server!.map((socket) => IpcChannel(socket, socket));
  }

  @override
  Future<IpcChannel> connect() async {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    return IpcChannel(socket, socket);
  }

  @override
  Future<void> close() async {
    await _server?.close();
    _server = null;
    final file = File(socketPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Loopback TCP transport (Windows, and the fallback when a Unix
/// socket cannot be bound). Binds `127.0.0.1` only, never `0.0.0.0`.
class LoopbackTcpTransport
    implements IpcServerTransport, IpcClientTransport {
  LoopbackTcpTransport({this.host = '127.0.0.1', this.port = 0});

  final String host;
  final int port;
  ServerSocket? _server;

  int get boundPort => _server?.port ?? port;

  @override
  Future<Stream<IpcChannel>> listen() async {
    _server = await ServerSocket.bind(host, port);
    return _server!.map((socket) => IpcChannel(socket, socket));
  }

  @override
  Future<IpcChannel> connect() async {
    final socket = await Socket.connect(host, boundPort);
    return IpcChannel(socket, socket);
  }

  @override
  Future<void> close() async {
    await _server?.close();
    _server = null;
  }
}
