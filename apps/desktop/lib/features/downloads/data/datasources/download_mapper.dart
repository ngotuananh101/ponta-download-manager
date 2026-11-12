import 'dart:io';

import 'package:download_api/download_api.dart';

import '../../domain/entities/download.dart';

Download downloadFromInfo(DownloadInfo info) {
  return Download(
    id: info.id,
    url: info.url,
    fileName: info.fileName,
    state: _stateWithMissingCheck(info),
    downloadedBytes: info.downloadedBytes,
    totalBytes: info.totalBytes,
    bytesPerSecond: info.bytesPerSecond,
    createdAt: info.createdAt,
    filePath: info.filePath,
    priority: info.priority,
  );
}

/// Maps the engine status, marking a completed download Missing when
/// its file is no longer on disk. Only completed downloads are
/// checked: an incomplete one legitimately has no finished file yet,
/// and a download with no known path cannot be judged. The check runs
/// at load (and on refresh), so a file deleted mid-session shows
/// Missing only after the next app start.
DownloadState _stateWithMissingCheck(DownloadInfo info) {
  final state = downloadStateFromStatus(info.status);
  final path = info.filePath;
  if (state == DownloadState.completed &&
      path != null &&
      !File(path).existsSync()) {
    return DownloadState.missing;
  }
  return state;
}

DownloadState downloadStateFromStatus(DownloadStatus status) {
  return switch (status) {
    DownloadStatus.queued => DownloadState.queued,
    DownloadStatus.downloading => DownloadState.downloading,
    DownloadStatus.paused => DownloadState.paused,
    DownloadStatus.completed => DownloadState.completed,
    DownloadStatus.failed => DownloadState.failed,
    DownloadStatus.cancelled => DownloadState.cancelled,
  };
}
