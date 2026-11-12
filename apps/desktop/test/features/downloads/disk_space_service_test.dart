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

    test('parsePowerShellFree reads a plain byte count', () {
      expect(DiskSpaceService.parsePowerShellFree('123456789\n'), 123456789);
      expect(
        DiskSpaceService.parsePowerShellFree('  123456789  \n'),
        123456789,
      );
    });

    test('parsePowerShellFree returns null for garbage', () {
      expect(DiskSpaceService.parsePowerShellFree('nothing here\n'), isNull);
      expect(DiskSpaceService.parsePowerShellFree(''), isNull);
    });

    test('windowsDriveLetter takes the drive letter of a Windows path',
        () {
      expect(
        DiskSpaceService.windowsDriveLetter(r'C:\Users\anhnt\Downloads'),
        'C',
      );
      expect(DiskSpaceService.windowsDriveLetter(r'D:\Downloads'), 'D');
      expect(DiskSpaceService.windowsDriveLetter('/home/anhnt'), isNull);
      expect(
        DiskSpaceService.windowsDriveLetter(r'\\server\share\dir'),
        isNull,
      );
    });
  });

  test('freeBytes reports the temp dir free space', () async {
    const service = DiskSpaceService();
    final free = await service.freeBytes(Directory.systemTemp.path);
    expect(free, isNotNull);
    expect(free, greaterThan(0));
  });
}
