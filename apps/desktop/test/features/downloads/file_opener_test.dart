import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdm/features/downloads/data/services/file_opener.dart';

void main() {
  group('FileOpener', () {
    test('openFile runs xdg-open on Linux', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'linux',
      );
      await opener.openFile('/home/anhnt/Downloads/f.bin');
      expect(calls, [
        ['xdg-open', '/home/anhnt/Downloads/f.bin'],
      ]);
    });

    test('showInFolder opens the containing directory on Linux', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'linux',
      );
      await opener.showInFolder('/home/anhnt/Downloads/f.bin');
      expect(calls, [
        ['xdg-open', '/home/anhnt/Downloads'],
      ]);
    });

    test('openFile uses open on macOS', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'macos',
      );
      await opener.openFile('/Users/anhnt/Downloads/f.bin');
      expect(calls, [
        ['open', '/Users/anhnt/Downloads/f.bin'],
      ]);
    });

    test('showInFolder reveals the file on macOS', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'macos',
      );
      await opener.showInFolder('/Users/anhnt/Downloads/f.bin');
      expect(calls, [
        ['open', '-R', '/Users/anhnt/Downloads/f.bin'],
      ]);
    });

    test('openFile uses explorer on Windows', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'windows',
      );
      await opener.openFile(r'C:\Users\anhnt\Downloads\f.bin');
      expect(calls, [
        ['explorer', r'C:\Users\anhnt\Downloads\f.bin'],
      ]);
    });

    test('showInFolder selects the file on Windows', () async {
      final calls = <List<String>>[];
      final opener = FileOpener(
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, '', '');
        },
        operatingSystem: 'windows',
      );
      await opener.showInFolder(r'C:\Users\anhnt\Downloads\f.bin');
      expect(calls, [
        ['explorer', r'/select,C:\Users\anhnt\Downloads\f.bin'],
      ]);
    });

    test('a non-zero exit throws', () async {
      final opener = FileOpener(
        run: (_, _) async => ProcessResult(0, 1, '', 'nope'),
        operatingSystem: 'linux',
      );
      await expectLater(
        opener.openFile('/home/anhnt/Downloads/f.bin'),
        throwsException,
      );
    });

    test('an unknown platform throws UnsupportedError', () async {
      final opener = FileOpener(
        run: (_, _) async => ProcessResult(0, 0, '', ''),
        operatingSystem: 'fuchsia',
      );
      await expectLater(
        opener.openFile('/home/anhnt/Downloads/f.bin'),
        throwsUnsupportedError,
      );
    });
  });
}
