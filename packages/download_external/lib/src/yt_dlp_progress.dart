/// A parsed yt-dlp `[download]` progress update.
class YtDlpProgress {
  const YtDlpProgress({
    required this.percent,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  /// 0-100.
  final double percent;

  /// Total bytes, or -1 when yt-dlp does not know it.
  final int totalBytes;

  /// Current speed in bytes per second (0 when yt-dlp reports none).
  final int bytesPerSecond;

  /// Bytes downloaded so far, derived from percent * total
  /// (-1 when the total is unknown).
  int get downloadedBytes =>
      totalBytes < 0 ? -1 : (totalBytes * percent / 100).round();
}

int _parseSize(String value, String unit) {
  final n = double.parse(value);
  switch (unit) {
    case 'B':
      return n.round();
    case 'KiB':
      return (n * 1024).round();
    case 'MiB':
      return (n * 1024 * 1024).round();
    case 'GiB':
      return (n * 1024 * 1024 * 1024).round();
    default:
      return -1;
  }
}

// `[download]  45.2% of  123.45MiB at  1.23MiB/s ETA 00:30`
// `[download] 100% of  123.45MiB in 00:01` (no speed at 100%)
// `[download]  12.0% of Unknown at  512.00KiB/s ETA 01:00`
// The total may carry a `~` (estimated size). Anything that is not a
// progress line (Destination, Merger, warnings) does not match.
final _progressPattern = RegExp(
  r'^\[download\]\s+(\d+(?:\.\d+)?)% of\s+~?\s*(?:Unknown|([\d.]+)(KiB|MiB|GiB|B))(?:\s+at\s+([\d.]+)(KiB|MiB|GiB|B)/s)?',
);

/// Parses one yt-dlp stdout line. Returns a [YtDlpProgress] for a
/// `[download] NN% of ...` line, null for anything else.
YtDlpProgress? parseYtDlpProgress(String line) {
  final match = _progressPattern.firstMatch(line);
  if (match == null) {
    return null;
  }
  final percent = double.parse(match.group(1)!);
  var totalBytes = -1;
  final totalValue = match.group(2);
  final totalUnit = match.group(3);
  if (totalValue != null && totalUnit != null) {
    totalBytes = _parseSize(totalValue, totalUnit);
  }
  var bytesPerSecond = 0;
  final speedValue = match.group(4);
  final speedUnit = match.group(5);
  if (speedValue != null && speedUnit != null) {
    bytesPerSecond = _parseSize(speedValue, speedUnit);
  }
  return YtDlpProgress(
    percent: percent,
    totalBytes: totalBytes,
    bytesPerSecond: bytesPerSecond,
  );
}
