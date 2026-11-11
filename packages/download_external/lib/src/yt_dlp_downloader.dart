import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

import 'yt_dlp_progress.dart';

/// Starts a process. Injectable so tests can use a fake yt-dlp.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

class _RunningDownload {
  _RunningDownload({
    required this.downloadId,
    required this.controller,
    required this.outputTemplate,
    required this.outputDir,
  });

  final String downloadId;
  final StreamController<DownloadEvent> controller;
  final String outputTemplate;
  final String outputDir;
  Process? process;
  String? finalPath;
  String lastErrorLine = '';
  bool paused = false;
  bool cancelled = false;

  /// True when the engine is shutting down: the process is killed
  /// but no terminal event is emitted, so the record stays
  /// non-terminal and recovery resumes it on restart.
  bool shuttingDown = false;

  /// Completes when the run is fully cleaned up (removed from
  /// _running). pause/cancel await it so a following resume cannot
  /// trip over a run that is still being torn down.
  final done = Completer<void>();
}

/// Runs yt-dlp as a subprocess for one download, translating its
/// stdout into [DownloadEvent]s.
///
/// The process is started as:
/// `yt-dlp --ffmpeg-location <dir> --newline --print after_move:filepath -o <template> <url>`
/// `--newline` forces one progress line per update (parseable);
/// `--print after_move:filepath` reports the final file path, because
/// yt-dlp chooses the extension (mp4/mkv) itself.
///
/// Only the download's own stream is exposed; the engine merges it
/// into its event stream. Pause kills the process and keeps the
/// partial output; resume re-runs yt-dlp with the same template.
/// Cancel kills the process and deletes the output.
class YtDlpDownloader {
  YtDlpDownloader({
    required this.ytDlpPath,
    required this.ffmpegDir,
    ProcessStarter? processStarter,
  }) : _processStarter = processStarter ?? Process.start;

  final String ytDlpPath;
  final String ffmpegDir;
  final ProcessStarter _processStarter;

  final _running = <String, _RunningDownload>{};

  bool get isRunning => _running.isNotEmpty;

  /// Starts downloading [url]. [outputTemplate] is the yt-dlp `-o`
  /// template (e.g. `/dir/live.%(ext)s`). Returns the event stream
  /// for this download; it closes when the download reaches a
  /// terminal state (completed / failed / paused / cancelled).
  Stream<DownloadEvent> start({
    required String downloadId,
    required String url,
    required String outputTemplate,
  }) {
    if (_running.containsKey(downloadId)) {
      throw StateError('Download $downloadId is already running');
    }
    final controller = StreamController<DownloadEvent>.broadcast();
    final running = _RunningDownload(
      downloadId: downloadId,
      controller: controller,
      outputTemplate: outputTemplate,
      outputDir: p.dirname(outputTemplate),
    );
    _running[downloadId] = running;
    unawaited(_run(running, url));
    return controller.stream;
  }

  Future<void> _run(_RunningDownload running, String url) async {
    final args = [
      '--ffmpeg-location',
      ffmpegDir,
      '--newline',
      '--print',
      'after_move:filepath',
      '-o',
      running.outputTemplate,
      url,
    ];
    Process process;
    try {
      process = await _processStarter(ytDlpPath, args);
    } catch (e) {
      _fail(running, 'yt-dlp-spawn-failed', 'Could not start yt-dlp: $e');
      return;
    }
    running.process = process;
    // Wait for the output streams to drain, not just for exitCode:
    // exitCode can complete before the last stdout lines (including
    // the printed final path) have been delivered to the listener.
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final stdoutLines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stderrLines = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final stdoutSub = stdoutLines.listen(
      (line) => _onStdout(running, line),
      onDone: stdoutDone.complete,
    );
    final stderrSub = stderrLines.listen(
      (line) {
        if (line.trim().isNotEmpty) {
          running.lastErrorLine = line.trim();
        }
      },
      onDone: stderrDone.complete,
    );
    final exitCode = await process.exitCode;
    if (running.shuttingDown) {
      // Engine shutdown: close the stream without an event. The
      // record stays non-terminal so recovery resumes it.
      _running.remove(running.downloadId);
      unawaited(running.controller.close());
      running.done.complete();
      return;
    }
    if (!running.paused && !running.cancelled) {
      // Normal exit: drain the output so the final printed path and
      // the last progress lines are not lost. After a pause/cancel
      // the process was killed and a child may hold the pipe open,
      // so the streams are not awaited there (those lines are not
      // needed for a paused/cancelled download).
      await stdoutDone.future;
      await stderrDone.future;
    }
    await stdoutSub.cancel();
    await stderrSub.cancel();
    if (running.cancelled) {
      deleteOutput(running.outputTemplate);
      _finish(
        running,
        DownloadEvent.stateChanged(
          downloadId: running.downloadId,
          status: DownloadStatus.cancelled,
        ),
      );
      return;
    }
    if (running.paused) {
      _finish(
        running,
        DownloadEvent.stateChanged(
          downloadId: running.downloadId,
          status: DownloadStatus.paused,
        ),
      );
      return;
    }
    if (exitCode == 0) {
      final filePath = running.finalPath ?? _globFinalPath(running);
      if (filePath == null) {
        _fail(
          running,
          'yt-dlp-no-output',
          'yt-dlp finished but produced no file',
        );
        return;
      }
      _finish(
        running,
        DownloadEvent.completed(
          downloadId: running.downloadId,
          filePath: filePath,
        ),
      );
      return;
    }
    final message = running.lastErrorLine.isNotEmpty
        ? running.lastErrorLine
        : 'yt-dlp exited with code $exitCode';
    _fail(running, 'yt-dlp-failed', message);
  }

