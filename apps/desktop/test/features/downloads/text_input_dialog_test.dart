import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/features/downloads/presentation/text_input_dialog.dart';
import 'package:pdm/shared/theme/app_theme.dart';

Future<void> openDialog(
  WidgetTester tester, {
  required void Function(String?) onResult,
  String? Function(String value)? validate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            onResult(
              await showTextInputDialog(
                context: context,
                title: 'Rename file',
                label: 'File name',
                initialValue: 'f.bin',
                validate: validate,
              ),
            );
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the initial value and returns the typed text',
      (tester) async {
    String? result;
    await openDialog(tester, onResult: (v) => result = v);
    expect(find.text('Rename file'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'f.bin');
    await tester.enterText(find.byType(TextField), 'g.bin');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(result, 'g.bin');
  });

  testWidgets('OK does nothing when the value is empty', (tester) async {
    String? result = 'unset';
    await openDialog(tester, onResult: (v) => result = v);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The dialog stays open and nothing is returned.
    expect(find.text('Rename file'), findsOneWidget);
    expect(result, 'unset');
  });

  testWidgets('shows the validation error and keeps OK disabled',
      (tester) async {
    String? result = 'unset';
    await openDialog(
      tester,
      onResult: (v) => result = v,
      validate: (v) =>
          v.contains('/') ? 'A file name cannot contain /' : null,
    );
    await tester.enterText(find.byType(TextField), 'sub/g.bin');
    await tester.pump();
    expect(find.text('A file name cannot contain /'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Rename file'), findsOneWidget);
    expect(result, 'unset');
  });

  testWidgets('Cancel returns null', (tester) async {
    String? result = 'unset';
    await openDialog(tester, onResult: (v) => result = v);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
