import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/browser_extension_installer.dart';
import 'package:path/path.dart' as p;

Directory makeHome(List<String> dirs) {
  final home = Directory.systemTemp.createTempSync('pdm-ext-');
  for (final path in dirs) {
    Directory('${home.path}/$path').createSync(recursive: true);
  }
  return home;
}

/// A Chrome profile with its Preferences file, the way Chrome leaves it.
void writePreferences(Directory home, String relative, Object json) {
  final file = File('${home.path}/$relative');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    json is String ? json : const JsonEncoder.withIndent('  ').convert(json),
  );
}

Map<String, dynamic> readPreferences(Directory home, String relative) =>
    jsonDecode(File('${home.path}/$relative').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> developerPreferences() => {
  'profile': {'exit_type': 'Normal', 'name': 'Personal'},
  'browser': {'check_default_browser': false},
  'extensions': <String, dynamic>{
    'settings': <String, dynamic>{
      'otherid': {'path': '/other', 'location': 4, 'state': 1},
    },
    'ui': <String, dynamic>{'developer_mode': true},
  },
};

Directory makeExtension(Directory home) {
  final dir = Directory('${home.path}/app/extension')
    ..createSync(recursive: true);
  File('${dir.path}/manifest.json')
      .writeAsStringSync('{"manifest_version": 3}');
  return dir;
}

void main() {
  group('inspect', () {
    test('reports a browser with no extension as not installed', () async {
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(home, '.config/google-chrome/Default/Preferences', {
        'profile': {'exit_type': 'Normal'},
      });

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses, hasLength(1));
      expect(statuses.single.browserId, 'chrome');
      expect(statuses.single.status, ExtensionStatus.notInstalled);
    });

    test('reports an installed extension as installed', () async {
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(home, '.config/google-chrome/Default/Preferences', {
        'extensions': {
          'settings': {
            BrowserExtensionInstaller.chromeExtensionId: {
              'path': extension.path,
              'location': 4,
              'state': 1,
            },
          },
          'ui': {'developer_mode': true},
        },
      });

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses.single.status, ExtensionStatus.installed);
    });

    test('reports an entry whose folder is gone as needing repair', () async {
      // A moved or uninstalled app leaves Chrome pointing at a directory
      // that no longer exists; chrome://extensions shows it as an error and
      // the extension never loads.
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(home, '.config/google-chrome/Default/Preferences', {
        'extensions': {
          'settings': {
            BrowserExtensionInstaller.chromeExtensionId: {
              'path': '/opt/gone/extension',
              'location': 4,
              'state': 1,
            },
          },
          'ui': {'developer_mode': true},
        },
      });

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses.single.status, ExtensionStatus.needsRepair);
      expect(statuses.single.reason, contains('/opt/gone/extension'));
    });

    test('ignores a Chromium directory with no profile in it', () async {
      // A bare ~/.config/chromium with no Default/Profile 1 is a leftover,
      // not an installed browser with a profile to write to.
      final home = makeHome(['.config/chromium', '.config/vivaldi']);
      addTearDown(() => home.deleteSync(recursive: true));

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses, isEmpty);
    });

    test('reports every profile of a browser separately', () async {
      // Two Chrome profiles means two Preferences files; installing into
      // only Default leaves the user's work profile without the extension.
      final home = makeHome([
        '.config/google-chrome/Default',
        '.config/google-chrome/Profile 1',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        developerPreferences(),
      );
      writePreferences(home, '.config/google-chrome/Profile 1/Preferences', {});

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses.map((s) => s.profilePath), [
        '${home.path}/.config/google-chrome/Default',
        '${home.path}/.config/google-chrome/Profile 1',
      ]);
    });

    test('ignores a profile directory with no Preferences file', () async {
      // Chrome creates the directory before it writes preferences; an
      // aborted first run leaves one behind that must not be counted as a
      // browser the user can install into.
      final home = makeHome(['.config/google-chrome/Profile 2']);
      addTearDown(() => home.deleteSync(recursive: true));

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses, isEmpty);
    });

    test('survives a corrupt Preferences file', () async {
      // Chrome rewrites a corrupt Preferences on the next launch, but the
      // status view must still say "not installed" (and not crash) so the
      // one-click install is offered.
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        '{"extensions": ',
      );

      final statuses = await BrowserExtensionInstaller.inspect(
        configHome: '${home.path}/.config',
      );

      expect(statuses.single.status, ExtensionStatus.needsRepair);
      expect(statuses.single.reason, contains('Preferences'));
    });
  });

  group('install', () {
    test(
      'adds the extension to an existing profile and keeps the rest',
      () async {
        final home = makeHome(['.config/google-chrome/Default']);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        writePreferences(home, '.config/google-chrome/Default/Preferences', {
          'profile': {'exit_type': 'Normal'},
          'extensions': {
            'settings': {
              'otherid': {'path': '/other', 'location': 4, 'state': 1},
            },
            'ui': {'developer_mode': true},
          },
        });

        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          configHome: '${home.path}/.config',
          extensionDirectory: extension.path,
          isBrowserRunning: (_) => false,
        );

        expect(result.installed.map((s) => s.browserId), ['chrome']);
        final prefs = readPreferences(
          home,
          '.config/google-chrome/Default/Preferences',
        );
        final settings =
            prefs['extensions']['settings'] as Map<String, dynamic>;
        // The user's other extensions survive: Chrome's Preferences is shared
        // state, not ours to replace.
        expect(
          settings.keys,
          containsAll(['otherid', BrowserExtensionInstaller.chromeExtensionId]),
        );
        expect((prefs['profile'] as Map)['exit_type'], 'Normal');

        final entry =
            settings[BrowserExtensionInstaller.chromeExtensionId] as Map;
        expect(entry['path'], extension.path);
        // location 4 is "unpacked"; state 1 is enabled.
        expect(entry['location'], 4);
        expect(entry['state'], 1);
        // Without developer_mode Chrome marks the entry
        // unsupportedDeveloperExtension and leaves the extension disabled.
        expect((prefs['extensions'] as Map)['ui']['developer_mode'], isTrue);
      },
    );

    test('is a no-op when the extension is already there', () async {
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(home, '.config/google-chrome/Default/Preferences', {
        'extensions': {
          'settings': {
            BrowserExtensionInstaller.chromeExtensionId: {
              'path': extension.path,
              'location': 4,
              'state': 1,
            },
          },
          'ui': {'developer_mode': true},
        },
      });
      final path = '${home.path}/.config/google-chrome/Default/Preferences';
      final before = File(path).lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );

      expect(result.installed, isEmpty);
      expect(result.alreadyInstalled.map((s) => s.browserId), ['chrome']);
      expect(File(path).lastModifiedSync(), before);
    });

    test('rewrites a stale path instead of leaving it alone', () async {
      // The app moved (or was reinstalled into a new directory): Chrome
      // would keep loading the old, missing extension directory.
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(home, '.config/google-chrome/Default/Preferences', {
        'extensions': {
          'settings': {
            BrowserExtensionInstaller.chromeExtensionId: {
              'path': '/opt/old/pdm/extension',
              'location': 4,
              'state': 1,
            },
          },
          'ui': {'developer_mode': true},
        },
      });

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );

      expect(result.installed.map((s) => s.browserId), ['chrome']);
      final entry = readPreferences(
        home,
        '.config/google-chrome/Default/Preferences',
      )['extensions']['settings'][BrowserExtensionInstaller.chromeExtensionId];
      expect(entry['path'], extension.path);
    });

    test('skips a browser that is running', () async {
      // Chrome rewrites Preferences from memory when it exits, so a write
      // made underneath a running browser is simply lost — and the user
      // would be told the extension is installed when it is not.
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        developerPreferences(),
      );

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (profilePath) =>
            profilePath.contains('google-chrome'),
      );

      expect(result.installed, isEmpty);
      expect(result.skipped.single.status, ExtensionStatus.browserRunning);
      expect(
        readPreferences(
          home,
          '.config/google-chrome/Default/Preferences',
        )['extensions']['settings'][BrowserExtensionInstaller
            .chromeExtensionId],
        isNull,
      );
    });

    test('does not install when the extension directory is missing', () async {
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        developerPreferences(),
      );

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: '${home.path}/app/missing-extension',
        isBrowserRunning: (_) => false,
      );

      expect(result.installed, isEmpty);
      expect(result.reason, contains('extension directory'));
    });

    test('installs into every Chromium browser that is present', () async {
      final home = makeHome([
        '.config/google-chrome/Default',
        '.config/BraveSoftware/Brave-Browser/Default',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        developerPreferences(),
      );
      writePreferences(
        home,
        '.config/BraveSoftware/Brave-Browser/Default/Preferences',
        developerPreferences(),
      );

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );

      expect(result.installed.map((s) => s.browserId), ['chrome', 'brave']);
      for (final relative in [
        '.config/google-chrome/Default/Preferences',
        '.config/BraveSoftware/Brave-Browser/Default/Preferences',
      ]) {
        final prefs = readPreferences(home, relative);
        expect(
          prefs['extensions']['settings'][BrowserExtensionInstaller
              .chromeExtensionId]['path'],
          extension.path,
        );
      }
    });

    test('leaves the extension folder where the installer put it', () async {
      // Chrome stores an absolute path; a path that does not exist shows up
      // in chrome://extensions as an error and the extension never loads.
      final home = makeHome(['.config/google-chrome/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(
        home,
        '.config/google-chrome/Default/Preferences',
        developerPreferences(),
      );

      await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );

      final storedPath =
          readPreferences(
                home,
                '.config/google-chrome/Default/Preferences',
              )['extensions']['settings'][BrowserExtensionInstaller
                  .chromeExtensionId]['path']
              as String;
      expect(p.isAbsolute(storedPath), isTrue);
      expect(Directory(storedPath).existsSync(), isTrue);
    });
  });

  group('safe profile seeding', () {
    const relative = '.config/google-chrome/Default/Preferences';

    test('default debug install does not touch profiles', () async {
      final home = makeHome([]);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(home, relative, developerPreferences());
      final file = File('${home.path}/$relative');
      final before = file.readAsBytesSync();
      final result = await BrowserExtensionInstaller.install(
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );
      expect(result.installed, isEmpty);
      expect(result.reason, contains('release'));
      expect(file.readAsBytesSync(), before);
    });

    for (final probe in ['throws', 'exit 2']) {
      test('fails closed when process check $probe', () async {
        final home = makeHome([]);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        writePreferences(home, relative, developerPreferences());
        final file = File('${home.path}/$relative');
        final before = file.readAsBytesSync();
        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          configHome: '${home.path}/.config',
          extensionDirectory: extension.path,
          runProcess: (executable, arguments) async {
            if (probe == 'throws') {
              throw const ProcessException('pgrep', [], 'unavailable');
            }
            return ProcessResult(0, 2, '', 'probe failed');
          },
        );
        expect(result.installed, isEmpty);
        expect(result.skipped.single.status, ExtensionStatus.needsUserAction);
        expect(result.skipped.single.reason, contains('verify'));
        expect(file.readAsBytesSync(), before);
      });
    }

    test('fails closed when the running override throws', () async {
      final home = makeHome([]);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(home, relative, developerPreferences());
      final file = File('${home.path}/$relative');
      final before = file.readAsBytesSync();
      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        configHome: '${home.path}/.config',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => throw StateError('unknown'),
      );
      expect(result.installed, isEmpty);
      expect(result.skipped.single.status, ExtensionStatus.needsUserAction);
      expect(file.readAsBytesSync(), before);
    });

    for (final windows in [false, true]) {
      test(
        'empty environment config path falls back to home: windows $windows',
        () async {
          final home = makeHome([]);
          addTearDown(() => home.deleteSync(recursive: true));
          final profile = windows
              ? 'AppData/Local/Google/Chrome/User Data/Default/Preferences'
              : relative;
          writePreferences(home, profile, developerPreferences());
          final statuses = await BrowserExtensionInstaller.inspect(
            isWindows: windows,
            environment: {
              'HOME': home.path,
              'USERPROFILE': home.path,
              'XDG_CONFIG_HOME': '',
              'LOCALAPPDATA': '',
            },
          );
          expect(statuses, hasLength(1));
          expect(statuses.single.browserId, 'chrome');
          expect(
            statuses.single.profilePath,
            '${home.path}/${p.dirname(profile)}',
          );
          final extension = makeExtension(home);
          final result = await BrowserExtensionInstaller.install(
            isReleaseBuild: true,
            isWindows: windows,
            environment: {
              'HOME': home.path,
              'USERPROFILE': home.path,
              'XDG_CONFIG_HOME': '',
              'LOCALAPPDATA': '',
            },
            extensionDirectory: extension.path,
            isBrowserRunning: (_) => false,
          );
          expect(windows ? result.skipped : result.installed, hasLength(1));
        },
      );
    }

    for (final corrupt in [
      '{"profile":{"name":"Personal"},"extensions":',
      '[]',
    ]) {
      test('leaves unreadable Preferences unchanged: $corrupt', () async {
        final home = makeHome([]);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        writePreferences(home, relative, corrupt);
        final file = File('${home.path}/$relative');
        final before = file.readAsBytesSync();
        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          configHome: '${home.path}/.config',
          extensionDirectory: extension.path,
          isBrowserRunning: (_) => false,
        );
        expect(result.installed, isEmpty);
        expect(result.skipped.single.status, ExtensionStatus.needsRepair);
        expect(file.readAsBytesSync(), before);
      });
    }

    for (final malformed in <Map<String, dynamic>>[
      {
        'extensions': ['keep me'],
      },
      {'extensions': null},
      {
        'extensions': {
          'settings': 'keep me',
          'ui': {'developer_mode': true},
        },
      },
      {
        'extensions': {
          'settings': {},
          'ui': ['keep me'],
        },
      },
      {
        'extensions': {
          'settings': {BrowserExtensionInstaller.chromeExtensionId: 7},
          'ui': {'developer_mode': true},
        },
      },
    ]) {
      test(
        'does not replace malformed nested Preferences: $malformed',
        () async {
          final home = makeHome([]);
          addTearDown(() => home.deleteSync(recursive: true));
          final extension = makeExtension(home);
          writePreferences(home, relative, malformed);
          final file = File('${home.path}/$relative');
          final before = file.readAsBytesSync();
          final result = await BrowserExtensionInstaller.install(
            isReleaseBuild: true,
            configHome: '${home.path}/.config',
            extensionDirectory: extension.path,
            isBrowserRunning: (_) => false,
          );
          expect(result.installed, isEmpty);
          expect(result.skipped.single.status, ExtensionStatus.needsRepair);
          expect(file.readAsBytesSync(), before);
        },
      );
    }

    for (final disabled in <Map<String, dynamic>>[
      {
        'state': 0,
        'disable_reasons': [1],
      },
      {'state': 0, 'disable_reasons': 1},
      {
        'state': 1,
        'disable_reasons': [1],
      },
      {'state': 1, 'disable_reasons': 1},
    ]) {
      for (final stale in [false, true]) {
        test(
          'preserves disabled extension $disabled, stale path: $stale',
          () async {
            final home = makeHome([]);
            addTearDown(() => home.deleteSync(recursive: true));
            final extension = makeExtension(home);
            final prefs = developerPreferences();
            prefs['extensions']['settings'][BrowserExtensionInstaller
                .chromeExtensionId] = {
              'path': stale ? '/opt/gone/extension' : extension.path,
              'location': 4,
              ...disabled,
            };
            writePreferences(home, relative, prefs);
            final file = File('${home.path}/$relative');
            final before = file.readAsBytesSync();
            final statuses = await BrowserExtensionInstaller.inspect(
              configHome: '${home.path}/.config',
            );
            expect(statuses.single.status, ExtensionStatus.needsUserAction);
            final result = await BrowserExtensionInstaller.install(
              isReleaseBuild: true,
              configHome: '${home.path}/.config',
              extensionDirectory: extension.path,
              isBrowserRunning: (_) => false,
            );
            expect(result.installed, isEmpty);
            expect(result.alreadyInstalled, isEmpty);
            expect(
              result.skipped.single.status,
              ExtensionStatus.needsUserAction,
            );
            expect(file.readAsBytesSync(), before);
          },
        );
      }
    }

    for (final devMode in [null, false]) {
      for (final existing in [false, true]) {
        test(
          'requires user to enable developer mode: $devMode, existing: $existing',
          () async {
            final home = makeHome([]);
            addTearDown(() => home.deleteSync(recursive: true));
            final extension = makeExtension(home);
            final prefs = developerPreferences();
            prefs['extensions']['ui'] = devMode == null
                ? {}
                : {'developer_mode': devMode};
            if (existing) {
              prefs['extensions']['settings'][BrowserExtensionInstaller
                  .chromeExtensionId] = {
                'path': extension.path,
                'state': 1,
                'location': 4,
              };
            }
            writePreferences(home, relative, prefs);
            final file = File('${home.path}/$relative');
            final before = file.readAsBytesSync();
            final result = await BrowserExtensionInstaller.install(
              isReleaseBuild: true,
              configHome: '${home.path}/.config',
              extensionDirectory: extension.path,
              isBrowserRunning: (_) => false,
            );
            expect(result.installed, isEmpty);
            expect(result.alreadyInstalled, isEmpty);
            expect(
              result.skipped.single.status,
              ExtensionStatus.needsUserAction,
            );
            expect(file.readAsBytesSync(), before);
          },
        );
      }
    }

    test(
      'atomically replaces Preferences without mutating another hard link',
      () async {
        final home = makeHome([]);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        writePreferences(home, relative, developerPreferences());
        final file = File('${home.path}/$relative');
        final before = file.readAsBytesSync();
        final backup = File('${file.path}.backup');
        final link = await Process.run('/usr/bin/ln', [file.path, backup.path]);
        expect(link.exitCode, 0);
        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          configHome: '${home.path}/.config',
          extensionDirectory: extension.path,
          isBrowserRunning: (_) => false,
        );
        expect(result.installed, hasLength(1));
        expect(backup.readAsBytesSync(), before);
        expect(
          readPreferences(
            home,
            relative,
          )['extensions']['settings'][BrowserExtensionInstaller
              .chromeExtensionId]['path'],
          extension.path,
        );
        expect(
          file.parent.listSync().map((e) => p.basename(e.path)),
          unorderedEquals(['Preferences', 'Preferences.backup']),
        );
      },
      skip: !Platform.isLinux,
    );

    for (final config in ['google-chrome', 'microsoft-edge', 'vivaldi']) {
      test(
        'default guard detects SingletonLock in $config user data directory',
        () async {
          final home = makeHome([]);
          addTearDown(() => home.deleteSync(recursive: true));
          final extension = makeExtension(home);
          final profile = '.config/$config/Profile 1/Preferences';
          writePreferences(home, profile, developerPreferences());
          final file = File('${home.path}/$profile');
          final before = file.readAsBytesSync();
          Link('${home.path}/.config/$config/SingletonLock')
              .createSync('host-99999999');
          final result = await BrowserExtensionInstaller.install(
            isReleaseBuild: true,
            configHome: '${home.path}/.config',
            extensionDirectory: extension.path,
          );
          expect(result.installed, isEmpty);
          expect(result.skipped.single.status, ExtensionStatus.browserRunning);
          expect(file.readAsBytesSync(), before);
        },
        skip: !Platform.isLinux,
      );
    }

    for (final (config, comm) in [
      ('google-chrome', 'chrome'),
      ('microsoft-edge', 'msedge'),
      ('vivaldi', 'vivaldi-bin'),
    ]) {
      test('default guard detects real process comm $comm', () async {
        final home = makeHome([]);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        final profile = '.config/$config/Default/Preferences';
        writePreferences(home, profile, developerPreferences());
        final file = File('${home.path}/$profile');
        final before = file.readAsBytesSync();
        // Ubuntu 25.10+ ships uutils coreutils, where /usr/bin/sleep is a
        // multicall binary that rejects unknown argv[0] names such as "chrome".
        // A shebang script sets /proc/<pid>/comm to its filename on execve and
        // stays in that process via shell builtins until stdin closes.
        final binary = File('${home.path}/$comm')
          ..writeAsStringSync('#!/bin/sh\nprintf \'ready\\n\'\nread _\n');
        final chmod = await Process.run('chmod', ['+x', binary.path]);
        expect(chmod.exitCode, 0);
        final process = await Process.start(binary.path, const []);
        addTearDown(() async {
          process.kill();
          await process.exitCode;
        });
        await process.stdout.first;
        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          configHome: '${home.path}/.config',
          extensionDirectory: extension.path,
        );
        expect(result.installed, isEmpty);
        expect(result.skipped.single.status, ExtensionStatus.browserRunning);
        expect(file.readAsBytesSync(), before);
      }, skip: !Platform.isLinux);
    }
  });

  group('Windows profiles', () {
    test('finds profiles below LOCALAPPDATA', () async {
      // Chrome and Edge on Windows keep their profiles under
      // %LOCALAPPDATA%, not %APPDATA% and not ~/.config. The installer has
      // to look there, or the one-click step does nothing on Windows.
      final home = makeHome([
        'Local/Google/Chrome/User Data/Default',
        'Local/Microsoft/Edge/User Data/Default',
        'Roaming/Mozilla/Firefox',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      writePreferences(
        home,
        'Local/Google/Chrome/User Data/Default/Preferences',
        {},
      );
      writePreferences(
        home,
        'Local/Microsoft/Edge/User Data/Default/Preferences',
        {},
      );

      final statuses = await BrowserExtensionInstaller.inspect(
        isWindows: true,
        localAppData: '${home.path}/Local',
      );

      expect(statuses.map((s) => s.browserId), ['chrome', 'edge']);
      expect(
        statuses.every((s) => s.status == ExtensionStatus.notInstalled),
        isTrue,
      );
    });

    test('does not seed Preferences on Windows', () async {
      // Chrome enforces the HMAC on `extensions.settings` on Windows
      // (chrome_pref_service_factory.cc: GROUP_ENFORCE_DEFAULT on IS_WIN,
      // so the tracked pref is ENFORCE_ON_LOAD), and an entry without a
      // matching split HMAC is a CHANGED_HMAC — reset on load. Writing it
      // anyway would report "installed" for an entry Chrome deletes, so the
      // one-click path stops at a user action there.
      final home = makeHome(['Local/Google/Chrome/User Data/Default']);
      addTearDown(() => home.deleteSync(recursive: true));
      final extension = makeExtension(home);
      writePreferences(
        home,
        'Local/Google/Chrome/User Data/Default/Preferences',
        {},
      );

      final result = await BrowserExtensionInstaller.install(
        isReleaseBuild: true,
        isWindows: true,
        localAppData: '${home.path}/Local',
        extensionDirectory: extension.path,
        isBrowserRunning: (_) => false,
      );

      expect(result.installed, isEmpty);
      expect(result.skipped.single.status, ExtensionStatus.needsUserAction);
      expect(result.skipped.single.browserId, 'chrome');
      expect(
        readPreferences(
          home,
          'Local/Google/Chrome/User Data/Default/Preferences',
        )['extensions'],
        isNull,
        reason: 'Preferences must be left untouched',
      );
    });

    test(
      'reports Linux-only seeding as unavailable, not as installed',
      () async {
        final home = makeHome([
          'Local/Google/Chrome/User Data/Default',
          'Local/Microsoft/Edge/User Data/Default',
        ]);
        addTearDown(() => home.deleteSync(recursive: true));
        final extension = makeExtension(home);
        for (final relative in [
          'Local/Google/Chrome/User Data/Default/Preferences',
          'Local/Microsoft/Edge/User Data/Default/Preferences',
        ]) {
          writePreferences(home, relative, {});
        }

        final result = await BrowserExtensionInstaller.install(
          isReleaseBuild: true,
          isWindows: true,
          localAppData: '${home.path}/Local',
          extensionDirectory: extension.path,
          isBrowserRunning: (_) => false,
        );

        expect(result.skipped.map((s) => s.browserId), ['chrome', 'edge']);
        expect(
          result.skipped.every(
            (s) => s.status == ExtensionStatus.needsUserAction,
          ),
          isTrue,
        );
      },
    );
  });
}
