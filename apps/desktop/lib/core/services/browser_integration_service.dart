import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// Which browser family a target belongs to. It decides the manifest
/// shape: a Chromium manifest whitelists extension ids through
/// `allowed_origins`, a Firefox manifest whitelists add-on ids through
/// `allowed_extensions`, and a manifest that carries the wrong one is
/// rejected by the browser.
enum BrowserFamily { chromium, firefox }

/// A browser PDM can register its native messaging host with.
class BrowserTarget {
  const BrowserTarget({
    required this.id,
    required this.label,
    required this.family,
    required this.registryKey,
  });

  /// Stable identifier used by the UI and the tests: `chrome`, `firefox`, ...
  final String id;
  final String label;
  final BrowserFamily family;

  /// Registry path below HKCU on Windows; unused on Linux.
  final String registryKey;

  @override
  String toString() => 'BrowserTarget($id)';
}

/// What [BrowserIntegrationService.ensureNativeHosts] managed to register.
class BrowserIntegrationResult {
  const BrowserIntegrationResult({required this.registered, this.reason});

  /// One entry per browser that now has a valid manifest, whether it was
  /// written just now or was already correct.
  final List<BrowserTarget> registered;

  /// Why nothing was registered, or why some browsers were skipped. Null
  /// when every detected browser is registered.
  final String? reason;

  bool get ok => registered.isNotEmpty;

  @override
  String toString() =>
      'BrowserIntegrationResult(${registered.map((t) => t.id)}, '
      'reason: $reason)';
}

/// Registers the PDM native messaging host with every browser installed for
/// the current user, so `connectNative('com.ponta.pdm')` works without the
/// user running `install.sh` or knowing the extension id.
///
/// The extension id is pinned by the public key in
/// `integrations/browser-extension/extension/manifest.json` (`key`), so it is
/// the same on every machine: the manifest can whitelist it in advance. Keep
/// [chromeExtensionId] in sync with that file — a test derives the id from the
/// key and compares, so a key change cannot silently break the host.
///
/// Browsers re-read the manifest on every `connectNative`, so registering
/// while the browser is running is enough; no restart is needed.
class BrowserIntegrationService {
  static const String hostName = 'com.ponta.pdm';
  static const String firefoxExtensionId = 'pdm@ponta.dev';

  /// SHA-256 of the DER public key in the extension manifest, rendered the
  /// Chromium way (first 16 bytes, nibbles mapped 0-f to a-p).
  static const String chromeExtensionId = 'hiojpajnfchdajfiegibmklalpgndono';

  static final _log = Logger('BrowserIntegrationService');

  /// Chromium-based browsers on Linux, as paths below XDG_CONFIG_HOME. Only
  /// the ones whose directory already exists are touched: creating
  /// `~/.config/microsoft-edge` for a machine that has no Edge would make
  /// every Chromium browser that looks there think Edge is installed.
  static const List<(String, String, String)> _linuxChromiumBrowsers = [
    ('chrome', 'Google Chrome', 'google-chrome'),
    ('chromium', 'Chromium', 'chromium'),
    ('edge', 'Microsoft Edge', 'microsoft-edge'),
    ('brave', 'Brave', 'BraveSoftware/Brave-Browser'),
    ('vivaldi', 'Vivaldi', 'vivaldi'),
    ('opera', 'Opera', 'opera'),
  ];

  /// The same browsers on Windows, as paths below %LOCALAPPDATA%, with the
  /// HKCU key Chrome and friends read the manifest path from.
  static const List<(String, String, String, String)> _windowsChromiumBrowsers =
      [
        (
          'chrome',
          'Google Chrome',
          r'Google\Chrome\User Data',
          r'Software\Google\Chrome\NativeMessagingHosts\com.ponta.pdm',
        ),
        (
          'chromium',
          'Chromium',
          r'Chromium\User Data',
          r'Software\Chromium\NativeMessagingHosts\com.ponta.pdm',
        ),
        (
          'edge',
          'Microsoft Edge',
          r'Microsoft\Edge\User Data',
          r'Software\Microsoft\Edge\NativeMessagingHosts\com.ponta.pdm',
        ),
        (
          'brave',
          'Brave',
          r'BraveSoftware\Brave-Browser\User Data',
          r'Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\com.ponta.pdm',
        ),
        (
          'vivaldi',
          'Vivaldi',
          r'Vivaldi\User Data',
          r'Software\Vivaldi\NativeMessagingHosts\com.ponta.pdm',
        ),
      ];

