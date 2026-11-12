import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_transport/download_transport.dart';
import 'package:test/test.dart';

class MemorySink implements ChunkSink {
  final bytes = <int>[];

  @override
  String? get filePath => null;

  @override
  Future<void> write(int offset, List<int> chunk) async {
    final needed = offset + chunk.length;
    if (bytes.length < needed) {
      bytes.addAll(List<int>.filled(needed - bytes.length, 0));
    }
    bytes.setRange(offset, offset + chunk.length, chunk);
  }

  @override
  Future<void> close() async {}
}

class _ThrowingCloseSink extends MemorySink {
  @override
  Future<void> close() async {
    throw StateError('close failed');
  }
}

void main() {
  late HttpServer server;
  late Uri base;

  final body = List<int>.generate(1024, (i) => i % 256);
  final bigBody = List<int>.generate(5 * 1024 * 1024, (i) => i % 256);
  final lyingBody = List<int>.generate(2048, (i) => i % 256);

  final requestedRanges = <String>[];
  final ifRangeHeaders = <String?>[];
  var flakyRemaining = 1;
  var getCount = 0;
  var dropRemaining = 1;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      try {
        if (path == '/not-found') {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        if (path == '/empty') {
          if (request.method == 'HEAD') {
            response.statusCode = HttpStatus.ok;
            response.headers.contentLength = 0;
            await response.close();
            return;
          }
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = 0;
          await response.close();
          return;
        }
        if (path == '/lying-head') {
          // HEAD lies about the size (1024) while the representation
          // is 2048 bytes; the range responses carry the true total.
          if (request.method == 'HEAD') {
            response.statusCode = HttpStatus.ok;
            response.headers.contentLength = 1024;
            response.headers.set('accept-ranges', 'bytes');
            response.headers.set('etag', '"v1"');
            await response.close();
            return;
          }
          final range = request.headers.value('range');
          if (range != null) {
            final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
            if (match != null) {
              final start = int.parse(match.group(1)!);
              final endText = match.group(2)!;
              final end = endText.isEmpty
                  ? lyingBody.length - 1
                  : int.parse(endText);
              response.statusCode = HttpStatus.partialContent;
              response.headers.set(
                'content-range',
                'bytes $start-$end/${lyingBody.length}',
              );
              response.headers.contentLength = end - start + 1;
              response.add(lyingBody.sublist(start, end + 1));
              await response.close();
              return;
            }
          }
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = lyingBody.length;
          response.add(lyingBody);
          await response.close();
          return;
        }
        if (path == '/zero-head') {
          // HEAD claims zero bytes while GET returns a 100-byte body.
          if (request.method == 'HEAD') {
            response.statusCode = HttpStatus.ok;
            response.headers.contentLength = 0;
            await response.close();
            return;
          }
          final data100 = List<int>.generate(100, (i) => i % 256);
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = data100.length;
          response.add(data100);
          await response.close();
          return;
        }
        if (path == '/flaky') {
          getCount++;
          final range = request.headers.value('range');
          if (request.method == 'GET' &&
              range == 'bytes=512-1023' &&
              flakyRemaining > 0) {
            flakyRemaining--;
            response.statusCode = HttpStatus.internalServerError;
            await response.close();
            return;
          }
          // Falls through to the /file behavior below.
        }
        if (path == '/slow-big') {
          if (request.method == 'HEAD') {
            response.statusCode = HttpStatus.ok;
            response.headers.contentLength = bigBody.length;
            response.headers.set('accept-ranges', 'bytes');
            response.headers.set('etag', '"v1"');
            await response.close();
            return;
          }
          final range = request.headers.value('range');
          ifRangeHeaders.add(request.headers.value('if-range'));
          requestedRanges.add(range ?? 'full');
          if (range != null) {
            final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
            if (match != null) {
              final start = int.parse(match.group(1)!);
              final endText = match.group(2)!;
              final end =
                  endText.isEmpty ? bigBody.length - 1 : int.parse(endText);
              response.statusCode = HttpStatus.partialContent;
              response.headers.set(
                'content-range',
                'bytes $start-$end/${bigBody.length}',
              );
              response.headers.contentLength = end - start + 1;
              const chunkSize = 128 * 1024;
              for (var offset = start; offset <= end; offset += chunkSize) {
                final chunkEnd = offset + chunkSize - 1 > end
                    ? end
                    : offset + chunkSize - 1;
                response.add(bigBody.sublist(offset, chunkEnd + 1));
                await response.flush();
                await Future<void>.delayed(
                  const Duration(milliseconds: 50),
                );
              }
              await response.close();
              return;
            }
          }
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = bigBody.length;
          response.add(bigBody);
          await response.close();
          return;
        }
        const total = 1024;
        final data = body;
        if (request.method == 'HEAD') {
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = total;
          if (path != '/no-range') {
            response.headers.set('accept-ranges', 'bytes');
          }
          response.headers.set('etag', '"v1"');
          response.headers.contentType =
              ContentType('application', 'octet-stream');
          response.headers.set(
            'content-disposition',
            'attachment; filename="archive.zip"',
          );
          await response.close();
          return;
        }
        if (path == '/drop-body' &&
            request.method == 'GET' &&
            dropRemaining > 0 &&
            request.headers.value('range') != 'bytes=0-0') {
          // Declare the full range, send half of it, then close: the
          // client sees the connection end mid-body.
          dropRemaining--;
          final dropRange = request.headers.value('range');
          final dropMatch = dropRange == null
              ? null
              : RegExp(r'bytes=(\d+)-(\d*)').firstMatch(dropRange);
          final dropStart =
              dropMatch == null ? 0 : int.parse(dropMatch.group(1)!);
          final dropEndText = dropMatch?.group(2) ?? '';
          final dropEnd =
              dropEndText.isEmpty ? total - 1 : int.parse(dropEndText);
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            'content-range',
            'bytes $dropStart-$dropEnd/$total',
          );
          response.headers.contentLength = dropEnd - dropStart + 1;
          final half = (dropEnd - dropStart + 1) ~/ 2;
          response.add(data.sublist(dropStart, dropStart + half));
          await response.flush();
          await response.close();
          return;
        }
        final range = request.headers.value('range');
        requestedRanges.add(range ?? 'full');
        if (range != null && path != '/no-range') {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
          if (match != null) {
            final start = int.parse(match.group(1)!);
            final endText = match.group(2)!;
            final end = endText.isEmpty ? total - 1 : int.parse(endText);
            if (path == '/range-then-200' && range != 'bytes=0-0') {
              // Passes the 1-byte validation, then answers a real
              // segment range with the full body.
              response.statusCode = HttpStatus.ok;
              response.headers.contentLength = total;
              response.add(data);
              await response.close();
              return;
            }
            response.statusCode = HttpStatus.partialContent;
            response.headers.set(
              'content-range',
              'bytes $start-$end/$total',
            );
            response.headers.contentLength = end - start + 1;
            response.add(data.sublist(start, end + 1));
            await response.close();
            return;
          }
        }
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = total;
        response.add(data);
        await response.close();
      } catch (_) {
        // Client went away (cancel test) — ignore.
      }
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    requestedRanges.clear();
    ifRangeHeaders.clear();
    flakyRemaining = 1;
    dropRemaining = 1;
    getCount = 0;
  });

  DownloadTask taskFor(
    String path, {
    required MemorySink sink,
    int maxConnections = 4,
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 10),
  }) {
    return DownloadTask(
      transport: HttpTransport(),
      sink: sink,
      url: base.resolve(path),
      id: 'test-1',
      maxConnections: maxConnections,
      maxRetries: maxRetries,
      retryDelay: retryDelay,
    );
  }

  group('SegmentPlanner', () {
    test('splits evenly with no gaps or overlaps', () {
      final segments = planSegments(totalBytes: 1000, maxConnections: 4);
      expect(segments.length, 4);
      expect(segments.map((s) => s.id), [0, 1, 2, 3]);
      expect(segments.first.start, 0);
      expect(segments.last.end, 999);
      for (var i = 0; i < segments.length; i++) {
        expect(segments[i].length, 250);
        if (i > 0) {
          expect(segments[i].start, segments[i - 1].end! + 1);
        }
      }
    });

    test('hands the remainder to the first segments', () {
      final segments = planSegments(totalBytes: 1001, maxConnections: 4);
      expect(segments.map((s) => s.length), [251, 250, 250, 250]);
    });

    test('caps segments at the byte count', () {
      final segments = planSegments(totalBytes: 3, maxConnections: 4);
      expect(segments.length, 3);
      expect(segments.map((s) => s.length), [1, 1, 1]);
    });

    test('unknown length plans one open segment', () {
      final segments = planSegments(totalBytes: null, maxConnections: 4);
      expect(segments.length, 1);
      expect(segments.single.start, 0);
      expect(segments.single.end, isNull);
    });

    test('zero length plans nothing', () {
      expect(planSegments(totalBytes: 0, maxConnections: 4), isEmpty);
    });
  });

  group('DownloadTask', () {
    test('single-stream downloads the exact bytes', () async {
      final sink = MemorySink();
      final task = taskFor('/no-range', sink: sink);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(info.downloadedBytes, 1024);
      expect(info.totalBytes, 1024);
      expect(sink.bytes, body);
    });

    test('segmented download uses several ranges and exact bytes',
        () async {
      final sink = MemorySink();
      final task = taskFor('/file', sink: sink, maxConnections: 4);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(info.fileName, 'archive.zip');
      expect(sink.bytes, body);
      final ranges = requestedRanges.where((r) => r != 'full').toSet();
      expect(ranges.length, greaterThanOrEqualTo(2));
    });

    test('emits progress and a completed event', () async {
      final sink = MemorySink();
      final task = taskFor('/file', sink: sink);
      final events = <DownloadEvent>[];
      task.events.listen(events.add);
      await task.run();
      expect(
        events.whereType<DownloadProgress>().map((e) => e.downloadedBytes),
        contains(1024),
      );
      expect(events.whereType<DownloadCompleted>(), isNotEmpty);
      expect(
        events
            .whereType<DownloadStateChanged>()
            .map((e) => e.status)
            .contains(DownloadStatus.completed),
        isTrue,
      );
    });

    test('progress events report a non-zero download speed', () async {
      final sink = MemorySink();
      final task = taskFor('/slow-big', sink: sink, maxConnections: 1);
      final events = <DownloadEvent>[];
      task.events.listen(events.add);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      // The download takes ~2s (5 MiB in 128 KiB chunks with a 50 ms
      // delay), so the speed window elapses and the rate is measured.
      final speeds = events
          .whereType<DownloadProgress>()
          .map((e) => e.bytesPerSecond)
          .toList();
      expect(speeds.any((s) => s > 0), isTrue);
    });

    test('zero-length file completes immediately', () async {
      final sink = MemorySink();
      final task = taskFor('/empty', sink: sink);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(info.downloadedBytes, 0);
      expect(sink.bytes, isEmpty);
    });

    test('a HEAD total contradicted by Content-Range uses the range total',
        () async {
      final sink = MemorySink();
      final task = taskFor('/lying-head', sink: sink, maxConnections: 4);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(info.totalBytes, 2048);
      expect(info.downloadedBytes, 2048);
      expect(sink.bytes, lyingBody);
    });

    test('a zero HEAD that hides a body fails instead of completing empty',
        () async {
      final sink = MemorySink();
      final task = taskFor('/zero-head', sink: sink);
      await expectLater(
        task.run(),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'size-mismatch'),
        ),
      );
      expect(task.status, DownloadStatus.failed);
    });

    test('pause stops progress and resume finishes', () async {
      final sink = MemorySink();
      final task = taskFor(
        '/slow-big',
        sink: sink,
        maxConnections: 2,
      );
      final events = <DownloadEvent>[];
      task.events.listen(events.add);
      final run = task.run();
      await task.events
          .where((e) => e is DownloadProgress).cast<DownloadProgress>()
          .firstWhere((e) => e.downloadedBytes > 0)
          .timeout(const Duration(seconds: 5));
      task.pause();
      expect(task.status, DownloadStatus.paused);
      final atPause = task.downloadedBytes;
      expect(atPause, greaterThan(0));
      ifRangeHeaders.clear();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(task.downloadedBytes, atPause);
      task.resume();
      final info = await run;
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, bigBody);
      expect(ifRangeHeaders, contains('"v1"'));
    });

    test('cancel stops the download', () async {
      final sink = MemorySink();
      final task = taskFor('/slow-big', sink: sink, maxConnections: 2);
      final run = task.run();
      await task.events
          .where((e) => e is DownloadProgress).cast<DownloadProgress>()
          .firstWhere((e) => e.downloadedBytes > 0)
          .timeout(const Duration(seconds: 5));
      task.cancel();
      final info = await run;
      expect(info.status, DownloadStatus.cancelled);
      expect(info.downloadedBytes, lessThan(bigBody.length));
    });

    test('retries a transient 500 and still completes', () async {
      final sink = MemorySink();
      final task = taskFor('/flaky', sink: sink, maxConnections: 2);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, body);
      expect(getCount, greaterThanOrEqualTo(2));
    });

    test('a dropped connection mid-body is retried and still completes',
        () async {
      final sink = MemorySink();
      final task = taskFor('/drop-body', sink: sink, maxConnections: 2);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, body);
    });

    test('404 fails the task', () async {
      final sink = MemorySink();
      final task = taskFor('/not-found', sink: sink);
      await expectLater(
        task.run(),
        throwsA(
          isA<DownloadError>().having((e) => e.code, 'code', 'http-404'),
        ),
      );
      expect(task.status, DownloadStatus.failed);
    });

    test('falls back to single-stream when a range is ignored mid-run',
        () async {
      final sink = MemorySink();
      final task = taskFor('/range-then-200', sink: sink, maxConnections: 4);
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, body);
    });

    test('a throwing sink.close() fails the task instead of completing it',
        () async {
      final sink = _ThrowingCloseSink();
      final task = taskFor('/no-range', sink: sink);
      final events = <DownloadEvent>[];
      task.events.listen(events.add);
      await expectLater(
        task.run(),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'close-failed'),
        ),
      );
      expect(task.status, DownloadStatus.failed);
      expect(
        events.whereType<DownloadFailed>().map((e) => e.code),
        contains('close-failed'),
      );
    });
  });
}
