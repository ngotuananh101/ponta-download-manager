import 'dart:io';

import 'package:path/path.dart' as p;

/// Default IPC socket path, shared by the engine (`serve`) and the
/// desktop UI: `$XDG_RUNTIME_DIR/pdm/engine.sock` (Linux),
/// `~/.local/share/pdm/engine.sock` when XDG is unset, and
/// `%LOCALAPPDATA%\pdm\engine.sock` on Windows. The client token
/// file is always `$socketPath.token`.
///
/// On Windows the path is only a rendezvous base: Dart cannot bind a
/// Unix socket there, so the server listens on loopback TCP instead
/// and writes the bound port to [portFilePath].
String defaultSocketPath() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base =
        localAppData ??
        p.join(
          Platform.environment['USERPROFILE'] ?? '.',
          'AppData',
          'Local',
        );
    return p.join(base, 'pdm', 'engine.sock');
  }
  final runtime = Platform.environment['XDG_RUNTIME_DIR'];
  final base =
      runtime ?? p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');
  return p.join(base, 'pdm', 'engine.sock');
}

/// Path of the file holding the loopback TCP port the IPC server
/// bound on Windows (`<socketPath>.port`). Unused on POSIX, where
/// the socket file itself is the endpoint.
String portFilePath(String socketPath) => '$socketPath.port';
