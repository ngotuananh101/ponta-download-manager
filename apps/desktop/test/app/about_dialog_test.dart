import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/app/about_dialog.dart';
import 'package:pdm/app/build_info.dart';
import 'package:pdm/shared/theme/app_theme.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

Future<void> openAbout(WidgetTester tester, BuildInfo info) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showPdmAboutDialog(context: context, buildInfo: info),
      child: const Text('Open About'),
    ))),
  ));
  await tester.tap(find.text('Open About'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('About identifies project and developer with selectable URLs',
      (tester) async {
    await openAbout(tester, const BuildInfo());
    for (final text in [
      'Ponta Download Manager', 'Version 0.1.0', 'Project', 'Developer',
      'Ngo Tuan Anh', 'ngotuananh101', 'Windows and Linux',
      'Flutter / Dart / SQLite',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.widgetWithText(SelectableText,
      'https://github.com/ngotuananh101'), findsOneWidget);
    expect(find.widgetWithText(SelectableText,
      'https://github.com/ngotuananh101/ponta-download-manager'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('development keeps both build rows with development values',
      (tester) async {
    await openAbout(tester, const BuildInfo(
      isDevelopment: true, commit: 'should-not-show', buildTime: 'should-not-show',
    ));
    expect(find.text('Commit'), findsOneWidget);
    expect(find.text('Build time'), findsOneWidget);
    expect(find.text('Development mode'), findsNWidgets(2));
    expect(find.text('should-not-show'), findsNothing);
  });

  testWidgets('release exposes selectable source SHA and build time',
      (tester) async {
    await openAbout(tester, const BuildInfo(
      isDevelopment: false,
      commit: '6440356c876e5a303bf53e83978730d21223e7e1',
      buildTime: '2026-11-19T02:00:00Z',
    ));
    expect(find.widgetWithText(SelectableText,
      '6440356c876e5a303bf53e83978730d21223e7e1'), findsOneWidget);
    expect(find.widgetWithText(SelectableText,
      '2026-11-19T02:00:00Z'), findsOneWidget);
    expect(find.text('Development mode'), findsNothing);
  });

  testWidgets('unstamped release shows unavailable metadata', (tester) async {
    await openAbout(tester, const BuildInfo(
      isDevelopment: false, commit: '', buildTime: '',
    ));
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('Development mode'), findsNothing);
  });

  testWidgets('long metadata fits a short narrow window and Close works',
      (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openAbout(tester, const BuildInfo(
      isDevelopment: false,
      commit: '6440356c876e5a303bf53e83978730d21223e7e1 (dirty)',
      buildTime: '2026-11-19T02:00:00Z',
    ));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Build time'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PdmDialog), findsNothing);
  });
}
