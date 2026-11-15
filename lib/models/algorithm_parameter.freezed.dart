// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_parameter.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmParameter {

 String get name; String? get unit; dynamic get min; dynamic get max; dynamic get defaultValue; String? get scope; String? get description; List<String>? get enumValues; String? get type; String? get busIdRef; String? get channelCountRef; bool? get isPerChannel; bool? get isCommon;
/// Create a copy of AlgorithmParameter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmParameterCopyWith<AlgorithmParameter> get copyWith => _$AlgorithmParameterCopyWithImpl<AlgorithmParameter>(this as AlgorithmParameter, _$identity);

  /// Serializes this AlgorithmParameter to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmParameter;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmParameter&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.unit, _this.unit) || other.unit == _this.unit)&&const DeepCollectionEquality().equals(other.min, _this.min)&&const DeepCollectionEquality().equals(other.max, _this.max)&&const DeepCollectionEquality().equals(other.defaultValue, _this.defaultValue)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.enumValues, _this.enumValues)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.busIdRef, _this.busIdRef) || other.busIdRef == _this.busIdRef)&&(identical(other.channelCountRef, _this.channelCountRef) || other.channelCountRef == _this.channelCountRef)&&(identical(other.isPerChannel, _this.isPerChannel) || other.isPerChannel == _this.isPerChannel)&&(identical(other.isCommon, _this.isCommon) || other.isCommon == _this.isCommon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmParameter;
  return Object.hash(runtimeType,_this.name,_this.unit,const DeepCollectionEquality().hash(_this.min),const DeepCollectionEquality().hash(_this.max),const DeepCollectionEquality().hash(_this.defaultValue),_this.scope,_this.description,const DeepCollectionEquality().hash(_this.enumValues),_this.type,_this.busIdRef,_this.channelCountRef,_this.isPerChannel,_this.isCommon);
}

@override
String toString() {
  final _this = this as AlgorithmParameter;
  return 'AlgorithmParameter(name: ${_this.name}, unit: ${_this.unit}, min: ${_this.min}, max: ${_this.max}, defaultValue: ${_this.defaultValue}, scope: ${_this.scope}, description: ${_this.description}, enumValues: ${_this.enumValues}, type: ${_this.type}, busIdRef: ${_this.busIdRef}, channelCountRef: ${_this.channelCountRef}, isPerChannel: ${_this.isPerChannel}, isCommon: ${_this.isCommon})';
}


}

