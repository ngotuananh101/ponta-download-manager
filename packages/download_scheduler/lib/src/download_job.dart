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
  });

  final String id;
  final String url;
  final String fileName;
  final String directory;
  final int priority;
  final int maxConnections;

  /// Enqueue order; breaks priority ties (earlier first).
  final int sequence;
}
