import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/disk_space_service.dart';

void main() {
  group('DiskSpaceService parsers', () {
    test('parseDfAvail reads the available 1K blocks', () {
      expect(
        DiskSpaceService.parseDfAvail('Avail\n  12345678\n'),
        12345678 * 1024,
      );
    });

    test('parseDfAvail returns null for garbage', () {
      expect(DiskSpaceService.parseDfAvail('nonsense\n'), isNull);
      expect(DiskSpaceService.parseDfAvail('Avail\nnot-a-number\n'), isNull);
    });

    test('parseDf reads the Available column', () {
      const output = '''
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/sda1       12345678 1234567   8765432  13% /
''';
      expect(DiskSpaceService.parseDf(output), 8765432 * 1024);
    });

    test('parseDf returns null for garbage', () {
      expect(DiskSpaceService.parseDf('nonsense\n'), isNull);
    });

    test('parseFsutil reads the free-bytes line', () {
      const output = '''
Total # of free bytes        : 123456789
Total # of bytes             : 987654321
Total # of avail free bytes  : 123456789
''';
      expect(DiskSpaceService.parseFsutil(output), 123456789);
    });

    test('parseFsutil returns null when the line is missing', () {
      expect(DiskSpaceService.parseFsutil('nothing here\n'), isNull);
    });
  });

  test('freeBytes reports the temp dir free space', () async {
    const service = DiskSpaceService();
    final free = await service.freeBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });
}
