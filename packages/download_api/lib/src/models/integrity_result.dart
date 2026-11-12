import 'package:freezed_annotation/freezed_annotation.dart';

part 'integrity_result.freezed.dart';
part 'integrity_result.g.dart';

/// The outcome of verifying a finished file on disk.
@freezed
abstract class IntegrityResult with _$IntegrityResult {
  const factory IntegrityResult.ok({required int bytes}) = IntegrityOk;

  /// The file exists and is readable, but its expected size was never
  /// known, so the size was not checked.
  const factory IntegrityResult.unknownSize({required int bytes}) =
      IntegrityUnknownSize;

  const factory IntegrityResult.missing() = IntegrityMissing;

  const factory IntegrityResult.sizeMismatch({
    required int expectedBytes,
    required int actualBytes,
  }) = IntegritySizeMismatch;

  const factory IntegrityResult.checksumMismatch({
    required String expectedSha256,
    required String actualSha256,
  }) = IntegrityChecksumMismatch;

  const factory IntegrityResult.unreadable({required String message}) =
      IntegrityUnreadable;

  factory IntegrityResult.fromJson(Map<String, dynamic> json) =>
      _$IntegrityResultFromJson(json);
}
