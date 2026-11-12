import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:pdm_native_host/src/native_host.dart';
import 'package:pdm_native_host/src/native_message_codec.dart';
import 'package:test/test.dart';

/// A controllable stand-in for a real engine, on the server side of
/// an in-memory IPC channel pair.
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
  Future<void> pauseDownload(String downloadId) async {}

  @override
  Future<void> resumeDownload(String downloadId) async {}

  @override
  Future<void> cancelDownload(String downloadId) async {}

  @override
  Future<void> retryDownload(String downloadId) async {}

  @override
  Future<void> deleteDownload(
    String downloadId, {
    bool deleteFile = false,
  }) async {
    calls.add('delete:$downloadId');
    infos.remove(downloadId);
  }

  @override
  Future<void> deleteFile(String downloadId) async {}

  @override
  Future<void> renameFile(String downloadId, String newFileName) async {}

  @override
  Future<void> moveFile(String downloadId, String directory) async {}

  @override
  Future<void> changeUrl(String downloadId, String url) async {}

  @override
  Future<void> setPriority(String downloadId, int priority) async {}

  @override
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {}

  @override
  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {}

  @override
  Future<List<DownloadSegment>> getSegments(String downloadId) async => [];

  @override
  Future<ProbeResult> probeUrl(String url) async =>
      ProbeResult(url: url, fileName: 'f.bin', totalBytes: 1000);
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
  test('one framed download.create reaches a real engine over IPC', () async {
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

    final host = NativeHost(
      clientFactory: clientFactory,
      downloadDirectory: '/tmp/dl',
    );
    final input = StreamController<List<int>>();
    final output = StreamController<List<int>>();
    final replies = <Map<String, Object?>>[];
    final replySub = NativeMessageCodec.decode(
      output.stream,
    ).listen(replies.add);
    final run = host.run(input.stream, output.sink);
    input.add(
      NativeMessageCodec.encode({
        'type': 'download.create',
        'id': 'r1',
        'url': 'http://127.0.0.1:9/f.bin',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await input.close();
    await run;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await replySub.cancel();
    await output.close();

    expect(engine.calls, ['create:http://127.0.0.1:9/f.bin']);
    expect(replies, hasLength(1));
    expect(replies.single['id'], 'r1');
    expect(replies.single['ok'], isTrue);
    expect(replies.single['downloadId'], 'dl-1');
  });
}
