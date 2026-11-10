import 'dart:io';

import 'package:pdm_engine/pdm_engine.dart';

Future<void> main(List<String> arguments) async {
  final result = parseCliArgs(arguments);
  switch (result.command) {
    case 'help':
      stdout.writeln(engineUsage);
    case 'version':
      stdout.writeln('pdm engine 0.1.0');
    case 'serve':
      stdout.writeln('Engine daemon is not implemented yet (IPC, M3).');
      exitCode = 2;
    case 'download':
      exitCode = await runDownload(result);
  }
}
