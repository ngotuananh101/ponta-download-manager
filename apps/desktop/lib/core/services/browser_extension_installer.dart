import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'browser_integration_service.dart';

/// Whether a browser profile has the PDM extension, and why not when it
/// does not.
enum ExtensionStatus {
  /// The profile lists the extension and the path it points at exists.
  installed,

  /// The browser exists but has no entry for the extension.
  notInstalled,

  /// The browser remembers a different extension directory (the app moved),
  /// or a Preferences file that cannot be parsed.
  needsRepair,

  /// The browser is running, and it would overwrite Preferences on exit.
  browserRunning,

  /// User consent or a manual browser step is required, or safe shutdown
  /// could not be verified. Preferences are left untouched.
  needsUserAction,
}

/// One browser profile and the state of the extension in it.
class BrowserExtensionStatus {
  const BrowserExtensionStatus({
    required this.browserId,
    required this.browserLabel,
    required this.profilePath,
    required this.status,
    this.reason,
  });

  final String browserId;
  final String browserLabel;

  /// The profile directory (`.../google-chrome/Default`).
  final String profilePath;
  final ExtensionStatus status;

  /// Human-readable explanation, shown under the browser name.
  final String? reason;

  @override
  String toString() =>
      'BrowserExtensionStatus($browserId/$profilePath: $status)';
}

/// The outcome of [BrowserExtensionInstaller.install].
class BrowserExtensionInstallResult {
  const BrowserExtensionInstallResult({
    required this.installed,
    required this.alreadyInstalled,
    required this.skipped,
    this.reason,
  });

  final List<BrowserExtensionStatus> installed;
  final List<BrowserExtensionStatus> alreadyInstalled;
  final List<BrowserExtensionStatus> skipped;

  /// Why nothing was installed (missing extension directory, ...).
  final String? reason;

  @override
  String toString() =>
      'BrowserExtensionInstallResult(installed: '
      '${installed.map((s) => s.browserId)}, skipped: '
      '${skipped.map((s) => s.browserId)}, reason: $reason)';
}

/// Seeds the bundled extension into stopped Chromium profiles on Linux.
///
/// This is a best-effort compatibility mechanism, not an officially supported
/// browser installation API. Browser versions may reject or reset the entry.
/// It requires developer mode to have already been enabled by the user and
/// never re-enables an extension the user or browser has disabled.
///
/// Three hard limits, each surfaced rather than papered over:
///  * Chrome rewrites Preferences from memory when it exits, so writing
///    underneath a running browser is lost (verified: the entry is gone after
///    the browser shuts down). [install] skips those profiles.
///  * On Windows and macOS Chrome HMAC-tracks `extensions.settings` and
///    enforces it on load (`chrome_pref_service_factory.cc`: IS_WIN/IS_MAC
///    get GROUP_ENFORCE_DEFAULT, which promotes the pref to ENFORCE_ON_LOAD;
///    a key without a matching authenticator is CHANGED_HMAC, which is
///    DO_RESET). An entry written from outside the browser is therefore
///    deleted on the next launch, so Windows gets [ExtensionStatus
///    .needsUserAction] instead of a write.
///  * The extension id must be pinned in its manifest for the entry to be
///    honoured — Chrome ignores (and rewrites away) an unpacked entry whose
///    id does not match the key-derived id.
///
/// Firefox is not handled here; its add-on installation flow is separate.
class BrowserExtensionInstaller {
  static final _log = Logger('BrowserExtensionInstaller');

  static const String chromeExtensionId =
      BrowserIntegrationService.chromeExtensionId;

  /// Chromium-family browsers on Linux as paths below XDG_CONFIG_HOME.
  static const List<(String, String, String)> browsers = [
    ('chrome', 'Google Chrome', 'google-chrome'),
    ('chromium', 'Chromium', 'chromium'),
    ('edge', 'Microsoft Edge', 'microsoft-edge'),
    ('brave', 'Brave', 'BraveSoftware/Brave-Browser'),
    ('vivaldi', 'Vivaldi', 'vivaldi'),
    ('opera', 'Opera', 'opera'),
  ];

  /// The same browsers on Windows, as paths below %LOCALAPPDATA%. Chrome and
  /// Edge keep profiles there, not in %APPDATA% and not in ~/.config.
  static const List<(String, String, String)> windowsBrowsers = [
    ('chrome', 'Google Chrome', r'Google\Chrome\User Data'),
    ('chromium', 'Chromium', r'Chromium\User Data'),
    ('edge', 'Microsoft Edge', r'Microsoft\Edge\User Data'),
    ('brave', 'Brave', r'BraveSoftware\Brave-Browser\User Data'),
    ('vivaldi', 'Vivaldi', r'Vivaldi\User Data'),
  ];

