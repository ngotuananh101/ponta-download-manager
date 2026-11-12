// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_check_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$UpdateCheckResult {

 bool get hasUpdate; bool get inconclusive; int get newTotalBytes;
/// Create a copy of UpdateCheckResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateCheckResultCopyWith<UpdateCheckResult> get copyWith => _$UpdateCheckResultCopyWithImpl<UpdateCheckResult>(this as UpdateCheckResult, _$identity);

  /// Serializes this UpdateCheckResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateCheckResult&&(identical(other.hasUpdate, hasUpdate) || other.hasUpdate == hasUpdate)&&(identical(other.inconclusive, inconclusive) || other.inconclusive == inconclusive)&&(identical(other.newTotalBytes, newTotalBytes) || other.newTotalBytes == newTotalBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,hasUpdate,inconclusive,newTotalBytes);

@override
String toString() {
  return 'UpdateCheckResult(hasUpdate: $hasUpdate, inconclusive: $inconclusive, newTotalBytes: $newTotalBytes)';
}


}

/// @nodoc
abstract mixin class $UpdateCheckResultCopyWith<$Res>  {
  factory $UpdateCheckResultCopyWith(UpdateCheckResult value, $Res Function(UpdateCheckResult) _then) = _$UpdateCheckResultCopyWithImpl;
@useResult
$Res call({
 bool hasUpdate, bool inconclusive, int newTotalBytes
});




}
/// @nodoc
class _$UpdateCheckResultCopyWithImpl<$Res>
    implements $UpdateCheckResultCopyWith<$Res> {
  _$UpdateCheckResultCopyWithImpl(this._self, this._then);

  final UpdateCheckResult _self;
  final $Res Function(UpdateCheckResult) _then;

/// Create a copy of UpdateCheckResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hasUpdate = null,Object? inconclusive = null,Object? newTotalBytes = null,}) {
  return _then(_self.copyWith(
hasUpdate: null == hasUpdate ? _self.hasUpdate : hasUpdate // ignore: cast_nullable_to_non_nullable
as bool,inconclusive: null == inconclusive ? _self.inconclusive : inconclusive // ignore: cast_nullable_to_non_nullable
as bool,newTotalBytes: null == newTotalBytes ? _self.newTotalBytes : newTotalBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateCheckResult].
extension UpdateCheckResultPatterns on UpdateCheckResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateCheckResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateCheckResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateCheckResult value)  $default,){
final _that = this;
switch (_that) {
case _UpdateCheckResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateCheckResult value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateCheckResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool hasUpdate,  bool inconclusive,  int newTotalBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateCheckResult() when $default != null:
return $default(_that.hasUpdate,_that.inconclusive,_that.newTotalBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool hasUpdate,  bool inconclusive,  int newTotalBytes)  $default,) {final _that = this;
switch (_that) {
case _UpdateCheckResult():
return $default(_that.hasUpdate,_that.inconclusive,_that.newTotalBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool hasUpdate,  bool inconclusive,  int newTotalBytes)?  $default,) {final _that = this;
switch (_that) {
case _UpdateCheckResult() when $default != null:
return $default(_that.hasUpdate,_that.inconclusive,_that.newTotalBytes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UpdateCheckResult implements UpdateCheckResult {
  const _UpdateCheckResult({required this.hasUpdate, required this.inconclusive, required this.newTotalBytes});
  factory _UpdateCheckResult.fromJson(Map<String, dynamic> json) => _$UpdateCheckResultFromJson(json);

@override final  bool hasUpdate;
@override final  bool inconclusive;
@override final  int newTotalBytes;

/// Create a copy of UpdateCheckResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateCheckResultCopyWith<_UpdateCheckResult> get copyWith => __$UpdateCheckResultCopyWithImpl<_UpdateCheckResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UpdateCheckResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateCheckResult&&(identical(other.hasUpdate, hasUpdate) || other.hasUpdate == hasUpdate)&&(identical(other.inconclusive, inconclusive) || other.inconclusive == inconclusive)&&(identical(other.newTotalBytes, newTotalBytes) || other.newTotalBytes == newTotalBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,hasUpdate,inconclusive,newTotalBytes);

@override
String toString() {
  return 'UpdateCheckResult(hasUpdate: $hasUpdate, inconclusive: $inconclusive, newTotalBytes: $newTotalBytes)';
}


}

/// @nodoc
abstract mixin class _$UpdateCheckResultCopyWith<$Res> implements $UpdateCheckResultCopyWith<$Res> {
  factory _$UpdateCheckResultCopyWith(_UpdateCheckResult value, $Res Function(_UpdateCheckResult) _then) = __$UpdateCheckResultCopyWithImpl;
@override @useResult
$Res call({
 bool hasUpdate, bool inconclusive, int newTotalBytes
});




}
/// @nodoc
class __$UpdateCheckResultCopyWithImpl<$Res>
    implements _$UpdateCheckResultCopyWith<$Res> {
  __$UpdateCheckResultCopyWithImpl(this._self, this._then);

  final _UpdateCheckResult _self;
  final $Res Function(_UpdateCheckResult) _then;

/// Create a copy of UpdateCheckResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hasUpdate = null,Object? inconclusive = null,Object? newTotalBytes = null,}) {
  return _then(_UpdateCheckResult(
hasUpdate: null == hasUpdate ? _self.hasUpdate : hasUpdate // ignore: cast_nullable_to_non_nullable
as bool,inconclusive: null == inconclusive ? _self.inconclusive : inconclusive // ignore: cast_nullable_to_non_nullable
as bool,newTotalBytes: null == newTotalBytes ? _self.newTotalBytes : newTotalBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
