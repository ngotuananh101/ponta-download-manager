// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
DownloadEvent _$DownloadEventFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'progress':
          return DownloadProgress.fromJson(
            json
          );
                case 'stateChanged':
          return DownloadStateChanged.fromJson(
            json
          );
                case 'completed':
          return DownloadCompleted.fromJson(
            json
          );
                case 'failed':
          return DownloadFailed.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'DownloadEvent',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$DownloadEvent {

 String get downloadId;
/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadEventCopyWith<DownloadEvent> get copyWith => _$DownloadEventCopyWithImpl<DownloadEvent>(this as DownloadEvent, _$identity);

  /// Serializes this DownloadEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadEvent&&(identical(other.downloadId, downloadId) || other.downloadId == downloadId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,downloadId);

@override
String toString() {
  return 'DownloadEvent(downloadId: $downloadId)';
}


}

/// @nodoc
abstract mixin class $DownloadEventCopyWith<$Res>  {
  factory $DownloadEventCopyWith(DownloadEvent value, $Res Function(DownloadEvent) _then) = _$DownloadEventCopyWithImpl;
@useResult
$Res call({
 String downloadId
});




}
/// @nodoc
class _$DownloadEventCopyWithImpl<$Res>
    implements $DownloadEventCopyWith<$Res> {
  _$DownloadEventCopyWithImpl(this._self, this._then);

  final DownloadEvent _self;
  final $Res Function(DownloadEvent) _then;

/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? downloadId = null,}) {
  return _then(_self.copyWith(
downloadId: null == downloadId ? _self.downloadId : downloadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadEvent].
extension DownloadEventPatterns on DownloadEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DownloadProgress value)?  progress,TResult Function( DownloadStateChanged value)?  stateChanged,TResult Function( DownloadCompleted value)?  completed,TResult Function( DownloadFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DownloadProgress() when progress != null:
return progress(_that);case DownloadStateChanged() when stateChanged != null:
return stateChanged(_that);case DownloadCompleted() when completed != null:
return completed(_that);case DownloadFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DownloadProgress value)  progress,required TResult Function( DownloadStateChanged value)  stateChanged,required TResult Function( DownloadCompleted value)  completed,required TResult Function( DownloadFailed value)  failed,}){
final _that = this;
switch (_that) {
case DownloadProgress():
return progress(_that);case DownloadStateChanged():
return stateChanged(_that);case DownloadCompleted():
return completed(_that);case DownloadFailed():
return failed(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DownloadProgress value)?  progress,TResult? Function( DownloadStateChanged value)?  stateChanged,TResult? Function( DownloadCompleted value)?  completed,TResult? Function( DownloadFailed value)?  failed,}){
final _that = this;
switch (_that) {
case DownloadProgress() when progress != null:
return progress(_that);case DownloadStateChanged() when stateChanged != null:
return stateChanged(_that);case DownloadCompleted() when completed != null:
return completed(_that);case DownloadFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String downloadId,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)?  progress,TResult Function( String downloadId,  DownloadStatus status)?  stateChanged,TResult Function( String downloadId,  String filePath)?  completed,TResult Function( String downloadId,  String code,  String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DownloadProgress() when progress != null:
return progress(_that.downloadId,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case DownloadStateChanged() when stateChanged != null:
return stateChanged(_that.downloadId,_that.status);case DownloadCompleted() when completed != null:
return completed(_that.downloadId,_that.filePath);case DownloadFailed() when failed != null:
return failed(_that.downloadId,_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String downloadId,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)  progress,required TResult Function( String downloadId,  DownloadStatus status)  stateChanged,required TResult Function( String downloadId,  String filePath)  completed,required TResult Function( String downloadId,  String code,  String message)  failed,}) {final _that = this;
switch (_that) {
case DownloadProgress():
return progress(_that.downloadId,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case DownloadStateChanged():
return stateChanged(_that.downloadId,_that.status);case DownloadCompleted():
return completed(_that.downloadId,_that.filePath);case DownloadFailed():
return failed(_that.downloadId,_that.code,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String downloadId,  int downloadedBytes,  int totalBytes,  int bytesPerSecond)?  progress,TResult? Function( String downloadId,  DownloadStatus status)?  stateChanged,TResult? Function( String downloadId,  String filePath)?  completed,TResult? Function( String downloadId,  String code,  String message)?  failed,}) {final _that = this;
switch (_that) {
case DownloadProgress() when progress != null:
return progress(_that.downloadId,_that.downloadedBytes,_that.totalBytes,_that.bytesPerSecond);case DownloadStateChanged() when stateChanged != null:
return stateChanged(_that.downloadId,_that.status);case DownloadCompleted() when completed != null:
return completed(_that.downloadId,_that.filePath);case DownloadFailed() when failed != null:
return failed(_that.downloadId,_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class DownloadProgress implements DownloadEvent {
  const DownloadProgress({required this.downloadId, required this.downloadedBytes, required this.totalBytes, required this.bytesPerSecond, final  String? $type}): $type = $type ?? 'progress';
  factory DownloadProgress.fromJson(Map<String, dynamic> json) => _$DownloadProgressFromJson(json);

@override final  String downloadId;
 final  int downloadedBytes;
 final  int totalBytes;
 final  int bytesPerSecond;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadProgressCopyWith<DownloadProgress> get copyWith => _$DownloadProgressCopyWithImpl<DownloadProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadProgressToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadProgress&&(identical(other.downloadId, downloadId) || other.downloadId == downloadId)&&(identical(other.downloadedBytes, downloadedBytes) || other.downloadedBytes == downloadedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSecond, bytesPerSecond) || other.bytesPerSecond == bytesPerSecond));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,downloadId,downloadedBytes,totalBytes,bytesPerSecond);

@override
String toString() {
  return 'DownloadEvent.progress(downloadId: $downloadId, downloadedBytes: $downloadedBytes, totalBytes: $totalBytes, bytesPerSecond: $bytesPerSecond)';
}


}

/// @nodoc
abstract mixin class $DownloadProgressCopyWith<$Res> implements $DownloadEventCopyWith<$Res> {
  factory $DownloadProgressCopyWith(DownloadProgress value, $Res Function(DownloadProgress) _then) = _$DownloadProgressCopyWithImpl;
@override @useResult
$Res call({
 String downloadId, int downloadedBytes, int totalBytes, int bytesPerSecond
});




}
/// @nodoc
class _$DownloadProgressCopyWithImpl<$Res>
    implements $DownloadProgressCopyWith<$Res> {
  _$DownloadProgressCopyWithImpl(this._self, this._then);

  final DownloadProgress _self;
  final $Res Function(DownloadProgress) _then;

/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? downloadId = null,Object? downloadedBytes = null,Object? totalBytes = null,Object? bytesPerSecond = null,}) {
  return _then(DownloadProgress(
downloadId: null == downloadId ? _self.downloadId : downloadId // ignore: cast_nullable_to_non_nullable
as String,downloadedBytes: null == downloadedBytes ? _self.downloadedBytes : downloadedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,bytesPerSecond: null == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DownloadStateChanged implements DownloadEvent {
  const DownloadStateChanged({required this.downloadId, required this.status, final  String? $type}): $type = $type ?? 'stateChanged';
  factory DownloadStateChanged.fromJson(Map<String, dynamic> json) => _$DownloadStateChangedFromJson(json);

@override final  String downloadId;
 final  DownloadStatus status;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadStateChangedCopyWith<DownloadStateChanged> get copyWith => _$DownloadStateChangedCopyWithImpl<DownloadStateChanged>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadStateChangedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadStateChanged&&(identical(other.downloadId, downloadId) || other.downloadId == downloadId)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,downloadId,status);

@override
String toString() {
  return 'DownloadEvent.stateChanged(downloadId: $downloadId, status: $status)';
}


}

/// @nodoc
abstract mixin class $DownloadStateChangedCopyWith<$Res> implements $DownloadEventCopyWith<$Res> {
  factory $DownloadStateChangedCopyWith(DownloadStateChanged value, $Res Function(DownloadStateChanged) _then) = _$DownloadStateChangedCopyWithImpl;
@override @useResult
$Res call({
 String downloadId, DownloadStatus status
});




}
/// @nodoc
class _$DownloadStateChangedCopyWithImpl<$Res>
    implements $DownloadStateChangedCopyWith<$Res> {
  _$DownloadStateChangedCopyWithImpl(this._self, this._then);

  final DownloadStateChanged _self;
  final $Res Function(DownloadStateChanged) _then;

/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? downloadId = null,Object? status = null,}) {
  return _then(DownloadStateChanged(
downloadId: null == downloadId ? _self.downloadId : downloadId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as DownloadStatus,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DownloadCompleted implements DownloadEvent {
  const DownloadCompleted({required this.downloadId, required this.filePath, final  String? $type}): $type = $type ?? 'completed';
  factory DownloadCompleted.fromJson(Map<String, dynamic> json) => _$DownloadCompletedFromJson(json);

@override final  String downloadId;
 final  String filePath;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadCompletedCopyWith<DownloadCompleted> get copyWith => _$DownloadCompletedCopyWithImpl<DownloadCompleted>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadCompletedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadCompleted&&(identical(other.downloadId, downloadId) || other.downloadId == downloadId)&&(identical(other.filePath, filePath) || other.filePath == filePath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,downloadId,filePath);

@override
String toString() {
  return 'DownloadEvent.completed(downloadId: $downloadId, filePath: $filePath)';
}


}

/// @nodoc
abstract mixin class $DownloadCompletedCopyWith<$Res> implements $DownloadEventCopyWith<$Res> {
  factory $DownloadCompletedCopyWith(DownloadCompleted value, $Res Function(DownloadCompleted) _then) = _$DownloadCompletedCopyWithImpl;
@override @useResult
$Res call({
 String downloadId, String filePath
});




}
/// @nodoc
class _$DownloadCompletedCopyWithImpl<$Res>
    implements $DownloadCompletedCopyWith<$Res> {
  _$DownloadCompletedCopyWithImpl(this._self, this._then);

  final DownloadCompleted _self;
  final $Res Function(DownloadCompleted) _then;

/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? downloadId = null,Object? filePath = null,}) {
  return _then(DownloadCompleted(
downloadId: null == downloadId ? _self.downloadId : downloadId // ignore: cast_nullable_to_non_nullable
as String,filePath: null == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DownloadFailed implements DownloadEvent {
  const DownloadFailed({required this.downloadId, required this.code, required this.message, final  String? $type}): $type = $type ?? 'failed';
  factory DownloadFailed.fromJson(Map<String, dynamic> json) => _$DownloadFailedFromJson(json);

@override final  String downloadId;
 final  String code;
 final  String message;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadFailedCopyWith<DownloadFailed> get copyWith => _$DownloadFailedCopyWithImpl<DownloadFailed>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadFailedToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadFailed&&(identical(other.downloadId, downloadId) || other.downloadId == downloadId)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,downloadId,code,message);

@override
String toString() {
  return 'DownloadEvent.failed(downloadId: $downloadId, code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $DownloadFailedCopyWith<$Res> implements $DownloadEventCopyWith<$Res> {
  factory $DownloadFailedCopyWith(DownloadFailed value, $Res Function(DownloadFailed) _then) = _$DownloadFailedCopyWithImpl;
@override @useResult
$Res call({
 String downloadId, String code, String message
});




}
/// @nodoc
class _$DownloadFailedCopyWithImpl<$Res>
    implements $DownloadFailedCopyWith<$Res> {
  _$DownloadFailedCopyWithImpl(this._self, this._then);

  final DownloadFailed _self;
  final $Res Function(DownloadFailed) _then;

/// Create a copy of DownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? downloadId = null,Object? code = null,Object? message = null,}) {
  return _then(DownloadFailed(
downloadId: null == downloadId ? _self.downloadId : downloadId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
