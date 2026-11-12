import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_transport/src/download_transport.dart';
import 'package:download_transport/src/range_validation.dart';
import 'package:download_transport/src/resource_info.dart';
import 'package:logging/logging.dart';

final _log = Logger('HttpTransport');

/// `dart:io` HttpClient implementation of [DownloadTransport].
class HttpTransport implements DownloadTransport {
  HttpTransport({
    HttpClient? client,
    this.connectionTimeout = const Duration(seconds: 15),
    this.requestTimeout = const Duration(seconds: 30),
  }) : _client = client ?? (HttpClient()..autoUncompress = false) {
    _client.connectionTimeout = connectionTimeout;
  }

  final HttpClient _client;

  /// Timeout for establishing a connection.
  final Duration connectionTimeout;

  /// Timeout for a probe or range-validation request (not for streams).
  final Duration requestTimeout;

  @override
  Future<ResourceInfo> probe(Uri url) async {
    try {
      final response = await _request('HEAD', url).timeout(requestTimeout);
      if (response.statusCode == HttpStatus.methodNotAllowed ||
          response.statusCode == HttpStatus.notImplemented) {
        await response.drain<void>();
        _log.fine('HEAD not allowed for $url; falling back to range GET');
        return await _probeWithRange(url);
      }
      if (response.statusCode >= HttpStatus.badRequest) {
        await response.drain<void>();
        _throwForStatus(url, response.statusCode);
      }
      final info = _resourceInfo(url, response);
      await response.drain<void>();
      _log.fine(
        'Probed $url: ${info.contentLength} bytes, '
        'range=${info.supportsRange}',
      );
      return info;
    } on DownloadError {
      rethrow;
    } on TimeoutException {
      throw DownloadError(
        'timeout',
        'Probe timed out after ${requestTimeout.inSeconds}s: $url',
      );
    } on SocketException catch (e) {
      throw DownloadError('network', e.message);
    } on HttpException catch (e) {
      throw DownloadError('network', e.message);
    }
  }

  @override
  Future<RangeValidation> validateRange(
    Uri url, {
    required int start,
    required int end,
  }) async {
    try {
      final response = await _request(
        'GET',
        url,
        headers: {'range': 'bytes=$start-$end'},
      ).timeout(requestTimeout);
      try {
        if (response.statusCode == HttpStatus.ok) {
          return const RangeValidation.invalid(
            'Server ignored Range and returned 200; use single-stream mode',
          );
        }
        if (response.statusCode != HttpStatus.partialContent) {
          _throwForStatus(url, response.statusCode);
        }
        final contentRange = response.headers.value('content-range');
        final parsed = _parseContentRange(contentRange);
        if (parsed == null) {
          return const RangeValidation.invalid(
            'Missing or malformed Content-Range header',
          );
        }
        final (rangeStart, rangeEnd, total) = parsed;
        if (rangeStart != start || rangeEnd != end) {
          return RangeValidation.invalid(
            'Content-Range $contentRange does not match requested '
            'bytes $start-$end',
          );
        }
        final expectedLength = end - start + 1;
        final contentLength = response.headers.contentLength;
        if (contentLength >= 0 && contentLength != expectedLength) {
          return RangeValidation.invalid(
            'Body length $contentLength does not match requested range '
            'length $expectedLength',
          );
        }
        return RangeValidation.valid(totalBytes: total);
      } finally {
        await response.drain<void>();
      }
    } on DownloadError {
      rethrow;
    } on TimeoutException {
      throw DownloadError(
        'timeout',
        'Range validation timed out after ${requestTimeout.inSeconds}s: $url',
      );
    } on SocketException catch (e) {
      throw DownloadError('network', e.message);
    } on HttpException catch (e) {
      throw DownloadError('network', e.message);
    }
  }

  @override
  Stream<List<int>> openStream(
    Uri url, {
    int? start,
    int? end,
    String? ifRange,
  }) async* {
    final headers = <String, String>{};
    if (start != null) {
      headers['range'] = end != null ? 'bytes=$start-$end' : 'bytes=$start-';
    }
    if (ifRange != null) {
      headers['if-range'] = ifRange;
    }
    final response = await _openResponse(url, headers);
    if (response.statusCode == HttpStatus.partialContent) {
      yield* _withNetworkErrors(response);
    } else if (response.statusCode == HttpStatus.ok) {
      if (start != null && (start != 0 || end != null)) {
        // A bounded range (or a resume from a non-zero offset) was
        // requested but the server answered 200 with the whole file:
        // it ignored the Range. Fail fast instead of streaming the
        // full body into a segment offset, which would write wrong
        // bytes up to the segment length and only then trigger the
        // fallback (progress reaching 100% first, then resetting
        // to 0). An open `bytes=0-` request is excluded: a 200 there
        // is the full file, which is exactly what a single-stream
        // download (and the fallback) wants.
        await response.drain<void>();
        throw const DownloadError(
          'range-ignored',
          'Server ignored Range and returned 200',
        );
      }
      yield* _withNetworkErrors(response);
    } else {
      await response.drain<void>();
      _throwForStatus(url, response.statusCode);
    }
  }

