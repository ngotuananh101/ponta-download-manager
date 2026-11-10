import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';

abstract interface class DownloadRepository {
  Stream<List<Download>> watchDownloads();
  Future<Either<Failure, Download>> addDownload(String url);
  Future<Either<Failure, Unit>> pauseDownload(String id);
  Future<Either<Failure, Unit>> resumeDownload(String id);
  Future<Either<Failure, Unit>> cancelDownload(String id);
}
