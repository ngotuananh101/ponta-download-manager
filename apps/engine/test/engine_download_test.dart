import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_external/download_external.dart';
import 'package:pdm_engine/pdm_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<int> bytesOf(int length, [int seed = 0]) =>
    List<int>.generate(length, (i) => (i + seed) % 256);

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _TestServer {
  _TestServer({
    required this.data,
    this.chunkDelay = const Duration(milliseconds: 10),
    this.failFirst = 0,
    this.chunkSize = 256,
  });

  final List<int> data;
  final Duration chunkDelay;
  final int failFirst;

  /// Bytes written per response flush. Must be large (64 KiB) for the
  /// client to see chunks arrive separately: Dart's HttpClient
  /// coalesces small writes into one chunk delivered at close time,
  /// so a pause issued after the first progress event would arrive
  /// after the download already finished.
  final int chunkSize;

  late HttpServer _server;
  var _requests = 0;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() async => _server.close();

  Future<void> _handle(HttpRequest request) async {
    _requests++;
    final response = request.response;
    if (_requests <= failFirst) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.contentType = ContentType.binary;
    if (request.method == 'HEAD') {
      response.headers.contentLength = data.length;
      await response.close();
      return;
    }
    final range = request.headers.value('range');
    var start = 0;
    var end = data.length - 1;
    if (range != null) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
      if (match != null) {
        start = int.parse(match.group(1)!);
        end = match.group(2)!.isEmpty
            ? data.length - 1
            : int.parse(match.group(2)!);
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          'Content-Range',
          'bytes $start-$end/${data.length}',
        );
      }
    }
    response.headers.contentLength = end - start + 1;
    var offset = start;
    while (offset <= end) {
      await Future<void>.delayed(chunkDelay);
      final next = (offset + chunkSize - 1).clamp(0, end);
      response.add(data.sublist(offset, next + 1));
      // Flush per chunk: without this the response is buffered and the
      // client receives everything at once, so a pause issued after the
      // first progress event arrives after the download already finished.
      await response.flush();
      offset = next + 1;
    }
    await response.close();
  }
}

