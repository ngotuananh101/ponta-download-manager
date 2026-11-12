import 'package:download_api/download_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

abstract interface class DownloadRepository {
  Stream<List<Download>> watchDownloads();

  /// Probes a URL before creating a download: the file name the server
  /// reports (or the URL's last segment) and the total size, -1 when
  /// unknown.
  Future<Either<Failure, ProbeResult>> probeUrl(String url);

  Future<Either<Failure, Download>> addDownload(
    String url, {
    String? directory,
    String? fileName,
    FileConflictPolicy? conflictPolicy,
    bool paused = false,
  });
  Future<Either<Failure, Unit>> pauseDownload(String id);
  Future<Either<Failure, Unit>> resumeDownload(String id);
  Future<Either<Failure, Unit>> cancelDownload(String id);
  Future<Either<Failure, Unit>> retryDownload(String id);

  /// Queue priority: higher runs first (1 high, 0 normal, -1 low).
  Future<Either<Failure, Unit>> setPriority(String id, int priority);
  Future<Either<Failure, Unit>> deleteDownload(
    String id, {
    bool deleteFile = false,
  });

  /// Deletes the finished file and keeps the row (it shows Missing).
  Future<Either<Failure, Unit>> deleteFile(String id);

  /// Renames the finished file on disk and updates the record.
  Future<Either<Failure, Unit>> renameFile(String id, String newFileName);

  /// Moves the finished file to another directory and updates the
  /// record.
  Future<Either<Failure, Unit>> moveFile(String id, String directory);

  /// Changes the download's URL and clears its stored validators.
  Future<Either<Failure, Unit>> changeUrl(String id, String url);

  /// Snail mode: a global speed cap in bytes/s (null = unlimited).
  Future<Either<Failure, Unit>> setGlobalBandwidthLimit(int? bytesPerSecond);

  /// Per-segment progress for the details panel's PROGRESS tab.
  Future<Either<Failure, List<DownloadSegment>>> getSegments(String id);
}