/// @nodoc
abstract mixin class $AlgorithmParameterCopyWith<$Res>  {
  factory $AlgorithmParameterCopyWith(AlgorithmParameter value, $Res Function(AlgorithmParameter) _then) = _$AlgorithmParameterCopyWithImpl;
@useResult
$Res call({
 String name, String? unit, dynamic min, dynamic max, dynamic defaultValue, String? scope, String? description, List<String>? enumValues, String? type, String? busIdRef, String? channelCountRef, bool? isPerChannel, bool? isCommon
});




}
/// @nodoc
class _$AlgorithmParameterCopyWithImpl<$Res>
    implements $AlgorithmParameterCopyWith<$Res> {
  _$AlgorithmParameterCopyWithImpl(this._self, this._then);

  final AlgorithmParameter _self;
  final $Res Function(AlgorithmParameter) _then;

/// Create a copy of AlgorithmParameter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? unit = freezed,Object? min = freezed,Object? max = freezed,Object? defaultValue = freezed,Object? scope = freezed,Object? description = freezed,Object? enumValues = freezed,Object? type = freezed,Object? busIdRef = freezed,Object? channelCountRef = freezed,Object? isPerChannel = freezed,Object? isCommon = freezed,}) {
  return _then(AlgorithmParameter(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as dynamic,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as dynamic,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue // ignore: cast_nullable_to_non_nullable
as dynamic,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,enumValues: freezed == enumValues ? _self.enumValues : enumValues // ignore: cast_nullable_to_non_nullable
as List<String>?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,busIdRef: freezed == busIdRef ? _self.busIdRef : busIdRef // ignore: cast_nullable_to_non_nullable
as String?,channelCountRef: freezed == channelCountRef ? _self.channelCountRef : channelCountRef // ignore: cast_nullable_to_non_nullable
as String?,isPerChannel: freezed == isPerChannel ? _self.isPerChannel : isPerChannel // ignore: cast_nullable_to_non_nullable
as bool?,isCommon: freezed == isCommon ? _self.isCommon : isCommon // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmParameter].
extension AlgorithmParameterPatterns on AlgorithmParameter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmParameter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmParameter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmParameter value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmParameter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmParameter value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmParameter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? unit,  dynamic min,  dynamic max,  dynamic defaultValue,  String? scope,  String? description,  List<String>? enumValues,  String? type,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel,  bool? isCommon)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmParameter() when $default != null:
return $default(_that.name,_that.unit,_that.min,_that.max,_that.defaultValue,_that.scope,_that.description,_that.enumValues,_that.type,_that.busIdRef,_that.channelCountRef,_that.isPerChannel,_that.isCommon);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? unit,  dynamic min,  dynamic max,  dynamic defaultValue,  String? scope,  String? description,  List<String>? enumValues,  String? type,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel,  bool? isCommon)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmParameter():
return $default(_that.name,_that.unit,_that.min,_that.max,_that.defaultValue,_that.scope,_that.description,_that.enumValues,_that.type,_that.busIdRef,_that.channelCountRef,_that.isPerChannel,_that.isCommon);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? unit,  dynamic min,  dynamic max,  dynamic defaultValue,  String? scope,  String? description,  List<String>? enumValues,  String? type,  String? busIdRef,  String? channelCountRef,  bool? isPerChannel,  bool? isCommon)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmParameter() when $default != null:
return $default(_that.name,_that.unit,_that.min,_that.max,_that.defaultValue,_that.scope,_that.description,_that.enumValues,_that.type,_that.busIdRef,_that.channelCountRef,_that.isPerChannel,_that.isCommon);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmParameter implements AlgorithmParameter {
  const _AlgorithmParameter({required this.name, this.unit, this.min, this.max, this.defaultValue, this.scope, this.description,  List<String>? enumValues, this.type, this.busIdRef, this.channelCountRef, this.isPerChannel, this.isCommon}): _enumValues = enumValues;
  factory _AlgorithmParameter.fromJson(Map<String, dynamic> json) => _$AlgorithmParameterFromJson(json);

@override final  String name;
@override final  String? unit;
@override final  dynamic min;
@override final  dynamic max;
@override final  dynamic defaultValue;
@override final  String? scope;
@override final  String? description;
 final  List<String>? _enumValues;
@override List<String>? get enumValues {
  final value = _enumValues;
  if (value == null) return null;
  if (_enumValues is EqualUnmodifiableListView) return _enumValues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  String? type;
@override final  String? busIdRef;
@override final  String? channelCountRef;
@override final  bool? isPerChannel;
@override final  bool? isCommon;

/// Create a copy of AlgorithmParameter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmParameterCopyWith<_AlgorithmParameter> get copyWith => __$AlgorithmParameterCopyWithImpl<_AlgorithmParameter>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmParameterToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmParameter&&(identical(other.name, name) || other.name == name)&&(identical(other.unit, unit) || other.unit == unit)&&const DeepCollectionEquality().equals(other.min, min)&&const DeepCollectionEquality().equals(other.max, max)&&const DeepCollectionEquality().equals(other.defaultValue, defaultValue)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.enumValues, _enumValues)&&(identical(other.type, type) || other.type == type)&&(identical(other.busIdRef, busIdRef) || other.busIdRef == busIdRef)&&(identical(other.channelCountRef, channelCountRef) || other.channelCountRef == channelCountRef)&&(identical(other.isPerChannel, isPerChannel) || other.isPerChannel == isPerChannel)&&(identical(other.isCommon, isCommon) || other.isCommon == isCommon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,unit,const DeepCollectionEquality().hash(min),const DeepCollectionEquality().hash(max),const DeepCollectionEquality().hash(defaultValue),scope,description,const DeepCollectionEquality().hash(_enumValues),type,busIdRef,channelCountRef,isPerChannel,isCommon);
}

@override
String toString() {
    return 'AlgorithmParameter(name: $name, unit: $unit, min: $min, max: $max, defaultValue: $defaultValue, scope: $scope, description: $description, enumValues: $enumValues, type: $type, busIdRef: $busIdRef, channelCountRef: $channelCountRef, isPerChannel: $isPerChannel, isCommon: $isCommon)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmParameterCopyWith<$Res> implements $AlgorithmParameterCopyWith<$Res> {
  factory _$AlgorithmParameterCopyWith(_AlgorithmParameter value, $Res Function(_AlgorithmParameter) _then) = __$AlgorithmParameterCopyWithImpl;
@override @useResult
$Res call({
 String name, String? unit, dynamic min, dynamic max, dynamic defaultValue, String? scope, String? description, List<String>? enumValues, String? type, String? busIdRef, String? channelCountRef, bool? isPerChannel, bool? isCommon
});




}
/// @nodoc
class __$AlgorithmParameterCopyWithImpl<$Res>
    implements _$AlgorithmParameterCopyWith<$Res> {
  __$AlgorithmParameterCopyWithImpl(this._self, this._then);

  final _AlgorithmParameter _self;
  final $Res Function(_AlgorithmParameter) _then;

/// Create a copy of AlgorithmParameter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? unit = freezed,Object? min = freezed,Object? max = freezed,Object? defaultValue = freezed,Object? scope = freezed,Object? description = freezed,Object? enumValues = freezed,Object? type = freezed,Object? busIdRef = freezed,Object? channelCountRef = freezed,Object? isPerChannel = freezed,Object? isCommon = freezed,}) {
  return _then(_AlgorithmParameter(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as dynamic,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as dynamic,defaultValue: freezed == defaultValue ? _self.defaultValue : defaultValue // ignore: cast_nullable_to_non_nullable
as dynamic,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,enumValues: freezed == enumValues ? _self._enumValues : enumValues // ignore: cast_nullable_to_non_nullable
as List<String>?,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,busIdRef: freezed == busIdRef ? _self.busIdRef : busIdRef // ignore: cast_nullable_to_non_nullable
as String?,channelCountRef: freezed == channelCountRef ? _self.channelCountRef : channelCountRef // ignore: cast_nullable_to_non_nullable
as String?,isPerChannel: freezed == isPerChannel ? _self.isPerChannel : isPerChannel // ignore: cast_nullable_to_non_nullable
as bool?,isCommon: freezed == isCommon ? _self.isCommon : isCommon // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
