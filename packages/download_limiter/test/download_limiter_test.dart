import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_limiter/download_limiter.dart';
import 'package:download_transport/download_transport.dart';
import 'package:test/test.dart';

class _MemorySink implements ChunkSink {
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

class _FakeTransport implements DownloadTransport {
  _FakeTransport({required this.data});

  final List<int> data;
  final chunkDelay = const Duration(milliseconds: 10);
  final chunkSize = 256;

  @override
  Future<ResourceInfo> probe(Uri url) async {
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
    final from = start ?? 0;
    final to = end ?? data.length - 1;
    var offset = from;
    while (offset <= to) {
      await Future<void>.delayed(chunkDelay);
      final next = (offset + chunkSize - 1).clamp(0, to);
      yield data.sublist(offset, next + 1);
      offset = next + 1;
    }
  }

  @override
  void close() {}
}

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
  group('TokenBucket', () {
    test('unlimited passes immediately', () async {
      final bucket = TokenBucket(rateBytesPerSecond: null);
      addTearDown(bucket.dispose);
      final stopwatch = Stopwatch()..start();
      await bucket.acquire(1024 * 1024);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('enforces its rate', () async {
      final bucket = TokenBucket(rateBytesPerSecond: 1024);
      addTearDown(bucket.dispose);
      await bucket.acquire(1024);
      final stopwatch = Stopwatch()..start();
      await bucket.acquire(1024);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });

    test('runtime setRate wakes waiters', () async {
      final bucket = TokenBucket(rateBytesPerSecond: 512);
      addTearDown(bucket.dispose);
      await bucket.acquire(512);
      final stopwatch = Stopwatch()..start();
      final waiting = bucket.acquire(2048);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      bucket.setRate(null);
      await waiting;
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('serves higher priority first', () async {
      final bucket = TokenBucket(rateBytesPerSecond: 1024);
      addTearDown(bucket.dispose);
      await bucket.acquire(1024);
      final order = <String>[];
      final low = bucket.acquire(
        1024,
        priority: 0,
      ).then((_) => order.add('low'));
      final high = bucket.acquire(
        1024,
        priority: 10,
      ).then((_) => order.add('high'));
      await Future.wait([low, high]);
      expect(order, ['high', 'low']);
    });

    test('burst allows an initial burst', () async {
      final bucket = TokenBucket(
        rateBytesPerSecond: 1024,
        burstBytes: 2048,
      );
      addTearDown(bucket.dispose);
      final first = Stopwatch()..start();
      await bucket.acquire(2048);
      expect(first.elapsedMilliseconds, lessThan(500));
      final second = Stopwatch()..start();
      await bucket.acquire(1024);
      expect(second.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });
  });

  group('BandwidthLimiter', () {
    test('enforces the per-download limit', () async {
      final limiter = BandwidthLimiter(perDownloadBytesPerSecond: 1024);
      addTearDown(limiter.dispose);
      final stopwatch = Stopwatch()..start();
      await limiter.acquire('a', 2048);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });

    test('enforces the global limit across downloads', () async {
      final limiter = BandwidthLimiter(globalBytesPerSecond: 1024);
      addTearDown(limiter.dispose);
      final stopwatch = Stopwatch()..start();
      await Future.wait([
        limiter.acquire('a', 1024),
        limiter.acquire('b', 1024),
      ]);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });

    test('runtime setGlobalLimit wakes waiters', () async {
      final limiter = BandwidthLimiter(globalBytesPerSecond: 512);
      addTearDown(limiter.dispose);
      final stopwatch = Stopwatch()..start();
      final waiting = limiter.acquire('a', 2048);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      limiter.setGlobalLimit(null);
      await waiting;
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    test('per-download override survives a default change', () async {
      final limiter = BandwidthLimiter(perDownloadBytesPerSecond: 1024);
      addTearDown(limiter.dispose);
      limiter.setDownloadLimit('a', 512);
      limiter.setPerDownloadLimit(2048);
      final fast = Stopwatch()..start();
      await limiter.acquire('b', 2048);
      expect(fast.elapsedMilliseconds, lessThan(500));
      final slow = Stopwatch()..start();
      await limiter.acquire('a', 1024);
      expect(slow.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });

    test('removeDownload drops the bucket', () async {
      final limiter = BandwidthLimiter(perDownloadBytesPerSecond: 1024);
      addTearDown(limiter.dispose);
      await limiter.acquire('a', 1024);
      limiter.removeDownload('a');
      final stopwatch = Stopwatch()..start();
      await limiter.acquire('a', 1024);
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('DownloadTask throttle', () {
    test('throttles a download to the per-download limit', () async {
      final data = bytesOf(2048);
      final transport = _FakeTransport(data: data);
      final limiter = BandwidthLimiter(perDownloadBytesPerSecond: 1024);
      addTearDown(limiter.dispose);
      final sink = _MemorySink();
      final task = DownloadTask(
        transport: transport,
        sink: sink,
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 1,
        retryDelay: const Duration(milliseconds: 10),
        limiter: limiter,
      );
      final stopwatch = Stopwatch()..start();
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, data);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(700));
    });
  });

  test('BandwidthUnit converts units', () {
    expect(BandwidthUnit.bytesPerSecond.toBytesPerSecond(512), 512);
    expect(BandwidthUnit.kibibytesPerSecond.toBytesPerSecond(1), 1024);
    expect(BandwidthUnit.mebibytesPerSecond.toBytesPerSecond(2), 2097152);
  });
}
