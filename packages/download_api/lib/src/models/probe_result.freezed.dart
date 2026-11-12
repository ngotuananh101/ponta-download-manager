// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'probe_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ProbeResult {

 String get url; String get fileName; int get totalBytes;
/// Create a copy of ProbeResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProbeResultCopyWith<ProbeResult> get copyWith => _$ProbeResultCopyWithImpl<ProbeResult>(this as ProbeResult, _$identity);

  /// Serializes this ProbeResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProbeResult&&(identical(other.url, url) || other.url == url)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,fileName,totalBytes);

@override
String toString() {
  return 'ProbeResult(url: $url, fileName: $fileName, totalBytes: $totalBytes)';
}


}

/// @nodoc
abstract mixin class $ProbeResultCopyWith<$Res>  {
  factory $ProbeResultCopyWith(ProbeResult value, $Res Function(ProbeResult) _then) = _$ProbeResultCopyWithImpl;
@useResult
$Res call({
 String url, String fileName, int totalBytes
});




}
/// @nodoc
class _$ProbeResultCopyWithImpl<$Res>
    implements $ProbeResultCopyWith<$Res> {
  _$ProbeResultCopyWithImpl(this._self, this._then);

  final ProbeResult _self;
  final $Res Function(ProbeResult) _then;

/// Create a copy of ProbeResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? fileName = null,Object? totalBytes = null,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProbeResult].
extension ProbeResultPatterns on ProbeResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProbeResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProbeResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProbeResult value)  $default,){
final _that = this;
switch (_that) {
case _ProbeResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProbeResult value)?  $default,){
final _that = this;
switch (_that) {
case _ProbeResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String fileName,  int totalBytes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProbeResult() when $default != null:
return $default(_that.url,_that.fileName,_that.totalBytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String fileName,  int totalBytes)  $default,) {final _that = this;
switch (_that) {
case _ProbeResult():
return $default(_that.url,_that.fileName,_that.totalBytes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String fileName,  int totalBytes)?  $default,) {final _that = this;
switch (_that) {
case _ProbeResult() when $default != null:
return $default(_that.url,_that.fileName,_that.totalBytes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ProbeResult implements ProbeResult {
  const _ProbeResult({required this.url, required this.fileName, required this.totalBytes});
  factory _ProbeResult.fromJson(Map<String, dynamic> json) => _$ProbeResultFromJson(json);

@override final  String url;
@override final  String fileName;
@override final  int totalBytes;

/// Create a copy of ProbeResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProbeResultCopyWith<_ProbeResult> get copyWith => __$ProbeResultCopyWithImpl<_ProbeResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProbeResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProbeResult&&(identical(other.url, url) || other.url == url)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,fileName,totalBytes);

@override
String toString() {
  return 'ProbeResult(url: $url, fileName: $fileName, totalBytes: $totalBytes)';
}


}

/// @nodoc
abstract mixin class _$ProbeResultCopyWith<$Res> implements $ProbeResultCopyWith<$Res> {
  factory _$ProbeResultCopyWith(_ProbeResult value, $Res Function(_ProbeResult) _then) = __$ProbeResultCopyWithImpl;
@override @useResult
$Res call({
 String url, String fileName, int totalBytes
});




}
/// @nodoc
class __$ProbeResultCopyWithImpl<$Res>
    implements _$ProbeResultCopyWith<$Res> {
  __$ProbeResultCopyWithImpl(this._self, this._then);

  final _ProbeResult _self;
  final $Res Function(_ProbeResult) _then;

/// Create a copy of ProbeResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? fileName = null,Object? totalBytes = null,}) {
  return _then(_ProbeResult(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
