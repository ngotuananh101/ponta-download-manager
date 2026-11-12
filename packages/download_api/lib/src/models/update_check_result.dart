import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_check_result.freezed.dart';
part 'update_check_result.g.dart';

/// Result of checking whether a newer version of a download is
/// available on the server. `newTotalBytes` is -1 when the server
/// does not report a size.
@freezed
abstract class UpdateCheckResult with _$UpdateCheckResult {
  const factory UpdateCheckResult({
    required bool hasUpdate,
    required bool inconclusive,
    required int newTotalBytes,
  }) = _UpdateCheckResult;

  factory UpdateCheckResult.fromJson(Map<String, dynamic> json) =>
      _$UpdateCheckResultFromJson(json);
}
