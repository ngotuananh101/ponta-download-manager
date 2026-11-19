import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdm/features/settings/external_tools_providers.dart';
import 'package:pdm/shared/widgets/update_dot.dart';

import '../../widget_test.dart' as fixture;

class _AvailableController extends ExternalToolsController {
  @override
  ExternalToolsUiState build() => ExternalToolsUiState(snapshot: ExternalToolsSnapshot([
    ExternalToolStatus(tool: ExternalTool.ffmpeg, origin: ExternalToolOrigin.bundled,
      currentVersion: '7.0.2', latest: ExternalToolRelease(tool: ExternalTool.ffmpeg,
        version: '9.0', url: Uri.https('github.com', '/archive'), sha256: 'a' * 64,
        sizeBytes: 1, archiveFormat: ToolArchiveFormat.tarXz, releaseId: '1')),
  ]));
}

void main() {
  testWidgets('confirmed release appears beside Settings and tools sidebar without installing', (tester) async {
    final temp = Directory.systemTemp.createTempSync('badge-');
    addTearDown(() => temp.deleteSync(recursive: true));
    tester.view.physicalSize = const Size(950, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      externalToolsControllerProvider.overrideWith(_AvailableController.new),
    ], child: fixture.app(settingsPath: '${temp.path}/settings.json')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDot), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('External tools'), findsOneWidget);
    expect(find.byType(UpdateDot), findsOneWidget);
    expect(Directory('${temp.path}/bin').existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
