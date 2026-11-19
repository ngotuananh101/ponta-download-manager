import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/autostart_service.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/features/settings/app_settings.dart';
import 'package:pdm/features/settings/settings_providers.dart';

void main() {
  test('saved and imported preferences publish only after persistence', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-prefs-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = FileConflictSettings(filePath: '${temp.path}/settings.json');
    final container = ProviderContainer.test(overrides: [
      fileConflictSettingsProvider.overrideWithValue(store),
    ]);
    await container.read(appSettingsProvider.notifier).save(
      const AppSettings(maxConcurrentDownloads: 7));
    expect(container.read(appSettingsProvider).maxConcurrentDownloads, 7);
    expect(store.loadSettings().maxConcurrentDownloads, 7);
    expect(await container.read(appSettingsProvider.notifier).importJson('[]'), isFalse);
    expect(container.read(appSettingsProvider).maxConcurrentDownloads, 7);
    expect(await container.read(appSettingsProvider.notifier).importJson(
      '{"maxConcurrentDownloads":4,"recentSaveDirectories":["/recent"]}'), isTrue);
    expect(container.read(appSettingsProvider).maxConcurrentDownloads, 4);
    expect(store.loadRecentDirectories(), ['/recent']);
  });

  test('failed registration never persists or publishes enabled preference', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-prefs-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final store = FileConflictSettings(filePath: '${temp.path}/settings.json');
    final container = ProviderContainer.test(overrides: [
      fileConflictSettingsProvider.overrideWithValue(store),
      autostartServiceProvider.overrideWithValue(AutostartService(
        platform: 'windows', isRelease: true,
        runProcess: (_, args) async => ProcessResult(1, 5, '', 'denied'),
      )),
    ]);
    await expectLater(container.read(appSettingsProvider.notifier).save(
      const AppSettings(launchAtStartup: true)), throwsStateError);
    expect(container.read(appSettingsProvider).launchAtStartup, isFalse);
    expect(store.loadSettings().launchAtStartup, isFalse);
  });

  test('failed persistence rolls back actual isolated autostart registration', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-prefs-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final blocked = '${temp.path}/blocked';
    Directory(blocked).createSync();
    final container = ProviderContainer.test(overrides: [
      fileConflictSettingsProvider.overrideWithValue(FileConflictSettings(filePath: blocked)),
      autostartServiceProvider.overrideWithValue(AutostartService(
        platform: 'linux', isRelease: true, executable: '/opt/pdm',
        environment: {'XDG_CONFIG_HOME': temp.path},
      )),
    ]);
    await expectLater(container.read(appSettingsProvider.notifier).save(
      const AppSettings(launchAtStartup: true)), throwsA(isA<FileSystemException>()));
    expect(File('${temp.path}/autostart/com.ponta.pdm.desktop').existsSync(), isFalse);
    expect(container.read(appSettingsProvider).launchAtStartup, isFalse);
  });
}
