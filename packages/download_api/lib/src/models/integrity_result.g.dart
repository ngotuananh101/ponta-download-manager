// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'integrity_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IntegrityOk _$IntegrityOkFromJson(Map<String, dynamic> json) => IntegrityOk(
  bytes: (json['bytes'] as num).toInt(),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$IntegrityOkToJson(IntegrityOk instance) =>
    <String, dynamic>{'bytes': instance.bytes, 'runtimeType': instance.$type};

IntegrityMissing _$IntegrityMissingFromJson(Map<String, dynamic> json) =>
    IntegrityMissing($type: json['runtimeType'] as String?);

Map<String, dynamic> _$IntegrityMissingToJson(IntegrityMissing instance) =>
    <String, dynamic>{'runtimeType': instance.$type};

IntegritySizeMismatch _$IntegritySizeMismatchFromJson(
  Map<String, dynamic> json,
) => IntegritySizeMismatch(
  expectedBytes: (json['expectedBytes'] as num).toInt(),
  actualBytes: (json['actualBytes'] as num).toInt(),
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$IntegritySizeMismatchToJson(
  IntegritySizeMismatch instance,
) => <String, dynamic>{
  'expectedBytes': instance.expectedBytes,
  'actualBytes': instance.actualBytes,
  'runtimeType': instance.$type,
};

IntegrityChecksumMismatch _$IntegrityChecksumMismatchFromJson(
  Map<String, dynamic> json,
) => IntegrityChecksumMismatch(
  expectedSha256: json['expectedSha256'] as String,
  actualSha256: json['actualSha256'] as String,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$IntegrityChecksumMismatchToJson(
  IntegrityChecksumMismatch instance,
) => <String, dynamic>{
  'expectedSha256': instance.expectedSha256,
  'actualSha256': instance.actualSha256,
  'runtimeType': instance.$type,
};

IntegrityUnreadable _$IntegrityUnreadableFromJson(Map<String, dynamic> json) =>
    IntegrityUnreadable(
      message: json['message'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$IntegrityUnreadableToJson(
  IntegrityUnreadable instance,
) => <String, dynamic>{
  'message': instance.message,
  'runtimeType': instance.$type,
};
