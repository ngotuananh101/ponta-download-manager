import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_segment.freezed.dart';
part 'download_segment.g.dart';

/// Per-segment progress for the details panel's PROGRESS tab
/// (docs/architecture.md §5.4). One entry per byte range of a download.
@freezed
abstract class DownloadSegment with _$DownloadSegment {
  const factory DownloadSegment({
    required int segmentId,
    required int start,
    int? end,
    @Default(0) int downloaded,
  }) = _DownloadSegment;

  factory DownloadSegment.fromJson(Map<String, dynamic> json) =>
      _$DownloadSegmentFromJson(json);
}
