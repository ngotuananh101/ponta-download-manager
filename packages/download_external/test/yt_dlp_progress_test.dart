import 'package:download_external/download_external.dart';
import 'package:test/test.dart';

void main() {
  test('parses a standard progress line', () {
    final p = parseYtDlpProgress(
      '[download]  45.2% of  123.45MiB at  1.23MiB/s ETA 00:30',
    );
    expect(p, isNotNull);
    expect(p!.percent, 45.2);
    expect(p.totalBytes, (123.45 * 1024 * 1024).round());
    expect(p.bytesPerSecond, (1.23 * 1024 * 1024).round());
    expect(
      p.downloadedBytes,
      (123.45 * 1024 * 1024 * 45.2 / 100).round(),
    );
  });

  test('parses KiB and GiB units', () {
    final kib = parseYtDlpProgress(
      '[download]  10.0% of  512.00KiB at  64.00KiB/s ETA 00:07',
    );
    expect(kib!.totalBytes, (512 * 1024).round());
    expect(kib.bytesPerSecond, (64 * 1024).round());
    final gib = parseYtDlpProgress(
      '[download]  99.9% of  2.50GiB at  10.00MiB/s ETA 00:01',
    );
    expect(gib!.totalBytes, (2.5 * 1024 * 1024 * 1024).round());
  });

  test('parses an unknown total', () {
    final p = parseYtDlpProgress(
      '[download]  12.0% of Unknown at  512.00KiB/s ETA 01:00',
    );
    expect(p, isNotNull);
    expect(p!.totalBytes, -1);
    expect(p.downloadedBytes, -1);
    expect(p.bytesPerSecond, (512 * 1024).round());
  });

  test('parses the 100% line without a speed', () {
    final p = parseYtDlpProgress('[download] 100% of  123.45MiB in 00:01');
    expect(p, isNotNull);
    expect(p!.percent, 100);
    expect(p.totalBytes, (123.45 * 1024 * 1024).round());
    expect(p.bytesPerSecond, 0);
    expect(p.downloadedBytes, p.totalBytes);
  });

  test('parses an estimated total with a tilde', () {
    final p = parseYtDlpProgress(
      '[download]  30.0% of ~ 50.00MiB at  2.00MiB/s ETA 00:17',
    );
    expect(p, isNotNull);
    expect(p!.totalBytes, (50 * 1024 * 1024).round());
  });

  test('returns null for non-progress lines', () {
    expect(
      parseYtDlpProgress('[download] Destination: /tmp/live.m3u8.mp4'),
      isNull,
    );
    expect(
      parseYtDlpProgress('[Merger] Merging formats into "/tmp/live.mp4"'),
      isNull,
    );
    expect(parseYtDlpProgress('[youtube] Extracting URL'), isNull);
    expect(parseYtDlpProgress(''), isNull);
    expect(parseYtDlpProgress('garbage'), isNull);
  });
}
