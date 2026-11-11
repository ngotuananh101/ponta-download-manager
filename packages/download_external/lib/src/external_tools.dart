import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the bundled ffmpeg and yt-dlp binaries live, and whether
/// they actually run.
///
/// Resolution order per tool: (1) bundled next to the app executable
/// (`<exe_dir>/bin/ffmpeg`, `<exe_dir>/bin/yt-dlp`, `.exe` on
/// Windows); (2) system PATH. A candidate only counts when its
/// version flag exits 0, so a non-executable or broken file falls
/// through to the next candidate. Note the flags differ: ffmpeg
/// takes a single-dash `-version` (its `--version` exits 8 and
/// prints to stderr), yt-dlp takes `--version`.
class ExternalTools {
  const ExternalTools({required this.ffmpegPath, required this.ytDlpPath});

  final String? ffmpegPath;
  final String? ytDlpPath;

  bool get ffmpegAvailable => ffmpegPath != null;
  bool get ytDlpAvailable => ytDlpPath != null;

  /// True only when both tools resolved and verified.
  bool get available => ffmpegAvailable && ytDlpAvailable;

  /// Resolves both tools. [executableDir] defaults to the directory
  /// holding the current executable. [pathLookup] finds a tool on
  /// PATH (defaults to `which` / `where`). [versionCheck] runs the
  /// tool's version flag and returns true when it exits 0.
  static Future<ExternalTools> resolve({
    String? executableDir,
    Future<String?> Function(String name)? pathLookup,
    Future<bool> Function(String path)? versionCheck,
  }) async {
    final dir = executableDir ?? p.dirname(Platform.resolvedExecutable);
    final lookup = pathLookup ?? _defaultPathLookup;
    final check = versionCheck ?? _defaultVersionCheck;
    final ffmpeg = await _resolveOne('ffmpeg', dir, lookup, check);
    final ytDlp = await _resolveOne('yt-dlp', dir, lookup, check);
    return ExternalTools(ffmpegPath: ffmpeg, ytDlpPath: ytDlp);
  }

  static Future<String?> _resolveOne(
    String name,
    String executableDir,
    Future<String?> Function(String name) lookup,
    Future<bool> Function(String path) check,
  ) async {
    final exeName = Platform.isWindows ? '$name.exe' : name;
    final bundled = p.join(executableDir, 'bin', exeName);
    if (await File(bundled).exists() && await check(bundled)) {
      return bundled;
    }
    final onPath = await lookup(name);
    if (onPath != null && await check(onPath)) {
      return onPath;
    }
    return null;
  }

  static Future<String?> _defaultPathLookup(String name) async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(cmd, [name]);
    if (result.exitCode != 0) {
      return null;
    }
    final out = (result.stdout as String).trim();
    if (out.isEmpty) {
      return null;
    }
    return out.split('\n').first.trim();
  }

  static Future<bool> _defaultVersionCheck(String path) async {
    // ffmpeg takes -version; --version exits 8. yt-dlp takes
    // --version. The basename is the tool name (ffmpeg, ffmpeg.exe,
    // yt-dlp, yt-dlp.exe).
    final args = p.basename(path).startsWith('ffmpeg')
        ? ['-version']
        : ['--version'];
    try {
      final result = await Process.run(path, args);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
