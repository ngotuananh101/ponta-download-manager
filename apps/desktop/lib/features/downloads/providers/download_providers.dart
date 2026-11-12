import 'dart:async';
import 'dart:io';

import 'package:download_api/download_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path/path.dart' as p;
import 'package:pdm/app/engine_ipc_host.dart';
import 'package:pdm/core/error/failures.dart';
import 'package:pdm/features/downloads/data/datasources/engine_download_datasource.dart';
import 'package:pdm/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:pdm/features/downloads/data/services/file_conflict_settings.dart';
import 'package:pdm/features/downloads/data/services/file_opener.dart';
import 'package:pdm/features/downloads/domain/entities/download.dart';
import 'package:pdm/features/downloads/domain/repositories/download_repository.dart';
import 'package:pdm_engine/pdm_engine.dart';

String _defaultDownloadDirectory() {
  if (Platform.isWindows) {
    return p.join(Platform.environment['USERPROFILE'] ?? '.', 'Downloads');
  }
  return p.join(Platform.environment['HOME'] ?? '.', 'Downloads');
}

/// The default download directory (~/Downloads). A separate provider
/// so the screen can read it without opening the engine.
final downloadDirectoryProvider = Provider<String>(
  (ref) => _defaultDownloadDirectory(),
);

/// The engine, running in this process. Opening it runs startup
/// recovery; disposing the datasource disposes the engine.
final downloadDatasourceProvider = Provider<EngineDownloadDatasource>((ref) {
  final datasource = EngineDownloadDatasource(
    engine: PdmEngine.open(),
    downloadDirectory: ref.watch(downloadDirectoryProvider),
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

/// Picks a directory with the system folder dialog. A separate
/// provider so tests can answer the picker instead of opening a
/// real dialog.
final directoryPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () => FilePicker.platform.getDirectoryPath(),
);

/// Picks a file to save to with the system save dialog. A separate
/// provider so tests can answer the dialog instead of opening a
/// real one.
final saveFileProvider =
    Provider<Future<String?> Function(String fileName)>(
  (ref) => (fileName) => FilePicker.platform.saveFile(fileName: fileName),
);

/// Opens a downloaded file or shows it in the file manager. A
/// separate provider so tests can record launches instead of opening
/// real files.
final fileOpenerProvider = Provider<FileOpener>((ref) => const FileOpener());

/// The remembered file-conflict choice (overwrite/rename), if any.
/// Persisted as JSON under the app data dir. The downloads screen
/// applies it without asking, and the conflict dialog saves it.
final fileConflictSettingsProvider = Provider<FileConflictSettings>(
  (ref) => FileConflictSettings(),
);

/// The user-facing download actions
/// (add/pause/resume/cancel/retry/delete/priority).
class DownloadsActions {
  DownloadsActions(this._repository);

  final DownloadRepository _repository;

  Future<Either<Failure, ProbeResult>> probeUrl(String url) =>
      _repository.probeUrl(url);

  Future<Either<Failure, Download>> addDownload(
    String url, {
    String? directory,
    String? fileName,
    FileConflictPolicy? conflictPolicy,
    bool paused = false,
  }) => _repository.addDownload(
        url,
        directory: directory,
        fileName: fileName,
        conflictPolicy: conflictPolicy,
        paused: paused,
      );

  Future<Either<Failure, Unit>> pauseDownload(String id) =>
      _repository.pauseDownload(id);

  Future<Either<Failure, Unit>> resumeDownload(String id) =>
      _repository.resumeDownload(id);

  Future<Either<Failure, Unit>> cancelDownload(String id) =>
      _repository.cancelDownload(id);

  Future<Either<Failure, Unit>> retryDownload(String id) =>
      _repository.retryDownload(id);

  Future<Either<Failure, Unit>> setPriority(String id, int priority) =>
      _repository.setPriority(id, priority);

  Future<Either<Failure, Unit>> deleteDownload(
    String id, {
    bool deleteFile = false,
  }) =>
      _repository.deleteDownload(id, deleteFile: deleteFile);

  Future<Either<Failure, Unit>> deleteFile(String id) =>
      _repository.deleteFile(id);

  Future<Either<Failure, Unit>> renameFile(String id, String newFileName) =>
      _repository.renameFile(id, newFileName);

  Future<Either<Failure, Unit>> moveFile(String id, String directory) =>
      _repository.moveFile(id, directory);

  Future<Either<Failure, Unit>> changeUrl(String id, String url) =>
      _repository.changeUrl(id, url);

  Future<Either<Failure, Unit>> addMirror(String id, String url) =>
      _repository.addMirror(id, url);
  Future<Either<Failure, Unit>> addTag(String id, String tag) =>
      _repository.addTag(id, tag);
  Future<Either<Failure, Unit>> removeTag(String id, String tag) =>
      _repository.removeTag(id, tag);

  Future<Either<Failure, UpdateCheckResult>> checkForUpdate(String id) =>
      _repository.checkForUpdate(id);

  Future<Either<Failure, IntegrityResult>> verifyFile(String id) =>
      _repository.verifyFile(id);

  Future<Either<Failure, Unit>> setGlobalBandwidthLimit(
    int? bytesPerSecond,
  ) => _repository.setGlobalBandwidthLimit(bytesPerSecond);

  Future<Either<Failure, List<DownloadSegment>>> getSegments(String id) =>
      _repository.getSegments(id);
}
