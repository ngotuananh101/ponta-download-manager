import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_recovery/download_recovery.dart';
import 'package:pdm_engine/pdm_engine.dart';
import 'package:test/test.dart';

void main() {
  test('live defaults affect new downloads but retain existing records', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-config-');
    final database = '${temp.path}/engine.db';
    final engine = PdmEngine.open(databasePath: database,
      config: EngineConfig(downloadDirectory: '${temp.path}/old'));
    addTearDown(() async {
      await engine.dispose();
      temp.deleteSync(recursive: true);
    });
    final old = await engine.createDownload(const CreateDownloadRequest(
      url: 'https://example.invalid/old', destination: 'old.bin', paused: true));
    engine.updateConfig(EngineConfig(downloadDirectory: '${temp.path}/new',
      maxConcurrentDownloads: 5, maxConnectionsPerDownload: 12));
    final next = await engine.createDownload(const CreateDownloadRequest(
      url: 'https://example.invalid/new', destination: 'new.bin', paused: true));
    final store = DownloadStore.open(database);
    addTearDown(store.close);
    expect(store.getDownload(old.id)!.directory, '${temp.path}/old');
    expect(store.getDownload(old.id)!.maxConnections, 8);
    expect(store.getDownload(next.id)!.directory, '${temp.path}/new');
    expect(store.getDownload(next.id)!.maxConnections, 12);
    expect(engine.config.maxConcurrentDownloads, 5);
  });

  test('invalid updates cannot partially mutate configuration', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-config-');
    final engine = PdmEngine.open(databasePath: '${temp.path}/engine.db');
    addTearDown(() async { await engine.dispose(); temp.deleteSync(recursive: true); });
    expect(() => engine.updateConfig(const EngineConfig(maxConcurrentDownloads: 0)),
      throwsArgumentError);
    expect(() => engine.updateConfig(const EngineConfig(maxConnectionsPerDownload: 0)),
      throwsArgumentError);
    expect(engine.config.maxConcurrentDownloads, 3);
    expect(engine.config.maxConnectionsPerDownload, 8);
  });
}
