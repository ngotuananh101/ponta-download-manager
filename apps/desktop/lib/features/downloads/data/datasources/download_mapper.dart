import 'package:download_api/download_api.dart';

import '../../domain/entities/download.dart';

Download downloadFromInfo(DownloadInfo info) {
  return Download(
    id: info.id,
    url: info.url,
    fileName: info.fileName,
    state: downloadStateFromStatus(info.status),
    downloadedBytes: info.downloadedBytes,
    totalBytes: info.totalBytes,
    bytesPerSecond: info.bytesPerSecond,
    createdAt: info.createdAt,
    filePath: info.filePath,
  );
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
