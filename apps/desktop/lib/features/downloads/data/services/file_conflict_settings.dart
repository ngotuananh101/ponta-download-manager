import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

import 'package:pdm/core/app_data_dir.dart';

/// The remembered file-conflict choice and recently used save
/// directories, persisted as JSON (`{"fileConflictPolicy":
/// "overwrite"|"rename", "recentSaveDirectories": [...]}`) under the
/// app data dir. A missing, corrupt or unknown policy means "ask every
/// time"; missing directories mean none were picked yet. There is no
/// Settings screen yet, so clearing the choice means deleting the file.
class FileConflictSettings {
  FileConflictSettings({String? filePath})
    : _filePath = filePath ?? p.join(defaultAppDataDir(), 'settings.json');

  final String _filePath;

  FileConflictPolicy? load() {
    return switch (_readJson()['fileConflictPolicy']) {
      'overwrite' => FileConflictPolicy.overwrite,
      'rename' => FileConflictPolicy.rename,
      _ => null,
    };
  }

  /// Recently used save directories, most recent first. Empty when
  /// none were picked yet.
  List<String> loadRecentDirectories() {
    final list = _readJson()['recentSaveDirectories'];
    if (list is List) {
      return list.whereType<String>().toList();
    }
    return const [];
  }

  /// Synchronous: the write is one small JSON line, and an async
  /// save would never complete inside a widget test's FakeAsync zone.
  /// Saving one half keeps the other: the file always holds both keys.
  void save(FileConflictPolicy? policy) {
    _write({
      'fileConflictPolicy': policy?.name,
      'recentSaveDirectories': loadRecentDirectories(),
    });
  }

  /// Persists the recent save directories, most recent first.
  void saveRecentDirectories(List<String> directories) {
    _write({
      'fileConflictPolicy': load()?.name,
      'recentSaveDirectories': directories,
    });
  }

  Map<String, Object?> _readJson() {
    try {
      final json = jsonDecode(File(_filePath).readAsStringSync());
      if (json is Map<String, Object?>) return json;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  void _write(Map<String, Object?> json) {
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(json));
  }
}
