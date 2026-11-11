// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'create_download_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CreateDownloadRequest {

 String get url; String get destination; int? get maxConnections; int? get priority; FileConflictPolicy? get conflictPolicy;
/// Create a copy of CreateDownloadRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CreateDownloadRequestCopyWith<CreateDownloadRequest> get copyWith => _$CreateDownloadRequestCopyWithImpl<CreateDownloadRequest>(this as CreateDownloadRequest, _$identity);

  /// Serializes this CreateDownloadRequest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CreateDownloadRequest&&(identical(other.url, url) || other.url == url)&&(identical(other.destination, destination) || other.destination == destination)&&(identical(other.maxConnections, maxConnections) || other.maxConnections == maxConnections)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.conflictPolicy, conflictPolicy) || other.conflictPolicy == conflictPolicy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,destination,maxConnections,priority,conflictPolicy);

@override
String toString() {
  return 'CreateDownloadRequest(url: $url, destination: $destination, maxConnections: $maxConnections, priority: $priority, conflictPolicy: $conflictPolicy)';
}


}

/// @nodoc
abstract mixin class $CreateDownloadRequestCopyWith<$Res>  {
  factory $CreateDownloadRequestCopyWith(CreateDownloadRequest value, $Res Function(CreateDownloadRequest) _then) = _$CreateDownloadRequestCopyWithImpl;
@useResult
$Res call({
 String url, String destination, int? maxConnections, int? priority, FileConflictPolicy? conflictPolicy
});




}
/// @nodoc
class _$CreateDownloadRequestCopyWithImpl<$Res>
    implements $CreateDownloadRequestCopyWith<$Res> {
  _$CreateDownloadRequestCopyWithImpl(this._self, this._then);

  final CreateDownloadRequest _self;
  final $Res Function(CreateDownloadRequest) _then;

/// Create a copy of CreateDownloadRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? destination = null,Object? maxConnections = freezed,Object? priority = freezed,Object? conflictPolicy = freezed,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,maxConnections: freezed == maxConnections ? _self.maxConnections : maxConnections // ignore: cast_nullable_to_non_nullable
as int?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int?,conflictPolicy: freezed == conflictPolicy ? _self.conflictPolicy : conflictPolicy // ignore: cast_nullable_to_non_nullable
as FileConflictPolicy?,
  ));
}

}


/// Adds pattern-matching-related methods to [CreateDownloadRequest].
extension CreateDownloadRequestPatterns on CreateDownloadRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CreateDownloadRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CreateDownloadRequest value)  $default,){
final _that = this;
switch (_that) {
case _CreateDownloadRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CreateDownloadRequest value)?  $default,){
final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy)  $default,) {final _that = this;
switch (_that) {
case _CreateDownloadRequest():
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy)?  $default,) {final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CreateDownloadRequest implements CreateDownloadRequest {
  const _CreateDownloadRequest({required this.url, required this.destination, this.maxConnections, this.priority, this.conflictPolicy});
  factory _CreateDownloadRequest.fromJson(Map<String, dynamic> json) => _$CreateDownloadRequestFromJson(json);

@override final  String url;
@override final  String destination;
@override final  int? maxConnections;
@override final  int? priority;
@override final  FileConflictPolicy? conflictPolicy;

/// Create a copy of CreateDownloadRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CreateDownloadRequestCopyWith<_CreateDownloadRequest> get copyWith => __$CreateDownloadRequestCopyWithImpl<_CreateDownloadRequest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CreateDownloadRequestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CreateDownloadRequest&&(identical(other.url, url) || other.url == url)&&(identical(other.destination, destination) || other.destination == destination)&&(identical(other.maxConnections, maxConnections) || other.maxConnections == maxConnections)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.conflictPolicy, conflictPolicy) || other.conflictPolicy == conflictPolicy));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,url,destination,maxConnections,priority,conflictPolicy);

@override
String toString() {
  return 'CreateDownloadRequest(url: $url, destination: $destination, maxConnections: $maxConnections, priority: $priority, conflictPolicy: $conflictPolicy)';
}


}

/// @nodoc
abstract mixin class _$CreateDownloadRequestCopyWith<$Res> implements $CreateDownloadRequestCopyWith<$Res> {
  factory _$CreateDownloadRequestCopyWith(_CreateDownloadRequest value, $Res Function(_CreateDownloadRequest) _then) = __$CreateDownloadRequestCopyWithImpl;
@override @useResult
$Res call({
 String url, String destination, int? maxConnections, int? priority, FileConflictPolicy? conflictPolicy
});




}
/// @nodoc
class __$CreateDownloadRequestCopyWithImpl<$Res>
    implements _$CreateDownloadRequestCopyWith<$Res> {
  __$CreateDownloadRequestCopyWithImpl(this._self, this._then);

  final _CreateDownloadRequest _self;
  final $Res Function(_CreateDownloadRequest) _then;

/// Create a copy of CreateDownloadRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? destination = null,Object? maxConnections = freezed,Object? priority = freezed,Object? conflictPolicy = freezed,}) {
  return _then(_CreateDownloadRequest(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,maxConnections: freezed == maxConnections ? _self.maxConnections : maxConnections // ignore: cast_nullable_to_non_nullable
as int?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int?,conflictPolicy: freezed == conflictPolicy ? _self.conflictPolicy : conflictPolicy // ignore: cast_nullable_to_non_nullable
as FileConflictPolicy?,
  ));
}


}

// dart format on
