import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/presentation/drop_parsing.dart';

void main() {
  group('parseDroppedContent', () {
    test('uri-list: one URL per line, comments and blanks skipped', () {
      final result = parseDroppedContent(
        strings: [
          const DropStringItem(
            mimeType: 'text/uri-list',
            value:
                '# comment\nhttps://example.com/a.zip\n\nhttps://example.com/b.zip\n',
          ),
        ],
        fileNames: const [],
      );
      expect(result.urls, [
        'https://example.com/a.zip',
        'https://example.com/b.zip',
      ]);
      expect(result.hasTorrent, isFalse);
      expect(result.hasOtherFile, isFalse);
    });

    test('plain text URL is accepted', () {
      final result = parseDroppedContent(
        strings: [
          const DropStringItem(
            mimeType: 'text/plain',
            value: 'https://example.com/a.zip',
          ),
        ],
        fileNames: const [],
      );
      expect(result.urls, ['https://example.com/a.zip']);
    });

    test('plain text that is not a URL is ignored', () {
      final result = parseDroppedContent(
        strings: [
          const DropStringItem(mimeType: 'text/plain', value: 'hello world'),
        ],
        fileNames: const [],
      );
      expect(result.urls, isEmpty);
    });

    test('html is skipped and the same URL is deduped', () {
      final result = parseDroppedContent(
        strings: [
          const DropStringItem(
            mimeType: 'text/uri-list',
            value: 'https://example.com/a.zip\n',
          ),
          const DropStringItem(
            mimeType: 'text/html',
            value: '<a href="https://example.com/a.zip">a</a>',
          ),
          const DropStringItem(
            mimeType: 'text/plain',
            value: 'https://example.com/a.zip',
          ),
        ],
        fileNames: const [],
      );
      expect(result.urls, ['https://example.com/a.zip']);
    });

    test('non-http(s) and file:// URIs are skipped', () {
      final result = parseDroppedContent(
        strings: [
          const DropStringItem(
            mimeType: 'text/uri-list',
            value: 'file:///home/user/a.zip\nftp://example.com/b.zip\n',
          ),
        ],
        fileNames: const [],
      );
      expect(result.urls, isEmpty);
    });

    test('a .torrent file is flagged, other files are flagged separately',
        () {
      final result = parseDroppedContent(
        strings: const [],
        fileNames: const ['ubuntu.torrent', 'notes.txt'],
      );
      expect(result.urls, isEmpty);
      expect(result.hasTorrent, isTrue);
      expect(result.hasOtherFile, isTrue);
    });

    test('torrent detection is case-insensitive', () {
      final result = parseDroppedContent(
        strings: const [],
        fileNames: const ['Ubuntu.TORRENT'],
      );
      expect(result.hasTorrent, isTrue);
      expect(result.hasOtherFile, isFalse);
    });
  });
}
