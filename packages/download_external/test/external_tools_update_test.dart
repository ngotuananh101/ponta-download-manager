import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

void main() {
  test('inspection kills and reaps a hung health-check process', () async {
    if (Platform.isWindows) return;
    final temp = await Directory.systemTemp.createTemp('tool-timeout-');
    addTearDown(() => temp.delete(recursive: true));
    final executable = File('${temp.path}/ffmpeg');
    await executable.writeAsString('#!/bin/sh\nexec /bin/sleep 30\n');
    await Process.run('chmod', ['+x', executable.path]);
    Process? launched;
    final client = ExternalToolReleaseClient(cacheDirectory: temp);
    final service = ExternalToolsUpdateService(
      releases: client,
      installer: ExternalToolInstaller(userToolsDirectory: Directory('${temp.path}/bin'), releases: client),
      resolveTools: () async => ExternalTools(ffmpegPath: executable.path, ytDlpPath: null),
      healthCheckTimeout: const Duration(milliseconds: 100),
      startProcess: (path, args) async {
        launched = await Process.start(path, args);
        return launched!;
      },
      isWindows: false);
    final snapshot = await service.inspectInstalled(ExternalToolsSnapshot(const []));
    expect(snapshot.tools.first.currentVersion, isNull);
    expect(launched, isNotNull);
    expect(await launched!.exitCode, isNot(0), reason: 'timed-out health-check process must be reaped');
  });

  test('individual actions preserve other tools and resolve fallback after removal', () async {
    final temp = await Directory.systemTemp.createTemp('tool-service-');
    addTearDown(() => temp.delete(recursive: true));
    final bodies = {ExternalTool.ytDlp: utf8.encode('2026.11.19'),
      ExternalTool.quickjs: utf8.encode('0.19.0')};
    final client = ExternalToolReleaseClient(cacheDirectory: Directory('${temp.path}/cache'),
      request: (uri, _) async => ToolHttpResponse(200, {}, Stream.value(bodies[ExternalTool.values.byName(uri.pathSegments.last)]!)));
    final installer = ExternalToolInstaller(userToolsDirectory: Directory('${temp.path}/bin'),
      releases: client, runProcess: (path, _) async => ProcessResult(1, 0, await File(path).readAsString(), ''));
    Future<ExternalTools> resolve() => ExternalTools.resolve(executableDir: temp.path,
      userToolsDir: '${temp.path}/bin', pathLookup: (name) async => '/system/$name',
      versionCheck: (_) async => true, jsRuntimeSupportCheck: (_) async => true);
    final service = ExternalToolsUpdateService(releases: client, installer: installer,
      resolveTools: resolve, isWindows: false,
      runProcess: (path, _) async => ProcessResult(1, 0,
        path.contains('/system/') ? (path.endsWith('ffmpeg') ? 'ffmpeg version 7.0.2' : path.endsWith('qjs') ? '0.18.0' : '2026.10.26')
          : await File(path).readAsString(), ''));
    final snapshot = ExternalToolsSnapshot([
      for (final tool in bodies.keys) ExternalToolStatus(tool: tool, origin: ExternalToolOrigin.system,
        currentVersion: tool == ExternalTool.ytDlp ? '2026.10.26' : '0.18.0',
        latest: ExternalToolRelease(tool: tool, version: utf8.decode(bodies[tool]!),
          url: Uri.https('github.com', '/${tool.name}'), sizeBytes: bodies[tool]!.length,
          sha256: tool == ExternalTool.quickjs ? 'a' * 64 : sha256.convert(bodies[tool]!).toString(),
          archiveFormat: ToolArchiveFormat.executable, releaseId: '1')),
    ]);
    final results = await service.installUpdates(snapshot, tool: ExternalTool.ytDlp);
    expect(results.map((r) => r.tool), [ExternalTool.ytDlp]);
    expect(results.map((r) => r.changed), [true]);
    expect(await File('${temp.path}/bin/qjs').exists(), isFalse);
    final failed = await service.installUpdates(snapshot, tool: ExternalTool.quickjs);
    expect(failed.single.changed, isFalse);
    final installed = await service.inspectInstalled(snapshot);
    expect(installed.tools.firstWhere((s) => s.tool == ExternalTool.ytDlp).hasUpdate, isFalse);
    expect(installed.hasDownloadedUpdates, isTrue);
    expect(installed.hasUpdates, isTrue);
    final other = await File('${temp.path}/bin/qjs').writeAsString('keep');
    expect((await service.removeDownloaded(tool: ExternalTool.ytDlp)).where((r) => r.changed).length, 1);
    expect(await other.readAsString(), 'keep');
    await other.delete();
    final removed = await service.inspectInstalled(snapshot);
    expect(removed.hasUpdates, isTrue);
    expect(removed.hasDownloadedUpdates, isFalse);
    expect(removed.tools.firstWhere((s) => s.tool == ExternalTool.ytDlp).origin, ExternalToolOrigin.system);
  });
}