  /// Where the profiles of every Chromium browser live, given the platform.
  static List<(String, String, String)> _browserProfiles({
    required bool isWindows,
    String? configHome,
    String? localAppData,
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    String? nonEmpty(String? value) =>
        value == null || value.isEmpty ? null : value;
    if (isWindows) {
      final base =
          nonEmpty(localAppData) ??
          nonEmpty(env['LOCALAPPDATA']) ??
          p.windows.join(env['USERPROFILE'] ?? '', 'AppData\\Local');
      return [
        for (final (id, label, relative) in windowsBrowsers)
          (id, label, p.windows.join(base, relative)),
      ];
    }
    final base =
        nonEmpty(configHome) ??
        nonEmpty(env['XDG_CONFIG_HOME']) ??
        p.join(env['HOME'] ?? '', '.config');
    return [
      for (final (id, label, relative) in browsers)
        (id, label, p.join(base, relative)),
    ];
  }

  // Match Linux comm names, not just launcher names (pgrep -x uses comm).
  // Conservative aliases may block another profile of the same browser.
  static const Map<String, List<String>> _processNames = {
    'chrome': ['chrome', 'google-chrome', 'chrome_crashpad'],
    'chromium': ['chromium', 'chromium-browse', 'chrome'],
    'edge': ['msedge', 'microsoft-edge'],
    'brave': ['brave', 'brave-browser'],
    'vivaldi': ['vivaldi-bin', 'vivaldi'],
    'opera': ['opera'],
  };

  /// Lists every Chromium profile found and whether it has the extension.
  static Future<List<BrowserExtensionStatus>> inspect({
    String? configHome,
    bool? isWindows,
    String? localAppData,
    Map<String, String>? environment,
  }) async {
    final statuses = <BrowserExtensionStatus>[];

    for (final (id, label, browserConfig) in _browserProfiles(
      isWindows: isWindows ?? Platform.isWindows,
      configHome: configHome,
      localAppData: localAppData,
      environment: environment,
    )) {
      for (final profile in _profilesOf(browserConfig)) {
        statuses.add(
          _statusOf(
            browserId: id,
            browserLabel: label,
            profilePath: profile.path,
            extensionDirectory: null,
          ),
        );
      }
    }
    return statuses;
  }

  /// Seeds eligible stopped profiles in release builds only. The default guard
  /// checks the browser's SingletonLock before probing conservative process
  /// comm aliases. Failed probes are fail-closed. Overrides are test seams.
  static Future<BrowserExtensionInstallResult> install({
    String? configHome,
    bool? isWindows,
    String? localAppData,
    required String extensionDirectory,
    bool? isReleaseBuild,
    Map<String, String>? environment,
    Future<ProcessResult> Function(String, List<String>)? runProcess,
    bool Function(String profilePath)? isBrowserRunning,
  }) async {
    if (!(isReleaseBuild ?? const bool.fromEnvironment('dart.vm.product'))) {
      return const BrowserExtensionInstallResult(
        installed: [],
        alreadyInstalled: [],
        skipped: [],
        reason: 'extension installation is only performed by release builds',
      );
    }
    if (!Directory(_fs(extensionDirectory)).existsSync()) {
      return BrowserExtensionInstallResult(
        installed: const [],
        alreadyInstalled: const [],
        skipped: const [],
        reason: 'extension directory not found at $extensionDirectory',
      );
    }

    final windows = isWindows ?? Platform.isWindows;
    final installed = <BrowserExtensionStatus>[];
    final already = <BrowserExtensionStatus>[];
    final skipped = <BrowserExtensionStatus>[];
    var anyProfile = false;

    for (final (id, label, browserConfig) in _browserProfiles(
      isWindows: windows,
      configHome: configHome,
      localAppData: localAppData,
      environment: environment,
    )) {
      final profiles = _profilesOf(browserConfig);
      if (profiles.isEmpty) continue;
      for (final profile in profiles) {
        anyProfile = true;
        final status = _statusOf(
          browserId: id,
          browserLabel: label,
          profilePath: profile.path,
          extensionDirectory: extensionDirectory,
        );
        if (status.status == ExtensionStatus.needsUserAction ||
            (status.status == ExtensionStatus.needsRepair &&
                _readPreferences(profile.path).json == null)) {
          skipped.add(status);
          continue;
        }
        if (status.status == ExtensionStatus.installed) {
          already.add(status);
          continue;
        }
        if (windows) {
          // Chrome tracks `extensions.settings` with an HMAC and enforces it
          // on Windows (see the class doc). An entry written from outside
          // Chrome has no matching HMAC for its key, so Chrome registers it
          // as untrusted and resets it on load: the write would look like it
          // worked and then silently disappear. Report the step as a user
          // action instead of pretending.
          skipped.add(
            BrowserExtensionStatus(
              browserId: id,
              browserLabel: label,
              profilePath: profile.path,
              status: ExtensionStatus.needsUserAction,
              reason:
                  'Windows Chrome verifies the extension list; use Load '
                  'unpacked once',
            ),
          );
          continue;
        }
        bool? running;
        try {
          running = isBrowserRunning != null
              ? isBrowserRunning(profile.path)
              : await _isBrowserRunning(
                  id,
                  browserConfig: browserConfig,
                  runProcess: runProcess ?? Process.run,
                );
        } catch (_) {
          // Overrides and filesystem probes must fail closed as well.
          running = null;
        }
        if (running != false) {
          skipped.add(
            BrowserExtensionStatus(
              browserId: id,
              browserLabel: label,
              profilePath: profile.path,
              status: running == true
                  ? ExtensionStatus.browserRunning
                  : ExtensionStatus.needsUserAction,
              reason: running == true
                  ? '$label is running; quit it and install again'
                  : 'Cannot verify that $label is closed; Preferences were not changed',
            ),
          );
          continue;
        }
        try {
          await _writeEntry(profile, extensionDirectory);
          installed.add(
            BrowserExtensionStatus(
              browserId: id,
              browserLabel: label,
              profilePath: profile.path,
              status: ExtensionStatus.installed,
            ),
          );
        } catch (e) {
          _log.warning('could not install into ${profile.path}: $e');
          skipped.add(
            BrowserExtensionStatus(
              browserId: id,
              browserLabel: label,
              profilePath: profile.path,
              status: ExtensionStatus.needsRepair,
              reason: '$e',
            ),
          );
        }
      }
    }

    return BrowserExtensionInstallResult(
      installed: installed,
      alreadyInstalled: already,
      skipped: skipped,
      reason: anyProfile ? null : 'no Chromium profile found',
    );
  }

  /// Dart's IO accepts forward slashes on Windows, so a Windows-style path is
  /// normalised once here instead of every call site carrying a platform
  /// branch. The stored `path` in Preferences stays a plain native path.
  static String _fs(String path) => path.replaceAll('\\', '/');

  /// `Default`, `Profile 1`, `Profile 2`, ... — the directories Chrome keeps
  /// per profile. Anything else in the config dir (Crashpad, NativeMessaging
  /// Hosts, Local State) is not a profile.
  static List<Directory> _profilesOf(String browserConfig) {
    final dir = Directory(_fs(browserConfig));
    if (!dir.existsSync()) return const [];
    final profiles = <Directory>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      final isProfile =
          name == 'Default' ||
          RegExp(r'^Profile \d+$').hasMatch(name) ||
          name == 'Guest Profile';
      if (!isProfile) continue;
      if (!File(_fs(p.join(entity.path, 'Preferences'))).existsSync()) continue;
      profiles.add(entity);
    }
    profiles.sort((a, b) {
      // Default first, then Profile 1, Profile 2, ...
      final an = p.basename(a.path);
      final bn = p.basename(b.path);
      if (an == 'Default') return -1;
      if (bn == 'Default') return 1;
      return an.compareTo(bn);
    });
    return profiles;
  }

