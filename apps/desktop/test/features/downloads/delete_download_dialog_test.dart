import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/presentation/delete_download_dialog.dart';
import 'package:pdm/shared/theme/app_theme.dart';

Future<void> openDialog(
  WidgetTester tester, {
  int count = 1,
  String? fileName = 'f.bin',
  required void Function(DeleteDownloadDecision?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            onResult(
              await showDeleteDownloadDialog(
                context: context,
                count: count,
                fileName: fileName,
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
  testWidgets('shows the file name and an unchecked delete-file box',
      (tester) async {
    DeleteDownloadDecision? decision;
    await openDialog(tester, onResult: (d) => decision = d);
    expect(find.text('Delete download'), findsOneWidget);
    expect(find.text('Delete "f.bin"?'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isFalse);
    expect(decision, isNull);
  });

  testWidgets('Delete keeps the file when the box is unchecked',
      (tester) async {
    DeleteDownloadDecision? decision;
    await openDialog(tester, onResult: (d) => decision = d);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(decision, isNotNull);
    expect(decision!.deleteFile, isFalse);
  });

  testWidgets('Delete deletes the file when the box is checked',
      (tester) async {
    DeleteDownloadDecision? decision;
    await openDialog(tester, onResult: (d) => decision = d);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(decision, isNotNull);
    expect(decision!.deleteFile, isTrue);
  });

  testWidgets('Cancel returns null', (tester) async {
    DeleteDownloadDecision? decision;
    await openDialog(tester, onResult: (d) => decision = d);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(decision, isNull);
  });

  testWidgets('bulk delete names the count and the plural box label',
      (tester) async {
    DeleteDownloadDecision? decision;
    await openDialog(
      tester,
      count: 3,
      fileName: null,
      onResult: (d) => decision = d,
    );
    expect(find.text('Delete 3 downloads'), findsOneWidget);
    expect(find.text('Delete 3 downloads?'), findsOneWidget);
    expect(find.text('Also delete the files from disk'), findsOneWidget);
    expect(decision, isNull);
  });
}
