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
  final probeHeaders = <Map<String, String>?>[];
  final streamHeaders = <Map<String, String>?>[];
  var openStreams = 0;
  var maxOpenStreams = 0;

  @override
  Future<ResourceInfo> probe(Uri url, {Map<String, String>? headers}) async {
    await onProbe?.call(url);
    probeHeaders.add(headers);
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
    Map<String, String>? headers,
  }) async {
    return RangeValidation.valid(totalBytes: data.length);
  }

  @override
  Stream<List<int>> openStream(
    Uri url, {
    int? start,
    int? end,
    String? ifRange,
    Map<String, String>? headers,
  }) async* {
    startedUrls.add(url.toString());
    ifRanges.add(ifRange);
    streamHeaders.add(headers);
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

/// Records its own close, so a test can see a task being discarded.
class _RecordingSink extends _NullSink {
  _RecordingSink(this.onClose);

  final void Function() onClose;

  @override
  Future<void> close() async {
    onClose();
  }
}

/// Rejects writes after close(), like the real file sink.
class _StrictSink implements ChunkSink {
  var _closed = false;

  @override
  String? get filePath => null;

  @override
  Future<void> write(int offset, List<int> bytes) async {
    if (_closed) {
      throw StateError('FileChunkSink is closed');
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

/// Holds close() until [gate] completes, so a test can order a
/// replacement job against the failing attempt's teardown.
class _GatedCloseSink extends _NullSink {
  _GatedCloseSink(this.gate);

  final Future<void> gate;

  @override
  Future<void> close() async {
    await gate;
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

    test('the default factory builds a task carrying the job headers',
        () async {
      final transport = _FakeTransport(data: bytesOf(1024));
      final tempDir =
          await Directory.systemTemp.createTemp('pdm-sched-headers-');
      addTearDown(() => tempDir.delete(recursive: true));
      final scheduler = DownloadScheduler(transport: transport);
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        directory: tempDir.path,
        cookie: 'session=abc',
        referrer: 'https://example.com/page',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(transport.probeHeaders, isNotEmpty);
      expect(transport.probeHeaders.last?['cookie'], 'session=abc');
      expect(
        transport.probeHeaders.last?['referer'],
        'https://example.com/page',
      );
      expect(transport.streamHeaders, isNotEmpty);
      expect(transport.streamHeaders.last?['cookie'], 'session=abc');
      expect(
        transport.streamHeaders.last?['referer'],
        'https://example.com/page',
      );
    });
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

    test('an erroring attempt cannot settle the job that replaced it',
        () async {
      // A failed task emits its failed event before its run() future
      // completes: it is still closing its sink. A consumer reacts to
      // that event by starting a new attempt for the same id (the
      // engine's mirror failover and a retry both do). By the time the
      // old attempt's error reaches _onTaskError, _running[id] is the
      // *new* job — and an id-only remove and status write threw the
      // live attempt away and marked its row failed while it was still
      // transferring.
      final closed = Completer<void>();
      var builds = 0;
      var restarted = false;
      late DownloadScheduler scheduler;
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 40),
      );
      transport.failPaths.add('/fail');
      scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          builds++;
          final ChunkSink sink = job.url.endsWith('/fail')
              ? _GatedCloseSink(closed.future)
              : _NullSink();
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: 1,
            retryDelay: const Duration(milliseconds: 10),
          );
          if (job.url.endsWith('/fail')) {
            // Fire the replacement while the failing attempt is still
            // tearing down, exactly like a failover on the failed event.
            final guard = task.events.listen((event) {
              event.maybeWhen(
                failed: (downloadId, _, _) {
                  if (restarted) {
                    return;
                  }
                  restarted = true;
                  scheduler.enqueue(
                    url: 'http://example.test/good',
                    fileName: 'f.bin',
                    maxConnections: 1,
                    id: downloadId,
                  );
                },
                orElse: () {},
              );
            });
            addTearDown(guard.cancel);
          }
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/fail',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/good'),
      );
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      expect(builds, 2);
      // The failing attempt finishes tearing down only now: its error
      // must not touch the attempt that replaced it.
      closed.complete();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        infoOf(scheduler, id).status,
        DownloadStatus.downloading,
        reason: 'the failed attempt marked the replacement failed',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(infoOf(scheduler, id).downloadedBytes, 4096);
    });

    test('a new attempt for an id discards the paused one it replaces',
        () async {
      // Pausing keeps the task alive: it is in _pausedRunning with its
      // sink open, waiting for a resume. Enqueueing a new attempt for
      // the same id (a retry of a paused row, a failover) used to leave
      // it there forever: two live tasks for one id, the paused one
      // still holding its sink and its segments, and a resume would
      // then start the attempt the row no longer belongs to.
      final closed = <String>[];
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      var builds = 0;
      final scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          builds++;
          final attempt = builds;
          final sink = _RecordingSink(
            () => closed.add('${job.url}#$attempt'),
          );
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: 1,
            retryDelay: const Duration(milliseconds: 10),
          );
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/slow',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      scheduler.pause(id);
      await waitForStatus(scheduler, id, DownloadStatus.paused);
      // The retry: a second attempt for the id the paused one still
      // holds.
      scheduler.enqueue(
        url: 'http://example.test/fast',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(builds, 2);
      await waitFor(
        () => closed.contains('http://example.test/slow#1'),
        timeout: const Duration(seconds: 2),
      );
      expect(infoOf(scheduler, id).downloadedBytes, 4096);
    });

    test('cancelling a resumed task cancels it instead of the sink', () async {
      // A job parked before its run (paused during the start window) is
      // resumed into _pending with runStarted: false. _start then calls
      // run() on it, so from that instant the task *is* running: the
      // entry must say so. Reported as false, cancel() took the
      // "never ran" path, closed the sink underneath the live task and
      // never called task.cancel() — the transfer failed on a closed
      // sink and the row went Cancelled then Failed.
      final transport = _FakeTransport(
        data: bytesOf(8192),
        chunkDelay: const Duration(milliseconds: 40),
      );
      final factoryEntered = Completer<void>();
      final releaseFactory = Completer<void>();
      var builds = 0;
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          builds++;
          if (builds == 1) {
            factoryEntered.complete();
            await releaseFactory.future;
          }
          // A sink that refuses writes once closed, like the file one:
          // closing it under a live task is fatal, not a no-op.
          final sink = _StrictSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
              retryDelay: const Duration(milliseconds: 10),
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryEntered.future.timeout(const Duration(seconds: 5));
      scheduler.pause(id);
      releaseFactory.complete();
      await waitForStatus(scheduler, id, DownloadStatus.paused);
      scheduler.resume(id);
      // run() is live now: the transfer progresses.
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      final seen = <DownloadEvent>[];
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      scheduler.cancel(id);
      await waitForStatus(scheduler, id, DownloadStatus.cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        seen.whereType<DownloadFailed>(),
        isEmpty,
        reason: 'the sink was closed under the live task',
      );
      expect(infoOf(scheduler, id).status, DownloadStatus.cancelled);
    });

    test('a finishing attempt does not settle a replacement still queued',
        () async {
      // The replacement does not have to be running yet: with one slot
      // and the old attempt still in _running, enqueue() puts it in
      // _pending, and _infos[id] already says queued. The old entry is
      // still the one in _running, so an ownership test that only looks
      // at _running says "mine" and the old attempt reports completed
      // for a job that has not even started — the row is finished
      // before the retry transfers anything.
      final transport = _FakeTransport(
        data: bytesOf(1024),
        chunkDelay: const Duration(milliseconds: 10),
      );
      final releases = <Completer<void>>[];
      var restarted = false;
      late DownloadScheduler scheduler;
      scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          releases.add(Completer<void>());
          if (job.url.endsWith('/slow')) {
            // The replacement's factory is held, so nothing about it can
            // be blamed for the old attempt's report.
            await releases.last.future;
          }
          final sink = _NullSink();
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: 1,
            retryDelay: const Duration(milliseconds: 10),
          );
          if (job.url.endsWith('/a')) {
            final guard = task.events.listen((event) {
              event.maybeWhen(
                completed: (downloadId, _) {
                  if (restarted) {
                    return;
                  }
                  restarted = true;
                  scheduler.enqueue(
                    url: 'http://example.test/slow',
                    fileName: 'f.bin',
                    maxConnections: 1,
                    id: downloadId,
                  );
                },
                orElse: () {},
              );
            });
            addTearDown(guard.cancel);
          }
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => restarted);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        infoOf(scheduler, id).status,
        isNot(DownloadStatus.completed),
        reason: 'the finished attempt settled the replacement',
      );
      expect(infoOf(scheduler, id).downloadedBytes, isNot(1024));
    });

    test('a replaced paused attempt tells its owner to stop tracking it',
        () async {
      // The attempt being replaced already ran: its task keeps
      // checkpointing until it is told otherwise, and cancelling it
      // makes it emit cancelled — which the owner writes to the row the
      // retry now owns, leaving the retry's download shown (and stored)
      // as cancelled while it transfers. runStarted is not the point:
      // either way the task no longer owns the id.
      final abandoned = <String>[];
      final transport = _FakeTransport(
        data: bytesOf(8192),
        chunkDelay: const Duration(milliseconds: 40),
      );
      final scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
              retryDelay: const Duration(milliseconds: 10),
            ),
            sink,
            onAbandoned: () => abandoned.add(job.url),
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/slow',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      scheduler.pause(id);
      await waitForStatus(scheduler, id, DownloadStatus.paused);
      expect(abandoned, isEmpty);
      scheduler.enqueue(
        url: 'http://example.test/fast',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(
        abandoned,
        ['http://example.test/slow'],
        reason: 'the paused attempt kept writing the retry\'s row',
      );
    });

    test('a cancelled start is not a current attempt', () async {
      // The factory asks this after its awaits before registering the
      // task with its owner. A cancel inside that window is the user
      // changing their mind: the scheduler will throw the task away, so
      // registering it would write the row the cancel just settled —
      // and for a delete, write a deleted row back into the store.
      final factoryEntered = Completer<void>();
      final releaseFactory = Completer<void>();
      late bool current;
      late DownloadScheduler scheduler;
      scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          if (!factoryEntered.isCompleted) {
            factoryEntered.complete();
            await releaseFactory.future;
          }
          current = scheduler.isCurrentAttempt(job);
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: _FakeTransport(data: bytesOf(64)),
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryEntered.future.timeout(const Duration(seconds: 5));
      scheduler.cancel(id);
      releaseFactory.complete();
      await releaseFactory.future;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        current,
        isFalse,
        reason: 'a cancelled start still reported itself as current',
      );
    });

    test('a retry discards a paused attempt still waiting in the queue',
        () async {
      // A download created paused never reaches _pausedRunning: it sits
      // in _pending, flagged paused, until resume() un-pauses it. A
      // retry for the same id enqueues a second attempt, and both are
      // now queued under one id — the retried one starts, the paused one
      // stays behind it. Any later resume() finds the old attempt first
      // (it is earlier in the queue) and starts it, so the same file is
      // downloaded a second time over the retry that already owns it.
      final transport = _FakeTransport(data: bytesOf(256));
      final scheduler = _makeScheduler(transport);
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'f.bin',
        maxConnections: 1,
        paused: true,
      );
      scheduler.enqueue(
        id: id,
        url: 'http://example.test/b',
        fileName: 'f.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      scheduler.resume(id);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        transport.startedUrls,
        ['http://example.test/b'],
        reason: 'the paused attempt the retry replaced ran as well',
      );
      expect(infoOf(scheduler, id).status, DownloadStatus.completed);
    });

    test('a retry discards a resumed attempt waiting in the queue',
        () async {
      // The other parked shape: an attempt that was paused while it ran
      // and then resumed still has its task, sink and subscription, and
      // waits in _pending until a slot frees. A retry that replaces it
      // must drop all three: a stale entry with a live task behind the
      // retry's own download in the queue is run again by the next
      // resume(), over the file the retry owns.
      final transport = _FakeTransport(data: bytesOf(256));
      final scheduler = _makeScheduler(transport, maxConcurrent: 1);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      final c = scheduler.enqueue(
        url: 'http://example.test/c',
        fileName: 'c.bin',
        maxConnections: 1,
      );
      scheduler.pause(a);
      await waitForStatus(scheduler, a, DownloadStatus.paused);
      // No slot free now that c starts, so this attempt waits in the
      // queue with its task still attached.
      scheduler.resume(a);
      scheduler.pause(a);
      scheduler.enqueue(
        id: a,
        url: 'http://example.test/b',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, c, DownloadStatus.completed);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      scheduler.resume(a);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        transport.startedUrls.where((u) => u.endsWith('/a')),
        isEmpty,
        reason: 'the replaced attempt was queued twice',
      );
      expect(infoOf(scheduler, a).status, DownloadStatus.completed);
    });

    test('a pause does not leave a failed task holding its slot', () async {
      // Pausing moves the attempt from _running to _pausedRunning. The
      // task can still fail afterwards — a paused transfer is only
      // stopped once its in-flight request unwinds — and that failure
      // reaches _onTaskError with the entry no longer in _running.
      // Leaving it in _pausedRunning keeps a dead task parked forever,
      // and resume() then puts it back in the queue: _start assigns the
      // slot again and calls run() on a task whose stream has already
      // closed, which throws out of the catch block and leaks the slot
      // for good.
      final transport = _FakeTransport(data: bytesOf(1024));
      final probeEntered = Completer<void>();
      final releaseProbe = Completer<void>();
      transport.onProbe = (url) async {
        if (!probeEntered.isCompleted) {
          probeEntered.complete();
          await releaseProbe.future;
          throw DownloadError('network', 'probe failed after pause');
        }
      };
      var builds = 0;
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          builds++;
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
              retryDelay: const Duration(milliseconds: 10),
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      await probeEntered.future.timeout(const Duration(seconds: 5));
      scheduler.pause(a);
      await waitForStatus(scheduler, a, DownloadStatus.paused);
      releaseProbe.complete();
      await waitForStatus(scheduler, a, DownloadStatus.failed);
      expect(builds, 1, reason: 'the failed attempt was started twice');
      // Resuming the failed row must not start a run for a task that
      // has already ended its stream.
      scheduler.resume(a);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        builds,
        1,
        reason: 'resume restarted a task that had already failed',
      );
      expect(infoOf(scheduler, a).status, DownloadStatus.failed);
      // And the single slot must still be usable.
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 1,
      );
      await waitForStatus(scheduler, b, DownloadStatus.completed);
    });

    test('a retry of a paused attempt announces no cancelled for it',
        () async {
      // Discarding the paused attempt cancels its task so it stops
      // writing. That cancellation emits its own cancelled event, and
      // the UI learns state only from events: forwarding it would put
      // the row on Cancelled while the retry is already transferring.
      final seen = <DownloadEvent>[];
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 40),
      );
      final scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          final sink = _NullSink();
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: 1,
            retryDelay: const Duration(milliseconds: 10),
          );
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/slow',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      scheduler.pause(id);
      await waitForStatus(scheduler, id, DownloadStatus.paused);
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      scheduler.enqueue(
        url: 'http://example.test/fast',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(
        seen.whereType<DownloadStateChanged>().where(
              (e) =>
                  e.downloadId == id &&
                  e.status == DownloadStatus.cancelled,
            ),
        isEmpty,
        reason: 'the retry was announced as cancelled',
      );
    });

    test('a finishing attempt cannot settle the job that replaced it',
        () async {
      // The same window on the success side. The task reports completed
      // before its run() future resolves, and changeNotifier-style
      // consumers react by enqueueing a new attempt for the id. The
      // scheduler's own bookkeeping then ran against whatever attempt
      // held the id, so the finished attempt reported completed for a
      // job that had already been replaced and its own _pump() raced
      // the new one.
      final finished = Completer<void>();
      var builds = 0;
      var restarted = false;
      late DownloadScheduler scheduler;
      // Slow enough that the replacement is still transferring when
      // the finished attempt reports.
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 25),
      );
      scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          builds++;
          final ChunkSink sink = job.url.endsWith('/a')
              ? _GatedCloseSink(finished.future)
              : _NullSink();
          final task = DownloadTask(
            transport: transport,
            sink: sink,
            url: Uri.parse(job.url),
            id: job.id,
            maxConnections: 1,
            retryDelay: const Duration(milliseconds: 10),
          );
          if (job.url.endsWith('/a')) {
            final guard = task.events.listen((event) {
              event.maybeWhen(
                completed: (downloadId, _) {
                  if (restarted) {
                    return;
                  }
                  restarted = true;
                  scheduler.enqueue(
                    url: 'http://example.test/slow',
                    fileName: 'f.bin',
                    maxConnections: 1,
                    id: downloadId,
                  );
                },
                orElse: () {},
              );
            });
            addTearDown(guard.cancel);
          }
          return ScheduledTask(task, sink);
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'f.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/slow'),
      );
      await waitFor(() => infoOf(scheduler, id).downloadedBytes > 0);
      expect(builds, 2);
      // The finished attempt reports now, with the replacement live.
      finished.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        infoOf(scheduler, id).status,
        DownloadStatus.downloading,
        reason: 'the finished attempt reported completed over the replacement',
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

    test('resume emits queued before the download restarts', () async {
      // The engine's store is updated by the engine, but the UI only
      // learns a state from scheduler events. Resuming a job that was
      // paused while running must therefore announce queued: the slot
      // may still be taken (nothing else will emit), and even with a
      // free slot the task's own queued status is a no-op, so the row
      // would sit at Paused until the first progress arrives.
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
      scheduler.pause(a);
      // The only slot is now busy with b, so the resumed job has to
      // wait in _pending: no other event can move the row.
      await waitFor(
        () => transport.startedUrls.contains('http://example.test/b'),
      );
      final seen = <DownloadEvent>[];
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      scheduler.resume(a);
      // The broadcast stream delivers asynchronously.
      await Future<void>.delayed(Duration.zero);
      expect(
        seen.whereType<DownloadStateChanged>().map((e) => e.status),
        contains(DownloadStatus.queued),
      );
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
    });

    test('pausing a download still starting emits paused', () async {
      // pause() returns early while the task is being built (the id is
      // parked in _pausedWhileStarting) and _start then moves it to the
      // paused set without an event, so the UI would keep showing
      // Queued for a download that will not start until resumed.
      final transport = _FakeTransport(data: bytesOf(4096));
      final factoryStarted = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          if (!factoryStarted.isCompleted) {
            factoryStarted.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: job.maxConnections,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      await factoryStarted.future.timeout(const Duration(seconds: 5));
      final seen = <DownloadEvent>[];
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      scheduler.pause(a);
      releaseFactory.complete();
      // The parked job never starts, so nothing else can correct the
      // snapshot: once the factory has drained, both the snapshot and
      // the event stream must already say paused.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        seen.whereType<DownloadStateChanged>().map((e) => e.status),
        contains(DownloadStatus.paused),
      );
      expect(infoOf(scheduler, a).status, DownloadStatus.paused);
      expect(infoOf(scheduler, a).downloadedBytes, 0);
      // The parked job must still be resumable afterwards.
      scheduler.resume(a);
      await waitForStatus(scheduler, a, DownloadStatus.completed);
    });

    test('resuming while the task is still starting is not lost', () async {
      // pause() records the intent in _pausedWhileStarting because the
      // factory is still building the task. Resume must cancel that
      // intent: _start parks the job as paused when the flag is still
      // there, so a swallowed resume leaves a download the user asked
      // to resume stuck at Paused with nothing left to wake it.
      final transport = _FakeTransport(data: bytesOf(4096));
      final factoryStarted = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          if (!factoryStarted.isCompleted) {
            factoryStarted.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: job.maxConnections,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
      );
      await factoryStarted.future.timeout(const Duration(seconds: 5));
      final seen = <DownloadEvent>[];
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      scheduler.pause(a);
      scheduler.resume(a);
      releaseFactory.complete();
      // The job must be running (or already done), never parked.
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      final finalStatus = seen
          .whereType<DownloadStateChanged>()
          .map((e) => e.status)
          .lastOrNull;
      expect(finalStatus, isNot(DownloadStatus.paused));
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

    test('a pause and cancel during a start do not stick to the retry',
        () async {
      // The row can be paused and then cancelled while the factory is
      // still building: cancel settles it, but it was paused first.
      // The pause flag has to be dropped with the cancelled job, or
      // the next attempt for the same id (a retry) is parked as paused
      // and never runs — with no event to correct the row either.
      final transport = _FakeTransport(data: bytesOf(1024));
      final factoryStarted = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          if (!factoryStarted.isCompleted) {
            factoryStarted.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: job.maxConnections,
            ),
            sink,
          );
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
      scheduler.cancel(id);
      releaseFactory.complete();
      await waitForStatus(scheduler, id, DownloadStatus.cancelled);
      // Retry the same id: it must actually run, not sit queued
      // forever on the pause intent of a job that was cancelled.
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

    test('a retry during the aborted start is not cancelled by it', () async {
      // The job was paused then cancelled while its factory was still
      // building, and the user retried the same id before that
      // factory finished: the retry is a *new* attempt, already
      // queued and possibly already running. The aborted attempt must
      // not settle the retry's tracking, nor announce cancelled for
      // it — the row would show Cancelled during an active download,
      // and a pause issued on the retry would be lost.
      final transport = _FakeTransport(data: bytesOf(1024));
      final factoryStarted = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          if (!factoryStarted.isCompleted) {
            factoryStarted.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: job.maxConnections,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final seen = <DownloadEvent>[];
      final subscription = scheduler.events.listen(seen.add);
      addTearDown(subscription.cancel);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryStarted.future.timeout(const Duration(seconds: 5));
      scheduler.pause(id);
      scheduler.cancel(id);
      // The retry lands while the aborted attempt still waits on its
      // factory, and starts under a free slot of its own.
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      releaseFactory.complete();
      await waitFor(
        () => infoOf(scheduler, id).status == DownloadStatus.completed,
        timeout: const Duration(seconds: 5),
      );
      final cancelledEvents = seen
          .whereType<DownloadStateChanged>()
          .where(
            (e) => e.downloadId == id && e.status == DownloadStatus.cancelled,
          )
          .length;
      // The aborted attempt may announce cancelled only once — the
      // explicit cancel. A second cancelled after the retry's queued
      // event is the stale one this test is about.
      expect(
        cancelledEvents,
        lessThanOrEqualTo(1),
        reason: 'the aborted start announced cancelled over the retry',
      );
      expect(infoOf(scheduler, id).downloadedBytes, 1024);
    });

    test('a pause on the retry survives the aborted start finishing',
        () async {
      // Same window, the other half: the retry is building its task
      // when the aborted attempt's factory resolves. That attempt used
      // to clear the id's _starting membership, so the pause issued on
      // the retry fell through to the queued branch — which cannot see
      // the retry, now in _starting — and was dropped: the download
      // ran to completion after the user paused it.
      final transport = _FakeTransport(data: bytesOf(4096));
      final factories = <Completer<void>>[];
      final starts = <Completer<void>>[];
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          final release = Completer<void>();
          factories.add(release);
          if (starts.isEmpty || factories.length > starts.length) {
            final started = Completer<void>();
            starts.add(started);
            started.complete();
          }
          await release.future;
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: job.maxConnections,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => factories.isNotEmpty);
      scheduler.pause(id);
      scheduler.cancel(id);
      // The retry starts and blocks in its own factory.
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => factories.length == 2);
      // The pause lands on the retry, which is still building.
      scheduler.pause(id);
      // Only now does the aborted attempt's factory resolve.
      factories.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      factories.last.complete();
      await waitForStatus(scheduler, id, DownloadStatus.paused);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        infoOf(scheduler, id).status,
        DownloadStatus.paused,
        reason: 'the aborted start dropped the pause on the retry',
      );
    });

    test('a cancel of a job parked before its run tells the owner', () async {
      // Pausing during the start window parks the built task in
      // _pausedRunning with runStarted: false: the task exists and was
      // registered with its owner, but run() was never called. The
      // cancel path for that state drops the task silently — no
      // task.cancel() (it emits nothing before run()) and no
      // onAbandoned — so the owner kept writing the queued/0-byte
      // snapshot over the row the cancel had just settled.
      final transport = _FakeTransport(data: bytesOf(1024));
      final abandoned = <String>[];
      final factoryEntered = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          if (!factoryEntered.isCompleted) {
            factoryEntered.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
            onAbandoned: () => abandoned.add(job.id),
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryEntered.future.timeout(const Duration(seconds: 5));
      // Pause while the factory is still building: the intent is
      // recorded, and _start parks the task in _pausedRunning when the
      // factory resolves. run() is then never called.
      scheduler.pause(id);
      releaseFactory.complete();
      await waitFor(
        () => infoOf(scheduler, id).status == DownloadStatus.paused,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      scheduler.cancel(id);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        abandoned,
        [id],
        reason: 'the parked task stayed tracked after its cancel',
      );
    });

    test('dispose tells the owner about a task that never ran', () async {
      // Same state, on the way out: dispose() drops a parked task
      // without running it. Its owner (the checkpoint writer) must
      // stop ticking it, exactly like _start's own _disposed branch.
      final transport = _FakeTransport(data: bytesOf(1024));
      final abandoned = <String>[];
      final factoryEntered = Completer<void>();
      final releaseFactory = Completer<void>();
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          if (!factoryEntered.isCompleted) {
            factoryEntered.complete();
            await releaseFactory.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
            onAbandoned: () => abandoned.add(job.id),
          );
        },
      );
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await factoryEntered.future.timeout(const Duration(seconds: 5));
      scheduler.pause(id);
      releaseFactory.complete();
      await waitFor(
        () => infoOf(scheduler, id).status == DownloadStatus.paused,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await scheduler.dispose();
      expect(
        abandoned,
        [id],
        reason: 'dispose left a never-run task tracked in its owner',
      );
    });

    test('isCurrentAttempt is false once a retry replaced the job', () async {
      // The engine registers a task with its checkpoint writer after
      // the factory's await. By then a retry may have replaced the
      // attempt: registering it would take the row's checkpoints from
      // the retry that already owns and runs it. The factory asks
      // isCurrentAttempt() before it touches shared state.
      final transport = _FakeTransport(data: bytesOf(64));
      final releases = <Completer<void>>[];
      final seen = <bool>[];
      late DownloadScheduler scheduler;
      scheduler = DownloadScheduler(
        maxConcurrent: 2,
        taskFactory: (job) async {
          final release = Completer<void>();
          releases.add(release);
          if (releases.length == 1) {
            await release.future;
          }
          seen.add(scheduler.isCurrentAttempt(job));
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 1);
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 2);
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      releases.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        seen,
        [true, false],
        reason: 'the abandoned attempt still reported itself as current',
      );
    });

    test('an abandoned start tells its owner to stop tracking it', () async {
      // The factory registers the task with whoever persists its
      // state (the engine's checkpoint writer). A retry replaces the
      // attempt while that factory is still building, so the task is
      // thrown away without ever running. Its owner must be told: an
      // untracked task keeps writing its queued/0-byte snapshot over
      // the row the retry now owns.
      final transport = _FakeTransport(data: bytesOf(1024));
      final releases = <Completer<void>>[];
      final abandoned = <String>[];
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          final release = Completer<void>();
          releases.add(release);
          if (releases.length == 1) {
            await release.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
            onAbandoned: () => abandoned.add(job.id),
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 1);
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      expect(
        abandoned,
        isEmpty,
        reason: 'the running retry was reported as abandoned',
      );
      releases.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        abandoned,
        [id],
        reason: 'the abandoned start kept writing its snapshot over the row',
      );
    });

    test('a retry does not leave the aborted start running too', () async {
      // The retry replaces the attempt whose factory is still building:
      // once that factory resolves, its task must be thrown away, not
      // registered and run. Otherwise both attempts download the same
      // file at once — the second one overwrites the first's sink —
      // and pause/cancel act on whichever entry landed last.
      final transport = _FakeTransport(data: bytesOf(1024));
      final releases = <Completer<void>>[];
      final scheduler = DownloadScheduler(
        maxConcurrent: 3,
        taskFactory: (job) async {
          final release = Completer<void>();
          releases.add(release);
          if (releases.length == 1) {
            await release.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 1);
      // Retry: a second attempt starts right away, with the first
      // still inside its factory.
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
      // The retry is done; only now does the aborted factory resolve.
      releases.first.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        transport.startedUrls,
        hasLength(1),
        reason: 'the aborted start ran its own duplicate download',
      );
      expect(infoOf(scheduler, id).status, DownloadStatus.completed);
    });

    test('a discarded start frees its slot for the retry waiting behind it',
        () async {
      // With one slot, the aborted start occupies it from the moment
      // _start begins until its factory resolves: the retry enqueued in
      // that window cannot start and waits in _pending. When the
      // aborted factory finally resolves, _start throws the task away
      // and returns — without _pump(), nothing restarts the queue, and
      // the retry sits in _pending forever with no task and no event.
      final transport = _FakeTransport(data: bytesOf(1024));
      final releases = <Completer<void>>[];
      final scheduler = DownloadScheduler(
        maxConcurrent: 1,
        taskFactory: (job) async {
          final release = Completer<void>();
          releases.add(release);
          if (releases.length == 1) {
            await release.future;
          }
          final sink = _NullSink();
          return ScheduledTask(
            DownloadTask(
              transport: transport,
              sink: sink,
              url: Uri.parse(job.url),
              id: job.id,
              maxConnections: 1,
            ),
            sink,
          );
        },
      );
      addTearDown(scheduler.dispose);
      final id = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 1);
      // The retry cannot start yet: the aborted start still holds the
      // only slot.
      scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 1,
        id: 'dl-1',
      );
      await waitFor(() => releases.length == 1);
      expect(
        infoOf(scheduler, id).status,
        isNot(DownloadStatus.completed),
        reason: 'the retry started while the aborted start held the slot',
      );
      // Free the slot by letting the aborted factory finish.
      releases.first.complete();
      await waitFor(
        () => releases.length == 2,
        timeout: const Duration(seconds: 2),
      );
      await waitForStatus(scheduler, id, DownloadStatus.completed);
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

    test('three jobs run together up to maxConcurrent with no total cap',
        () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final scheduler = _makeScheduler(transport, maxConcurrent: 3);
      addTearDown(scheduler.dispose);
      final a = scheduler.enqueue(
        url: 'http://example.test/a',
        fileName: 'a.bin',
        maxConnections: 8,
      );
      final b = scheduler.enqueue(
        url: 'http://example.test/b',
        fileName: 'b.bin',
        maxConnections: 8,
      );
      final c = scheduler.enqueue(
        url: 'http://example.test/c',
        fileName: 'c.bin',
        maxConnections: 8,
      );
      // No total connection cap: a free download slot starts the third
      // job even though 2 x 8 connections are already reserved.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        transport.startedUrls.toSet(),
        {
          'http://example.test/a',
          'http://example.test/b',
          'http://example.test/c',
        },
      );
      await waitForStatus(scheduler, a, DownloadStatus.completed);
      await waitForStatus(scheduler, b, DownloadStatus.completed);
      await waitForStatus(scheduler, c, DownloadStatus.completed);
      expect(transport.maxOpenStreams, 24);
    });
  });
}
