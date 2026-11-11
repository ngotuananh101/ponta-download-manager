import 'dart:convert';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pdm/app/app.dart';
import 'package:pdm/app/snail_icon.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/presentation/download_details_panel.dart';
import 'package:pdm/features/downloads/presentation/downloads_filtering.dart';
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
  Size size = const Size(950, 650),
}) async {
  tester.view.physicalSize = size;
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
    // The one downloading row. The file name shows in the status bar
    // only when the row is selected, and each speed shows in the
    // table and the status bar.
    expect(find.text('f.bin'), findsOneWidget);
    expect(find.text('1000 B'), findsOneWidget);
    expect(find.text('Downloading 50%'), findsOneWidget);
    expect(find.text('250 B/s'), findsNWidgets(2));
    expect(find.text('0 B/s'), findsNWidgets(2));
  });

  testWidgets('the download table rows use xs semibold text',
      (tester) async {
    await pumpApp(tester);
    // 'f.bin' also shows in the status bar; the first match is the
    // table row's name cell.
    final nameStyle =
        tester.widget<Text>(find.text('f.bin').first).style;
    expect(nameStyle?.fontSize, 12);
    expect(nameStyle?.fontWeight, FontWeight.w600);
    final statusStyle = tester
        .widget<Text>(find.text('Downloading 50%'))
        .style;
    expect(statusStyle?.fontSize, 12);
    expect(statusStyle?.fontWeight, FontWeight.w600);
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

  testWidgets('the toolbar button texts use the FDM colors',
      (tester) async {
    await pumpApp(tester);
    // The sort/filter pill labels are FDM's near-white, sampled from
    // the screenshot; the Add button's dark text comes from the theme's
    // onPrimary (covered by the AppTheme palette test).
    expect(
      tester.widget<Text>(find.text('Newest')).style?.color,
      const Color(0xFFF4F5F5),
    );
    expect(
      tester.widget<Text>(find.text('All files')).style?.color,
      const Color(0xFFF4F5F5),
    );
  });

  testWidgets('all toolbar items share one vertical center line',
      (tester) async {
    await pumpApp(tester);
    // The search pill is a Container(36) holding a borderless
    // TextField; measure the pill, not the TextField (which sizes to
    // its 32px content and is centered inside the pill).
    final searchBox = tester.getRect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Container),
      ).first,
    );
    final addButton = tester.getRect(find.byType(FilledButton));
    // Every visible item is 36px tall.
    expect(searchBox.height, 36);
    expect(addButton.height, 36);
    // And they all share one vertical center line. (The menu button
    // itself has no visible background, so only its icon's center
    // matters, not the button's height.)
    final centerY = searchBox.center.dy;
    expect(addButton.center.dy, centerY);
    expect(tester.getRect(find.byIcon(Icons.menu)).center.dy, centerY);
    expect(tester.getRect(find.byIcon(Icons.sort)).center.dy, centerY);
    expect(
      tester.getRect(find.byIcon(Icons.filter_list)).center.dy,
      centerY,
    );
    expect(
      tester.getRect(find.byType(Checkbox).first).center.dy,
      centerY,
    );
  });

  testWidgets('the toolbar input and buttons use small text',
      (tester) async {
    await pumpApp(tester);
    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('Newest')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('All files')).style?.fontSize, 12);
    // The Add button label is xs semibold, like the table rows.
    expect(
      tester.widget<Text>(find.text('Add download')).style?.fontSize,
      12,
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
    // Snail mode is OFF by default (unlimited speed).
    expect(find.text('OFF'), findsOneWidget);
  });

  testWidgets('the status bar toggle shows a snail icon',
      (tester) async {
    await pumpApp(tester);
    expect(find.byType(SnailIcon), findsOneWidget);
  });

  testWidgets('the status bar toggle switches snail mode on and off',
      (tester) async {
    final actions = MockDownloadsActions();
    when(
      () => actions.setGlobalBandwidthLimit(any()),
    ).thenAnswer((_) async => const Right(unit));
    await pumpApp(tester, actions: actions);
    expect(find.text('OFF'), findsOneWidget);
    await tester.tap(find.text('OFF'));
    await tester.pumpAndSettle();
    verify(() => actions.setGlobalBandwidthLimit(8192)).called(1);
    expect(find.text('ON'), findsOneWidget);
    await tester.tap(find.text('ON'));
    await tester.pumpAndSettle();
    verify(() => actions.setGlobalBandwidthLimit(null)).called(1);
    expect(find.text('OFF'), findsOneWidget);
  });

  testWidgets('shows the drop zone when there are no downloads',
      (tester) async {
    await pumpApp(tester, downloads: const []);
    expect(find.text('Drag-and-drop URL or torrent file'), findsOneWidget);
  });

  testWidgets('the drop zone hides when its area is too small',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('Drag-and-drop URL or torrent file'), findsOneWidget);
    // At 260px tall the body leaves less than the 120px the zone
    // needs under the 32px table header: the zone hides and the row
    // keeps the space instead.
    await pumpApp(tester, size: const Size(950, 260));
    expect(find.text('f.bin'), findsOneWidget);
    expect(find.text('Drag-and-drop URL or torrent file'), findsNothing);
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

  testWidgets('tapping the drop zone does not open the add dialog',
      (tester) async {
    await pumpApp(tester, downloads: const []);
    await tester.tap(find.text('Drag-and-drop URL or torrent file'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('only a selected row has a background fill',
      (tester) async {
    await pumpApp(tester);
    // The innermost Container ancestor of the row's file name is the
    // row itself (the name also shows in the status bar, so .first
    // picks the table row's text).
    final rowFinder = find
        .ancestor(of: find.text('f.bin').first, matching: find.byType(Container))
        .last;
    BoxDecoration? decoration() =>
        tester.widget<Container>(rowFinder).decoration as BoxDecoration?;
    expect(decoration()?.color, Colors.transparent);
    await tester.tap(
      find.descendant(of: rowFinder, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    final scheme =
        Theme.of(tester.element(find.text('f.bin').first)).colorScheme;
    expect(decoration()?.color, scheme.surfaceContainerHigh);
  });

  testWidgets('tapping a row selects it', (tester) async {
    await pumpApp(tester);
    // The innermost Container ancestor of the row's file name is the
    // row itself (the name also shows in the status bar, so .first
    // picks the table row's text).
    final rowFinder = find
        .ancestor(of: find.text('f.bin').first, matching: find.byType(Container))
        .last;
    BoxDecoration? decoration() =>
        tester.widget<Container>(rowFinder).decoration as BoxDecoration?;
    expect(decoration()?.color, Colors.transparent);
    // Tap the row's file name (not the checkbox, not the menu).
    await tester.tap(find.text('f.bin').first);
    await tester.pumpAndSettle();
    final scheme =
        Theme.of(tester.element(find.text('f.bin').first)).colorScheme;
    expect(decoration()?.color, scheme.surfaceContainerHigh);
    expect(find.text('1 selected'), findsOneWidget);
    // Tapping the same row again deselects it.
    await tester.tap(find.text('f.bin').first);
    await tester.pumpAndSettle();
    expect(decoration()?.color, Colors.transparent);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('tapping the row menu does not select the row',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    // The menu opens (Pause is a downloading row's action).
    expect(find.text('Pause'), findsOneWidget);
    // And the row is still unselected: no bulk bar.
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('a completed row has a Delete action', (tester) async {
    const completed = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/f.bin',
      fileName: 'f.bin',
      state: DownloadState.completed,
      downloadedBytes: 1000,
      totalBytes: 1000,
    );
    await pumpApp(tester, downloads: const [completed]);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('deleting a row calls deleteDownload', (tester) async {
    final actions = MockDownloadsActions();
    when(
      () => actions.deleteDownload('dl-1'),
    ).thenAnswer((_) async => const Right(unit));
    await pumpApp(tester, actions: actions);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    verify(() => actions.deleteDownload('dl-1')).called(1);
  });

  testWidgets('the row icon follows the download state',
      (tester) async {
    const downloading = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/a.bin',
      fileName: 'a.bin',
      state: DownloadState.downloading,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const paused = Download(
      id: 'dl-2',
      url: 'http://127.0.0.1:9/b.bin',
      fileName: 'b.bin',
      state: DownloadState.paused,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const completed = Download(
      id: 'dl-3',
      url: 'http://127.0.0.1:9/c.bin',
      fileName: 'c.bin',
      state: DownloadState.completed,
      downloadedBytes: 1000,
      totalBytes: 1000,
    );
    const failed = Download(
      id: 'dl-4',
      url: 'http://127.0.0.1:9/d.bin',
      fileName: 'd.bin',
      state: DownloadState.failed,
      downloadedBytes: 100,
      totalBytes: 1000,
    );
    await pumpApp(
      tester,
      downloads: const [downloading, paused, completed, failed],
    );
    // The icon sits in the name cell's Row, right before the name.
    IconData iconBefore(String name) {
      final nameRow = find
          .ancestor(of: find.text(name).first, matching: find.byType(Row))
          .last;
      final icon = tester.widget<Icon>(
        find.descendant(of: nameRow, matching: find.byType(Icon)).first,
      );
      return icon.icon!;
    }

    expect(iconBefore('a.bin'), Icons.arrow_downward);
    expect(iconBefore('b.bin'), Icons.play_arrow);
    expect(iconBefore('c.bin'), Icons.folder);
    expect(iconBefore('d.bin'), Icons.insert_drive_file);
  });

  testWidgets('the select dropdown offers the FDM options', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    for (final option in [
      'All',
      'Downloads only',
      'Uploads only',
      'Completed',
      'Stopped',
    ]) {
      expect(find.text(option), findsWidgets);
    }
  });

  testWidgets('selecting Completed selects only the completed rows',
      (tester) async {
    const downloading = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/a.bin',
      fileName: 'a.bin',
      state: DownloadState.downloading,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const paused = Download(
      id: 'dl-2',
      url: 'http://127.0.0.1:9/b.bin',
      fileName: 'b.bin',
      state: DownloadState.paused,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const completed = Download(
      id: 'dl-3',
      url: 'http://127.0.0.1:9/c.bin',
      fileName: 'c.bin',
      state: DownloadState.completed,
      downloadedBytes: 1000,
      totalBytes: 1000,
    );
    await pumpApp(
      tester,
      downloads: const [downloading, paused, completed],
    );
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    // 'Completed' also shows as the completed row's status text; the
    // menu item is the last match (the popup lives in the Overlay).
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('selecting Stopped selects only the stopped rows',
      (tester) async {
    const downloading = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/a.bin',
      fileName: 'a.bin',
      state: DownloadState.downloading,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const paused = Download(
      id: 'dl-2',
      url: 'http://127.0.0.1:9/b.bin',
      fileName: 'b.bin',
      state: DownloadState.paused,
      downloadedBytes: 500,
      totalBytes: 1000,
    );
    const failed = Download(
      id: 'dl-3',
      url: 'http://127.0.0.1:9/c.bin',
      fileName: 'c.bin',
      state: DownloadState.failed,
      downloadedBytes: 100,
      totalBytes: 1000,
    );
    await pumpApp(
      tester,
      downloads: const [downloading, paused, failed],
    );
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stopped'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('selecting Uploads only selects nothing', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uploads only'));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('the toolbar select menus use xs text in compact rows',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();
    for (final option in [
      'Newest',
      'Old',
      'A-Z',
      'Z-A',
      'By size: large',
      'By size: small',
      'By status: ascending',
      'By status: descending',
    ]) {
      expect(find.text(option), findsWidgets);
    }
    // The menu item text is xs (12px) like the table rows.
    final menuText = tester.widget<Text>(find.text('By size: large').last);
    expect(menuText.style?.fontSize, 12);
    // The menu rows are compact (32px, not the 48px default).
    final items = tester.widgetList<PopupMenuItem<DownloadSort>>(
      find.byType(PopupMenuItem<DownloadSort>),
    );
    expect(items.length, 8);
    expect(items.every((item) => item.height == 32), isTrue);
  });

  testWidgets('the right-side menu uses xs text in compact rows',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Pause all'), findsOneWidget);
    expect(find.text('Resume all'), findsOneWidget);
    final menuText = tester.widget<Text>(find.text('Pause all'));
    expect(menuText.style?.fontSize, 12);
    final items = tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(items.length, 2);
    expect(items.every((item) => item.height == 32), isTrue);
  });

  testWidgets('the row menu uses xs text in compact rows',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // The menu item text is xs (12px) like the table rows.
    final menuText = tester.widget<Text>(find.text('Pause'));
    expect(menuText.style?.fontSize, 12);
    // The menu rows are compact (32px, not the 48px default).
    final items = tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(items.length, 3);
    expect(items.every((item) => item.height == 32), isTrue);
  });

  testWidgets('the status bar uses xs text and a bigger snail toggle',
      (tester) async {
    await pumpApp(tester);
    // The speeds show in the table and the status bar; the last
    // match is the status bar one.
    final downloadSpeed = tester.widget<Text>(find.text('250 B/s').last);
    expect(downloadSpeed.style?.fontSize, 12);
    final uploadSpeed = tester.widget<Text>(find.text('0 B/s').last);
    expect(uploadSpeed.style?.fontSize, 12);
    // The snail toggle is bigger than the 14px icon it had.
    final snail = tester.widget<SnailIcon>(find.byType(SnailIcon));
    expect(snail.size, 16);
  });

  testWidgets('the status bar shows the selected download name only',
      (tester) async {
    await pumpApp(tester);
    // Nothing selected: the file name shows only in the table row.
    expect(find.text('f.bin'), findsOneWidget);
    // Select the row: the name appears in the status bar too.
    await tester.tap(find.text('f.bin'));
    await tester.pumpAndSettle();
    expect(find.text('f.bin'), findsNWidgets(2));
    // The status bar name is xs and its button sits flush to the
    // right edge (950px wide minus the 12px bar padding).
    final statusName = tester.widget<Text>(find.text('f.bin').last);
    expect(statusName.style?.fontSize, 12);
    final statusButton = find.ancestor(
      of: find.text('f.bin').last,
      matching: find.byType(InkWell),
    );
    expect(tester.getBottomRight(statusButton).dx, closeTo(938, 1));
  });

  testWidgets(
      'the status bar file name button is a compact select-like button',
      (tester) async {
    await pumpApp(tester);
    // Nothing selected: no name button at all.
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
    // Select the row: the button appears at the far right.
    await tester.tap(find.text('f.bin').first);
    await tester.pumpAndSettle();
    final button = find.ancestor(
      of: find.text('f.bin').last,
      matching: find.byType(InkWell),
    );
    // Compact: far narrower than the 950px-wide status bar.
    expect(tester.getSize(button).width, lessThan(400));
    // Text on the left, chevron on the right.
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.arrow_drop_up),
      ),
      findsOneWidget,
    );
    final nameCenter = tester.getCenter(find.text('f.bin').last);
    final iconCenter = tester.getCenter(find.byIcon(Icons.arrow_drop_up));
    expect(nameCenter.dx, lessThan(iconCenter.dx));
    // Opening the panel flips the chevron down.
    await tester.tap(find.text('f.bin').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.arrow_drop_up),
      ),
      findsNothing,
    );
    expect(find.byType(DownloadDetailsPanel), findsOneWidget);
  });

  testWidgets('the bulk bar uses xs text', (tester) async {
    await pumpApp(tester);
    // Select the row so the bulk bar appears.
    await tester.tap(find.text('f.bin'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    final count = tester.widget<Text>(find.text('1 selected'));
    expect(count.style?.fontSize, 12);
    for (final label in ['Pause', 'Cancel', 'Delete']) {
      final buttonText = tester.widget<Text>(find.text(label));
      expect(buttonText.style?.fontSize, 12);
    }
  });

  testWidgets('the table rows have a small checkbox and no bottom border',
      (tester) async {
    await pumpApp(tester);
    // The row checkbox is the last Checkbox in the tree (the toolbar
    // select-all comes first); it is scaled down to 0.8x.
    final rowCheckbox = find.byType(Checkbox).last;
    final transforms = tester.widgetList<Transform>(
      find.ancestor(of: rowCheckbox, matching: find.byType(Transform)),
    );
    expect(
      transforms.any(
        // The x-scale is storage[0]; getMaxScaleOnAxis would return
        // the z-scale (1.0) for a 2D scale matrix.
        (t) => (t.transform.storage[0] - 0.8).abs() < 0.001,
      ),
      isTrue,
    );
    // The row container is the only 40px one in the tree (the bulk
    // bar is hidden when nothing is selected); it has no border.
    final containers = tester.widgetList<Container>(find.byType(Container));
    final rowContainers = containers
        .where((c) => c.constraints?.maxHeight == 40)
        .toList();
    expect(rowContainers.length, 1);
    final decoration = rowContainers.single.decoration as BoxDecoration?;
    expect(decoration?.border, isNull);
  });

  // Opens the details panel: tap the row to select it, then tap the
  // file name button in the status bar.
  Future<void> openDetailsPanel(
    WidgetTester tester, [
    String fileName = 'f.bin',
  ]) async {
    await tester.tap(find.text(fileName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(fileName).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the status bar file name opens the details panel',
      (tester) async {
    await pumpApp(tester);
    // Nothing selected: no name in the status bar, no panel.
    expect(find.byType(DownloadDetailsPanel), findsNothing);
    await openDetailsPanel(tester);
    expect(find.byType(DownloadDetailsPanel), findsOneWidget);
    expect(find.text('GENERAL'), findsOneWidget);
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(find.text('CONNECTIONS'), findsOneWidget);
    // GENERAL tab: the downloaded / total and the percent.
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('500 B / 1000 B'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('the details panel GENERAL tab shows the download fields',
      (tester) async {
    final detailed = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/f.bin',
      fileName: 'f.bin',
      state: DownloadState.downloading,
      downloadedBytes: 500,
      totalBytes: 1000,
      bytesPerSecond: 250,
      createdAt: DateTime(2026, 11, 11, 17, 10),
      filePath: '/tmp/downloads/f.bin',
      priority: 2,
    );
    await pumpApp(tester, downloads: [detailed]);
    await openDetailsPanel(tester);
    final panel = find.byType(DownloadDetailsPanel);
    expect(
      find.descendant(of: panel, matching: find.text('/tmp/downloads')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Priority')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('high')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Added at')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('11 thg 11 2026, 17:10'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.text('http://127.0.0.1:9/f.bin'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'the details panel GENERAL tab shows a large thumbnail on the left',
      (tester) async {
    final detailed = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/f.bin',
      fileName: 'f.bin',
      state: DownloadState.downloading,
      downloadedBytes: 500,
      totalBytes: 1000,
      bytesPerSecond: 250,
      createdAt: DateTime(2026, 11, 11, 17, 10),
      filePath: '/tmp/downloads/f.bin',
      priority: 2,
    );
    await pumpApp(tester, downloads: [detailed]);
    await openDetailsPanel(tester);
    final panel = find.byType(DownloadDetailsPanel);
    final thumb = find.descendant(
      of: panel,
      matching: find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.arrow_downward && w.size == 56,
      ),
    );
    expect(thumb, findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('details-thumb'))),
      const Size(120, 120),
    );
    final thumbRect = tester.getRect(thumb);
    final name = find.descendant(of: panel, matching: find.text('f.bin'));
    expect(name, findsOneWidget);
    final nameRect = tester.getRect(name);
    expect(thumbRect.right, lessThanOrEqualTo(nameRect.left));
    expect(thumbRect.top, lessThanOrEqualTo(nameRect.top + 1));
  });

  testWidgets('the details panel GENERAL tab shows the image itself',
      (tester) async {
    // Real file I/O awaited directly in a testWidgets body deadlocks
    // on the fake-async zone, so the fixture file is created inside
    // runAsync. The tearDown deletes it synchronously for the same
    // reason.
    late final Directory tempDir;
    late final File imageFile;
    await tester.runAsync(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-thumb-test-');
      // A 1x1 transparent PNG.
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      imageFile = File(p.join(tempDir.path, 'pic.png'));
      await imageFile.writeAsBytes(base64Decode(pngBase64));
    });
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final detailed = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/pic.png',
      fileName: 'pic.png',
      state: DownloadState.completed,
      downloadedBytes: 100,
      totalBytes: 100,
      bytesPerSecond: 0,
      createdAt: DateTime(2026, 11, 11, 17, 10),
      filePath: imageFile.path,
      priority: 0,
    );
    await pumpApp(tester, downloads: [detailed]);
    await openDetailsPanel(tester, 'pic.png');
    final panel = find.byType(DownloadDetailsPanel);
    expect(
      find.descendant(of: panel, matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('details-thumb'))),
      const Size(120, 120),
    );
  });

  testWidgets(
      'the details panel GENERAL tab falls back to the icon when no thumbnail is available',
      (tester) async {
    final detailed = Download(
      id: 'dl-1',
      url: 'http://127.0.0.1:9/clip.mp4',
      fileName: 'clip.mp4',
      state: DownloadState.completed,
      downloadedBytes: 100,
      totalBytes: 100,
      bytesPerSecond: 0,
      createdAt: DateTime(2026, 11, 11, 17, 10),
      filePath: '/tmp/downloads/clip.mp4',
      priority: 0,
    );
    await pumpApp(tester, downloads: [detailed]);
    await openDetailsPanel(tester, 'clip.mp4');
    final panel = find.byType(DownloadDetailsPanel);
    expect(
      find.descendant(
        of: panel,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.folder && w.size == 56,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the details panel PROGRESS tab shows the segment bitmap',
      (tester) async {
    final actions = MockDownloadsActions();
    when(() => actions.getSegments(any())).thenAnswer(
      (_) async => const Right([
        DownloadSegment(segmentId: 0, start: 0, end: 499, downloaded: 500),
        DownloadSegment(segmentId: 1, start: 500, end: 999, downloaded: 0),
      ]),
    );
    await pumpApp(tester, actions: actions);
    await openDetailsPanel(tester);
    await tester.tap(find.text('PROGRESS'));
    await tester.pumpAndSettle();
    verify(() => actions.getSegments('dl-1')).called(1);
    final panel = find.byType(DownloadDetailsPanel);
    final context = tester.element(panel);
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Theme.of(context).colorScheme.surfaceContainerHighest;
    // The first half of the file is downloaded (blue), the rest is
    // not (dark): both colors must appear in the bitmap.
    expect(
      find.descendant(
        of: panel,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == primary,
        ),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: panel,
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == dark,
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('the details panel CONNECTIONS tab shows a connections table',
      (tester) async {
    final actions = MockDownloadsActions();
    when(() => actions.getSegments(any())).thenAnswer(
      (_) async => const Right([
        DownloadSegment(segmentId: 0, start: 0, end: 499, downloaded: 500),
        DownloadSegment(segmentId: 1, start: 500, end: 999, downloaded: 0),
      ]),
    );
    await pumpApp(tester, actions: actions);
    await openDetailsPanel(tester);
    await tester.tap(find.text('CONNECTIONS'));
    await tester.pumpAndSettle();
    final panel = find.byType(DownloadDetailsPanel);
    // Header columns.
    for (final header in ['#', 'Host', 'Port', 'Downloaded', 'Progress']) {
      expect(
        find.descendant(of: panel, matching: find.text(header)),
        findsOneWidget,
      );
    }
    // One row per segment: the first is fully downloaded, the second
    // has not started. Both connect to the download's host and port.
    expect(
      find.descendant(of: panel, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('127.0.0.1')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text('9')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text('500 B')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('0 B')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('100%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('0%')),
      findsOneWidget,
    );
  });

  testWidgets(
      'the details panel CONNECTIONS tab shows no connections when empty',
      (tester) async {
    final actions = MockDownloadsActions();
    when(() => actions.getSegments(any())).thenAnswer(
      (_) async => const Right(<DownloadSegment>[]),
    );
    await pumpApp(tester, actions: actions);
    await openDetailsPanel(tester);
    await tester.tap(find.text('CONNECTIONS'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(DownloadDetailsPanel),
        matching: find.text('No connections yet.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the details panel closes with the X button',
      (tester) async {
    await pumpApp(tester);
    await openDetailsPanel(tester);
    expect(find.byType(DownloadDetailsPanel), findsOneWidget);
    // The panel's X is the close button inside the panel; the window
    // title bar has its own close button.
    await tester.tap(
      find.descendant(
        of: find.byType(DownloadDetailsPanel),
        matching: find.byTooltip('Close'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DownloadDetailsPanel), findsNothing);
  });
}
