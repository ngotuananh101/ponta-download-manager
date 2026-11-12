import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:download_api/download_api.dart';

/// Verifies a finished file on disk (architecture §5.1): it exists,
/// and — when the expected size is known — its size matches. When an
/// expected SHA-256 is given, the file's hash must match too. When the
/// expected size is unknown (negative), the result is unknownSize:
/// the file exists and is readable, but its size was not checked.
class IntegrityVerifier {
  const IntegrityVerifier();

  Future<IntegrityResult> verify({
    required String path,
    required int expectedBytes,
    String? expectedSha256,
  }) async {
    // statSync reports a path it cannot resolve (missing, or
    // through a non-directory) as notFound instead of throwing.
    final FileStat stat;
    try {
      stat = FileStat.statSync(path);
    } on FileSystemException catch (e) {
      return IntegrityResult.unreadable(message: e.message);
    }
    if (stat.type == FileSystemEntityType.notFound) {
      return const IntegrityResult.missing();
    }
    if (stat.type != FileSystemEntityType.file) {
      return IntegrityResult.unreadable(message: '$path is not a file');
    }
    // The size is known without reading, but readability is part of
    // "intact": a file we cannot open cannot be used.
    try {
      File(path).openSync(mode: FileMode.read).closeSync();
    } on FileSystemException catch (e) {
      return IntegrityResult.unreadable(message: e.message);
    }
    if (expectedBytes < 0) {
      // The file exists and is readable, but its expected size was
      // never known, so the size was not checked.
      return IntegrityResult.unknownSize(bytes: stat.size);
    }
    if (stat.size != expectedBytes) {
      return IntegrityResult.sizeMismatch(
        expectedBytes: expectedBytes,
        actualBytes: stat.size,
      );
    }
    if (expectedSha256 != null) {
      final digest = await sha256.bind(File(path).openRead()).first;
      final actual = digest.toString();
      if (actual != expectedSha256.toLowerCase()) {
        return IntegrityResult.checksumMismatch(
          expectedSha256: expectedSha256,
          actualSha256: actual,
        );
      }
    }
    return IntegrityResult.ok(bytes: stat.size);
  }
}
