import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'external_tool_release.dart';
import 'external_tool_release_client.dart';
import 'external_tool_versions.dart';

class ExternalToolInstaller {
  ExternalToolInstaller({required this.userToolsDirectory, required this.releases,
    ToolProcessRunner? runProcess, bool? isWindows,
    Future<void> Function(String source, String target)? replaceFile,
    Future<void> Function(String path)? deleteFile})
      : _runProcess = runProcess, _replaceFile = replaceFile,
        _deleteFile = deleteFile, isWindows = isWindows ?? Platform.isWindows;

  final Directory userToolsDirectory;
  final ExternalToolReleaseClient releases;
  final ToolProcessRunner? _runProcess;
  final Future<void> Function(String source, String target)? _replaceFile;
  final Future<void> Function(String path)? _deleteFile;
  final bool isWindows;

  Future<bool> hasDownloadedCopy(ExternalTool tool) async =>
      await FileSystemEntity.type(_target(tool).path, followLinks: false) !=
          FileSystemEntityType.notFound;

  File _target(ExternalTool tool) => File(p.join(userToolsDirectory.path,
      tool.executableName(isWindows: isWindows)));

  Future<void> _validateDirectory() async {
    final type = await FileSystemEntity.type(userToolsDirectory.path, followLinks: false);
    if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.directory) {
      throw const FileSystemException('Tools directory must not be a symbolic link');
    }
    await userToolsDirectory.create(recursive: true);
  }

  Future<ToolMutationResult> install(ExternalToolRelease release,
      {void Function(ToolUpdateProgress)? onProgress, String? currentVersion}) async {
    Directory? staging;
    var changed = false;
    try {
      if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(release.sha256)) {
        throw const FormatException('Invalid SHA-256 digest');
      }
      await _validateDirectory();
      final target = _target(release.tool);
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.file) {
        throw const FileSystemException('Managed executable is not a regular file');
      }
      staging = await userToolsDirectory.createTemp('.install-');
      final artifact = File(p.join(staging.path, 'artifact'));
      await releases.download(release, artifact, onProgress: (received, total) =>
        onProgress?.call(ToolUpdateProgress(tool: release.tool, receivedBytes: received,
          totalBytes: total, phase: 'Downloading')));
      final digest = await sha256.bind(artifact.openRead()).first;
      if (digest.toString() != release.sha256.toLowerCase()) {
        throw const FormatException('SHA-256 digest mismatch');
      }
      onProgress?.call(ToolUpdateProgress(tool: release.tool, receivedBytes: release.sizeBytes,
        totalBytes: release.sizeBytes, phase: 'Verifying'));
      final executable = File(p.join(staging.path, release.tool.executableName(isWindows: isWindows)));
      if (release.archiveFormat == ToolArchiveFormat.executable) {
        await artifact.rename(executable.path);
      } else {
        if (release.tool != ExternalTool.ffmpeg ||
            (isWindows && release.archiveFormat != ToolArchiveFormat.zip) ||
            (!isWindows && release.archiveFormat != ToolArchiveFormat.tarXz)) {
          throw const FormatException('Unsupported tool archive');
        }
        final source = artifact.path;
        final destination = executable.path;
        final format = release.archiveFormat;
        final windows = isWindows;
        await Isolate.run(() => _extractExecutable(source, destination, format, windows));
      }
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', ['700', executable.path]);
        if (chmod.exitCode != 0) throw const FileSystemException('Cannot mark executable');
      }
      final result = await (_runProcess?.call(executable.path, release.tool.versionArguments) ??
          _runVersion(executable.path, release.tool.versionArguments));
      final version = parseToolVersion(release.tool, '${result.stdout}\n${result.stderr}');
      if (result.exitCode != 0 || version == null ||
          !isToolVersionCompatible(release.tool, version, release.version) ||
          (currentVersion != null && compareToolVersions(version, currentVersion) < 0)) {
        throw const FormatException('Downloaded executable failed version verification');
      }
      // Same-filesystem rename replaces an existing file atomically. Never unlink
      // the previous binary first: on a sharing violation it must remain usable.
      await (_replaceFile?.call(executable.path, target.path) ?? executable.rename(target.path));
      changed = true;
    } catch (error) {
      return ToolMutationResult(tool: release.tool, changed: changed, error: error.toString());
    } finally {
      try {
        await staging?.delete(recursive: true);
      } on FileSystemException {
        // An active scanner may delay deletion on Windows. Do not undo a valid install.
      }
    }
    return ToolMutationResult(tool: release.tool, changed: changed);
  }

  Future<ToolMutationResult> remove(ExternalTool tool) async {
    var changed = false;
    try {
      final dirType = await FileSystemEntity.type(userToolsDirectory.path, followLinks: false);
      if (dirType == FileSystemEntityType.notFound) return ToolMutationResult(tool: tool, changed: false);
      if (dirType != FileSystemEntityType.directory) throw const FileSystemException('Invalid tools directory');
      final target = _target(tool);
      final type = await FileSystemEntity.type(target.path, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        if (type != FileSystemEntityType.file) throw const FileSystemException('Managed executable is not a regular file');
        await (_deleteFile?.call(target.path) ?? target.delete());
        changed = true;
      }
    } catch (error) {
      return ToolMutationResult(tool: tool, changed: changed, error: error.toString());
    }
    return ToolMutationResult(tool: tool, changed: changed);
  }
}

