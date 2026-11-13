import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/linux_desktop_service.dart';

void main() {
  test('re-installs the icon when the bundled icon changed', () async {
    final tempDir = await Directory.systemTemp.createTemp('pdm-icon-');
    try {
      final iconsDir =
          Directory('${tempDir.path}/icons/hicolor/256x256/apps')
            ..createSync(recursive: true);
      final installed = File(
        '${iconsDir.path}/${LinuxDesktopService.appId}.png',
      );
      // A stale icon from an earlier install.
      await installed.writeAsBytes([1, 2, 3]);

      await LinuxDesktopService.ensureDesktopIntegration(
        customXdgDataHome: tempDir,
        isReleaseBuild: true,
      );

      final bundled = await File('assets/images/icon.png').readAsBytes();
      expect(await installed.readAsBytes(), bundled);

      // A second run with identical bytes leaves the file untouched.
      final mtime = await installed.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await LinuxDesktopService.ensureDesktopIntegration(
        customXdgDataHome: tempDir,
        isReleaseBuild: true,
      );
      expect(await installed.lastModified(), mtime);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes nothing in a debug or test build', () async {
    // `flutter test` and `flutter run` are both debug builds, so the
    // real default (kReleaseMode) is exercised here: a dev run must
    // not register a .desktop entry pointing into build/.
    final tempDir = await Directory.systemTemp.createTemp('pdm-icon-');
    try {
      await LinuxDesktopService.ensureDesktopIntegration(
        customXdgDataHome: tempDir,
      );

      expect(
        Directory('${tempDir.path}/applications').existsSync(),
        isFalse,
        reason: 'no .desktop entry may be written outside release builds',
      );
      expect(
        Directory('${tempDir.path}/icons').existsSync(),
        isFalse,
        reason: 'no icon may be installed outside release builds',
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
