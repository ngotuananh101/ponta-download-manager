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
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('f.bin'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();
    verify(() => actions.pauseDownload('dl-1')).called(1);
  });

  testWidgets('shows the empty state when there are no downloads',
      (tester) async {
    await tester.pumpWidget(app(downloads: const []));
    await tester.pumpAndSettle();
    expect(find.text('No downloads yet.'), findsOneWidget);
  });
}
