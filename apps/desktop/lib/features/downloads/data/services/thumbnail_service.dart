import 'dart:async';
import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/core/app_data_dir.dart';

import '../../domain/entities/download.dart';

/// File extensions Flutter can display directly with [Image.file].
const imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

/// Video extensions ffmpeg can extract a still frame from.
const videoExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'flv',
  'webm',
  'm4v',
  'mpg',
  'mpeg',
  '3gp',
  'ts',
  'm2ts',
  'vob',
  'ogv',
};

/// Runs a process: the executable is [args.first]. Injectable in tests.
typedef ProcessRunner = Future<ProcessResult> Function(
  List<String> args, {
  Duration? timeout,
});

/// Resolves a thumbnail image for a completed download, for the
/// details panel's GENERAL tab.
///
/// Images are shown directly (the downloaded file itself). Videos get
/// a still frame extracted with the bundled ffmpeg, cached under the
/// app data dir so it is extracted once per file. Anything else —
/// non-media, still downloading, missing file, no ffmpeg, a failed
/// extraction — returns null and the panel falls back to its icon.
class ThumbnailService {
  ThumbnailService({
    String? ffmpegPath,
    String? cacheDir,
    ProcessRunner? runProcess,
  })  : _ffmpegPath = ffmpegPath,
        _cacheDir = cacheDir,
        _runProcess = runProcess ?? _defaultRunProcess;

  final String? _ffmpegPath;
  final String? _cacheDir;
  final ProcessRunner _runProcess;

  Future<String?> thumbnailFor(Download download) async {
    if (download.state != DownloadState.completed) return null;
    final filePath = download.filePath;
    if (filePath == null) return null;
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    if (imageExtensions.contains(ext)) {
      // A sync check: the image shows on the next frame after the
      // panel opens, with no async hop for pumpAndSettle to outrun.
      return File(filePath).existsSync() ? filePath : null;
    }
    if (!videoExtensions.contains(ext)) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final stat = await file.stat();
      final dir = Directory(_cacheDir ?? _defaultCacheDir());
      final thumbPath = p.join(
        dir.path,
        '${download.id}_${stat.size}_'
        '${stat.modified.millisecondsSinceEpoch}.jpg',
      );
      if (await File(thumbPath).exists()) return thumbPath;
      final ffmpeg = await _resolveFfmpeg();
      if (ffmpeg == null) return null;
      await dir.create(recursive: true);
      await _deleteStaleThumbs(dir, download.id);
      final extracted = await _extractFrame(
        ffmpeg: ffmpeg,
        video: filePath,
        out: thumbPath,
      );
      return extracted ? thumbPath : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveFfmpeg() async {
    if (_ffmpegPath != null) return _ffmpegPath;
    try {
      final tools = await ExternalTools.resolve();
      return tools.ffmpegPath;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _extractFrame({
    required String ffmpeg,
    required String video,
    required String out,
  }) async {
    // A frame 1s in; short clips fall back to the first frame.
    for (final seek in ['1', '0']) {
      try {
        final result = await _runProcess([
          ffmpeg,
          '-y',
          '-v',
          'error',
          '-ss',
          seek,
          '-i',
          video,
          '-frames:v',
          '1',
          '-vf',
          'scale=240:-1',
          out,
        ], timeout: const Duration(seconds: 15));
        if (result.exitCode == 0 && await File(out).exists()) {
          return true;
        }
      } catch (_) {
        // Try the next seek, then give up.
      }
    }
    return false;
  }

  Future<void> _deleteStaleThumbs(Directory dir, String id) async {
    try {
      await for (final entry in dir.list()) {
        final name = p.basename(entry.path);
        if (name.startsWith('${id}_') && name.endsWith('.jpg')) {
          await entry.delete();
        }
      }
    } catch (_) {
      // Best effort: a stale thumbnail only wastes disk.
    }
  }

  static String _defaultCacheDir() => p.join(defaultAppDataDir(), 'thumbs');

  static Future<ProcessResult> _defaultRunProcess(
    List<String> args, {
    Duration? timeout,
  }) async {
    final process = await Process.start(args.first, args.sublist(1));
    unawaited(process.stdout.drain());
    unawaited(process.stderr.drain());
    final limit = timeout ?? const Duration(seconds: 15);
    final code = await process.exitCode.timeout(
      limit,
      onTimeout: () {
        process.kill();
        return process.exitCode;
      },
    );
    return ProcessResult(process.pid, code, '', '');
  }
}
