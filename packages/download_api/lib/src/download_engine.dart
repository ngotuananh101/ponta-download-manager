import 'package:download_api/src/models/create_download_request.dart';
import 'package:download_api/src/models/download_event.dart';
import 'package:download_api/src/models/download_info.dart';

/// Application-level engine API (docs/architecture.md §16).
/// The UI talks to this interface, never to internal segment workers.
abstract interface class DownloadEngine {
  Future<DownloadInfo> createDownload(CreateDownloadRequest request);

  Future<void> pauseDownload(String downloadId);

  Future<void> resumeDownload(String downloadId);

  Future<void> cancelDownload(String downloadId);

  Future<void> retryDownload(String downloadId);

  /// Removes a download entirely: stops it if it runs, drops its
  /// partial file, and deletes its stored record. The finished file
  /// on disk (if any) is kept.
  Future<void> deleteDownload(String downloadId);

  Future<void> setPriority(String downloadId, int priority);

  Future<void> setGlobalBandwidthLimit(int? bytesPerSecond);

  Future<void> setDownloadBandwidthLimit(
    String downloadId,
    int? bytesPerSecond,
  );

  Future<List<DownloadInfo>> listDownloads();

  Stream<DownloadEvent> get events;
}
