// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'yt_dlp_probe_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$YtDlpProbeResult {

 bool get supported; String? get title; String? get thumbnail; int? get durationSeconds; List<YtDlpFormat> get formats; String? get errorCode; String? get errorMessage;
/// Create a copy of YtDlpProbeResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$YtDlpProbeResultCopyWith<YtDlpProbeResult> get copyWith => _$YtDlpProbeResultCopyWithImpl<YtDlpProbeResult>(this as YtDlpProbeResult, _$identity);

  /// Serializes this YtDlpProbeResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as YtDlpProbeResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is YtDlpProbeResult&&(identical(other.supported, _this.supported) || other.supported == _this.supported)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.thumbnail, _this.thumbnail) || other.thumbnail == _this.thumbnail)&&(identical(other.durationSeconds, _this.durationSeconds) || other.durationSeconds == _this.durationSeconds)&&const DeepCollectionEquality().equals(other.formats, _this.formats)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as YtDlpProbeResult;
  return Object.hash(runtimeType,_this.supported,_this.title,_this.thumbnail,_this.durationSeconds,const DeepCollectionEquality().hash(_this.formats),_this.errorCode,_this.errorMessage);
}

@override
String toString() {
  final _this = this as YtDlpProbeResult;
  return 'YtDlpProbeResult(supported: ${_this.supported}, title: ${_this.title}, thumbnail: ${_this.thumbnail}, durationSeconds: ${_this.durationSeconds}, formats: ${_this.formats}, errorCode: ${_this.errorCode}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $YtDlpProbeResultCopyWith<$Res>  {
  factory $YtDlpProbeResultCopyWith(YtDlpProbeResult value, $Res Function(YtDlpProbeResult) _then) = _$YtDlpProbeResultCopyWithImpl;
@useResult
$Res call({
 bool supported, String? title, String? thumbnail, int? durationSeconds, List<YtDlpFormat> formats, String? errorCode, String? errorMessage
});




}
/// @nodoc
class _$YtDlpProbeResultCopyWithImpl<$Res>
    implements $YtDlpProbeResultCopyWith<$Res> {
  _$YtDlpProbeResultCopyWithImpl(this._self, this._then);

  final YtDlpProbeResult _self;
  final $Res Function(YtDlpProbeResult) _then;

/// Create a copy of YtDlpProbeResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? supported = null,Object? title = freezed,Object? thumbnail = freezed,Object? durationSeconds = freezed,Object? formats = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(YtDlpProbeResult(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,thumbnail: freezed == thumbnail ? _self.thumbnail : thumbnail // ignore: cast_nullable_to_non_nullable
as String?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,formats: null == formats ? _self.formats : formats // ignore: cast_nullable_to_non_nullable
as List<YtDlpFormat>,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [YtDlpProbeResult].
extension YtDlpProbeResultPatterns on YtDlpProbeResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _YtDlpProbeResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _YtDlpProbeResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _YtDlpProbeResult value)  $default,){
final _that = this;
switch (_that) {
case _YtDlpProbeResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _YtDlpProbeResult value)?  $default,){
final _that = this;
switch (_that) {
case _YtDlpProbeResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool supported,  String? title,  String? thumbnail,  int? durationSeconds,  List<YtDlpFormat> formats,  String? errorCode,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _YtDlpProbeResult() when $default != null:
return $default(_that.supported,_that.title,_that.thumbnail,_that.durationSeconds,_that.formats,_that.errorCode,_that.errorMessage);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool supported,  String? title,  String? thumbnail,  int? durationSeconds,  List<YtDlpFormat> formats,  String? errorCode,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _YtDlpProbeResult():
return $default(_that.supported,_that.title,_that.thumbnail,_that.durationSeconds,_that.formats,_that.errorCode,_that.errorMessage);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool supported,  String? title,  String? thumbnail,  int? durationSeconds,  List<YtDlpFormat> formats,  String? errorCode,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _YtDlpProbeResult() when $default != null:
return $default(_that.supported,_that.title,_that.thumbnail,_that.durationSeconds,_that.formats,_that.errorCode,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _YtDlpProbeResult implements YtDlpProbeResult {
  const _YtDlpProbeResult({required this.supported, this.title, this.thumbnail, this.durationSeconds,  List<YtDlpFormat> formats = const [], this.errorCode, this.errorMessage}): _formats = formats;
  factory _YtDlpProbeResult.fromJson(Map<String, dynamic> json) => _$YtDlpProbeResultFromJson(json);

@override final  bool supported;
@override final  String? title;
@override final  String? thumbnail;
@override final  int? durationSeconds;
 final  List<YtDlpFormat> _formats;
@override@JsonKey() List<YtDlpFormat> get formats {
  if (_formats is EqualUnmodifiableListView) return _formats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_formats);
}

@override final  String? errorCode;
@override final  String? errorMessage;

/// Create a copy of YtDlpProbeResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$YtDlpProbeResultCopyWith<_YtDlpProbeResult> get copyWith => __$YtDlpProbeResultCopyWithImpl<_YtDlpProbeResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$YtDlpProbeResultToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _YtDlpProbeResult&&(identical(other.supported, supported) || other.supported == supported)&&(identical(other.title, title) || other.title == title)&&(identical(other.thumbnail, thumbnail) || other.thumbnail == thumbnail)&&(identical(other.durationSeconds, durationSeconds) || other.durationSeconds == durationSeconds)&&const DeepCollectionEquality().equals(other.formats, _formats)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,supported,title,thumbnail,durationSeconds,const DeepCollectionEquality().hash(_formats),errorCode,errorMessage);
}

@override
String toString() {
    return 'YtDlpProbeResult(supported: $supported, title: $title, thumbnail: $thumbnail, durationSeconds: $durationSeconds, formats: $formats, errorCode: $errorCode, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$YtDlpProbeResultCopyWith<$Res> implements $YtDlpProbeResultCopyWith<$Res> {
  factory _$YtDlpProbeResultCopyWith(_YtDlpProbeResult value, $Res Function(_YtDlpProbeResult) _then) = __$YtDlpProbeResultCopyWithImpl;
@override @useResult
$Res call({
 bool supported, String? title, String? thumbnail, int? durationSeconds, List<YtDlpFormat> formats, String? errorCode, String? errorMessage
});




}
/// @nodoc
class __$YtDlpProbeResultCopyWithImpl<$Res>
    implements _$YtDlpProbeResultCopyWith<$Res> {
  __$YtDlpProbeResultCopyWithImpl(this._self, this._then);

  final _YtDlpProbeResult _self;
  final $Res Function(_YtDlpProbeResult) _then;

/// Create a copy of YtDlpProbeResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? supported = null,Object? title = freezed,Object? thumbnail = freezed,Object? durationSeconds = freezed,Object? formats = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(_YtDlpProbeResult(
supported: null == supported ? _self.supported : supported // ignore: cast_nullable_to_non_nullable
as bool,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,thumbnail: freezed == thumbnail ? _self.thumbnail : thumbnail // ignore: cast_nullable_to_non_nullable
as String?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,formats: null == formats ? _self._formats : formats // ignore: cast_nullable_to_non_nullable
as List<YtDlpFormat>,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$YtDlpFormat {

 String get formatId; String get ext; String? get resolution; int? get width; int? get height; int? get filesize; int? get filesizeApprox; String get vcodec; String get acodec; double? get fps; String? get note;
/// Create a copy of YtDlpFormat
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$YtDlpFormatCopyWith<YtDlpFormat> get copyWith => _$YtDlpFormatCopyWithImpl<YtDlpFormat>(this as YtDlpFormat, _$identity);

  /// Serializes this YtDlpFormat to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as YtDlpFormat;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is YtDlpFormat&&(identical(other.formatId, _this.formatId) || other.formatId == _this.formatId)&&(identical(other.ext, _this.ext) || other.ext == _this.ext)&&(identical(other.resolution, _this.resolution) || other.resolution == _this.resolution)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height)&&(identical(other.filesize, _this.filesize) || other.filesize == _this.filesize)&&(identical(other.filesizeApprox, _this.filesizeApprox) || other.filesizeApprox == _this.filesizeApprox)&&(identical(other.vcodec, _this.vcodec) || other.vcodec == _this.vcodec)&&(identical(other.acodec, _this.acodec) || other.acodec == _this.acodec)&&(identical(other.fps, _this.fps) || other.fps == _this.fps)&&(identical(other.note, _this.note) || other.note == _this.note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as YtDlpFormat;
  return Object.hash(runtimeType,_this.formatId,_this.ext,_this.resolution,_this.width,_this.height,_this.filesize,_this.filesizeApprox,_this.vcodec,_this.acodec,_this.fps,_this.note);
}

@override
String toString() {
  final _this = this as YtDlpFormat;
  return 'YtDlpFormat(formatId: ${_this.formatId}, ext: ${_this.ext}, resolution: ${_this.resolution}, width: ${_this.width}, height: ${_this.height}, filesize: ${_this.filesize}, filesizeApprox: ${_this.filesizeApprox}, vcodec: ${_this.vcodec}, acodec: ${_this.acodec}, fps: ${_this.fps}, note: ${_this.note})';
}


}

/// @nodoc
abstract mixin class $YtDlpFormatCopyWith<$Res>  {
  factory $YtDlpFormatCopyWith(YtDlpFormat value, $Res Function(YtDlpFormat) _then) = _$YtDlpFormatCopyWithImpl;
@useResult
$Res call({
 String formatId, String ext, String? resolution, int? width, int? height, int? filesize, int? filesizeApprox, String vcodec, String acodec, double? fps, String? note
});




}
/// @nodoc
class _$YtDlpFormatCopyWithImpl<$Res>
    implements $YtDlpFormatCopyWith<$Res> {
  _$YtDlpFormatCopyWithImpl(this._self, this._then);

  final YtDlpFormat _self;
  final $Res Function(YtDlpFormat) _then;

/// Create a copy of YtDlpFormat
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? formatId = null,Object? ext = null,Object? resolution = freezed,Object? width = freezed,Object? height = freezed,Object? filesize = freezed,Object? filesizeApprox = freezed,Object? vcodec = null,Object? acodec = null,Object? fps = freezed,Object? note = freezed,}) {
  return _then(YtDlpFormat(
formatId: null == formatId ? _self.formatId : formatId // ignore: cast_nullable_to_non_nullable
as String,ext: null == ext ? _self.ext : ext // ignore: cast_nullable_to_non_nullable
as String,resolution: freezed == resolution ? _self.resolution : resolution // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,filesize: freezed == filesize ? _self.filesize : filesize // ignore: cast_nullable_to_non_nullable
as int?,filesizeApprox: freezed == filesizeApprox ? _self.filesizeApprox : filesizeApprox // ignore: cast_nullable_to_non_nullable
as int?,vcodec: null == vcodec ? _self.vcodec : vcodec // ignore: cast_nullable_to_non_nullable
as String,acodec: null == acodec ? _self.acodec : acodec // ignore: cast_nullable_to_non_nullable
as String,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [YtDlpFormat].
extension YtDlpFormatPatterns on YtDlpFormat {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _YtDlpFormat value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _YtDlpFormat() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _YtDlpFormat value)  $default,){
final _that = this;
switch (_that) {
case _YtDlpFormat():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _YtDlpFormat value)?  $default,){
final _that = this;
switch (_that) {
case _YtDlpFormat() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String formatId,  String ext,  String? resolution,  int? width,  int? height,  int? filesize,  int? filesizeApprox,  String vcodec,  String acodec,  double? fps,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _YtDlpFormat() when $default != null:
return $default(_that.formatId,_that.ext,_that.resolution,_that.width,_that.height,_that.filesize,_that.filesizeApprox,_that.vcodec,_that.acodec,_that.fps,_that.note);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String formatId,  String ext,  String? resolution,  int? width,  int? height,  int? filesize,  int? filesizeApprox,  String vcodec,  String acodec,  double? fps,  String? note)  $default,) {final _that = this;
switch (_that) {
case _YtDlpFormat():
return $default(_that.formatId,_that.ext,_that.resolution,_that.width,_that.height,_that.filesize,_that.filesizeApprox,_that.vcodec,_that.acodec,_that.fps,_that.note);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String formatId,  String ext,  String? resolution,  int? width,  int? height,  int? filesize,  int? filesizeApprox,  String vcodec,  String acodec,  double? fps,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _YtDlpFormat() when $default != null:
return $default(_that.formatId,_that.ext,_that.resolution,_that.width,_that.height,_that.filesize,_that.filesizeApprox,_that.vcodec,_that.acodec,_that.fps,_that.note);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _YtDlpFormat implements YtDlpFormat {
  const _YtDlpFormat({required this.formatId, required this.ext, this.resolution, this.width, this.height, this.filesize, this.filesizeApprox, required this.vcodec, required this.acodec, this.fps, this.note});
  factory _YtDlpFormat.fromJson(Map<String, dynamic> json) => _$YtDlpFormatFromJson(json);

@override final  String formatId;
@override final  String ext;
@override final  String? resolution;
@override final  int? width;
@override final  int? height;
@override final  int? filesize;
@override final  int? filesizeApprox;
@override final  String vcodec;
@override final  String acodec;
@override final  double? fps;
@override final  String? note;

/// Create a copy of YtDlpFormat
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$YtDlpFormatCopyWith<_YtDlpFormat> get copyWith => __$YtDlpFormatCopyWithImpl<_YtDlpFormat>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$YtDlpFormatToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _YtDlpFormat&&(identical(other.formatId, formatId) || other.formatId == formatId)&&(identical(other.ext, ext) || other.ext == ext)&&(identical(other.resolution, resolution) || other.resolution == resolution)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.filesize, filesize) || other.filesize == filesize)&&(identical(other.filesizeApprox, filesizeApprox) || other.filesizeApprox == filesizeApprox)&&(identical(other.vcodec, vcodec) || other.vcodec == vcodec)&&(identical(other.acodec, acodec) || other.acodec == acodec)&&(identical(other.fps, fps) || other.fps == fps)&&(identical(other.note, note) || other.note == note));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,formatId,ext,resolution,width,height,filesize,filesizeApprox,vcodec,acodec,fps,note);
}

@override
String toString() {
    return 'YtDlpFormat(formatId: $formatId, ext: $ext, resolution: $resolution, width: $width, height: $height, filesize: $filesize, filesizeApprox: $filesizeApprox, vcodec: $vcodec, acodec: $acodec, fps: $fps, note: $note)';
}


}

