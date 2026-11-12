// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DownloadInfo _$DownloadInfoFromJson(Map<String, dynamic> json) =>
    _DownloadInfo(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      status: $enumDecode(_$DownloadStatusEnumMap, json['status']),
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num).toInt(),
      bytesPerSecond: (json['bytesPerSecond'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      filePath: json['filePath'] as String?,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$DownloadInfoToJson(_DownloadInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'url': instance.url,
      'fileName': instance.fileName,
      'status': _$DownloadStatusEnumMap[instance.status]!,
      'downloadedBytes': instance.downloadedBytes,
      'totalBytes': instance.totalBytes,
      'bytesPerSecond': instance.bytesPerSecond,
      'createdAt': instance.createdAt?.toIso8601String(),
      'filePath': instance.filePath,
      'priority': instance.priority,
      'tags': instance.tags,
      'errorCode': instance.errorCode,
      'errorMessage': instance.errorMessage,
    };

const _$DownloadStatusEnumMap = {
  DownloadStatus.queued: 'queued',
  DownloadStatus.downloading: 'downloading',
  DownloadStatus.paused: 'paused',
  DownloadStatus.completed: 'completed',
  DownloadStatus.failed: 'failed',
  DownloadStatus.cancelled: 'cancelled',
};
