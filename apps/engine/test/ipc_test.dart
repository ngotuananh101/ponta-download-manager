import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:pdm_engine/pdm_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<int> bytesOf(int length, [int seed = 0]) =>
    List<int>.generate(length, (i) => (i + seed) % 256);

void main() {
  group(
    'PdmEngine over IPC',
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'Unix domain sockets only'
        : null,
    () {
      test('a client creates a download over IPC and the file lands exact',
          () async {
        final data = bytesOf(65536);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final response = request.response;
          response.headers.set('Accept-Ranges', 'bytes');
          response.headers.contentType = ContentType.binary;
          if (request.method == 'HEAD') {
            response.headers.contentLength = data.length;
            await response.close();
            return;
          }
          final range = request.headers.value('range');
          var start = 0;
          var end = data.length - 1;
          if (range != null) {
            final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
            if (match != null) {
              start = int.parse(match.group(1)!);
              end = match.group(2)!.isEmpty
                  ? data.length - 1
                  : int.parse(match.group(2)!);
              response.statusCode = HttpStatus.partialContent;
              response.headers.set(
                'Content-Range',
                'bytes $start-$end/${data.length}',
              );
            }
          }
          response.headers.contentLength = end - start + 1;
          response.add(data.sublist(start, end + 1));
          await response.close();
        });
        addTearDown(server.close);

        final tempDir = await Directory.systemTemp.createTemp(
          'pdm-engine-ipc-test-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final socketPath = p.join(tempDir.path, 'engine.sock');
        final engine = PdmEngine.open(
          config: EngineConfig(
            downloadDirectory: tempDir.path,
            maxConnectionsPerDownload: 2,
          ),
          databasePath: p.join(tempDir.path, 'pdm.db'),
        );
        addTearDown(engine.dispose);
        final transport = UnixSocketTransport(socketPath: socketPath);
        final ipcServer = IpcServer(
          engine: engine,
          connections: await transport.listen(),
          token: 'ipc-test-token',
        );
        addTearDown(ipcServer.close);
        addTearDown(transport.close);

        final client = await IpcClient.connect(
          channelFactory: () =>
              UnixSocketTransport(socketPath: socketPath).connect(),
          token: 'ipc-test-token',
        );
        addTearDown(client.close);
        final completed = Completer<void>();
        final sub = client.events.listen((event) {
          event.when(
            progress: (id, downloaded, total, speed) {},
            stateChanged: (id, status) {},
            completed: (id, filePath) {
              if (!completed.isCompleted) {
                completed.complete();
              }
            },
            failed: (id, code, message) {
              if (!completed.isCompleted) {
                completed.completeError('$code $message');
              }
            },
          );
        });
        addTearDown(sub.cancel);

        final info = await client.createDownload(
          CreateDownloadRequest(
            url: 'http://127.0.0.1:${server.port}/f.bin',
            destination: p.join(tempDir.path, 'f.bin'),
          ),
        );
        await completed.future.timeout(const Duration(seconds: 15));
        expect(
          await File(p.join(tempDir.path, 'f.bin')).readAsBytes(),
          data,
        );
        final downloads = await client.listDownloads();
        expect(downloads.single.id, info.id);
        expect(downloads.single.status, DownloadStatus.completed);
      });
    },
  );
}
