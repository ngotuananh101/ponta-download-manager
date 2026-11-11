// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_segment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DownloadSegment _$DownloadSegmentFromJson(Map<String, dynamic> json) =>
    _DownloadSegment(
      segmentId: (json['segmentId'] as num).toInt(),
      start: (json['start'] as num).toInt(),
      end: (json['end'] as num?)?.toInt(),
      downloaded: (json['downloaded'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$DownloadSegmentToJson(_DownloadSegment instance) =>
    <String, dynamic>{
      'segmentId': instance.segmentId,
      'start': instance.start,
      'end': instance.end,
      'downloaded': instance.downloaded,
    };
