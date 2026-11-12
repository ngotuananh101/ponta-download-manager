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
    // Final on-disk destination (directory + fileName). Null for infos
    // that predate this field or arrive over IPC, which does not carry
    // it. The desktop UI needs it for the "Missing Files" filter.
    String? filePath,
    // Queue priority. Higher runs first; 0 is the default (normal).
    // The UI shows it as high / normal / low.
    @Default(0) int priority,
    // Labels on the download, for grouping. Empty by default; older
    // IPC JSON without the field decodes to [].
    @Default([]) List<String> tags,
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
