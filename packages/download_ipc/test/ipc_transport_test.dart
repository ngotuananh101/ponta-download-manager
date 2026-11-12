import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('createIpcServerTransport', () {
    test('picks a Unix socket on POSIX', () {
      final transport = createIpcServerTransport(
        socketPath: '/tmp/engine.sock',
        isWindows: false,
      );
      expect(transport, isA<UnixSocketTransport>());
    });

    test('picks loopback TCP on Windows', () {
      final transport = createIpcServerTransport(
        socketPath: r'C:\Users\anhnt\AppData\Local\pdm\engine.sock',
        isWindows: true,
      );
      expect(transport, isA<LoopbackTcpTransport>());
    });
  });

  group('connectIpcChannel', () {
    test('a TCP server and client round-trip through the port file',
        () async {
      final temp = await Directory.systemTemp.createTemp('pdm-ipc-tcp-');
      addTearDown(() => temp.delete(recursive: true));
      final socketPath = '${temp.path}/engine.sock';
      final engine = FakeEngine();
      final transport = createIpcServerTransport(
        socketPath: socketPath,
        isWindows: true,
      );
      final server = IpcServer(
        engine: engine,
        connections: await transport.listen(),
        token: 'tok',
      );
      // TearDowns run in reverse registration order: the server closes
      // before the transport.
      addTearDown(transport.close);
      addTearDown(server.close);
      final tcp = transport as LoopbackTcpTransport;
      await File(
        portFilePath(socketPath),
      ).writeAsString('${tcp.boundPort}');

      final client = await IpcClient.connect(
        channelFactory: () => connectIpcChannel(
          socketPath: socketPath,
          isWindows: true,
        ),
        token: 'tok',
      );
      addTearDown(client.close);

      final info = await client.createDownload(
        CreateDownloadRequest(
          url: 'http://127.0.0.1:9/f.bin',
          destination: '/tmp/f.bin',
        ),
      );
      expect(info.id, 'dl-1');
      expect(engine.calls, ['create:http://127.0.0.1:9/f.bin']);
    });

    test('throws a clear error on Windows when no port file exists',
        () async {
      final temp = await Directory.systemTemp.createTemp('pdm-ipc-tcp-');
      addTearDown(() => temp.delete(recursive: true));
      await expectLater(
        connectIpcChannel(
          socketPath: '${temp.path}/engine.sock',
          isWindows: true,
        ),
        throwsStateError,
      );
    });
  });
}
