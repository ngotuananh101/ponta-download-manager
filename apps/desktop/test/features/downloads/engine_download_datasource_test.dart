import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm_engine/pdm_engine.dart';

class MockPdmEngine extends Mock implements PdmEngine {}

DownloadInfo info({
  String id = 'dl-1',
  DownloadStatus status = DownloadStatus.queued,
  int downloadedBytes = 0,
  int totalBytes = 1000,
  int bytesPerSecond = 0,
  String? filePath,
}) {
  return DownloadInfo(
    id: id,
    url: 'http://127.0.0.1:9/f.bin',
    fileName: 'f.bin',
    status: status,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    bytesPerSecond: bytesPerSecond,
    filePath: filePath,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      CreateDownloadRequest(
        url: 'http://127.0.0.1:9/f.bin',
        destination: '/tmp/f.bin',
      ),
    );
  });

  group('EngineDownloadDatasource', () {
    late MockPdmEngine engine;
    late StreamController<DownloadEvent> events;

    setUp(() {
      engine = MockPdmEngine();
      events = StreamController<DownloadEvent>();
      when(() => engine.events).thenAnswer((_) => events.stream);
      when(
        () => engine.listDownloads(),
      ).thenAnswer((_) async => const <DownloadInfo>[]);
      when(() => engine.dispose()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await events.close();
    });

    EngineDownloadDatasource datasource({
      Duration progressEmitInterval = const Duration(milliseconds: 100),
    }) {
      return EngineDownloadDatasource(
        engine: engine,
        downloadDirectory: '/tmp/downloads',
        progressEmitInterval: progressEmitInterval,
      );
    }

    test('the initial list comes from listDownloads', () async {
      when(
        () => engine.listDownloads(),
      ).thenAnswer((_) async => [info()]);
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last.single.id, 'dl-1');
      expect(emitted.last.single.fileName, 'f.bin');
      expect(emitted.last.single.state, DownloadState.queued);
    });

    test('progress events are throttled, state events emit at once', () {
      fakeAsync((async) {
        when(
          () => engine.listDownloads(),
        ).thenAnswer((_) async => [info()]);
        final source = datasource();
        final emitted = <List<Download>>[];
        final sub = source.watchDownloads().listen(emitted.add);
        async.flushMicrotasks();
        // Empty list at subscribe time, then the initial list.
        expect(emitted, hasLength(2));
        for (var i = 1; i <= 20; i++) {
          events.add(
            DownloadEvent.progress(
              downloadId: 'dl-1',
              downloadedBytes: i * 10,
              totalBytes: 1000,
              bytesPerSecond: 100,
            ),
          );
        }
        async.flushMicrotasks();
        expect(emitted, hasLength(2));
        async.elapse(const Duration(milliseconds: 100));
        expect(emitted, hasLength(3));
        expect(emitted.last.single.downloadedBytes, 200);
        expect(emitted.last.single.state, DownloadState.downloading);
        async.elapse(const Duration(milliseconds: 100));
        expect(emitted, hasLength(3));
        events.add(
          DownloadEvent.stateChanged(
            downloadId: 'dl-1',
            status: DownloadStatus.paused,
          ),
        );
        async.flushMicrotasks();
        expect(emitted, hasLength(4));
        expect(emitted.last.single.state, DownloadState.paused);
        sub.cancel();
        unawaited(source.dispose());
      });
    });

    test('a progress event after pause does not revive the download', () {
      fakeAsync((async) {
        when(
          () => engine.listDownloads(),
        ).thenAnswer(
          (_) async => [info(status: DownloadStatus.downloading)],
        );
        final source = datasource();
        final emitted = <List<Download>>[];
        final sub = source.watchDownloads().listen(emitted.add);
        async.flushMicrotasks();
        expect(emitted.last.single.state, DownloadState.downloading);
        // Pause: the state flips to paused at once.
        events.add(
          DownloadEvent.stateChanged(
            downloadId: 'dl-1',
            status: DownloadStatus.paused,
          ),
        );
        async.flushMicrotasks();
        expect(emitted.last.single.state, DownloadState.paused);
        // An in-flight chunk's progress arrives after the pause. The
        // bytes update, but the row must stay paused instead of
        // flicking back to "Downloading" with the old %.
        events.add(
          DownloadEvent.progress(
            downloadId: 'dl-1',
            downloadedBytes: 500,
            totalBytes: 1000,
            bytesPerSecond: 100,
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        expect(emitted.last.single.downloadedBytes, 500);
        expect(emitted.last.single.state, DownloadState.paused);
        sub.cancel();
        unawaited(source.dispose());
      });
    });

    test('a completed download whose file is gone loads as missing', () {
      fakeAsync((async) {
        final dir = Directory.systemTemp.createTempSync('pdm-missing-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final gone = '${dir.path}/gone.bin';
        when(() => engine.listDownloads()).thenAnswer(
          (_) async => [
            info(status: DownloadStatus.completed, filePath: gone),
          ],
        );
        final source = datasource();
        final emitted = <List<Download>>[];
        final sub = source.watchDownloads().listen(emitted.add);
        async.flushMicrotasks();
        expect(emitted.last.single.state, DownloadState.missing);
        // A stray progress event must not revive it to downloading.
        events.add(
          DownloadEvent.progress(
            downloadId: 'dl-1',
            downloadedBytes: 100,
            totalBytes: 100,
            bytesPerSecond: 100,
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));
        expect(emitted.last.single.state, DownloadState.missing);
        sub.cancel();
        unawaited(source.dispose());
      });
    });

    test('a failed event stores the error message, a retry clears it',
        () {
      fakeAsync((async) {
        when(
          () => engine.listDownloads(),
        ).thenAnswer(
          (_) async => [info(status: DownloadStatus.downloading)],
        );
        final source = datasource();
        final emitted = <List<Download>>[];
        final sub = source.watchDownloads().listen(emitted.add);
        async.flushMicrotasks();
        expect(emitted.last.single.errorMessage, isNull);
        events.add(
          DownloadEvent.failed(
            downloadId: 'dl-1',
            code: 'external-tools-missing',
            message:
                'ffmpeg and yt-dlp are required to download streams.',
          ),
        );
        async.flushMicrotasks();
        expect(emitted.last.single.state, DownloadState.failed);
        expect(
          emitted.last.single.errorMessage,
          'ffmpeg and yt-dlp are required to download streams.',
        );
        // Retry: the state flips back to queued, and the stale
        // reason must not linger on the row.
        events.add(
          DownloadEvent.stateChanged(
            downloadId: 'dl-1',
            status: DownloadStatus.queued,
          ),
        );
        async.flushMicrotasks();
        expect(emitted.last.single.state, DownloadState.queued);
        expect(emitted.last.single.errorMessage, isNull);
        sub.cancel();
        unawaited(source.dispose());
      });
    });

    test('addDownload joins the list from the create response', () async {
      when(
        () => engine.listDownloads(),
      ).thenAnswer((_) async => const <DownloadInfo>[]);
      when(
        () => engine.createDownload(any()),
      ).thenAnswer((_) async => info(status: DownloadStatus.downloading));
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      final created = await source.addDownload('http://127.0.0.1:9/f.bin');
      expect(created.id, 'dl-1');
      // The emission travels two async hops (engine event → the
      // datasource's broadcast controller → this subscriber), so give
      // it a turn before asserting on the list.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last.single.id, 'dl-1');
      expect(emitted.last.single.state, DownloadState.downloading);
      final request =
          verify(() => engine.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(request.destination, '/tmp/downloads/f.bin');
    });

    test('addDownload passes directory, file name and paused through',
        () async {
      when(
        () => engine.createDownload(any()),
      ).thenAnswer((_) async => info());
      final source = datasource();
      addTearDown(source.dispose);
      await source.addDownload(
        'http://127.0.0.1:9/f.bin',
        directory: '/tmp/other',
        fileName: 'g.bin',
        paused: true,
      );
      final request =
          verify(() => engine.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(request.destination, '/tmp/other/g.bin');
      expect(request.paused, isTrue);
    });

    test('probeUrl delegates to the engine', () async {
      const probe = ProbeResult(
        url: 'http://127.0.0.1:9/f.bin',
        fileName: 'f.bin',
        totalBytes: 1000,
      );
      when(() => engine.probeUrl(any())).thenAnswer((_) async => probe);
      final source = datasource();
      addTearDown(source.dispose);
      final got = await source.probeUrl('http://127.0.0.1:9/f.bin');
      expect(got.fileName, 'f.bin');
      expect(got.totalBytes, 1000);
      verify(() => engine.probeUrl('http://127.0.0.1:9/f.bin')).called(1);
    });

    test('pause/resume/cancel/retry delegate to the engine', () async {
      final source = datasource();
      addTearDown(source.dispose);
      when(() => engine.pauseDownload('dl-1')).thenAnswer((_) async {});
      when(() => engine.resumeDownload('dl-1')).thenAnswer((_) async {});
      when(() => engine.cancelDownload('dl-1')).thenAnswer((_) async {});
      when(() => engine.retryDownload('dl-1')).thenAnswer((_) async {});
      await source.pauseDownload('dl-1');
      await source.resumeDownload('dl-1');
      await source.cancelDownload('dl-1');
      await source.retryDownload('dl-1');
      verify(() => engine.pauseDownload('dl-1')).called(1);
      verify(() => engine.resumeDownload('dl-1')).called(1);
      verify(() => engine.cancelDownload('dl-1')).called(1);
      verify(() => engine.retryDownload('dl-1')).called(1);
    });

    test('deleteDownload forwards the deleteFile flag to the engine',
        () async {
      final source = datasource();
      addTearDown(source.dispose);
      when(
        () => engine.deleteDownload(
          any(),
          deleteFile: any(named: 'deleteFile'),
        ),
      ).thenAnswer((_) async {});
      await source.deleteDownload('dl-1', deleteFile: true);
      await source.deleteDownload('dl-1');
      verify(
        () => engine.deleteDownload('dl-1', deleteFile: true),
      ).called(1);
      verify(
        () => engine.deleteDownload('dl-1', deleteFile: false),
      ).called(1);
    });

    test('setGlobalBandwidthLimit forwards the limit to the engine',
        () async {
      final source = datasource();
      addTearDown(source.dispose);
      when(
        () => engine.setGlobalBandwidthLimit(any()),
      ).thenAnswer((_) async {});
      await source.setGlobalBandwidthLimit(8192);
      await source.setGlobalBandwidthLimit(null);
      verify(() => engine.setGlobalBandwidthLimit(8192)).called(1);
      verify(() => engine.setGlobalBandwidthLimit(null)).called(1);
    });

    test('a download created outside the UI appears when its events arrive',
        () async {
      // The list starts empty; the engine later creates a download
      // (e.g. via IPC from the browser extension) and emits a
      // stateChanged event for it. The datasource never called
      // addDownload, so the id is unknown until the refresh.
      var stored = <DownloadInfo>[];
      when(
        () => engine.listDownloads(),
      ).thenAnswer((_) async => stored);
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last, isEmpty);
      stored = [info(id: 'dl-2')];
      events.add(
        DownloadEvent.stateChanged(
          downloadId: 'dl-2',
          status: DownloadStatus.queued,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted.last.single.id, 'dl-2');
      expect(emitted.last.single.fileName, 'f.bin');
    });


    test('the initial list carries the priority', () async {
      when(() => engine.listDownloads()).thenAnswer(
        (_) async => [
          DownloadInfo(
            id: 'dl-1',
            url: 'http://127.0.0.1:9/f.bin',
            fileName: 'f.bin',
            status: DownloadStatus.queued,
            totalBytes: 1000,
            priority: 2,
          ),
        ],
      );
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted.last.single.priority, 2);
    });

    test('getSegments delegates to the engine', () async {
      const segments = [
        DownloadSegment(segmentId: 0, start: 0, end: 499, downloaded: 500),
        DownloadSegment(segmentId: 1, start: 500, end: 999, downloaded: 0),
      ];
      when(
        () => engine.getSegments('dl-1'),
      ).thenAnswer((_) async => segments);
      final source = datasource();
      addTearDown(source.dispose);
      final result = await source.getSegments('dl-1');
      expect(result, segments);
      verify(() => engine.getSegments('dl-1')).called(1);
    });

    test('dispose disposes the engine', () async {
      final source = datasource();
      await source.dispose();
      verify(() => engine.dispose()).called(1);
    });
  });
}
