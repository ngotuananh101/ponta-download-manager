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

/// Pumps the app at the minimum window size (950x650). The toolbar
/// needs that width: its search box is a fixed 200px, so below 950px
/// the toolbar would overflow.
Future<void> pumpApp(
  WidgetTester tester, {
  List<Download> downloads = const [_download],
  MockDownloadsActions? actions,
}) async {
  tester.view.physicalSize = const Size(950, 650);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(app(downloads: downloads, actions: actions));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the download table with the FDM columns',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('Ponta Download Manager'), findsOneWidget);
    expect(find.text('Add download'), findsOneWidget);
    // Table headers.
    for (final header in [
      '#',
      'Name',
      'Size',
      'Status',
      'Download',
      'Upload',
      'Added',
    ]) {
      expect(find.text(header), findsOneWidget);
    }
    // The one downloading row (the file name also shows in the status
    // bar, and each speed shows in the table and the status bar).
    expect(find.text('f.bin'), findsNWidgets(2));
    expect(find.text('1000 B'), findsOneWidget);
    expect(find.text('Downloading 50%'), findsOneWidget);
    expect(find.text('250 B/s'), findsNWidgets(2));
    expect(find.text('0 B/s'), findsNWidgets(2));
  });

  testWidgets('the toolbar right group is flush to the right edge',
      (tester) async {
    await pumpApp(tester);
    // The menu button is the last toolbar item; it should sit at the
    // right edge, inset only by the toolbar's 8px side padding plus
    // the button's own few px. (A Flexible search used to share the
    // free space with the Spacer, leaving the leftover past its 200px
    // cap empty after the menu.)
    final menuRect = tester.getRect(find.byTooltip('Menu'));
    expect(menuRect.right, greaterThan(930));
  });

  testWidgets('the toolbar input and buttons use small text',
      (tester) async {
    await pumpApp(tester);
    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('Newest')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('All files')).style?.fontSize, 12);
    expect(
      tester.widget<Text>(find.text('Add download')).style?.fontSize,
      14,
    );
    expect(
      tester.widget<Text>(find.text('Support the project')).style?.fontSize,
      14,
    );
  });

  testWidgets('the row menu pauses a download', (tester) async {
    final actions = MockDownloadsActions();
    when(
      () => actions.pauseDownload(any()),
    ).thenAnswer((_) async => const Right(unit));
    await pumpApp(tester, actions: actions);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    verify(() => actions.pauseDownload('dl-1')).called(1);
  });

  testWidgets('toolbar and status bar show the FDM layout', (tester) async {
    await pumpApp(tester);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('All files'), findsOneWidget);
    expect(find.text('Search in downloads...'), findsOneWidget);
    expect(find.text('250 B/s'), findsNWidgets(2));
    expect(find.text('0 B/s'), findsNWidgets(2));
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('Support the project'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
  });

  testWidgets('shows the drop zone when there are no downloads',
      (tester) async {
    await pumpApp(tester, downloads: const []);
    expect(find.text('Drag-and-drop URL or torrent file'), findsOneWidget);
  });

  testWidgets('an unknown total shows the downloaded size, not -1 B',
      (tester) async {
    const unknownTotal = Download(
      id: 'dl-2',
      url: 'https://examplefile.com/file-download/203',
      fileName: '203',
      state: DownloadState.completed,
      downloadedBytes: 159641,
      totalBytes: -1,
    );
    await pumpApp(tester, downloads: const [unknownTotal]);
    expect(find.textContaining('155.9 KiB'), findsOneWidget);
    expect(find.textContaining('-1 B'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('a downloading unknown total shows no percent',
      (tester) async {
    const downloading = Download(
      id: 'dl-3',
      url: 'https://examplefile.com/file-download/203',
      fileName: '203',
      state: DownloadState.downloading,
      downloadedBytes: 1024,
      totalBytes: -1,
    );
    await pumpApp(tester, downloads: const [downloading]);
    expect(find.text('Downloading'), findsOneWidget);
    expect(find.text('1.0 KiB'), findsOneWidget);
  });
}
