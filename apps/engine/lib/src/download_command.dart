import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

import 'cli.dart';
import 'engine_config.dart';
import 'pdm_engine.dart';

String _fileNameFromUrl(String url) {
  final segments = Uri.parse(url).pathSegments;
  final last = segments.isNotEmpty ? segments.last : '';
  return last.isEmpty ? 'download' : last;
}

/// Runs the `download` CLI command: downloads one URL and prints the
/// result. Returns the process exit code (0 on success).
Future<int> runDownload(CliResult result, {StringSink? out}) async {
  final sink = out ?? stdout;
  final url = result.url;
  if (url == null || url.isEmpty) {
    sink.writeln(engineUsage);
    return 2;
  }
  final directory = result.directory ?? 'downloads';
  final config = EngineConfig(
    downloadDirectory: directory,
    maxConnectionsPerDownload: result.maxConnections ?? 8,
  );
  final engine = PdmEngine.open(
    config: config,
    databasePath: result.databasePath,
  );
  if (result.globalLimitBytesPerSecond != null) {
    await engine.setGlobalBandwidthLimit(result.globalLimitBytesPerSecond);
  }
  var waitingId = '';
  final terminal = Completer<DownloadInfo>();
  final subscription = engine.events.listen((event) {
    event.when(
      progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {},
      stateChanged: (downloadId, status) {},
      completed: (eventId, filePath) async {
        if (eventId == waitingId && !terminal.isCompleted) {
          final downloads = await engine.listDownloads();
          final found = downloads.where((d) => d.id == eventId).toList();
          terminal.complete(
            found.isNotEmpty
                ? found.first
                : DownloadInfo(
                    id: eventId,
                    url: url,
                    fileName: _fileNameFromUrl(url),
                    status: DownloadStatus.completed,
                    totalBytes: -1,
                  ),
          );
        }
      },
      failed: (eventId, code, message) async {
        if (eventId == waitingId && !terminal.isCompleted) {
          terminal.completeError(DownloadError(code, message));
        }
      },
    );
  });
  try {
    final info = await engine.createDownload(
      CreateDownloadRequest(
        url: url,
        destination: p.join(directory, _fileNameFromUrl(url)),
        maxConnections: config.maxConnectionsPerDownload,
      ),
    );
    waitingId = info.id;
    sink.writeln('Downloading $url ...');
    final done = await terminal.future;
    sink.writeln(
      'Done: ${p.join(directory, done.fileName)} '
      '(${done.downloadedBytes} bytes)',
    );
    return 0;
  } on DownloadError catch (e) {
    sink.writeln('Failed: ${e.code} ${e.message}');
    return 1;
  } finally {
    await subscription.cancel();
    await engine.dispose();
  }
}
