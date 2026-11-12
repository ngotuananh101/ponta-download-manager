// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_check_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_UpdateCheckResult _$UpdateCheckResultFromJson(Map<String, dynamic> json) =>
    _UpdateCheckResult(
      hasUpdate: json['hasUpdate'] as bool,
      inconclusive: json['inconclusive'] as bool,
      newTotalBytes: (json['newTotalBytes'] as num).toInt(),
    );

Map<String, dynamic> _$UpdateCheckResultToJson(_UpdateCheckResult instance) =>
    <String, dynamic>{
      'hasUpdate': instance.hasUpdate,
      'inconclusive': instance.inconclusive,
      'newTotalBytes': instance.newTotalBytes,
    };
