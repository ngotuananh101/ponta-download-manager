import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_transport/download_transport.dart';
import 'package:test/test.dart';

import 'download_core_test.dart' show MemorySink;

final _body = List<int>.generate(32, (i) => i + 1);

class _Transport implements DownloadTransport {
  _Transport(this.serve);

  final Stream<List<int>> Function(int start, int? end) serve;
  final requests = <({int start, int? end, String? ifRange})>[];

  @override
  Future<ResourceInfo> probe(Uri url, {Map<String, String>? headers}) async =>
      ResourceInfo(
        finalUrl: url,
        statusCode: 200,
        contentLength: _body.length,
        supportsRange: true,
        eTag: '"v1"',
        lastModified: null,
        contentDisposition: null,
        contentType: 'application/octet-stream',
        fileName: 'file',
      );

  @override
  Future<RangeValidation> validateRange(Uri url, {
    required int start,
    required int end,
    Map<String, String>? headers,
  }) async => RangeValidation.valid(totalBytes: _body.length);

  @override
  Stream<List<int>> openStream(Uri url, {
    int? start,
    int? end,
    String? ifRange,
    Map<String, String>? headers,
  }) {
    requests.add((start: start ?? 0, end: end, ifRange: ifRange));
    return serve(start ?? 0, end);
  }

  @override
  void close() {}
}

DownloadTask _task(_Transport transport, MemorySink sink, {
  int maxConnections = 8,
  int maxRetries = 3,
  Duration retryDelay = const Duration(milliseconds: 10),
}) => DownloadTask(
  transport: transport,
  sink: sink,
  url: Uri.parse('https://example.test/file'),
  id: 'adaptive',
  maxConnections: maxConnections,
  maxRetries: maxRetries,
  retryDelay: retryDelay,
);

Matcher _error(String code) =>
    isA<DownloadError>().having((error) => error.code, 'code', code);

