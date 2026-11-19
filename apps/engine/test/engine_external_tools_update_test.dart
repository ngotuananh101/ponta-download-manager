import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_external/download_external.dart';
import 'package:pdm_engine/pdm_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late PdmEngine engine;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('engine-tools-');
    engine = PdmEngine.open(databasePath: '${temp.path}/engine.db',
      config: EngineConfig(downloadDirectory: temp.path),
      resolveExternalTools: () async => const ExternalTools(ffmpegPath: null, ytDlpPath: null));
  });
  tearDown(() async { await engine.dispose(); await temp.delete(recursive: true); });

  test('maintenance excludes new probes and playlist records but not native downloads', () async {
    final release = Completer<void>();
    final active = engine.withExternalToolsMaintenance((refresh) async {
      await release.future;
      await refresh();
    });
    expect(engine.isExternalToolsBusy, isTrue);
    await expectLater(engine.probeYtDlp('https://example.invalid/video'),
      throwsA(isA<DownloadError>().having((e) => e.code, 'code', 'external-tools-updating')));
    await expectLater(engine.createDownload(CreateDownloadRequest(
      url: 'https://example.invalid/live.m3u8', destination: '${temp.path}/video.mp4')),
      throwsA(isA<DownloadError>()));
    expect(await engine.listDownloads(), isEmpty);
    await engine.createDownload(CreateDownloadRequest(url: 'https://example.invalid/native',
      destination: '${temp.path}/native', paused: true));
    await expectLater(engine.withExternalToolsMaintenance((_) async {}), throwsStateError);
    release.complete();
    await active;
    expect(engine.isExternalToolsBusy, isFalse);
  });

  test('pending resolution prevents mutation and refresh retries missing tools', () async {
    await engine.dispose();
    final resolution = Completer<ExternalTools>();
    var count = 0;
    engine = PdmEngine.open(databasePath: '${temp.path}/other.db', resolveExternalTools: () {
      count++;
      return resolution.future;
    });
    final probe = engine.probeYtDlp('https://example.invalid/video');
    final failedProbe = expectLater(probe, throwsA(isA<DownloadError>()));
    expect(engine.isExternalToolsBusy, isTrue);
    var ran = false;
    await expectLater(engine.withExternalToolsMaintenance((_) async { ran = true; }), throwsStateError);
    expect(ran, isFalse);
    resolution.complete(const ExternalTools(ffmpegPath: null, ytDlpPath: null));
    await failedProbe;
    await engine.withExternalToolsMaintenance((refresh) => refresh());
    await expectLater(engine.probeYtDlp('https://example.invalid/video'), throwsA(isA<DownloadError>()));
    expect(count, 2);
    await expectLater(engine.withExternalToolsMaintenance((_) async => throw StateError('test')), throwsStateError);
    expect(engine.isExternalToolsBusy, isFalse);
  });
}
