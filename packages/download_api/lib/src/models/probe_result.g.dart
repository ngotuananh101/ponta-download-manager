// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'probe_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProbeResult _$ProbeResultFromJson(Map<String, dynamic> json) => _ProbeResult(
  url: json['url'] as String,
  fileName: json['fileName'] as String,
  totalBytes: (json['totalBytes'] as num).toInt(),
);

Map<String, dynamic> _$ProbeResultToJson(_ProbeResult instance) =>
    <String, dynamic>{
      'url': instance.url,
      'fileName': instance.fileName,
      'totalBytes': instance.totalBytes,
    };
