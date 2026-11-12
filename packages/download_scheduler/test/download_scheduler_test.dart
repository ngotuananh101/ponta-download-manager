import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_scheduler/download_scheduler.dart';
import 'package:download_transport/download_transport.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _NullSink implements ChunkSink {
  @override
  String? get filePath => null;

  @override
  Future<void> write(int offset, List<int> bytes) async {}

  @override
  Future<void> close() async {}
}

class _FakeTransport implements DownloadTransport {
  _FakeTransport({
    required this.data,
    this.chunkDelay = const Duration(milliseconds: 20),
  });

  final List<int> data;
  final Duration chunkDelay;
  final int chunkSize = 256;

  final failPaths = <String>{};
  Future<void> Function(Uri url)? onProbe;
  final startedUrls = <String>[];
  final ifRanges = <String?>[];
  var openStreams = 0;
  var maxOpenStreams = 0;

  @override
  Future<ResourceInfo> probe(Uri url) async {
    await onProbe?.call(url);
    if (failPaths.contains(url.path)) {
      throw DownloadError('network', 'probe failed for ${url.path}');
    }
    return ResourceInfo(
      finalUrl: url,
      statusCode: 200,
      contentLength: data.length,
      supportsRange: true,
      eTag: 'v1',
      lastModified: null,
      contentDisposition: null,
      contentType: 'application/octet-stream',
      fileName: 'file.bin',
    );
  }

  @override
  Future<RangeValidation> validateRange(
    Uri url, {
    required int start,
    required int end,
  }) async {
    return RangeValidation.valid(totalBytes: data.length);
  }

  @override
  Stream<List<int>> openStream(
    Uri url, {
    int? start,
    int? end,
    String? ifRange,
  }) async* {
    startedUrls.add(url.toString());
    ifRanges.add(ifRange);
    openStreams++;
    if (openStreams > maxOpenStreams) {
      maxOpenStreams = openStreams;
    }
    try {
      final from = start ?? 0;
      final to = end ?? data.length - 1;
      var offset = from;
      while (offset <= to) {
        await Future<void>.delayed(chunkDelay);
        final next = (offset + chunkSize - 1).clamp(0, to);
        yield data.sublist(offset, next + 1);
        offset = next + 1;
      }
    } finally {
      openStreams--;
    }
  }

  @override
  void close() {}
}

List<int> bytesOf(int length, [int seed = 0]) =>
    List<int>.generate(length, (i) => (i + seed) % 256);

DownloadScheduler _makeScheduler(
  _FakeTransport transport, {
  int maxConcurrent = 3,
}) {
  return DownloadScheduler(
    maxConcurrent: maxConcurrent,
    taskFactory: (job) async {
      final sink = _NullSink();
      final task = DownloadTask(
        transport: transport,
        sink: sink,
        url: Uri.parse(job.url),
        id: job.id,
        maxConnections: job.maxConnections,
        retryDelay: const Duration(milliseconds: 10),
      );
      return ScheduledTask(task, sink);
    },
  );
}

class _ThrowingCloseSink extends _NullSink {
  @override
  Future<void> close() async {
    throw StateError('close failed');
  }
}

DownloadScheduler _makeSchedulerWithThrowingClose(
  _FakeTransport transport, {
  int maxConcurrent = 3,
}) {
  return DownloadScheduler(
    maxConcurrent: maxConcurrent,
    taskFactory: (job) async {
      final ChunkSink sink = job.url.endsWith('/a')
          ? _ThrowingCloseSink()
          : _NullSink();
      final task = DownloadTask(
        transport: transport,
        sink: sink,
        url: Uri.parse(job.url),
        id: job.id,
        maxConnections: job.maxConnections,
        retryDelay: const Duration(milliseconds: 10),
      );
      return ScheduledTask(task, sink);
    },
  );
}

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

DownloadInfo infoOf(DownloadScheduler scheduler, String id) =>
    scheduler.downloads.firstWhere((info) => info.id == id);

Future<void> waitForStatus(
  DownloadScheduler scheduler,
  String id,
  DownloadStatus status,
) async {
  await waitFor(() => infoOf(scheduler, id).status == status);
}

