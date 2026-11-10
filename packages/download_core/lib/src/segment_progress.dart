/// Checkpointed progress of one segment, used to resume a download
/// from where it stopped (docs/architecture.md §7.4).
class SegmentProgress {
  const SegmentProgress({
    required this.segmentId,
    required this.start,
    required this.end,
    required this.downloaded,
  });

  final int segmentId;
  final int start;
  final int? end;
  final int downloaded;
}
