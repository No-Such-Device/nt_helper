// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'flash_progress.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FlashProgress {

 FlashStage get stage; int get percent; String get message; bool get isError; bool get isSandboxError;
/// Create a copy of FlashProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlashProgressCopyWith<FlashProgress> get copyWith => _$FlashProgressCopyWithImpl<FlashProgress>(this as FlashProgress, _$identity);

  /// Serializes this FlashProgress to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FlashProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlashProgress&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.percent, _this.percent) || other.percent == _this.percent)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.isError, _this.isError) || other.isError == _this.isError)&&(identical(other.isSandboxError, _this.isSandboxError) || other.isSandboxError == _this.isSandboxError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FlashProgress;
  return Object.hash(runtimeType,_this.stage,_this.percent,_this.message,_this.isError,_this.isSandboxError);
}

@override
String toString() {
  final _this = this as FlashProgress;
  return 'FlashProgress(stage: ${_this.stage}, percent: ${_this.percent}, message: ${_this.message}, isError: ${_this.isError}, isSandboxError: ${_this.isSandboxError})';
}


}

/// @nodoc
abstract mixin class $FlashProgressCopyWith<$Res>  {
  factory $FlashProgressCopyWith(FlashProgress value, $Res Function(FlashProgress) _then) = _$FlashProgressCopyWithImpl;
@useResult
$Res call({
 FlashStage stage, int percent, String message, bool isError, bool isSandboxError
});




}
/// @nodoc
class _$FlashProgressCopyWithImpl<$Res>
    implements $FlashProgressCopyWith<$Res> {
  _$FlashProgressCopyWithImpl(this._self, this._then);

  final FlashProgress _self;
  final $Res Function(FlashProgress) _then;

/// Create a copy of FlashProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stage = null,Object? percent = null,Object? message = null,Object? isError = null,Object? isSandboxError = null,}) {
  return _then(FlashProgress(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as FlashStage,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,isError: null == isError ? _self.isError : isError // ignore: cast_nullable_to_non_nullable
as bool,isSandboxError: null == isSandboxError ? _self.isSandboxError : isSandboxError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FlashProgress].
extension FlashProgressPatterns on FlashProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FlashProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FlashProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FlashProgress value)  $default,){
final _that = this;
switch (_that) {
case _FlashProgress():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FlashProgress value)?  $default,){
final _that = this;
switch (_that) {
case _FlashProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FlashStage stage,  int percent,  String message,  bool isError,  bool isSandboxError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FlashProgress() when $default != null:
return $default(_that.stage,_that.percent,_that.message,_that.isError,_that.isSandboxError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FlashStage stage,  int percent,  String message,  bool isError,  bool isSandboxError)  $default,) {final _that = this;
switch (_that) {
case _FlashProgress():
return $default(_that.stage,_that.percent,_that.message,_that.isError,_that.isSandboxError);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FlashStage stage,  int percent,  String message,  bool isError,  bool isSandboxError)?  $default,) {final _that = this;
switch (_that) {
case _FlashProgress() when $default != null:
return $default(_that.stage,_that.percent,_that.message,_that.isError,_that.isSandboxError);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FlashProgress implements FlashProgress {
  const _FlashProgress({required this.stage, required this.percent, required this.message, this.isError = false, this.isSandboxError = false});
  factory _FlashProgress.fromJson(Map<String, dynamic> json) => _$FlashProgressFromJson(json);

@override final  FlashStage stage;
@override final  int percent;
@override final  String message;
@override@JsonKey() final  bool isError;
@override@JsonKey() final  bool isSandboxError;

/// Create a copy of FlashProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FlashProgressCopyWith<_FlashProgress> get copyWith => __$FlashProgressCopyWithImpl<_FlashProgress>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FlashProgressToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FlashProgress&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.percent, percent) || other.percent == percent)&&(identical(other.message, message) || other.message == message)&&(identical(other.isError, isError) || other.isError == isError)&&(identical(other.isSandboxError, isSandboxError) || other.isSandboxError == isSandboxError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,stage,percent,message,isError,isSandboxError);
}

@override
String toString() {
    return 'FlashProgress(stage: $stage, percent: $percent, message: $message, isError: $isError, isSandboxError: $isSandboxError)';
}


}

/// @nodoc
abstract mixin class _$FlashProgressCopyWith<$Res> implements $FlashProgressCopyWith<$Res> {
  factory _$FlashProgressCopyWith(_FlashProgress value, $Res Function(_FlashProgress) _then) = __$FlashProgressCopyWithImpl;
@override @useResult
$Res call({
 FlashStage stage, int percent, String message, bool isError, bool isSandboxError
});




}
/// @nodoc
class __$FlashProgressCopyWithImpl<$Res>
    implements _$FlashProgressCopyWith<$Res> {
  __$FlashProgressCopyWithImpl(this._self, this._then);

  final _FlashProgress _self;
  final $Res Function(_FlashProgress) _then;

/// Create a copy of FlashProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stage = null,Object? percent = null,Object? message = null,Object? isError = null,Object? isSandboxError = null,}) {
  return _then(_FlashProgress(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as FlashStage,percent: null == percent ? _self.percent : percent // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,isError: null == isError ? _self.isError : isError // ignore: cast_nullable_to_non_nullable
as bool,isSandboxError: null == isSandboxError ? _self.isSandboxError : isSandboxError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