  static const String _firefoxWindowsRegistryKey =
      r'Software\Mozilla\NativeMessagingHosts\com.ponta.pdm';

  /// The native host binary shipped in the bundle. CMake installs the
  /// contents of `apps/desktop/bundle/bin` into `<bundle>/bin`, the same
  /// place ffmpeg and yt-dlp land, so the manifest path is computed from the
  /// program directory rather than from whatever the build machine used.
  /// [programDirectory] defaults to the directory of the running executable.
  static String hostBinaryPath([String? programDirectory, bool? isWindows]) {
    final windows = isWindows ?? Platform.isWindows;
    final base = programDirectory ?? p.dirname(Platform.resolvedExecutable);
    return windows
        ? p.windows.join(base, 'bin', 'pdm-native-host.exe')
        : p.posix.join(base, 'bin', 'pdm-native-host');
  }

  /// The folder holding the unpacked extension, shipped next to the program
  /// binary. Used for the "Load unpacked" step Chrome still requires.
  static String extensionDirectory(
    String programDirectory, {
    required bool isWindows,
  }) {
    return isWindows
        ? p.windows.join(programDirectory, 'extension')
        : p.posix.join(programDirectory, 'extension');
  }

  /// Uses durable per-user assets for AppImages, whose mount disappears on
  /// exit. Normal installed/portable bundles keep their existing paths.
  static Future<({String hostPath, String extensionPath})> prepareBundlePaths({
    String? programDirectory,
    bool? isWindows,
    bool? isReleaseBuild,
    Map<String, String>? environment,
  }) async {
    final env = environment ?? Platform.environment;
    final windows = isWindows ?? Platform.isWindows;
    final base = programDirectory ?? p.dirname(Platform.resolvedExecutable);
    final original = (
      hostPath: hostBinaryPath(base, windows),
      extensionPath: extensionDirectory(base, isWindows: windows),
    );
    if (windows ||
        !(isReleaseBuild ?? _isReleaseBuild) ||
        _nonEmpty(env['APPIMAGE']) == null) {
      return original;
    }
    final dataHome =
        _nonEmpty(env['XDG_DATA_HOME']) ??
        p.join(_nonEmpty(env['HOME']) ?? '', '.local', 'share');
    if (!p.isAbsolute(dataHome)) {
      throw StateError(
        'No absolute user data directory for AppImage integration',
      );
    }
    final persistent = p.join(dataHome, 'pdm', 'browser-integration');
    final sourceHostExists = File(original.hostPath).existsSync();
    final sourceExtensionExists = File(
      p.join(original.extensionPath, 'manifest.json'),
    ).existsSync();
    // Do not disguise a damaged release by reusing old staged assets.
    if (!sourceHostExists || !sourceExtensionExists) return original;
    final host = File(p.join(persistent, 'bin', 'pdm-native-host'));
    if (sourceHostExists &&
        (!host.existsSync() ||
            !_sameBytes(
              await host.readAsBytes(),
              await File(original.hostPath).readAsBytes(),
            ))) {
      await host.parent.create(recursive: true);
      final temp = File('${host.path}.tmp.$pid');
      try {
        await File(original.hostPath).copy(temp.path);
        final chmod = await Process.run('chmod', ['u+x', temp.path]);
        if (chmod.exitCode != 0) {
          throw StateError('Could not make the native host executable');
        }
        await temp.rename(host.path);
      } finally {
        if (temp.existsSync()) await temp.delete();
      }
    }
    final extension = p.join(persistent, 'extension');
    final source = Directory(original.extensionPath);
    if (source.existsSync()) {
      await Directory(extension).create(recursive: true);
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final dest = File(
          p.join(extension, p.relative(entity.path, from: source.path)),
        );
        await dest.parent.create(recursive: true);
        if (dest.existsSync() &&
            _sameBytes(await dest.readAsBytes(), await entity.readAsBytes())) {
          continue;
        }
        final temp = File('${dest.path}.tmp.$pid');
        try {
          await entity.copy(temp.path);
          await temp.rename(dest.path);
        } finally {
          if (temp.existsSync()) await temp.delete();
        }
      }
    }
    return (hostPath: host.path, extensionPath: extension);
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  /// The Chromium manifest body: `allowed_origins` for this one extension.
  static Map<String, Object> chromiumManifest(String hostPath) => {
    'name': hostName,
    'description': 'Ponta Download Manager native messaging host',
    'path': hostPath,
    'type': 'stdio',
    'allowed_origins': ['chrome-extension://$chromeExtensionId/'],
  };

