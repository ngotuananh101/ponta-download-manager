import 'package:download_api/download_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/features/downloads/presentation/new_download_dialog.dart';
import 'package:pdm/shared/theme/app_theme.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

const _probe = ProbeResult(
  url: 'http://127.0.0.1:9/f.bin',
  fileName: 'f.bin',
  totalBytes: 1000,
);

Future<void> openDialog(
  WidgetTester tester, {
  ProbeResult probe = _probe,
  String defaultDirectory = '/tmp/downloads',
  List<String> recentDirectories = const [],
  Future<String?> Function()? pickDirectory,
  Future<int?> Function(String path)? freeSpace,
  required void Function(NewDownloadDecision?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            onResult(
              await showNewDownloadDialog(
                context: context,
                probe: probe,
                defaultDirectory: defaultDirectory,
                recentDirectories: recentDirectories,
                pickDirectory: pickDirectory,
                freeSpace: freeSpace,
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
  testWidgets('shows the probed file name, size and free disk space',
      (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 150323855360,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    expect(find.text('New download'), findsOneWidget);
    expect(find.text('f.bin'), findsOneWidget);
    expect(find.text('/tmp/downloads'), findsOneWidget);
    expect(
      find.text('Size: 1000 B (Disk space: 140.0 GiB)'),
      findsOneWidget,
    );
    expect(decision, isNull);
  });

  testWidgets('the size line gets the full remaining row width',
      (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 150323855360,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    // The Scheduler row used a Spacer plus a Flexible around the size
    // text, so the Spacer took half the remaining width and the size
    // text only got ~173px — too narrow for the full
    // "Size: 1000 B (Disk space: 140.0 GiB)", so the disk-space part
    // was cut off by the ellipsis. The size text takes all the
    // remaining width instead and sits at the right edge.
    expect(
      find.ancestor(
        of: find.text('Size: 1000 B (Disk space: 140.0 GiB)'),
        matching: find.byType(Expanded),
      ),
      findsOneWidget,
    );
    final size = tester.widget<Text>(
      find.text('Size: 1000 B (Disk space: 140.0 GiB)'),
    );
    expect(size.textAlign, TextAlign.right);
    expect(decision, isNull);
  });

  testWidgets('an unknown size shows Unknown size', (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      probe: const ProbeResult(
        url: 'http://127.0.0.1:9/stream.m3u8',
        fileName: 'stream.m3u8',
        totalBytes: -1,
      ),
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    expect(find.textContaining('Unknown size'), findsOneWidget);
    expect(decision, isNull);
  });

  testWidgets('the folder button picks a directory', (tester) async {
    NewDownloadDecision? decision;
    final probedPaths = <String>[];
    await openDialog(
      tester,
      freeSpace: (path) async {
        probedPaths.add(path);
        return 1024;
      },
      pickDirectory: () async => '/tmp/picked',
      onResult: (d) => decision = d,
    );
    await tester.tap(find.byIcon(Icons.folder_open));
    await tester.pumpAndSettle();
    expect(find.text('/tmp/picked'), findsOneWidget);
    expect(probedPaths, contains('/tmp/picked'));
    expect(decision, isNull);
  });

  testWidgets('DOWNLOAD returns the directory, name and paused false',
      (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    await tester.tap(find.text('DOWNLOAD'));
    await tester.pumpAndSettle();
    expect(find.byType(NewDownloadDialog), findsNothing);
    expect(decision, isNotNull);
    expect(decision!.directory, '/tmp/downloads');
    expect(decision!.fileName, 'f.bin');
    expect(decision!.paused, isFalse);
  });

  testWidgets('Scheduler checked makes DOWNLOAD return paused true',
      (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DOWNLOAD'));
    await tester.pumpAndSettle();
    expect(decision, isNotNull);
    expect(decision!.paused, isTrue);
  });

  testWidgets('Download later returns paused true', (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    await tester.tap(find.text('Download later'));
    await tester.pumpAndSettle();
    expect(decision, isNotNull);
    expect(decision!.paused, isTrue);
  });

  testWidgets('an empty file name disables both action buttons',
      (tester) async {
    NewDownloadDecision? decision;
    await openDialog(
      tester,
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) => decision = d,
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    final download = tester.widget<PdmDialogButton>(
      find.ancestor(
        of: find.text('DOWNLOAD'),
        matching: find.byType(PdmDialogButton),
      ),
    );
    final later = tester.widget<PdmDialogButton>(
      find.ancestor(
        of: find.text('Download later'),
        matching: find.byType(PdmDialogButton),
      ),
    );
    expect(download.onPressed, isNull);
    expect(later.onPressed, isNull);
    expect(decision, isNull);
  });

  testWidgets('Cancel returns null', (tester) async {
    NewDownloadDecision? decision;
    var closed = false;
    await openDialog(
      tester,
      freeSpace: (_) async => 1024,
      pickDirectory: () async => null,
      onResult: (d) {
        decision = d;
        closed = true;
      },
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(decision, isNull);
    expect(find.byType(NewDownloadDialog), findsNothing);
  });
}
