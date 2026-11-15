// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'node_position.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NodePosition {

 int get algorithmIndex; double get x; double get y; double get width; double get height;
/// Create a copy of NodePosition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodePositionCopyWith<NodePosition> get copyWith => _$NodePositionCopyWithImpl<NodePosition>(this as NodePosition, _$identity);

  /// Serializes this NodePosition to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as NodePosition;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodePosition&&(identical(other.algorithmIndex, _this.algorithmIndex) || other.algorithmIndex == _this.algorithmIndex)&&(identical(other.x, _this.x) || other.x == _this.x)&&(identical(other.y, _this.y) || other.y == _this.y)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as NodePosition;
  return Object.hash(runtimeType,_this.algorithmIndex,_this.x,_this.y,_this.width,_this.height);
}

@override
String toString() {
  final _this = this as NodePosition;
  return 'NodePosition(algorithmIndex: ${_this.algorithmIndex}, x: ${_this.x}, y: ${_this.y}, width: ${_this.width}, height: ${_this.height})';
}


}

/// @nodoc
abstract mixin class $NodePositionCopyWith<$Res>  {
  factory $NodePositionCopyWith(NodePosition value, $Res Function(NodePosition) _then) = _$NodePositionCopyWithImpl;
@useResult
$Res call({
 int algorithmIndex, double x, double y, double width, double height
});




}
/// @nodoc
class _$NodePositionCopyWithImpl<$Res>
    implements $NodePositionCopyWith<$Res> {
  _$NodePositionCopyWithImpl(this._self, this._then);

  final NodePosition _self;
  final $Res Function(NodePosition) _then;

/// Create a copy of NodePosition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? algorithmIndex = null,Object? x = null,Object? y = null,Object? width = null,Object? height = null,}) {
  return _then(NodePosition(
algorithmIndex: null == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [NodePosition].
extension NodePositionPatterns on NodePosition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NodePosition value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NodePosition() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NodePosition value)  $default,){
final _that = this;
switch (_that) {
case _NodePosition():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NodePosition value)?  $default,){
final _that = this;
switch (_that) {
case _NodePosition() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int algorithmIndex,  double x,  double y,  double width,  double height)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NodePosition() when $default != null:
return $default(_that.algorithmIndex,_that.x,_that.y,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int algorithmIndex,  double x,  double y,  double width,  double height)  $default,) {final _that = this;
switch (_that) {
case _NodePosition():
return $default(_that.algorithmIndex,_that.x,_that.y,_that.width,_that.height);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int algorithmIndex,  double x,  double y,  double width,  double height)?  $default,) {final _that = this;
switch (_that) {
case _NodePosition() when $default != null:
return $default(_that.algorithmIndex,_that.x,_that.y,_that.width,_that.height);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NodePosition implements NodePosition {
  const _NodePosition({required this.algorithmIndex, required this.x, required this.y, this.width = 200.0, this.height = 100.0});
  factory _NodePosition.fromJson(Map<String, dynamic> json) => _$NodePositionFromJson(json);

@override final  int algorithmIndex;
@override final  double x;
@override final  double y;
@override@JsonKey() final  double width;
@override@JsonKey() final  double height;

/// Create a copy of NodePosition
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodePositionCopyWith<_NodePosition> get copyWith => __$NodePositionCopyWithImpl<_NodePosition>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NodePositionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodePosition&&(identical(other.algorithmIndex, algorithmIndex) || other.algorithmIndex == algorithmIndex)&&(identical(other.x, x) || other.x == x)&&(identical(other.y, y) || other.y == y)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,algorithmIndex,x,y,width,height);
}

@override
String toString() {
    return 'NodePosition(algorithmIndex: $algorithmIndex, x: $x, y: $y, width: $width, height: $height)';
}


}

/// @nodoc
abstract mixin class _$NodePositionCopyWith<$Res> implements $NodePositionCopyWith<$Res> {
  factory _$NodePositionCopyWith(_NodePosition value, $Res Function(_NodePosition) _then) = __$NodePositionCopyWithImpl;
@override @useResult
$Res call({
 int algorithmIndex, double x, double y, double width, double height
});




}
/// @nodoc
class __$NodePositionCopyWithImpl<$Res>
    implements _$NodePositionCopyWith<$Res> {
  __$NodePositionCopyWithImpl(this._self, this._then);

  final _NodePosition _self;
  final $Res Function(_NodePosition) _then;

/// Create a copy of NodePosition
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? algorithmIndex = null,Object? x = null,Object? y = null,Object? width = null,Object? height = null,}) {
  return _then(_NodePosition(
algorithmIndex: null == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int,x: null == x ? _self.x : x // ignore: cast_nullable_to_non_nullable
as double,y: null == y ? _self.y : y // ignore: cast_nullable_to_non_nullable
as double,width: null == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as double,height: null == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
