import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('installer-'));
  tearDown(() async => temp.delete(recursive: true));

  ExternalToolRelease release(List<int> bytes, {String? digest, ExternalTool tool = ExternalTool.ytDlp}) =>
      ExternalToolRelease(tool: tool, version: tool == ExternalTool.ytDlp ? '2026.11.19' : '0.19.0',
        url: Uri.https('github.com', '/binary'), sha256: digest ?? sha256.convert(bytes).toString(),
        sizeBytes: bytes.length, archiveFormat: ToolArchiveFormat.executable, releaseId: '1');

  test('digest mismatch leaves old binary untouched and never executes downloaded bytes', () async {
    final old = await File('${temp.path}/yt-dlp').writeAsString('old');
    var processes = 0;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
      ToolHttpResponse(200, {}, Stream.value([1, 2, 3])));
    final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
      runProcess: (_, _) async { processes++; return ProcessResult(1, 0, '2026.11.19', ''); });
    final result = await installer.install(release([1, 2, 3], digest: 'a' * 64));
    expect(result.changed, isFalse);
    expect(result.error, contains('SHA-256'));
    expect(processes, 0);
    expect(await old.readAsString(), 'old');
    expect((await temp.list().toList()).map((e) => e.path), [old.path]);
  });

  test('installs verified executable then removes only managed files', () async {
    final unrelated = await File('${temp.path}/pdm-native-host').writeAsString('keep');
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
      ToolHttpResponse(200, {}, Stream.value([1, 2, 3])));
    final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
      runProcess: (executable, args) async {
        expect(args, ['--version']);
        expect(await File(executable).readAsBytes(), [1, 2, 3]);
        return ProcessResult(1, 0, '2026.11.19', '');
      });
    expect((await installer.install(release([1, 2, 3]))).changed, isTrue);
    expect(await File('${temp.path}/yt-dlp').readAsBytes(), [1, 2, 3]);
    expect((await installer.remove(ExternalTool.ytDlp)).changed, isTrue);
    expect(await unrelated.readAsString(), 'keep');
    expect(await File('${temp.path}/yt-dlp').exists(), isFalse);
  });

  test('accepts a patch-level ffmpeg build from the selected release family', () async {
    final bytes = [1, 2, 3];
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
      ToolHttpResponse(200, {}, Stream.value(bytes)));
    final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
      runProcess: (_, _) async => ProcessResult(1, 0, 'ffmpeg version n9.0.1-12-gabc', ''));
    final result = await installer.install(ExternalToolRelease(tool: ExternalTool.ffmpeg,
      version: '9.0', url: Uri.https('github.com', '/archive'),
      sha256: sha256.convert(bytes).toString(), sizeBytes: bytes.length,
      archiveFormat: ToolArchiveFormat.executable, releaseId: '1'));
    expect(result.changed, isTrue, reason: result.error);
  });

  test('replacement failure preserves old binary and reports unchanged', () async {
    final old = await File('${temp.path}/yt-dlp').writeAsString('old');
    final bytes = [1, 2, 3];
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
      ToolHttpResponse(200, {}, Stream.value(bytes)));
    final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
      runProcess: (_, _) async => ProcessResult(1, 0, '2026.11.19', ''),
      replaceFile: (_, _) async => throw const FileSystemException('sharing violation'));
    final result = await installer.install(release(bytes));
    expect(result.changed, isFalse);
    expect(result.error, contains('sharing violation'));
    expect(await old.readAsString(), 'old');
  });

  test('delete failure retains managed executable and reports unchanged', () async {
    final binary = await File('${temp.path}/yt-dlp').writeAsString('old');
    final installer = ExternalToolInstaller(userToolsDirectory: temp,
      releases: ExternalToolReleaseClient(cacheDirectory: temp),
      deleteFile: (_) async => throw const FileSystemException('sharing violation'));
    final result = await installer.remove(ExternalTool.ytDlp);
    expect(result.changed, isFalse);
    expect(result.error, contains('sharing violation'));
    expect(await binary.readAsString(), 'old');
  });

  test('failed version verification retains previous binary', () async {
    final old = await File('${temp.path}/yt-dlp').writeAsString('old');
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
      ToolHttpResponse(200, {}, Stream.value([1, 2, 3])));
    final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
      runProcess: (_, _) async => ProcessResult(1, 0, '2020.01.01', ''));
    expect((await installer.install(release([1, 2, 3]))).changed, isFalse);
    expect(await old.readAsString(), 'old');
  });

  for (final windows in [false, true]) {
    test('${windows ? 'zip' : 'tar.xz'} extraction does not send progress callback state to isolate', () async {
      final name = windows ? 'ffmpeg.exe' : 'ffmpeg';
      final archive = Archive()..add(ArchiveFile('distribution/bin/$name', 3, [1, 2, 3]));
      final bytes = windows ? ZipEncoder().encode(archive)
          : XZEncoder().encodeBytes(TarEncoder().encode(archive));
      final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
        ToolHttpResponse(200, {}, Stream.value(bytes)));
      final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
        isWindows: windows, runProcess: (_, _) async => ProcessResult(1, 0, 'ffmpeg version 9.0', ''));
      // A UI progress callback can retain unsendable Riverpod/Future state.
      // ReceivePort provides a deterministic equivalent without a Flutter dependency.
      final progressPort = ReceivePort();
      addTearDown(progressPort.close);
      final phases = <String>[];
      final result = await installer.install(ExternalToolRelease(tool: ExternalTool.ffmpeg,
        version: '9.0', url: Uri.https('github.com', '/archive'),
        sha256: sha256.convert(bytes).toString(), sizeBytes: bytes.length,
        archiveFormat: windows ? ToolArchiveFormat.zip : ToolArchiveFormat.tarXz, releaseId: '1'),
        onProgress: (progress) {
          progressPort.sendPort.send(progress.phase);
          phases.add(progress.phase);
        });
      expect(result.error, isNull);
      expect(result.changed, isTrue);
      expect(await File('${temp.path}/$name').readAsBytes(), [1, 2, 3]);
      expect(phases, containsAll(['Downloading', 'Verifying']));
    });

    for (final unsafe in [false, true]) {
      test('${windows ? 'zip' : 'tar.xz'} extracts only ffmpeg and rejects traversal=$unsafe', () async {
        final name = windows ? 'ffmpeg.exe' : 'ffmpeg';
        final archive = Archive()
          ..add(ArchiveFile('distribution/bin/$name', 3, [1, 2, 3]))
          ..add(ArchiveFile(unsafe ? '../escape' : 'distribution/readme', 1, [9]));
        final bytes = windows ? ZipEncoder().encode(archive)
            : XZEncoder().encodeBytes(TarEncoder().encode(archive));
        final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async =>
          ToolHttpResponse(200, {}, Stream.value(bytes)));
        final installer = ExternalToolInstaller(userToolsDirectory: temp, releases: client,
          isWindows: windows, runProcess: (path, args) async {
            expect(args, ['-version']);
            expect(await File(path).readAsBytes(), [1, 2, 3]);
            return ProcessResult(1, 0, 'ffmpeg version 9.0', '');
          });
        final result = await installer.install(ExternalToolRelease(tool: ExternalTool.ffmpeg,
          version: '9.0', url: Uri.https('github.com', '/archive'),
          sha256: sha256.convert(bytes).toString(), sizeBytes: bytes.length,
          archiveFormat: windows ? ToolArchiveFormat.zip : ToolArchiveFormat.tarXz, releaseId: '1'));
        expect(result.changed, !unsafe, reason: result.error);
        expect(await File('${temp.path}/$name').exists(), !unsafe);
        expect(await File('${temp.path}/readme').exists(), isFalse);
      });
    }
  }

  test('does not follow a managed executable symlink on removal', () async {
    final outside = await File('${temp.path}/unrelated').writeAsString('keep');
    await Link('${temp.path}/yt-dlp').create(outside.path);
    final installer = ExternalToolInstaller(userToolsDirectory: temp,
      releases: ExternalToolReleaseClient(cacheDirectory: temp));
    final result = await installer.remove(ExternalTool.ytDlp);
    expect(result.changed, isFalse);
    expect(result.error, isNotNull);
    expect(await outside.readAsString(), 'keep');
  });
}
