import 'dart:convert';

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

/// One progress update for a single yt-dlp stream (one format), as
/// printed by the `--progress-template` line (see
/// [parseYtDlpStreamProgress]).
class YtDlpStreamUpdate {
  const YtDlpStreamUpdate({
    required this.formatId,
    required this.finished,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  /// The format this update belongs to (`137`, `140`, ...).
  final String formatId;

  /// True for yt-dlp's `finished` progress status: this stream is
  /// fully downloaded and the next one (or post-processing) follows.
  final bool finished;

  /// Bytes of this stream downloaded so far.
  final int downloadedBytes;

  /// Total bytes of this stream, or -1 when unknown.
  final int totalBytes;

  /// Current speed in bytes per second (0 when yt-dlp reports none).
  final int bytesPerSecond;
}

/// The streams one run is going to download, as printed by the
/// `--print before_dl:` line before any transfer starts.
class YtDlpStreamPlan {
  const YtDlpStreamPlan({required this.formatIds, required this.sizes});

  /// The format ids, in download order.
  final List<String> formatIds;

  /// The planned size of each stream, parallel to [formatIds]. Null
  /// when yt-dlp did not know it.
  final List<int?> sizes;

  /// The combined size of every stream, or null when any of them is
  /// unknown.
  int? get totalBytes {
    var sum = 0;
    for (final size in sizes) {
      if (size == null) {
        return null;
      }
      sum += size;
    }
    return sum;
  }
}

/// A progress update as the download is shown to the user: the whole
/// run, not one of its streams, so the percent never drops back to 0
/// when a second stream starts.
class YtDlpRunProgress {
  const YtDlpRunProgress({
    required this.percent,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  /// 0-99 while the process runs. A progress line means bytes are
  /// still moving (or the merge is still ahead), so 100 is left to
  /// the completed event; a row that shows 100% and then keeps working
  /// reads as the download restarting.
  final double percent;

  /// Bytes downloaded so far. With a plan this is the sum over every
  /// stream, so it never goes backwards.
  final int downloadedBytes;

  /// The combined size of every stream, or -1 when unknown.
  final int totalBytes;

  /// Current speed in bytes per second (0 when yt-dlp reports none).
  final int bytesPerSecond;
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

/// The prefix of the `--progress-template` line the downloader asks
/// yt-dlp to print. Kept here so the flag and the parser agree.
const ytDlpProgressPrefix = 'PDMPROGRESS';

/// The `--progress-template` value paired with [ytDlpProgressPrefix]:
/// one machine-readable line per update, with the stream's format id
/// so a run of several streams can be told apart.
const ytDlpProgressTemplate =
    'download:$ytDlpProgressPrefix|%(progress.status)s|'
    '%(info.format_id)s|%(progress.downloaded_bytes)s|'
    '%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|'
    '%(progress.speed)s';

/// The prefix of the `--print before_dl:` line (see
/// [ytDlpStreamPlanPrint]).
const ytDlpPlanPrefix = 'PDMPLAN';

/// The `--print` value paired with [ytDlpPlanPrefix]: the formats this
/// run will download, printed once before the first transfer. The `j`
/// conversion emits JSON, which is parsed rather than split.
const ytDlpStreamPlanPrint =
    'before_dl:$ytDlpPlanPrefix|%(requested_formats.:.format_id)j|'
    '%(requested_formats.:.filesize)j|'
    '%(requested_formats.:.filesize_approx)j|%(format_id)s|'
    '%(filesize)j|%(filesize_approx)j';

int? _parseOptionalInt(String value) => double.tryParse(value)?.round();

int _speedOrZero(String value) {
  final n = double.tryParse(value);
  if (n == null || n.isNaN || n < 0) {
    return 0;
  }
  return n.round();
}

/// Parses one `--progress-template` line. Returns null for anything
/// else, including a line with too few fields.
YtDlpStreamUpdate? parseYtDlpStreamProgress(String line) {
  if (!line.startsWith('$ytDlpProgressPrefix|')) {
    return null;
  }
  final parts = line.split('|');
  if (parts.length < 7) {
    return null;
  }
  final formatId = parts[2].trim();
  if (formatId.isEmpty || formatId == 'NA') {
    return null;
  }
  final downloaded = _parseOptionalInt(parts[3]);
  final total = _parseOptionalInt(parts[4]);
  final estimate = _parseOptionalInt(parts[5]);
  return YtDlpStreamUpdate(
    formatId: formatId,
    finished: parts[1] == 'finished',
    downloadedBytes: downloaded ?? 0,
    totalBytes: total ?? estimate ?? -1,
    bytesPerSecond: _speedOrZero(parts[6]),
  );
}

/// Parses the `--print before_dl:` line into the run's stream plan,
/// or null when the line is not a plan.
YtDlpStreamPlan? parseYtDlpStreamPlan(String line) {
  if (!line.startsWith('$ytDlpPlanPrefix|')) {
    return null;
  }
  final parts = line.split('|');
  if (parts.length < 7) {
    return null;
  }
  final ids = _parseJsonList(parts[1]);
  final sizes = _parseJsonList(parts[2]);
  final approxSizes = _parseJsonList(parts[3]);
  if (ids.isNotEmpty) {
    return YtDlpStreamPlan(
      formatIds: [for (final id in ids) '$id'],
      sizes: [
        for (var i = 0; i < ids.length; i++)
          _asInt(i < sizes.length ? sizes[i] : null) ??
              _asInt(i < approxSizes.length ? approxSizes[i] : null),
      ],
    );
  }
  // A single-format run prints `[]` for requested_formats; its id is
  // in the format_id field and its size in filesize/filesize_approx.
  final formatId = parts[4].trim();
  if (formatId.isEmpty || formatId == 'NA') {
    return null;
  }
  return YtDlpStreamPlan(
    formatIds: [formatId],
    sizes: [_parseOptionalInt(parts[5]) ?? _parseOptionalInt(parts[6])],
  );
}

List<dynamic> _parseJsonList(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is List ? decoded : const [];
  } catch (_) {
    return const [];
  }
}

int? _asInt(dynamic value) => value is num ? value.round() : null;

/// Folds the per-stream updates of one yt-dlp run into a single
/// monotonic run: yt-dlp downloads each stream separately (a
/// `<video>+bestaudio` pick is two passes, each printing its own
/// 0→100%), so the raw percent is not the download's progress. This
/// keeps the reported percent from ever dropping back and holds it
/// below 100 until yt-dlp finished, so a finished stream is not shown
/// as the whole download completing.
class YtDlpProgressTracker {
  YtDlpProgressTracker({YtDlpStreamPlan? plan}) : _plan = plan;

  YtDlpStreamPlan? _plan;
  final _doneBytes = <String, int>{};

  /// The plan known so far (null until yt-dlp printed it).
  YtDlpStreamPlan? get plan => _plan;

  /// Adopts a plan that arrived mid-run: the print line can race the
  /// first progress line, and the plan makes every later byte count
  /// comparable.
  void applyPlan(YtDlpStreamPlan plan) {
    _plan = plan;
  }

  /// Folds one stream update into the run's progress.
  YtDlpRunProgress update(YtDlpStreamUpdate stream) {
    if (stream.finished) {
      final known = _doneBytes[stream.formatId] ?? 0;
      if (stream.downloadedBytes > known) {
        _doneBytes[stream.formatId] = stream.downloadedBytes;
      }
    }
    final plan = _plan;
    if (plan != null) {
      return _updateWithPlan(plan, stream);
    }
    return _updateWithoutPlan(stream);
  }

  YtDlpRunProgress _updateWithPlan(
    YtDlpStreamPlan plan,
    YtDlpStreamUpdate stream,
  ) {
    final downloaded = _completedBytes(plan, stream.formatId) +
        stream.downloadedBytes;
    // Every stream's contribution is the size it really transferred:
    // the finished ones report it, and the running one reports its own
    // total. The plan's `filesize` is only yt-dlp's estimate and can be
    // far off (a real 5 MB plan entry transferred 2.7 MB), which would
    // leave the run stuck below 100% after the last stream finished.
    // The plan is what supplies the streams that have not started yet.
    final total = _runTotal(plan, stream);
    if (total == null || total <= 0) {
      return YtDlpRunProgress(
        percent: 0,
        downloadedBytes: downloaded,
        totalBytes: -1,
        bytesPerSecond: stream.bytesPerSecond,
      );
    }
    return YtDlpRunProgress(
      percent: _clampPercent(downloaded, total),
      downloadedBytes: downloaded,
      totalBytes: total,
      bytesPerSecond: stream.bytesPerSecond,
    );
  }

  /// The run's total from what is known right now: real bytes for the
  /// streams that already ran, the current stream's own total, and the
  /// plan's estimate for the ones still ahead. Null (unknown) when a
  /// stream has no size — the denominator would only grow as the run
  /// goes on, which makes the reported percent fall back on its own.
  int? _runTotal(YtDlpStreamPlan plan, YtDlpStreamUpdate stream) {
    final current = plan.formatIds.indexOf(stream.formatId);
    if (current < 0) {
      // yt-dlp downloaded a format the plan did not name (a fallback
      // pick), so the plan cannot size this run.
      return null;
    }
    var total = 0;
    for (var i = 0; i < plan.formatIds.length; i++) {
      final known = i == current
          ? (stream.totalBytes > 0 ? stream.totalBytes : plan.sizes[i])
          : (_doneBytes[plan.formatIds[i]] ?? plan.sizes[i]);
      if (known == null) {
        return null;
      }
      total += known;
    }
    return total;
  }

  /// Bytes of the streams that finished before [currentFormatId], in
  /// plan order. A finished stream still reports its own bytes, so it
  /// is counted through [_doneBytes] rather than added again.
  int _completedBytes(YtDlpStreamPlan plan, String currentFormatId) {
    var sum = 0;
    final seen = <String>{};
    for (final id in plan.formatIds) {
      if (id == currentFormatId) {
        break;
      }
      final size = _doneBytes[id] ??
          (plan.sizes[plan.formatIds.indexOf(id)]);
      if (size != null && seen.add(id)) {
        sum += size;
      }
    }
    return sum;
  }

  /// Without a plan the run's total is unknown: report the current
  /// stream's own progress while it is the only stream known, but once
  /// a stream finished, the run's total can no longer be derived (the
  /// next stream's size is not known up front), so the total turns
  /// unknown rather than a denominator that grows mid-run — that would
  /// make the reported percent fall back on its own.
  YtDlpRunProgress _updateWithoutPlan(YtDlpStreamUpdate stream) {
    final completed = _doneBytes.entries
        .where((entry) => entry.key != stream.formatId)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final streamTotal = stream.totalBytes;
    final downloaded = completed + stream.downloadedBytes;
    if (streamTotal <= 0 || completed > 0) {
      return YtDlpRunProgress(
        percent: 0,
        downloadedBytes: downloaded,
        totalBytes: -1,
        bytesPerSecond: stream.bytesPerSecond,
      );
    }
    return YtDlpRunProgress(
      percent: _clampPercent(downloaded, streamTotal),
      downloadedBytes: downloaded,
      totalBytes: streamTotal,
      bytesPerSecond: stream.bytesPerSecond,
    );
  }

  /// 0-99: only yt-dlp completing proves the whole file (and its
  /// post-processing) is done, so a finished stream must not read as
  /// 100% while the merge is still ahead.
  double _clampPercent(int downloaded, int total) {
    if (total <= 0) {
      return 0;
    }
    final percent = downloaded * 100 / total;
    return percent.clamp(0, 99).toDouble();
  }
}
