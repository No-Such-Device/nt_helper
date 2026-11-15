// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmPort {

 String? get id; String get name; String? get description; String? get busIdRef; String? get channelCountRef; bool? get isPerChannel;
/// Create a copy of AlgorithmPort
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmPortCopyWith<AlgorithmPort> get copyWith => _$AlgorithmPortCopyWithImpl<AlgorithmPort>(this as AlgorithmPort, _$identity);

  /// Serializes this AlgorithmPort to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmPort;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmPort&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.busIdRef, _this.busIdRef) || other.busIdRef == _this.busIdRef)&&(identical(other.channelCountRef, _this.channelCountRef) || other.channelCountRef == _this.channelCountRef)&&(identical(other.isPerChannel, _this.isPerChannel) || other.isPerChannel == _this.isPerChannel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmPort;
  return Object.hash(runtimeType,_this.id,_this.name,_this.description,_this.busIdRef,_this.channelCountRef,_this.isPerChannel);
}

@override
String toString() {
  final _this = this as AlgorithmPort;
  return 'AlgorithmPort(id: ${_this.id}, name: ${_this.name}, description: ${_this.description}, busIdRef: ${_this.busIdRef}, channelCountRef: ${_this.channelCountRef}, isPerChannel: ${_this.isPerChannel})';
}


}

/// @nodoc
abstract mixin class $AlgorithmPortCopyWith<$Res>  {
  factory $AlgorithmPortCopyWith(AlgorithmPort value, $Res Function(AlgorithmPort) _then) = _$AlgorithmPortCopyWithImpl;
@useResult
$Res call({
 String? id, String name, String? description, String? busIdRef, String? channelCountRef, bool? isPerChannel
});




}
/// @nodoc
class _$AlgorithmPortCopyWithImpl<$Res>
    implements $AlgorithmPortCopyWith<$Res> {
  _$AlgorithmPortCopyWithImpl(this._self, this._then);

  final AlgorithmPort _self;
  final $Res Function(AlgorithmPort) _then;

/// Create a copy of AlgorithmPort
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? name = null,Object? description = freezed,Object? busIdRef = freezed,Object? channelCountRef = freezed,Object? isPerChannel = freezed,}) {
  return _then(AlgorithmPort(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,busIdRef: freezed == busIdRef ? _self.busIdRef : busIdRef // ignore: cast_nullable_to_non_nullable
as String?,channelCountRef: freezed == channelCountRef ? _self.channelCountRef : channelCountRef // ignore: cast_nullable_to_non_nullable
as String?,isPerChannel: freezed == isPerChannel ? _self.isPerChannel : isPerChannel // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmPort].
extension AlgorithmPortPatterns on AlgorithmPort {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmPort value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmPort() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmPort value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmPort():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmPort value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmPort() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? id,  String name,  String? description,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmPort() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.busIdRef,_that.channelCountRef,_that.isPerChannel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? id,  String name,  String? description,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmPort():
return $default(_that.id,_that.name,_that.description,_that.busIdRef,_that.channelCountRef,_that.isPerChannel);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? id,  String name,  String? description,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmPort() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.busIdRef,_that.channelCountRef,_that.isPerChannel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmPort implements AlgorithmPort {
  const _AlgorithmPort({this.id, required this.name, this.description, this.busIdRef, this.channelCountRef, this.isPerChannel});
  factory _AlgorithmPort.fromJson(Map<String, dynamic> json) => _$AlgorithmPortFromJson(json);

@override final  String? id;
@override final  String name;
@override final  String? description;
@override final  String? busIdRef;
@override final  String? channelCountRef;
@override final  bool? isPerChannel;

/// Create a copy of AlgorithmPort
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmPortCopyWith<_AlgorithmPort> get copyWith => __$AlgorithmPortCopyWithImpl<_AlgorithmPort>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmPortToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmPort&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.busIdRef, busIdRef) || other.busIdRef == busIdRef)&&(identical(other.channelCountRef, channelCountRef) || other.channelCountRef == channelCountRef)&&(identical(other.isPerChannel, isPerChannel) || other.isPerChannel == isPerChannel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description,busIdRef,channelCountRef,isPerChannel);
}

@override
String toString() {
    return 'AlgorithmPort(id: $id, name: $name, description: $description, busIdRef: $busIdRef, channelCountRef: $channelCountRef, isPerChannel: $isPerChannel)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmPortCopyWith<$Res> implements $AlgorithmPortCopyWith<$Res> {
  factory _$AlgorithmPortCopyWith(_AlgorithmPort value, $Res Function(_AlgorithmPort) _then) = __$AlgorithmPortCopyWithImpl;
@override @useResult
$Res call({
 String? id, String name, String? description, String? busIdRef, String? channelCountRef, bool? isPerChannel
});




}
/// @nodoc
class __$AlgorithmPortCopyWithImpl<$Res>
    implements _$AlgorithmPortCopyWith<$Res> {
  __$AlgorithmPortCopyWithImpl(this._self, this._then);

  final _AlgorithmPort _self;
  final $Res Function(_AlgorithmPort) _then;

/// Create a copy of AlgorithmPort
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? name = null,Object? description = freezed,Object? busIdRef = freezed,Object? channelCountRef = freezed,Object? isPerChannel = freezed,}) {
  return _then(_AlgorithmPort(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,busIdRef: freezed == busIdRef ? _self.busIdRef : busIdRef // ignore: cast_nullable_to_non_nullable
as String?,channelCountRef: freezed == channelCountRef ? _self.channelCountRef : channelCountRef // ignore: cast_nullable_to_non_nullable
as String?,isPerChannel: freezed == isPerChannel ? _self.isPerChannel : isPerChannel // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
