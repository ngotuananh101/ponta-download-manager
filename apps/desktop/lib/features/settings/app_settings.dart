import 'package:download_api/download_api.dart';
import 'package:path/path.dart' as p;

/// The action shared by the minimize and close controls.
enum WindowAction { tray, quit }
enum StartupState { normal, tray }

/// What the Delete button does with the download's finished file.
enum DeleteAction { removeOnly, deleteFile, ask }

/// Persisted preferences. A null directory follows the OS Downloads folder.
class AppSettings {
  const AppSettings({
    this.downloadDirectory,
    this.maxConcurrentDownloads = 3,
    this.maxConnectionsPerDownload = 8,
    this.fileConflictPolicy,
    this.launchAtStartup = false,
    this.windowAction = WindowAction.tray,
    this.startupState = StartupState.normal,
    this.deleteAction = DeleteAction.ask,
  });

  final String? downloadDirectory;
  final int maxConcurrentDownloads;
  final int maxConnectionsPerDownload;
  final FileConflictPolicy? fileConflictPolicy;
  final bool launchAtStartup;
  final WindowAction windowAction;
  final StartupState startupState;
  final DeleteAction deleteAction;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    int count(String key, int fallback) {
      final value = json[key];
      return value is int && value >= 1 && value <= 32 ? value : fallback;
    }
    final directory = json['downloadDirectory'];
    return AppSettings(
      downloadDirectory: directory is String && directory.trim().isNotEmpty &&
              p.isAbsolute(directory)
          ? directory : null,
      maxConcurrentDownloads: count('maxConcurrentDownloads', 3),
      maxConnectionsPerDownload: count('maxConnectionsPerDownload', 8),
      fileConflictPolicy: switch (json['fileConflictPolicy']) {
        'overwrite' => FileConflictPolicy.overwrite,
        'rename' => FileConflictPolicy.rename,
        _ => null,
      },
      launchAtStartup: json['launchAtStartup'] == true,
      windowAction: json['windowAction'] == 'quit'
          ? WindowAction.quit : WindowAction.tray,
      startupState: json['startupState'] == 'tray'
          ? StartupState.tray : StartupState.normal,
      deleteAction: switch (json['deleteAction']) {
        'removeOnly' => DeleteAction.removeOnly,
        'deleteFile' => DeleteAction.deleteFile,
        _ => DeleteAction.ask,
      },
    );
  }

  void validate() {
    for (final value in [maxConcurrentDownloads, maxConnectionsPerDownload]) {
      if (value < 1 || value > 32) {
        throw ArgumentError('Download limits must be integers from 1 to 32');
      }
    }
    final directory = downloadDirectory;
    if (directory != null &&
        (directory.trim().isEmpty || !p.isAbsolute(directory))) {
      throw ArgumentError('Download folder must be an absolute path');
    }
  }

  Map<String, Object?> toJson() => {
    'downloadDirectory': downloadDirectory,
    'maxConcurrentDownloads': maxConcurrentDownloads,
    'maxConnectionsPerDownload': maxConnectionsPerDownload,
    'fileConflictPolicy': fileConflictPolicy?.name,
    'launchAtStartup': launchAtStartup,
    'windowAction': windowAction.name,
    'startupState': startupState.name,
    'deleteAction': deleteAction.name,
  };
}
