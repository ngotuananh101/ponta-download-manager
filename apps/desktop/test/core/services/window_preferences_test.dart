import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/autostart_service.dart';
import 'package:pdm/core/services/window_preferences.dart';
import 'package:pdm/features/settings/app_settings.dart';

void main() {
  test('Linux registration uses stable AppImage and removes only own entry', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-autostart-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final other = File('${temp.path}/autostart/other.desktop');
    other.parent.createSync(recursive: true);
    other.writeAsStringSync('untouched');
    final service = AutostartService(
      platform: 'linux', isRelease: true,
      executable: '/tmp/mount/pdm',
      environment: {'XDG_CONFIG_HOME': temp.path, 'APPIMAGE': '/opt/My PDM 50%.AppImage'},
    );
    await service.setEnabled(true);
    final file = File('${temp.path}/autostart/com.ponta.pdm.desktop');
    expect(file.readAsStringSync(), contains('Exec="/opt/My PDM 50%%.AppImage"'));
    expect(file.readAsStringSync(), isNot(contains('/tmp/mount')));
    await service.setEnabled(false);
    expect(file.existsSync(), isFalse);
    expect(other.readAsStringSync(), 'untouched');
  });

  test('Windows uses current-user Run with one quoted executable argument', () async {
    final calls = <List<String>>[];
    final service = AutostartService(
      platform: 'windows', isRelease: true,
      executable: r'C:\My Apps\pdm.exe', environment: const {},
      runProcess: (command, args) async {
        expect(command, 'reg.exe');
        calls.add(args);
        return ProcessResult(1, 0, '', '');
      },
    );
    await service.setEnabled(true);
    expect(calls.single, [
      'add', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v', 'PontaDownloadManager', '/t', 'REG_SZ', '/d',
      r'"C:\My Apps\pdm.exe"', '/f',
    ]);
    await service.setEnabled(false);
    expect(calls.last.take(4), [
      'delete', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v', 'PontaDownloadManager',
    ]);
  });

  test('development enabling and failed registration report errors', () async {
    final development = AutostartService(platform: 'linux', isRelease: false);
    await expectLater(development.setEnabled(true), throwsStateError);
    final failing = AutostartService(
      platform: 'windows', isRelease: true, executable: r'C:\pdm.exe',
      runProcess: (_, args) async => ProcessResult(1, 5, '', 'Access denied'),
    );
    await expectLater(failing.setEnabled(true), throwsStateError);
  });

  test('startup visibility applies exactly one native action', () {
    final actions = <String>[];
    applyStartupVisibility(hidden: true, hide: () => actions.add('hide'),
      show: () => actions.add('show'), focus: () => actions.add('focus'));
    applyStartupVisibility(hidden: false, hide: () => actions.add('hide'),
      show: () => actions.add('show'), focus: () => actions.add('focus'));
    expect(actions, ['hide', 'show', 'focus']);
  });

  test('Linux Exec escaping survives desktop-entry and command parsing', () async {
    final temp = Directory.systemTemp.createTempSync('pdm-autostart-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final service = AutostartService(platform: 'linux', isRelease: true,
      executable: '/opt/pdm "quoted" \$cash `tick` \\ path',
      environment: {'XDG_CONFIG_HOME': temp.path});
    await service.setEnabled(true);
    expect(File('${temp.path}/autostart/com.ponta.pdm.desktop').readAsStringSync(),
      contains(r'Exec="/opt/pdm \\"quoted\\" \\$cash \\`tick\\` \\\\ path"'));
  });

  test('startup tray respects CLI but falls back to visible without tray', () {
    expect(shouldStartHidden(const AppSettings(), ['--minimized'], true), isTrue);
    expect(shouldStartHidden(const AppSettings(startupState: StartupState.tray), [], true), isTrue);
    expect(shouldStartHidden(const AppSettings(startupState: StartupState.tray), [], false), isFalse);
    expect(shouldStartHidden(const AppSettings(), [], true), isFalse);
  });

  test('window policy performs hide or graceful quit and has no-tray fallback', () async {
    final actions = <String>[];
    Future<void> apply(WindowAction action, bool tray, bool close) => applyWindowAction(
      action: action, trayAvailable: tray, closing: close,
      hide: () => actions.add('hide'),
      minimize: () => actions.add('minimize'),
      quit: () async { actions.add('quit'); },
    );
    await apply(WindowAction.tray, true, false);
    await apply(WindowAction.quit, true, false);
    await apply(WindowAction.tray, false, false);
    await apply(WindowAction.tray, false, true);
    expect(actions, ['hide', 'quit', 'minimize', 'quit']);
  });
}
