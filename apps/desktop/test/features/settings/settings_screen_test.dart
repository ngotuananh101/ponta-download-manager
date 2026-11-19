import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/core/services/browser_extension_installer.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/downloads/presentation/screens/downloads_screen.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/features/settings/app_settings.dart';
import 'package:pdm/features/settings/browser_integration.dart';
import 'package:pdm/features/settings/settings_screen.dart';
import 'package:pdm/shared/theme/app_theme.dart';

void main() {
  late Directory temp;
  late FileConflictSettings store;
  late BrowserIntegrationSnapshot snapshot;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('pdm-settings-ui-');
    store = FileConflictSettings(filePath: '${temp.path}/settings.json');
    snapshot = const BrowserIntegrationSnapshot(
      statuses: [
        BrowserExtensionStatus(
          browserId: 'chrome',
          browserLabel: 'Google Chrome',
          profilePath: '/profile/Default',
          status: ExtensionStatus.installed,
        ),
      ],
    );
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester, {bool downloads = false,
      Future<String?> Function()? picker}) async {
    if (downloads) {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(ProviderScope(overrides: [
      fileConflictSettingsProvider.overrideWithValue(store),
      downloadDirectoryResolverProvider.overrideWithValue(() => '${temp.path}/os'),
      directoryPickerProvider.overrideWithValue(picker ?? () async => null),
      dropTargetEnabledProvider.overrideWithValue(false),
      downloadsProvider.overrideWith((ref) => Stream.value([])),
      browserIntegrationStatusProvider.overrideWith((ref) async => snapshot),
    ], child: MaterialApp(theme: AppTheme.dark,
      home: downloads ? const DownloadsScreen() : Scaffold(body: Builder(
        builder: (context) => TextButton(onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          child: const Text('Open settings')))),
    )));
    await tester.pumpAndSettle();
    if (downloads) {
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
    } else {
      await tester.tap(find.text('Open settings'));
    }
    await tester.pumpAndSettle();
  }

  Future<void> chooseSection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('menu opens settings and saving edited limits persists them', (tester) async {
    await open(tester, downloads: true);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '5');
    await tester.enterText(find.byKey(const Key('connections-per-download')), '16');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.loadSettings().maxConcurrentDownloads, 5);
    expect(store.loadSettings().maxConnectionsPerDownload, 16);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('prefill, cancelled picker, and Cancel leave settings unchanged', (tester) async {
    store.saveSettings(AppSettings(downloadDirectory: temp.path,
      maxConcurrentDownloads: 7, windowAction: WindowAction.quit));
    await open(tester);
    expect(tester.widget<TextFormField>(find.byKey(const Key('concurrent-downloads')))
      .controller!.text, '7');
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('download-folder')))
      .controller!.text, temp.path);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '10');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.loadSettings().maxConcurrentDownloads, 7);
  });

  testWidgets('invalid limits cannot persist and errors stay visible', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '0');
    await tester.enterText(find.byKey(const Key('connections-per-download')), '1.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an integer from 1 to 32'), findsNWidgets(2));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(File('${temp.path}/settings.json').existsSync(), isFalse);
  });

  testWidgets('invalid download field blocks Save from another section', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '0');
    await chooseSection(tester, 'System');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // Back on Downloads, with the error visible and nothing written.
    expect(find.text('Enter an integer from 1 to 32'), findsOneWidget);
    expect(File('${temp.path}/settings.json').existsSync(), isFalse);
  });

  testWidgets('failed save retains draft and reports the write error', (tester) async {
    final blocked = '${temp.path}/blocked';
    Directory(blocked).createSync();
    store = FileConflictSettings(filePath: blocked);
    await open(tester);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '9');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save settings'), findsOneWidget);
    await chooseSection(tester, 'System');
    // The error belongs to the whole screen, not the Downloads section.
    expect(find.textContaining('Could not save settings'), findsOneWidget);
    await chooseSection(tester, 'Downloads');
    expect(tester.widget<TextFormField>(find.byKey(const Key('concurrent-downloads')))
      .controller!.text, '9');
  });

  testWidgets('the sidebar switches sections without losing the draft',
      (tester) async {
    tester.view.physicalSize = const Size(950, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    expect(find.text('Default download folder'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '9');

    await chooseSection(tester, 'System');
    expect(find.text('Default download folder'), findsNothing);
    expect(find.text('Launch at system startup'), findsOneWidget);
    expect(find.text('Initial window state'), findsOneWidget);

    await chooseSection(tester, 'Downloads');
    expect(tester.widget<TextFormField>(find.byKey(const Key('concurrent-downloads')))
      .controller!.text, '9');
  });

  testWidgets('the delete action is a Downloads preference and persists',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('When deleting a download'));
    await tester.pumpAndSettle();
    expect(find.text('When deleting a download'), findsOneWidget);
    await tester.ensureVisible(find.text('Always ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete the file on disk too').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.loadSettings().deleteAction, DeleteAction.deleteFile);
  });

  testWidgets('saving from System persists download fields edited earlier',
      (tester) async {
    await open(tester);
    // The whole form validates together, whichever section Save is shown on.
    await tester.enterText(find.byKey(const Key('concurrent-downloads')), '6');
    await chooseSection(tester, 'System');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.loadSettings().maxConcurrentDownloads, 6);
  });

  testWidgets('Browser integration is a settings section with a retry',
      (tester) async {
    await open(tester);
    await chooseSection(tester, 'Browser integration');
    expect(find.byType(BrowserIntegrationSection), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Google Chrome'), findsOneWidget);
    expect(find.textContaining('listed as enabled'), findsOneWidget);
  });

  testWidgets('short narrow screen collapses the sidebar and Back discards the draft',
      (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    expect(tester.takeException(), isNull);
    // Too narrow for labels: the sidebar is an icon rail, so move to System
    // through the title instead of tapping hidden text.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
    expect(File('${temp.path}/settings.json').existsSync(), isFalse);
  });
}
