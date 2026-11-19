import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/features/settings/external_tools_providers.dart';
import 'package:pdm/features/settings/external_tools_section.dart';
import 'package:pdm/shared/widgets/pdm_dialog.dart';

class _Controller extends ExternalToolsController {
  @override
  ExternalToolsUiState build() => ExternalToolsUiState(snapshot: ExternalToolsSnapshot([
    ExternalToolStatus(tool: ExternalTool.ffmpeg, origin: ExternalToolOrigin.bundled,
      currentVersion: '7.0.2', latest: ExternalToolRelease(tool: ExternalTool.ffmpeg,
        version: '9.0', url: Uri.https('github.com', '/archive'), sha256: 'a' * 64,
        sizeBytes: 1, archiveFormat: ToolArchiveFormat.tarXz, releaseId: '1')),
    const ExternalToolStatus(tool: ExternalTool.ytDlp, origin: ExternalToolOrigin.missing,
      checkError: 'Offline'),
  ]));

  ExternalTool? installed;
  ExternalTool? removed;

  @override
  Future<void> installUpdate(ExternalTool tool) async => installed = tool;

  @override
  Future<void> removeDownloaded(ExternalTool tool) async => removed = tool;
}

class _ReadyController extends _Controller {
  @override
  ExternalToolsUiState build() => ExternalToolsUiState(snapshot: ExternalToolsSnapshot([
    for (final tool in ExternalTool.values)
      ExternalToolStatus(tool: tool, origin: ExternalToolOrigin.downloaded,
        currentVersion: '1.0', hasDownloadedCopy: true,
        latest: ExternalToolRelease(tool: tool, version: '2.0',
          url: Uri.https('github.com', '/binary'), sha256: 'a' * 64,
          sizeBytes: 1, archiveFormat: ToolArchiveFormat.executable, releaseId: '1')),
  ]));
}

void main() {
  testWidgets('renders confirmed update, missing tool and busy reason without narrow overflow', (tester) async {
    tester.view.physicalSize = const Size(330, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      externalToolsControllerProvider.overrideWith(_Controller.new),
      externalToolsBusyProvider.overrideWith((ref) => Stream.value(true)),
    ], child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExternalToolsSection())))));
    await tester.pumpAndSettle();
    expect(find.textContaining('9.0'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.textContaining('probe'), findsOneWidget);
    expect(find.byKey(const Key('external-tool-ffmpeg')), findsOneWidget);
    expect(find.byKey(const Key('external-tool-ytDlp')), findsOneWidget);
    expect(find.byKey(const Key('external-tool-quickjs')), findsOneWidget);
    expect(find.text('Update'), findsNWidgets(3));
    expect(find.text('Download updates'), findsNothing);
    expect(tester.takeException(), isNull);
    for (final button in tester.widgetList<PdmDialogButton>(find.byType(PdmDialogButton))) {
      if (button.label != 'Check now') expect(button.onPressed, isNull);
    }
  });

  testWidgets('each card dispatches update and removal only for its own tool', (tester) async {
    final controller = _ReadyController();
    await tester.pumpWidget(ProviderScope(overrides: [
      externalToolsControllerProvider.overrideWith(() => controller),
      externalToolsBusyProvider.overrideWith((ref) => Stream.value(false)),
    ], child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ExternalToolsSection())))));
    await tester.pumpAndSettle();
    for (final entry in const {'ffmpeg': ExternalTool.ffmpeg, 'ytDlp': ExternalTool.ytDlp, 'quickjs': ExternalTool.quickjs}.entries) {
      final card = find.byKey(Key('external-tool-${entry.key}'));
      final update = find.descendant(of: card, matching: find.text('Update'));
      await tester.ensureVisible(update);
      await tester.tap(update);
      await tester.pump();
      expect(controller.installed, entry.value);
      final remove = find.descendant(of: card, matching: find.text('Remove downloaded version'));
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
      expect(controller.removed, entry.value);
    }
  });
}
