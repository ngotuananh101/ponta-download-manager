import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:download_integrity/download_integrity.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('IntegrityVerifier', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pdm-integrity-');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    const verifier = IntegrityVerifier();

    test('ok when the file exists with the expected size', () async {
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes(List<int>.generate(2048, (i) => i % 256));
      final result = await verifier.verify(
        path: file.path,
        expectedBytes: 2048,
      );
      expect(result, const IntegrityResult.ok(bytes: 2048));
    });

    test('missing when the file is gone', () async {
      final result = await verifier.verify(
        path: p.join(tempDir.path, 'nope.bin'),
        expectedBytes: 2048,
      );
      expect(result, const IntegrityResult.missing());
    });

    test('sizeMismatch when the file changed', () async {
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes(List<int>.generate(1024, (i) => i % 256));
      final result = await verifier.verify(
        path: file.path,
        expectedBytes: 2048,
      );
      expect(
        result,
        const IntegrityResult.sizeMismatch(
          expectedBytes: 2048,
          actualBytes: 1024,
        ),
      );
    });

    test('unknown total is existence-only', () async {
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes(List<int>.generate(512, (i) => i % 256));
      final result = await verifier.verify(
        path: file.path,
        expectedBytes: -1,
      );
      expect(result, const IntegrityResult.ok(bytes: 512));
    });

    test('checksum match is ok', () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes(bytes);
      final result = await verifier.verify(
        path: file.path,
        expectedBytes: bytes.length,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(result, IntegrityResult.ok(bytes: bytes.length));
    });

    test('checksum mismatch is reported', () async {
      final bytes = List<int>.generate(256, (i) => i % 256);
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes(bytes);
      final wrong =
          sha256.convert(List<int>.generate(256, (i) => 0)).toString();
      final result = await verifier.verify(
        path: file.path,
        expectedBytes: bytes.length,
        expectedSha256: wrong,
      );
      expect(
        result,
        IntegrityResult.checksumMismatch(
          expectedSha256: wrong,
          actualSha256: sha256.convert(bytes).toString(),
        ),
      );
    });

    test('unreadable when the path is not a file', () async {
      final result = await verifier.verify(
        path: tempDir.path,
        expectedBytes: 3,
      );
      result.when(
        ok: (_) => fail('expected unreadable'),
        missing: () => fail('expected unreadable'),
        sizeMismatch: (_, _) => fail('expected unreadable'),
        checksumMismatch: (_, _) => fail('expected unreadable'),
        unreadable: (_) {},
      );
    });

    test('unreadable when the file cannot be read', () async {
      final file = File(p.join(tempDir.path, 'f.bin'));
      await file.writeAsBytes([1, 2, 3]);
      await Process.run('chmod', ['000', file.path]);
      try {
        final result = await verifier.verify(
          path: file.path,
          expectedBytes: 3,
        );
        result.when(
          ok: (_) => fail('expected unreadable'),
          missing: () => fail('expected unreadable'),
          sizeMismatch: (_, _) => fail('expected unreadable'),
          checksumMismatch: (_, _) => fail('expected unreadable'),
          unreadable: (_) {},
        );
      } finally {
        await Process.run('chmod', ['644', file.path]);
      }
    });
  });
}
