// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'create_download_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CreateDownloadRequest {

 String get url; String get destination; int? get maxConnections; int? get priority; FileConflictPolicy? get conflictPolicy; bool get paused; String? get cookie; String? get referrer;
/// Create a copy of CreateDownloadRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CreateDownloadRequestCopyWith<CreateDownloadRequest> get copyWith => _$CreateDownloadRequestCopyWithImpl<CreateDownloadRequest>(this as CreateDownloadRequest, _$identity);

  /// Serializes this CreateDownloadRequest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CreateDownloadRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CreateDownloadRequest&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.destination, _this.destination) || other.destination == _this.destination)&&(identical(other.maxConnections, _this.maxConnections) || other.maxConnections == _this.maxConnections)&&(identical(other.priority, _this.priority) || other.priority == _this.priority)&&(identical(other.conflictPolicy, _this.conflictPolicy) || other.conflictPolicy == _this.conflictPolicy)&&(identical(other.paused, _this.paused) || other.paused == _this.paused)&&(identical(other.cookie, _this.cookie) || other.cookie == _this.cookie)&&(identical(other.referrer, _this.referrer) || other.referrer == _this.referrer));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CreateDownloadRequest;
  return Object.hash(runtimeType,_this.url,_this.destination,_this.maxConnections,_this.priority,_this.conflictPolicy,_this.paused,_this.cookie,_this.referrer);
}

@override
String toString() {
  final _this = this as CreateDownloadRequest;
  return 'CreateDownloadRequest(url: ${_this.url}, destination: ${_this.destination}, maxConnections: ${_this.maxConnections}, priority: ${_this.priority}, conflictPolicy: ${_this.conflictPolicy}, paused: ${_this.paused}, cookie: ${_this.cookie}, referrer: ${_this.referrer})';
}


}

/// @nodoc
abstract mixin class $CreateDownloadRequestCopyWith<$Res>  {
  factory $CreateDownloadRequestCopyWith(CreateDownloadRequest value, $Res Function(CreateDownloadRequest) _then) = _$CreateDownloadRequestCopyWithImpl;
@useResult
$Res call({
 String url, String destination, int? maxConnections, int? priority, FileConflictPolicy? conflictPolicy, bool paused, String? cookie, String? referrer
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
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? destination = null,Object? maxConnections = freezed,Object? priority = freezed,Object? conflictPolicy = freezed,Object? paused = null,Object? cookie = freezed,Object? referrer = freezed,}) {
  return _then(CreateDownloadRequest(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,maxConnections: freezed == maxConnections ? _self.maxConnections : maxConnections // ignore: cast_nullable_to_non_nullable
as int?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int?,conflictPolicy: freezed == conflictPolicy ? _self.conflictPolicy : conflictPolicy // ignore: cast_nullable_to_non_nullable
as FileConflictPolicy?,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,cookie: freezed == cookie ? _self.cookie : cookie // ignore: cast_nullable_to_non_nullable
as String?,referrer: freezed == referrer ? _self.referrer : referrer // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy,  bool paused,  String? cookie,  String? referrer)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy,_that.paused,_that.cookie,_that.referrer);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy,  bool paused,  String? cookie,  String? referrer)  $default,) {final _that = this;
switch (_that) {
case _CreateDownloadRequest():
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy,_that.paused,_that.cookie,_that.referrer);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String destination,  int? maxConnections,  int? priority,  FileConflictPolicy? conflictPolicy,  bool paused,  String? cookie,  String? referrer)?  $default,) {final _that = this;
switch (_that) {
case _CreateDownloadRequest() when $default != null:
return $default(_that.url,_that.destination,_that.maxConnections,_that.priority,_that.conflictPolicy,_that.paused,_that.cookie,_that.referrer);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CreateDownloadRequest implements CreateDownloadRequest {
  const _CreateDownloadRequest({required this.url, required this.destination, this.maxConnections, this.priority, this.conflictPolicy, this.paused = false, this.cookie, this.referrer});
  factory _CreateDownloadRequest.fromJson(Map<String, dynamic> json) => _$CreateDownloadRequestFromJson(json);

@override final  String url;
@override final  String destination;
@override final  int? maxConnections;
@override final  int? priority;
@override final  FileConflictPolicy? conflictPolicy;
@override@JsonKey() final  bool paused;
@override final  String? cookie;
@override final  String? referrer;

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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CreateDownloadRequest&&(identical(other.url, url) || other.url == url)&&(identical(other.destination, destination) || other.destination == destination)&&(identical(other.maxConnections, maxConnections) || other.maxConnections == maxConnections)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.conflictPolicy, conflictPolicy) || other.conflictPolicy == conflictPolicy)&&(identical(other.paused, paused) || other.paused == paused)&&(identical(other.cookie, cookie) || other.cookie == cookie)&&(identical(other.referrer, referrer) || other.referrer == referrer));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,destination,maxConnections,priority,conflictPolicy,paused,cookie,referrer);
}

@override
String toString() {
    return 'CreateDownloadRequest(url: $url, destination: $destination, maxConnections: $maxConnections, priority: $priority, conflictPolicy: $conflictPolicy, paused: $paused, cookie: $cookie, referrer: $referrer)';
}


}

/// @nodoc
abstract mixin class _$CreateDownloadRequestCopyWith<$Res> implements $CreateDownloadRequestCopyWith<$Res> {
  factory _$CreateDownloadRequestCopyWith(_CreateDownloadRequest value, $Res Function(_CreateDownloadRequest) _then) = __$CreateDownloadRequestCopyWithImpl;
@override @useResult
$Res call({
 String url, String destination, int? maxConnections, int? priority, FileConflictPolicy? conflictPolicy, bool paused, String? cookie, String? referrer
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
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? destination = null,Object? maxConnections = freezed,Object? priority = freezed,Object? conflictPolicy = freezed,Object? paused = null,Object? cookie = freezed,Object? referrer = freezed,}) {
  return _then(_CreateDownloadRequest(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,destination: null == destination ? _self.destination : destination // ignore: cast_nullable_to_non_nullable
as String,maxConnections: freezed == maxConnections ? _self.maxConnections : maxConnections // ignore: cast_nullable_to_non_nullable
as int?,priority: freezed == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int?,conflictPolicy: freezed == conflictPolicy ? _self.conflictPolicy : conflictPolicy // ignore: cast_nullable_to_non_nullable
as FileConflictPolicy?,paused: null == paused ? _self.paused : paused // ignore: cast_nullable_to_non_nullable
as bool,cookie: freezed == cookie ? _self.cookie : cookie // ignore: cast_nullable_to_non_nullable
as String?,referrer: freezed == referrer ? _self.referrer : referrer // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
