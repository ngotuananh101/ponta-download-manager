import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_scheduler/download_scheduler.dart';
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

void main() {
  test('scheduler with a limiter completes a real download', () async {
    final data = bytesOf(2048);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final response = request.response;
      response.headers.set('Accept-Ranges', 'bytes');
      response.headers.contentType = ContentType.binary;
      final range = request.headers.value('range');
      if (request.method == 'HEAD') {
        response.headers.contentLength = data.length;
        await response.close();
        return;
      }
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
        if (match != null) {
          final start = int.parse(match.group(1)!);
          final end = match.group(2)!.isEmpty
              ? data.length - 1
              : int.parse(match.group(2)!);
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            'Content-Range',
            'bytes $start-$end/${data.length}',
          );
          response.add(data.sublist(start, end + 1));
          await response.close();
          return;
        }
      }
      response.headers.contentLength = data.length;
      response.add(data);
      await response.close();
    });
    final tempDir = await Directory.systemTemp.createTemp(
      'pdm-limiter-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final limiter = BandwidthLimiter(perDownloadBytesPerSecond: 1024);
    addTearDown(limiter.dispose);
    final scheduler = DownloadScheduler(
      maxConcurrent: 1,
      limiter: limiter,
    );
    addTearDown(scheduler.dispose);
    var completed = false;
    final subscription = scheduler.events.listen((event) {
      event.when(
        progress: (downloadId, downloadedBytes, totalBytes, bytesPerSecond) {},
        stateChanged: (downloadId, status) {},
        completed: (downloadId, filePath) {
          completed = true;
        },
        failed: (downloadId, code, message) {},
      );
    });
    addTearDown(subscription.cancel);
    final stopwatch = Stopwatch()..start();
    final id = scheduler.enqueue(
      url: 'http://127.0.0.1:${server.port}/f.bin',
      fileName: 'f.bin',
      directory: tempDir.path,
    );
    expect(id, 'dl-1');
    await waitFor(() => completed, timeout: const Duration(seconds: 15));
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(700));
    final file = File(p.join(tempDir.path, 'f.bin'));
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), data);
  });
}
