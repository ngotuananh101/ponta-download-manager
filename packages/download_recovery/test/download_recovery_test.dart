import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_core/download_core.dart';
import 'package:download_recovery/download_recovery.dart';
import 'package:download_transport/download_transport.dart';
import 'package:path/path.dart' as p;
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
  _FakeTransport({
    required this.data,
    this.chunkDelay = const Duration(milliseconds: 10),
  });

  final List<int> data;
  final Duration chunkDelay;
  final chunkSize = 256;

  final openedRanges = <({int start, int? end, String? ifRange})>[];

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
    openedRanges.add((start: start ?? 0, end: end, ifRange: ifRange));
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

DownloadRecord makeRecord({
  String id = 'dl-1',
  String url = 'http://example.test/f.bin',
  String fileName = 'f.bin',
  String directory = '/tmp',
  DownloadStatus status = DownloadStatus.paused,
  int downloadedBytes = 0,
  int totalBytes = 1024,
  int maxConnections = 4,
  int priority = 0,
}) {
  return DownloadRecord(
    id: id,
    url: url,
    fileName: fileName,
    directory: directory,
    status: status,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    maxConnections: maxConnections,
    priority: priority,
  );
}

void main() {
  group('DownloadStore', () {
    test('stores and reads back a download and its segments', () {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final record = makeRecord(downloadedBytes: 512);
      store.upsertDownload(record);
      final read = store.getDownload('dl-1')!;
      expect(read.url, record.url);
      expect(read.fileName, record.fileName);
      expect(read.status, DownloadStatus.paused);
      expect(read.downloadedBytes, 512);
      expect(read.totalBytes, 1024);
      store.saveCheckpoint(record, [
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 0,
          start: 0,
          end: 511,
          downloaded: 512,
        ),
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 1,
          start: 512,
          end: 1023,
          downloaded: 0,
        ),
      ]);
      final segments = store.getSegments('dl-1');
      expect(segments.length, 2);
      expect(segments[0].downloaded, 512);
      expect(segments[1].downloaded, 0);
      expect(store.listDownloads().length, 1);
      expect(store.listNonTerminal().length, 1);
      store.upsertDownload(record.copyWith(status: DownloadStatus.completed));
      expect(store.listNonTerminal(), isEmpty);
    });

    test('delete removes the download and its segments', () {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final record = makeRecord();
      store.saveCheckpoint(record, [
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 0,
          start: 0,
          end: 1023,
          downloaded: 100,
        ),
      ]);
      store.deleteDownload('dl-1');
      expect(store.getDownload('dl-1'), isNull);
      expect(store.getSegments('dl-1'), isEmpty);
    });

    test('persists across reopen', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-recovery-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final path = p.join(tempDir.path, 'pdm.db');
      final first = DownloadStore.open(path);
      first.saveCheckpoint(makeRecord(downloadedBytes: 512), [
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 0,
          start: 0,
          end: 511,
          downloaded: 512,
        ),
      ]);
      first.close();
      final second = DownloadStore.open(path);
      addTearDown(second.close);
      expect(second.getDownload('dl-1')!.downloadedBytes, 512);
      expect(second.getSegments('dl-1').length, 1);
    });
  });

  group('CheckpointWriter', () {
    test('writes a completed checkpoint', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-recovery-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final writer = CheckpointWriter(store);
      addTearDown(writer.dispose);
      final transport = _FakeTransport(data: bytesOf(1024));
      final sink = _MemorySink();
      final task = DownloadTask(
        transport: transport,
        sink: sink,
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 2,
        retryDelay: const Duration(milliseconds: 10),
      );
      writer.track(task, directory: tempDir.path, fileName: 'f.bin');
      await task.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final record = store.getDownload('dl-1')!;
      expect(record.status, DownloadStatus.completed);
      expect(record.downloadedBytes, 1024);
      expect(record.totalBytes, 1024);
      expect(record.eTag, 'v1');
      final segments = store.getSegments('dl-1');
      expect(
        segments.fold(0, (sum, s) => sum + s.downloaded),
        1024,
      );
    });

    test('writes promptly on pause', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-recovery-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final writer = CheckpointWriter(store);
      addTearDown(writer.dispose);
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final task = DownloadTask(
        transport: transport,
        sink: _MemorySink(),
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 1,
        retryDelay: const Duration(milliseconds: 10),
      );
      writer.track(task, directory: tempDir.path, fileName: 'f.bin');
      final run = task.run();
      await waitFor(() => task.downloadedBytes > 0);
      task.pause();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final record = store.getDownload('dl-1')!;
      expect(record.status, DownloadStatus.paused);
      expect(record.downloadedBytes, greaterThan(0));
      task.cancel();
      await run;
    });

    test('writes progress on its interval', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-recovery-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final writer = CheckpointWriter(store);
      addTearDown(writer.dispose);
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 100),
      );
      final task = DownloadTask(
        transport: transport,
        sink: _MemorySink(),
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 1,
        retryDelay: const Duration(milliseconds: 10),
      );
      writer.track(task, directory: tempDir.path, fileName: 'f.bin');
      final run = task.run();
      await waitFor(
        () => (store.getDownload('dl-1')?.downloadedBytes ?? 0) > 0,
        timeout: const Duration(seconds: 5),
      );
      task.cancel();
      await run;
    });

    test('flush writes current progress', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'pdm-recovery-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final writer = CheckpointWriter(store);
      addTearDown(writer.dispose);
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final task = DownloadTask(
        transport: transport,
        sink: _MemorySink(),
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 1,
        retryDelay: const Duration(milliseconds: 10),
      );
      writer.track(task, directory: tempDir.path, fileName: 'f.bin');
      final run = task.run();
      await waitFor(() => task.downloadedBytes > 0);
      task.pause();
      writer.flush();
      expect(
        store.getDownload('dl-1')!.downloadedBytes,
        task.downloadedBytes,
      );
      task.cancel();
      await run;
    });
  });

  group('Recovery', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-recovery-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resumes a consistent partial download', () async {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      final record = makeRecord(
        directory: tempDir.path,
        downloadedBytes: 512,
      );
      store.saveCheckpoint(record, [
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 0,
          start: 0,
          end: 511,
          downloaded: 512,
        ),
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 1,
          start: 512,
          end: 1023,
          downloaded: 0,
        ),
      ]);
      await File(p.join(tempDir.path, 'f.bin.partial')).writeAsBytes(
        bytesOf(512),
      );
      final decisions = Recovery(store).reconcile();
      expect(decisions.length, 1);
      expect(decisions[0].action, RecoveryAction.resume);
      expect(decisions[0].segments.length, 2);
    });

    test('restarts when the partial file is missing', () {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.upsertDownload(makeRecord(directory: tempDir.path));
      final decisions = Recovery(store).reconcile();
      expect(decisions.length, 1);
      expect(decisions[0].action, RecoveryAction.restart);
      expect(decisions[0].reason, contains('missing'));
    });

    test('restarts when the checkpoint is inconsistent', () async {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.saveCheckpoint(makeRecord(directory: tempDir.path), [
        const SegmentRecord(
          downloadId: 'dl-1',
          segmentId: 0,
          start: 0,
          end: 511,
          downloaded: 800,
        ),
      ]);
      await File(p.join(tempDir.path, 'f.bin.partial')).writeAsBytes(
        bytesOf(512),
      );
      final decisions = Recovery(store).reconcile();
      expect(decisions[0].action, RecoveryAction.restart);
      expect(decisions[0].reason, contains('inconsistent'));
    });

    test('restarts when segments are unknown for a segmented download',
        () async {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.upsertDownload(
        makeRecord(directory: tempDir.path, downloadedBytes: 512),
      );
      await File(p.join(tempDir.path, 'f.bin.partial')).writeAsBytes(
        bytesOf(512),
      );
      final decisions = Recovery(store).reconcile();
      expect(decisions[0].action, RecoveryAction.restart);
    });

    test('resumes a single-stream download without segments', () async {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.upsertDownload(
        makeRecord(
          directory: tempDir.path,
          downloadedBytes: 512,
          maxConnections: 1,
        ),
      );
      await File(p.join(tempDir.path, 'f.bin.partial')).writeAsBytes(
        bytesOf(512),
      );
      final decisions = Recovery(store).reconcile();
      expect(decisions[0].action, RecoveryAction.resume);
      expect(decisions[0].segments.length, 1);
      expect(decisions[0].segments[0].downloaded, 512);
      expect(decisions[0].segments[0].end, isNull);
    });

    test('completes a download whose final file exists', () async {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.upsertDownload(makeRecord(directory: tempDir.path));
      await File(p.join(tempDir.path, 'f.bin')).writeAsBytes(bytesOf(1024));
      final decisions = Recovery(store).reconcile();
      expect(decisions[0].action, RecoveryAction.complete);
      expect(
        store.getDownload('dl-1')!.status,
        DownloadStatus.completed,
      );
    });

    test('marks a corrupt record unrecoverable', () {
      final store = DownloadStore.inMemory();
      addTearDown(store.close);
      store.upsertDownload(
        makeRecord(directory: tempDir.path, url: ''),
      );
      final decisions = Recovery(store).reconcile();
      expect(decisions[0].action, RecoveryAction.unrecoverable);
    });
  });

  group('DownloadTask resume', () {
    test('fetches only the missing ranges', () async {
      final data = bytesOf(1024);
      final transport = _FakeTransport(data: data);
      final sink = _MemorySink()..bytes.addAll(data.sublist(0, 512));
      final task = DownloadTask(
        transport: transport,
        sink: sink,
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 1,
        retryDelay: const Duration(milliseconds: 10),
        resumeFrom: const [
          SegmentProgress(
            segmentId: 0,
            start: 0,
            end: 1023,
            downloaded: 512,
          ),
        ],
      );
      final info = await task.run();
      expect(info.status, DownloadStatus.completed);
      expect(sink.bytes, data);
      expect(
        transport.openedRanges.map((r) => r.start).toList(),
        [512],
      );
      expect(
        transport.openedRanges.map((r) => r.end).toList(),
        [1023],
      );
      expect(task.segments.length, 1);
      expect(task.segments[0].downloaded, 1024);
    });

    test('segments getter reports live progress', () async {
      final transport = _FakeTransport(
        data: bytesOf(4096),
        chunkDelay: const Duration(milliseconds: 50),
      );
      final task = DownloadTask(
        transport: transport,
        sink: _MemorySink(),
        url: Uri.parse('http://example.test/f.bin'),
        id: 'dl-1',
        maxConnections: 2,
        retryDelay: const Duration(milliseconds: 10),
      );
      final run = task.run();
      await waitFor(
        () => task.segments.any((s) => s.downloaded > 0),
      );
      expect(task.segments.length, 2);
      expect(
        task.segments.fold(0, (sum, s) => sum + s.downloaded),
        task.downloadedBytes,
      );
      await run;
    });
  });
}
