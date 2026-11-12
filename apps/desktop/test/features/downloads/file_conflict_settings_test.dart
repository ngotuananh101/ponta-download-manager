import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';

void main() {
  group('FileConflictSettings export/import', () {
    late Directory tempDir;
    late String settingsPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      settingsPath = '${tempDir.path}/settings.json';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('exportJson round-trips the policy and recent directories', () {
      File(settingsPath).writeAsStringSync(
        jsonEncode({
          'fileConflictPolicy': 'rename',
          'recentSaveDirectories': ['/tmp/a', '/tmp/b'],
        }),
      );
      final settings = FileConflictSettings(filePath: settingsPath);
      final decoded = jsonDecode(settings.exportJson())
          as Map<String, Object?>;
      expect(decoded['fileConflictPolicy'], 'rename');
      expect(decoded['recentSaveDirectories'], ['/tmp/a', '/tmp/b']);
    });

    test('exportJson with no settings file exports empty values', () {
      final settings = FileConflictSettings(filePath: settingsPath);
      final decoded = jsonDecode(settings.exportJson())
          as Map<String, Object?>;
      expect(decoded['fileConflictPolicy'], isNull);
      expect(decoded['recentSaveDirectories'], isEmpty);
    });

    test('importJson persists the policy and recent directories', () {
      final settings = FileConflictSettings(filePath: settingsPath);
      expect(
        settings.importJson(
          jsonEncode({
            'fileConflictPolicy': 'overwrite',
            'recentSaveDirectories': ['/tmp/x'],
          }),
        ),
        isTrue,
      );
      expect(settings.load(), FileConflictPolicy.overwrite);
      expect(settings.loadRecentDirectories(), ['/tmp/x']);
    });

    test('importJson drops an unknown policy value but keeps the rest',
        () {
      final settings = FileConflictSettings(filePath: settingsPath);
      expect(
        settings.importJson(
          jsonEncode({
            'fileConflictPolicy': 'bogus',
            'recentSaveDirectories': ['/tmp/x'],
          }),
        ),
        isTrue,
      );
      expect(settings.load(), isNull);
      expect(settings.loadRecentDirectories(), ['/tmp/x']);
    });

    test('importJson rejects text that is not a JSON object', () {
      final settings = FileConflictSettings(filePath: settingsPath);
      expect(settings.importJson('not json at all'), isFalse);
      expect(settings.importJson('[1, 2]'), isFalse);
      expect(File(settingsPath).existsSync(), isFalse);
    });
  });
}
