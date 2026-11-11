import 'package:download_core/download_core.dart';

/// A download waiting to run, or paused mid-run.
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.url,
    required this.fileName,
    required this.directory,
    required this.priority,
    required this.maxConnections,
    required this.sequence,
    this.resumeFrom = const [],
    this.resumeExisting = false,
    this.overwrite = false,
  });

  final String id;
  final String url;
  final String fileName;
  final String directory;
  final int priority;
  final int maxConnections;

  /// Enqueue order; breaks priority ties (earlier first).
  final int sequence;

  /// Checkpointed progress to resume from, when this job restarts a
  /// download that already has bytes on disk.
  final List<SegmentProgress> resumeFrom;

  /// Open the existing partial file instead of creating a new one.
  final bool resumeExisting;

  /// Replace the final file when the download finishes, instead of
  /// failing when it already exists.
  final bool overwrite;
}
