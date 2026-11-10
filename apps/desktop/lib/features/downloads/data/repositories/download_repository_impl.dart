import 'package:fpdart/fpdart.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/data/datasources/in_memory_download_datasource.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';
import 'package:uuid/uuid.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  DownloadRepositoryImpl(this._datasource);

  final InMemoryDownloadDatasource _datasource;
  final _uuid = const Uuid();

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
    final segments = uri.pathSegments;
    final fileName = segments.isNotEmpty && segments.last.isNotEmpty
        ? segments.last
        : 'download';
    final download = Download(
      id: _uuid.v4(),
      url: url,
      fileName: fileName,
      state: DownloadState.queued,
      totalBytes: 0,
    );
    _datasource.addDownload(download);
    return Right(download);
  }

  @override
  Future<Either<Failure, Unit>> pauseDownload(String id) async {
    return _updateState(id, DownloadState.paused);
  }

  @override
  Future<Either<Failure, Unit>> resumeDownload(String id) async {
    return _updateState(id, DownloadState.downloading);
  }

  @override
  Future<Either<Failure, Unit>> cancelDownload(String id) async {
    return _updateState(id, DownloadState.cancelled);
  }

  Future<Either<Failure, Unit>> _updateState(
    String id,
    DownloadState state,
  ) async {
    final downloads = await _datasource.watchDownloads().first;
    final index = downloads.indexWhere((item) => item.id == id);
    if (index == -1) {
      return const Left(ValidationFailure('Download not found'));
    }
    _datasource.updateDownload(downloads[index].copyWith(state: state));
    return const Right(unit);
  }
}
