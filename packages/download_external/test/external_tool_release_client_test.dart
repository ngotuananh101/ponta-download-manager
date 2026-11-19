import 'dart:convert';
import 'dart:io';

import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

Map<String, Object?> asset(String name, {String? digest}) => {
  'name': name, 'size': 3, 'id': 1,
  'digest': digest ?? 'sha256:${'a' * 64}',
  'browser_download_url': 'https://github.com/example/releases/download/latest/$name',
};

ToolHttpResponse response(int code, {Object? json, Map<String, String> headers = const {}}) =>
    ToolHttpResponse(code, headers, Stream.value(json == null ? [] : utf8.encode(jsonEncode(json))));

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('tool-releases-'));
  tearDown(() async => temp.delete(recursive: true));

  test('selects the newest stable static x64 ffmpeg asset through repository redirects', () async {
    final urls = <String>[];
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (uri, headers) async {
      urls.add(uri.toString());
      if (urls.length == 1) return response(301, headers: {'location': '/repositories/292087234/releases/latest'});
      return response(200, json: {'tag_name': 'latest', 'id': 1, 'assets': [
        asset('ffmpeg-master-latest-linux64-gpl.tar.xz'),
        asset('ffmpeg-n10.0-latest-linux64-gpl-shared-10.0.tar.xz'),
        asset('ffmpeg-n10.0-latest-linuxarm64-gpl-10.0.tar.xz'),
        asset('ffmpeg-n8.1-latest-linux64-gpl-8.1.tar.xz'),
        asset('ffmpeg-n9.0-latest-linux64-gpl-9.0.tar.xz'),
      ]});
    });
    final release = await client.latest(ExternalTool.ffmpeg, isWindows: false);
    expect(urls, ['https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest',
      'https://api.github.com/repositories/292087234/releases/latest']);
    expect(release.version, '9.0');
    expect(release.archiveFormat, ToolArchiveFormat.tarXz);
    expect(release.sha256, 'a' * 64);
  });

  test('reuses validated cached metadata on 304, including across clients', () async {
    final first = ExternalToolReleaseClient(cacheDirectory: temp, request: (uri, headers) async {
      expect(uri.path, '/repos/quickjs-ng/quickjs/releases/latest');
      expect(headers, isNot(contains('If-None-Match')));
      return response(200, headers: {'etag': '"qjs"'}, json: {'id': 1,
        'tag_name': 'v0.19.0', 'assets': [asset('qjs-windows-x86_64.exe')]});
    });
    expect((await first.latest(ExternalTool.quickjs, isWindows: true)).version, '0.19.0');
    final next = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, headers) async {
      expect(headers['If-None-Match'], '"qjs"');
      return response(304);
    });
    expect((await next.latest(ExternalTool.quickjs, isWindows: true)).version, '0.19.0');
  });

  test('retries a cacheless 304 once and surfaces rate limits', () async {
    var requests = 0;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (uri, headers) async {
      expect(uri.path, '/repos/yt-dlp/yt-dlp/releases/latest');
      expect(headers, isNot(contains('If-None-Match')));
      return response(++requests == 1 ? 304 : 429);
    });
    await expectLater(client.latest(ExternalTool.ytDlp, isWindows: false), throwsFormatException);
    expect(requests, 2);
  });

  for (final digest in [null, 'sha256:123', 'sha256:${'z' * 64}']) {
    test('rejects unusable release digest $digest', () async {
      final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async => response(200,
        json: {'id': 1, 'tag_name': '2026.10.26', 'assets': [
          {...asset('yt-dlp_linux'), 'digest': digest},
        ]}));
      await expectLater(client.latest(ExternalTool.ytDlp, isWindows: false), throwsFormatException);
    });
  }

  test('rejects an unrelated redirect without contacting its destination', () async {
    var count = 0;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (_, _) async {
      count++;
      return response(302, headers: {'location': 'https://example.com/file'});
    });
    await expectLater(client.latest(ExternalTool.ytDlp, isWindows: false), throwsFormatException);
    expect(count, 1);
  });

  test('streams a release through the CDN and refuses truncated bodies', () async {
    final release = ExternalToolRelease(tool: ExternalTool.ytDlp, version: '2026.10.26',
      url: Uri.https('github.com', '/releases/asset'), sha256: 'a' * 64, sizeBytes: 3,
      archiveFormat: ToolArchiveFormat.executable, releaseId: '1');
    final target = File('${temp.path}/download');
    var truncate = false;
    final client = ExternalToolReleaseClient(cacheDirectory: temp, request: (uri, _) async {
      if (uri.host == 'github.com') {
        return response(302, headers: {'location': 'https://release-assets.githubusercontent.com/asset'});
      }
      return ToolHttpResponse(200, {'content-length': '3'}, Stream.fromIterable([
        [1], if (!truncate) [2, 3],
      ]));
    });
    final progress = <int>[];
    await client.download(release, target, onProgress: (received, _) => progress.add(received));
    expect(await target.readAsBytes(), [1, 2, 3]);
    expect(progress, [1, 3]);
    truncate = true;
    await expectLater(client.download(release, target), throwsFormatException);
  });
}
