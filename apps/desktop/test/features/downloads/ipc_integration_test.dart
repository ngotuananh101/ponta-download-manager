import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/datasources/ipc_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

/// A controllable stand-in for a real engine, on the server side of
/// an in-memory IPC channel pair.
class FakeEngine implements DownloadEngine {
  final _events = StreamController<DownloadEvent>.broadcast();
  final infos = <String, DownloadInfo>{};
  final calls = <String>[];
  var _counter = 0;

  void emit(DownloadEvent event) => _events.add(event);

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
  Future<void> setPriority(String downloadId, int priority) async {}

  @override
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {}

  @override
  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {}
}

(IpcChannel, IpcChannel) channelPair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  return (
    IpcChannel(bToA.stream, aToB.sink),
    IpcChannel(aToB.stream, bToA.sink),
  );
}

void main() {
  test('repository drives a real server over IPC and sees its events',
      () async {
    final engine = FakeEngine();
    final connections = StreamController<IpcChannel>();
    final server = IpcServer(
      engine: engine,
      connections: connections.stream,
      token: 'test-token',
    );
    addTearDown(server.close);
    addTearDown(connections.close);

    Future<IpcClient> clientFactory() async {
      final (serverSide, clientSide) = channelPair();
      addTearDown(serverSide.close);
      addTearDown(clientSide.close);
      connections.add(serverSide);
      return IpcClient.connect(
        channelFactory: () async => clientSide,
        token: 'test-token',
      );
    }

    final datasource = IpcDownloadDatasource(
      clientFactory: clientFactory,
      downloadDirectory: '/tmp/downloads',
      progressEmitInterval: const Duration(milliseconds: 10),
    );
    addTearDown(datasource.dispose);
    final repository = DownloadRepositoryImpl(datasource);

    final emitted = <List<Download>>[];
    final sub = repository.watchDownloads().listen(emitted.add);
    addTearDown(sub.cancel);
    await datasource.connect();

    final result = await repository.addDownload('http://127.0.0.1:9/f.bin');
    expect(result.isRight(), isTrue);
    expect(engine.calls, ['create:http://127.0.0.1:9/f.bin']);

    engine.emit(
      DownloadEvent.progress(
        downloadId: 'dl-1',
        downloadedBytes: 500,
        totalBytes: 1000,
        bytesPerSecond: 250,
      ),
    );
    engine.emit(
      DownloadEvent.completed(downloadId: 'dl-1', filePath: '/tmp/f.bin'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emitted.last.single.id, 'dl-1');
    expect(emitted.last.single.state, DownloadState.completed);
    expect(emitted.last.single.downloadedBytes, 500);
    expect(emitted.last.single.bytesPerSecond, 250);

    expect((await repository.pauseDownload('dl-1')).isRight(), isTrue);
    expect(engine.calls, contains('pause:dl-1'));
  });
}
