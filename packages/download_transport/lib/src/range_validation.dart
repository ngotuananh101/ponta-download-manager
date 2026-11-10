/// Outcome of validating a range response (docs/architecture.md §5.3).
class RangeValidation {
  const RangeValidation({
    required this.valid,
    required this.reason,
    required this.totalBytes,
  });

  const RangeValidation.valid({required this.totalBytes})
      : valid = true,
        reason = null;

  const RangeValidation.invalid(this.reason, {this.totalBytes})
      : valid = false;

  /// True when the server returned 206 with a Content-Range matching the
  /// requested interval and a consistent total length.
  final bool valid;

  /// Why validation failed, when [valid] is false.
  final String? reason;

  /// Total representation length from Content-Range, when known.
  final int? totalBytes;
}