void main() {
  for (final code in ['http-429', 'http-503', 'network']) {
    test('recovers at two active range streams after $code without restarting', () async {
      final release = Completer<void>();
      var active = 0;
      final heldStarts = <int>{};
      var rejected = 0;
      final transport = _Transport((start, end) async* {
        if (active >= 2) {
          rejected++;
          throw DownloadError(code, 'Only two active ranges are allowed');
        }
        active++;
        try {
          // Hold the first two streams actually admitted by the server.
          if (heldStarts.length < 2) {
            heldStarts.add(start);
            yield _body.sublist(start, start + 1);
            await release.future;
            yield _body.sublist(start + 1, end! + 1);
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 2));
            yield _body.sublist(start, end! + 1);
          }
        } finally {
          active--;
        }
      });
      final sink = MemorySink();
      final task = _task(transport, sink);
      final timer = Timer(const Duration(milliseconds: 180), release.complete);
      final info = await task.run().timeout(const Duration(seconds: 3));
      timer.cancel();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, _body);
      expect(active, 0);
      expect(rejected, inInclusiveRange(1, 18));
      expect(heldStarts, hasLength(2));
      for (final start in heldStarts) {
        expect(transport.requests.where((request) => request.end == start + 3),
            hasLength(1));
      }
      expect(transport.requests.every((request) =>
          request.end != null && request.ifRange == '"v1"'), isTrue);
    });
  }

  test('adapts to one connection when excess requests reset', () async {
    final release = Completer<void>();
    var active = false;
    final transport = _Transport((start, end) async* {
      if (active) {
        throw const DownloadError('network', 'Only one active range is allowed');
      }
      active = true;
      try {
        yield _body.sublist(start, end! + 1);
        await release.future;
      } finally {
        active = false;
      }
    });
    final sink = MemorySink();
    final task = _task(transport, sink, maxConnections: 32, maxRetries: 1);
    final timer = Timer(const Duration(milliseconds: 250), release.complete);
    try {
      expect((await task.run().timeout(const Duration(seconds: 3))).status,
          DownloadStatus.completed);
      expect(sink.bytes, _body);
    } finally {
      timer.cancel();
      if (!release.isCompleted) {
        release.complete();
      }
      task.cancel();
    }
  });

  test('range fallback waits for sibling stream cancellation', () async {
    final listening = Completer<void>();
    final cancelling = Completer<void>();
    final releaseCancellation = Completer<void>();
    final sibling = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () {
        cancelling.complete();
        return releaseCancellation.future;
      },
    );
    final rejected = StreamController<List<int>>();
    final sink = MemorySink();
    final transport = _Transport((start, end) {
      if (end == null) {
        expect(releaseCancellation.isCompleted, isTrue);
        return Stream.value(_body);
      }
      return start == 0 ? rejected.stream : sibling.stream;
    });
    final task = _task(transport, sink, maxConnections: 2);
    final run = task.run();
    try {
      await listening.future.timeout(const Duration(seconds: 2));
      rejected.addError(const DownloadError('range-ignored', 'Ignored Range'));
      unawaited(rejected.close());
      await cancelling.future.timeout(const Duration(seconds: 2));
      expect(transport.requests.any((r) => r.end == null), isFalse);
      releaseCancellation.complete();
      expect((await run.timeout(const Duration(seconds: 2))).status,
          DownloadStatus.completed);
      expect(sink.bytes, _body);
    } finally {
      if (!releaseCancellation.isCompleted) {
        releaseCancellation.complete();
      }
      task.cancel();
      await run;
      await sibling.close();
    }
  });

  test('retries a clean short range from the first missing byte', () async {
    final transport = _Transport((start, end) async* {
      if (start == 0) {
        yield _body.sublist(0, 3);
      } else {
        yield _body.sublist(start, end! + 1);
      }
    });
    final sink = MemorySink();
    final info = await _task(transport, sink, maxConnections: 2).run();
    expect(info.status, DownloadStatus.completed);
    expect(sink.bytes, _body);
    expect(transport.requests.where((r) => r.end == 15).map((r) => r.start), [0, 3]);
  });

  test('an empty range cannot repeatedly reset its retry budget', () async {
    final transport = _Transport((_, _) => Stream.value(<int>[]));
    final sink = MemorySink();
    await expectLater(
      _task(transport, sink, maxConnections: 1, maxRetries: 1)
          .run().timeout(const Duration(seconds: 2)),
      throwsA(_error('truncated')),
    );
    expect(transport.requests.length, 2);
  });

  test('cancel interrupts a long retry delay', () async {
    final rejected = Completer<void>();
    final transport = _Transport((_, _) async* {
      rejected.complete();
      throw const DownloadError('http-429', 'Rate limited');
    });
    final task = _task(transport, MemorySink(), maxConnections: 1,
        retryDelay: const Duration(seconds: 3));
    final run = task.run();
    await rejected.future;
    await Future<void>.delayed(Duration.zero);
    task.cancel();
    final info = await run.timeout(const Duration(milliseconds: 500));
    expect(info.status, DownloadStatus.cancelled);
    expect(transport.requests.length, 1);
  });

  test('Retry-After holds all new requests but lets active streams finish', () async {
    final clock = Stopwatch()..start();
    var limitedAt = Duration.zero;
    var limited = false;
    final starts = <Duration>[];
    final transport = _Transport((start, end) async* {
      starts.add(clock.elapsed);
      if (start == 0 && !limited) {
        limited = true;
        limitedAt = clock.elapsed;
        throw const DownloadError('http-429', 'Slow down',
            retryAfter: Duration(milliseconds: 100));
      }
      yield _body.sublist(start, end! + 1);
    });
    final sink = MemorySink();
    await _task(transport, sink, maxConnections: 2).run();
    expect(sink.bytes, _body);
    expect(starts.length, 3);
    expect(starts.last - limitedAt,
        greaterThanOrEqualTo(const Duration(milliseconds: 100)));
  });

  test('range fallback preserves an existing Retry-After cooldown', () async {
    const delay = Duration(milliseconds: 150);
    final clock = Stopwatch()..start();
    final limited = StreamController<List<int>>();
    final ignored = StreamController<List<int>>();
    final bothOpened = Completer<void>();
    var opened = 0;
    var fallbackAt = Duration.zero;
    final transport = _Transport((start, end) {
      if (end == null) {
        fallbackAt = clock.elapsed;
        return Stream.value(_body);
      }
      if (++opened == 2) {
        bothOpened.complete();
      }
      return start == 0 ? limited.stream : ignored.stream;
    });
    final sink = MemorySink();
    final task = _task(transport, sink, maxConnections: 2);
    final run = task.run();
    await bothOpened.future;
    final limitedAt = clock.elapsed;
    limited.addError(const DownloadError('http-429', 'Slow down', retryAfter: delay));
    unawaited(limited.close());
    // Let the first response establish the cooldown before reporting the
    // ignored range on the other connection.
    await Future<void>.delayed(Duration.zero);
    ignored.addError(const DownloadError('range-ignored', 'Ignored Range'));
    unawaited(ignored.close());
    expect((await run.timeout(const Duration(seconds: 2))).status,
        DownloadStatus.completed);
    expect(sink.bytes, _body);
    expect(fallbackAt - limitedAt, greaterThanOrEqualTo(delay));
  });

  test('pause and resume do not bypass the server cooldown', () async {
    var tries = 0;
    final rejected = Completer<void>();
    final clock = Stopwatch()..start();
    var limitedAt = Duration.zero;
    var retriedAt = Duration.zero;
    final transport = _Transport((start, end) async* {
      if (tries++ == 0) {
        limitedAt = clock.elapsed;
        rejected.complete();
        throw const DownloadError('http-503', 'Unavailable',
            retryAfter: Duration(milliseconds: 160));
      }
      retriedAt = clock.elapsed;
      yield _body.sublist(start, end! + 1);
    });
    final task = _task(transport, MemorySink(), maxConnections: 1);
    final run = task.run();
    await rejected.future;
    await Future<void>.delayed(Duration.zero);
    task.pause();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(tries, 1);
    task.resume();
    await run;
    expect(retriedAt - limitedAt,
        greaterThanOrEqualTo(const Duration(milliseconds: 160)));
  });

  test('cancel interrupts server cooldown without leaving an active timer', () async {
    final rejected = Completer<void>();
    final transport = _Transport((_, _) async* {
      rejected.complete();
      throw const DownloadError('http-429', 'Wait',
          retryAfter: Duration(days: 1));
    });
    final task = _task(transport, MemorySink(), maxConnections: 1);
    final run = task.run();
    await rejected.future;
    await Future<void>.delayed(Duration.zero);
    task.cancel();
    expect((await run.timeout(const Duration(milliseconds: 500))).status,
        DownloadStatus.cancelled);
    expect(transport.requests.length, 1);
  });

  test('an authorization error is not retried at lower concurrency', () async {
    final transport = _Transport((_, _) =>
        Stream.error(const DownloadError('http-403', 'Forbidden')));
    await expectLater(_task(transport, MemorySink(), maxConnections: 1).run(),
        throwsA(_error('http-403')));
    expect(transport.requests.length, 1);
  });
}
