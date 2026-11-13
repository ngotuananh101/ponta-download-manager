// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DownloadInfo {

 String get id; String get url; String get fileName; DownloadStatus get status; int get downloadedBytes; int get totalBytes; int get bytesPerSecond; DateTime? get createdAt; String? get filePath; int get priority; List<String> get tags; String? get errorCode; String? get errorMessage;
/// Create a copy of DownloadInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadInfoCopyWith<DownloadInfo> get copyWith => _$DownloadInfoCopyWithImpl<DownloadInfo>(this as DownloadInfo, _$identity);

  /// Serializes this DownloadInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DownloadInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadInfo&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.fileName, _this.fileName) || other.fileName == _this.fileName)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.downloadedBytes, _this.downloadedBytes) || other.downloadedBytes == _this.downloadedBytes)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.bytesPerSecond, _this.bytesPerSecond) || other.bytesPerSecond == _this.bytesPerSecond)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.filePath, _this.filePath) || other.filePath == _this.filePath)&&(identical(other.priority, _this.priority) || other.priority == _this.priority)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.errorCode, _this.errorCode) || other.errorCode == _this.errorCode)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DownloadInfo;
  return Object.hash(runtimeType,_this.id,_this.url,_this.fileName,_this.status,_this.downloadedBytes,_this.totalBytes,_this.bytesPerSecond,_this.createdAt,_this.filePath,_this.priority,const DeepCollectionEquality().hash(_this.tags),_this.errorCode,_this.errorMessage);
}

@override
String toString() {
  final _this = this as DownloadInfo;
  return 'DownloadInfo(id: ${_this.id}, url: ${_this.url}, fileName: ${_this.fileName}, status: ${_this.status}, downloadedBytes: ${_this.downloadedBytes}, totalBytes: ${_this.totalBytes}, bytesPerSecond: ${_this.bytesPerSecond}, createdAt: ${_this.createdAt}, filePath: ${_this.filePath}, priority: ${_this.priority}, tags: ${_this.tags}, errorCode: ${_this.errorCode}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $DownloadInfoCopyWith<$Res>  {
  factory $DownloadInfoCopyWith(DownloadInfo value, $Res Function(DownloadInfo) _then) = _$DownloadInfoCopyWithImpl;
@useResult
$Res call({
 String id, String url, String fileName, DownloadStatus status, int downloadedBytes, int totalBytes, int bytesPerSecond, DateTime? createdAt, String? filePath, int priority, List<String> tags, String? errorCode, String? errorMessage
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? url = null,Object? fileName = null,Object? status = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? bytesPerSecond = null,Object? createdAt = freezed,Object? filePath = freezed,Object? priority = null,Object? tags = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(DownloadInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,bytesPerSecond: null == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,filePath: freezed == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond,  DateTime? createdAt,  String? filePath,  int priority,  List<String> tags,  String? errorCode,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond,_that.createdAt,_that.filePath,_that.priority,_that.tags,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond,  DateTime? createdAt,  String? filePath,  int priority,  List<String> tags,  String? errorCode,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _DownloadInfo():
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond,_that.createdAt,_that.filePath,_that.priority,_that.tags,_that.errorCode,_that.errorMessage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String url,  String fileName,  DownloadStatus status,  int downloadedBytes,  int totalBytes,  int bytesPerSecond,  DateTime? createdAt,  String? filePath,  int priority,  List<String> tags,  String? errorCode,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _DownloadInfo() when $default != null:
return $default(_that.id,_that.url,_that.fileName,_that.status,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond,_that.createdAt,_that.filePath,_that.priority,_that.tags,_that.errorCode,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadInfo implements DownloadInfo {
  const _DownloadInfo({required this.id, required this.url, required this.fileName, required this.status, this.downloadedBytes = 0, required this.totalBytes, this.bytesPerSecond = 0, this.createdAt, this.filePath, this.priority = 0,  List<String> tags = const [], this.errorCode, this.errorMessage}): _tags = tags;
  factory _DownloadInfo.fromJson(Map<String, dynamic> json) => _$DownloadInfoFromJson(json);

@override final  String id;
@override final  String url;
@override final  String fileName;
@override final  DownloadStatus status;
@override@JsonKey() final  int downloadedBytes;
@override final  int totalBytes;
@override@JsonKey() final  int bytesPerSecond;
@override final  DateTime? createdAt;
@override final  String? filePath;
@override@JsonKey() final  int priority;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override final  String? errorCode;
@override final  String? errorMessage;

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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadInfo&&(identical(other.id, id) || other.id == id)&&(identical(other.url, url) || other.url == url)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.status, status) || other.status == status)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSecond, bytesPerSecond) || other.bytesPerSecond == bytesPerSecond)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.errorCode, errorCode) || other.errorCode == errorCode)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,url,fileName,status,downloadedBytes,totalBytes,bytesPerSecond,createdAt,filePath,priority,const DeepCollectionEquality().hash(_tags),errorCode,errorMessage);
}

@override
String toString() {
    return 'DownloadInfo(id: $id, url: $url, fileName: $fileName, status: $status, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, bytesPerSecond: $bytesPerSecond, createdAt: $createdAt, filePath: $filePath, priority: $priority, tags: $tags, errorCode: $errorCode, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$DownloadInfoCopyWith<$Res> implements $DownloadInfoCopyWith<$Res> {
  factory _$DownloadInfoCopyWith(_DownloadInfo value, $Res Function(_DownloadInfo) _then) = __$DownloadInfoCopyWithImpl;
@override @useResult
$Res call({
 String id, String url, String fileName, DownloadStatus status, int downloadedBytes, int totalBytes, int bytesPerSecond, DateTime? createdAt, String? filePath, int priority, List<String> tags, String? errorCode, String? errorMessage
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? url = null,Object? fileName = null,Object? status = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? bytesPerSecond = null,Object? createdAt = freezed,Object? filePath = freezed,Object? priority = null,Object? tags = null,Object? errorCode = freezed,Object? errorMessage = freezed,}) {
  return _then(_DownloadInfo(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,bytesPerSecond: null == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,filePath: freezed == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String?,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,errorCode: freezed == errorCode ? _self.errorCode : errorCode // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
