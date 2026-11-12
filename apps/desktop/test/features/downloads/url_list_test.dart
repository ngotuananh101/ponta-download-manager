import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/url_list.dart';

void main() {
  group('parseUrlList', () {
    test('splits lines, trims whitespace, keeps http(s) only', () {
      expect(
        parseUrlList(
          '  https://example.com/a.bin  \n'
          'http://example.com/b.bin\n'
          'ftp://example.com/c.bin\n'
          'not a url\n',
        ),
        ['https://example.com/a.bin', 'http://example.com/b.bin'],
      );
    });

    test('drops blank lines and dedupes, keeping the first occurrence',
        () {
      expect(
        parseUrlList(
          'https://example.com/a.bin\n'
          '\n'
          'https://example.com/a.bin\n'
          'https://example.com/b.bin\n',
        ),
        ['https://example.com/a.bin', 'https://example.com/b.bin'],
      );
    });

    test('handles CRLF line endings and an uppercase scheme', () {
      expect(
        parseUrlList(
          'HTTPS://example.com/a.bin\r\nhttps://example.com/b.bin\r\n',
        ),
        ['HTTPS://example.com/a.bin', 'https://example.com/b.bin'],
      );
    });

    test('empty or whitespace-only input parses to no urls', () {
      expect(parseUrlList(''), isEmpty);
      expect(parseUrlList('  \n\n  '), isEmpty);
    });
  });
}
