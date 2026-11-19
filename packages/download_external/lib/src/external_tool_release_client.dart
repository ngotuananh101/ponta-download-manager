import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'external_tool_release.dart';
import 'external_tool_versions.dart';

typedef ToolHttpRequest = Future<ToolHttpResponse> Function(
  Uri uri, Map<String, String> headers);

class ToolHttpResponse {
  const ToolHttpResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;
}

class ExternalToolReleaseClient {
  ExternalToolReleaseClient({required this.cacheDirectory, ToolHttpRequest? request})
      : _requestOverride = request;

  final Directory cacheDirectory;
  final ToolHttpRequest? _requestOverride;
  HttpClient? _http;
  bool _closed = false;

  static const _metadataLimit = 2 * 1024 * 1024;
  static const _artifactLimit = 512 * 1024 * 1024;
  static const _hosts = {
    'api.github.com', 'github.com', 'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
  };
  static const _repositories = {
    ExternalTool.ffmpeg: 'BtbN/FFmpeg-Builds',
    ExternalTool.ytDlp: 'yt-dlp/yt-dlp',
    ExternalTool.quickjs: 'quickjs-ng/quickjs',
  };

  Future<ExternalToolRelease> latest(ExternalTool tool, {required bool isWindows}) async {
    final endpoint = Uri.https('api.github.com', '/repos/${_repositories[tool]}/releases/latest');
    final cache = File(p.join(cacheDirectory.path, '${tool.name}-${isWindows ? 'windows' : 'linux'}.json'));
    String? etag;
    ExternalToolRelease? cached;
    try {
      if (await cache.exists() && await cache.length() <= _metadataLimit * 2) {
        final entry = jsonDecode(await cache.readAsString()) as Map<String, dynamic>;
        cached = _parseRelease(tool, isWindows, entry['release']);
        etag = entry['etag'] as String;
        if (etag.isEmpty || etag.contains(RegExp(r'[\r\n]'))) etag = null;
      }
    } catch (_) {
      etag = null;
    }
    final headers = <String, String>{'Accept': 'application/vnd.github+json'};
    if (etag != null) headers['If-None-Match'] = etag;
    var response = await _get(endpoint, headers);
    if (response.statusCode == 304) {
      await _discard(response.body);
      if (etag != null && cached != null) return cached;
      response = await _get(endpoint, {'Accept': 'application/vnd.github+json'});
    }
    await _requireOk(response);
    final bytes = <int>[];
    await for (final chunk in _timedBody(response, const Duration(minutes: 2))) {
      if (bytes.length + chunk.length > _metadataLimit) {
        throw const FormatException('Release metadata is too large');
      }
      bytes.addAll(chunk);
    }
    final data = jsonDecode(utf8.decode(bytes));
    final release = _parseRelease(tool, isWindows, data);
    final nextEtag = response.headers['etag'];
    if (nextEtag != null) {
      await _writeCache(cache, jsonEncode({'etag': nextEtag, 'release': data}));
    }
    return release;
  }

  Future<void> _writeCache(File cache, String contents) async {
    Directory? staging;
    try {
      await cacheDirectory.create(recursive: true);
      staging = await cacheDirectory.createTemp('.metadata-');
      final file = await File(p.join(staging.path, 'release.json')).writeAsString(contents, flush: true);
      await file.rename(cache.path);
    } on FileSystemException {
      // Metadata caching is optional, even if app data is not writable.
    } finally {
      try {
        await staging?.delete(recursive: true);
      } on FileSystemException {
        // Never fail a successful check over cache cleanup.
      }
    }
  }

