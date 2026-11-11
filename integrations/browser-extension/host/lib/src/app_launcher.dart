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
/// for its IPC endpoint (token + socket) to appear. Linux only: the
/// app binary is resolved from the .desktop file the app installs
/// itself, or from the PDM_APP_PATH environment variable.
class AppLauncher {
  AppLauncher({
    required this.socketPath,
    this.desktopFilePath,
    this.environment,
    Future<void> Function(String path)? processStarter,
    this.timeout = const Duration(seconds: 15),
  }) : _processStarter = processStarter ?? _defaultStarter;

  final String socketPath;
  final String? desktopFilePath;
  final Map<String, String>? environment;
  final Duration timeout;
  final Future<void> Function(String path) _processStarter;

  static Future<void> _defaultStarter(String path) async {
    await Process.start(path, [], mode: ProcessStartMode.detached);
  }

  String get _tokenPath => '$socketPath.token';

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

  /// Whether the IPC endpoint (token + socket) currently exists.
  bool endpointExists() {
    return File(_tokenPath).existsSync() && File(socketPath).existsSync();
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

  /// Starts the app if it is not already running, then waits for its
  /// IPC endpoint. Returns false when the app path cannot be resolved,
  /// the launch fails, or the endpoint never appears.
  Future<bool> launchAndWait() async {
    if (endpointExists()) {
      return true;
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
