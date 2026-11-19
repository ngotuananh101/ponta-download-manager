import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/app/browser_integration_dialog.dart';
import 'package:pdm/core/services/browser_extension_installer.dart';
import 'package:pdm/core/services/browser_integration_service.dart';
import 'package:pdm/shared/theme/app_theme.dart';

Directory makeHome(List<String> dirs) {
  final home = Directory.systemTemp.createTempSync('pdm-dialog-');
  for (final path in dirs) {
    Directory('${home.path}/$path').createSync(recursive: true);
  }
  return home;
}

void seedProfile(Directory home, String relative, {bool installed = false}) {
  final file = File('${home.path}/$relative/Preferences');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    installed
        ? '{'
              '"extensions": {"settings": {"'
              '${BrowserExtensionInstaller.chromeExtensionId}": {'
              '"path": "${home.path}/app/extension", "location": 4, "state": 1'
              '}}, "ui": {"developer_mode": true}}}'
        : '{"extensions":{"ui":{"developer_mode":true}}}',
  );
}

void makeExtension(Directory home) {
  final manifest = File('${home.path}/app/extension/manifest.json');
  manifest.parent.createSync(recursive: true);
  manifest.writeAsStringSync('{"manifest_version": 3}');
}

Future<void> pumpDialog(
  WidgetTester tester, {
  required BrowserIntegrationSnapshot snapshot,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        browserIntegrationStatusProvider.overrideWith((ref) async => snapshot),
      ],
      child: MaterialApp(
        // The app's own theme, not the Material default: tapping a button
        // in the default Material 3 theme loads the ink-sparkle shader,
        // which is not in the test asset bundle.
        theme: AppTheme.light,
        home: const Scaffold(body: BrowserIntegrationDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('real setup retains Windows manual action and host failure', () async {
    final home = makeHome(['local/Google/Chrome/User Data/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, 'local/Google/Chrome/User Data/Default');
    final snapshot = await loadBrowserIntegrationSnapshot(
      programDirectory: '${home.path}/app',
      configHome: '${home.path}/.config',
      homeDir: home.path,
      localAppData: '${home.path}/local',
      appData: '${home.path}/roaming',
      isWindows: true,
      isReleaseBuild: true,
    );
    expect(snapshot.statuses.single.status, ExtensionStatus.needsUserAction);
    expect(snapshot.hostRegistration!.registered, isEmpty);
    expect(snapshot.hostRegistration!.reason, contains('not found'));
  });

  test('real setup retains running-browser status', () async {
    final home = makeHome(['.config/google-chrome/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, '.config/google-chrome/Default');
    final snapshot = await loadBrowserIntegrationSnapshot(
      programDirectory: '${home.path}/app',
      homeDir: home.path,
      configHome: '${home.path}/.config',
      isWindows: false,
      isReleaseBuild: true,
      isBrowserRunning: (_) => true,
    );
    expect(snapshot.statuses.single.status, ExtensionStatus.browserRunning);
  });

  test('real setup registers a newly detected browser on retry', () async {
    final home = makeHome(['.config/google-chrome/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, '.config/google-chrome/Default');
    File('${home.path}/app/bin/pdm-native-host').createSync(recursive: true);
    Future<BrowserIntegrationSnapshot> load() => loadBrowserIntegrationSnapshot(
      programDirectory: '${home.path}/app',
      homeDir: home.path,
      configHome: '${home.path}/.config',
      isWindows: false,
      isReleaseBuild: true,
      isBrowserRunning: (_) => false,
    );
    await load();
    seedProfile(home, '.config/chromium/Default');
    final result = await load();
    expect(
      result.hostRegistration!.registered.map((b) => b.id),
      containsAll(['chrome', 'chromium']),
    );
    final host = jsonDecode(
      File(
        '${home.path}/.config/chromium/NativeMessagingHosts/com.ponta.pdm.json',
      ).readAsStringSync(),
    );
    expect(host['path'], '${home.path}/app/bin/pdm-native-host');
  });

  test('setup discovers profiles from its supplied environment', () async {
    final home = makeHome(['config/google-chrome/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, 'config/google-chrome/Default');
    File('${home.path}/app/bin/pdm-native-host').createSync(recursive: true);
    final snapshot = await loadBrowserIntegrationSnapshot(
      programDirectory: '${home.path}/app',
      environment: {
        'HOME': home.path,
        'XDG_CONFIG_HOME': '${home.path}/config',
      },
      isWindows: false,
      isReleaseBuild: true,
      isBrowserRunning: (_) => false,
    );
    expect(snapshot.statuses.single.status, ExtensionStatus.installed);
    expect(
      snapshot.statuses.single.profilePath,
      '${home.path}/config/google-chrome/Default',
    );
    expect(snapshot.hostRegistration!.registered.single.id, 'chrome');
    final host = jsonDecode(
      File(
        '${home.path}/config/google-chrome/NativeMessagingHosts/com.ponta.pdm.json',
      ).readAsStringSync(),
    );
    expect(host['path'], '${home.path}/app/bin/pdm-native-host');
  });

  testWidgets('many profiles remain scrollable without overflowing', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      snapshot: BrowserIntegrationSnapshot(
        statuses: [
          for (var i = 0; i < 15; i++)
            BrowserExtensionStatus(
              browserId: 'chrome',
              browserLabel: 'Google Chrome',
              profilePath: '/profile/Profile $i',
              status: ExtensionStatus.browserRunning,
            ),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Check again'), findsOneWidget);
  });

  testWidgets('shows failed native host registration instead of success', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      snapshot: const BrowserIntegrationSnapshot(
        statuses: [],
        hostRegistration: BrowserIntegrationResult(
          registered: [],
          reason: 'host binary missing',
        ),
        setupReason: 'extension directory missing',
      ),
    );
    expect(find.textContaining('host binary missing'), findsOneWidget);
    expect(find.textContaining('extension directory missing'), findsOneWidget);
    expect(find.textContaining('is registered for'), findsNothing);
  });

  testWidgets('lists a browser with the extension as ready', (tester) async {
    final home = makeHome(['.config/google-chrome/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, '.config/google-chrome/Default', installed: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserIntegrationStatusProvider.overrideWith(
            (ref) async => BrowserIntegrationSnapshot(
              statuses: [
                BrowserExtensionStatus(
                  browserId: 'chrome',
                  browserLabel: 'Google Chrome',
                  profilePath: '${home.path}/.config/google-chrome/Default',
                  status: ExtensionStatus.installed,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BrowserIntegrationDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.textContaining('listed as enabled'), findsOneWidget);
    // A resolved browser gets no "do this" instruction.
    expect(find.textContaining('Load unpacked'), findsNothing);
  });

  testWidgets('tells the user what to do on Windows', (tester) async {
    // On Windows Chrome verifies the extension list (HMAC), so the app
    // cannot install it silently. The dialog has to say so, with the two
    // concrete steps, instead of leaving the user with "not installed".
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserIntegrationStatusProvider.overrideWith(
            (ref) async => const BrowserIntegrationSnapshot(
              statuses: [
                BrowserExtensionStatus(
                  browserId: 'chrome',
                  browserLabel: 'Google Chrome',
                  profilePath: r'C:\Users\me\AppData\Local\Google\Chrome\User Data\Default',
                  status: ExtensionStatus.needsUserAction,
                ),
              ],
              manualSteps:
                  'Open chrome://extensions, enable Developer mode, '
                  r'then Load unpacked: C:\Program Files\Ponta Download Manager\extension',
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BrowserIntegrationDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('chrome://extensions'), findsOneWidget);
    expect(find.textContaining('Load unpacked'), findsOneWidget);
  });

  testWidgets('offers a retry that re-runs the install', (tester) async {
    final home = makeHome(['.config/google-chrome/Default']);
    addTearDown(() => home.deleteSync(recursive: true));
    makeExtension(home);
    seedProfile(home, '.config/google-chrome/Default');
    var reads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          browserIntegrationStatusProvider.overrideWith((ref) async {
            reads++;
            if (reads == 1) {
              return BrowserIntegrationSnapshot(
                statuses: [
                  BrowserExtensionStatus(
                    browserId: 'chrome',
                    browserLabel: 'Google Chrome',
                    profilePath: '${home.path}/.config/google-chrome/Default',
                    status: ExtensionStatus.browserRunning,
                  ),
                ],
              );
            }
            return BrowserIntegrationSnapshot(
              statuses: [
                BrowserExtensionStatus(
                  browserId: 'chrome',
                  browserLabel: 'Google Chrome',
                  profilePath: '${home.path}/.config/google-chrome/Default',
                  status: ExtensionStatus.installed,
                ),
              ],
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: BrowserIntegrationDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Close the browser'), findsOneWidget);

    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();

    expect(reads, greaterThan(1));
    expect(find.textContaining('listed as enabled'), findsOneWidget);
  });

  testWidgets('shows the native host state', (tester) async {
    await pumpDialog(
      tester,
      snapshot: const BrowserIntegrationSnapshot(
        statuses: [],
        hostPath: '/opt/pdm/bin/pdm-native-host',
      ),
    );

    // The dialog always names the host, so "the extension is installed but
    // the host is not registered" is visible instead of a silent no-op
    // download button in the popup.
    expect(find.textContaining('com.ponta.pdm'), findsOneWidget);
  });
}
