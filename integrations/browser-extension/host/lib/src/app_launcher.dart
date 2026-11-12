import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;

/// Parses the app binary path out of a .desktop file's Exec= line.
/// Handles a quoted path and trailing arguments (%u, %U, ...).
/// Returns null when there is no usable Exec= line.
String? appPathFromDesktopContent(String content) {
  for (final line in content.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('Exec=')) {
      continue;
    }
    var value = trimmed.substring('Exec='.length).trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('"')) {
      final closing = value.indexOf('"', 1);
      if (closing == -1) {
        return null;
      }
      return value.substring(1, closing);
    }
    final firstSpace = value.indexOf(RegExp(r'\s'));
    if (firstSpace != -1) {
      value = value.substring(0, firstSpace);
    }
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Default location of the .desktop file the app installs on Linux
/// (via LinuxDesktopService).
String defaultDesktopFilePath() {
  final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
  final base =
      xdgDataHome ??
      p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');
  return p.join(base, 'applications', 'com.ponta.pdm.desktop');
}

/// Launches the PDM desktop app when it is not running, and waits
/// for its IPC endpoint (token + socket, or token + port file on
/// Windows) to appear. Linux only: the app binary is resolved from
/// the .desktop file the app installs itself, or from the
/// PDM_APP_PATH environment variable.
class AppLauncher {
  AppLauncher({
    required this.socketPath,
    this.desktopFilePath,
    this.environment,
    Future<void> Function(String path)? processStarter,
    this.timeout = const Duration(seconds: 15),
    bool? isWindows,
  }) : _processStarter = processStarter ?? _defaultStarter,
       _isWindows = isWindows ?? Platform.isWindows;

  final String socketPath;
  final String? desktopFilePath;
  final Map<String, String>? environment;
  final Duration timeout;
  final Future<void> Function(String path) _processStarter;
  final bool _isWindows;

  static Future<void> _defaultStarter(String path) async {
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }

  String get _tokenPath => '$socketPath.token';

  String get _portPath => portFilePath(socketPath);

  /// The app binary path: PDM_APP_PATH first, then the Exec= line of
  /// the installed .desktop file. Null when neither is available.
  String? resolveAppPath() {
    final env = environment ?? Platform.environment;
    final fromEnv = env['PDM_APP_PATH'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    final desktopPath = desktopFilePath ?? defaultDesktopFilePath();
    final file = File(desktopPath);
    if (!file.existsSync()) {
      return null;
    }
    try {
      return appPathFromDesktopContent(file.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// Whether the IPC endpoint currently exists: token + socket on
  /// POSIX, token + port file on Windows (there is no socket file
  /// there — the server listens on loopback TCP). File existence
  /// alone does not mean the app is running: a crash leaves these
  /// files behind, so [launchAndWait] probes liveness before
  /// trusting them.
  bool endpointExists() {
    if (!File(_tokenPath).existsSync()) {
      return false;
    }
    return _isWindows
        ? File(_portPath).existsSync()
        : File(socketPath).existsSync();
  }

  /// Polls until the IPC endpoint exists, or the timeout elapses.
  Future<bool> waitForEndpoint() async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (endpointExists()) {
        return true;
      }
      if (DateTime.now().isAfter(deadline)) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Whether a process is actually listening at the endpoint: a bare
  /// socket connect, closed at once. Files alone prove nothing — a
  /// crash leaves them behind.
  Future<bool> _isEndpointLive() async {
    if (await _probeOnce()) {
      return true;
    }
    // The app may be mid-startup (files written just before the
    // socket starts listening): give it one short grace period
    // before treating the files as crash leftovers.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return _probeOnce();
  }

  Future<bool> _probeOnce() async {
    try {
      final socket = _isWindows ? await _probeTcp() : await _probeUnix();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Socket> _probeUnix() {
    return Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 1),
    );
  }

  Future<Socket> _probeTcp() async {
    final port = int.tryParse(
      (await File(_portPath).readAsString()).trim(),
    );
    if (port == null) {
      throw const FormatException('No port in port file');
    }
    return Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: const Duration(seconds: 1),
    );
  }

  void _deleteStaleEndpoint() {
    for (final path in [_tokenPath, _isWindows ? _portPath : socketPath]) {
      try {
        File(path).deleteSync();
      } catch (_) {
        // Best effort: the app rebinds over a stale socket file
        // anyway (UnixSocketTransport unlinks before bind).
      }
    }
  }

  /// Starts the app if it is not already running, then waits for its
  /// IPC endpoint. Returns false when the app path cannot be resolved,
  /// the launch fails, or the endpoint never appears.
  Future<bool> launchAndWait() async {
    if (endpointExists()) {
      if (await _isEndpointLive()) {
        return true;
      }
      // The token/socket (or port) files are leftovers from a crash:
      // no process is listening. Drop them so the fresh app can bind
      // and waitForEndpoint waits for its files, not these stale ones.
      _deleteStaleEndpoint();
    }
    final appPath = resolveAppPath();
    if (appPath == null) {
      return false;
    }
    try {
      await _processStarter(appPath);
    } catch (_) {
      return false;
    }
    return waitForEndpoint();
  }
}

/// Connects to the app, launching it first when it is not running.
/// The first connect attempt is made as-is; only when it fails does
/// the launcher run, and the connect is then retried once.
Future<IpcClient> connectWithAutoLaunch({
  required Future<IpcClient> Function() connect,
  required AppLauncher launcher,
}) async {
  try {
    return await connect();
  } on Object catch (_) {
    // The app is not running (or the endpoint is gone): launch it.
  }
  final launched = await launcher.launchAndWait();
  if (!launched) {
    throw DownloadError(
      IpcErrorCode.connectionClosed,
      'PDM is not running and could not be started',
    );
  }
  return connect();
}
