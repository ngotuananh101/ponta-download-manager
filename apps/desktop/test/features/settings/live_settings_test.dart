import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/features/settings/app_settings.dart';
import 'package:pdm/features/settings/settings_providers.dart';
import 'package:pdm_engine/pdm_engine.dart';

void main() {
  test('settings update existing datasource and engine instead of reopening them', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-live-prefs-');
    final store = FileConflictSettings(filePath: '${temp.path}/settings.json');
    final container = ProviderContainer(overrides: [
      fileConflictSettingsProvider.overrideWithValue(store),
      downloadDirectoryResolverProvider.overrideWithValue(() => '${temp.path}/os'),
      engineFactoryProvider.overrideWithValue((config) => PdmEngine.open(
        config: config, databasePath: '${temp.path}/engine.db')),
    ]);
    final datasource = container.read(downloadDatasourceProvider);
    try {
      expect(datasource.engine.config.downloadDirectory, '${temp.path}/os');
      await container.read(appSettingsProvider.notifier).save(AppSettings(
        downloadDirectory: '${temp.path}/custom',
        maxConcurrentDownloads: 6, maxConnectionsPerDownload: 16));
      expect(identical(container.read(downloadDatasourceProvider), datasource), isTrue);
      expect(container.read(downloadDirectoryProvider), '${temp.path}/custom');
      expect(datasource.downloadDirectory, '${temp.path}/custom');
      expect(datasource.engine.config.maxConcurrentDownloads, 6);
      expect(datasource.engine.config.maxConnectionsPerDownload, 16);
    } finally {
      await datasource.dispose();
      container.dispose();
      temp.deleteSync(recursive: true);
    }
  });
}
