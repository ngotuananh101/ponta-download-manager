import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/core/app_data_dir.dart';
import 'package:pdm/features/settings/app_settings.dart';

/// Shared JSON preference storage. Legacy conflict/recent-folder writes
/// preserve every other preference, including keys from future versions.
class FileConflictSettings {
  FileConflictSettings({String? filePath})
    : _filePath = filePath ?? p.join(defaultAppDataDir(), 'settings.json');

  final String _filePath;

  AppSettings loadSettings() => AppSettings.fromJson(_readJson());
  FileConflictPolicy? load() => loadSettings().fileConflictPolicy;

  List<String> loadRecentDirectories() {
    final list = _readJson()['recentSaveDirectories'];
    return list is List ? list.whereType<String>().toList() : const [];
  }

  /// Synchronous small writes also work in widget tests' FakeAsync zone.
  void save(FileConflictPolicy? policy) => _write({
    ..._readJson(),
    'fileConflictPolicy': policy?.name,
  });

  void saveRecentDirectories(List<String> directories) => _write({
    ..._readJson(),
    'recentSaveDirectories': directories,
  });

  void saveSettings(AppSettings settings, {List<String>? recentDirectories}) {
    settings.validate();
    _write({
      ..._readJson(),
      ...settings.toJson(),
      'recentSaveDirectories': recentDirectories ?? loadRecentDirectories(),
    });
  }

  String exportJson() => jsonEncode({
    ...loadSettings().toJson(),
    'recentSaveDirectories': loadRecentDirectories(),
  });

  static Map<String, Object?>? decodeSettings(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Storage-only compatibility API. The UI uses the settings notifier to
  /// apply runtime/OS changes as well as persisting imported preferences.
  bool importJson(String text) {
    final json = decodeSettings(text);
    if (json == null) return false;
    final directories = json['recentSaveDirectories'];
    saveSettings(AppSettings.fromJson(json), recentDirectories:
      directories is List ? directories.whereType<String>().toList() : const []);
    return true;
  }

  Map<String, Object?> _readJson() {
    try {
      return decodeSettings(File(_filePath).readAsStringSync()) ?? const {};
    } catch (_) {
      return const {};
    }
  }

  void _write(Map<String, Object?> json) {
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    // Write beside the destination then rename: a failed write cannot leave
    // a half-serialized preference file behind.
    final temporary = File('$_filePath.tmp');
    try {
      temporary.writeAsStringSync(jsonEncode(json), flush: true);
      temporary.renameSync(_filePath);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }
}
