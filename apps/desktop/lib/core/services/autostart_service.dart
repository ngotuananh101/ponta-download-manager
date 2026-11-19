import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final autostartServiceProvider = Provider<AutostartService>(
  (ref) => AutostartService(),
);

/// Current-user launch-at-login registration. Never invoked at plain startup.
class AutostartService {
  AutostartService({
    String? platform,
    bool? isRelease,
    String? executable,
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? runProcess,
  }) : _platform = platform ?? Platform.operatingSystem,
       _isRelease = isRelease ?? kReleaseMode,
       _executable = executable ?? Platform.resolvedExecutable,
       _environment = environment ?? Platform.environment,
       _runProcess = runProcess ?? ((command, args) => Process.run(command, args));

  final String _platform;
  final bool _isRelease;
  final String _executable;
  final Map<String, String> _environment;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  bool get canEnable => _isRelease && (_platform == 'linux' || _platform == 'windows');
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !canEnable) {
      throw StateError('Launch at startup requires a packaged Linux or Windows release');
    }
    if (_platform == 'linux') {
      final configured = _environment['XDG_CONFIG_HOME'];
      final home = _environment['HOME'];
      final root = configured != null && p.isAbsolute(configured)
          ? configured : home != null && p.isAbsolute(home) ? p.join(home, '.config') : null;
      if (root == null) throw StateError('Cannot resolve the user configuration folder');
      final file = File(p.join(root, 'autostart', 'com.ponta.pdm.desktop'));
      if (!enabled) {
        if (file.existsSync()) file.deleteSync();
        return;
      }
      final appImage = _environment['APPIMAGE'];
      final executable = appImage != null && p.isAbsolute(appImage)
          ? appImage : _executable;
      if (!p.isAbsolute(executable) || executable.contains('\n') || executable.contains('\r')) {
        throw StateError('Cannot register an invalid executable path');
      }
      // Desktop Entry Exec quoting is not shell quoting. Percent signs are
      // field-code escapes; backslashes must survive both parsing layers.
      final escaped = executable.replaceAll('\\', r'\\\\')
          .replaceAll('"', r'\\"').replaceAll('`', r'\\`')
          .replaceAll(r'$', r'\\$').replaceAll('%', '%%');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('[Desktop Entry]\nType=Application\n'
          'Name=Ponta Download Manager\nExec="$escaped"\n'
          'Terminal=false\nX-GNOME-Autostart-enabled=true\n', flush: true);
      return;
    }
    if (_platform == 'windows') {
      if (_executable.contains('"') || _executable.contains('\n') || _executable.contains('\r')) {
        throw StateError('Cannot register an invalid executable path');
      }
      final result = await _runProcess('reg.exe', enabled ? [
        'add', _runKey, '/v', 'PontaDownloadManager', '/t', 'REG_SZ',
        '/d', '"$_executable"', '/f',
      ] : ['delete', _runKey, '/v', 'PontaDownloadManager', '/f']);
      if (result.exitCode != 0) {
        throw StateError('Could not ${enabled ? 'enable' : 'disable'} launch at startup: '
            '${result.stderr} ${result.stdout}');
      }
      return;
    }
    throw StateError('Launch at startup is not supported on this platform');
  }
}
