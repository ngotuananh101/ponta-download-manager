import 'dart:io';

import 'package:pdm_engine/pdm_engine.dart';

Future<void> main(List<String> arguments) async {
  final result = parseCliArgs(arguments);
  switch (result.command) {
    case 'help':
      stdout.writeln(engineUsage);
    case 'version':
      stdout.writeln('pdm engine 0.1.0');
    case 'download':
      exitCode = await runDownload(result);
  }
}