Future<DownloadInfo> waitForInfo(
  PdmEngine engine,
  String id,
  bool Function(DownloadInfo) matches, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final downloads = await engine.listDownloads();
    final found = downloads.where((d) => d.id == id).toList();
    if (found.isNotEmpty && matches(found.first)) {
      return found.first;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for $id');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('parseCliArgs flags', () {
    const url = 'http://example.test/f.bin';

    test('download captures --dir, --connections, --db and --limit', () {
      final result = parseCliArgs([
        'download',
        url,
        '--dir',
        '/tmp/x',
        '--connections',
        '2',
        '--db',
        '/tmp/p.db',
        '--limit',
        '1024',
      ]);
      expect(result.command, 'download');
      expect(result.url, url);
      expect(result.directory, '/tmp/x');
      expect(result.maxConnections, 2);
      expect(result.databasePath, '/tmp/p.db');
      expect(result.globalLimitBytesPerSecond, 1024);
    });

    test('download flags default to null', () {
      final result = parseCliArgs(['download', url]);
      expect(result.directory, isNull);
      expect(result.maxConnections, isNull);
      expect(result.databasePath, isNull);
      expect(result.globalLimitBytesPerSecond, isNull);
    });
  });

  group('PdmEngine', () {
    late Directory tempDir;
    late _TestServer server;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-engine-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    PdmEngine openEngine({
      int maxConcurrent = 3,
      int maxConnections = 8,
      ExternalTools? externalTools,
      YtDlpDownloader? ytDlpDownloader,
    }) {
      return PdmEngine.open(
        config: EngineConfig(
          downloadDirectory: tempDir.path,
          maxConcurrentDownloads: maxConcurrent,
          maxConnectionsPerDownload: maxConnections,
        ),
        databasePath: p.join(tempDir.path, 'pdm.db'),
        externalTools: externalTools,
        ytDlpDownloader: ytDlpDownloader,
      );
    }

    Future<String> makeFakeYtDlp(String script) async {
      final file = File(p.join(tempDir.path, 'yt-dlp'));
      await file.writeAsString(script);
      await Process.run('chmod', ['+x', file.path]);
      return file.path;
    }

    Future<void> startServer({
      required List<int> data,
      Duration chunkDelay = const Duration(milliseconds: 10),
      int failFirst = 0,
      int chunkSize = 256,
    }) async {
      server = _TestServer(
        data: data,
        chunkDelay: chunkDelay,
        failFirst: failFirst,
        chunkSize: chunkSize,
      );
      await server.start();
      addTearDown(server.close);
    }

    test('downloads a file end to end', () async {
      final data = bytesOf(4096);
      await startServer(data: data);
      final engine = openEngine(maxConnections: 2);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      expect(info.status, DownloadStatus.queued);
      expect(info.createdAt, isNotNull);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, 4096);
      expect(done.totalBytes, 4096);
      final file = File(p.join(tempDir.path, 'f.bin'));
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), data);
      final downloads = await engine.listDownloads();
      expect(downloads.length, 1);
      expect(downloads.first.id, info.id);
      expect(downloads.first.createdAt, isNotNull);
      expect(
        DateTime.now()
            .difference(downloads.first.createdAt!)
            .inSeconds
            .abs(),
        lessThan(60),
      );
    });

    test('pauses and resumes a download', () async {
      final data = bytesOf(262144);
      await startServer(
        data: data,
        chunkDelay: const Duration(milliseconds: 20),
        chunkSize: 65536,
      );
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      // Wait for the first progress event: the store only learns about
      // progress from the checkpoint writer (1s interval), which is
      // slower than this download.
      final started = Completer<void>();
      final subscription = engine.events.listen((event) {
        event.when(
          progress: (eventId, downloaded, total, speed) {
            if (eventId == info.id &&
                downloaded > 0 &&
                !started.isCompleted) {
              started.complete();
            }
          },
          stateChanged: (eventId, status) {},
          completed: (eventId, filePath) {},
          failed: (eventId, code, message) {},
        );
      });
      addTearDown(subscription.cancel);
      await started.future.timeout(const Duration(seconds: 10));
      await engine.pauseDownload(info.id);
      final paused = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.paused && d.downloadedBytes > 0,
      );
      expect(paused.downloadedBytes, lessThan(262144));
      await engine.resumeDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(await File(p.join(tempDir.path, 'f.bin')).readAsBytes(), data);
    });

    test('resumes a paused download after a restart', () async {
      final data = bytesOf(8192);
      await startServer(
        data: data,
        chunkDelay: const Duration(milliseconds: 20),
      );
      final first = openEngine(maxConnections: 2);
      final info = await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(first, info.id, (d) => d.downloadedBytes > 0);
      await first.pauseDownload(info.id);
      await waitForInfo(
        first,
        info.id,
        (d) => d.status == DownloadStatus.paused,
      );
      await first.dispose();
      final second = openEngine(maxConnections: 2);
      addTearDown(second.dispose);
      await waitForInfo(
        second,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(await File(p.join(tempDir.path, 'f.bin')).readAsBytes(), data);
      final downloads = await second.listDownloads();
      expect(downloads.length, 1);
      expect(downloads.first.id, info.id);
    });

    test('retries a download after a failure', () async {
      final data = bytesOf(2048);
      await startServer(data: data, failFirst: 1);
      final engine = openEngine();
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.failed,
      );
      await engine.retryDownload(info.id);
      // The retry reuses the same id: the same download restarts, no
      // second record is created and no other download is touched.
      final downloads = await engine.listDownloads();
      expect(downloads.length, 1);
      expect(downloads.first.id, info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(await File(p.join(tempDir.path, 'f.bin')).readAsBytes(), data);
    });

    test('deleteDownload removes the record and drops the partial',
        () async {
      final data = bytesOf(10 * 1024 * 1024);
      await startServer(data: data);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(engine, info.id, (d) => d.downloadedBytes > 0);
      await engine.pauseDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.paused,
      );
      final partial = File(p.join(tempDir.path, 'f.bin.partial'));
      expect(await partial.exists(), isTrue);
      await engine.deleteDownload(info.id);
      expect(await engine.listDownloads(), isEmpty);
      // The partial is dropped; there is no finished file to keep.
      expect(await partial.exists(), isFalse);
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isFalse);
    });

    test('deleteDownload keeps the finished file on disk', () async {
      final data = bytesOf(2048);
      await startServer(data: data);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      await engine.deleteDownload(info.id);
      expect(await engine.listDownloads(), isEmpty);
      // Deleting a row must not delete a file another row still
      // references, so the finished file stays on disk.
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isTrue);
    });

    test('a paused download stays paused after a restart', () async {
      final data = bytesOf(256 * 1024);
      await startServer(data: data, chunkSize: 1024);
      final first = openEngine(maxConnections: 1);
      final created = await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      // Wait until it is downloading with some bytes, then pause it.
      await waitForInfo(
        first,
        created.id,
        (d) =>
            d.status == DownloadStatus.downloading &&
            d.downloadedBytes > 0,
      );
      await first.pauseDownload(created.id);
      await waitForInfo(
        first,
        created.id,
        (d) => d.status == DownloadStatus.paused,
      );
      final pausedBytes = (await first.listDownloads())
          .firstWhere((d) => d.id == created.id)
          .downloadedBytes;
      expect(pausedBytes, greaterThan(0));
      await first.dispose();
      // Re-open: the paused download must stay paused, not resume.
      final second = openEngine(maxConnections: 1);
      addTearDown(second.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final afterRestart = (await second.listDownloads())
          .firstWhere((d) => d.id == created.id);
      expect(afterRestart.status, DownloadStatus.paused);
      expect(afterRestart.downloadedBytes, pausedBytes);
      // And resuming it after the restart still works.
      await second.resumeDownload(created.id);
      final done = await waitForInfo(
        second,
        created.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, data.length);
      expect(File(p.join(tempDir.path, 'f.bin')).readAsBytesSync(), data);
    });

    test('a retry after a restart does not overwrite other downloads',
        () async {
      final data = bytesOf(1024);
      await startServer(data: data);
      final first = openEngine(maxConnections: 1);
      final a = await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/a.bin',
          destination: p.join(tempDir.path, 'a.bin'),
        ),
      );
      final b = await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/b.bin',
          destination: p.join(tempDir.path, 'b.bin'),
        ),
      );
      final c = await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/c.bin',
          destination: p.join(tempDir.path, 'c.bin'),
        ),
      );
      // Make all three terminal (cancelled) so a restart does not
      // re-enqueue them and seed the scheduler's id counter.
      await first.cancelDownload(a.id);
      await first.cancelDownload(b.id);
      await first.cancelDownload(c.id);
      await waitForInfo(
        first,
        a.id,
        (d) => d.status == DownloadStatus.cancelled,
      );
      await waitForInfo(
        first,
        b.id,
        (d) => d.status == DownloadStatus.cancelled,
      );
      await waitForInfo(
        first,
        c.id,
        (d) => d.status == DownloadStatus.cancelled,
      );
      await first.dispose();
      // Re-open: all three are terminal, so recovery re-enqueues
      // nothing and the counter would restart at 0 without the fix.
      final second = openEngine(maxConnections: 1);
      addTearDown(second.dispose);
      // Retry the last download twice, as the user did.
      await second.retryDownload(c.id);
      await second.retryDownload(c.id);
      final downloads = await second.listDownloads();
      expect(downloads.length, 3);
      expect(
        downloads.map((d) => d.fileName).toList(),
        ['a.bin', 'b.bin', 'c.bin'],
      );
      expect(downloads.map((d) => d.id).toSet().length, 3);
    });

    test('setPriority reorders queued downloads', () async {
      final data = bytesOf(8192);
      await startServer(
        data: data,
        chunkDelay: const Duration(milliseconds: 20),
      );
      final engine = openEngine(maxConcurrent: 1, maxConnections: 1);
      addTearDown(engine.dispose);
      final first = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'a.bin'),
        ),
      );
      final second = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'b.bin'),
        ),
      );
      final third = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'c.bin'),
        ),
      );
      await engine.setPriority(third.id, 10);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        final downloads = await engine.listDownloads();
        final byId = {for (final d in downloads) d.id: d};
        final thirdInfo = byId[third.id]!;
        final secondInfo = byId[second.id]!;
        if ((thirdInfo.status == DownloadStatus.downloading ||
                thirdInfo.status == DownloadStatus.completed) &&
            secondInfo.status == DownloadStatus.queued) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'third did not start before second: '
            'third=${thirdInfo.status}, second=${secondInfo.status}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await waitForInfo(
        engine,
        first.id,
        (d) => d.status == DownloadStatus.completed,
      );
      await waitForInfo(
        engine,
        third.id,
        (d) => d.status == DownloadStatus.completed,
      );
      await waitForInfo(
        engine,
        second.id,
        (d) => d.status == DownloadStatus.completed,
      );
    });

    test('setGlobalBandwidthLimit throttles downloads', () async {
      final data = bytesOf(2048);
      await startServer(data: data);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      await engine.setGlobalBandwidthLimit(1024);
      final stopwatch = Stopwatch()..start();
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(700));
      expect(await File(p.join(tempDir.path, 'f.bin')).readAsBytes(), data);
    });
    group('yt-dlp downloads', () {
      const successScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo "[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30"
echo "[download]  50.0% of  100.00MiB at  2.00MiB/s ETA 00:25"
echo "[download] 100% of  100.00MiB in 00:01"
mkdir -p "$(dirname "$final")"
touch "$final"
echo "$final"
exit 0
''';

      const slowScript = r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
final=$(printf '%s' "$out" | sed 's/%(ext)s/mp4/')
echo "[download]  10.0% of  100.00MiB at  1.00MiB/s ETA 01:30"
mkdir -p "$(dirname "$final")"
touch "$final.part"
sleep 3
echo "[download] 100% of  100.00MiB in 00:03"
touch "$final"
echo "$final"
exit 0
''';

      test('an m3u8 url downloads via yt-dlp and completes with the real file',
          () async {
        final fake = await makeFakeYtDlp(successScript);
        final engine = openEngine(
          ytDlpDownloader: YtDlpDownloader(
            ytDlpPath: fake,
            ffmpegDir: tempDir.path,
          ),
        );
        addTearDown(engine.dispose);
        final info = await engine.createDownload(
          CreateDownloadRequest(
            url: 'https://example.com/live.m3u8',
            destination: p.join(tempDir.path, 'live.m3u8'),
          ),
        );
        expect(info.id.startsWith('yt-'), isTrue);
        final done = await waitForInfo(
          engine,
          info.id,
          (d) => d.status == DownloadStatus.completed,
        );
        expect(done.fileName, 'live.mp4');
        expect(done.filePath, p.join(tempDir.path, 'live.mp4'));
        expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isTrue);
      });

      test('a normal url still uses the native scheduler', () async {
        final data = bytesOf(2048);
        await startServer(data: data);
        final fake = await makeFakeYtDlp(successScript);
        final engine = openEngine(
          ytDlpDownloader: YtDlpDownloader(
            ytDlpPath: fake,
            ffmpegDir: tempDir.path,
          ),
        );
        addTearDown(engine.dispose);
        final info = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
          ),
        );
        expect(info.id.startsWith('dl-'), isTrue);
        final done = await waitForInfo(
          engine,
          info.id,
          (d) => d.status == DownloadStatus.completed,
        );
        expect(done.fileName, 'f.bin');
        expect(File(p.join(tempDir.path, 'f.bin')).readAsBytesSync(), data);
      });

      test('an m3u8 url without the tools throws external-tools-missing',
          () async {
        final engine = openEngine(
          externalTools: const ExternalTools(
            ffmpegPath: null,
            ytDlpPath: null,
          ),
        );
        addTearDown(engine.dispose);
        await expectLater(
          engine.createDownload(
            CreateDownloadRequest(
              url: 'https://example.com/live.m3u8',
              destination: p.join(tempDir.path, 'live.m3u8'),
            ),
          ),
          throwsA(
            isA<DownloadError>().having(
              (e) => e.code,
              'code',
              'external-tools-missing',
            ),
          ),
        );
        expect(await engine.listDownloads(), isEmpty);
      });

      test('a yt-dlp download pauses and resumes', () async {
        final fake = await makeFakeYtDlp(slowScript);
        final engine = openEngine(
          ytDlpDownloader: YtDlpDownloader(
            ytDlpPath: fake,
            ffmpegDir: tempDir.path,
          ),
        );
        addTearDown(engine.dispose);
        final info = await engine.createDownload(
          CreateDownloadRequest(
            url: 'https://example.com/live.m3u8',
            destination: p.join(tempDir.path, 'live.m3u8'),
          ),
        );
        await waitForInfo(
          engine,
          info.id,
          (d) =>
              d.status == DownloadStatus.downloading &&
              d.downloadedBytes > 0,
        );
        await engine.pauseDownload(info.id);
        final paused = await waitForInfo(
          engine,
          info.id,
          (d) => d.status == DownloadStatus.paused,
        );
        expect(paused.downloadedBytes, greaterThan(0));
        await engine.resumeDownload(info.id);
        final done = await waitForInfo(
          engine,
          info.id,
          (d) => d.status == DownloadStatus.completed,
        );
        expect(done.fileName, 'live.mp4');
        expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isTrue);
      });

      test('a paused yt-dlp download stays paused after a restart',
          () async {
        final fake = await makeFakeYtDlp(slowScript);
        final first = openEngine(
          ytDlpDownloader: YtDlpDownloader(
            ytDlpPath: fake,
            ffmpegDir: tempDir.path,
          ),
        );
        final created = await first.createDownload(
          CreateDownloadRequest(
            url: 'https://example.com/live.m3u8',
            destination: p.join(tempDir.path, 'live.m3u8'),
          ),
        );
        await waitForInfo(
          first,
          created.id,
          (d) =>
              d.status == DownloadStatus.downloading &&
              d.downloadedBytes > 0,
        );
        await first.pauseDownload(created.id);
        await waitForInfo(
          first,
          created.id,
          (d) => d.status == DownloadStatus.paused,
        );
        await first.dispose();
        final second = openEngine(
          ytDlpDownloader: YtDlpDownloader(
            ytDlpPath: fake,
            ffmpegDir: tempDir.path,
          ),
        );
        addTearDown(second.dispose);
        final restored = await waitForInfo(
          second,
          created.id,
          (d) => d.status == DownloadStatus.paused,
        );
        expect(restored.downloadedBytes, greaterThan(0));
        await second.resumeDownload(created.id);
        final done = await waitForInfo(
          second,
          created.id,
          (d) => d.status == DownloadStatus.completed,
        );
        expect(done.fileName, 'live.mp4');
      });
    });

  });

  group('runDownload command', () {
    test('downloads a file and returns exit code 0', () async {
      final data = bytesOf(2048);
      final server = _TestServer(data: data);
      await server.start();
      addTearDown(server.close);
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-engine-cli-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final out = StringBuffer();
      final code = await runDownload(
        CliResult(
          command: 'download',
          url: 'http://127.0.0.1:${server.port}/f.bin',
          directory: tempDir.path,
          databasePath: p.join(tempDir.path, 'pdm.db'),
          maxConnections: 2,
        ),
        out: out,
      );
      expect(code, 0);
      expect(out.toString(), contains('Done'));
      expect(
        await File(p.join(tempDir.path, 'f.bin')).readAsBytes(),
        data,
      );
    });

  });
}
