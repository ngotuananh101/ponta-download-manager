/// Stable, serializable error for engine operations.
class DownloadError implements Exception {
  const DownloadError(this.code, this.message, {this.retryAfter});

  final String code;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'DownloadError($code): $message';
}
