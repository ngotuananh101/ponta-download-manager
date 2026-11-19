import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:download_external/download_external.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/external_tools_service.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/providers/download_providers.dart';
import 'package:pdm/features/settings/external_tools_providers.dart';
import 'package:pdm_engine/pdm_engine.dart';

class _SeededController extends ExternalToolsController {
  _SeededController(this.initial);
  final ExternalToolsSnapshot initial;

  @override
  ExternalToolsUiState build() => ExternalToolsUiState(snapshot: initial);
}

void main() {
  test('individual update keeps other offers, excludes overlap and refreshes engine before inspection', () async {
    final temp = await Directory.systemTemp.createTemp('individual-updater-');
    final bin = Directory('${temp.path}/bin')..createSync();
    final qjs = File('${bin.path}/qjs')..writeAsStringSync('0.18.0');
    final ytDlp = File('${bin.path}/yt-dlp')..writeAsStringSync('2026.10.26');
    final bytes = utf8.encode('2026.11.19');
    final requested = Completer<void>();
    final releaseDownload = Completer<void>();
    var downloads = 0;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async {
      downloads++;
      requested.complete();
      await releaseDownload.future;
      return ToolHttpResponse(200, {}, Stream.value(bytes));
    });
    final snapshot = ExternalToolsSnapshot([
      for (final tool in [ExternalTool.ytDlp, ExternalTool.quickjs])
        ExternalToolStatus(tool: tool, origin: ExternalToolOrigin.downloaded,
          currentVersion: tool == ExternalTool.ytDlp ? '2026.10.26' : '0.18.0', hasDownloadedCopy: true,
          latest: ExternalToolRelease(tool: tool, version: tool == ExternalTool.ytDlp ? '2026.11.19' : '0.19.0',
            url: Uri.https('github.com', '/${tool.name}'), sha256: sha256.convert(bytes).toString(),
            sizeBytes: bytes.length, archiveFormat: ToolArchiveFormat.executable, releaseId: '1')),
    ]);
    var resolutions = 0;
    final engine = PdmEngine.open(databasePath: '${temp.path}/db', resolveExternalTools: () async {
      resolutions++;
      return const ExternalTools(ffmpegPath: null, ytDlpPath: null);
    });
    final datasource = EngineDownloadDatasource(engine: engine, downloadDirectory: temp.path);
    await expectLater(engine.probeYtDlp('https://example.invalid/video'), throwsA(anything));
    expect(resolutions, 1);
    final service = ExternalToolsUpdateService(releases: client,
      installer: ExternalToolInstaller(userToolsDirectory: bin, releases: client,
        runProcess: (path, _) async => ProcessResult(1, 0, await File(path).readAsString(), '')),
      resolveTools: () async {
        final before = resolutions;
        await expectLater(engine.probeYtDlp('https://example.invalid/video'), throwsA(anything));
        expect(resolutions, before, reason: 'inspection still owns maintenance and excludes new probes');
        return ExternalTools(ffmpegPath: null, ytDlpPath: ytDlp.path, qjsPath: qjs.path);
      },
      runProcess: (path, _) async => ProcessResult(1, 0, await File(path).readAsString(), ''), isWindows: false);
    final container = ProviderContainer(overrides: [
      externalToolsControllerProvider.overrideWith(() => _SeededController(snapshot)),
      externalToolsUpdateServiceProvider.overrideWithValue(service),
      downloadDatasourceProvider.overrideWithValue(datasource),
    ]);
    addTearDown(() async { container.dispose(); service.close(); await datasource.dispose(); await temp.delete(recursive: true); });
    final controller = container.read(externalToolsControllerProvider.notifier);
    final install = controller.installUpdate(ExternalTool.ytDlp);
    await requested.future;
    expect(engine.isExternalToolsBusy, isTrue);
    expect(container.read(externalToolsControllerProvider).hasUpdates, isTrue);
    await controller.checkNow();
    await controller.installUpdate(ExternalTool.quickjs);
    await controller.removeDownloaded(ExternalTool.quickjs);
    expect(await qjs.readAsString(), '0.18.0');
    releaseDownload.complete();
    await install;
    final state = container.read(externalToolsControllerProvider);
    expect(state.error, isNull);
    expect(state.mutating, isFalse);
    expect(state.results.single.tool, ExternalTool.ytDlp);
    expect(state.results.single.changed, isTrue);
    expect(state.snapshot!.tools.singleWhere((s) => s.tool == ExternalTool.ytDlp).hasUpdate, isFalse);
    expect(state.snapshot!.tools.singleWhere((s) => s.tool == ExternalTool.quickjs).hasUpdate, isTrue);
    expect(state.hasUpdates, isTrue);
    expect(downloads, 1);
    expect(await qjs.readAsString(), '0.18.0');
    expect(engine.isExternalToolsBusy, isFalse);
    await expectLater(engine.probeYtDlp('https://example.invalid/video'), throwsA(anything));
    expect(resolutions, 2, reason: 'the next operation resolves tools again after refresh');
    await controller.removeDownloaded(ExternalTool.ytDlp);
    expect(await ytDlp.exists(), isFalse);
    expect(await qjs.readAsString(), '0.18.0');
  });

  test('startup checks once per container and offline errors never imply updates', () async {
    final temp = await Directory.systemTemp.createTemp('updater-provider-');
    var checks = 0;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async {
      checks++;
      return ToolHttpResponse(429, {}, const Stream.empty());
    });
    final service = ExternalToolsUpdateService(releases: client,
      installer: ExternalToolInstaller(userToolsDirectory: Directory('${temp.path}/bin'), releases: client),
      resolveTools: () async => const ExternalTools(ffmpegPath: null, ytDlpPath: null), isWindows: false);
    final engine = PdmEngine.open(databasePath: '${temp.path}/db');
    final datasource = EngineDownloadDatasource(engine: engine, downloadDirectory: temp.path);
    final container = ProviderContainer(overrides: [
      externalToolsUpdateServiceProvider.overrideWithValue(service),
      downloadDatasourceProvider.overrideWithValue(datasource),
    ]);
    addTearDown(() async { container.dispose(); service.close(); await datasource.dispose(); await temp.delete(recursive: true); });
    await container.read(externalToolsStartupCheckProvider.future);
    await container.read(externalToolsStartupCheckProvider.future);
    expect(checks, 3);
    expect(container.read(externalToolsControllerProvider).hasUpdates, isFalse);
    expect(container.read(externalToolsControllerProvider).snapshot!.tools.every((s) => s.checkError != null), isTrue);
    await container.read(externalToolsControllerProvider.notifier).checkNow();
    expect(checks, 6);
    await engine.withExternalToolsMaintenance((_) async {
      await container.read(externalToolsControllerProvider.notifier).removeDownloaded(ExternalTool.ytDlp);
      expect(container.read(externalToolsControllerProvider).error, contains('busy'));
    });
    expect(container.read(externalToolsControllerProvider).mutating, isFalse);
  });
}
