import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/core/services/browser_integration_service.dart';

/// A temp HOME with the given dirs already present, the way a machine looks
/// after each browser has been run at least once.
Directory makeHome(List<String> dirs) {
  final home = Directory.systemTemp.createTempSync('pdm-home-');
  for (final path in dirs) {
    Directory('${home.path}/$path').createSync(recursive: true);
  }
  return home;
}

/// Creates the bundled host the way an install does, so the "is the binary
/// there?" guard passes.
String plantHost(Directory home, {String name = 'pdm-native-host'}) {
  final file = File('${home.path}/app/bin/$name');
  file.createSync(recursive: true);
  return file.path;
}

String manifestPathFor(Directory home, String relative) =>
    '${home.path}/$relative';

String readManifest(Directory home, String relative) =>
    File(manifestPathFor(home, relative)).readAsStringSync();

void main() {
  test(
    'AppImage assets stay usable after the mount directory disappears',
    () async {
      final home = makeHome(['mount/bin', 'mount/extension/icons']);
      addTearDown(() => home.deleteSync(recursive: true));
      File('${home.path}/mount/bin/pdm-native-host')
          .writeAsStringSync('host executable');
      File('${home.path}/mount/extension/manifest.json')
          .writeAsStringSync('{"manifest_version":3}');
      File('${home.path}/mount/extension/icons/icon.png')
          .writeAsStringSync('icon');
      final paths = await BrowserIntegrationService.prepareBundlePaths(
        programDirectory: '${home.path}/mount',
        isWindows: false,
        environment: {
          'APPIMAGE': '${home.path}/pdm.AppImage',
          'XDG_DATA_HOME': '${home.path}/data',
          'HOME': home.path,
        },
        isReleaseBuild: true,
      );
      Directory('${home.path}/mount').deleteSync(recursive: true);
      expect(
        paths.hostPath,
        startsWith('${home.path}/data/pdm/browser-integration/'),
      );
      expect(File(paths.hostPath).readAsStringSync(), 'host executable');
      expect(
        File('${paths.extensionPath}/icons/icon.png').readAsStringSync(),
        'icon',
      );
      final executable = await Process.run('test', ['-x', paths.hostPath]);
      expect(executable.exitCode, 0);
    },
  );

  test('AppImage staging leaves identical assets untouched', () async {
    final home = makeHome(['mount/bin', 'mount/extension']);
    addTearDown(() => home.deleteSync(recursive: true));
    File('${home.path}/mount/bin/pdm-native-host').writeAsStringSync('host');
    File('${home.path}/mount/extension/manifest.json').writeAsStringSync('{}');
    Future<({String hostPath, String extensionPath})> prepare() =>
        BrowserIntegrationService.prepareBundlePaths(
          programDirectory: '${home.path}/mount',
          isWindows: false,
          environment: {
            'APPIMAGE': '/opt/pdm.AppImage',
            'XDG_DATA_HOME': '${home.path}/data',
          },
          isReleaseBuild: true,
        );
    final paths = await prepare();
    final previous = DateTime.utc(2020);
    await File(paths.hostPath).setLastModified(previous);
    await prepare();
    expect((await File(paths.hostPath).lastModified()).toUtc(), previous);
  });

  test('AppImage staging reports missing source host instead of reusing old assets', () async {
    final home = makeHome([
      'mount/extension',
      'data/pdm/browser-integration/bin',
    ]);
    addTearDown(() => home.deleteSync(recursive: true));
    File('${home.path}/mount/extension/manifest.json').writeAsStringSync('{}');
    File('${home.path}/data/pdm/browser-integration/bin/pdm-native-host')
        .writeAsStringSync('old');
    final paths = await BrowserIntegrationService.prepareBundlePaths(
      programDirectory: '${home.path}/mount',
      isWindows: false,
      environment: {
        'APPIMAGE': '/opt/pdm.AppImage',
        'XDG_DATA_HOME': '${home.path}/data',
      },
      isReleaseBuild: true,
    );
    expect(paths.hostPath, '${home.path}/mount/bin/pdm-native-host');
  });

  test('debug AppImage does not stage integration assets', () async {
    final home = makeHome([]);
    addTearDown(() => home.deleteSync(recursive: true));
    final paths = await BrowserIntegrationService.prepareBundlePaths(
      programDirectory: '${home.path}/mount',
      isWindows: false,
      environment: {'APPIMAGE': '/tmp/pdm.AppImage', 'HOME': home.path},
      isReleaseBuild: false,
    );
    expect(paths.hostPath, '${home.path}/mount/bin/pdm-native-host');
    expect(Directory('${home.path}/.local').existsSync(), isFalse);
  });

  test('empty config home falls back to the user config directory', () async {
    final home = makeHome(['.config/google-chrome']);
    addTearDown(() => home.deleteSync(recursive: true));
    final result = await BrowserIntegrationService.ensureNativeHosts(
      homeDir: home.path,
      configHome: '',
      environment: const {},
      hostBinaryPath: plantHost(home),
      isWindows: false,
      isReleaseBuild: true,
    );
    expect(result.registered.single.id, 'chrome');
    expect(
      File(
        '${home.path}/.config/google-chrome/NativeMessagingHosts/com.ponta.pdm.json',
      ).existsSync(),
      isTrue,
    );
  });

  group('Linux', () {
    test('registers the host for every browser that has been run', () async {
      final home = makeHome([
        '.config/google-chrome',
        '.config/chromium',
        '.config/BraveSoftware/Brave-Browser',
        '.mozilla',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home);

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/.config',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: false,
      );

      expect(
        result.registered.map((t) => t.id),
        containsAll(['chrome', 'chromium', 'brave', 'firefox']),
      );
      expect(result.registered.map((t) => t.id), isNot(contains('edge')));
      expect(result.reason, isNull);

      // A browser that was never run must not be given a config dir: writing
      // into ~/.config/microsoft-edge would make the next Chrome-family
      // browser that looks there think it is installed.
      expect(
        Directory('${home.path}/.config/microsoft-edge').existsSync(),
        isFalse,
      );

      final chrome = jsonDecode(
        readManifest(
          home,
          '.config/google-chrome/NativeMessagingHosts/com.ponta.pdm.json',
        ),
      );
      expect(chrome['name'], 'com.ponta.pdm');
      expect(chrome['type'], 'stdio');
      expect(chrome['path'], host);
      expect(chrome['allowed_origins'], [
        'chrome-extension://${BrowserIntegrationService.chromeExtensionId}/',
      ]);

      final firefox = jsonDecode(
        readManifest(
          home,
          '.mozilla/native-messaging-hosts/com.ponta.pdm.json',
        ),
      );
      expect(firefox['name'], 'com.ponta.pdm');
      expect(firefox['type'], 'stdio');
      expect(firefox['path'], host);
      // A Firefox manifest uses allowed_extensions; allowed_origins there is
      // ignored at best and rejected at worst.
      expect(firefox['allowed_extensions'], ['pdm@ponta.dev']);
      expect(firefox.containsKey('allowed_origins'), isFalse);
    });

    test('honours XDG_CONFIG_HOME instead of assuming ~/.config', () async {
      final home = makeHome(['xdg/google-chrome', 'xdg/vivaldi']);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home);

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/xdg',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: false,
      );

      expect(
        result.registered.map((t) => t.id),
        containsAll(['chrome', 'vivaldi']),
      );
      expect(
        File('${home.path}/xdg/vivaldi/NativeMessagingHosts/com.ponta.pdm.json')
            .existsSync(),
        isTrue,
      );
      expect(
        Directory('${home.path}/.config').existsSync(),
        isFalse,
        reason: 'nothing may be written outside XDG_CONFIG_HOME',
      );
    });

    test('writes the manifest once, then leaves it alone', () async {
      // Every launch re-runs this. Rewriting the file on each start is churn
      // in a directory the browser reads, and it would make "did this install
      // change anything?" impossible to answer from timestamps.
      final home = makeHome(['.config/google-chrome', '.mozilla']);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home);

      Future<BrowserIntegrationResult> run() =>
          BrowserIntegrationService.ensureNativeHosts(
            homeDir: home.path,
            configHome: '${home.path}/.config',
            hostBinaryPath: host,
            isReleaseBuild: true,
            isWindows: false,
          );

      await run();
      final path = manifestPathFor(
        home,
        '.config/google-chrome/NativeMessagingHosts/com.ponta.pdm.json',
      );
      final before = File(path).lastModifiedSync();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final second = await run();

      expect(File(path).lastModifiedSync(), before);
      // "Unchanged" is a success, not a skip: the extension can connect, so
      // the status must not flip to "not installed" on the second launch.
      expect(second.registered.map((t) => t.id), contains('chrome'));
    });

    test('rewrites a manifest that points somewhere else', () async {
      // An old install (or install.sh run by hand) points at
      // ~/.local/bin/pdm-native-host; an upgraded app ships it in the bundle.
      final home = makeHome(['.config/google-chrome']);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home);
      final path = manifestPathFor(
        home,
        '.config/google-chrome/NativeMessagingHosts/com.ponta.pdm.json',
      );
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('{"path": "/old/pdm-native-host"}');

      await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/.config',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: false,
      );

      expect(jsonDecode(File(path).readAsStringSync())['path'], host);
    });

    test('does nothing in a debug build', () async {
      // `flutter run` and `flutter test` are debug builds: registering a host
      // that points into build/ would break as soon as that is cleaned, the
      // same reason LinuxDesktopService only writes its .desktop in release.
      final home = makeHome(['.config/google-chrome', '.mozilla']);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home);

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/.config',
        hostBinaryPath: host,
        isReleaseBuild: false,
        isWindows: false,
      );

      expect(result.registered, isEmpty);
      expect(result.reason, isNotNull);
      expect(
        Directory('${home.path}/.config/google-chrome/NativeMessagingHosts')
            .existsSync(),
        isFalse,
      );
    });

    test(
      'skips registration when the bundled host binary is missing',
      () async {
        // The host is compiled into the bundle by the release build. A bundle
        // without it can still run the app; it just has no browser integration,
        // and must not leave a manifest pointing at nothing.
        final home = makeHome(['.config/google-chrome']);
        addTearDown(() => home.deleteSync(recursive: true));

        final result = await BrowserIntegrationService.ensureNativeHosts(
          homeDir: home.path,
          configHome: '${home.path}/.config',
          hostBinaryPath: '${home.path}/missing/pdm-native-host',
          isReleaseBuild: true,
          isWindows: false,
        );

        expect(result.registered, isEmpty);
        expect(result.reason, contains('pdm-native-host'));
        expect(
          Directory('${home.path}/.config/google-chrome/NativeMessagingHosts')
              .existsSync(),
          isFalse,
        );
      },
    );
  });

  group('Windows', () {
    test('points every installed browser at one manifest through HKCU', () async {
      // The registry is per-user, so this needs no admin rights and works
      // whether the app was installed per-machine or per-user.
      final home = makeHome([
        'AppData/Local/pdm',
        'AppData/Local/Google/Chrome/User Data',
        'AppData/Local/Microsoft/Edge/User Data',
        'AppData/Roaming/Mozilla/Firefox',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home, name: 'pdm-native-host.exe');
      final calls = <List<String>>[];

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/AppData/Roaming',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: true,
        localAppData: '${home.path}\\AppData\\Local',
        appData: '${home.path}\\AppData\\Roaming',
        runProcess: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(
        result.registered.map((t) => t.id),
        containsAll(['chrome', 'edge', 'firefox']),
      );
      expect(result.registered.map((t) => t.id), isNot(contains('brave')));

      // One manifest per family; each registry key points at its family's
      // file, because the two shapes differ (allowed_origins vs
      // allowed_extensions) and neither browser accepts the other's.
      final chromiumManifest =
          '${home.path}\\AppData\\Local\\pdm\\com.ponta.pdm.json';
      final firefoxManifest =
          '${home.path}\\AppData\\Local\\pdm\\firefox\\com.ponta.pdm.json';
      expect(
        jsonDecode(
          File(chromiumManifest.replaceAll('\\', '/')).readAsStringSync(),
        )['path'],
        host,
      );
      expect(
        jsonDecode(
          File(firefoxManifest.replaceAll('\\', '/')).readAsStringSync(),
        )['allowed_extensions'],
        ['pdm@ponta.dev'],
      );

      final byKey = {for (final call in calls) call[2]: call};
      expect(byKey.keys, [
        'HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts\\com.ponta.pdm',
        'HKCU\\Software\\Microsoft\\Edge\\NativeMessagingHosts\\com.ponta.pdm',
        'HKCU\\Software\\Mozilla\\NativeMessagingHosts\\com.ponta.pdm',
      ]);
      for (final call in byKey.values) {
        expect(call.first, 'reg');
        expect(call[1], 'add');
        expect(call, contains('/ve'));
        expect(call, contains('REG_SZ'));
        expect(call, contains('/f'));
        expect(call.last, '/f');
      }
      expect(
        byKey['HKCU\\Software\\Google\\Chrome\\NativeMessagingHosts\\com.ponta.pdm'],
        contains(chromiumManifest),
      );
      expect(
        byKey['HKCU\\Software\\Microsoft\\Edge\\NativeMessagingHosts\\com.ponta.pdm'],
        contains(chromiumManifest),
      );
      expect(
        byKey['HKCU\\Software\\Mozilla\\NativeMessagingHosts\\com.ponta.pdm'],
        contains(firefoxManifest),
      );
    });

    test('leaves browsers that are not installed alone', () async {
      final home = makeHome([
        'AppData/Local/pdm',
        'AppData/Local/Google/Chrome/User Data',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home, name: 'pdm-native-host.exe');
      final calls = <List<String>>[];

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}/AppData/Roaming',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: true,
        localAppData: '${home.path}\\AppData\\Local',
        appData: '${home.path}\\AppData\\Roaming',
        runProcess: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(result.registered.map((t) => t.id), ['chrome']);
      expect(calls, hasLength(1));
    });

    test('reports a registry failure instead of claiming success', () async {
      final home = makeHome([
        'AppData/Local/pdm',
        'AppData/Local/Google/Chrome/User Data',
      ]);
      addTearDown(() => home.deleteSync(recursive: true));
      final host = plantHost(home, name: 'pdm-native-host.exe');

      final result = await BrowserIntegrationService.ensureNativeHosts(
        homeDir: home.path,
        configHome: '${home.path}\\AppData\\Roaming',
        hostBinaryPath: host,
        isReleaseBuild: true,
        isWindows: true,
        localAppData: '${home.path}\\AppData\\Local',
        appData: '${home.path}\\AppData\\Roaming',
        runProcess: (executable, args) async =>
            ProcessResult(1, 1, '', 'Access is denied.'),
      );

      expect(result.registered, isEmpty);
      expect(result.reason, contains('Access is denied'));
    });
  });

  test('ships the extension folder next to the program', () {
    expect(
      BrowserIntegrationService.extensionDirectory(
        '/opt/pdm',
        isWindows: false,
      ),
      '/opt/pdm/extension',
    );
    expect(
      BrowserIntegrationService.extensionDirectory(
        r'C:\Program Files\Ponta Download Manager',
        isWindows: true,
      ),
      r'C:\Program Files\Ponta Download Manager\extension',
    );
  });

  test('finds the host binary in the bundle', () {
    // CMake installs the contents of bundle/bin into <bundle>/bin, so the
    // host lands beside ffmpeg and yt-dlp rather than next to pdm itself.
    expect(
      BrowserIntegrationService.hostBinaryPath('/opt/pdm', false),
      '/opt/pdm/bin/pdm-native-host',
    );
    expect(
      BrowserIntegrationService.hostBinaryPath(
        r'C:\Program Files\Ponta Download Manager',
        true,
      ),
      r'C:\Program Files\Ponta Download Manager\bin\pdm-native-host.exe',
    );
  });

  test('the pinned id matches the key in the extension manifest', () {
    // The manifest's public `key` is what makes the id the same on every
    // machine; the host manifest whitelists that id. If someone regenerates
    // the key without updating the constant, every browser silently rejects
    // the connection, so the two are checked against each other.
    final manifest = _findRepoFile(
      'integrations/browser-extension/extension/manifest.json',
    );
    final json =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final der = base64Decode(json['key'] as String);
    final digest = sha256.convert(der).bytes;
    final id = digest
        .take(16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .split('')
        .map(
          (c) =>
              String.fromCharCode('a'.codeUnitAt(0) + int.parse(c, radix: 16)),
        )
        .join();
    expect(id, BrowserIntegrationService.chromeExtensionId);
  });
}

/// `flutter test` runs with the package directory or the workspace root as
/// the working directory depending on how it was invoked; walk up from both
/// until the file shows up.
File _findRepoFile(String relative) {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = File(p.join(dir.path, relative));
    if (candidate.existsSync()) return candidate;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  fail('$relative not found above ${Directory.current.path}');
}
