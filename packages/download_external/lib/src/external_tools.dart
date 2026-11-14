import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the bundled ffmpeg, yt-dlp and quickjs binaries live, and
/// whether they actually run.
///
/// Resolution order per tool: (1) bundled next to the app executable
/// (`<exe_dir>/bin/ffmpeg`, `<exe_dir>/bin/yt-dlp`, `.exe` on
/// Windows); (2) system PATH. A candidate only counts when its
/// version flag exits 0, so a non-executable or broken file falls
/// through to the next candidate. Note the flags differ: ffmpeg
/// takes a single-dash `-version` (its `--version` exits 8 and
/// prints to stderr), yt-dlp and quickjs take `--version`.
///
/// quickjs (`qjs`) is the JavaScript runtime yt-dlp uses to solve
/// YouTube's player challenges. It is optional: without it yt-dlp
/// still downloads HLS/DASH and other sites, it just cannot extract
/// most YouTube formats.
class ExternalTools {
  const ExternalTools({
    required this.ffmpegPath,
    required this.ytDlpPath,
    this.qjsPath,
    this.ytDlpSupportsJsRuntimes = true,
  });

  final String? ffmpegPath;
  final String? ytDlpPath;
  final String? qjsPath;

  /// False when the resolved yt-dlp predates `--js-runtimes`.
  /// yt-dlp exits 2 on an unknown option, which would break every
  /// probe and download, so an old binary must not be given the flag.
  /// Only a yt-dlp found on PATH is ever checked; the bundled release
  /// is known to support it.
  final bool ytDlpSupportsJsRuntimes;

  bool get ffmpegAvailable => ffmpegPath != null;
  bool get ytDlpAvailable => ytDlpPath != null;
  bool get qjsAvailable => qjsPath != null;

  /// True only when both tools resolved and verified. quickjs is not
  /// part of this: it only widens what yt-dlp can extract.
  bool get available => ffmpegAvailable && ytDlpAvailable;

  /// The `--js-runtimes` values handed to yt-dlp: the bundled quickjs
  /// when present, plus node and bun for a user who has them. yt-dlp
  /// picks the highest-priority runtime that is available (node >
  /// quickjs > bun) and falls through a runtime that turns out to be
  /// broken, so listing all three is safe. Empty when no runtime is
  /// worth enabling.
  List<String> get ytDlpJsRuntimeArgs {
    if (!ytDlpSupportsJsRuntimes) {
      return const [];
    }
    return [if (qjsPath != null) 'quickjs:$qjsPath', 'node', 'bun'];
  }

  /// Resolves both tools. [executableDir] defaults to the directory
  /// holding the current executable. [pathLookup] finds a tool on
  /// PATH (defaults to `which` / `where`). [versionCheck] runs the
  /// tool's version flag and returns true when it exits 0.
  /// [jsRuntimeSupportCheck] reports whether a yt-dlp found on PATH
  /// understands `--js-runtimes`; it is not called for the bundled
  /// binary.
  static Future<ExternalTools> resolve({
    String? executableDir,
    Future<String?> Function(String name)? pathLookup,
    Future<bool> Function(String path)? versionCheck,
    Future<bool> Function(String path)? jsRuntimeSupportCheck,
  }) async {
    final dir = executableDir ?? p.dirname(Platform.resolvedExecutable);
    final lookup = pathLookup ?? _defaultPathLookup;
    final check = versionCheck ?? _defaultVersionCheck;
    final ffmpeg = await _resolveOne('ffmpeg', dir, lookup, check);
    final ytDlp = await _resolveOne('yt-dlp', dir, lookup, check);
    final qjs = await _resolveOne('qjs', dir, lookup, check);
    final supportsJsRuntimes = ytDlp == null || _isBundled(ytDlp, dir)
        ? true
        : await (jsRuntimeSupportCheck ?? _defaultJsRuntimeSupportCheck)(ytDlp);
    return ExternalTools(
      ffmpegPath: ffmpeg,
      ytDlpPath: ytDlp,
      qjsPath: qjs,
      ytDlpSupportsJsRuntimes: supportsJsRuntimes,
    );
  }

  static bool _isBundled(String path, String executableDir) =>
      p.equals(p.dirname(path), p.join(executableDir, 'bin'));

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
    // ffmpeg takes -version; --version exits 8. yt-dlp and quickjs
    // take --version. The basename is the tool name (ffmpeg,
    // ffmpeg.exe, yt-dlp, yt-dlp.exe, qjs, qjs.exe).
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

  /// True when [path]'s help text lists `--js-runtimes`. `--version`
  /// cannot answer this: yt-dlp ignores unknown options there and
  /// still exits 0.
  static Future<bool> _defaultJsRuntimeSupportCheck(String path) async {
    try {
      final result = await Process.run(path, ['--help']);
      return '${result.stdout}${result.stderr}'.contains('--js-runtimes');
    } catch (_) {
      return false;
    }
  }
}
