import 'dart:async';
import 'dart:io';

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

YtDlpProbeResult probeResult() {
  return const YtDlpProbeResult(
    supported: true,
    title: 'Test video',
    thumbnail: 'https://example.com/thumb.jpg',
    durationSeconds: 120,
    formats: [
      YtDlpFormat(
        formatId: '18',
        ext: 'mp4',
        resolution: '640x360',
        width: 640,
        height: 360,
        vcodec: 'avc1',
        acodec: 'mp4a',
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
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
      expect(captured.conflictPolicy, FileConflictPolicy.rename);
    });

    test('download.create with cookie and referrer forwards them',
        () async {
      when(
        () => client.createDownload(any()),
      ).thenAnswer((_) async => info());
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
          'cookie': 'session=abc',
          'referrer': 'http://127.0.0.1:9/page',
        },
      ]);
      expect(replies.single['ok'], isTrue);
      final captured =
          verify(() => client.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(captured.cookie, 'session=abc');
      expect(captured.referrer, 'http://127.0.0.1:9/page');
    });

    test('a non-string cookie is rejected and never calls the client',
        () async {
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
          'cookie': 42,
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(() => client.createDownload(any()));
    });

    test('a non-string referrer is rejected and never calls the client',
        () async {
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
          'referrer': 42,
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(() => client.createDownload(any()));
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

    test('a factory failure that is not a DownloadError still replies '
        'with an error', () async {
      final failing = NativeHost(
        clientFactory: () async {
          throw const FileSystemException('token file missing');
        },
        downloadDirectory: '/tmp/dl',
      );
      final replies = await runWith(failing, [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'http://127.0.0.1:9/f.bin',
        },
      ]);
      expect(replies, hasLength(1));
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'internal');
    });

    test('ytdlp.probe forwards url, cookie and referrer and replies '
        'with the probe JSON', () async {
      when(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      ).thenAnswer((_) async => probeResult());
      final replies = await runWith(host(), [
        {
          'type': 'ytdlp.probe',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
          'cookie': 'session=abc',
          'referrer': 'https://example.com/page',
        },
      ]);
      expect(replies, hasLength(1));
      expect(replies.single['id'], 'r1');
      expect(replies.single['ok'], isTrue);
      final probe = replies.single['probe'] as Map<String, Object?>;
      expect(probe['supported'], isTrue);
      expect(probe['title'], 'Test video');
      final formats = probe['formats'] as List;
      expect(formats, hasLength(1));
      expect((formats.single as Map)['formatId'], '18');
      verify(
        () => client.probeYtDlp(
          url: 'https://example.com/watch?v=1',
          cookie: 'session=abc',
          referrer: 'https://example.com/page',
        ),
      ).called(1);
    });

    test('a ytdlp.probe error replies with the engine code', () async {
      when(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      ).thenThrow(
        const DownloadError('yt-dlp-unsupported', 'no extractor'),
      );
      final replies = await runWith(host(), [
        {
          'type': 'ytdlp.probe',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'yt-dlp-unsupported');
      verify(
        () => client.probeYtDlp(
          url: 'https://example.com/watch?v=1',
          cookie: null,
          referrer: null,
        ),
      ).called(1);
    });

    test('a non-string cookie on ytdlp.probe is rejected and never calls '
        'the client', () async {
      final replies = await runWith(host(), [
        {
          'type': 'ytdlp.probe',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
          'cookie': 42,
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      );
    });

    test('a non-string referrer on ytdlp.probe is rejected and never '
        'calls the client', () async {
      final replies = await runWith(host(), [
        {
          'type': 'ytdlp.probe',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
          'referrer': 42,
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      );
    });

    test('a missing url on ytdlp.probe is rejected', () async {
      final replies = await runWith(host(), [
        {'type': 'ytdlp.probe', 'id': 'r1'},
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      );
    });

    test('a non-http url on ytdlp.probe is rejected', () async {
      final replies = await runWith(host(), [
        {
          'type': 'ytdlp.probe',
          'id': 'r1',
          'url': 'ftp://example.com/watch?v=1',
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(
        () => client.probeYtDlp(
          url: any(named: 'url'),
          cookie: any(named: 'cookie'),
          referrer: any(named: 'referrer'),
        ),
      );
    });

    test('download.create with ytDlpFormat forwards it', () async {
      when(
        () => client.createDownload(any()),
      ).thenAnswer((_) async => info());
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
          'fileName': 'video.mp4',
          'ytDlpFormat': '137+bestaudio',
        },
      ]);
      expect(replies.single['ok'], isTrue);
      final captured =
          verify(() => client.createDownload(captureAny())).captured.single
              as CreateDownloadRequest;
      expect(captured.ytDlpFormat, '137+bestaudio');
    });

    test('a non-string ytDlpFormat is rejected and never calls the client',
        () async {
      final replies = await runWith(host(), [
        {
          'type': 'download.create',
          'id': 'r1',
          'url': 'https://example.com/watch?v=1',
          'ytDlpFormat': 42,
        },
      ]);
      expect(replies.single['ok'], isFalse);
      expect(replies.single['code'], 'invalid-params');
      verifyNever(() => client.createDownload(any()));
    });
  });
}
