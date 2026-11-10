import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'IpcServer + IpcClient over a real Unix socket',
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'Unix domain sockets only'
        : null,
    () {
      test('create/list/events round-trip, wrong token refused', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'pdm-ipc-socket-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final socketPath = p.join(tempDir.path, 'engine.sock');
        final engine = FakeEngine();
        final transport = UnixSocketTransport(socketPath: socketPath);
        final connections = await transport.listen();
        final server = IpcServer(
          engine: engine,
          connections: connections,
          token: 'sock-token',
        );
        addTearDown(server.close);
        addTearDown(transport.close);

        final client = await IpcClient.connect(
          channelFactory: () =>
              UnixSocketTransport(socketPath: socketPath).connect(),
          token: 'sock-token',
        );
        addTearDown(client.close);
        final events = <DownloadEvent>[];
        final sub = client.events.listen(events.add);
        addTearDown(sub.cancel);

        final info = await client.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:9/f.bin',
            destination: '/tmp/f.bin',
          ),
        );
        expect(info.id, 'dl-1');
        engine.emit(
          DownloadEvent.progress(
            downloadId: 'dl-1',
            downloadedBytes: 10,
            totalBytes: 1000,
            bytesPerSecond: 0,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(events, hasLength(1));
        expect(
          events.single,
          isA<DownloadProgress>().having(
            (e) => e.downloadedBytes,
            'downloadedBytes',
            10,
          ),
        );
        final downloads = await client.listDownloads();
        expect(downloads.map((d) => d.id), ['dl-1']);

        await expectLater(
          IpcClient.connect(
            channelFactory: () =>
                UnixSocketTransport(socketPath: socketPath).connect(),
            token: 'bad-token',
          ),
          throwsA(isA<DownloadError>()),
        );

        await server.close();
        await transport.close();
        expect(await File(socketPath).exists(), isFalse);
      });
    },
  );
}
