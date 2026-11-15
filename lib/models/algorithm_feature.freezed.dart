// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_feature.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmFeature {

 String get guid; String get name; String? get description; List<AlgorithmParameter> get parameters;
/// Create a copy of AlgorithmFeature
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmFeatureCopyWith<AlgorithmFeature> get copyWith => _$AlgorithmFeatureCopyWithImpl<AlgorithmFeature>(this as AlgorithmFeature, _$identity);

  /// Serializes this AlgorithmFeature to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmFeature;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmFeature&&(identical(other.guid, _this.guid) || other.guid == _this.guid)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.parameters, _this.parameters));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmFeature;
  return Object.hash(runtimeType,_this.guid,_this.name,_this.description,const DeepCollectionEquality().hash(_this.parameters));
}

@override
String toString() {
  final _this = this as AlgorithmFeature;
  return 'AlgorithmFeature(guid: ${_this.guid}, name: ${_this.name}, description: ${_this.description}, parameters: ${_this.parameters})';
}


}

/// @nodoc
abstract mixin class $AlgorithmFeatureCopyWith<$Res>  {
  factory $AlgorithmFeatureCopyWith(AlgorithmFeature value, $Res Function(AlgorithmFeature) _then) = _$AlgorithmFeatureCopyWithImpl;
@useResult
$Res call({
 String guid, String name, String? description, List<AlgorithmParameter> parameters
});




}
/// @nodoc
class _$AlgorithmFeatureCopyWithImpl<$Res>
    implements $AlgorithmFeatureCopyWith<$Res> {
  _$AlgorithmFeatureCopyWithImpl(this._self, this._then);

  final AlgorithmFeature _self;
  final $Res Function(AlgorithmFeature) _then;

/// Create a copy of AlgorithmFeature
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? guid = null,Object? name = null,Object? description = freezed,Object? parameters = null,}) {
  return _then(AlgorithmFeature(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,parameters: null == parameters ? _self.parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<AlgorithmParameter>,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmFeature].
extension AlgorithmFeaturePatterns on AlgorithmFeature {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmFeature value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmFeature() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmFeature value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmFeature():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmFeature value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmFeature() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String guid,  String name,  String? description,  List<AlgorithmParameter> parameters)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmFeature() when $default != null:
return $default(_that.guid,_that.name,_that.description,_that.parameters);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String guid,  String name,  String? description,  List<AlgorithmParameter> parameters)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmFeature():
return $default(_that.guid,_that.name,_that.description,_that.parameters);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String guid,  String name,  String? description,  List<AlgorithmParameter> parameters)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmFeature() when $default != null:
return $default(_that.guid,_that.name,_that.description,_that.parameters);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmFeature implements AlgorithmFeature {
  const _AlgorithmFeature({required this.guid, required this.name, this.description,  List<AlgorithmParameter> parameters = const []}): _parameters = parameters;
  factory _AlgorithmFeature.fromJson(Map<String, dynamic> json) => _$AlgorithmFeatureFromJson(json);

@override final  String guid;
@override final  String name;
@override final  String? description;
 final  List<AlgorithmParameter> _parameters;
@override@JsonKey() List<AlgorithmParameter> get parameters {
  if (_parameters is EqualUnmodifiableListView) return _parameters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parameters);
}


/// Create a copy of AlgorithmFeature
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmFeatureCopyWith<_AlgorithmFeature> get copyWith => __$AlgorithmFeatureCopyWithImpl<_AlgorithmFeature>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmFeatureToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmFeature&&(identical(other.guid, guid) || other.guid == guid)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.parameters, _parameters));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,guid,name,description,const DeepCollectionEquality().hash(_parameters));
}

@override
String toString() {
    return 'AlgorithmFeature(guid: $guid, name: $name, description: $description, parameters: $parameters)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmFeatureCopyWith<$Res> implements $AlgorithmFeatureCopyWith<$Res> {
  factory _$AlgorithmFeatureCopyWith(_AlgorithmFeature value, $Res Function(_AlgorithmFeature) _then) = __$AlgorithmFeatureCopyWithImpl;
@override @useResult
$Res call({
 String guid, String name, String? description, List<AlgorithmParameter> parameters
});




}
/// @nodoc
class __$AlgorithmFeatureCopyWithImpl<$Res>
    implements _$AlgorithmFeatureCopyWith<$Res> {
  __$AlgorithmFeatureCopyWithImpl(this._self, this._then);

  final _AlgorithmFeature _self;
  final $Res Function(_AlgorithmFeature) _then;

/// Create a copy of AlgorithmFeature
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? guid = null,Object? name = null,Object? description = freezed,Object? parameters = null,}) {
  return _then(_AlgorithmFeature(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,parameters: null == parameters ? _self._parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<AlgorithmParameter>,
  ));
}


}

// dart format on