  /// Converts a dropped connection mid-body into a transient network
  /// error. Errors from a `yield*` stream bypass a try/catch around
  /// the yield, so the conversion has to happen on the stream itself:
  /// the task retries a DownloadError('network') instead of failing
  /// on the raw HttpException.
  Stream<List<int>> _withNetworkErrors(Stream<List<int>> source) {
    return source.handleError((Object error) {
      if (error is SocketException) {
        throw DownloadError('network', error.message);
      }
      if (error is HttpException) {
        throw DownloadError('network', error.message);
      }
      throw error;
    });
  }

  @override
  void close() {
    _client.close();
  }

  Future<HttpClientResponse> _openResponse(
    Uri url,
    Map<String, String> headers,
  ) async {
    try {
      return await _request('GET', url, headers: headers);
    } on SocketException catch (e) {
      throw DownloadError('network', e.message);
    } on HttpException catch (e) {
      throw DownloadError('network', e.message);
    }
  }

  Future<HttpClientResponse> _request(
    String method,
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final request = await _client.openUrl(method, url);
    // File downloads want the raw bytes: never let the server send a
    // compressed body whose Content-Length no longer matches it.
    request.headers.set('accept-encoding', 'identity');
    headers?.forEach(request.headers.set);
    return request.close();
  }

  Future<ResourceInfo> _probeWithRange(Uri url) async {
    try {
      final response = await _request(
        'GET',
        url,
        headers: {'range': 'bytes=0-0'},
      ).timeout(requestTimeout);
      try {
        if (response.statusCode == HttpStatus.partialContent) {
          final total = _parseContentRangeTotal(
            response.headers.value('content-range'),
          );
          final info = _resourceInfo(url, response);
          return total == null ? info : info.copyWith(contentLength: total);
        }
        if (response.statusCode == HttpStatus.ok) {
          return _resourceInfo(url, response);
        }
        _throwForStatus(url, response.statusCode);
      } finally {
        await response.drain<void>();
      }
    } on DownloadError {
      rethrow;
    } on TimeoutException {
      throw DownloadError(
        'timeout',
        'Probe timed out after ${requestTimeout.inSeconds}s: $url',
      );
    } on SocketException catch (e) {
      throw DownloadError('network', e.message);
    } on HttpException catch (e) {
      throw DownloadError('network', e.message);
    }
  }

  ResourceInfo _resourceInfo(Uri url, HttpClientResponse response) {
    final headers = response.headers;
    final contentLength = headers.contentLength;
    return ResourceInfo(
      finalUrl: _finalUrl(url, response),
      statusCode: response.statusCode,
      contentLength: contentLength >= 0 ? contentLength : null,
      supportsRange: headers.value('accept-ranges') == 'bytes',
      eTag: headers.value('etag'),
      lastModified: headers.value('last-modified'),
      contentDisposition: headers.value('content-disposition'),
      contentType: headers.contentType?.mimeType,
      fileName: _fileName(url, headers.value('content-disposition')),
    );
  }

  Uri _finalUrl(Uri url, HttpClientResponse response) {
    if (response.redirects.isEmpty) {
      return url;
    }
    return response.redirects.last.location;
  }

  String _fileName(Uri url, String? contentDisposition) {
    if (contentDisposition != null) {
      final match = RegExp(
        'filename\\*?=(?:UTF-8\'\')?"?([^";]+)"?',
      ).firstMatch(contentDisposition);
      if (match != null) {
        final name = Uri.decodeComponent(match.group(1)!).trim();
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    if (url.pathSegments.isNotEmpty && url.pathSegments.last.isNotEmpty) {
      return url.pathSegments.last;
    }
    return 'download';
  }

  (int, int, int?)? _parseContentRange(String? contentRange) {
    if (contentRange == null) {
      return null;
    }
    final match = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+|\*)$',
    ).firstMatch(contentRange.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null) {
      return null;
    }
    final totalText = match.group(3)!;
    final total = totalText == '*' ? null : int.tryParse(totalText);
    if (totalText != '*' && total == null) {
      return null;
    }
    return (start, end, total);
  }

  int? _parseContentRangeTotal(String? contentRange) {
    return _parseContentRange(contentRange)?.$3;
  }

  Never _throwForStatus(Uri url, int statusCode) {
    throw DownloadError('http-$statusCode', 'HTTP $statusCode for $url');
  }
}
