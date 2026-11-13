import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

import 'yt_dlp_cookies.dart';
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

  /// Temp cookies file for this run, deleted when the run reaches a
  /// terminal state (or on shutdown). Null when no cookie was given
  /// or the file could not be created.
  TempCookieFile? cookieFile;
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
  /// terminal state (completed / failed / paused / cancelled). A run
  /// with cookies that fails at format selection is retried once
  /// without cookies (see [_run]).
  Stream<DownloadEvent> start({
    required String downloadId,
    required String url,
    required String outputTemplate,
    String? format,
    String? cookie,
    String? referrer,
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
    unawaited(
      _run(running, url, format: format, cookie: cookie, referrer: referrer),
    );
    return controller.stream;
  }

  Future<void> _run(
    _RunningDownload running,
    String url, {
    String? format,
    String? cookie,
    String? referrer,
  }) async {
    if (cookie != null && cookie.trim().isNotEmpty) {
      // Best effort: a run without cookies still proceeds when the
      // temp file cannot be created.
      try {
        running.cookieFile = TempCookieFile.create(
          cookieHeader: cookie,
          url: Uri.parse(url),
        );
      } catch (_) {
        running.cookieFile = null;
      }
    }
    // A failed run with cookies is retried once without them (see
    // the failure path at the end of this loop). The loop body keeps
    // its old indentation so the diff stays reviewable; every path
    // inside returns except the retry, which requires attempt 0.
    String? firstError;
    for (var attempt = 0; ; attempt++) {
    final args = [
      '--ffmpeg-location',
      ffmpegDir,
      '--newline',
      '--print',
      'after_move:filepath',
      // Progress goes to stdout, but --print suppresses it unless
      // --progress is also given. Without it the UI sees no
      // progress at all (the row stays queued until it completes).
      '--progress',
      '-o',
      running.outputTemplate,
      if (format != null && format.isNotEmpty) ...['-f', format],
      if (running.cookieFile != null) ...[
        '--cookies',
        running.cookieFile!.file.path,
      ],
      if (referrer != null && referrer.trim().isNotEmpty) ...[
        '--referer',
        referrer,
      ],
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
          // Error lines reach the UI; never surface cookie material.
          running.lastErrorLine = scrubCookieMaterial(
            line.trim(),
            running.cookieFile?.file.path,
          );
        }
      },
      onDone: stderrDone.complete,
    );
    final exitCode = await process.exitCode;
    if (running.shuttingDown) {
      // Engine shutdown: close the stream without an event. The
      // record stays non-terminal so recovery resumes it.
      running.cookieFile?.delete();
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
    // Format selection happens before any transfer, so a failure
    // here means nothing was downloaded yet: retrying without
    // cookies is safe. The original error is kept when the retry
    // fails too.
    if (attempt == 0 &&
        running.cookieFile != null &&
        message.contains('Requested format is not available')) {
      firstError = message;
      running.cookieFile?.delete();
      running.cookieFile = null;
      running.lastErrorLine = '';
      running.finalPath = null;
      continue;
    }
    _fail(running, 'yt-dlp-failed', firstError ?? message);
    return;
    } // for (attempt)
  }


  /// Probes [url] with `yt-dlp -J --no-playlist` and returns the video
  /// metadata and formats, or a `supported: false` result when no
  /// extractor matches or the probe fails. Never throws for a yt-dlp
  /// failure; those are reported in the result. The temp cookies file
  /// (when [cookie] is given) is deleted before this returns. A run
  /// with cookies that fails is retried once without them, so a bad
  /// cookie can never make a public video un-probeable.
  Future<YtDlpProbeResult> probe({
    required String url,
    String? cookie,
    String? referrer,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    TempCookieFile? cookieFile;
    if (cookie != null && cookie.trim().isNotEmpty) {
      try {
        cookieFile = TempCookieFile.create(
          cookieHeader: cookie,
          url: Uri.parse(url),
        );
      } catch (_) {
        // Best effort: probe without cookies when the temp file
        // cannot be created.
        cookieFile = null;
      }
    }
    try {
      final first = await _probeOnce(
        url: url,
        cookieFile: cookieFile,
        referrer: referrer,
        timeout: timeout,
      );
      // A failed run with cookies is retried once without them:
      // cookies must only ever add capability (login-walled videos),
      // never make a public video un-probeable. The original error is
      // kept when the retry fails too.
      if (cookieFile != null &&
          !first.supported &&
          first.errorCode != 'yt-dlp-unsupported' &&
          first.errorCode != 'yt-dlp-timeout') {
        final retry = await _probeOnce(
          url: url,
          referrer: referrer,
          timeout: timeout,
        );
        if (retry.supported) return retry;
      }
      return first;
    } finally {
      cookieFile?.delete();
    }
  }

  /// One `yt-dlp -J --no-playlist` run. Never throws for a yt-dlp
  /// failure; those are reported in the result. The temp cookies file
  /// (when [cookieFile] is given) is owned by the caller and deleted
  /// by it, so a retry can run without cookies afterwards.
  Future<YtDlpProbeResult> _probeOnce({
    required String url,
    TempCookieFile? cookieFile,
    String? referrer,
    required Duration timeout,
  }) async {
    {
      // One attempt, in a block so the old body keeps its shape.
      final args = <String>[
        '-J',
        '--no-playlist',
        if (cookieFile != null) ...[
          '--cookies',
          cookieFile.file.path,
        ],
        if (referrer != null && referrer.trim().isNotEmpty) ...[
          '--referer',
          referrer,
        ],
        url,
      ];
      Process process;
      try {
        process = await _processStarter(ytDlpPath, args);
      } catch (e) {
        return YtDlpProbeResult(
          supported: false,
          errorCode: 'yt-dlp-probe-failed',
          errorMessage: 'Could not start yt-dlp: $e',
        );
      }
      final stdoutBuffer = StringBuffer();
      final stderrLines = <String>[];
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => stdoutBuffer.writeln(line),
            onDone: stdoutDone.complete,
          );
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.trim().isNotEmpty) {
                stderrLines.add(line.trim());
              }
            },
            onDone: stderrDone.complete,
          );
      int exitCode;
      try {
        exitCode = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill();
        await stdoutSub.cancel();
        await stderrSub.cancel();
        return const YtDlpProbeResult(
          supported: false,
          errorCode: 'yt-dlp-timeout',
          errorMessage: 'yt-dlp probe timed out',
        );
      }
      await stdoutDone.future;
      await stderrDone.future;
      await stdoutSub.cancel();
      await stderrSub.cancel();
      // Error lines reach the UI; never surface cookie material.
      final lastError = stderrLines.isEmpty
          ? 'yt-dlp exited with code $exitCode'
          : scrubCookieMaterial(stderrLines.last, cookieFile?.file.path);
      if (exitCode == 0) {
        final result = _probeResultFromJson(stdoutBuffer.toString());
        if (result != null) {
          return result;
        }
        return const YtDlpProbeResult(
          supported: false,
          errorCode: 'yt-dlp-probe-failed',
          errorMessage: 'Could not parse yt-dlp output',
        );
      }
      if (stderrLines.any((line) => line.contains('Unsupported URL'))) {
        return YtDlpProbeResult(
          supported: false,
          errorCode: 'yt-dlp-unsupported',
          errorMessage: lastError,
        );
      }
      if (stderrLines.any(
        (line) =>
            line.contains('Video unavailable') ||
            line.contains('Private video'),
      )) {
        return YtDlpProbeResult(
          supported: false,
          errorCode: 'unavailable',
          errorMessage: lastError,
        );
      }
      return YtDlpProbeResult(
        supported: false,
        errorCode: 'yt-dlp-probe-failed',
        errorMessage: lastError,
      );
    }
  }

  /// Parses `yt-dlp -J` stdout into a probe result, or null when it
  /// is not a JSON object with at least one format.
  YtDlpProbeResult? _probeResultFromJson(String stdout) {
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final formats = <YtDlpFormat>[];
      final rawFormats = decoded['formats'];
      if (rawFormats is List) {
        for (final raw in rawFormats) {
          if (raw is Map<String, dynamic>) {
            final format = _formatFromJson(raw);
            if (format != null) {
              formats.add(format);
            }
          }
        }
      }
      if (formats.isEmpty) {
        return null;
      }
      final duration = decoded['duration'];
      return YtDlpProbeResult(
        supported: true,
        title: decoded['title'] as String?,
        thumbnail: decoded['thumbnail'] as String?,
        durationSeconds: duration is num ? duration.round() : null,
        formats: formats,
      );
    } catch (_) {
      return null;
    }
  }

  /// Maps one yt-dlp `-J` format object to [YtDlpFormat], or null
  /// when it has no format id. yt-dlp uses snake_case keys and
  /// numeric fields may be int or double.
  YtDlpFormat? _formatFromJson(Map<String, dynamic> json) {
    final formatId = json['format_id'];
    if (formatId is! String || formatId.isEmpty) {
      return null;
    }
    int? asInt(dynamic value) => value is num ? value.toInt() : null;
    double? asDouble(dynamic value) =>
        value is num ? value.toDouble() : null;
    return YtDlpFormat(
      formatId: formatId,
      ext: json['ext'] as String? ?? '',
      resolution: json['resolution'] as String?,
      width: asInt(json['width']),
      height: asInt(json['height']),
      filesize: asInt(json['filesize']),
      filesizeApprox: asInt(json['filesize_approx']),
      vcodec: json['vcodec'] as String? ?? 'none',
      acodec: json['acodec'] as String? ?? 'none',
      fps: asDouble(json['fps']),
      note: json['format_note'] as String?,
    );
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
  /// output file belonging to the template stem, excluding `.part`.
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
      if (!_isOwnOutput(name, stem)) {
        continue;
      }
      if (name.endsWith('.part')) {
        continue;
      }
      return entity.path;
    }
    return null;
  }

  /// Extensions yt-dlp can write for the `-o <stem>.%(ext)s` template
  /// (default merge, no --remux/--recode).
  static const _outputExtensions = <String>{
    'mp4',
    'mkv',
    'webm',
    'mov',
    'm4v',
    'avi',
    '3gp',
    'flv',
    'wmv',
    'mp3',
    'm4a',
    'opus',
    'ogg',
    'oga',
    'wav',
    'flac',
    'aac',
    'mka',
    'ts',
    'm2ts',
  };

  /// True when [name] is a file yt-dlp wrote for the template with
  /// this [stem]: `<stem>.<ext>` or a format intermediate
  /// `<stem>.f<id>.<ext>`, optionally with a `.part` suffix. A plain
  /// prefix match would also catch unrelated files in the same
  /// directory, e.g. `<stem>-notes.txt` or `<stem>2.mp4`.
  static bool _isOwnOutput(String name, String stem) {
    if (!name.startsWith('$stem.')) {
      return false;
    }
    var rest = name.substring(stem.length + 1);
    if (rest.endsWith('.part')) {
      rest = rest.substring(0, rest.length - 5);
    }
    final dot = rest.lastIndexOf('.');
    final ext = dot == -1 ? rest : rest.substring(dot + 1);
    if (!_outputExtensions.contains(ext)) {
      return false;
    }
    if (dot == -1) {
      return true;
    }
    return RegExp(r'^f\d+$').hasMatch(rest.substring(0, dot));
  }

  /// Deletes this download's own output files for the template
  /// (the finished file and any partials). Used by cancel and
  /// retry, where the download is restarted from scratch.
  void deleteOutput(String outputTemplate) {
    _deleteMatching(outputTemplate, partialOnly: false);
  }

  /// Deletes only this download's own `.part` files for the
  /// template. Used by delete, where a finished file on disk is kept.
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
      if (!_isOwnOutput(name, stem)) {
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
    running.cookieFile?.delete();
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
