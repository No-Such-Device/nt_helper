// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'video_stream_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$VideoStreamState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VideoStreamState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VideoStreamState()';
}


}

/// @nodoc
class $VideoStreamStateCopyWith<$Res>  {
$VideoStreamStateCopyWith(VideoStreamState _, $Res Function(VideoStreamState) __);
}


/// Adds pattern-matching-related methods to [VideoStreamState].
extension VideoStreamStatePatterns on VideoStreamState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Disconnected value)?  disconnected,TResult Function( _Connecting value)?  connecting,TResult Function( _Streaming value)?  streaming,TResult Function( _Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Disconnected() when disconnected != null:
return disconnected(_that);case _Connecting() when connecting != null:
return connecting(_that);case _Streaming() when streaming != null:
return streaming(_that);case _Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Disconnected value)  disconnected,required TResult Function( _Connecting value)  connecting,required TResult Function( _Streaming value)  streaming,required TResult Function( _Error value)  error,}){
final _that = this;
switch (_that) {
case _Disconnected():
return disconnected(_that);case _Connecting():
return connecting(_that);case _Streaming():
return streaming(_that);case _Error():
return error(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Disconnected value)?  disconnected,TResult? Function( _Connecting value)?  connecting,TResult? Function( _Streaming value)?  streaming,TResult? Function( _Error value)?  error,}){
final _that = this;
switch (_that) {
case _Disconnected() when disconnected != null:
return disconnected(_that);case _Connecting() when connecting != null:
return connecting(_that);case _Streaming() when streaming != null:
return streaming(_that);case _Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  connecting,TResult Function( Stream<dynamic> videoStream,  int width,  int height,  double fps)?  streaming,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Disconnected() when disconnected != null:
return disconnected();case _Connecting() when connecting != null:
return connecting();case _Streaming() when streaming != null:
return streaming(_that.videoStream,_that.width,_that.height,_that.fps);case _Error() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  connecting,required TResult Function( Stream<dynamic> videoStream,  int width,  int height,  double fps)  streaming,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case _Disconnected():
return disconnected();case _Connecting():
return connecting();case _Streaming():
return streaming(_that.videoStream,_that.width,_that.height,_that.fps);case _Error():
return error(_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  connecting,TResult? Function( Stream<dynamic> videoStream,  int width,  int height,  double fps)?  streaming,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case _Disconnected() when disconnected != null:
return disconnected();case _Connecting() when connecting != null:
return connecting();case _Streaming() when streaming != null:
return streaming(_that.videoStream,_that.width,_that.height,_that.fps);case _Error() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _Disconnected implements VideoStreamState {
  const _Disconnected();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Disconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VideoStreamState.disconnected()';
}


}




/// @nodoc


class _Connecting implements VideoStreamState {
  const _Connecting();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'VideoStreamState.connecting()';
}


}




/// @nodoc


class _Streaming implements VideoStreamState {
  const _Streaming({required this.videoStream, required this.width, required this.height, required this.fps});


 final  Stream<dynamic> videoStream;
 final  int width;
 final  int height;
 final  double fps;

/// Create a copy of VideoStreamState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StreamingCopyWith<_Streaming> get copyWith => __$StreamingCopyWithImpl<_Streaming>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Streaming&&(identical(other.videoStream, videoStream) || other.videoStream == videoStream)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height)&&(identical(other.fps, fps) || other.fps == fps));
}


@override
int get hashCode {
    return Object.hash(runtimeType,videoStream,width,height,fps);
}

@override
String toString() {
    return 'VideoStreamState.streaming(videoStream: $videoStream, width: $width, height: $height, fps: $fps)';
}


}

/// @nodoc
abstract mixin class _$StreamingCopyWith<$Res> implements $VideoStreamStateCopyWith<$Res> {
  factory _$StreamingCopyWith(_Streaming value, $Res Function(_Streaming) _then) = __$StreamingCopyWithImpl;
@useResult
$Res call({
 Stream<dynamic> videoStream, int width, int height, double fps
});




}
/// @nodoc
class __$StreamingCopyWithImpl<$Res>
    implements _$StreamingCopyWith<$Res> {
  __$StreamingCopyWithImpl(this._self, this._then);

  final _Streaming _self;
  final $Res Function(_Streaming) _then;

/// Create a copy of VideoStreamState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? videoStream = null,Object? width = null,Object? height = null,Object? fps = null,}) {
  return _then(_Streaming(
videoStream: null == videoStream ? _self.videoStream : videoStream // ignore: cast_nullable_to_non_nullable
as Stream<dynamic>,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int,fps: null == fps ? _self.fps : fps // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class _Error implements VideoStreamState {
  const _Error(this.message);


 final  String message;

/// Create a copy of VideoStreamState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ErrorCopyWith<_Error> get copyWith => __$ErrorCopyWithImpl<_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'VideoStreamState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class _$ErrorCopyWith<$Res> implements $VideoStreamStateCopyWith<$Res> {
  factory _$ErrorCopyWith(_Error value, $Res Function(_Error) _then) = __$ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class __$ErrorCopyWithImpl<$Res>
    implements _$ErrorCopyWith<$Res> {
  __$ErrorCopyWithImpl(this._self, this._then);

  final _Error _self;
  final $Res Function(_Error) _then;

/// Create a copy of VideoStreamState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(_Error(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
