import 'package:args/args.dart';

const String engineUsage = '''
Ponta Download Manager engine (0.1.0)

Usage: engine [options] <command>

Commands:
  download <url>   Download a URL.
    --dir <dir>         Download directory (default: downloads).
    --connections <n>   Max connections per download (default: 8).
    --db <path>         Database path (default: ~/.local/share/pdm/pdm.db).
    --limit <bytes/s>   Global bandwidth limit in bytes per second.
  serve            Run the engine daemon.
    --socket <path>     IPC socket path (default: \$XDG_RUNTIME_DIR/pdm/engine.sock).
    --db <path>         Database path (default: ~/.local/share/pdm/pdm.db).

Options:
  -h, --help       Show usage.
      --version    Show the engine version.
''';

/// Result of parsing the engine CLI arguments.
class CliResult {
  const CliResult({
    required this.command,
    this.url,
    this.directory,
    this.maxConnections,
    this.databasePath,
    this.globalLimitBytesPerSecond,
    this.socketPath,
  });

  /// One of 'help', 'version', 'download', 'serve'.
  final String command;
  final String? url;
  final String? directory;
  final int? maxConnections;
  final String? databasePath;
  final int? globalLimitBytesPerSecond;
  final String? socketPath;
}

/// Parses [args] for `bin/engine.dart`. Never prints; callers decide output.
CliResult parseCliArgs(List<String> args) {
  final downloadParser = ArgParser()
    ..addOption('dir', help: 'Download directory.')
    ..addOption('connections', help: 'Max connections per download.')
    ..addOption('db', help: 'Database path.')
    ..addOption('limit', help: 'Global bandwidth limit in bytes per second.');
  final serveParser = ArgParser()
    ..addOption('socket', help: 'IPC socket path.')
    ..addOption('db', help: 'Database path.');
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Show the engine version.')
    ..addCommand('download', downloadParser)
    ..addCommand('serve', serveParser);
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
    return CliResult(
      command: 'download',
      url: rest.first,
      directory: command['dir'] as String?,
      maxConnections: int.tryParse(command['connections'] as String? ?? ''),
      databasePath: command['db'] as String?,
      globalLimitBytesPerSecond: int.tryParse(
        command['limit'] as String? ?? '',
      ),
    );
  }
  if (command.name == 'serve') {
    return CliResult(
      command: 'serve',
      socketPath: command['socket'] as String?,
      databasePath: command['db'] as String?,
    );
  }
  return CliResult(command: command.name!);
}