/// @nodoc
abstract mixin class _$YtDlpFormatCopyWith<$Res> implements $YtDlpFormatCopyWith<$Res> {
  factory _$YtDlpFormatCopyWith(_YtDlpFormat value, $Res Function(_YtDlpFormat) _then) = __$YtDlpFormatCopyWithImpl;
@override @useResult
$Res call({
 String formatId, String ext, String? resolution, int? width, int? height, int? filesize, int? filesizeApprox, String vcodec, String acodec, double? fps, String? note
});




}
/// @nodoc
class __$YtDlpFormatCopyWithImpl<$Res>
    implements _$YtDlpFormatCopyWith<$Res> {
  __$YtDlpFormatCopyWithImpl(this._self, this._then);

  final _YtDlpFormat _self;
  final $Res Function(_YtDlpFormat) _then;

/// Create a copy of YtDlpFormat
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? formatId = null,Object? ext = null,Object? resolution = freezed,Object? width = freezed,Object? height = freezed,Object? filesize = freezed,Object? filesizeApprox = freezed,Object? vcodec = null,Object? acodec = null,Object? fps = freezed,Object? note = freezed,}) {
  return _then(_YtDlpFormat(
formatId: null == formatId ? _self.formatId : formatId // ignore: cast_nullable_to_non_nullable
as String,ext: null == ext ? _self.ext : ext // ignore: cast_nullable_to_non_nullable
as String,resolution: freezed == resolution ? _self.resolution : resolution // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,filesize: freezed == filesize ? _self.filesize : filesize // ignore: cast_nullable_to_non_nullable
as int?,filesizeApprox: freezed == filesizeApprox ? _self.filesizeApprox : filesizeApprox // ignore: cast_nullable_to_non_nullable
as int?,vcodec: null == vcodec ? _self.vcodec : vcodec // ignore: cast_nullable_to_non_nullable
as String,acodec: null == acodec ? _self.acodec : acodec // ignore: cast_nullable_to_non_nullable
as String,fps: freezed == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
