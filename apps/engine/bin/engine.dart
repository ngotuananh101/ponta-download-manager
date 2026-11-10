import 'dart:io';
import 'package:pdm_engine/pdm_engine.dart';

void main(List<String> arguments) {
  final result = parseCliArgs(arguments);
  switch (result.command) {
    case 'help':
      stdout.writeln(engineUsage);
    case 'version':
      stdout.writeln('pdm engine 0.1.0');
    case 'serve':
      stdout.writeln('Engine daemon is not implemented yet (M1).');
      exitCode = 2;
    case 'download':
      stdout.writeln(
        'Download transport is not implemented yet (M1): ${result.url}',
      );
      exitCode = 2;
  }
}