  /// The Firefox manifest body: Firefox rejects a manifest whose
  /// `allowed_extensions` is missing, and ignores `allowed_origins`.
  static Map<String, Object> firefoxManifest(String hostPath) => {
    'name': hostName,
    'description': 'Ponta Download Manager native messaging host',
    'path': hostPath,
    'type': 'stdio',
    'allowed_extensions': [firefoxExtensionId],
  };

  /// Writes the native messaging manifest for every installed browser.
  ///
  /// Only release builds write anything: a debug build's host binary lives in
  /// `build/`, and a manifest pointing there breaks the moment that directory
  /// is cleaned — the same rule `LinuxDesktopService` follows. [isReleaseBuild],
  /// [homeDir], [configHome], [localAppData], [appData], [isWindows] and
  /// [runProcess] are test seams.
  static Future<BrowserIntegrationResult> ensureNativeHosts({
    String? homeDir,
    String? configHome,
    String? localAppData,
    String? appData,
    required String hostBinaryPath,
    bool? isReleaseBuild,
    bool? isWindows,
    Future<ProcessResult> Function(String executable, List<String> args)?
    runProcess,
  }) async {
    final release = isReleaseBuild ?? _isReleaseBuild;
    if (!release) {
      return const BrowserIntegrationResult(
        registered: [],
        reason: 'browser integration is only registered by release builds',
      );
    }

    final windows = isWindows ?? Platform.isWindows;
    final hostOnDisk = windows
        ? hostBinaryPath.replaceAll('\\', '/')
        : hostBinaryPath;
    if (!File(hostOnDisk).existsSync()) {
      return BrowserIntegrationResult(
        registered: const [],
        reason: 'native host binary not found at $hostBinaryPath',
      );
    }

    try {
      return windows
          ? await _ensureWindows(
              hostBinaryPath: hostBinaryPath,
              localAppData:
                  _nonEmpty(localAppData) ??
                  _nonEmpty(Platform.environment['LOCALAPPDATA']) ??
                  _joinWindows(
                    homeDir ?? Platform.environment['USERPROFILE'],
                    r'AppData\Local',
                  ),
              appData:
                  _nonEmpty(appData) ??
                  _nonEmpty(Platform.environment['APPDATA']) ??
                  _joinWindows(
                    homeDir ?? Platform.environment['USERPROFILE'],
                    r'AppData\Roaming',
                  ),
              runProcess: runProcess ?? _runProcess,
            )
          : await _ensureLinux(
              hostBinaryPath: hostBinaryPath,
              homeDir: homeDir ?? Platform.environment['HOME'] ?? '',
              configHome:
                  _nonEmpty(configHome) ??
                  _nonEmpty(Platform.environment['XDG_CONFIG_HOME']) ??
                  p.join(
                    homeDir ?? Platform.environment['HOME'] ?? '',
                    '.config',
                  ),
            );
    } catch (e) {
      _log.warning('native host registration failed: $e');
      return BrowserIntegrationResult(registered: const [], reason: '$e');
    }
  }

  static bool get _isReleaseBuild {
    // Kept as a getter so the test seam stays the only override.
    return const bool.fromEnvironment('dart.vm.product');
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> args,
  ) => Process.run(executable, args);

  static String _joinWindows(String? base, String rest) {
    if (base == null || base.isEmpty) return rest;
    return '$base\\$rest';
  }

