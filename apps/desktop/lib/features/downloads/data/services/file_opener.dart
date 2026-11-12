import 'dart:io';

import 'package:path/path.dart' as p;

/// Opens a downloaded file with its default app, or shows it in the
/// file manager. Shells out to the platform's opener, following
/// DiskSpaceService: Linux xdg-open, macOS open, Windows explorer.
/// Throws when the opener exits non-zero or the platform is unknown —
/// except on Windows, where explorer commonly exits non-zero even on
/// success, so its exit code is ignored (a failed spawn still throws).
class FileOpener {
  const FileOpener({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    run,
    String? operatingSystem,
  }) : _run = run,
       _operatingSystem = operatingSystem;

  final Future<ProcessResult> Function(String, List<String>)? _run;
  final String? _operatingSystem;

  String get _os => _operatingSystem ?? Platform.operatingSystem;

  Future<void> openFile(String path) async {
    switch (_os) {
      case 'windows':
        await _launch('explorer', [path], path, ignoreExitCode: true);
      case 'macos':
        await _launch('open', [path], path);
      case 'linux':
        await _launch('xdg-open', [path], path);
      default:
        throw UnsupportedError('Cannot open files on $_os');
    }
  }

  Future<void> showInFolder(String path) async {
    switch (_os) {
      case 'windows':
        // '/select,' and the path are separate arguments: one combined
        // '/select,<path>' argument breaks on paths with spaces.
        await _launch(
          'explorer',
          ['/select,', path],
          path,
          ignoreExitCode: true,
        );
      case 'macos':
        await _launch('open', ['-R', path], path);
      case 'linux':
        await _launch('xdg-open', [p.dirname(path)], path);
      default:
        throw UnsupportedError('Cannot show files on $_os');
    }
  }

  Future<void> _launch(
    String executable,
    List<String> args,
    String path, {
    bool ignoreExitCode = false,
  }) async {
    final result = await (_run ?? Process.run)(executable, args);
    if (!ignoreExitCode && result.exitCode != 0) {
      throw Exception('Could not open $path (exit ${result.exitCode})');
    }
  }
}
