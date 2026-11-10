import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/app/app.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';

class MockDownloadsActions extends Mock implements DownloadsActions {}

const _download = Download(
  id: 'dl-1',
  url: 'http://127.0.0.1:9/f.bin',
  fileName: 'f.bin',
  state: DownloadState.downloading,
  downloadedBytes: 500,
  totalBytes: 1000,
  bytesPerSecond: 250,
);

Widget app({
  List<Download> downloads = const [_download],
  MockDownloadsActions? actions,
}) {
  return ProviderScope(
    overrides: [
      downloadsProvider.overrideWith((ref) => Stream.value(downloads)),
      if (actions != null)
        downloadsActionsProvider.overrideWithValue(actions),
      // The native library behind DropTarget is not bundled in a test
      // VM, so the screen renders without the native target here.
      dropTargetEnabledProvider.overrideWithValue(false),
    ],
    child: const PdmApp(),
  );
}

void main() {
  testWidgets('shows a download with progress and a pause button',
      (tester) async {
    final actions = MockDownloadsActions();
    when(
      () => actions.pauseDownload(any()),
    ).thenAnswer((_) async => const Right(unit));
    await tester.pumpWidget(app(actions: actions));
    await tester.pumpAndSettle();
    expect(find.text('Ponta Download Manager'), findsOneWidget);
    expect(find.text('Add download'), findsOneWidget);
    expect(find.text('f.bin'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    verify(() => actions.pauseDownload('dl-1')).called(1);
  });

  testWidgets('toolbar and status bar show the FDM layout', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('All files'), findsOneWidget);
    expect(find.text('Search in downloads...'), findsOneWidget);
    // The one downloading item runs at 250 B/s.
    expect(find.text('250 B/s'), findsOneWidget);
    expect(find.text('0 B/s'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('Support the project'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
  });

  testWidgets('shows the drop zone when there are no downloads',
      (tester) async {
    await tester.pumpWidget(app(downloads: const []));
    await tester.pumpAndSettle();
    expect(find.text('Drag-and-drop URL or torrent file'), findsOneWidget);
  });

  testWidgets('an unknown total is shown as unknown, not -1 B (0%)',
      (tester) async {
    const unknownTotal = Download(
      id: 'dl-2',
      url: 'https://examplefile.com/file-download/203',
      fileName: '203',
      state: DownloadState.completed,
      downloadedBytes: 159641,
      totalBytes: -1,
    );
    await tester.pumpWidget(app(downloads: const [unknownTotal]));
    await tester.pumpAndSettle();
    expect(find.textContaining('155.9 KiB'), findsOneWidget);
    expect(find.textContaining('total unknown'), findsOneWidget);
    expect(find.textContaining('-1 B'), findsNothing);
    expect(find.textContaining('(0%)'), findsNothing);
    expect(find.textContaining('completed'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 1);
  });

  testWidgets('a downloading unknown total shows an indeterminate bar',
      (tester) async {
    const downloading = Download(
      id: 'dl-3',
      url: 'https://examplefile.com/file-download/203',
      fileName: '203',
      state: DownloadState.downloading,
      downloadedBytes: 1024,
      totalBytes: -1,
    );
    await tester.pumpWidget(app(downloads: const [downloading]));
    // No pumpAndSettle here: an indeterminate LinearProgressIndicator
    // animates forever, so the tester would never settle.
    await tester.pump();
    expect(find.textContaining('total unknown'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
  });
}
