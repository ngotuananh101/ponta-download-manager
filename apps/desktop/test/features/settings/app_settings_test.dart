import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/settings/app_settings.dart';

void main() {
  late Directory temp;
  late File file;
  late FileConflictSettings store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pdm-settings-');
    file = File('${temp.path}/settings.json');
    store = FileConflictSettings(filePath: file.path);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('missing and corrupt settings resolve to safe defaults', () {
    for (final text in [null, 'broken', '[]', '{"maxConcurrentDownloads":0}']) {
      if (text != null) file.writeAsStringSync(text);
      final settings = store.loadSettings();
      expect(settings.downloadDirectory, isNull);
      expect(settings.maxConcurrentDownloads, 3);
      expect(settings.maxConnectionsPerDownload, 8);
      expect(settings.launchAtStartup, isFalse);
      expect(settings.windowAction, WindowAction.tray);
      expect(settings.startupState, StartupState.normal);
      expect(settings.deleteAction, DeleteAction.ask);
    }
  });

  test('legacy writes preserve new settings and unknown keys', () {
    file.writeAsStringSync(jsonEncode({
      'downloadDirectory': temp.path,
      'maxConcurrentDownloads': 5,
      'futureKey': 'keep',
    }));
    store.save(FileConflictPolicy.rename);
    store.saveRecentDirectories(['/one', '/two']);
    expect(store.loadSettings().maxConcurrentDownloads, 5);
    expect(store.loadSettings().downloadDirectory, temp.path);
    expect(jsonDecode(file.readAsStringSync())['futureKey'], 'keep');
  });

  test('all preferences export and import together with recent folders', () {
    final settings = AppSettings(
      downloadDirectory: temp.path,
      maxConcurrentDownloads: 6,
      maxConnectionsPerDownload: 12,
      fileConflictPolicy: FileConflictPolicy.overwrite,
      launchAtStartup: true,
      windowAction: WindowAction.quit,
      startupState: StartupState.tray,
      deleteAction: DeleteAction.deleteFile,
    );
    store.saveRecentDirectories(['/recent']);
    store.saveSettings(settings);
    final exported = store.exportJson();
    file.deleteSync();
    expect(store.importJson(exported), isTrue);
    expect(store.loadSettings().toJson(), settings.toJson());
    expect(store.loadRecentDirectories(), ['/recent']);
    expect(store.importJson('[]'), isFalse);
    expect(store.loadSettings().toJson(), settings.toJson());
  });

  test('invalid imported values are normalized without throwing', () {
    expect(store.importJson(jsonEncode({
      'downloadDirectory': 'relative',
      'maxConcurrentDownloads': 33,
      'maxConnectionsPerDownload': 1.5,
      'launchAtStartup': 'true',
      'windowAction': 'unknown',
      'startupState': 'unknown',
      'deleteAction': 'unknown',
      'recentSaveDirectories': ['/good', 7],
    })), isTrue);
    expect(store.loadSettings().maxConcurrentDownloads, 3);
    expect(store.loadSettings().maxConnectionsPerDownload, 8);
    expect(store.loadSettings().downloadDirectory, isNull);
    expect(store.loadSettings().launchAtStartup, isFalse);
    expect(store.loadSettings().deleteAction, DeleteAction.ask);
    expect(store.loadRecentDirectories(), ['/good']);
  });

  test('invalid saves are rejected before modifying the file', () {
    store.saveSettings(const AppSettings());
    final before = file.readAsStringSync();
    for (final settings in [
      const AppSettings(maxConcurrentDownloads: 0),
      const AppSettings(maxConnectionsPerDownload: 33),
      const AppSettings(downloadDirectory: 'relative'),
    ]) {
      expect(() => store.saveSettings(settings), throwsArgumentError);
      expect(file.readAsStringSync(), before);
    }
  });
}
