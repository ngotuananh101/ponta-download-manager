import 'dart:async';
import 'dart:io';

import 'package:download_ipc/download_ipc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/data/datasources/ipc_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';

String _defaultDownloadDirectory() {
  if (Platform.isWindows) {
    return p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads');
  }
  return p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
}

final downloadDatasourceProvider = Provider<IpcDownloadDatasource>((ref) {
  final socketPath = defaultSocketPath();
  final datasource = IpcDownloadDatasource(
    clientFactory: () async {
      final token = await File('$socketPath.token').readAsString();
      return IpcClient.connect(
        channelFactory: () =>
            UnixSocketTransport(socketPath: socketPath).connect(),
        token: token,
      );
    },
    downloadDirectory: _defaultDownloadDirectory(),
  );
  unawaited(datasource.connect());
  ref.onDispose(() => unawaited(datasource.dispose()));
  return datasource;
});

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepositoryImpl(ref.watch(downloadDatasourceProvider));
});

/// The live download list, driven by engine snapshots and events.
final downloadsProvider = StreamProvider<List<Download>>((ref) {
  return ref.watch(downloadRepositoryProvider).watchDownloads();
});

/// True once the hello handshake with the engine succeeded.
final engineConnectedProvider = StreamProvider<bool>((ref) {
  return ref.watch(downloadDatasourceProvider).watchConnected();
});

final downloadsActionsProvider = Provider<DownloadsActions>((ref) {
  return DownloadsActions(ref.watch(downloadRepositoryProvider));
});

/// The user-facing download actions (add/pause/resume/cancel/retry).
class DownloadsActions {
  DownloadsActions(this._repository);

  final DownloadRepository _repository;

  Future<Either<Failure, Download>> addDownload(String url) =>
      _repository.addDownload(url);

  Future<Either<Failure, Unit>> pauseDownload(String id) =>
      _repository.pauseDownload(id);

  Future<Either<Failure, Unit>> resumeDownload(String id) =>
      _repository.resumeDownload(id);

  Future<Either<Failure, Unit>> cancelDownload(String id) =>
      _repository.cancelDownload(id);

  Future<Either<Failure, Unit>> retryDownload(String id) =>
      _repository.retryDownload(id);
}
