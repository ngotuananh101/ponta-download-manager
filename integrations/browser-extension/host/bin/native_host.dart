import 'dart:io';

import 'package:download_ipc/download_ipc.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pdm_native_host/src/app_launcher.dart';
import 'package:pdm_native_host/src/native_host.dart';

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '[${record.loggerName}] ${record.level.name}: ${record.message}',
    );
  });
  final socketPath = defaultSocketPath();
  final downloadDirectory = Platform.isWindows
      ? p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads')
      : p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
  final host = NativeHost(
    clientFactory: () async {
      return connectWithAutoLaunch(
        connect: () async {
          final token = await File('$socketPath.token').readAsString();
          return IpcClient.connect(
            channelFactory: () =>
                UnixSocketTransport(socketPath: socketPath).connect(),
            token: token,
          );
        },
        launcher: AppLauncher(socketPath: socketPath),
      );
    },
    downloadDirectory: downloadDirectory,
  );
  await host.run(stdin, stdout);
}
