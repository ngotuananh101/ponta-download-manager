import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdm-external-tools-');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<String> makeBundled(String name, {bool executable = true}) async {
    final bin = Directory(p.join(tmp.path, 'bin'));
    await bin.create(recursive: true);
    final file = File(p.join(bin.path, name));
    await file.writeAsString('#!/bin/sh\nexit 0\n');
    if (executable) {
      await Process.run('chmod', ['+x', file.path]);
    }
    return file.path;
  }

  test('prefers the bundled binary over PATH', () async {
    final bundled = await makeBundled('ffmpeg');
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (_) async => '/usr/bin/ffmpeg',
      versionCheck: (_) async => true,
    );
    expect(tools.ffmpegPath, bundled);
    expect(tools.ffmpegAvailable, isTrue);
  });

  test('falls back to PATH when the bundled binary is missing', () async {
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (name) async =>
          name == 'yt-dlp' ? '/usr/local/bin/yt-dlp' : null,
      versionCheck: (_) async => true,
    );
    expect(tools.ffmpegPath, isNull);
    expect(tools.ytDlpPath, '/usr/local/bin/yt-dlp');
    expect(tools.available, isFalse);
  });

  test('returns null when neither bundled nor PATH has the tool',
      () async {
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (_) async => null,
      versionCheck: (_) async => true,
    );
    expect(tools.ffmpegPath, isNull);
    expect(tools.ytDlpPath, isNull);
    expect(tools.available, isFalse);
  });

  test('falls back to PATH when the bundled binary fails --version',
      () async {
    await makeBundled('ffmpeg');
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (_) async => '/usr/bin/ffmpeg',
      versionCheck: (path) async => !path.contains(tmp.path),
    );
    expect(tools.ffmpegPath, '/usr/bin/ffmpeg');
  });

  test('returns null when the PATH binary fails --version', () async {
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (_) async => '/usr/bin/ffmpeg',
      versionCheck: (_) async => false,
    );
    expect(tools.ffmpegPath, isNull);
  });

  test('the default check accepts ffmpeg with its -version flag',
      () async {
    // Real ffmpeg exits 8 for --version and 0 for -version. The
    // default check must use -version or the bundled ffmpeg never
    // resolves. No versionCheck injection here: this exercises the
    // real default.
    final bin = Directory(p.join(tmp.path, 'bin'));
    await bin.create(recursive: true);
    final file = File(p.join(bin.path, 'ffmpeg'));
    await file.writeAsString(
      '#!/bin/sh\n'
      'if [ "\$1" = "-version" ]; then\n'
      '  echo "ffmpeg version 7.0.2-static"\n'
      '  exit 0\n'
      'else\n'
      '  echo "ffmpeg version 7.0.2-static" >&2\n'
      '  exit 8\n'
      'fi\n',
    );
    await Process.run('chmod', ['+x', file.path]);
    final tools = await ExternalTools.resolve(executableDir: tmp.path);
    expect(tools.ffmpegPath, file.path);
  });

  test('available is true only when both tools resolve', () async {
    await makeBundled('ffmpeg');
    await makeBundled('yt-dlp');
    final tools = await ExternalTools.resolve(
      executableDir: tmp.path,
      pathLookup: (_) async => null,
      versionCheck: (_) async => true,
    );
    expect(tools.available, isTrue);
  });
}
