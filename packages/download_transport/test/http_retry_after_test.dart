import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_transport/download_transport.dart';
import 'package:test/test.dart';

void main() {
  test('rejects an ignored range without draining the response body', () async {
    final stopped = Completer<void>();
    final body = StreamController<List<int>>(onCancel: stopped.complete);
    final transport = HttpTransport(
      client: FakeHttpClient((method, uri, headers) async {
        return FakeHttpClientResponse(statusCode: HttpStatus.ok, body: body.stream);
      }),
    );
    addTearDown(transport.close);
    final request = transport.openStream(
      Uri.parse('https://example.com/file'), start: 4, end: 7,
    ).drain<void>();
    try {
      await expectLater(
        request.timeout(const Duration(seconds: 1)),
        throwsA(isA<DownloadError>().having((e) => e.code, 'code', 'range-ignored')),
      );
      expect(stopped.isCompleted, isTrue);
    } finally {
      await body.close();
    }
  });

  group('DownloadError', () {
    test('preserves existing positional API and defaults retryAfter to null',
        () {
      const error = DownloadError('http-500', 'HTTP 500 for https://x');
      expect(error.code, 'http-500');
      expect(error.message, 'HTTP 500 for https://x');
      expect(error.retryAfter, isNull);
    });

    test('accepts optional named retryAfter', () {
      const error = DownloadError(
        'http-429',
        'HTTP 429 for https://x',
        retryAfter: Duration(seconds: 30),
      );
      expect(error.code, 'http-429');
      expect(error.message, 'HTTP 429 for https://x');
      expect(error.retryAfter, const Duration(seconds: 30));
    });
  });

  group('HttpTransport Retry-After', () {
    test('probe supplies retryAfter for HTTP 429 delta-seconds', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'retry-after': '120'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.message, 'message',
                  'HTTP 429 for https://example.com/file')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 120)),
        ),
      );
    });

    test('probe supplies retryAfter for HTTP 503 HTTP-date', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.serviceUnavailable,
            headers: {
              'retry-after': HttpDate.format(
                DateTime.now().toUtc().add(const Duration(seconds: 60)),
              ),
            },
          );
        }),
      );
      addTearDown(transport.close);

      try {
        await transport.probe(Uri.parse('https://example.com/file'));
        fail('expected DownloadError');
      } on DownloadError catch (e) {
        expect(e.code, 'http-503');
        expect(e.message, 'HTTP 503 for https://example.com/file');
        expect(e.retryAfter, isNotNull);
        // Allow small clock drift between header formatting and parsing.
        expect(e.retryAfter!.inSeconds, inInclusiveRange(55, 65));
      }
    });

    test('caps a far-future HTTP-date Retry-After', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.serviceUnavailable,
            headers: {
              'retry-after': HttpDate.format(DateTime.utc(9999, 12, 31)),
            },
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-503')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 2147483648)),
        ),
      );
    });

    test('past HTTP-date yields nonnegative zero retryAfter', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {
              'retry-after': HttpDate.format(
                DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
              ),
            },
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.retryAfter, 'retryAfter', Duration.zero),
        ),
      );
    });

    test('valid long delta-seconds is preserved (no early retry coercion)',
        () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.serviceUnavailable,
            headers: {'retry-after': '86400'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-503')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 86400)),
        ),
      );
    });

    for (final value in ['9223372036854775807', '9223372036854775808']) {
      test('saturates an oversized delta-seconds value ($value)', () async {
        final transport = HttpTransport(
          client: FakeHttpClient((method, uri, headers) async {
            return FakeHttpClientResponse(
              statusCode: HttpStatus.tooManyRequests,
              headers: {'retry-after': value},
            );
          }),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.probe(Uri.parse('https://example.com/file')),
          throwsA(
            isA<DownloadError>()
                .having((e) => e.code, 'code', 'http-429')
                .having((e) => e.retryAfter, 'retryAfter',
                    const Duration(seconds: 2147483648)),
          ),
        );
      });
    }

    test('invalid Retry-After is ignored', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'retry-after': 'not-a-date-or-number'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('negative delta-seconds is ignored', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'retry-after': '-5'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('429/503 without Retry-After keeps retryAfter null', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.serviceUnavailable,
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-503')
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });

    test('openStream supplies retryAfter for HTTP 429 delta-seconds', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'retry-after': '7'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport
            .openStream(Uri.parse('https://example.com/file'))
            .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk)),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.message, 'message',
                  'HTTP 429 for https://example.com/file')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 7)),
        ),
      );
    });

    test('validateRange supplies retryAfter for HTTP 503', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.serviceUnavailable,
            headers: {'retry-after': '15'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.validateRange(
          Uri.parse('https://example.com/file'),
          start: 0,
          end: 99,
        ),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-503')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 15)),
        ),
      );
    });

    test('range-probe fallback supplies retryAfter for HTTP 429', () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          if (method == 'HEAD') {
            return FakeHttpClientResponse(
              statusCode: HttpStatus.methodNotAllowed,
            );
          }
          return FakeHttpClientResponse(
            statusCode: HttpStatus.tooManyRequests,
            headers: {'retry-after': '3'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-429')
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 3)),
        ),
      );
    });

    test('non-429/503 HTTP errors do not get retryAfter from header',
        () async {
      final transport = HttpTransport(
        client: FakeHttpClient((method, uri, headers) async {
          return FakeHttpClientResponse(
            statusCode: HttpStatus.notFound,
            headers: {'retry-after': '120'},
          );
        }),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.probe(Uri.parse('https://example.com/file')),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'http-404')
              .having((e) => e.retryAfter, 'retryAfter', isNull),
        ),
      );
    });
  });
}

