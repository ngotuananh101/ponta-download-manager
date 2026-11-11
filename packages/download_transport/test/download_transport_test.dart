import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:download_transport/download_transport.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late HttpTransport transport;
  late Uri base;

  final body = List<int>.generate(1024, (i) => i % 256);

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final path = request.uri.path;
      final response = request.response;
      try {
        if (path == '/not-found') {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        if (path == '/redirect') {
          response.statusCode = HttpStatus.found;
          response.headers.set('location', '/file');
          await response.close();
          return;
        }
        if (path == '/big') {
          // Large body: the client must receive data incrementally and
          // cancelling after the first chunk must stop the rest.
          const total = 5 * 1024 * 1024;
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = total;
          final chunk = List<int>.filled(80 * 1024, 7);
          for (var i = 0; i < 64; i++) {
            response.add(chunk);
            await response.flush();
          }
          await response.close();
          return;
        }
        if (path == '/no-head' && request.method == 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
          await response.close();
          return;
        }
        final total = path == '/no-head' ? 512 : 1024;
        final data = body.sublist(0, total);
        if (request.method == 'HEAD') {
          response.statusCode = HttpStatus.ok;
          response.headers.contentLength = total;
          if (path != '/no-range') {
            response.headers.set('accept-ranges', 'bytes');
          }
          response.headers.set('etag', '"v1"');
          response.headers.set(
            'last-modified',
            'Wed, 21 Oct 2015 07:28:00 GMT',
          );
          response.headers.contentType = ContentType(
            'application',
            'octet-stream',
          );
          response.headers.set(
            'content-disposition',
            'attachment; filename="archive.zip"',
          );
          await response.close();
          return;
        }
        final range = request.headers.value('range');
        if (range != null && path != '/no-range') {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range);
          if (match != null) {
            final start = int.parse(match.group(1)!);
            final endText = match.group(2)!;
            final end = endText.isEmpty ? total - 1 : int.parse(endText);
            response.statusCode = HttpStatus.partialContent;
            response.headers.set('accept-ranges', 'bytes');
            response.headers.set('content-range', 'bytes $start-$end/$total');
            response.headers.contentLength = end - start + 1;
            response.add(data.sublist(start, end + 1));
            await response.close();
            return;
          }
        }
        response.statusCode = HttpStatus.ok;
        response.headers.contentLength = total;
        response.add(data);
        await response.close();
      } catch (_) {
        // Client went away (cancel test) — ignore.
      }
    });
    transport = HttpTransport();
  });

  tearDownAll(() async {
    transport.close();
    await server.close(force: true);
  });

  group('probe', () {
    test('returns size, range support, validators and file name', () async {
      final info = await transport.probe(base.resolve('/file'));
      expect(info.statusCode, HttpStatus.ok);
      expect(info.contentLength, 1024);
      expect(info.supportsRange, isTrue);
      expect(info.eTag, '"v1"');
      expect(info.lastModified, 'Wed, 21 Oct 2015 07:28:00 GMT');
      expect(info.contentType, 'application/octet-stream');
      expect(info.fileName, 'archive.zip');
    });

    test('follows redirects and reports the final URL', () async {
      final info = await transport.probe(base.resolve('/redirect'));
      expect(info.finalUrl.path, '/file');
      expect(info.contentLength, 1024);
    });

    test('falls back to a range GET when HEAD is not allowed', () async {
      final info = await transport.probe(base.resolve('/no-head'));
      expect(info.contentLength, 512);
      expect(info.supportsRange, isTrue);
    });

    test('throws DownloadError on 404', () async {
      await expectLater(
        transport.probe(base.resolve('/not-found')),
        throwsA(isA<DownloadError>().having((e) => e.code, 'code', 'http-404')),
      );
    });
  });

  group('validateRange', () {
    test('accepts a matching 206 response', () async {
      final result = await transport.validateRange(
        base.resolve('/file'),
        start: 0,
        end: 99,
      );
      expect(result.valid, isTrue);
      expect(result.totalBytes, 1024);
    });

    test('rejects a server that ignores Range with 200', () async {
      final result = await transport.validateRange(
        base.resolve('/no-range'),
        start: 0,
        end: 99,
      );
      expect(result.valid, isFalse);
      expect(result.reason, isNotEmpty);
    });
  });

  group('openStream', () {
    test('downloads the exact bytes', () async {
      final bytes = await transport
          .openStream(base.resolve('/file'))
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      expect(bytes, body);
    });

    test('downloads an exact byte range', () async {
      final bytes = await transport
          .openStream(base.resolve('/file'), start: 100, end: 199)
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
      expect(bytes, body.sublist(100, 200));
    });

    test('throws DownloadError on 404', () async {
      await expectLater(
        transport
            .openStream(base.resolve('/not-found'))
            .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk)),
        throwsA(isA<DownloadError>().having((e) => e.code, 'code', 'http-404')),
      );
    });

    test('a 200 answer to a Range request throws range-ignored', () async {
      // /no-range ignores Range and answers 200 with the full body.
      // Yielding that body into a segment offset would write the
      // wrong bytes; the task must fail fast instead, before any
      // chunk is consumed.
      await expectLater(
        transport
            .openStream(base.resolve('/no-range'), start: 0, end: 99)
            .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk)),
        throwsA(
          isA<DownloadError>()
              .having((e) => e.code, 'code', 'range-ignored'),
        ),
      );
    });

    test('cancelling the stream stops the download', () async {
      final received = <int>[];
      final firstChunk = Completer<void>();
      final subscription = transport.openStream(base.resolve('/big')).listen((
        chunk,
      ) {
        received.addAll(chunk);
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
        }
      });
      await firstChunk.future.timeout(const Duration(seconds: 5));
      await subscription.cancel().timeout(const Duration(seconds: 2));
      expect(received.isNotEmpty, isTrue);
      expect(received.length, lessThan(5 * 1024 * 1024));
    });
  });
}
