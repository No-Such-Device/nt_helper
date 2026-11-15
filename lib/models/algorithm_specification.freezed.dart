// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_specification.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmSpecification {

 String get name; String? get unit; dynamic get value; String? get description; dynamic get min; dynamic get max;
/// Create a copy of AlgorithmSpecification
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmSpecificationCopyWith<AlgorithmSpecification> get copyWith => _$AlgorithmSpecificationCopyWithImpl<AlgorithmSpecification>(this as AlgorithmSpecification, _$identity);

  /// Serializes this AlgorithmSpecification to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmSpecification;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmSpecification&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.unit, _this.unit) || other.unit == _this.unit)&&const DeepCollectionEquality().equals(other.value, _this.value)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.min, _this.min)&&const DeepCollectionEquality().equals(other.max, _this.max));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmSpecification;
  return Object.hash(runtimeType,_this.name,_this.unit,const DeepCollectionEquality().hash(_this.value),_this.description,const DeepCollectionEquality().hash(_this.min),const DeepCollectionEquality().hash(_this.max));
}

@override
String toString() {
  final _this = this as AlgorithmSpecification;
  return 'AlgorithmSpecification(name: ${_this.name}, unit: ${_this.unit}, value: ${_this.value}, description: ${_this.description}, min: ${_this.min}, max: ${_this.max})';
}


}

/// @nodoc
abstract mixin class $AlgorithmSpecificationCopyWith<$Res>  {
  factory $AlgorithmSpecificationCopyWith(AlgorithmSpecification value, $Res Function(AlgorithmSpecification) _then) = _$AlgorithmSpecificationCopyWithImpl;
@useResult
$Res call({
 String name, String? unit, dynamic value, String? description, dynamic min, dynamic max
});




}
/// @nodoc
class _$AlgorithmSpecificationCopyWithImpl<$Res>
    implements $AlgorithmSpecificationCopyWith<$Res> {
  _$AlgorithmSpecificationCopyWithImpl(this._self, this._then);

  final AlgorithmSpecification _self;
  final $Res Function(AlgorithmSpecification) _then;

/// Create a copy of AlgorithmSpecification
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? unit = freezed,Object? value = freezed,Object? description = freezed,Object? min = freezed,Object? max = freezed,}) {
  return _then(AlgorithmSpecification(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as dynamic,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as dynamic,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmSpecification].
extension AlgorithmSpecificationPatterns on AlgorithmSpecification {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmSpecification value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmSpecification() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmSpecification value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmSpecification():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmSpecification value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmSpecification() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? unit,  dynamic value,  String? description,  dynamic min,  dynamic max)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmSpecification() when $default != null:
return $default(_that.name,_that.unit,_that.value,_that.description,_that.min,_that.max);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? unit,  dynamic value,  String? description,  dynamic min,  dynamic max)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmSpecification():
return $default(_that.name,_that.unit,_that.value,_that.description,_that.min,_that.max);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? unit,  dynamic value,  String? description,  dynamic min,  dynamic max)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmSpecification() when $default != null:
return $default(_that.name,_that.unit,_that.value,_that.description,_that.min,_that.max);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmSpecification implements AlgorithmSpecification {
  const _AlgorithmSpecification({required this.name, this.unit, this.value, this.description, this.min, this.max});
  factory _AlgorithmSpecification.fromJson(Map<String, dynamic> json) => _$AlgorithmSpecificationFromJson(json);

@override final  String name;
@override final  String? unit;
@override final  dynamic value;
@override final  String? description;
@override final  dynamic min;
@override final  dynamic max;

/// Create a copy of AlgorithmSpecification
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmSpecificationCopyWith<_AlgorithmSpecification> get copyWith => __$AlgorithmSpecificationCopyWithImpl<_AlgorithmSpecification>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmSpecificationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmSpecification&&(identical(other.name, name) || other.name == name)&&(identical(other.unit, unit) || other.unit == unit)&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.min, min)&&const DeepCollectionEquality().equals(other.max, max));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,unit,const DeepCollectionEquality().hash(value),description,const DeepCollectionEquality().hash(min),const DeepCollectionEquality().hash(max));
}

@override
String toString() {
    return 'AlgorithmSpecification(name: $name, unit: $unit, value: $value, description: $description, min: $min, max: $max)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmSpecificationCopyWith<$Res> implements $AlgorithmSpecificationCopyWith<$Res> {
  factory _$AlgorithmSpecificationCopyWith(_AlgorithmSpecification value, $Res Function(_AlgorithmSpecification) _then) = __$AlgorithmSpecificationCopyWithImpl;
@override @useResult
$Res call({
 String name, String? unit, dynamic value, String? description, dynamic min, dynamic max
});




}
/// @nodoc
class __$AlgorithmSpecificationCopyWithImpl<$Res>
    implements _$AlgorithmSpecificationCopyWith<$Res> {
  __$AlgorithmSpecificationCopyWithImpl(this._self, this._then);

  final _AlgorithmSpecification _self;
  final $Res Function(_AlgorithmSpecification) _then;

/// Create a copy of AlgorithmSpecification
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? unit = freezed,Object? value = freezed,Object? description = freezed,Object? min = freezed,Object? max = freezed,}) {
  return _then(_AlgorithmSpecification(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as dynamic,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,min: freezed == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as dynamic,max: freezed == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as dynamic,
  ));
}


}

// dart format on