  ExternalToolRelease _parseRelease(ExternalTool tool, bool isWindows, Object? data) {
    if (data is! Map<String, dynamic> || data['assets'] is! List || data['id'] is! int) {
      throw const FormatException('Invalid GitHub release metadata');
    }
    final assets = (data['assets'] as List).whereType<Map<String, dynamic>>();
    final tag = data['tag_name'];
    Map<String, dynamic>? selected;
    String? version;
    var format = ToolArchiveFormat.executable;
    if (tool == ExternalTool.ffmpeg) {
      format = isWindows ? ToolArchiveFormat.zip : ToolArchiveFormat.tarXz;
      final platform = isWindows ? 'win64' : 'linux64';
      final extension = isWindows ? r'zip' : r'tar\.xz';
      final pattern = RegExp('^ffmpeg-n(\\d+(?:\\.\\d+)+)-latest-$platform-gpl-\\1\\.$extension\$');
      for (final asset in assets) {
        final name = asset['name'];
        final candidate = name is String ? pattern.firstMatch(name)?.group(1) : null;
        if (candidate != null && (version == null || compareToolVersions(candidate, version) > 0)) {
          version = candidate;
          selected = asset;
        }
      }
    } else {
      final name = switch (tool) {
        ExternalTool.ytDlp => isWindows ? 'yt-dlp.exe' : 'yt-dlp_linux',
        _ => isWindows ? 'qjs-windows-x86_64.exe' : 'qjs-linux-x86_64',
      };
      for (final asset in assets) {
        if (asset['name'] == name) {
          selected = asset;
          break;
        }
      }
      if (tag is String && RegExp(r'^v?\d+(?:\.\d+)+$').hasMatch(tag)) {
        version = parseToolVersion(tool, tag);
      }
    }
    if (selected == null || version == null) {
      throw const FormatException('No supported asset in the latest release');
    }
    final digest = selected['digest'];
    if (digest is! String || !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Release asset has no valid SHA-256 digest');
    }
    final size = selected['size'];
    final rawUrl = selected['browser_download_url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (size is! int || size <= 0 || size > _artifactLimit || url == null) {
      throw const FormatException('Invalid release asset size or URL');
    }
    _validateUri(url);
    return ExternalToolRelease(tool: tool, version: version, url: url,
      sha256: digest.substring(7).toLowerCase(), sizeBytes: size,
      archiveFormat: format, releaseId: '${data['id']}:${selected['id']}');
  }

  Future<void> download(ExternalToolRelease release, File target,
      {void Function(int received, int? total)? onProgress}) async {
    if (release.sizeBytes <= 0 || release.sizeBytes > _artifactLimit) {
      throw const FormatException('Invalid release asset size');
    }
    final response = await _get(release.url, const {});
    await _requireOk(response);
    final length = response.headers['content-length'];
    if (length != null && int.tryParse(length) != release.sizeBytes) {
      await _discard(response.body);
      throw const FormatException('Unexpected release size');
    }
    final file = await target.open(mode: FileMode.write);
    var received = 0;
    try {
      await for (final chunk in _timedBody(response, const Duration(minutes: 15))) {
        received += chunk.length;
        if (received > release.sizeBytes) throw const FormatException('Release exceeds its declared size');
        await file.writeFrom(chunk);
        onProgress?.call(received, release.sizeBytes);
      }
      if (received != release.sizeBytes) throw const FormatException('Incomplete release download');
      await file.flush();
    } finally {
      await file.close();
    }
  }

  Stream<List<int>> _timedBody(ToolHttpResponse response, Duration total) async* {
    final iterator = StreamIterator(response.body);
    final watch = Stopwatch()..start();
    try {
      while (true) {
        final remaining = total - watch.elapsed;
        if (remaining <= Duration.zero) throw TimeoutException('Release transfer timed out');
        const idle = Duration(seconds: 60);
        if (!await iterator.moveNext().timeout(remaining < idle ? remaining : idle)) break;
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  static void _validateUri(Uri uri) {
    if (uri.scheme != 'https' || !_hosts.contains(uri.host) ||
        uri.userInfo.isNotEmpty || uri.port != 443) {
      throw const FormatException('Untrusted GitHub release URL');
    }
  }

  Future<ToolHttpResponse> _get(Uri uri, Map<String, String> headers) async {
    for (var hop = 0; hop <= 5; hop++) {
      if (_closed) throw StateError('Release client is closed');
      _validateUri(uri);
      final response = await (_requestOverride ?? _request)(uri, {
        'User-Agent': 'DesktopUpdater', 'Accept-Encoding': 'identity', ...headers,
      }).timeout(const Duration(seconds: 60));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) return response;
      await _discard(response.body);
      final location = response.headers['location'];
      if (location == null) throw const FormatException('Missing GitHub redirect location');
      uri = uri.resolve(location);
    }
    throw const FormatException('Too many GitHub redirects');
  }

  static Future<void> _discard(Stream<List<int>> body) => body.listen(null).cancel();

  static Future<void> _requireOk(ToolHttpResponse response) async {
    if (response.statusCode != 200) {
      await _discard(response.body);
      throw FormatException('GitHub request failed (HTTP ${response.statusCode})');
    }
  }

  Future<ToolHttpResponse> _request(Uri uri, Map<String, String> headers) async {
    final http = _http ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = false;
    final request = await http.getUrl(uri);
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 60), onTimeout: () {
      request.abort();
      throw TimeoutException('GitHub did not respond');
    });
    final resultHeaders = <String, String>{};
    response.headers.forEach((name, values) => resultHeaders[name] = values.join(', '));
    return ToolHttpResponse(response.statusCode, resultHeaders, response);
  }

  void close() {
    _closed = true;
    _http?.close(force: true);
  }
}
