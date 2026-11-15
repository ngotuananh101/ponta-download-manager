import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pdm_native_host/src/host_runner.dart';

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '[${record.loggerName}] ${record.level.name}: ${record.message}',
    );
  });
  await runNativeHost(input: stdin, output: stdout);
}