void main() {
  group('DownloadScheduler', () {
    test('runs up to maxConcurrent downloads at once', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      final c = scheduler.enqueue(
        url: 'http://example.test/c',
        fileName: 'c.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      await waitForStatus(scheduler, c, DownloadStatus.completed);
      expect(transport.maxOpenStreams, 2);
      expect(
        transport.startedUrls.take(2).toSet(),
        {'http://example.test/a', 'http://example.test/b'},
      );
      expect(transport.startedUrls.last, 'http://example.test/c');
      expect(infoOf(scheduler, a).downloadedBytes, 4096);
    });

    test('starts higher priority jobs first', () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      final c = scheduler.enqueue(
        url: 'http://example.test/c',
        fileName: 'c.bin',
        priority: 10,
        maxConnections: 1,
      );
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      await waitForStatus(scheduler, c, DownloadStatus.completed);
      expect(transport.startedUrls, [
        'http://example.test/a',
        'http://example.test/c',
        'http://example.test/b',
      ]);
    });

    test('a throwing sink.close() reports failed and frees the slot',
        () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final scheduler = _makeSchedulerWithThrowingClose(
        transport,
        maxConcurrent: 1,
      );
      addTearDown(scheduler.dispose);
      final events = <DownloadEvent>[];
      scheduler.events.listen(events.add);
      final first = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final second = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, first, DownloadStatus.failed);
      await waitForStatus(scheduler, second, DownloadStatus.completed);
      expect(
        events.whereType<DownloadFailed>().map((e) => e.downloadId),
        contains(first),
      );
      expect(
        events.whereType<DownloadCompleted>().map((e) => e.downloadId),
        isNot(contains(first)),
      );
    });

    test('pause frees a slot and resume finishes the download', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      final c = scheduler.enqueue(
        url: 'http://example.test/c',
        fileName: 'c.bin',
        maxConnections: 1,
      );
      await waitFor(() => infoOf(scheduler, a).downloadedBytes > 0);
      scheduler.pause(a);
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/c'),
      );
      final before = infoOf(scheduler, a).downloadedBytes;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(infoOf(scheduler, a).downloadedBytes, before);
      expect(infoOf(scheduler, a).status, DownloadStatus.paused);
      scheduler.resume(a);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      await waitForStatus(scheduler, c, DownloadStatus.completed);
      expect(infoOf(scheduler, a).downloadedBytes, 4096);
      expect(transport.ifRanges, contains('v1'));
    });

    test('pausing during the probe stops the download', () async {
      final transport = _FakeTransport(data: bytesOf(4096));
      final probeEntered = Completer<void>();
      final releaseProbe = Completer<void>();
      transport.onProbe = (url) async {
        if (url.path == '/a' && !probeEntered.isCompleted) {
          probeEntered.complete();
          await releaseProbe.future;
        }
      };
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await probeEntered.future.timeout(const Duration(seconds: 5));
      scheduler.pause(a);
      releaseProbe.complete();
      // The freed slot lets dl-2 run and complete.
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      // dl-1 downloaded nothing while paused.
      expect(infoOf(scheduler, a).downloadedBytes, 0);
      expect(infoOf(scheduler, a).status, DownloadStatus.paused);
      scheduler.resume(a);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      expect(infoOf(scheduler, a).downloadedBytes, 4096);
    });

    test('a pause during a failing start does not stick to the retry',
        () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final factoryStarted = Completer<void>();
      final failFactory = Completer<void>();
      var factoryCalls = 0;
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          factoryCalls++;
          if (factoryCalls == 1) {
            factoryStarted.complete();
            await failFactory.future;
            throw StateError('factory boom');
          }
          final sink = _NullSink();
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: job.maxConnections,
            retryDelay: const Duration(milliseconds: 10),
          );
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryStarted.future.timeout(const Duration(seconds: 5));
      scheduler.pause(id);
      failFactory.complete();
      await waitForStatus(scheduler, id, DownloadStatus.failed);
      // Retry the same id: it must run instead of sitting paused
      // on the stale flag from the failed start.
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(
        () => infoOf(scheduler, id).status == DownloadStatus.completed,
        timeout: const Duration(seconds: 3),
      );
      expect(infoOf(scheduler, id).downloadedBytes, 1024);
    });

    test('pauseAll pauses everything and resumeAll restarts it', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await waitFor(() => infoOf(scheduler, a).downloadedBytes > 0);
      scheduler.pauseAll();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final frozen = infoOf(scheduler, a).downloadedBytes;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(infoOf(scheduler, a).downloadedBytes, frozen);
      expect(infoOf(scheduler, a).status, DownloadStatus.paused);
      expect(infoOf(scheduler, b).status, DownloadStatus.paused);
      expect(transport.startedUrls, ['http://example.test/a']);
      scheduler.resumeAll();
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
    });

    test('cancel removes a queued job', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      scheduler.cancel(b);
      expect(infoOf(scheduler, b).status, DownloadStatus.cancelled);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      expect(transport.startedUrls, ['http://example.test/a']);
    });

    test('cancel stops a running download', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await waitFor(() => infoOf(scheduler, a).downloadedBytes > 0);
      scheduler.cancel(a);
      await waitForStatus(scheduler, a, DownloadStatus.cancelled);
      expect(infoOf(scheduler, a).downloadedBytes, lessThan(4096));
      await waitForStatus(scheduler, b, DownloadStatus.completed);
    });

    test('a failed job does not block the queue', () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      transport.failPaths.add('/fail');
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final good1 = scheduler.enqueue(
        url: 'http://example.test/good1',
        fileName: 'g1.bin',
        maxConnections: 1,
      );
      final fail = scheduler.enqueue(
        url: 'http://example.test/fail',
        fileName: 'f.bin',
        maxConnections: 1,
      );
      final good2 = scheduler.enqueue(
        url: 'http://example.test/good2',
        fileName: 'g2.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, fail, DownloadStatus.failed);
      await waitForStatus(scheduler, good1, DownloadStatus.completed);
      await waitForStatus(scheduler, good2, DownloadStatus.completed);
    });

    test('setMaxConcurrent starts queued jobs', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/a'),
      );
      expect(transport.startedUrls, ['http://example.test/a']);
      scheduler.setMaxConcurrent(2);
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/b'),
      );
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
    });

    test('downloads snapshot reflects state', () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      final first = infoOf(scheduler, a);
      expect(first.status, DownloadStatus.queued);
      expect(first.totalBytes, -1);
      expect(first.downloadedBytes, 0);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      final last = infoOf(scheduler, a);
      expect(last.status, DownloadStatus.completed);
      expect(last.totalBytes, 1024);
      expect(last.downloadedBytes, 1024);
    });

    test('enqueue after dispose throws', () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final scheduler = _makeScheduler(transport);
      await scheduler.dispose();
      expect(
        () => scheduler.enqueue(
          url: 'http://example.test/a',
          fileName: 'a.bin',
        ),
        throwsStateError,
      );
    });

    test('runs real downloads to disk', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-scheduler-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final dataA = bytesOf(2048, 0);
      final dataB = bytesOf(2048, 5);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((request) async {
        final data = request.uri.path == '/a' ? dataA : dataB;
        if (request.method == 'HEAD') {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          await request.response.close();
          return;
        }
        final range = request.headers.value('range');
        if (range != null) {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
          final start = int.parse(match!.group(1)!);
          final end = match.group(2)!.isEmpty
              ? data.length - 1
              : int.parse(match.group(2)!);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes $start-$end/${data.length}')
            ..headers.set('content-length', '${end - start + 1}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data.sublist(start, end + 1));
        } else {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data);
        }
        await request.response.close();
      });
      final scheduler = DownloadScheduler(maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final base = 'http://127.0.0.1:${server.port}';
      final a = scheduler.enqueue(
        url: '$base/a',
        fileName: 'a.bin',
        directory: tempDir.path,
      );
      final b = scheduler.enqueue(
        url: '$base/b',
        fileName: 'b.bin',
        directory: tempDir.path,
      );
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      expect(await File(p.join(tempDir.path, 'a.bin')).readAsBytes(), dataA);
      expect(await File(p.join(tempDir.path, 'b.bin')).readAsBytes(), dataB);
    });

    test('overwrite replaces an existing file', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-scheduler-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final data = bytesOf(2048, 0);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          await request.response.close();
          return;
        }
        final range = request.headers.value('range');
        if (range != null) {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
          final start = int.parse(match!.group(1)!);
          final end = match.group(2)!.isEmpty
              ? data.length - 1
              : int.parse(match.group(2)!);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes $start-$end/${data.length}')
            ..headers.set('content-length', '${end - start + 1}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data.sublist(start, end + 1));
        } else {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data);
        }
        await request.response.close();
      });
      await File(p.join(tempDir.path, 'a.bin')).writeAsBytes(bytesOf(16));
      final scheduler = DownloadScheduler(maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://127.0.0.1:${server.port}/a',
        fileName: 'a.bin',
        directory: tempDir.path,
        overwrite: true,
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(await File(p.join(tempDir.path, 'a.bin')).readAsBytes(), data);
    });

    test('setPriority keeps the overwrite flag', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-scheduler-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final data = bytesOf(2048, 0);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((request) async {
        if (request.method == 'HEAD') {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          await request.response.close();
          return;
        }
        final range = request.headers.value('range');
        if (range != null) {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
          final start = int.parse(match!.group(1)!);
          final end = match.group(2)!.isEmpty
              ? data.length - 1
              : int.parse(match.group(2)!);
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes $start-$end/${data.length}')
            ..headers.set('content-length', '${end - start + 1}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data.sublist(start, end + 1));
        } else {
          request.response
            ..headers.set('content-length', '${data.length}')
            ..headers.set('accept-ranges', 'bytes');
          request.response.add(data);
        }
        await request.response.close();
      });
      await File(p.join(tempDir.path, 'a.bin')).writeAsBytes(bytesOf(16));
      final scheduler = DownloadScheduler(maxConcurrent: 2);
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://127.0.0.1:${server.port}/a',
        fileName: 'a.bin',
        directory: tempDir.path,
        overwrite: true,
        paused: true,
      );
      scheduler.setPriority(id, 1);
      scheduler.resume(id);
      await waitFor(() {
        final status = infoOf(scheduler, id).status;
        return status == DownloadStatus.completed ||
            status == DownloadStatus.failed;
      });
      expect(infoOf(scheduler, id).status, DownloadStatus.completed);
      expect(await File(p.join(tempDir.path, 'a.bin')).readAsBytes(), data);
    });
  });
}
