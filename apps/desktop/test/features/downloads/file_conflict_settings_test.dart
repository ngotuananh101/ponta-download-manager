import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late FileConflictSettings settings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pdm-settings-test-');
    settings = FileConflictSettings(
      filePath: p.join(dir.path, 'settings.json'),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('load returns null and recent directories are empty when missing',
      () {
    expect(settings.load(), isNull);
    expect(settings.loadRecentDirectories(), isEmpty);
  });

  test('save and load round-trip the policy', () {
    settings.save(FileConflictPolicy.rename);
    expect(settings.load(), FileConflictPolicy.rename);
  });

  test('recent directories round-trip', () {
    settings.saveRecentDirectories(['/tmp/a', '/tmp/b']);
    expect(settings.loadRecentDirectories(), ['/tmp/a', '/tmp/b']);
  });

  test('saving the policy keeps the recent directories', () {
    settings.saveRecentDirectories(['/tmp/a']);
    settings.save(FileConflictPolicy.overwrite);
    expect(settings.load(), FileConflictPolicy.overwrite);
    expect(settings.loadRecentDirectories(), ['/tmp/a']);
  });

  test('saving recent directories keeps the policy', () {
    settings.save(FileConflictPolicy.rename);
    settings.saveRecentDirectories(['/tmp/a']);
    expect(settings.load(), FileConflictPolicy.rename);
    expect(settings.loadRecentDirectories(), ['/tmp/a']);
  });
}
