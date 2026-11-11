import 'package:download_api/download_api.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

abstract interface class DownloadRepository {
  Stream<List<Download>> watchDownloads();
  Future<Either<Failure, Download>> addDownload(
    String url, {
    FileConflictPolicy? conflictPolicy,
  });
  Future<Either<Failure, Unit>> pauseDownload(String id);
  Future<Either<Failure, Unit>> resumeDownload(String id);
  Future<Either<Failure, Unit>> cancelDownload(String id);
  Future<Either<Failure, Unit>> retryDownload(String id);
  Future<Either<Failure, Unit>> deleteDownload(String id);

  /// Snail mode: a global speed cap in bytes/s (null = unlimited).
  Future<Either<Failure, Unit>> setGlobalBandwidthLimit(int? bytesPerSecond);

  /// Per-segment progress for the details panel's PROGRESS tab.
  Future<Either<Failure, List<DownloadSegment>>> getSegments(String id);
}
