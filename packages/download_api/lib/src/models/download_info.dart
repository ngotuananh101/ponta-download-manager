import 'package:freezed_annotation/freezed_annotation.dart';

part 'download_info.freezed.dart';
part 'download_info.g.dart';

/// Immutable snapshot of a download task, shared between engine and UI.
@freezed
abstract class DownloadInfo with _$DownloadInfo {
  const factory DownloadInfo({
    required String id,
    required String url,
    required String fileName,
    required DownloadStatus status,
    @Default(0) int downloadedBytes,
    required int totalBytes,
    @Default(0) int bytesPerSecond,
    DateTime? createdAt,
  }) = _DownloadInfo;

  factory DownloadInfo.fromJson(Map<String, dynamic> json) =>
      _$DownloadInfoFromJson(json);
}

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}
