/// One byte range of a download (docs/architecture.md §5.4).
class Segment {
  const Segment({required this.id, required this.start, required this.end});

  /// Stable id, 0-based, in download order.
  final int id;

  /// First byte (inclusive).
  final int start;

  /// Last byte (inclusive), or null for an open-ended segment
  /// (unknown total length).
  final int? end;

  /// Length in bytes, or null for an open-ended segment.
  int? get length => end == null ? null : end! - start + 1;
}
