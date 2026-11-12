import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Linux desktop integration: installs the .desktop file and the
/// hicolor icon into the user's XDG data directory so GNOME Shell
/// (Wayland/X11) can resolve the app_id to the application name and
/// icon on the top bar, dash/dock, app switcher — and the tray.
///
/// Ported from dev-stack's LinuxDesktopService, adapted to PDM.
class LinuxDesktopService {
  static const String appId = 'com.ponta.pdm';
  static const String appName = 'Ponta Download Manager';
  static const String appComment =
      'Download manager with segmented downloads';

  static final _log = Logger('LinuxDesktopService');

  static String? _cachedIconPath;

  /// Returns the cached absolute icon path if available.
  static String? get cachedIconPath => _cachedIconPath;

  /// Resolves the best absolute path to icon.png for the window
  /// icon or the tray icon.
  static String resolveIconPath() {
    if (_cachedIconPath != null && File(_cachedIconPath!).existsSync()) {
      return _cachedIconPath!;
    }

    final dataHome = _resolveXdgDataHome();
    if (dataHome != null) {
      final installedIcon = File(
        p.join(
          dataHome.path,
          'icons',
          'hicolor',
          '256x256',
          'apps',
          '$appId.png',
        ),
      );
      if (installedIcon.existsSync()) {
        _cachedIconPath = installedIcon.path;
        return installedIcon.path;
      }
    }

    final searchPaths = [
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'images',
        'icon.png',
      ),
      p.join(p.dirname(Platform.resolvedExecutable), 'pdm.png'),
      p.join(p.dirname(Platform.resolvedExecutable), '$appId.png'),
      p.join(Directory.current.path, 'assets', 'images', 'icon.png'),
    ];

    for (final path in searchPaths) {
      if (File(path).existsSync()) {
        _cachedIconPath = path;
        return path;
      }
    }

    return 'assets/images/icon.png';
  }

  /// Returns the target .desktop file content.
  static String generateDesktopEntryContent({required String execPath}) {
    return '''[Desktop Entry]
Type=Application
Name=$appName
Comment=$appComment
Exec="$execPath" %u
Icon=$appId
Terminal=false
Categories=Network;FileTransfer;
StartupWMClass=$appId
''';
  }

  /// Ensures that the application has a valid .desktop file and
  /// hicolor icon installed in the user's XDG data directory
  /// (~/.local/share).
  static Future<String?> ensureDesktopIntegration({
    String? customExecPath,
    Directory? customXdgDataHome,
  }) async {
    if (!Platform.isLinux) return null;

    try {
      final dataHome = customXdgDataHome ?? _resolveXdgDataHome();
      if (dataHome == null) return null;

      final appsDir = Directory(p.join(dataHome.path, 'applications'));
      final iconsDir = Directory(
        p.join(dataHome.path, 'icons', 'hicolor', '256x256', 'apps'),
      );

      if (!appsDir.existsSync()) {
        appsDir.createSync(recursive: true);
      }
      if (!iconsDir.existsSync()) {
        iconsDir.createSync(recursive: true);
      }

      // 1. Extract and install icon
      final iconFile = File(p.join(iconsDir.path, '$appId.png'));
      await _ensureIconInstalled(iconFile);
      if (iconFile.existsSync()) {
        _cachedIconPath = iconFile.path;
      }

      // 2. Resolve target execution path
      final execPath = customExecPath ?? Platform.resolvedExecutable;

      // 3. Create or update .desktop file
      final desktopFile = File(p.join(appsDir.path, '$appId.desktop'));
      final expectedContent = generateDesktopEntryContent(execPath: execPath);

      bool needsWrite = true;
      if (desktopFile.existsSync()) {
        try {
          final currentContent = await desktopFile.readAsString();
          if (currentContent == expectedContent) {
            needsWrite = false;
          }
        } catch (_) {
          needsWrite = true;
        }
      }

      if (needsWrite) {
        await desktopFile.writeAsString(expectedContent, flush: true);
        try {
          await Process.run('chmod', ['+x', desktopFile.path]);
        } catch (_) {}

        // Notify desktop environment if tools are available
        try {
          await Process.run('update-desktop-database', [appsDir.path]);
        } catch (_) {}
        try {
          final hicolorBase = p.join(dataHome.path, 'icons', 'hicolor');
          await Process.run('gtk-update-icon-cache', [
            '-q',
            '-t',
            '-f',
            hicolorBase,
          ]);
        } catch (_) {}
      }

      return _cachedIconPath;
    } catch (e) {
      _log.warning('Linux desktop integration failed: $e');
      return null;
    }
  }

  static Directory? _resolveXdgDataHome() {
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return Directory(xdgDataHome);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, '.local', 'share'));
    }
    return null;
  }

  /// Installs the bundled icon, re-installing it when the bundled
  /// icon changed: the first version returned early whenever a file
  /// already existed, so an icon update never reached the installed
  /// copy and the dock, app switcher and tray kept the old icon.
  static Future<void> _ensureIconInstalled(File targetIcon) async {
    final bytes = await _loadBundledIconBytes();
    if (bytes == null || bytes.isEmpty) return;

    if (targetIcon.existsSync()) {
      try {
        if (_bytesEqual(await targetIcon.readAsBytes(), bytes)) return;
      } catch (_) {}
    }

    try {
      await targetIcon.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// Loads the bundled icon bytes: the Flutter asset bundle first, then
  /// the on-disk fallbacks. Returns null when none can be read.
  static Future<List<int>?> _loadBundledIconBytes() async {
    try {
      final byteData = await rootBundle.load('assets/images/icon.png');
      return byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
    } catch (_) {}

    // Fallback: look for icon file relative to executable or working dir
    final searchPaths = [
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'images',
        'icon.png',
      ),
      p.join(p.dirname(Platform.resolvedExecutable), 'pdm.png'),
      p.join(p.dirname(Platform.resolvedExecutable), '$appId.png'),
      'assets/images/icon.png',
    ];

    for (final path in searchPaths) {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) {
        try {
          return await file.readAsBytes();
        } catch (_) {}
      }
    }
    return null;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
