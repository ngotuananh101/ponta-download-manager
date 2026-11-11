import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/app/engine_ipc_host.dart';

/// A controllable stand-in for a real engine.
class FakeEngine implements DownloadEngine {
  final _events = StreamController<DownloadEvent>.broadcast();
  final infos = <String, DownloadInfo>{};
  final calls = <String>[];
  var _counter = 0;

  @override
  Stream<DownloadEvent> get events => _events.stream;

  @override
  Future<DownloadInfo> createDownload(CreateDownloadRequest request) async {
    calls.add('create:${request.url}');
    final id = 'dl-${++_counter}';
    final info = DownloadInfo(
      id: id,
      url: request.url,
      fileName: request.destination.split('/').last,
      status: DownloadStatus.queued,
      totalBytes: 1000,
    );
    infos[id] = info;
    return info;
  }

  @override
  Future<List<DownloadInfo>> listDownloads() async => infos.values.toList();

  @override
  Future<void> pauseDownload(String downloadId) async {
    calls.add('pause:$downloadId');
  }

  @override
  Future<void> resumeDownload(String downloadId) async {
    calls.add('resume:$downloadId');
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    calls.add('cancel:$downloadId');
  }

  @override
  Future<void> retryDownload(String downloadId) async {
    calls.add('retry:$downloadId');
  }

  @override
  Future<void> deleteDownload(String downloadId) async {
    calls.add('delete:$downloadId');
    infos.remove(downloadId);
  }

  @override
  Future<void> setPriority(String downloadId, int priority) async {}

  @override
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {}

  @override
  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {}
}

void main() {
  test('the app-hosted IPC server answers a real client', () async {
    final temp = await Directory.systemTemp.createTemp('pdm-ipc-host-');
    addTearDown(() => temp.delete(recursive: true));
    final socketPath = '${temp.path}/engine.sock';
    final engine = FakeEngine();

    final host = await EngineIpcHost.start(
      engine: engine,
      socketPath: socketPath,
    );
    addTearDown(host.close);

    // The token file exists next to the socket, and the socket is bound.
    final tokenFile = File('$socketPath.token');
    expect(await tokenFile.exists(), isTrue);
    expect(await File(socketPath).exists(), isTrue);
    final token = await tokenFile.readAsString();
    expect(token, isNotEmpty);

    final client = await IpcClient.connect(
      channelFactory: () => UnixSocketTransport(socketPath: socketPath).connect(),
      token: token,
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
    expect((await client.listDownloads()).single.id, 'dl-1');
  });

  test('close removes the socket and the token file', () async {
    final temp = await Directory.systemTemp.createTemp('pdm-ipc-host-');
    addTearDown(() => temp.delete(recursive: true));
    final socketPath = '${temp.path}/nested/engine.sock';
    final host = await EngineIpcHost.start(
      engine: FakeEngine(),
      socketPath: socketPath,
    );
    // The token write creates the socket's parent dir (the regression
    // from the extension part: serve crashed on a first run when the
    // dir did not exist yet).
    expect(await File('$socketPath.token').exists(), isTrue);
    await host.close();
    expect(await File(socketPath).exists(), isFalse);
    expect(await File('$socketPath.token').exists(), isFalse);
  });
}
