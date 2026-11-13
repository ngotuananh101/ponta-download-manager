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
}
