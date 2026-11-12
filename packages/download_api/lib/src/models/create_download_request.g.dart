// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_download_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_CreateDownloadRequest _$CreateDownloadRequestFromJson(
  Map<String, dynamic> json,
) => _CreateDownloadRequest(
  url: json['url'] as String,
  destination: json['destination'] as String,
  maxConnections: (json['maxConnections'] as num?)?.toInt(),
  priority: (json['priority'] as num?)?.toInt(),
  conflictPolicy: $enumDecodeNullable(
    _$FileConflictPolicyEnumMap,
    json['conflictPolicy'],
  ),
  paused: json['paused'] as bool? ?? false,
);

Map<String, dynamic> _$CreateDownloadRequestToJson(
  _CreateDownloadRequest instance,
) => <String, dynamic>{
  'url': instance.url,
  'destination': instance.destination,
  'maxConnections': instance.maxConnections,
  'priority': instance.priority,
  'conflictPolicy': _$FileConflictPolicyEnumMap[instance.conflictPolicy],
  'paused': instance.paused,
};

const _$FileConflictPolicyEnumMap = {
  FileConflictPolicy.overwrite: 'overwrite',
  FileConflictPolicy.rename: 'rename',
};
