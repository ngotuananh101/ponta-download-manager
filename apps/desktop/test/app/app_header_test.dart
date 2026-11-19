import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/app/app_header.dart';

void main() {
  testWidgets('AppHeader shows the title and window controls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );

    expect(find.text('Ponta Download Manager'), findsOneWidget);
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('AppHeader keeps the window controls at the right edge',
      (tester) async {
    tester.view.physicalSize = const Size(950, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();

    // The brand must not reserve flex space after the buttons: a loose
    // Flexible in front of the drag area left a gap between Close and the
    // window edge.
    expect(tester.getRect(find.byType(AppHeader)).right, 950);
    expect(tester.getRect(find.byTooltip('Close')).right, 950);
    expect(tester.getRect(find.byTooltip('Minimize')).left,
        950 - kWindowCaptionButtonWidth * 3);
  });

  testWidgets('AppHeader ellipsizes the brand in a narrow window',
      (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byTooltip('Close')).right, 420);
  });
}
