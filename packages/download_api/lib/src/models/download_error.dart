/// Stable, serializable error for engine operations.
class DownloadError implements Exception {
  const DownloadError(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'DownloadError($code): $message';
}
