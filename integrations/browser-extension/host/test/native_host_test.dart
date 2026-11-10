import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:pdm_native_host/src/native_host.dart';
import 'package:pdm_native_host/src/native_message_codec.dart';

class MockIpcClient extends Mock implements IpcClient {}

DownloadInfo info({String id = 'dl-1'}) {
  return DownloadInfo(
    id: id,
    url: 'http://127.0.0.1:9/f.bin',
    fileName: 'f.bin',
    status: DownloadStatus.queued,
    totalBytes: 1000,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      CreateDownloadRequest(
        url: 'http://127.0.0.1:9/f.bin',
        destination: '/tmp/dl/f.bin',
      ),
    );
  });

  group('NativeHost', () {
    late MockIpcClient client;

    setUp(() {
      client = MockIpcClient();
      when(() => client.close()).thenAnswer((_) async {});
    });

    Future<List<Map<String, Object?>>> runWith(
      NativeHost host,
      List<Map<String, Object?>> messages,
    ) async {
      final input = StreamController<List<int>>();
      final output = StreamController<List<int>>();
      final replies = <Map<String, Object?>>[];
      final replySub = NativeMessageCodec.decode(
        output.stream,
      ).listen(replies.add);
      final run = host.run(input.stream, output.sink);
      for (final message in messages) {
        input.add(NativeMessageCodec.encode(message));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await input.close();
      await run;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await replySub.cancel();
      await output.close();
      return replies;
    }

    NativeHost host({Future<IpcClient> Function()? factory}) {
      return NativeHost(
        clientFactory: factory ?? () async => client,
        downloadDirectory: '/tmp/dl',
      );
    }

    test('a valid download.create calls createDownload and replies ok',
        () async {
      when(
        () => client.createDownload(any()),
      ).thenAnswer((_) async => info());
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
        },
      ]);
      expect(replies, hasLength(1));
      expect(replies.single['id'], 'r1');
      expect(replies.single['ok'], isTrue);
      expect(replies.single['downloadId'], 'dl-1');
      final captured =
          verify(() => client.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(captured.url, 'http://127.0.0.1:9/f.bin');
      expect(captured.destination, '/tmp/dl/f.bin');
    });

    test('an unknown type is rejected and never calls the client', () async {
      final replies = await runWith(host(), [
        {'type': 'download.list', 'id': 'r1'},
      ]);
      expect(replies, hasLength(1));
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-message');
      verifyNever(() => client.createDownload(any()));
    });

    test('a non-http url is rejected', () async {
      final replies = await runWith(host(), [
        {'type': 'download.create', 'id': 'r1', 'url': 'ftp://example.com/f'},
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(() => client.createDownload(any()));
    });

    test('a file name with a separator is rejected', () async {
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
          'fileName': '../escape.bin',
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(() => client.createDownload(any()));
    });

    test('a connection-closed failure is retried once and then succeeds',
        () async {
      var calls = 0;
      when(() => client.createDownload(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw const DownloadError('connection-closed', 'down');
        }
        return info();
      });
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
        },
      ]);
      expect(replies.single['ok'], isTrue);
      verify(() => client.createDownload(any())).called(2);
    });

    test('a client that always fails replies with the engine code',
        () async {
      when(() => client.createDownload(any())).thenThrow(
        const DownloadError('connection-closed', 'no engine'),
      );
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'connection-closed');
      verify(() => client.createDownload(any())).called(2);
    });

    test('stdin EOF ends the loop and closes the client', () async {
      when(
        () => client.createDownload(any()),
      ).thenAnswer((_) async => info());
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
        },
      ]);
      expect(replies.single['ok'], isTrue);
      verify(() => client.close()).called(1);
    });
  });
}
