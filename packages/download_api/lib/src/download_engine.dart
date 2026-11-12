import 'package:download_api/src/models/create_download_request.dart';
import 'package:download_api/src/models/probe_result.dart';
import 'package:download_api/src/models/update_check_result.dart';
import 'package:download_api/src/models/download_event.dart';
import 'package:download_api/src/models/download_info.dart';
import 'package:download_api/src/models/download_segment.dart';
import 'package:download_api/src/models/integrity_result.dart';

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

  /// Deletes the finished file (and any partial) of a download and
  /// keeps its stored record: the row shows as Missing on the next
  /// load. Best-effort: a missing or undeletable file is not an
  /// error.
  Future<void> deleteFile(String downloadId);

  /// Renames the finished file on disk and updates the stored
  /// record. Throws [DownloadError] `invalid-name` when the name is
  /// empty or contains a path separator, and `file-exists` when the
  /// target name is already taken.
  Future<void> renameFile(String downloadId, String newFileName);

  /// Moves the finished file to another directory and updates the
  /// stored record. Throws [DownloadError] `invalid-directory`
  /// when the directory does not exist, and `file-exists` when a
  /// file with the same name is already there.
  Future<void> moveFile(String downloadId, String directory);

  /// Changes the URL of a download (for a failed download whose link
  /// expired) and clears its stored validators: the old eTag and
  /// lastModified belong to the old URL. Throws [DownloadError]
  /// `invalid-url` when the URL is not http(s).
  Future<void> changeUrl(String downloadId, String url);

  /// Adds an alternative URL for the same file. The engine tries
  /// mirrors in order when the primary URL fails. Throws
  /// [DownloadError] `invalid-url` when the URL is not http(s);
  /// a duplicate URL is ignored.
  Future<void> addMirror(String downloadId, String url);

  /// Checks whether the server hosts a newer version of a download,
  /// comparing the server's reported size with the stored one.
  /// Throws [DownloadError] when the download is unknown or the
  /// probe fails.
  Future<UpdateCheckResult> checkForUpdate(String downloadId);

  /// Verifies the finished file on disk: it exists and (when the
  /// record knows the size) its size matches. Throws
  /// [DownloadError] when the download is unknown.
  Future<IntegrityResult> verifyFile(String downloadId);

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
