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
      );

      final bundled = await File('assets/images/icon.png').readAsBytes();
      expect(await installed.readAsBytes(), bundled);

      // A second run with identical bytes leaves the file untouched.
      final mtime = await installed.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await LinuxDesktopService.ensureDesktopIntegration(
        customXdgDataHome: tempDir,
      );
      expect(await installed.lastModified(), mtime);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