/// Kills and reaps a health-check process on timeout; Future.timeout alone would
/// leave the verified staging executable locked on Windows.
Future<ProcessResult> _runVersion(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments);
  final stdout = process.stdout.transform(const SystemEncoding().decoder).join();
  final stderr = process.stderr.transform(const SystemEncoding().decoder).join();
  try {
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    return ProcessResult(process.pid, code, await stdout, await stderr);
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    await Future.wait([stdout, stderr]);
    rethrow;
  }
}

void _extractExecutable(String source, String destination, ToolArchiveFormat format, bool windows) {
  const expandedLimit = 2 * 1024 * 1024 * 1024;
  const executableLimit = 512 * 1024 * 1024;
  var entries = 0;
  var expanded = 0;
  var selected = false;
  final expected = windows ? 'ffmpeg.exe' : 'ffmpeg';
  void validate(String name, int size, bool link) {
    if (++entries > 10000 || size < 0 || (expanded += size) > expandedLimit ||
        link || name.contains('\\') || name.startsWith('/') || name.contains(':') ||
        name.split('/').contains('..')) {
      throw const FormatException('Unsafe archive entry');
    }
  }
  bool select(String name, int size, bool regular) {
    final parts = name.split('/');
    if (parts.length != 3 || parts[0].isEmpty || parts[1] != 'bin' || parts[2] != expected) return false;
    if (selected || !regular || size <= 0 || size > executableLimit) {
      throw const FormatException('Invalid or duplicate ffmpeg executable');
    }
    selected = true;
    return true;
  }

  if (format == ToolArchiveFormat.tarXz) {
    // Decode XZ to a bounded *file*, not a memory buffer. Tar then consumes the
    // seekable file; RAM remains independent of the archive's expanded size.
    final tarPath = '$source.tar';
    final compressed = InputFileStream(source);
    final tarOutput = OutputFileStream(tarPath);
    try {
      XZDecoder(maxDictionarySize: 64 * 1024 * 1024).decodeStream(compressed, tarOutput,
        verify: true, throwOnError: true, maxOutputSize: expandedLimit);
    } finally {
      tarOutput.closeSync();
      compressed.closeSync();
    }
    final tar = InputFileStream(tarPath);
    try {
      TarDecoder().decodeStream(tar, verify: true, throwOnError: true,
        keepEntries: false, callback: (entry) {
          validate(entry.name, entry.size, entry.isSymbolicLink || entry.isHardLink);
          if (select(entry.name, entry.size, entry.isFile)) {
            final output = OutputFileStream(destination);
            try {
              entry.writeContent(output);
            } finally {
              output.closeSync();
            }
          }
        });
    } finally {
      tar.closeSync();
    }
  } else {
    final input = InputFileStream(source);
    try {
      final directory = ZipDirectory();
      for (final header in directory.headers(input, verify: true)) {
        final file = header.file!;
        final mode = header.externalFileAttributes >> 16;
        final fileType = mode & 0xf000;
        validate(file.filename, file.uncompressedSize,
          fileType != 0 && fileType != 0x8000 && fileType != 0x4000);
        if (select(file.filename, file.uncompressedSize, !file.filename.endsWith('/') && fileType != 0x4000)) {
          file.verify = true;
          file.throwOnError = true;
          final output = OutputFileStream(destination);
          try {
            file.decompress(output);
          } finally {
            output.closeSync();
          }
        }
      }
    } finally {
      input.closeSync();
    }
  }
  if (!selected) throw const FormatException('Archive has no ffmpeg executable');
}
