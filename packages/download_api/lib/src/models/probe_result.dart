import 'package:freezed_annotation/freezed_annotation.dart';

part 'probe_result.freezed.dart';
part 'probe_result.g.dart';

/// Result of probing a URL before creating a download: the file name
/// the server reports (or the URL's last segment) and the total size.
/// `totalBytes` is -1 when the server does not report a size.
@freezed
abstract class ProbeResult with _$ProbeResult {
  const factory ProbeResult({
    required String url,
    required String fileName,
    required int totalBytes,
  }) = _ProbeResult;

  factory ProbeResult.fromJson(Map<String, dynamic> json) =>
      _$ProbeResultFromJson(json);
}