  static Future<BrowserIntegrationResult> _ensureLinux({
    required String hostBinaryPath,
    required String homeDir,
    required String configHome,
  }) async {
    final registered = <BrowserTarget>[];

    for (final (id, label, relative) in _linuxChromiumBrowsers) {
      final browserConfig = p.join(configHome, relative);
      if (!Directory(browserConfig).existsSync()) continue;
      final manifest = File(
        p.join(browserConfig, 'NativeMessagingHosts', '$hostName.json'),
      );
      await _writeIfChanged(
        manifest,
        const JsonEncoder.withIndent('  ')
            .convert(chromiumManifest(hostBinaryPath)),
      );
      registered.add(
        BrowserTarget(
          id: id,
          label: label,
          family: BrowserFamily.chromium,
          registryKey: '',
        ),
      );
    }

    final manifest = File(
      p.join(homeDir, '.mozilla', 'native-messaging-hosts', '$hostName.json'),
    );
    if (Directory(p.join(homeDir, '.mozilla')).existsSync()) {
      await _writeIfChanged(
        manifest,
        const JsonEncoder.withIndent('  ')
            .convert(firefoxManifest(hostBinaryPath)),
      );
      registered.add(
        const BrowserTarget(
          id: 'firefox',
          label: 'Firefox',
          family: BrowserFamily.firefox,
          registryKey: '',
        ),
      );
    }

    if (registered.isEmpty) {
      return const BrowserIntegrationResult(
        registered: [],
        reason: 'no supported browser profile found',
      );
    }
    return BrowserIntegrationResult(registered: registered);
  }

  static Future<BrowserIntegrationResult> _ensureWindows({
    required String hostBinaryPath,
    required String localAppData,
    required String appData,
    required Future<ProcessResult> Function(String, List<String>) runProcess,
  }) async {
    final registered = <BrowserTarget>[];
    String? failure;

    // One manifest per family, in a directory the app owns. Chrome, Edge and
    // Firefox all read the same file shape for their own family only.
    final chromiumPath = p.windows.join(localAppData, 'pdm', '$hostName.json');
    final firefoxPath = p.windows.join(
      localAppData,
      'pdm',
      'firefox',
      '$hostName.json',
    );
    await _writeIfChanged(
      File(chromiumPath.replaceAll('\\', '/')),
      const JsonEncoder.withIndent('  ')
          .convert(chromiumManifest(hostBinaryPath)),
    );
    await _writeIfChanged(
      File(firefoxPath.replaceAll('\\', '/')),
      const JsonEncoder.withIndent('  ')
          .convert(firefoxManifest(hostBinaryPath)),
    );

    for (final (id, label, profileRelative, key) in _windowsChromiumBrowsers) {
      final profile = p.windows.join(localAppData, profileRelative);
      if (!Directory(profile.replaceAll('\\', '/')).existsSync()) continue;
      final error = await _registerKey(runProcess, key, chromiumPath);
      if (error != null) {
        failure ??= error;
        continue;
      }
      registered.add(
        BrowserTarget(
          id: id,
          label: label,
          family: BrowserFamily.chromium,
          registryKey: key,
        ),
      );
    }

    if (Directory(
      p.windows.join(appData, r'Mozilla\Firefox').replaceAll('\\', '/'),
    ).existsSync()) {
      final error = await _registerKey(
        runProcess,
        _firefoxWindowsRegistryKey,
        firefoxPath,
      );
      if (error != null) {
        failure ??= error;
      } else {
        registered.add(
          const BrowserTarget(
            id: 'firefox',
            label: 'Firefox',
            family: BrowserFamily.firefox,
            registryKey: _firefoxWindowsRegistryKey,
          ),
        );
      }
    }

    if (registered.isEmpty) {
      return BrowserIntegrationResult(
        registered: const [],
        reason: failure ?? 'no supported browser profile found',
      );
    }
    return BrowserIntegrationResult(registered: registered, reason: failure);
  }

  /// Sets the default value of [key] (below HKCU) to [manifestPath]. Returns
  /// the error output when `reg` fails, so a permission problem is reported
  /// instead of being counted as success.
  static Future<String?> _registerKey(
    Future<ProcessResult> Function(String, List<String>) runProcess,
    String key,
    String manifestPath,
  ) async {
    final result = await runProcess('reg', [
      'add',
      'HKCU\\$key',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      manifestPath,
      '/f',
    ]);
    if (result.exitCode == 0) return null;
    final message = '${result.stderr}'.trim();
    return message.isEmpty ? 'reg add failed (${result.exitCode})' : message;
  }

  /// Writes [content] only when it differs, so re-running on every launch
  /// neither churns the browser's config directory nor resets timestamps.
  static Future<void> _writeIfChanged(File file, String content) async {
    if (file.existsSync()) {
      try {
        if (await file.readAsString() == content) return;
      } catch (_) {
        // Unreadable: rewrite it.
      }
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }
}
