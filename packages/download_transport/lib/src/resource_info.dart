/// Result of probing a remote resource (docs/architecture.md §5.2).
class ResourceInfo {
  const ResourceInfo({
    required this.finalUrl,
    required this.statusCode,
    required this.contentLength,
    required this.supportsRange,
    required this.eTag,
    required this.lastModified,
    required this.contentDisposition,
    required this.contentType,
    required this.fileName,
  });

  /// URL after following redirects.
  final Uri finalUrl;

  /// HTTP status of the probe response.
  final int statusCode;

  /// Representation length in bytes, when the server reports it.
  final int? contentLength;

  /// True when the server advertises `Accept-Ranges: bytes`.
  /// This alone does not guarantee correct range behavior (§5.2);
  /// use validateRange before segmenting.
  final bool supportsRange;

  /// ETag validator, when the server sends one.
  final String? eTag;

  /// Last-Modified validator, when the server sends one.
  final String? lastModified;

  /// Raw Content-Disposition header, when present.
  final String? contentDisposition;

  /// Content type without parameters, when the server sends one.
  final String? contentType;

  /// File name from Content-Disposition, or the last URL path segment,
  /// or 'download'.
  final String fileName;

  ResourceInfo copyWith({Object? contentLength = _unset}) {
    return ResourceInfo(
      finalUrl: finalUrl,
      statusCode: statusCode,
      contentLength: contentLength == _unset
          ? this.contentLength
          : contentLength as int?,
      supportsRange: supportsRange,
      eTag: eTag,
      lastModified: lastModified,
      contentDisposition: contentDisposition,
      contentType: contentType,
      fileName: fileName,
    );
  }

  static const _unset = Object();
}
