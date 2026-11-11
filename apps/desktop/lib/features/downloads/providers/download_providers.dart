import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/app/engine_ipc_host.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';
import 'package:pdm_engine/pdm_engine.dart';

String _defaultDownloadDirectory() {
  if (Platform.isWindows) {
    return p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads');
  }
  return p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
}

/// The engine, running in this process. Opening it runs startup
/// recovery; disposing the datasource disposes the engine.
final downloadDatasourceProvider = Provider<EngineDownloadDatasource>((ref) {
  final datasource = EngineDownloadDatasource(
    engine: PdmEngine.open(),
    downloadDirectory: _defaultDownloadDirectory(),
  );
  ref.onDispose(() => unawaited(datasource.dispose()));
  return datasource;
});

/// The IPC server the browser extension's native host talks to.
/// Started at app startup; closed on quit (and by onDispose).
final engineIpcHostProvider = FutureProvider<EngineIpcHost>((ref) async {
  final host = await EngineIpcHost.start(
    engine: ref.watch(downloadDatasourceProvider).engine,
  );
  ref.onDispose(() => unawaited(host.close()));
  return host;
});

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) {
  return DownloadRepositoryImpl(ref.watch(downloadDatasourceProvider));
});

/// The live download list, driven by engine snapshots and events.
final downloadsProvider = StreamProvider<List<Download>>((ref) {
  return ref.watch(downloadRepositoryProvider).watchDownloads();
});

final downloadsActionsProvider = Provider<DownloadsActions>((ref) {
  return DownloadsActions(ref.watch(downloadRepositoryProvider));
});

/// Whether the native drag-and-drop target is available.
///
/// The desktop_drop plugin loads a native library
/// (`libdesktop_drop_plugin.so`) that is only bundled in a built app.
/// A widget test runs in a plain Dart VM without it, and building a
/// [DropTarget] there throws. The screen only builds the target when
/// this is true; tests override it to false so the screen renders
/// without the native target.
final dropTargetEnabledProvider = Provider<bool>((ref) => true);

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

  Future<Either<Failure, Unit>> deleteDownload(String id) =>
      _repository.deleteDownload(id);

  Future<Either<Failure, Unit>> setGlobalBandwidthLimit(
    int? bytesPerSecond,
  ) => _repository.setGlobalBandwidthLimit(bytesPerSecond);

  Future<Either<Failure, List<DownloadSegment>>> getSegments(String id) =>
      _repository.getSegments(id);
}
