import 'dart:io';

import 'external_tool_versions.dart';

enum ExternalToolOrigin { downloaded, bundled, system, missing }
enum ToolArchiveFormat { executable, tarXz, zip }

typedef ToolProcessRunner = Future<ProcessResult> Function(
  String executable, List<String> arguments);

class ExternalToolRelease {
  const ExternalToolRelease({required this.tool, required this.version,
    required this.url, required this.sha256, required this.sizeBytes,
    required this.archiveFormat, required this.releaseId});

  final ExternalTool tool;
  final String version;
  final Uri url;
  final String sha256;
  final int sizeBytes;
  final ToolArchiveFormat archiveFormat;
  final String releaseId;
}

class ExternalToolStatus {
  const ExternalToolStatus({required this.tool, required this.origin,
    this.path, this.currentVersion, this.latest, this.checkError,
    this.hasDownloadedCopy = false});

  final ExternalTool tool;
  final ExternalToolOrigin origin;
  final String? path;
  final String? currentVersion;
  final ExternalToolRelease? latest;
  final String? checkError;
  final bool hasDownloadedCopy;

  bool get hasUpdate {
    final current = currentVersion;
    final release = latest;
    return current != null && release != null && checkError == null &&
        compareToolVersions(release.version, current) > 0;
  }
}

class ExternalToolsSnapshot {
  ExternalToolsSnapshot(Iterable<ExternalToolStatus> tools)
      : tools = List.unmodifiable(tools);

  final List<ExternalToolStatus> tools;
  bool get hasUpdates => tools.any((status) => status.hasUpdate);
  bool get hasDownloadedUpdates => tools.any((status) => status.hasDownloadedCopy);
}

class ToolMutationResult {
  const ToolMutationResult({required this.tool, required this.changed, this.error});

  final ExternalTool tool;
  final bool changed;
  final String? error;
}

class ToolUpdateProgress {
  const ToolUpdateProgress({required this.tool, required this.receivedBytes,
    this.totalBytes, required this.phase});

  final ExternalTool tool;
  final int receivedBytes;
  final int? totalBytes;
  final String phase;
}