typedef _OpenHandler = Future<HttpClientResponse> Function(
  String method,
  Uri url,
  FakeHttpHeaders requestHeaders,
);

class _NoSuchMethodBase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeHttpClient extends _NoSuchMethodBase implements HttpClient {
  FakeHttpClient(this._handler);

  final _OpenHandler _handler;

  @override
  Duration? connectionTimeout;

  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final headers = FakeHttpHeaders();
    return FakeHttpClientRequest(method, url, headers, _handler);
  }

  @override
  void close({bool force = false}) {}
}

class FakeHttpClientRequest extends _NoSuchMethodBase
    implements HttpClientRequest {
  FakeHttpClientRequest(this._method, this._url, this._headers, this._handler);

  final String _method;
  final Uri _url;
  final FakeHttpHeaders _headers;
  final _OpenHandler _handler;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() => _handler(_method, _url, _headers);
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse({
    required this.statusCode,
    Map<String, String>? headers,
    List<List<int>>? bodyChunks,
    Stream<List<int>>? body,
    List<RedirectInfo>? redirects,
  })  : _headers = FakeHttpHeaders(initial: headers),
        _body = body ?? Stream<List<int>>.fromIterable(bodyChunks ?? const []),
        _redirects = redirects ?? const [];

  @override
  final int statusCode;
  final FakeHttpHeaders _headers;
  final Stream<List<int>> _body;
  final List<RedirectInfo> _redirects;

  @override
  HttpHeaders get headers => _headers;

  @override
  List<RedirectInfo> get redirects => _redirects;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _body.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeHttpHeaders extends _NoSuchMethodBase implements HttpHeaders {
  FakeHttpHeaders({Map<String, String>? initial}) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = '$value';
  }

  @override
  int get contentLength {
    final raw = _values['content-length'];
    if (raw == null) return -1;
    return int.tryParse(raw) ?? -1;
  }

  @override
  set contentLength(int contentLength) {
    _values['content-length'] = '$contentLength';
  }

  @override
  ContentType? get contentType {
    final raw = _values['content-type'];
    if (raw == null) return null;
    return ContentType.parse(raw);
  }
}
