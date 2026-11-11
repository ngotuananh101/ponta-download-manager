import 'dart:io';

import 'package:path/path.dart' as p;

/// The per-user app data directory (`<data>/pdm`): the remembered
/// file-conflict choice lives here, next to the thumbnail cache.
/// Windows: `%LOCALAPPDATA%\pdm`, else `~/.local/share/pdm`
/// (`$XDG_DATA_HOME/pdm` when set).
String defaultAppDataDir() {
  if (Platform.isWindows) {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        p.join(
          Platform.environment['USERPROFILE'] ?? '.',
          'AppData',
          'Local',
        );
    return p.join(base, 'pdm');
  }
  final xdg = Platform.environment['XDG_DATA_HOME'];
  final base =
      xdg ?? p.join(Platform.environment['HOME'] ?? '.', '.local', 'share');
  return p.join(base, 'pdm');
}
