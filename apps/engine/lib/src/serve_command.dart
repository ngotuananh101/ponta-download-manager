import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;

import 'cli.dart';
import 'engine_config.dart';
import 'pdm_engine.dart';

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

/// Runs the `serve` CLI command: opens the engine, serves it over
/// IPC, and shuts down cleanly on SIGINT/SIGTERM. Returns the
/// process exit code (0 on a clean signal shutdown).
Future<int> runServe(CliResult result, {StringSink? out}) async {
  final sink = out ?? stdout;
  final socketPath = result.socketPath ?? defaultSocketPath();
  final engine = PdmEngine.open(
    config: const EngineConfig(),
    databasePath: result.databasePath,
  );
  final token = _randomToken();
  final tokenPath = await writeTokenFile(socketPath, token);
  final transport = UnixSocketTransport(socketPath: socketPath);
  final server = IpcServer(
    engine: engine,
    connections: await transport.listen(),
    token: token,
  );
  sink.writeln('Listening on $socketPath');
  final signals = <StreamSubscription<ProcessSignal>>[];
  final shutdown = Completer<void>();
  final watched = [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm,
  ];
  for (final signal in watched) {
    signals.add(
      signal.watch().listen((_) {
        if (!shutdown.isCompleted) {
          shutdown.complete();
        }
      }),
    );
  }
  await shutdown.future;
  for (final subscription in signals) {
    await subscription.cancel();
  }
  await server.close();
  await transport.close();
  await engine.dispose();
  final tokenFile = File(tokenPath);
  if (await tokenFile.exists()) {
    await tokenFile.delete();
  }
  return 0;
}
