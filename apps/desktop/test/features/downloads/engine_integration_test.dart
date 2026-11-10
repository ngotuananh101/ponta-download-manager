import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm_engine/pdm_engine.dart';
import 'package:path/path.dart' as p;

List<int> bytesOf(int length, [int seed = 0]) =>
    List<int>.generate(length, (i) => (i + seed) % 256);

Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A small range-capable HTTP server, enough for the engine's probe +
/// segmented download.
class TestServer {
  TestServer(this.data);

  final List<int> data;
  late HttpServer _server;

  int get port => _server.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> close() async => _server.close();

  Future<void> _handle(HttpRequest request) async {
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
  }
}

void main() {
  test('a real engine in-process drives the repository end to end', () async {
    final temp = await Directory.systemTemp.createTemp('pdm-engine-integ-');
    addTearDown(() => temp.delete(recursive: true));
    final data = bytesOf(65536);
    final server = TestServer(data);
    await server.start();
    addTearDown(server.close);

    final engine = PdmEngine.open(
      databasePath: p.join(temp.path, 'pdm.db'),
    );
    final datasource = EngineDownloadDatasource(
      engine: engine,
      downloadDirectory: temp.path,
      progressEmitInterval: const Duration(milliseconds: 10),
    );
    addTearDown(datasource.dispose);
    final repository = DownloadRepositoryImpl(datasource);

    final emitted = <List<Download>>[];
    final sub = repository.watchDownloads().listen(emitted.add);
    addTearDown(sub.cancel);

    final url = 'http://127.0.0.1:${server.port}/f.bin';
    final result = await repository.addDownload(url);
    expect(result.isRight(), isTrue);
    final created = result.getOrElse((_) => throw StateError('no download'));
    expect(created.fileName, 'f.bin');

    await waitFor(
      () =>
          emitted.isNotEmpty &&
          emitted.last.isNotEmpty &&
          emitted.last.single.state == DownloadState.completed,
    );
    final file = File(p.join(temp.path, 'f.bin'));
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), data);
  });
}
