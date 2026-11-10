import 'package:download_api/download_api.dart';
import 'package:download_ipc/download_ipc.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/data/datasources/download_mapper.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';

/// The repository over the in-process engine datasource. The engine
/// is the source of truth: no state is flipped locally, and a
/// download created here comes back with the engine's id.
class DownloadRepositoryImpl implements DownloadRepository {
  DownloadRepositoryImpl(this._datasource);

  final EngineDownloadDatasource _datasource;

  @override
  Stream<List<Download>> watchDownloads() => _datasource.watchDownloads();

  @override
  Future<Either<Failure, Download>> addDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const Left(
        ValidationFailure('URL must start with http:// or https://'),
      );
    }
    try {
      final info = await _datasource.addDownload(url);
      return Right(downloadFromInfo(info));
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  @override
  Future<Either<Failure, Unit>> pauseDownload(String id) =>
      _act(() => _datasource.pauseDownload(id));

  @override
  Future<Either<Failure, Unit>> resumeDownload(String id) =>
      _act(() => _datasource.resumeDownload(id));

  @override
  Future<Either<Failure, Unit>> cancelDownload(String id) =>
      _act(() => _datasource.cancelDownload(id));

  @override
  Future<Either<Failure, Unit>> retryDownload(String id) =>
      _act(() => _datasource.retryDownload(id));

  Future<Either<Failure, Unit>> _act(Future<void> Function() call) async {
    try {
      await call();
      return const Right(unit);
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  Failure _toFailure(DownloadError error) {
    if (error.code == IpcErrorCode.notFound) {
      return const ValidationFailure('Download not found');
    }
    return UnexpectedFailure(error.message);
  }
}
