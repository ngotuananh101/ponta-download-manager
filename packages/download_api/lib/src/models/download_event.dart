import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:download_api/src/models/download_info.dart';

part 'download_event.freezed.dart';
part 'download_event.g.dart';

/// Asynchronous engine events (docs/architecture.md §4.2).
@freezed
abstract class DownloadEvent with _$DownloadEvent {
  const factory DownloadEvent.progress({
    required String downloadId,
    required int downloadedBytes,
    required int totalBytes,
    required int bytesPerSecond,
  }) = DownloadProgress;

  const factory DownloadEvent.stateChanged({
    required String downloadId,
    required DownloadStatus status,
  }) = DownloadStateChanged;

  const factory DownloadEvent.completed({
    required String downloadId,
    required String filePath,
  }) = DownloadCompleted;

  const factory DownloadEvent.failed({
    required String downloadId,
    required String code,
    required String message,
  }) = DownloadFailed;

  factory DownloadEvent.fromJson(Map<String, dynamic> json) =>
      _$DownloadEventFromJson(json);
}
