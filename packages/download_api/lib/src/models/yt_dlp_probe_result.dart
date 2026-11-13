import 'package:freezed_annotation/freezed_annotation.dart';

part 'yt_dlp_probe_result.freezed.dart';
part 'yt_dlp_probe_result.g.dart';

/// Result of probing a URL with yt-dlp: whether any extractor supports
/// the URL, the video metadata, and the available download formats.
/// `supported` is false when no extractor matches the URL.
@freezed
abstract class YtDlpProbeResult with _$YtDlpProbeResult {
  // Freezed reads @JsonSerializable off the factory and forwards it to
  // the generated class; the analyzer only allows the annotation on
  // classes, hence the suppression.
  // ignore: invalid_annotation_target
  @JsonSerializable(explicitToJson: true)
  const factory YtDlpProbeResult({
    required bool supported,
    String? title,
    String? thumbnail,
    int? durationSeconds,
    @Default([]) List<YtDlpFormat> formats,
    String? errorCode,
    String? errorMessage,
  }) = _YtDlpProbeResult;

  factory YtDlpProbeResult.fromJson(Map<String, dynamic> json) =>
      _$YtDlpProbeResultFromJson(json);
}

/// One yt-dlp format of a probed video: a combined format, a video-only
/// format, or an audio-only format. `vcodec`/`acodec` are 'none' when
/// the format carries no stream of that kind.
@freezed
abstract class YtDlpFormat with _$YtDlpFormat {
  const factory YtDlpFormat({
    required String formatId,
    required String ext,
    String? resolution,
    int? width,
    int? height,
    int? filesize,
    int? filesizeApprox,
    required String vcodec,
    required String acodec,
    double? fps,
    String? note,
  }) = _YtDlpFormat;

  factory YtDlpFormat.fromJson(Map<String, dynamic> json) =>
      _$YtDlpFormatFromJson(json);
}
