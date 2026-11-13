import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('IpcChannel codec', () {
    test('round-trips a request, a response and an event', () async {
      final (a, b) = createChannelPair();
      addTearDown(a.close);
      addTearDown(b.close);
      final received = collect(b.messages, 3);
      await a.send({
        'type': 'request',
        'v': 1,
        'id': 'req-1',
        'method': 'download.list',
        'params': <String, Object?>{},
      });
      await a.send({
        'type': 'response',
        'v': 1,
        'id': 'req-1',
        'result': {'ok': true},
      });
      await a.send({
        'type': 'event',
        'v': 1,
        'event': 'download.progress',
        'data': {'downloadId': 'dl-1', 'downloadedBytes': 10},
      });
      final messages = await received;
      expect(messages[0]['type'], 'request');
      expect(messages[0]['id'], 'req-1');
      expect(messages[1]['type'], 'response');
      expect(messages[2]['event'], 'download.progress');
    });

    test('decodes a line split across two chunks', () async {
      final sender = StreamController<List<int>>();
      final receiver = StreamController<List<int>>();
      final channel = IpcChannel(
        receiver.stream,
        sender.sink,
      );
      addTearDown(channel.close);
      final message = utf8.encode(
        jsonEncode({'type': 'event', 'v': 1, 'event': 'ping'}),
      );
      final firstHalf = message.sublist(0, 10);
      final secondHalf = [...message.sublist(10), 0x0A];
      final received = collect(channel.messages, 1);
      receiver.add(firstHalf);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      receiver.add(secondHalf);
      final messages = await received;
      expect(messages.single['event'], 'ping');
    });

    test('tolerates CRLF line endings', () async {
      final inbound = StreamController<List<int>>();
      final outbound = StreamController<List<int>>();
      final channel = IpcChannel(inbound.stream, outbound.sink);
      addTearDown(channel.close);
      final received = collect(channel.messages, 1);
      inbound.add(utf8.encode('{"type":"event","v":1,"event":"ping"}\r\n'));
      final messages = await received;
      expect(messages.single['event'], 'ping');
    });

    test('a malformed line yields an invalid-message error to the peer',
        () async {
      final aInbound = StreamController<List<int>>();
      final bInbound = StreamController<List<int>>();
      final aSide = IpcChannel(aInbound.stream, bInbound.sink);
      final bSide = IpcChannel(bInbound.stream, aInbound.sink);
      addTearDown(aSide.close);
      addTearDown(bSide.close);
      final errors = collect(aSide.messages, 1);
      bInbound.add(utf8.encode('this is not json\n'));
      final messages = await errors;
      expect(messages.single['type'], 'error');
      final error = messages.single['error'] as Map<String, Object?>;
      expect(error['code'], 'invalid-message');
    });

    test('a line over the cap closes the channel', () async {
      final inbound = StreamController<List<int>>();
      final outbound = StreamController<List<int>>();
      final channel = IpcChannel(
        inbound.stream,
        outbound.sink,
        maxLineBytes: 16,
      );
      addTearDown(channel.close);
      var closed = false;
      channel.messages.listen((_) {}, onDone: () => closed = true);
      inbound.add(Uint8List(32));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(closed, isTrue);
      expect(channel.isClosed, isTrue);
    });

    test('a single over-cap line with a newline closes the channel',
        () async {
      final inbound = StreamController<List<int>>();
      final outbound = StreamController<List<int>>();
      final channel = IpcChannel(
        inbound.stream,
        outbound.sink,
        maxLineBytes: 16,
      );
      addTearDown(channel.close);
      final received = <Map<String, Object?>>[];
      final written = <List<int>>[];
      var closed = false;
      channel.messages.listen(received.add, onDone: () => closed = true);
      outbound.stream.listen(written.add);
      // One chunk, 33 bytes + newline: the cap must apply even
      // though the chunk contains a newline.
      inbound.add(utf8.encode('{"type":"event","v":1,"event":"ping"}\n'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
      expect(closed, isTrue);
      expect(channel.isClosed, isTrue);
      final text = utf8.decode(written.expand((chunk) => chunk).toList());
      expect(text, contains('invalid-message'));
    });

    test('an over-cap line split across chunks closes the channel',
        () async {
      final inbound = StreamController<List<int>>();
      final outbound = StreamController<List<int>>();
      final channel = IpcChannel(
        inbound.stream,
        outbound.sink,
        maxLineBytes: 16,
      );
      addTearDown(channel.close);
      final received = <Map<String, Object?>>[];
      var closed = false;
      channel.messages.listen(received.add, onDone: () => closed = true);
      final line = utf8.encode('{"type":"event","v":1,"event":"ping"}');
      inbound.add(line.sublist(0, 10));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      inbound.add([...line.sublist(10), 0x0A]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
      expect(closed, isTrue);
      expect(channel.isClosed, isTrue);
    });

    test('send refuses a message over the cap', () async {
      final inbound = StreamController<List<int>>();
      final outbound = StreamController<List<int>>();
      final channel = IpcChannel(
        inbound.stream,
        outbound.sink,
        maxLineBytes: 16,
      );
      addTearDown(channel.close);
      final written = <List<int>>[];
      outbound.stream.listen(written.add);
      await expectLater(
        channel.send({'type': 'event', 'v': 1, 'event': 'ping'}),
        throwsArgumentError,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(written, isEmpty);
      expect(channel.isClosed, isFalse);
    });
  });

  group('IpcServer + IpcClient over an in-memory channel', () {
    late FakeEngine engine;
    late StreamController<IpcChannel> connections;
    late IpcServer server;

    setUp(() {
      engine = FakeEngine();
      connections = StreamController<IpcChannel>();
      server = IpcServer(
        engine: engine,
        connections: connections.stream,
        token: 'test-token',
      );
    });

    tearDown(() async {
      await server.close();
      await connections.close();
    });

    Future<IpcClient> connectClient({
      String token = 'test-token',
      Duration requestTimeout = IpcClient.defaultRequestTimeout,
    }) async {
      final (serverSide, clientSide) = createChannelPair();
      addTearDown(serverSide.close);
      addTearDown(clientSide.close);
      connections.add(serverSide);
      final client = await IpcClient.connect(
        channelFactory: () async => clientSide,
        token: token,
        requestTimeout: requestTimeout,
      );
      addTearDown(client.close);
      return client;
    }

    test('hello-ok then a sync snapshot, then create + events', () async {
      final client = await connectClient();
      final syncs = <List<DownloadInfo>>[];
      final syncSub = client.syncSnapshots.listen(syncs.add);
      addTearDown(syncSub.cancel);
      final events = <DownloadEvent>[];
      final eventSub = client.events.listen(events.add);
      addTearDown(eventSub.cancel);
      // The sync snapshot arrives right after hello.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(syncs, hasLength(1));
      expect(syncs.single, isEmpty);

      final info = await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      expect(info.id, 'dl-1');
      expect(info.url, 'http://127.0.0.1:9/f.bin');
      expect(engine.calls, contains('create:http://127.0.0.1:9/f.bin'));

      engine.emit(
        DownloadEvent.progress(
          downloadId: 'dl-1',
          downloadedBytes: 500,
          totalBytes: 1000,
          bytesPerSecond: 0,
        ),
      );
      engine.emit(
        DownloadEvent.completed(downloadId: 'dl-1', filePath: '/tmp/f.bin'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, hasLength(2));
      expect(
        events[0],
        isA<DownloadProgress>().having(
          (e) => e.downloadedBytes,
          'downloadedBytes',
          500,
        ),
      );
      expect(events[1], isA<DownloadCompleted>());
    });

    test('pause, resume, cancel, retry, priority and limits round-trip',
        () async {
      final client = await connectClient();
      final info = await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      await client.pauseDownload(info.id);
      await client.resumeDownload(info.id);
      await client.cancelDownload(info.id);
      await client.retryDownload(info.id);
      await client.setPriority(info.id, 5);
      await client.setGlobalBandwidthLimit(1024);
      await client.setDownloadBandwidthLimit(info.id, 512);
      await client.setGlobalBandwidthLimit(null);
      expect(engine.calls, [
        'create:http://127.0.0.1:9/f.bin',
        'pause:dl-1',
        'resume:dl-1',
        'cancel:dl-1',
        'retry:dl-1',
        'setPriority:dl-1:5',
        'setGlobal:1024',
        'setDownload:dl-1:512',
        'setGlobal:null',
      ]);
      final downloads = await client.listDownloads();
      expect(downloads.map((d) => d.id), ['dl-1']);
    });

    test('segments round-trip through the server and client', () async {
      final client = await connectClient();
      final info = await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      engine.segments[info.id] = [
        const DownloadSegment(segmentId: 0, start: 0, end: 499, downloaded: 500),
        const DownloadSegment(segmentId: 1, start: 500, end: 999, downloaded: 0),
      ];
      final segments = await client.getSegments(info.id);
      expect(segments.length, 2);
      expect(segments.first.segmentId, 0);
      expect(segments.first.end, 499);
      expect(segments.first.downloaded, 500);
      expect(segments.last.segmentId, 1);
      expect(segments.last.start, 500);
      expect(segments.last.downloaded, 0);
      expect(engine.calls, contains('segments:${info.id}'));
    });

    test('a second client gets the current downloads in its sync snapshot',
        () async {
      final first = await connectClient();
      await first.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      final second = await connectClient();
      final syncs = <List<DownloadInfo>>[];
      final sub = second.syncSnapshots.listen(syncs.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(syncs, hasLength(1));
      expect(syncs.single.map((d) => d.id), ['dl-1']);
    });

    test('an event emitted while the sync snapshot is pending arrives '
        'after the sync', () async {
      // A slow listDownloads keeps the sync snapshot pending after
      // hello-ok, so an engine event fired in that window would
      // overtake the snapshot without the fix.
      final slowEngine = _SlowListEngine();
      slowEngine.infos['dl-1'] = DownloadInfo(
        id: 'dl-1',
        url: 'http://127.0.0.1:9/f.bin',
        fileName: 'f.bin',
        status: DownloadStatus.queued,
        totalBytes: 1000,
      );
      final slowConnections = StreamController<IpcChannel>();
      final slowServer = IpcServer(
        engine: slowEngine,
        connections: slowConnections.stream,
        token: 'test-token',
      );
      addTearDown(slowServer.close);
      addTearDown(slowConnections.close);
      final (serverSide, clientSide) = createChannelPair();
      addTearDown(serverSide.close);
      addTearDown(clientSide.close);
      slowConnections.add(serverSide);
      final client = await IpcClient.connect(
        channelFactory: () async => clientSide,
        token: 'test-token',
      );
      addTearDown(client.close);
      final order = <String>[];
      final syncSub = client.syncSnapshots.listen((_) => order.add('sync'));
      addTearDown(syncSub.cancel);
      final eventSub = client.events.listen((_) => order.add('event'));
      addTearDown(eventSub.cancel);
      slowEngine.emit(
        DownloadEvent.progress(
          downloadId: 'dl-1',
          downloadedBytes: 500,
          totalBytes: 1000,
          bytesPerSecond: 0,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(order, ['sync', 'event']);
    });

    test('an unknown method fails with unknown-method', () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.nope', {}),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'unknown-method',
          ),
        ),
      );
    });

    test('create carries the conflict policy to the engine', () async {
      final client = await connectClient();
      await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
          conflictPolicy: FileConflictPolicy.rename,
        ),
      );
      expect(engine.createdPolicies, [FileConflictPolicy.rename]);
    });

    test('create with cookie and referrer round-trips them', () async {
      final client = await connectClient();
      await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
          cookie: 'session=abc',
          referrer: 'http://127.0.0.1:9/page',
        ),
      );
      expect(engine.createdRequests, hasLength(1));
      expect(engine.createdRequests.single.cookie, 'session=abc');
      expect(
        engine.createdRequests.single.referrer,
        'http://127.0.0.1:9/page',
      );
    });

    test('create with a non-string cookie fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.create', {
          'url': 'http://127.0.0.1:9/f.bin',
          'destination': '/tmp/f.bin',
          'cookie': 42,
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('create with a non-string referrer fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.create', {
          'url': 'http://127.0.0.1:9/f.bin',
          'destination': '/tmp/f.bin',
          'referrer': 42,
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });


    test('probe round-trips through the server and client', () async {
      final client = await connectClient();
      engine.probeResult = const YtDlpProbeResult(
        supported: true,
        title: 'Test video',
        thumbnail: 'https://example.com/thumb.jpg',
        durationSeconds: 123,
        formats: [
          YtDlpFormat(
            formatId: '18',
            ext: 'mp4',
            resolution: '640x360',
            width: 640,
            height: 360,
            filesize: 1000,
            vcodec: 'avc1',
            acodec: 'mp4a',
            fps: 30.0,
            note: '360p',
          ),
          YtDlpFormat(
            formatId: '140',
            ext: 'm4a',
            vcodec: 'none',
            acodec: 'mp4a',
          ),
        ],
      );
      final result = await client.probeYtDlp(
        url: 'https://example.com/watch?v=abc',
        cookie: 'session=abc',
        referrer: 'https://example.com/page',
      );
      expect(result.supported, isTrue);
      expect(result.title, 'Test video');
      expect(result.thumbnail, 'https://example.com/thumb.jpg');
      expect(result.durationSeconds, 123);
      expect(result.formats, hasLength(2));
      expect(result.formats[0].formatId, '18');
      expect(result.formats[0].resolution, '640x360');
      expect(result.formats[0].width, 640);
      expect(result.formats[0].filesize, 1000);
      expect(result.formats[0].fps, 30.0);
      expect(result.formats[0].note, '360p');
      expect(result.formats[1].formatId, '140');
      expect(result.formats[1].vcodec, 'none');
      expect(engine.probeCalls, hasLength(1));
      expect(engine.probeCalls.single.url, 'https://example.com/watch?v=abc');
      expect(engine.probeCalls.single.cookie, 'session=abc');
      expect(engine.probeCalls.single.referrer, 'https://example.com/page');
    });

    test('probe without a url fails with invalid-params', () async {
      final client = await connectClient();
      await expectLater(
        client.request('ytdlp.probe', {'cookie': 'session=abc'}),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('probe with a non-string cookie fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('ytdlp.probe', {
          'url': 'https://example.com/watch?v=abc',
          'cookie': 42,
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('probe with a non-string referrer fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('ytdlp.probe', {
          'url': 'https://example.com/watch?v=abc',
          'referrer': 42,
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('create carries ytDlpFormat to the engine', () async {
      final client = await connectClient();
      await client.createDownload(
        CreateDownloadRequest(
          url: 'https://example.com/watch?v=abc',
          destination: '/tmp/video.mp4',
          ytDlpFormat: '137+bestaudio',
        ),
      );
      expect(engine.createdRequests, hasLength(1));
      expect(engine.createdRequests.single.ytDlpFormat, '137+bestaudio');
    });

    test('create with a non-string ytDlpFormat fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.create', {
          'url': 'https://example.com/watch?v=abc',
          'destination': '/tmp/video.mp4',
          'ytDlpFormat': 137,
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('probe uses a longer timeout than the default request timeout',
        () async {
      expect(IpcClient.probeTimeout, const Duration(seconds: 60));
      expect(
        IpcClient.probeTimeout,
        greaterThan(IpcClient.defaultRequestTimeout),
      );
      // A client connected with a 50 ms default timeout still waits
      // out a slow probe: probeYtDlp overrides the per-request timeout.
      engine.probeDelay = const Duration(milliseconds: 300);
      final client = await connectClient(
        requestTimeout: const Duration(milliseconds: 50),
      );
      final result = await client.probeYtDlp(
        url: 'https://example.com/watch?v=abc',
      );
      expect(result.supported, isTrue);
    });

    test('create with an unknown conflict policy fails with invalid-params',
        () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.create', {
          'url': 'http://127.0.0.1:9/f.bin',
          'destination': '/tmp/f.bin',
          'conflictPolicy': 'explode',
        }),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('create without a url fails with invalid-params', () async {
      final client = await connectClient();
      await expectLater(
        client.request('download.create', {'destination': '/tmp/f.bin'}),
        throwsA(
          isA<DownloadError>().having(
            (e) => e.code,
            'code',
            'invalid-params',
          ),
        ),
      );
    });

    test('a wrong token is refused', () async {
      await expectLater(
        connectClient(token: 'wrong-token'),
        throwsA(isA<DownloadError>()),
      );
    });

    test('reconnect resyncs the current downloads', () async {
      Future<IpcChannel> Function() channelFactory() {
        return () async {
          final (serverSide, clientSide) = createChannelPair();
          addTearDown(serverSide.close);
          addTearDown(clientSide.close);
          connections.add(serverSide);
          return clientSide;
        };
      }

      final client = await IpcClient.connect(
        channelFactory: channelFactory(),
        token: 'test-token',
      );
      addTearDown(client.close);
      final info = await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      expect(info.id, 'dl-1');
      await client.reconnect();
      final syncs = <List<DownloadInfo>>[];
      final sub = client.syncSnapshots.listen(syncs.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The replay may still be the pre-reconnect snapshot; the fresh
      // one follows it, so the last snapshot is the one that matters.
      expect(syncs, isNotEmpty);
      expect(syncs.last.map((d) => d.id), ['dl-1']);
    });
  });

  group('download info protocol', () {
    test('round-trips the failure reason', () {
      const info = DownloadInfo(
        id: 'dl-1',
        url: 'https://example.com/f.bin',
        fileName: 'f.bin',
        status: DownloadStatus.failed,
        downloadedBytes: 0,
        totalBytes: 1000,
        errorCode: 'http-404',
        errorMessage: 'Not Found',
      );
      final decoded = downloadInfoFromJson(downloadInfoToJson(info));
      expect(decoded.errorCode, 'http-404');
      expect(decoded.errorMessage, 'Not Found');
    });

    test('decodes an older message without the failure fields as null', () {
      final decoded = downloadInfoFromJson({
        'id': 'dl-1',
        'url': 'https://example.com/f.bin',
        'fileName': 'f.bin',
        'status': 'failed',
        'downloadedBytes': 0,
        'totalBytes': 1000,
        'bytesPerSecond': 0,
        'priority': 0,
      });
      expect(decoded.errorCode, isNull);
      expect(decoded.errorMessage, isNull);
    });
  });

  group('yt-dlp probe protocol', () {
    test('round-trips a supported probe result', () {
      const result = YtDlpProbeResult(
        supported: true,
        title: 'Test video',
        thumbnail: 'https://example.com/thumb.jpg',
        durationSeconds: 123,
        formats: [
          YtDlpFormat(
            formatId: '18',
            ext: 'mp4',
            resolution: '640x360',
            width: 640,
            height: 360,
            filesize: 1000,
            filesizeApprox: 1100,
            vcodec: 'avc1',
            acodec: 'mp4a',
            fps: 30.0,
            note: '360p',
          ),
        ],
      );
      final decoded = ytDlpProbeResultFromJson(ytDlpProbeResultToJson(result));
      expect(decoded.supported, isTrue);
      expect(decoded.title, 'Test video');
      expect(decoded.thumbnail, 'https://example.com/thumb.jpg');
      expect(decoded.durationSeconds, 123);
      expect(decoded.formats, hasLength(1));
      expect(decoded.formats.single.formatId, '18');
      expect(decoded.formats.single.resolution, '640x360');
      expect(decoded.formats.single.filesize, 1000);
      expect(decoded.formats.single.filesizeApprox, 1100);
      expect(decoded.formats.single.fps, 30.0);
      expect(decoded.formats.single.note, '360p');
    });

    test('decodes a result without the optional fields', () {
      final decoded = ytDlpProbeResultFromJson({
        'supported': false,
        'errorCode': 'yt-dlp-unsupported',
        'errorMessage': 'Unsupported URL',
      });
      expect(decoded.supported, isFalse);
      expect(decoded.title, isNull);
      expect(decoded.formats, isEmpty);
      expect(decoded.errorCode, 'yt-dlp-unsupported');
      expect(decoded.errorMessage, 'Unsupported URL');
    });
  });
}

/// A [FakeEngine] whose listDownloads answers slowly, so the sync
/// snapshot is still pending after hello-ok.
class _SlowListEngine extends FakeEngine {
  @override
  Future<List<DownloadInfo>> listDownloads() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.listDownloads();
  }
}
