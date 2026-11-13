// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'yt_dlp_probe_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_YtDlpProbeResult _$YtDlpProbeResultFromJson(Map<String, dynamic> json) =>
    _YtDlpProbeResult(
      supported: json['supported'] as bool,
      title: json['title'] as String?,
      thumbnail: json['thumbnail'] as String?,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      formats:
          (json['formats'] as List<dynamic>?)
              ?.map((e) => YtDlpFormat.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$YtDlpProbeResultToJson(_YtDlpProbeResult instance) =>
    <String, dynamic>{
      'supported': instance.supported,
      'title': instance.title,
      'thumbnail': instance.thumbnail,
      'durationSeconds': instance.durationSeconds,
      'formats': instance.formats.map((e) => e.toJson()).toList(),
      'errorCode': instance.errorCode,
      'errorMessage': instance.errorMessage,
    };

_YtDlpFormat _$YtDlpFormatFromJson(Map<String, dynamic> json) => _YtDlpFormat(
  formatId: json['formatId'] as String,
  ext: json['ext'] as String,
  resolution: json['resolution'] as String?,
  width: (json['width'] as num?)?.toInt(),
  height: (json['height'] as num?)?.toInt(),
  filesize: (json['filesize'] as num?)?.toInt(),
  filesizeApprox: (json['filesizeApprox'] as num?)?.toInt(),
  vcodec: json['vcodec'] as String,
  acodec: json['acodec'] as String,
  fps: (json['fps'] as num?)?.toDouble(),
  note: json['note'] as String?,
);

Map<String, dynamic> _$YtDlpFormatToJson(_YtDlpFormat instance) =>
    <String, dynamic>{
      'formatId': instance.formatId,
      'ext': instance.ext,
      'resolution': instance.resolution,
      'width': instance.width,
      'height': instance.height,
      'filesize': instance.filesize,
      'filesizeApprox': instance.filesizeApprox,
      'vcodec': instance.vcodec,
      'acodec': instance.acodec,
      'fps': instance.fps,
      'note': instance.note,
    };
