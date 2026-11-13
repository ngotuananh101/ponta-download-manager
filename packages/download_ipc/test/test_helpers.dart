import 'dart:async';

import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';

/// Two channels wired to each other in memory: what one sends, the
/// other receives. No socket involved.
(IpcChannel, IpcChannel) createChannelPair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  final a = IpcChannel(bToA.stream, aToB.sink);
  final b = IpcChannel(aToB.stream, bToA.sink);
  return (a, b);
}

/// A controllable stand-in for a real engine.
class FakeEngine implements DownloadEngine {
  final _events = StreamController<DownloadEvent>.broadcast();
  final infos = <String, DownloadInfo>{};
  final calls = <String>[];

  /// The conflict policy of every createDownload call, in order.
  final createdPolicies = <FileConflictPolicy?>[];

  /// Every createDownload request, in order.
  final createdRequests = <CreateDownloadRequest>[];
  var _counter = 0;

  /// Events the test pushes into the engine's stream.
  void emit(DownloadEvent event) => _events.add(event);

  @override
  Stream<DownloadEvent> get events => _events.stream;

  @override
  Future<DownloadInfo> createDownload(CreateDownloadRequest request) async {
    calls.add('create:${request.url}');
    createdPolicies.add(request.conflictPolicy);
    createdRequests.add(request);
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
    _setStatus(downloadId, DownloadStatus.paused);
  }

  @override
  Future<void> resumeDownload(String downloadId) async {
    calls.add('resume:$downloadId');
    _setStatus(downloadId, DownloadStatus.queued);
  }

  @override
  Future<void> cancelDownload(String downloadId) async {
    calls.add('cancel:$downloadId');
    _setStatus(downloadId, DownloadStatus.cancelled);
  }

  @override
  Future<void> retryDownload(String downloadId) async {
    calls.add('retry:$downloadId');
  }

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
  Future<void> addMirror(String downloadId, String url) async {}
  @override
  Future<void> addTag(String downloadId, String tag) async {}
  @override
  Future<void> removeTag(String downloadId, String tag) async {}

  @override
  Future<UpdateCheckResult> checkForUpdate(String downloadId) async =>
      const UpdateCheckResult(
        hasUpdate: false,
        inconclusive: false,
        newTotalBytes: 0,
      );

  @override
  Future<IntegrityResult> verifyFile(String downloadId) async =>
      const IntegrityResult.ok(bytes: 0);

  @override
  Future<void> setPriority(String downloadId, int priority) async {
    calls.add('setPriority:$downloadId:$priority');
  }

  @override
  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond) async {
    calls.add('setGlobal:$bytesPerSecond');
  }

  @override
  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  ) async {
    calls.add('setDownload:$downloadId:$bytesPerSecond');
  }

  /// Segments returned by getSegments, keyed by download id.
  final segments = <String, List<DownloadSegment>>{};

  @override
  Future<List<DownloadSegment>> getSegments(String downloadId) async {
    calls.add('segments:$downloadId');
    return segments[downloadId] ?? [];
  }

  @override
  Future<ProbeResult> probeUrl(String url) async =>
      ProbeResult(url: url, fileName: 'f.bin', totalBytes: 1000);

  void _setStatus(String id, DownloadStatus status) {
    final info = infos[id];
    if (info != null) {
      infos[id] = info.copyWith(status: status);
    }
  }
}

Future<List<Map<String, Object?>>> collect(
  Stream<Map<String, Object?>> stream,
  int count, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final received = <Map<String, Object?>>[];
  final done = Completer<List<Map<String, Object?>>>();
  final sub = stream.listen((message) {
    received.add(message);
    if (received.length >= count && !done.isCompleted) {
      done.complete(received);
    }
  });
  try {
    return await done.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}
