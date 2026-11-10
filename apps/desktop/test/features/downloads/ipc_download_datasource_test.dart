import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/features/downloads/data/datasources/ipc_download_datasource.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

class MockIpcClient extends Mock implements IpcClient {}

DownloadInfo info({
  String id = 'dl-1',
  DownloadStatus status = DownloadStatus.queued,
  int downloadedBytes = 0,
  int totalBytes = 1000,
  int bytesPerSecond = 0,
}) {
  return DownloadInfo(
    id: id,
    url: 'http://127.0.0.1:9/f.bin',
    fileName: 'f.bin',
    status: status,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    bytesPerSecond: bytesPerSecond,
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

  group('IpcDownloadDatasource', () {
    late MockIpcClient client;
    late StreamController<DownloadEvent> events;

    setUp(() {
      client = MockIpcClient();
      events = StreamController<DownloadEvent>();
      when(() => client.events).thenAnswer((_) => events.stream);
      when(() => client.close()).thenAnswer((_) async {});
    });

    tearDown(() async {
      await events.close();
    });

    IpcDownloadDatasource datasource({
      Duration progressEmitInterval = const Duration(milliseconds: 100),
      Duration reconnectInterval = const Duration(seconds: 5),
      Future<IpcClient> Function()? factory,
    }) {
      return IpcDownloadDatasource(
        clientFactory: factory ?? () async => client,
        downloadDirectory: '/tmp/downloads',
        progressEmitInterval: progressEmitInterval,
        reconnectInterval: reconnectInterval,
      );
    }

    test('a sync snapshot maps to the downloads list', () async {
      when(
        () => client.syncSnapshots,
      ).thenAnswer((_) => Stream.value([info()]));
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      await source.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The first emission is the empty list at subscribe time.
      expect(emitted, hasLength(2));
      expect(emitted.last.single.id, 'dl-1');
      expect(emitted.last.single.fileName, 'f.bin');
      expect(emitted.last.single.state, DownloadState.queued);
    });

    test('progress events are throttled, state events emit at once', () {
      fakeAsync((async) {
        when(
          () => client.syncSnapshots,
        ).thenAnswer((_) => Stream.value([info()]));
        final source = datasource();
        final emitted = <List<Download>>[];
        final sub = source.watchDownloads().listen(emitted.add);
        unawaited(source.connect());
        async.flushMicrotasks();
        // Empty list at subscribe time, then the sync snapshot.
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
        unawaited(sub.cancel());
        unawaited(source.dispose());
        async.flushMicrotasks();
      });
    });

    test('addDownload calls createDownload with the joined destination',
        () async {
      when(
        () => client.syncSnapshots,
      ).thenAnswer((_) => const Stream<List<DownloadInfo>>.empty());
      when(
        () => client.createDownload(any()),
      ).thenAnswer((_) async => info());
      final source = datasource();
      addTearDown(source.dispose);
      await source.connect();
      final created = await source.addDownload('http://127.0.0.1:9/f.bin');
      expect(created.id, 'dl-1');
      final captured =
          verify(() => client.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(captured.url, 'http://127.0.0.1:9/f.bin');
      expect(captured.destination, '/tmp/downloads/f.bin');
    });

    test('pause, resume, cancel and retry delegate to the client', () async {
      when(
        () => client.syncSnapshots,
      ).thenAnswer((_) => const Stream<List<DownloadInfo>>.empty());
      when(() => client.pauseDownload(any())).thenAnswer((_) async {});
      when(() => client.resumeDownload(any())).thenAnswer((_) async {});
      when(() => client.cancelDownload(any())).thenAnswer((_) async {});
      when(() => client.retryDownload(any())).thenAnswer((_) async {});
      final source = datasource();
      addTearDown(source.dispose);
      await source.connect();
      await source.pauseDownload('dl-1');
      await source.resumeDownload('dl-1');
      await source.cancelDownload('dl-1');
      await source.retryDownload('dl-1');
      verify(() => client.pauseDownload('dl-1')).called(1);
      verify(() => client.resumeDownload('dl-1')).called(1);
      verify(() => client.cancelDownload('dl-1')).called(1);
      verify(() => client.retryDownload('dl-1')).called(1);
    });

    test('a failed connect emits disconnected and retries', () {
      fakeAsync((async) {
        when(
          () => client.syncSnapshots,
        ).thenAnswer((_) => const Stream<List<DownloadInfo>>.empty());
        var attempts = 0;
        final source = datasource(
          factory: () async {
            attempts++;
            if (attempts == 1) {
              throw const DownloadError('connection-closed', 'no engine');
            }
            return client;
          },
        );
        final connected = <bool>[];
        final sub = source.watchConnected().listen(connected.add);
        unawaited(source.connect());
        async.flushMicrotasks();
        expect(connected, [false]);
        expect(attempts, 1);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(attempts, 2);
        expect(connected, [false, true]);
        unawaited(sub.cancel());
        unawaited(source.dispose());
        async.flushMicrotasks();
      });
    });

    test('events for unknown ids are ignored', () async {
      when(
        () => client.syncSnapshots,
      ).thenAnswer((_) => Stream.value(const <DownloadInfo>[]));
      final source = datasource();
      addTearDown(source.dispose);
      final emitted = <List<Download>>[];
      final sub = source.watchDownloads().listen(emitted.add);
      addTearDown(sub.cancel);
      await source.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Empty list at subscribe time, then the empty sync snapshot.
      expect(emitted, hasLength(2));
      expect(emitted.last, isEmpty);
      events.add(
        DownloadEvent.progress(
          downloadId: 'dl-9',
          downloadedBytes: 10,
          totalBytes: 100,
          bytesPerSecond: 0,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(emitted, hasLength(2));
    });
  });
}
