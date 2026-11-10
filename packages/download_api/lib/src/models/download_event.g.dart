// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DownloadProgress _$DownloadProgressFromJson(Map<String, dynamic> json) =>
    DownloadProgress(
      downloadId: json['downloadId'] as String,
      downloadedBytes: (json['downloadedBytes'] as num).toInt(),
      totalBytes: (json['totalBytes'] as num).toInt(),
      bytesPerSecond: (json['bytesPerSecond'] as num).toInt(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$DownloadProgressToJson(DownloadProgress instance) =>
    <String, dynamic>{
      'downloadId': instance.downloadId,
      'downloadedBytes': instance.downloadedBytes,
      'totalBytes': instance.totalBytes,
      'bytesPerSecond': instance.bytesPerSecond,
      'runtimeType': instance.$type,
    };

DownloadStateChanged _$DownloadStateChangedFromJson(
  Map<String, dynamic> json,
) => DownloadStateChanged(
  downloadId: json['downloadId'] as String,
  status: $enumDecode(_$DownloadStatusEnumMap, json['status']),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$DownloadStateChangedToJson(
  DownloadStateChanged instance,
) => <String, dynamic>{
  'downloadId': instance.downloadId,
  'status': _$DownloadStatusEnumMap[instance.status]!,
  'runtimeType': instance.$type,
};

const _$DownloadStatusEnumMap = {
  DownloadStatus.queued: 'queued',
  DownloadStatus.downloading: 'downloading',
  DownloadStatus.paused: 'paused',
  DownloadStatus.completed: 'completed',
  DownloadStatus.failed: 'failed',
  DownloadStatus.cancelled: 'cancelled',
};

DownloadCompleted _$DownloadCompletedFromJson(Map<String, dynamic> json) =>
    DownloadCompleted(
      downloadId: json['downloadId'] as String,
      filePath: json['filePath'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$DownloadCompletedToJson(DownloadCompleted instance) =>
    <String, dynamic>{
      'downloadId': instance.downloadId,
      'filePath': instance.filePath,
      'runtimeType': instance.$type,
    };

DownloadFailed _$DownloadFailedFromJson(Map<String, dynamic> json) =>
    DownloadFailed(
      downloadId: json['downloadId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$DownloadFailedToJson(DownloadFailed instance) =>
    <String, dynamic>{
      'downloadId': instance.downloadId,
      'code': instance.code,
      'message': instance.message,
      'runtimeType': instance.$type,
    };
