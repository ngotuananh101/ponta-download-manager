import 'dart:io';

import 'package:pdm_engine/pdm_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolveUniquePath', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-naming-test-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns the path itself when free', () {
      expect(
        resolveUniquePath(p.join(tempDir.path, 'f.bin')),
        p.join(tempDir.path, 'f.bin'),
      );
    });

    test('adds (1) then (2)', () async {
      final first = p.join(tempDir.path, 'f.bin');
      await File(first).writeAsString('old');
      expect(resolveUniquePath(first), p.join(tempDir.path, 'f (1).bin'));
      await File(p.join(tempDir.path, 'f (1).bin')).writeAsString('old');
      expect(resolveUniquePath(first), p.join(tempDir.path, 'f (2).bin'));
    });

    test('strips an existing (N) suffix', () async {
      await File(p.join(tempDir.path, 'f (1).bin')).writeAsString('old');
      expect(
        resolveUniquePath(p.join(tempDir.path, 'f (1).bin')),
        p.join(tempDir.path, 'f (2).bin'),
      );
    });

    test('handles extension-less names', () async {
      final readme = p.join(tempDir.path, 'README');
      await File(readme).writeAsString('old');
      expect(resolveUniquePath(readme), p.join(tempDir.path, 'README (1)'));
    });

    test('keeps multi-dot extensions together', () async {
      final archive = p.join(tempDir.path, 'archive.tar.gz');
      await File(archive).writeAsString('old');
      expect(
        resolveUniquePath(archive),
        p.join(tempDir.path, 'archive.tar (1).gz'),
      );
    });

    test('honours a custom isTaken predicate', () {
      final taken = {'/tmp/f.bin', '/tmp/f (1).bin'};
      expect(
        resolveUniquePath('/tmp/f.bin', isTaken: taken.contains),
        '/tmp/f (2).bin',
      );
    });
  });
}
