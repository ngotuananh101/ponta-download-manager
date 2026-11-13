import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/core/services/drop_target_channel.dart';
import 'package:pdm/features/downloads/presentation/drop_parsing.dart';

void main() {
  group('parseDroppedContent', () {
    test('uri-list: one URL per line, comments and blanks skipped', () {
      final result = parseDroppedContent(
        const DropPayload(
          uris: ['https://example.com/a.zip', 'https://example.com/b.zip'],
          text: '# comment\nhttps://example.com/a.zip\n\n',
        ),
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
        const DropPayload(text: 'https://example.com/a.zip'),
      );
      expect(result.urls, ['https://example.com/a.zip']);
    });

    test('plain text that is not a URL is ignored', () {
      final result = parseDroppedContent(
        const DropPayload(text: 'hello world'),
      );
      expect(result.urls, isEmpty);
    });

    test('the same URL in several representations is deduped', () {
      final result = parseDroppedContent(
        const DropPayload(
          uris: ['https://example.com/a.zip'],
          text: 'https://example.com/a.zip',
        ),
      );
      expect(result.urls, ['https://example.com/a.zip']);
    });

    test('non-http(s) URIs are skipped', () {
      final result = parseDroppedContent(
        const DropPayload(
          uris: ['file:///home/user/a.zip', 'ftp://example.com/b.zip'],
        ),
      );
      expect(result.urls, isEmpty);
    });

    test('a .torrent file is flagged, other files are flagged separately', () {
      final result = parseDroppedContent(
        const DropPayload(
          files: ['/home/user/ubuntu.torrent', '/home/user/notes.txt'],
        ),
      );
      expect(result.urls, isEmpty);
      expect(result.hasTorrent, isTrue);
      expect(result.hasOtherFile, isTrue);
    });

    test('torrent detection is case-insensitive', () {
      final result = parseDroppedContent(
        const DropPayload(files: ['/home/user/Ubuntu.TORRENT']),
      );
      expect(result.hasTorrent, isTrue);
      expect(result.hasOtherFile, isFalse);
    });
  });
}
