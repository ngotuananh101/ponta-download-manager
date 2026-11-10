import 'package:download_transport/src/range_validation.dart';
import 'package:download_transport/src/resource_info.dart';

/// HTTP transport behind an interface (docs/architecture.md §15).
/// Implementations must stream bytes without loading a whole response
/// into memory, and must never write a 200 response into a segment
/// offset (§5.3).
abstract interface class DownloadTransport {
  /// Probes the resource: HEAD where useful, GET/Range fallback when
  /// HEAD is unsupported (405/501). Follows redirects.
  Future<ResourceInfo> probe(Uri url);

  /// Validates that the server answers the requested byte range with
  /// 206 and a matching Content-Range (§5.3).
  Future<RangeValidation> validateRange(
    Uri url, {
    required int start,
    required int end,
  });

  /// Opens a byte stream for the URL, or for [start]-[end] when a range
  /// is given. Cancelling the subscription aborts the request.
  /// When [ifRange] is given, it is sent as an If-Range header.
  Stream<List<int>> openStream(
    Uri url, {
    int? start,
    int? end,
    String? ifRange,
  });

  /// Releases the underlying HTTP client. The transport must not be
  /// used after [close].
  void close();
}