  static BrowserExtensionStatus _statusOf({
    required String browserId,
    required String browserLabel,
    required String profilePath,
    required String? extensionDirectory,
  }) {
    final parsed = _readPreferences(profilePath);
    final json = parsed.json;
    if (json == null) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.needsRepair,
        reason: 'Preferences unreadable: ${parsed.error}',
      );
    }
    final entry = _entryOf(json);
    if (entry != null && _isDisabled(entry)) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.needsUserAction,
        reason: 'The extension is disabled; enable it in the browser',
      );
    }
    // Inspection of a missing extension remains notInstalled. Installation,
    // and inspection of an existing entry, must honor developer-mode consent.
    if ((entry != null || extensionDirectory != null) &&
        !_hasDeveloperMode(json)) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.needsUserAction,
        reason: 'Enable developer mode in the browser before loading unpacked',
      );
    }
    if (entry == null) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.notInstalled,
      );
    }
    final storedPath = entry['path'];
    if (storedPath is! String || !Directory(storedPath).existsSync()) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.needsRepair,
        reason: 'extension path is missing ($storedPath)',
      );
    }
    // The app moved: the profile points at a directory that still exists but
    // is not the bundle's extension any more.
    if (extensionDirectory != null &&
        p.canonicalize(storedPath) != p.canonicalize(extensionDirectory)) {
      return BrowserExtensionStatus(
        browserId: browserId,
        browserLabel: browserLabel,
        profilePath: profilePath,
        status: ExtensionStatus.needsRepair,
        reason: 'extension path points at $storedPath',
      );
    }
    return BrowserExtensionStatus(
      browserId: browserId,
      browserLabel: browserLabel,
      profilePath: profilePath,
      status: ExtensionStatus.installed,
    );
  }

  static Map<String, dynamic>? _entryOf(Map<String, dynamic> prefs) {
    final extensions = prefs['extensions'];
    if (extensions is! Map) return null;
    final settings = extensions['settings'];
    if (settings is! Map) return null;
    final entry = settings[chromeExtensionId];
    return entry is Map ? entry.cast<String, dynamic>() : null;
  }

  static ({Map<String, dynamic>? json, String? error}) _readPreferences(
    String profilePath,
  ) {
    final file = File(_fs(p.join(profilePath, 'Preferences')));
    if (!file.existsSync()) return (json: null, error: 'file is missing');
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        return (json: null, error: 'not a JSON object');
      }
      final json = decoded.cast<String, dynamic>();
      _validatePreferences(json);
      return (json: json, error: null);
    } catch (e) {
      return (json: null, error: '$e');
    }
  }

  static void _validatePreferences(Map<String, dynamic> prefs) {
    void requireMap(Map parent, String key) {
      if (parent.containsKey(key) && parent[key] is! Map) {
        throw FormatException('Preferences $key is not an object');
      }
    }

    requireMap(prefs, 'extensions');
    final extensions = prefs['extensions'];
    if (extensions is! Map) return;
    requireMap(extensions, 'settings');
    requireMap(extensions, 'ui');
    final settings = extensions['settings'];
    if (settings is Map) requireMap(settings, chromeExtensionId);
  }

  static bool _hasDeveloperMode(Map<String, dynamic> prefs) {
    final extensions = prefs['extensions'];
    if (extensions is! Map) return false;
    final ui = extensions['ui'];
    return ui is Map && ui['developer_mode'] == true;
  }

  static bool _isDisabled(Map<String, dynamic> entry) {
    if (entry['state'] != 1) return true;
    final reasons = entry['disable_reasons'];
    if (reasons == null) return false;
    if (reasons is int) return reasons != 0;
    if (reasons is List) return reasons.isNotEmpty;
    // Unknown representations are not evidence that the entry is enabled.
    return true;
  }

  /// Adds only our entry and commits a complete snapshot via same-directory
  /// rename. Never replace corrupt or structurally malformed Preferences.
  static Future<void> _writeEntry(
    Directory profile,
    String extensionDirectory,
  ) async {
    final file = File(_fs(p.join(profile.path, 'Preferences')));
    final prefs = _readPreferences(profile.path);
    final json = prefs.json;
    if (json == null) {
      throw FormatException('Preferences unreadable: ${prefs.error}');
    }
    final oldEntry = _entryOf(json);
    if ((oldEntry != null && _isDisabled(oldEntry)) ||
        !_hasDeveloperMode(json)) {
      throw StateError('Browser consent changed; Preferences were not changed');
    }
    final extensions = _asMap(json, 'extensions');
    final settings = _asMap(extensions, 'settings');
    settings[chromeExtensionId] = <String, dynamic>{
      'path': p.canonicalize(extensionDirectory),
      'location': 4,
      'state': 1,
    };

    final random = Random.secure();
    final temporary = File(
      '${file.path}.pdm-$pid-${random.nextInt(1 << 32)}.tmp',
    );
    var created = false;
    try {
      // Exclusive creation avoids clobbering another install's temporary file.
      await temporary.create(exclusive: true);
      created = true;
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
      await temporary.rename(file.path);
    } finally {
      if (created && await temporary.exists()) await temporary.delete();
    }
  }

  static Map<String, dynamic> _asMap(Map<String, dynamic> parent, String key) {
    final existing = parent[key];
    if (existing is Map) return existing.cast<String, dynamic>();
    if (parent.containsKey(key)) {
      throw FormatException('Preferences $key is not an object');
    }
    final created = <String, dynamic>{};
    parent[key] = created;
    return created;
  }

  static Future<bool?> _isBrowserRunning(
    String browserId, {
    required String browserConfig,
    required Future<ProcessResult> Function(String, List<String>) runProcess,
  }) async {
    try {
      // Chromium puts the lock at the user-data root, not in each profile.
      // Do not follow the link: its hostname/PID target is normally dangling.
      // Even a stale lock blocks writes rather than guessing about its owner.
      final lock = _fs(p.join(browserConfig, 'SingletonLock'));
      if (FileSystemEntity.typeSync(lock, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return true;
      }
      final names = _processNames[browserId];
      if (names == null) return null;
      final pattern = '(${names.map(RegExp.escape).join('|')})';
      final result = await runProcess('pgrep', ['-x', pattern]);
      if (result.exitCode == 0) return true;
      if (result.exitCode == 1) return false;
      return null;
    } catch (_) {
      // Missing tools and permissions do not establish a safe shutdown.
      return null;
    }
  }
}
