// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'download_segment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$DownloadSegment {

 int get segmentId; int get start; int? get end; int get downloaded;
/// Create a copy of DownloadSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadSegmentCopyWith<DownloadSegment> get copyWith => _$DownloadSegmentCopyWithImpl<DownloadSegment>(this as DownloadSegment, _$identity);

  /// Serializes this DownloadSegment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as DownloadSegment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadSegment&&(identical(other.segmentId, _this.segmentId) || other.segmentId == _this.segmentId)&&(identical(other.start, _this.start) || other.start == _this.start)&&(identical(other.end, _this.end) || other.end == _this.end)&&(identical(other.downloaded, _this.downloaded) || other.downloaded == _this.downloaded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as DownloadSegment;
  return Object.hash(runtimeType,_this.segmentId,_this.start,_this.end,_this.downloaded);
}

@override
String toString() {
  final _this = this as DownloadSegment;
  return 'DownloadSegment(segmentId: ${_this.segmentId}, start: ${_this.start}, end: ${_this.end}, downloaded: ${_this.downloaded})';
}


}

/// @nodoc
abstract mixin class $DownloadSegmentCopyWith<$Res>  {
  factory $DownloadSegmentCopyWith(DownloadSegment value, $Res Function(DownloadSegment) _then) = _$DownloadSegmentCopyWithImpl;
@useResult
$Res call({
 int segmentId, int start, int? end, int downloaded
});




}
/// @nodoc
class _$DownloadSegmentCopyWithImpl<$Res>
    implements $DownloadSegmentCopyWith<$Res> {
  _$DownloadSegmentCopyWithImpl(this._self, this._then);

  final DownloadSegment _self;
  final $Res Function(DownloadSegment) _then;

/// Create a copy of DownloadSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? segmentId = null,Object? start = null,Object? end = freezed,Object? downloaded = null,}) {
  return _then(DownloadSegment(
segmentId: null == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as int,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int?,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DownloadSegment].
extension DownloadSegmentPatterns on DownloadSegment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DownloadSegment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DownloadSegment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DownloadSegment value)  $default,){
final _that = this;
switch (_that) {
case _DownloadSegment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DownloadSegment value)?  $default,){
final _that = this;
switch (_that) {
case _DownloadSegment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int segmentId,  int start,  int? end,  int downloaded)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DownloadSegment() when $default != null:
return $default(_that.segmentId,_that.start,_that.end,_that.downloaded);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int segmentId,  int start,  int? end,  int downloaded)  $default,) {final _that = this;
switch (_that) {
case _DownloadSegment():
return $default(_that.segmentId,_that.start,_that.end,_that.downloaded);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int segmentId,  int start,  int? end,  int downloaded)?  $default,) {final _that = this;
switch (_that) {
case _DownloadSegment() when $default != null:
return $default(_that.segmentId,_that.start,_that.end,_that.downloaded);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DownloadSegment implements DownloadSegment {
  const _DownloadSegment({required this.segmentId, required this.start, this.end, this.downloaded = 0});
  factory _DownloadSegment.fromJson(Map<String, dynamic> json) => _$DownloadSegmentFromJson(json);

@override final  int segmentId;
@override final  int start;
@override final  int? end;
@override@JsonKey() final  int downloaded;

/// Create a copy of DownloadSegment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DownloadSegmentCopyWith<_DownloadSegment> get copyWith => __$DownloadSegmentCopyWithImpl<_DownloadSegment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DownloadSegmentToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _DownloadSegment&&(identical(other.segmentId, segmentId) || other.segmentId == segmentId)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,segmentId,start,end,downloaded);
}

@override
String toString() {
    return 'DownloadSegment(segmentId: $segmentId, start: $start, end: $end, downloaded: $downloaded)';
}


}

/// @nodoc
abstract mixin class _$DownloadSegmentCopyWith<$Res> implements $DownloadSegmentCopyWith<$Res> {
  factory _$DownloadSegmentCopyWith(_DownloadSegment value, $Res Function(_DownloadSegment) _then) = __$DownloadSegmentCopyWithImpl;
@override @useResult
$Res call({
 int segmentId, int start, int? end, int downloaded
});




}
/// @nodoc
class __$DownloadSegmentCopyWithImpl<$Res>
    implements _$DownloadSegmentCopyWith<$Res> {
  __$DownloadSegmentCopyWithImpl(this._self, this._then);

  final _DownloadSegment _self;
  final $Res Function(_DownloadSegment) _then;

/// Create a copy of DownloadSegment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? segmentId = null,Object? start = null,Object? end = freezed,Object? downloaded = null,}) {
  return _then(_DownloadSegment(
segmentId: null == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as int,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: freezed == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int?,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