  void _onStdout(_RunningDownload running, String line) {
    final progress = parseYtDlpProgress(line);
    if (progress != null) {
      running.controller.add(
        DownloadEvent.progress(
          downloadId: running.downloadId,
          downloadedBytes: progress.downloadedBytes,
          totalBytes: progress.totalBytes,
          bytesPerSecond: progress.bytesPerSecond,
        ),
      );
      return;
    }
    // The `--print after_move:filepath` line is a bare absolute path
    // inside the output directory (not a `[xxx]` log line).
    final trimmed = line.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('[') &&
        p.isAbsolute(trimmed) &&
        p.isWithin(running.outputDir, trimmed) &&
        !trimmed.endsWith('.part')) {
      running.finalPath = trimmed;
    }
  }

  /// Fallback when the printed final path was not captured: the
  /// output file matching the template stem, excluding `.part`.
  String? _globFinalPath(_RunningDownload running) {
    final stem = p
        .basename(running.outputTemplate)
        .replaceAll('.%(ext)s', '');
    final dir = Directory(running.outputDir);
    if (!dir.existsSync()) {
      return null;
    }
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = p.basename(entity.path);
      if (!name.startsWith(stem)) {
        continue;
      }
      if (name.endsWith('.part')) {
        continue;
      }
      return entity.path;
    }
    return null;
  }

  /// Deletes every file matching the output template stem
  /// (the finished file and any partial). Used by cancel and retry,
  /// where the download is restarted from scratch.
  void deleteOutput(String outputTemplate) {
    _deleteMatching(outputTemplate, partialOnly: false);
  }

  /// Deletes only the `.part` files matching the output template
  /// stem. Used by delete, where a finished file on disk is kept.
  void deletePartial(String outputTemplate) {
    _deleteMatching(outputTemplate, partialOnly: true);
  }

  void _deleteMatching(String outputTemplate, {required bool partialOnly}) {
    final stem = p.basename(outputTemplate).replaceAll('.%(ext)s', '');
    final dir = Directory(p.dirname(outputTemplate));
    if (!dir.existsSync()) {
      return;
    }
    for (final entity in dir.listSync()) {
      if (entity is! File) {
        continue;
      }
      final name = p.basename(entity.path);
      if (!name.startsWith(stem)) {
        continue;
      }
      if (partialOnly && !name.endsWith('.part')) {
        continue;
      }
      try {
        entity.deleteSync();
      } catch (_) {
        // Best effort: the file may already be gone.
      }
    }
  }

  void _fail(_RunningDownload running, String code, String message) {
    _finish(
      running,
      DownloadEvent.failed(
        downloadId: running.downloadId,
        code: code,
        message: message,
      ),
    );
  }

  void _finish(_RunningDownload running, DownloadEvent event) {
    _running.remove(running.downloadId);
    running.controller.add(event);
    unawaited(running.controller.close());
    running.done.complete();
  }

  /// Kills the process, keeping the partial output (pause).
  /// Waits until the run is fully cleaned up, so a following resume
  /// cannot trip over a run that is still being torn down.
  Future<void> pause(String downloadId) async {
    final running = _running[downloadId];
    if (running == null) {
      return;
    }
    running.paused = true;
    running.process?.kill();
    await running.done.future;
  }

  /// Kills the process and deletes the output/partial (cancel).
  /// Waits until the run is fully cleaned up.
  Future<void> cancel(String downloadId) async {
    final running = _running[downloadId];
    if (running == null) {
      return;
    }
    running.cancelled = true;
    running.process?.kill();
    await running.done.future;
  }

  /// Kills all running processes without emitting a terminal event
  /// (engine shutdown). Their records stay non-terminal so recovery
  /// resumes them on restart.
  Future<void> shutdown() async {
    for (final running in _running.values.toList()) {
      running.shuttingDown = true;
      running.process?.kill();
    }
  }
}
