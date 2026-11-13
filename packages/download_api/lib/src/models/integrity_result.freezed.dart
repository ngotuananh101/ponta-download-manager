// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'integrity_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
IntegrityResult _$IntegrityResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'ok':
          return IntegrityOk.fromJson(
            json
          );
                case 'unknownSize':
          return IntegrityUnknownSize.fromJson(
            json
          );
                case 'missing':
          return IntegrityMissing.fromJson(
            json
          );
                case 'sizeMismatch':
          return IntegritySizeMismatch.fromJson(
            json
          );
                case 'checksumMismatch':
          return IntegrityChecksumMismatch.fromJson(
            json
          );
                case 'unreadable':
          return IntegrityUnreadable.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'IntegrityResult',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$IntegrityResult {



  /// Serializes this IntegrityResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'IntegrityResult()';
}


}

/// @nodoc
class $IntegrityResultCopyWith<$Res>  {
$IntegrityResultCopyWith(IntegrityResult _, $Res Function(IntegrityResult) __);
}


/// Adds pattern-matching-related methods to [IntegrityResult].
extension IntegrityResultPatterns on IntegrityResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IntegrityOk value)?  ok,TResult Function( IntegrityUnknownSize value)?  unknownSize,TResult Function( IntegrityMissing value)?  missing,TResult Function( IntegritySizeMismatch value)?  sizeMismatch,TResult Function( IntegrityChecksumMismatch value)?  checksumMismatch,TResult Function( IntegrityUnreadable value)?  unreadable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IntegrityOk() when ok != null:
return ok(_that);case IntegrityUnknownSize() when unknownSize != null:
return unknownSize(_that);case IntegrityMissing() when missing != null:
return missing(_that);case IntegritySizeMismatch() when sizeMismatch != null:
return sizeMismatch(_that);case IntegrityChecksumMismatch() when checksumMismatch != null:
return checksumMismatch(_that);case IntegrityUnreadable() when unreadable != null:
return unreadable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IntegrityOk value)  ok,required TResult Function( IntegrityUnknownSize value)  unknownSize,required TResult Function( IntegrityMissing value)  missing,required TResult Function( IntegritySizeMismatch value)  sizeMismatch,required TResult Function( IntegrityChecksumMismatch value)  checksumMismatch,required TResult Function( IntegrityUnreadable value)  unreadable,}){
final _that = this;
switch (_that) {
case IntegrityOk():
return ok(_that);case IntegrityUnknownSize():
return unknownSize(_that);case IntegrityMissing():
return missing(_that);case IntegritySizeMismatch():
return sizeMismatch(_that);case IntegrityChecksumMismatch():
return checksumMismatch(_that);case IntegrityUnreadable():
return unreadable(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IntegrityOk value)?  ok,TResult? Function( IntegrityUnknownSize value)?  unknownSize,TResult? Function( IntegrityMissing value)?  missing,TResult? Function( IntegritySizeMismatch value)?  sizeMismatch,TResult? Function( IntegrityChecksumMismatch value)?  checksumMismatch,TResult? Function( IntegrityUnreadable value)?  unreadable,}){
final _that = this;
switch (_that) {
case IntegrityOk() when ok != null:
return ok(_that);case IntegrityUnknownSize() when unknownSize != null:
return unknownSize(_that);case IntegrityMissing() when missing != null:
return missing(_that);case IntegritySizeMismatch() when sizeMismatch != null:
return sizeMismatch(_that);case IntegrityChecksumMismatch() when checksumMismatch != null:
return checksumMismatch(_that);case IntegrityUnreadable() when unreadable != null:
return unreadable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int bytes)?  ok,TResult Function( int bytes)?  unknownSize,TResult Function()?  missing,TResult Function( int expectedBytes,  int actualBytes)?  sizeMismatch,TResult Function( String expectedSha256,  String actualSha256)?  checksumMismatch,TResult Function( String message)?  unreadable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IntegrityOk() when ok != null:
return ok(_that.bytes);case IntegrityUnknownSize() when unknownSize != null:
return unknownSize(_that.bytes);case IntegrityMissing() when missing != null:
return missing();case IntegritySizeMismatch() when sizeMismatch != null:
return sizeMismatch(_that.expectedBytes,_that.actualBytes);case IntegrityChecksumMismatch() when checksumMismatch != null:
return checksumMismatch(_that.expectedSha256,_that.actualSha256);case IntegrityUnreadable() when unreadable != null:
return unreadable(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int bytes)  ok,required TResult Function( int bytes)  unknownSize,required TResult Function()  missing,required TResult Function( int expectedBytes,  int actualBytes)  sizeMismatch,required TResult Function( String expectedSha256,  String actualSha256)  checksumMismatch,required TResult Function( String message)  unreadable,}) {final _that = this;
switch (_that) {
case IntegrityOk():
return ok(_that.bytes);case IntegrityUnknownSize():
return unknownSize(_that.bytes);case IntegrityMissing():
return missing();case IntegritySizeMismatch():
return sizeMismatch(_that.expectedBytes,_that.actualBytes);case IntegrityChecksumMismatch():
return checksumMismatch(_that.expectedSha256,_that.actualSha256);case IntegrityUnreadable():
return unreadable(_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int bytes)?  ok,TResult? Function( int bytes)?  unknownSize,TResult? Function()?  missing,TResult? Function( int expectedBytes,  int actualBytes)?  sizeMismatch,TResult? Function( String expectedSha256,  String actualSha256)?  checksumMismatch,TResult? Function( String message)?  unreadable,}) {final _that = this;
switch (_that) {
case IntegrityOk() when ok != null:
return ok(_that.bytes);case IntegrityUnknownSize() when unknownSize != null:
return unknownSize(_that.bytes);case IntegrityMissing() when missing != null:
return missing();case IntegritySizeMismatch() when sizeMismatch != null:
return sizeMismatch(_that.expectedBytes,_that.actualBytes);case IntegrityChecksumMismatch() when checksumMismatch != null:
return checksumMismatch(_that.expectedSha256,_that.actualSha256);case IntegrityUnreadable() when unreadable != null:
return unreadable(_that.message);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class IntegrityOk implements IntegrityResult {
  const IntegrityOk({required this.bytes,  String? $type}): $type = $type ?? 'ok';
  factory IntegrityOk.fromJson(Map<String, dynamic> json) => _$IntegrityOkFromJson(json);

 final  int bytes;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntegrityOkCopyWith<IntegrityOk> get copyWith => _$IntegrityOkCopyWithImpl<IntegrityOk>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IntegrityOkToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityOk&&(identical(other.bytes, bytes) || other.bytes == bytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,bytes);
}

@override
String toString() {
    return 'IntegrityResult.ok(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $IntegrityOkCopyWith<$Res> implements $IntegrityResultCopyWith<$Res> {
  factory $IntegrityOkCopyWith(IntegrityOk value, $Res Function(IntegrityOk) _then) = _$IntegrityOkCopyWithImpl;
@useResult
$Res call({
 int bytes
});




}
/// @nodoc
class _$IntegrityOkCopyWithImpl<$Res>
    implements $IntegrityOkCopyWith<$Res> {
  _$IntegrityOkCopyWithImpl(this._self, this._then);

  final IntegrityOk _self;
  final $Res Function(IntegrityOk) _then;

/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(IntegrityOk(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class IntegrityUnknownSize implements IntegrityResult {
  const IntegrityUnknownSize({required this.bytes,  String? $type}): $type = $type ?? 'unknownSize';
  factory IntegrityUnknownSize.fromJson(Map<String, dynamic> json) => _$IntegrityUnknownSizeFromJson(json);

 final  int bytes;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntegrityUnknownSizeCopyWith<IntegrityUnknownSize> get copyWith => _$IntegrityUnknownSizeCopyWithImpl<IntegrityUnknownSize>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IntegrityUnknownSizeToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityUnknownSize&&(identical(other.bytes, bytes) || other.bytes == bytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,bytes);
}

@override
String toString() {
    return 'IntegrityResult.unknownSize(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $IntegrityUnknownSizeCopyWith<$Res> implements $IntegrityResultCopyWith<$Res> {
  factory $IntegrityUnknownSizeCopyWith(IntegrityUnknownSize value, $Res Function(IntegrityUnknownSize) _then) = _$IntegrityUnknownSizeCopyWithImpl;
@useResult
$Res call({
 int bytes
});




}
/// @nodoc
class _$IntegrityUnknownSizeCopyWithImpl<$Res>
    implements $IntegrityUnknownSizeCopyWith<$Res> {
  _$IntegrityUnknownSizeCopyWithImpl(this._self, this._then);

  final IntegrityUnknownSize _self;
  final $Res Function(IntegrityUnknownSize) _then;

/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(IntegrityUnknownSize(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class IntegrityMissing implements IntegrityResult {
  const IntegrityMissing({ String? $type}): $type = $type ?? 'missing';
  factory IntegrityMissing.fromJson(Map<String, dynamic> json) => _$IntegrityMissingFromJson(json);



@JsonKey(name: 'runtimeType')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$IntegrityMissingToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityMissing);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'IntegrityResult.missing()';
}


}




/// @nodoc
@JsonSerializable()

class IntegritySizeMismatch implements IntegrityResult {
  const IntegritySizeMismatch({required this.expectedBytes, required this.actualBytes,  String? $type}): $type = $type ?? 'sizeMismatch';
  factory IntegritySizeMismatch.fromJson(Map<String, dynamic> json) => _$IntegritySizeMismatchFromJson(json);

 final  int expectedBytes;
 final  int actualBytes;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntegritySizeMismatchCopyWith<IntegritySizeMismatch> get copyWith => _$IntegritySizeMismatchCopyWithImpl<IntegritySizeMismatch>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IntegritySizeMismatchToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegritySizeMismatch&&(identical(other.expectedBytes, expectedBytes) || other.expectedBytes == expectedBytes)&&(identical(other.actualBytes, actualBytes) || other.actualBytes == actualBytes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,expectedBytes,actualBytes);
}

@override
String toString() {
    return 'IntegrityResult.sizeMismatch(expectedBytes: $expectedBytes, actualBytes: $actualBytes)';
}


}

/// @nodoc
abstract mixin class $IntegritySizeMismatchCopyWith<$Res> implements $IntegrityResultCopyWith<$Res> {
  factory $IntegritySizeMismatchCopyWith(IntegritySizeMismatch value, $Res Function(IntegritySizeMismatch) _then) = _$IntegritySizeMismatchCopyWithImpl;
@useResult
$Res call({
 int expectedBytes, int actualBytes
});




}
/// @nodoc
class _$IntegritySizeMismatchCopyWithImpl<$Res>
    implements $IntegritySizeMismatchCopyWith<$Res> {
  _$IntegritySizeMismatchCopyWithImpl(this._self, this._then);

  final IntegritySizeMismatch _self;
  final $Res Function(IntegritySizeMismatch) _then;

/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expectedBytes = null,Object? actualBytes = null,}) {
  return _then(IntegritySizeMismatch(
expectedBytes: null == expectedBytes ? _self.expectedBytes : expectedBytes // ignore: cast_nullable_to_non_nullable
as int,actualBytes: null == actualBytes ? _self.actualBytes : actualBytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class IntegrityChecksumMismatch implements IntegrityResult {
  const IntegrityChecksumMismatch({required this.expectedSha256, required this.actualSha256,  String? $type}): $type = $type ?? 'checksumMismatch';
  factory IntegrityChecksumMismatch.fromJson(Map<String, dynamic> json) => _$IntegrityChecksumMismatchFromJson(json);

 final  String expectedSha256;
 final  String actualSha256;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntegrityChecksumMismatchCopyWith<IntegrityChecksumMismatch> get copyWith => _$IntegrityChecksumMismatchCopyWithImpl<IntegrityChecksumMismatch>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IntegrityChecksumMismatchToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityChecksumMismatch&&(identical(other.expectedSha256, expectedSha256) || other.expectedSha256 == expectedSha256)&&(identical(other.actualSha256, actualSha256) || other.actualSha256 == actualSha256));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,expectedSha256,actualSha256);
}

@override
String toString() {
    return 'IntegrityResult.checksumMismatch(expectedSha256: $expectedSha256, actualSha256: $actualSha256)';
}


}

/// @nodoc
abstract mixin class $IntegrityChecksumMismatchCopyWith<$Res> implements $IntegrityResultCopyWith<$Res> {
  factory $IntegrityChecksumMismatchCopyWith(IntegrityChecksumMismatch value, $Res Function(IntegrityChecksumMismatch) _then) = _$IntegrityChecksumMismatchCopyWithImpl;
@useResult
$Res call({
 String expectedSha256, String actualSha256
});




}
/// @nodoc
class _$IntegrityChecksumMismatchCopyWithImpl<$Res>
    implements $IntegrityChecksumMismatchCopyWith<$Res> {
  _$IntegrityChecksumMismatchCopyWithImpl(this._self, this._then);

  final IntegrityChecksumMismatch _self;
  final $Res Function(IntegrityChecksumMismatch) _then;

/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expectedSha256 = null,Object? actualSha256 = null,}) {
  return _then(IntegrityChecksumMismatch(
expectedSha256: null == expectedSha256 ? _self.expectedSha256 : expectedSha256 // ignore: cast_nullable_to_non_nullable
as String,actualSha256: null == actualSha256 ? _self.actualSha256 : actualSha256 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class IntegrityUnreadable implements IntegrityResult {
  const IntegrityUnreadable({required this.message,  String? $type}): $type = $type ?? 'unreadable';
  factory IntegrityUnreadable.fromJson(Map<String, dynamic> json) => _$IntegrityUnreadableFromJson(json);

 final  String message;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntegrityUnreadableCopyWith<IntegrityUnreadable> get copyWith => _$IntegrityUnreadableCopyWithImpl<IntegrityUnreadable>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$IntegrityUnreadableToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IntegrityUnreadable&&(identical(other.message, message) || other.message == message));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'IntegrityResult.unreadable(message: $message)';
}


}

/// @nodoc
abstract mixin class $IntegrityUnreadableCopyWith<$Res> implements $IntegrityResultCopyWith<$Res> {
  factory $IntegrityUnreadableCopyWith(IntegrityUnreadable value, $Res Function(IntegrityUnreadable) _then) = _$IntegrityUnreadableCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$IntegrityUnreadableCopyWithImpl<$Res>
    implements $IntegrityUnreadableCopyWith<$Res> {
  _$IntegrityUnreadableCopyWithImpl(this._self, this._then);

  final IntegrityUnreadable _self;
  final $Res Function(IntegrityUnreadable) _then;

/// Create a copy of IntegrityResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(IntegrityUnreadable(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
