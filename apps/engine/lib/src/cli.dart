import 'package:args/args.dart';

const String engineUsage = '''
Ponta Download Manager engine (0.1.0)

Usage: engine [options] <command>

Commands:
  download <url>   Download a URL (not implemented yet, M1).
  serve            Run the engine daemon (not implemented yet, M1).

Options:
  -h, --help       Show usage.
      --version    Show the engine version.
''';

/// Result of parsing the engine CLI arguments.
class CliResult {
  const CliResult({required this.command, this.url});

  /// One of 'help', 'version', 'download', 'serve'.
  final String command;
  final String? url;
}

/// Parses [args] for `bin/engine.dart`. Never prints; callers decide output.
CliResult parseCliArgs(List<String> args) {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Show the engine version.')
    ..addCommand('download')
    ..addCommand('serve');
  final results = parser.parse(args);
  if (results.flag('version')) {
    return const CliResult(command: 'version');
  }
  if (results.flag('help') || results.command == null) {
    return const CliResult(command: 'help');
  }
  final command = results.command!;
  if (command.name == 'download') {
    final rest = command.rest;
    if (rest.isEmpty) {
      return const CliResult(command: 'help');
    }
    return CliResult(command: 'download', url: rest.first);
  }
  return CliResult(command: command.name!);
}
