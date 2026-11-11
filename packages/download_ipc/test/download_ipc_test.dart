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

    Future<IpcClient> connectClient({String token = 'test-token'}) async {
      final (serverSide, clientSide) = createChannelPair();
      addTearDown(serverSide.close);
      addTearDown(clientSide.close);
      connections.add(serverSide);
      final client = await IpcClient.connect(
        channelFactory: () async => clientSide,
        token: token,
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
      expect(syncs, hasLength(1));
      expect(syncs.single.map((d) => d.id), ['dl-1']);
    });
  });
}
