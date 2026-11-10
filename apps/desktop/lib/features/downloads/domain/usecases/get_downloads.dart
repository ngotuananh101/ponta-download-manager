import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';

class GetDownloads {
  const GetDownloads(this._repository);

  final DownloadRepository _repository;

  Future<Either<Failure, List<Download>>> call() async {
    final downloads = await _repository.watchDownloads().first;
    return Right(downloads);
  }
}
