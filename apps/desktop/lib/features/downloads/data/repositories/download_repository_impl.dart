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
  Future<Either<Failure, ProbeResult>> probeUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const Left(
        ValidationFailure('URL must start with http:// or https://'),
      );
    }
    try {
      return Right(await _datasource.probeUrl(url));
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  @override
  Future<Either<Failure, Download>> addDownload(
    String url, {
    String? directory,
    String? fileName,
    FileConflictPolicy? conflictPolicy,
    bool paused = false,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return const Left(
        ValidationFailure('URL must start with http:// or https://'),
      );
    }
    try {
      final info = await _datasource.addDownload(
        url,
        directory: directory,
        fileName: fileName,
        conflictPolicy: conflictPolicy,
        paused: paused,
      );
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

  @override
  Future<Either<Failure, Unit>> setPriority(String id, int priority) =>
      _act(() => _datasource.setPriority(id, priority));

  @override
  Future<Either<Failure, Unit>> deleteDownload(
    String id, {
    bool deleteFile = false,
  }) =>
      _act(() => _datasource.deleteDownload(id, deleteFile: deleteFile));

  @override
  Future<Either<Failure, Unit>> deleteFile(String id) =>
      _act(() => _datasource.deleteFile(id));

  @override
  Future<Either<Failure, Unit>> renameFile(String id, String newFileName) =>
      _act(() => _datasource.renameFile(id, newFileName));

  @override
  Future<Either<Failure, Unit>> moveFile(String id, String directory) =>
      _act(() => _datasource.moveFile(id, directory));

  @override
  Future<Either<Failure, Unit>> changeUrl(String id, String url) =>
      _act(() => _datasource.changeUrl(id, url));

  @override
  Future<Either<Failure, Unit>> addMirror(String id, String url) =>
      _act(() => _datasource.addMirror(id, url));

  @override
  Future<Either<Failure, UpdateCheckResult>> checkForUpdate(String id) async {
    // Like getSegments: _act is for void actions, so a
    // value-returning call inlines the same try/catch.
    try {
      return Right(await _datasource.checkForUpdate(id));
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  @override
  Future<Either<Failure, IntegrityResult>> verifyFile(String id) async {
    // Like getSegments: _act is for void actions, so a
    // value-returning call inlines the same try/catch.
    try {
      return Right(await _datasource.verifyFile(id));
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  @override
  Future<Either<Failure, Unit>> setGlobalBandwidthLimit(
    int? bytesPerSecond,
  ) => _act(() => _datasource.setGlobalBandwidthLimit(bytesPerSecond));

  @override
  Future<Either<Failure, List<DownloadSegment>>> getSegments(
    String id,
  ) async {
    try {
      return Right(await _datasource.getSegments(id));
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  Future<Either<Failure, Unit>> _act(Future<void> Function() call) async {
    try {
      await call();
      return const Right(unit);
    } on DownloadError catch (e) {
      return Left(_toFailure(e));
    }
  }

  Failure _toFailure(DownloadError error) {
    if (error.code == 'file-exists') {
      // The engine reports 'Destination already exists: <path>'.
      const prefix = 'Destination already exists: ';
      final destination = error.message.startsWith(prefix)
          ? error.message.substring(prefix.length)
          : '';
      return FileExistsFailure(destination);
    }
    if (error.code == IpcErrorCode.notFound) {
      return const ValidationFailure('Download not found');
    }
    return UnexpectedFailure(error.message);
  }
}
