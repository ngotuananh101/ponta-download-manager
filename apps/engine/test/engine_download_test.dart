import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_recovery/download_recovery.dart';
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

  // Mutable on purpose: a test can swap the hosted file between
  // requests, so the same URL reports a different size.
  List<int> data;
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

  /// How many requests this server has served (for proving which URL
  /// a download actually tried).
  int get requests => _requests;

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

    test('probeUrl returns the file name and size', () async {
      final data = bytesOf(4096);
      await startServer(data: data);
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final probe = await engine.probeUrl(
        'http://127.0.0.1:${server.port}/f.bin',
      );
      expect(probe.fileName, 'f.bin');
      expect(probe.totalBytes, 4096);
    });

    test('probeUrl rejects a non-http URL', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      expect(
        engine.probeUrl('ftp://example.com/f.bin'),
        throwsA(
          isA<DownloadError>().having((e) => e.code, 'code', 'invalid-url'),
        ),
      );
    });

    test('probeUrl reports a playlist size as unknown without probing',
        () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      // A dead port: the probe must not touch the network for playlists.
      final probe = await engine.probeUrl(
        'http://127.0.0.1:9/stream.m3u8',
      );
      expect(probe.fileName, 'stream.m3u8');
      expect(probe.totalBytes, -1);
    });

    test('createDownload with paused stays paused until resumed', () async {
      final data = bytesOf(4096);
      await startServer(data: data);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
          paused: true,
        ),
      );
      expect(info.status, DownloadStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final listed = await engine.listDownloads();
      final row = listed.firstWhere((d) => d.id == info.id);
      expect(row.status, DownloadStatus.paused);
      expect(row.downloadedBytes, 0);
      expect(File(p.join(tempDir.path, 'f.bin')).existsSync(), isFalse);
      await engine.resumeDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, 4096);
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

    test('deleteDownload with deleteFile removes the finished file',
        () async {
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
      await engine.deleteDownload(info.id, deleteFile: true);
      expect(await engine.listDownloads(), isEmpty);
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isFalse);
    });

    test('deleteFile removes the finished file and keeps the record',
        () async {
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
      await engine.deleteFile(info.id);
      // The row stays, still completed in the engine; the file is gone.
      final listed = await engine.listDownloads();
      expect(listed, hasLength(1));
      expect(listed.single.status, DownloadStatus.completed);
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isFalse);
    });

    test('deleteFile with no file on disk is not an error', () async {
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
      // The file is already gone (deleted outside the app).
      await File(p.join(tempDir.path, 'f.bin')).delete();
      await engine.deleteFile(info.id);
      expect(await engine.listDownloads(), hasLength(1));
    });

    test('renameFile renames the finished file and updates the record',
        () async {
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
      await engine.renameFile(info.id, 'g.bin');
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isFalse);
      expect(await File(p.join(tempDir.path, 'g.bin')).exists(), isTrue);
      final listed = await engine.listDownloads();
      expect(listed, hasLength(1));
      expect(listed.single.fileName, 'g.bin');
      expect(listed.single.filePath, p.join(tempDir.path, 'g.bin'));
    });

    test('renameFile to an existing name throws file-exists', () async {
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
      File(p.join(tempDir.path, 'g.bin')).writeAsStringSync('other');
      await expectLater(
        engine.renameFile(info.id, 'g.bin'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'file-exists'),
        ),
      );
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isTrue);
    });

    test('renameFile with an invalid name throws', () async {
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
      await expectLater(
        engine.renameFile(info.id, 'sub/g.bin'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-name'),
        ),
      );
      await expectLater(
        engine.renameFile(info.id, ''),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-name'),
        ),
      );
    });

    test('moveFile moves the finished file and updates the record',
        () async {
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
      final other = Directory(p.join(tempDir.path, 'other'))..createSync();
      await engine.moveFile(info.id, other.path);
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isFalse);
      expect(await File(p.join(other.path, 'f.bin')).exists(), isTrue);
      final listed = await engine.listDownloads();
      expect(listed, hasLength(1));
      expect(listed.single.filePath, p.join(other.path, 'f.bin'));
    });

    test('moveFile to a directory where the file exists throws file-exists',
        () async {
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
      final other = Directory(p.join(tempDir.path, 'other'))..createSync();
      File(p.join(other.path, 'f.bin')).writeAsStringSync('other');
      await expectLater(
        engine.moveFile(info.id, other.path),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'file-exists'),
        ),
      );
      expect(await File(p.join(tempDir.path, 'f.bin')).exists(), isTrue);
    });

    test('moveFile to a missing directory throws', () async {
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
      await expectLater(
        engine.moveFile(info.id, p.join(tempDir.path, 'missing')),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-directory'),
        ),
      );
    });

    test('changeUrl updates the URL used by the next Retry', () async {
      final data = bytesOf(2048);
      await startServer(data: data, failFirst: 1);
      final otherData = bytesOf(1024);
      final server2 = _TestServer(data: otherData);
      await server2.start();
      addTearDown(server2.close);
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
        (d) => d.status == DownloadStatus.failed,
      );
      final newUrl = 'http://127.0.0.1:${server2.port}/g.bin';
      await engine.changeUrl(info.id, newUrl);
      var listed = await engine.listDownloads();
      expect(listed.single.url, newUrl);
      await engine.retryDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      // The completed file came from the new URL (1024 bytes, not
      // the old server's 2048).
      final file = File(p.join(tempDir.path, 'f.bin'));
      expect(await file.length(), 1024);
      listed = await engine.listDownloads();
      expect(listed.single.url, newUrl);
    });

    test('changeUrl with an invalid URL throws', () async {
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
      await expectLater(
        engine.changeUrl(info.id, 'ftp://127.0.0.1/f.bin'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-url'),
        ),
      );
    });

    test('changeUrl with an unknown id is a no-op', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      await engine.changeUrl('nope', 'http://127.0.0.1:9/g.bin');
    });

    test('checkForUpdate reports up to date when the size matches',
        () async {
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
      final result = await engine.checkForUpdate(info.id);
      expect(result.hasUpdate, isFalse);
      expect(result.inconclusive, isFalse);
      expect(result.newTotalBytes, 2048);
    });

    test('checkForUpdate reports an update when the size changed',
        () async {
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
      // The server now hosts a bigger file at the same URL.
      server.data = bytesOf(4096);
      final result = await engine.checkForUpdate(info.id);
      expect(result.hasUpdate, isTrue);
      expect(result.inconclusive, isFalse);
      expect(result.newTotalBytes, 4096);
    });

    test('checkForUpdate is inconclusive when the record has no size',
        () async {
      final data = bytesOf(2048);
      await startServer(data: data);
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${server.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      final result = await engine.checkForUpdate(info.id);
      expect(result.hasUpdate, isFalse);
      expect(result.inconclusive, isTrue);
      expect(result.newTotalBytes, 2048);
    });

    test('checkForUpdate with an unknown id throws', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      await expectLater(
        engine.checkForUpdate('nope'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'not-found'),
        ),
      );
    });

    test('checkForUpdate propagates a probe failure', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await expectLater(
        engine.checkForUpdate(info.id),
        throwsA(isA<DownloadError>()),
      );
    });

    test('verifyFile reports ok for a completed download', () async {
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
      final result = await engine.verifyFile(info.id);
      expect(result, const IntegrityResult.ok(bytes: 2048));
    });

    test('verifyFile reports missing when the file is gone', () async {
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
      File(p.join(tempDir.path, 'f.bin')).deleteSync();
      final result = await engine.verifyFile(info.id);
      expect(result, const IntegrityResult.missing());
    });

    test('verifyFile reports a size mismatch when the file changed',
        () async {
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
      File(p.join(tempDir.path, 'f.bin'))
          .writeAsBytesSync([0], mode: FileMode.append);
      final result = await engine.verifyFile(info.id);
      expect(
        result,
        const IntegrityResult.sizeMismatch(
          expectedBytes: 2048,
          actualBytes: 2049,
        ),
      );
    });

    test('verifyFile with an unknown id throws', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      await expectLater(
        engine.verifyFile('nope'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'not-found'),
        ),
      );
    });

    test('verifyFile is existence-only when the record has no size',
        () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      // The download never runs, so the record has no size; a file
      // placed at the destination by hand is enough for ok.
      File(p.join(tempDir.path, 'f.bin')).writeAsBytesSync(bytesOf(512));
      final result = await engine.verifyFile(info.id);
      expect(result, const IntegrityResult.ok(bytes: 512));
    });

    test('addMirror stores the URL and ignores duplicates', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      const mirror = 'http://127.0.0.1:9/m.bin';
      await engine.addMirror(info.id, mirror);
      await engine.addMirror(info.id, mirror);
      final store = DownloadStore.open(p.join(tempDir.path, 'pdm.db'));
      addTearDown(store.close);
      expect(store.getDownload(info.id)!.mirrors, [mirror]);
    });

    test('addMirror with a bad URL throws', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await expectLater(
        engine.addMirror(info.id, 'not-a-url'),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-url'),
        ),
      );
    });

    test('addMirror with an unknown id is a no-op', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      await engine.addMirror('nope', 'http://127.0.0.1:9/m.bin');
    });

    test('addTag stores the tag', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await engine.addTag(info.id, 'iso');
      final listed = await engine.listDownloads();
      expect(listed.single.tags, ['iso']);
    });

    test('addTag trims the tag and ignores duplicates', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await engine.addTag(info.id, '  iso  ');
      await engine.addTag(info.id, 'iso');
      final listed = await engine.listDownloads();
      expect(listed.single.tags, ['iso']);
    });

    test('addTag with an empty tag throws', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await expectLater(
        engine.addTag(info.id, '   '),
        throwsA(
          predicate<DownloadError>((e) => e.code == 'invalid-tag'),
        ),
      );
    });

    test('addTag with an unknown id is a no-op', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      await engine.addTag('nope', 'iso');
    });

    test('removeTag removes the tag', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await engine.addTag(info.id, 'iso');
      await engine.addTag(info.id, 'music');
      await engine.removeTag(info.id, 'iso');
      final listed = await engine.listDownloads();
      expect(listed.single.tags, ['music']);
    });

    test('removeTag of an absent tag is a no-op', () async {
      final engine = openEngine(maxConcurrent: 0);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await engine.addTag(info.id, 'iso');
      await engine.removeTag(info.id, 'music');
      final listed = await engine.listDownloads();
      expect(listed.single.tags, ['iso']);
    });

    test('retry keeps the tags', () async {
      final data = bytesOf(2048);
      await startServer(data: data, failFirst: 1);
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
        (d) => d.status == DownloadStatus.failed,
      );
      await engine.addTag(info.id, 'iso');
      await engine.retryDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.tags, ['iso']);
    });

    test('a failed download falls over to its mirror', () async {
      final primary =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await primary.start();
      addTearDown(primary.close);
      final mirror = _TestServer(data: bytesOf(2048));
      await mirror.start();
      addTearDown(mirror.close);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      // Created paused: the primary fails fast, so the mirror must
      // be stored before the first attempt runs.
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${primary.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
          paused: true,
        ),
      );
      await engine.addMirror(
        info.id,
        'http://127.0.0.1:${mirror.port}/f.bin',
      );
      await engine.resumeDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, 2048);
      expect(File(p.join(tempDir.path, 'f.bin')).lengthSync(), 2048);
    });

    test('a download fails when all mirrors fail', () async {
      final primary =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await primary.start();
      addTearDown(primary.close);
      final mirror =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await mirror.start();
      addTearDown(mirror.close);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${primary.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
          paused: true,
        ),
      );
      await engine.addMirror(
        info.id,
        'http://127.0.0.1:${mirror.port}/f.bin',
      );
      await engine.resumeDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.failed,
      );
    });

    test('retry keeps the mirrors so the retry can fail over', () async {
      final primary =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await primary.start();
      addTearDown(primary.close);
      final mirror = _TestServer(data: bytesOf(2048));
      await mirror.start();
      addTearDown(mirror.close);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${primary.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
        ),
      );
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.failed,
      );
      await engine.addMirror(
        info.id,
        'http://127.0.0.1:${mirror.port}/f.bin',
      );
      await engine.retryDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, 2048);
    });

    test('changeUrl keeps the mirrors', () async {
      final first =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await first.start();
      addTearDown(first.close);
      final second =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await second.start();
      addTearDown(second.close);
      final mirror = _TestServer(data: bytesOf(2048));
      await mirror.start();
      addTearDown(mirror.close);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      // Paused: the first attempt must not start before the URL
      // is changed, or its task races the retry on the same id and
      // the same partial file.
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${first.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
          paused: true,
        ),
      );
      await engine.addMirror(
        info.id,
        'http://127.0.0.1:${mirror.port}/f.bin',
      );
      await engine.changeUrl(
        info.id,
        'http://127.0.0.1:${second.port}/f.bin',
      );
      await engine.retryDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.downloadedBytes, 2048);
    });

    test('a manual retry restarts from the primary', () async {
      final primary =
          _TestServer(data: bytesOf(2048), failFirst: 100);
      await primary.start();
      addTearDown(primary.close);
      final mirror = _TestServer(data: bytesOf(2048));
      await mirror.start();
      addTearDown(mirror.close);
      final engine = openEngine(maxConnections: 1);
      addTearDown(engine.dispose);
      final info = await engine.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:${primary.port}/f.bin',
          destination: p.join(tempDir.path, 'f.bin'),
          paused: true,
        ),
      );
      await engine.addMirror(
        info.id,
        'http://127.0.0.1:${mirror.port}/f.bin',
      );
      await engine.resumeDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      final triedPrimary = primary.requests;
      expect(triedPrimary, greaterThan(0));
      await engine.retryDownload(info.id);
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      // The retry hit the primary again before falling over.
      expect(primary.requests, greaterThan(triedPrimary));
    });

    test(
        'deleteDownload with deleteFile and no file on disk still removes the record',
        () async {
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
      // The file is already gone (deleted outside the app).
      await File(p.join(tempDir.path, 'f.bin')).delete();
      await engine.deleteDownload(info.id, deleteFile: true);
      expect(await engine.listDownloads(), isEmpty);
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

    group('getSegments', () {
      test('reports live segments for a running download', () async {
        final data = bytesOf(256 * 1024);
        await startServer(data: data, chunkSize: 1024);
        final engine = openEngine(maxConnections: 2);
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
          (d) =>
              d.status == DownloadStatus.downloading &&
              d.downloadedBytes > 0,
        );
        final segments = await engine.getSegments(info.id);
        expect(segments.length, 2);
        expect(segments.first.start, 0);
        expect(segments.last.end, data.length - 1);
        final downloaded =
            segments.fold<int>(0, (sum, s) => sum + s.downloaded);
        expect(downloaded, greaterThan(0));
        expect(downloaded, lessThanOrEqualTo(data.length));
      });

      test('reports checkpointed segments for a paused download after '
          'a restart', () async {
        final data = bytesOf(256 * 1024);
        await startServer(data: data, chunkSize: 1024);
        final first = openEngine(maxConnections: 1);
        final created = await first.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
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
        final second = openEngine(maxConnections: 1);
        addTearDown(second.dispose);
        final segments = await second.getSegments(created.id);
        expect(segments, isNotEmpty);
        expect(segments.first.start, 0);
        expect(segments.last.end, data.length - 1);
        final downloaded =
            segments.fold<int>(0, (sum, s) => sum + s.downloaded);
        expect(downloaded, greaterThan(0));
      });

      test('returns empty for an unknown download', () async {
        final engine = openEngine();
        addTearDown(engine.dispose);
        expect(await engine.getSegments('no-such-id'), isEmpty);
      });

      test('listDownloads carries the priority', () async {
        final data = bytesOf(1024);
        await startServer(data: data);
        final engine = openEngine(maxConnections: 1);
        addTearDown(engine.dispose);
        final high = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/a.bin',
            destination: p.join(tempDir.path, 'a.bin'),
            priority: 2,
          ),
        );
        final normal = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/b.bin',
            destination: p.join(tempDir.path, 'b.bin'),
          ),
        );
        final downloads = await engine.listDownloads();
        expect(
          downloads.firstWhere((d) => d.id == high.id).priority,
          2,
        );
        expect(
          downloads.firstWhere((d) => d.id == normal.id).priority,
          0,
        );
      });
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

    test('deleteDownload with deleteFile removes the produced file',
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
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isTrue);
      await engine.deleteDownload(info.id, deleteFile: true);
      expect(await engine.listDownloads(), isEmpty);
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isFalse);
    });

    test('deleteFile removes the produced file and keeps the record',
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
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isTrue);
      await engine.deleteFile(info.id);
      expect(await engine.listDownloads(), hasLength(1));
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isFalse);
    });

    test('renameFile renames the produced file', () async {
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
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      await engine.renameFile(info.id, 'renamed.mp4');
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isFalse);
      expect(
        File(p.join(tempDir.path, 'renamed.mp4')).existsSync(),
        isTrue,
      );
      final listed = await engine.listDownloads();
      expect(listed.single.fileName, 'renamed.mp4');
    });

    test('moveFile moves the produced file', () async {
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
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      final other = Directory(p.join(tempDir.path, 'other'))..createSync();
      await engine.moveFile(info.id, other.path);
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isFalse);
      expect(File(p.join(other.path, 'live.mp4')).existsSync(), isTrue);
      final listed = await engine.listDownloads();
      expect(listed.single.filePath, p.join(other.path, 'live.mp4'));
    });

    test('checkForUpdate is inconclusive for a playlist URL', () async {
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
      await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      final result = await engine.checkForUpdate(info.id);
      expect(result.hasUpdate, isFalse);
      expect(result.inconclusive, isTrue);
      expect(result.newTotalBytes, -1);
    });

    test('createDownload with paused stores a paused playlist without starting it',
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
          paused: true,
        ),
      );
      expect(info.id.startsWith('yt-'), isTrue);
      expect(info.status, DownloadStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final listed = await engine.listDownloads();
      expect(
        listed.firstWhere((d) => d.id == info.id).status,
        DownloadStatus.paused,
      );
      expect(File(p.join(tempDir.path, 'live.mp4')).existsSync(), isFalse);
      await engine.resumeDownload(info.id);
      final done = await waitForInfo(
        engine,
        info.id,
        (d) => d.status == DownloadStatus.completed,
      );
      expect(done.fileName, 'live.mp4');
    });

      test('a yt-dlp download reports one synthetic segment', () async {
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
        final segments = await engine.getSegments(info.id);
        expect(segments.length, 1);
        expect(segments.first.start, 0);
        expect(segments.first.end, greaterThan(0));
        expect(segments.first.downloaded, greaterThan(0));
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

    group('file conflict policy', () {
      test('throws file-exists when the destination exists', () async {
        await File(p.join(tempDir.path, 'f.bin')).writeAsBytes(bytesOf(16));
        final engine = openEngine();
        addTearDown(engine.dispose);
        await expectLater(
          engine.createDownload(
            CreateDownloadRequest(
              url: 'http://127.0.0.1:9/f.bin',
              destination: p.join(tempDir.path, 'f.bin'),
            ),
          ),
          throwsA(
            isA<DownloadError>().having(
              (e) => e.code,
              'code',
              'file-exists',
            ),
          ),
        );
      });

      test('overwrite proceeds when the destination exists', () async {
        final data = bytesOf(4096);
        await startServer(data: data);
        await File(p.join(tempDir.path, 'f.bin')).writeAsBytes(bytesOf(16));
        final engine = openEngine(maxConnections: 2);
        addTearDown(engine.dispose);
        final info = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
            conflictPolicy: FileConflictPolicy.overwrite,
          ),
        );
        expect(info.fileName, 'f.bin');
        final done = await waitForInfo(
          engine,
          info.id,
          (d) => d.status == DownloadStatus.completed,
        );
        expect(done.fileName, 'f.bin');
        expect(
          await File(p.join(tempDir.path, 'f.bin')).readAsBytes(),
          data,
        );
      });

      test('rename picks the next free name', () async {
        await File(p.join(tempDir.path, 'f.bin')).writeAsBytes(bytesOf(16));
        // No concurrent slots: the jobs never start, so the test only
        // checks the names createDownload picks and nothing writes to
        // the temp dir while tearDown deletes it.
        final engine = openEngine(maxConcurrent: 0);
        addTearDown(engine.dispose);
        final first = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:9/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
            conflictPolicy: FileConflictPolicy.rename,
          ),
        );
        expect(first.fileName, 'f (1).bin');
        final second = await engine.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:9/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
            conflictPolicy: FileConflictPolicy.rename,
          ),
        );
        expect(second.fileName, 'f (2).bin');
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
