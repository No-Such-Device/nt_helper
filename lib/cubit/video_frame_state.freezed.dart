// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_frame_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoFrameState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoFrameState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VideoFrameState()';
}


}

/// @nodoc
class $VideoFrameStateCopyWith<$Res>  {
$VideoFrameStateCopyWith(VideoFrameState _, $Res Function(VideoFrameState) __);
}


/// Adds pattern-matching-related methods to [VideoFrameState].
extension VideoFrameStatePatterns on VideoFrameState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VideoFrameState value)?  $default,{TResult Function( _Initial value)?  initial,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VideoFrameState() when $default != null:
return $default(_that);case _Initial() when initial != null:
return initial(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VideoFrameState value)  $default,{required TResult Function( _Initial value)  initial,}){
final _that = this;
switch (_that) {
case _VideoFrameState():
return $default(_that);case _Initial():
return initial(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VideoFrameState value)?  $default,{TResult? Function( _Initial value)?  initial,}){
final _that = this;
switch (_that) {
case _VideoFrameState() when $default != null:
return $default(_that);case _Initial() when initial != null:
return initial(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Uint8List? frameData,  int frameCounter,  DateTime? lastFrameTime,  double fps)?  $default,{TResult Function()?  initial,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VideoFrameState() when $default != null:
return $default(_that.frameData,_that.frameCounter,_that.lastFrameTime,_that.fps);case _Initial() when initial != null:
return initial();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Uint8List? frameData,  int frameCounter,  DateTime? lastFrameTime,  double fps)  $default,{required TResult Function()  initial,}) {final _that = this;
switch (_that) {
case _VideoFrameState():
return $default(_that.frameData,_that.frameCounter,_that.lastFrameTime,_that.fps);case _Initial():
return initial();case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Uint8List? frameData,  int frameCounter,  DateTime? lastFrameTime,  double fps)?  $default,{TResult? Function()?  initial,}) {final _that = this;
switch (_that) {
case _VideoFrameState() when $default != null:
return $default(_that.frameData,_that.frameCounter,_that.lastFrameTime,_that.fps);case _Initial() when initial != null:
return initial();case _:
  return null;

}
}

}

/// @nodoc


class _VideoFrameState implements VideoFrameState {
  const _VideoFrameState({this.frameData, this.frameCounter = 0, this.lastFrameTime, this.fps = 0.0});


 final  Uint8List? frameData;
@JsonKey() final  int frameCounter;
 final  DateTime? lastFrameTime;
@JsonKey() final  double fps;

/// Create a copy of VideoFrameState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VideoFrameStateCopyWith<_VideoFrameState> get copyWith => __$VideoFrameStateCopyWithImpl<_VideoFrameState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _VideoFrameState&&const DeepCollectionEquality().equals(other.frameData, frameData)&&(identical(other.frameCounter, frameCounter) || other.frameCounter == frameCounter)&&(identical(other.lastFrameTime, lastFrameTime) || other.lastFrameTime == lastFrameTime)&&(identical(other.fps, fps) || other.fps == fps));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(frameData),frameCounter,lastFrameTime,fps);
}

@override
String toString() {
    return 'VideoFrameState(frameData: $frameData, frameCounter: $frameCounter, lastFrameTime: $lastFrameTime, fps: $fps)';
}


}

/// @nodoc
abstract mixin class _$VideoFrameStateCopyWith<$Res> implements $VideoFrameStateCopyWith<$Res> {
  factory _$VideoFrameStateCopyWith(_VideoFrameState value, $Res Function(_VideoFrameState) _then) = __$VideoFrameStateCopyWithImpl;
@useResult
$Res call({
 Uint8List? frameData, int frameCounter, DateTime? lastFrameTime, double fps
});




}
/// @nodoc
class __$VideoFrameStateCopyWithImpl<$Res>
    implements _$VideoFrameStateCopyWith<$Res> {
  __$VideoFrameStateCopyWithImpl(this._self, this._then);

  final _VideoFrameState _self;
  final $Res Function(_VideoFrameState) _then;

/// Create a copy of VideoFrameState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? frameData = freezed,Object? frameCounter = null,Object? lastFrameTime = freezed,Object? fps = null,}) {
  return _then(_VideoFrameState(
frameData: freezed == frameData ? _self.frameData : frameData // ignore: cast_nullable_to_non_nullable
as Uint8List?,frameCounter: null == frameCounter ? _self.frameCounter : frameCounter // ignore: cast_nullable_to_non_nullable
as int,lastFrameTime: freezed == lastFrameTime ? _self.lastFrameTime : lastFrameTime // ignore: cast_nullable_to_non_nullable
as DateTime?,fps: null == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class _Initial implements VideoFrameState {
  const _Initial();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Initial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VideoFrameState.initial()';
}


}




// dart format on
