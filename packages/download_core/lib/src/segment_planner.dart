import 'package:download_core/src/segment.dart';

/// Plans non-overlapping inclusive ranges covering [0, totalBytes - 1]
/// (docs/architecture.md §5.4). Segment ids are 0-based in download
/// order and stay stable for the run.
List<Segment> planSegments({
  required int? totalBytes,
  required int maxConnections,
}) {
  if (totalBytes == null) {
    return const [Segment(id: 0, start: 0, end: null)];
  }
  if (totalBytes <= 0) {
    return const [];
  }
  final count = maxConnections.clamp(1, 32).clamp(1, totalBytes);
  final base = totalBytes ~/ count;
  final remainder = totalBytes % count;
  final segments = <Segment>[];
  var start = 0;
  for (var i = 0; i < count; i++) {
    final size = base + (i < remainder ? 1 : 0);
    segments.add(Segment(id: i, start: start, end: start + size - 1));
    start += size;
  }
  return segments;
}
