// RED test: broadcasting to a client that went away must not raise
// an unhandled error, and the server must keep serving other clients.
// Reproduces the broken-pipe log: a short-lived IPC client (the
// native host) connects, gets its reply, then destroys its socket
// abruptly while unread broadcast bytes are pending (RST), and the
// engine keeps emitting events.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group(
    'IpcServer broadcast to a dead client',
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'Unix domain sockets only'
        : null,
    () {
      test('no unhandled error, server keeps working', () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'pdm-ipc-dead-client-',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final socketPath = p.join(tempDir.path, 'engine.sock');
        final engine = FakeEngine();
        final transport = UnixSocketTransport(socketPath: socketPath);
        final connections = await transport.listen();
        final server = IpcServer(
          engine: engine,
          connections: connections,
          token: 'test-token',
        );
        addTearDown(server.close);
        addTearDown(transport.close);

        // A raw client: hello handshake, then one create request.
        final raw = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        );
        final lines = <String>[];
        final sub = raw
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(lines.add);
        addTearDown(sub.cancel);
        raw.add(
          utf8.encode(
            '${jsonEncode({'type': 'hello', 'v': 1, 'token': 'test-token'})}\n',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        raw.add(
          utf8.encode(
            '${jsonEncode({
              'type': 'request',
              'v': 1,
              'id': 'req-1',
              'method': 'download.create',
              'params': {
                'url': 'http://127.0.0.1:9/f.bin',
                'destination': '/tmp/f.bin',
              },
            })}\n',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        // The client got its reply; now it goes away abruptly with
        // unread broadcast bytes pending (the native host exiting).
        raw.destroy();
        // Emit a burst synchronously, before the server's read side
        // has delivered EOF: the broadcast races the disconnect and
        // must not raise an unhandled error.
        for (var i = 0; i < 50; i++) {
          engine.emit(
            DownloadEvent.progress(
              downloadId: 'dl-1',
              downloadedBytes: i * 10,
              totalBytes: 1000,
              bytesPerSecond: 0,
            ),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // The server still serves a fresh client.
        final client2 = await IpcClient.connect(
          channelFactory: () =>
              UnixSocketTransport(socketPath: socketPath).connect(),
          token: 'test-token',
        );
        addTearDown(client2.close);
        final downloads = await client2.listDownloads();
        expect(downloads.map((d) => d.id), ['dl-1']);
      });
    },
  );
}
