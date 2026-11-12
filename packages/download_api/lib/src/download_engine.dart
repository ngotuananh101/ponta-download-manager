import 'package:download_api/src/models/create_download_request.dart';
import 'package:download_api/src/models/probe_result.dart';
import 'package:download_api/src/models/download_event.dart';
import 'package:download_api/src/models/download_info.dart';
import 'package:download_api/src/models/download_segment.dart';

/// Application-level engine API (docs/architecture.md §16).
/// The UI talks to this interface, never to internal segment workers.
abstract interface class DownloadEngine {
  Future<DownloadInfo> createDownload(CreateDownloadRequest request);

  /// Probes a URL before creating a download: the file name the server
  /// reports (or the URL's last segment) and the total size, -1 when
  /// unknown. Throws [DownloadError] when the URL is unreachable.
  Future<ProbeResult> probeUrl(String url);

  Future<void> pauseDownload(String downloadId);

  Future<void> resumeDownload(String downloadId);

  Future<void> cancelDownload(String downloadId);

  Future<void> retryDownload(String downloadId);

  /// Removes a download entirely: stops it if it runs, drops its
  /// partial file, and deletes its stored record. The finished file
  /// on disk (if any) is kept unless [deleteFile] is true, in which
  /// case it is deleted too (best-effort: a missing or undeletable
  /// file never blocks deleting the record).
  Future<void> deleteDownload(String downloadId, {bool deleteFile = false});

  Future<void> setPriority(String downloadId, int priority);

  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond);

  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  );

  Future<List<DownloadInfo>> listDownloads();

  /// Per-segment progress for the details panel's PROGRESS tab.
  /// Empty when the download has no segments yet (queued, or a
  /// download the engine has not planned segments for).
  Future<List<DownloadSegment>> getSegments(String downloadId);

  Stream<DownloadEvent> get events;
}
