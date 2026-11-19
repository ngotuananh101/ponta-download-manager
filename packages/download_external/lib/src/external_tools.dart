import 'dart:io';

import 'external_tool_process.dart';

import 'package:path/path.dart' as p;

import 'external_tool_release.dart';
import 'external_tool_versions.dart';

/// Resolves usable tools from an optional user directory, the bundle, then PATH.
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
  }) : _origins = const {};

  ExternalTools._({required this.ffmpegPath, required this.ytDlpPath,
    required this.qjsPath, required this.ytDlpSupportsJsRuntimes,
    required Map<ExternalTool, ExternalToolOrigin> origins}) : _origins = origins;

  final Map<ExternalTool, ExternalToolOrigin> _origins;

  String? pathOf(ExternalTool tool) => switch (tool) {
    ExternalTool.ffmpeg => ffmpegPath,
    ExternalTool.ytDlp => ytDlpPath,
    ExternalTool.quickjs => qjsPath,
  };

  ExternalToolOrigin originOf(ExternalTool tool) => _origins[tool] ??
      (pathOf(tool) == null ? ExternalToolOrigin.missing : ExternalToolOrigin.system);

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

  /// Resolves tools, preferring verified files in [userToolsDir] when supplied.
  static Future<ExternalTools> resolve({
    String? executableDir,
    String? userToolsDir,
    bool? isWindows,
    Future<String?> Function(String name)? pathLookup,
    Future<bool> Function(String path)? versionCheck,
    Future<bool> Function(String path)? jsRuntimeSupportCheck,
  }) async {
    final dir = executableDir ?? p.dirname(Platform.resolvedExecutable);
    final lookup = pathLookup ?? _defaultPathLookup;
    final check = versionCheck ?? _defaultVersionCheck;
    final results = <ExternalTool, (String?, ExternalToolOrigin)>{};
    for (final tool in ExternalTool.values) {
      final name = tool.executableName(isWindows: isWindows ?? Platform.isWindows);
      if (userToolsDir != null) {
        final user = p.join(userToolsDir, name);
        if (await FileSystemEntity.type(user, followLinks: false) ==
            FileSystemEntityType.file && await check(user)) {
          results[tool] = (user, ExternalToolOrigin.downloaded);
          continue;
        }
      }
      final bundled = p.join(dir, 'bin', name);
      if (await File(bundled).exists() && await check(bundled)) {
        results[tool] = (bundled, ExternalToolOrigin.bundled);
        continue;
      }
      final system = await lookup(tool.executable);
      results[tool] = system != null && await check(system)
          ? (system, ExternalToolOrigin.system)
          : (null, ExternalToolOrigin.missing);
    }
    final (ytDlp, ytDlpOrigin) = results[ExternalTool.ytDlp]!;
    return ExternalTools._(
      ffmpegPath: results[ExternalTool.ffmpeg]!.$1,
      ytDlpPath: ytDlp,
      qjsPath: results[ExternalTool.quickjs]!.$1,
      ytDlpSupportsJsRuntimes: ytDlp == null ||
          ytDlpOrigin == ExternalToolOrigin.bundled ||
          await (jsRuntimeSupportCheck ?? _defaultJsRuntimeSupportCheck)(ytDlp),
      origins: Map.unmodifiable(results.map((tool, result) => MapEntry(tool, result.$2))),
    );
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
      final result = await runExternalToolProcess(path, args);
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
      final result = await runExternalToolProcess(path, ['--help']);
      return '${result.stdout}${result.stderr}'.contains('--js-runtimes');
    } catch (_) {
      return false;
    }
  }
}
