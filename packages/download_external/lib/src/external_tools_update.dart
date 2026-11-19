import 'dart:async';

import 'external_tool_installer.dart';
import 'external_tool_release.dart';
import 'external_tool_release_client.dart';
import 'external_tool_process.dart';
import 'external_tool_versions.dart';
import 'external_tools.dart';

class ExternalToolsUpdateService {
  ExternalToolsUpdateService({required this.releases, required this.installer,
    required this.resolveTools, ToolProcessRunner? runProcess, required this.isWindows,
    this.healthCheckTimeout = const Duration(seconds: 10), ExternalToolProcessStarter? startProcess})
      : runProcess = runProcess ?? ((path, args) => runExternalToolProcess(
          path, args, timeout: healthCheckTimeout, startProcess: startProcess));

  final ExternalToolReleaseClient releases;
  final ExternalToolInstaller installer;
  final Future<ExternalTools> Function() resolveTools;
  final ToolProcessRunner runProcess;
  final Duration healthCheckTimeout;
  final bool isWindows;

  Future<ExternalToolsSnapshot> checkAll() async {
    final local = await inspectInstalled(ExternalToolsSnapshot(const []));
    final statuses = <ExternalToolStatus>[];
    for (final status in local.tools) {
      ExternalToolRelease? latest;
      String? error;
      try {
        latest = await releases.latest(status.tool, isWindows: isWindows);
      } catch (failure) {
        error = failure.toString();
      }
      statuses.add(ExternalToolStatus(tool: status.tool, path: status.path,
        origin: status.origin, currentVersion: status.currentVersion, latest: latest,
        checkError: error, hasDownloadedCopy: status.hasDownloadedCopy));
    }
    return ExternalToolsSnapshot(statuses);
  }

  Future<ExternalToolsSnapshot> inspectInstalled(ExternalToolsSnapshot previous) async {
    final tools = await resolveTools();
    final old = {for (final status in previous.tools) status.tool: status};
    final statuses = <ExternalToolStatus>[];
    for (final tool in ExternalTool.values) {
      final path = tools.pathOf(tool);
      String? version;
      if (path != null) {
        try {
          final result = await runProcess(path, tool.versionArguments).timeout(healthCheckTimeout);
          if (result.exitCode == 0) version = parseToolVersion(tool, '${result.stdout}\n${result.stderr}');
        } catch (_) {
          // Unknown version is not version zero and is never offered an update.
        }
      }
      statuses.add(ExternalToolStatus(tool: tool, origin: tools.originOf(tool), path: path,
        currentVersion: version, latest: old[tool]?.latest, checkError: old[tool]?.checkError,
        hasDownloadedCopy: await installer.hasDownloadedCopy(tool)));
    }
    return ExternalToolsSnapshot(statuses);
  }

  Future<List<ToolMutationResult>> installUpdates(ExternalToolsSnapshot snapshot,
      {required ExternalTool tool, void Function(ToolUpdateProgress)? onProgress}) async {
    final results = <ToolMutationResult>[];
    for (final status in snapshot.tools) {
      if (status.tool == tool && status.hasUpdate) {
        results.add(await installer.install(status.latest!, onProgress: onProgress,
          currentVersion: status.currentVersion));
      }
    }
    return results;
  }

  Future<List<ToolMutationResult>> removeDownloaded({required ExternalTool tool}) async =>
      [await installer.remove(tool)];

  void close() => releases.close();
}
