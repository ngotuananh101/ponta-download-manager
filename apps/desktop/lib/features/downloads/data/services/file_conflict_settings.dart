import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

import 'package:pdm/core/app_data_dir.dart';

/// The remembered file-conflict choice, persisted as JSON
/// (`{"fileConflictPolicy": "overwrite"|"rename"}`) under the app data
/// dir. A missing, corrupt or unknown value means "ask every time".
/// There is no Settings screen yet, so clearing the choice means
/// deleting the file.
class FileConflictSettings {
  FileConflictSettings({String? filePath})
    : _filePath = filePath ?? p.join(defaultAppDataDir(), 'settings.json');

  final String _filePath;

  FileConflictPolicy? load() {
    try {
      final json = jsonDecode(File(_filePath).readAsStringSync());
      return switch (json['fileConflictPolicy']) {
        'overwrite' => FileConflictPolicy.overwrite,
        'rename' => FileConflictPolicy.rename,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// Synchronous: the write is one small JSON line, and an async
  /// save would never complete inside a widget test's FakeAsync zone.
  void save(FileConflictPolicy? policy) {
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({'fileConflictPolicy': policy?.name}),
    );
  }
}
