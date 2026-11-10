// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DownloadInfo {

 String get id; String get url; String get fileName; DownloadStatus get status; int get downloadedBytes; int get totalBytes; int get bytesPerSecond;
/// Create a copy of DownloadInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadInfoCopyWith<DownloadInfo> get copyWith => _$DownloadInfoCopyWithImpl<DownloadInfo>(this as DownloadInfo, _$identity);

  /// Serializes this DownloadInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.url, url) || other.url == url)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.status, status) || other.status == status)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSecond, bytesPerSecond) || other.bytesPerSecond == bytesPerSecond));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,url,fileName,status,downloadedBytes,totalBytes,bytesPerSecond);

@override
String toString() {
  return 'DownloadInfo(id: $id, url: $url, fileName: $fileName, status: $status, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, bytesPerSecond: $bytesPerSecond)';
}


}

/// @nodoc
abstract mixin class $DownloadInfoCopyWith<$Res>  {
  factory $DownloadInfoCopyWith(DownloadInfo value, $Res Function(DownloadInfo) _then) = _$DownloadInfoCopyWithImpl;
@useResult
$Res call({
 String id, String url, String fileName, DownloadStatus status, int downloadedBytes, int totalBytes, int bytesPerSecond
});




}
/// @nodoc
class _$DownloadInfoCopyWithImpl<$Res>
    implements $DownloadInfoCopyWith<$Res> {
  _$DownloadInfoCopyWithImpl(this._self, this._then);

  final DownloadInfo _self;
  final $Res Function(DownloadInfo) _then;

/// Create a copy of DownloadInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? url = null,Object? fileName = null,Object? status = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? bytesPerSecond = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,bytesPerSecond: null == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadInfo].
extension DownloadInfoPatterns on DownloadInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadInfo value)  $default,){
final _that = this;
switch (_that) {
case _DownloadInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadInfo value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)  $default,) {final _that = this;
switch (_that) {
case _DownloadInfo():
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)?  $default,) {final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadInfo implements DownloadInfo {
  const _DownloadInfo({required this.id, required this.url, required this.fileName, required this.status, this.downloadedBytes = 0, required this.totalBytes, this.bytesPerSecond = 0});
  factory _DownloadInfo.fromJson(Map<String, dynamic> json) => _$DownloadInfoFromJson(json);

@override final  String id;
@override final  String url;
@override final  String fileName;
@override final  DownloadStatus status;
@override@JsonKey() final  int downloadedBytes;
@override final  int totalBytes;
@override@JsonKey() final  int bytesPerSecond;

/// Create a copy of DownloadInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadInfoCopyWith<_DownloadInfo> get copyWith => __$DownloadInfoCopyWithImpl<_DownloadInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadInfoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.url, url) || other.url == url)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.status, status) || other.status == status)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSecond, bytesPerSecond) || other.bytesPerSecond == bytesPerSecond));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,url,fileName,status,downloadedBytes,totalBytes,bytesPerSecond);

@override
String toString() {
  return 'DownloadInfo(id: $id, url: $url, fileName: $fileName, status: $status, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, bytesPerSecond: $bytesPerSecond)';
}


}

/// @nodoc
abstract mixin class _$DownloadInfoCopyWith<$Res> implements $DownloadInfoCopyWith<$Res> {
  factory _$DownloadInfoCopyWith(_DownloadInfo value, $Res Function(_DownloadInfo) _then) = __$DownloadInfoCopyWithImpl;
@override @useResult
$Res call({
 String id, String url, String fileName, DownloadStatus status, int downloadedBytes, int totalBytes, int bytesPerSecond
});




}
/// @nodoc
class __$DownloadInfoCopyWithImpl<$Res>
    implements _$DownloadInfoCopyWith<$Res> {
  __$DownloadInfoCopyWithImpl(this._self, this._then);

  final _DownloadInfo _self;
  final $Res Function(_DownloadInfo) _then;

/// Create a copy of DownloadInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? url = null,Object? fileName = null,Object? status = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? bytesPerSecond = null,}) {
  return _then(_DownloadInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,bytesPerSecond: null == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
