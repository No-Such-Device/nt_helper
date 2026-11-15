// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmMetadata {

 String get guid; String get name; List<String> get categories; String get description;@JsonKey(name: 'short_description') String? get shortDescription;@JsonKey(name: 'gui_description') String? get guiDescription;@JsonKey(name: 'use_cases') List<String> get useCases; List<AlgorithmSpecification> get specifications;@JsonKey(fromJson: _parametersFromJson) List<AlgorithmParameter> get parameters; List<String> get features;@JsonKey(name: 'input_ports', fromJson: _portsFromJson) List<AlgorithmPort> get inputPorts;@JsonKey(name: 'output_ports', fromJson: _portsFromJson) List<AlgorithmPort> get outputPorts;
/// Create a copy of AlgorithmMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmMetadataCopyWith<AlgorithmMetadata> get copyWith => _$AlgorithmMetadataCopyWithImpl<AlgorithmMetadata>(this as AlgorithmMetadata, _$identity);

  /// Serializes this AlgorithmMetadata to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmMetadata;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmMetadata&&(identical(other.guid, _this.guid) || other.guid == _this.guid)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.categories, _this.categories)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.shortDescription, _this.shortDescription) || other.shortDescription == _this.shortDescription)&&(identical(other.guiDescription, _this.guiDescription) || other.guiDescription == _this.guiDescription)&&const DeepCollectionEquality().equals(other.useCases, _this.useCases)&&const DeepCollectionEquality().equals(other.specifications, _this.specifications)&&const DeepCollectionEquality().equals(other.parameters, _this.parameters)&&const DeepCollectionEquality().equals(other.features, _this.features)&&const DeepCollectionEquality().equals(other.inputPorts, _this.inputPorts)&&const DeepCollectionEquality().equals(other.outputPorts, _this.outputPorts));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmMetadata;
  return Object.hash(runtimeType,_this.guid,_this.name,const DeepCollectionEquality().hash(_this.categories),_this.description,_this.shortDescription,_this.guiDescription,const DeepCollectionEquality().hash(_this.useCases),const DeepCollectionEquality().hash(_this.specifications),const DeepCollectionEquality().hash(_this.parameters),const DeepCollectionEquality().hash(_this.features),const DeepCollectionEquality().hash(_this.inputPorts),const DeepCollectionEquality().hash(_this.outputPorts));
}

@override
String toString() {
  final _this = this as AlgorithmMetadata;
  return 'AlgorithmMetadata(guid: ${_this.guid}, name: ${_this.name}, categories: ${_this.categories}, description: ${_this.description}, shortDescription: ${_this.shortDescription}, guiDescription: ${_this.guiDescription}, useCases: ${_this.useCases}, specifications: ${_this.specifications}, parameters: ${_this.parameters}, features: ${_this.features}, inputPorts: ${_this.inputPorts}, outputPorts: ${_this.outputPorts})';
}


}

/// @nodoc
abstract mixin class $AlgorithmMetadataCopyWith<$Res>  {
  factory $AlgorithmMetadataCopyWith(AlgorithmMetadata value, $Res Function(AlgorithmMetadata) _then) = _$AlgorithmMetadataCopyWithImpl;
@useResult
$Res call({
 String guid, String name, List<String> categories, String description,@JsonKey(name: 'short_description') String? shortDescription,@JsonKey(name: 'gui_description') String? guiDescription,@JsonKey(name: 'use_cases') List<String> useCases, List<AlgorithmSpecification> specifications,@JsonKey(fromJson: _parametersFromJson) List<AlgorithmParameter> parameters, List<String> features,@JsonKey(name: 'input_ports', fromJson: _portsFromJson) List<AlgorithmPort> inputPorts,@JsonKey(name: 'output_ports', fromJson: _portsFromJson) List<AlgorithmPort> outputPorts
});




}
/// @nodoc
class _$AlgorithmMetadataCopyWithImpl<$Res>
    implements $AlgorithmMetadataCopyWith<$Res> {
  _$AlgorithmMetadataCopyWithImpl(this._self, this._then);

  final AlgorithmMetadata _self;
  final $Res Function(AlgorithmMetadata) _then;

/// Create a copy of AlgorithmMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? guid = null,Object? name = null,Object? categories = null,Object? description = null,Object? shortDescription = freezed,Object? guiDescription = freezed,Object? useCases = null,Object? specifications = null,Object? parameters = null,Object? features = null,Object? inputPorts = null,Object? outputPorts = null,}) {
  return _then(AlgorithmMetadata(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categories: null == categories ? _self.categories : categories // ignore: cast_nullable_to_non_nullable
as List<String>,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,shortDescription: freezed == shortDescription ? _self.shortDescription : shortDescription // ignore: cast_nullable_to_non_nullable
as String?,guiDescription: freezed == guiDescription ? _self.guiDescription : guiDescription // ignore: cast_nullable_to_non_nullable
as String?,useCases: null == useCases ? _self.useCases : useCases // ignore: cast_nullable_to_non_nullable
as List<String>,specifications: null == specifications ? _self.specifications : specifications // ignore: cast_nullable_to_non_nullable
as List<AlgorithmSpecification>,parameters: null == parameters ? _self.parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<AlgorithmParameter>,features: null == features ? _self.features : features // ignore: cast_nullable_to_non_nullable
as List<String>,inputPorts: null == inputPorts ? _self.inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<AlgorithmPort>,outputPorts: null == outputPorts ? _self.outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<AlgorithmPort>,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmMetadata].
extension AlgorithmMetadataPatterns on AlgorithmMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmMetadata value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String guid,  String name,  List<String> categories,  String description, @JsonKey(name: 'short_description')  String? shortDescription, @JsonKey(name: 'gui_description')  String? guiDescription, @JsonKey(name: 'use_cases')  List<String> useCases,  List<AlgorithmSpecification> specifications, @JsonKey(fromJson: _parametersFromJson)  List<AlgorithmParameter> parameters,  List<String> features, @JsonKey(name: 'input_ports', fromJson: _portsFromJson)  List<AlgorithmPort> inputPorts, @JsonKey(name: 'output_ports', fromJson: _portsFromJson)  List<AlgorithmPort> outputPorts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmMetadata() when $default != null:
return $default(_that.guid,_that.name,_that.categories,_that.description,_that.shortDescription,_that.guiDescription,_that.useCases,_that.specifications,_that.parameters,_that.features,_that.inputPorts,_that.outputPorts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String guid,  String name,  List<String> categories,  String description, @JsonKey(name: 'short_description')  String? shortDescription, @JsonKey(name: 'gui_description')  String? guiDescription, @JsonKey(name: 'use_cases')  List<String> useCases,  List<AlgorithmSpecification> specifications, @JsonKey(fromJson: _parametersFromJson)  List<AlgorithmParameter> parameters,  List<String> features, @JsonKey(name: 'input_ports', fromJson: _portsFromJson)  List<AlgorithmPort> inputPorts, @JsonKey(name: 'output_ports', fromJson: _portsFromJson)  List<AlgorithmPort> outputPorts)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmMetadata():
return $default(_that.guid,_that.name,_that.categories,_that.description,_that.shortDescription,_that.guiDescription,_that.useCases,_that.specifications,_that.parameters,_that.features,_that.inputPorts,_that.outputPorts);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String guid,  String name,  List<String> categories,  String description, @JsonKey(name: 'short_description')  String? shortDescription, @JsonKey(name: 'gui_description')  String? guiDescription, @JsonKey(name: 'use_cases')  List<String> useCases,  List<AlgorithmSpecification> specifications, @JsonKey(fromJson: _parametersFromJson)  List<AlgorithmParameter> parameters,  List<String> features, @JsonKey(name: 'input_ports', fromJson: _portsFromJson)  List<AlgorithmPort> inputPorts, @JsonKey(name: 'output_ports', fromJson: _portsFromJson)  List<AlgorithmPort> outputPorts)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmMetadata() when $default != null:
return $default(_that.guid,_that.name,_that.categories,_that.description,_that.shortDescription,_that.guiDescription,_that.useCases,_that.specifications,_that.parameters,_that.features,_that.inputPorts,_that.outputPorts);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmMetadata implements AlgorithmMetadata {
  const _AlgorithmMetadata({required this.guid, required this.name, required  List<String> categories, required this.description, @JsonKey(name: 'short_description') this.shortDescription, @JsonKey(name: 'gui_description') this.guiDescription, @JsonKey(name: 'use_cases')  List<String> useCases = const [],  List<AlgorithmSpecification> specifications = const [], @JsonKey(fromJson: _parametersFromJson)  List<AlgorithmParameter> parameters = const [],  List<String> features = const [], @JsonKey(name: 'input_ports', fromJson: _portsFromJson)  List<AlgorithmPort> inputPorts = const [], @JsonKey(name: 'output_ports', fromJson: _portsFromJson)  List<AlgorithmPort> outputPorts = const []}): _categories = categories,_useCases = useCases,_specifications = specifications,_parameters = parameters,_features = features,_inputPorts = inputPorts,_outputPorts = outputPorts;
  factory _AlgorithmMetadata.fromJson(Map<String, dynamic> json) => _$AlgorithmMetadataFromJson(json);

@override final  String guid;
@override final  String name;
 final  List<String> _categories;
@override List<String> get categories {
  if (_categories is EqualUnmodifiableListView) return _categories;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_categories);
}

@override final  String description;
@override@JsonKey(name: 'short_description') final  String? shortDescription;
@override@JsonKey(name: 'gui_description') final  String? guiDescription;
 final  List<String> _useCases;
@override@JsonKey(name: 'use_cases') List<String> get useCases {
  if (_useCases is EqualUnmodifiableListView) return _useCases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_useCases);
}

 final  List<AlgorithmSpecification> _specifications;
@override@JsonKey() List<AlgorithmSpecification> get specifications {
  if (_specifications is EqualUnmodifiableListView) return _specifications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_specifications);
}

 final  List<AlgorithmParameter> _parameters;
@override@JsonKey(fromJson: _parametersFromJson) List<AlgorithmParameter> get parameters {
  if (_parameters is EqualUnmodifiableListView) return _parameters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parameters);
}

 final  List<String> _features;
@override@JsonKey() List<String> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}

 final  List<AlgorithmPort> _inputPorts;
@override@JsonKey(name: 'input_ports', fromJson: _portsFromJson) List<AlgorithmPort> get inputPorts {
  if (_inputPorts is EqualUnmodifiableListView) return _inputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_inputPorts);
}

 final  List<AlgorithmPort> _outputPorts;
@override@JsonKey(name: 'output_ports', fromJson: _portsFromJson) List<AlgorithmPort> get outputPorts {
  if (_outputPorts is EqualUnmodifiableListView) return _outputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputPorts);
}


/// Create a copy of AlgorithmMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmMetadataCopyWith<_AlgorithmMetadata> get copyWith => __$AlgorithmMetadataCopyWithImpl<_AlgorithmMetadata>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmMetadataToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmMetadata&&(identical(other.guid, guid) || other.guid == guid)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.categories, _categories)&&(identical(other.description, description) || other.description == description)&&(identical(other.shortDescription, shortDescription) || other.shortDescription == shortDescription)&&(identical(other.guiDescription, guiDescription) || other.guiDescription == guiDescription)&&const DeepCollectionEquality().equals(other.useCases, _useCases)&&const DeepCollectionEquality().equals(other.specifications, _specifications)&&const DeepCollectionEquality().equals(other.parameters, _parameters)&&const DeepCollectionEquality().equals(other.features, _features)&&const DeepCollectionEquality().equals(other.inputPorts, _inputPorts)&&const DeepCollectionEquality().equals(other.outputPorts, _outputPorts));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,guid,name,const DeepCollectionEquality().hash(_categories),description,shortDescription,guiDescription,const DeepCollectionEquality().hash(_useCases),const DeepCollectionEquality().hash(_specifications),const DeepCollectionEquality().hash(_parameters),const DeepCollectionEquality().hash(_features),const DeepCollectionEquality().hash(_inputPorts),const DeepCollectionEquality().hash(_outputPorts));
}

@override
String toString() {
    return 'AlgorithmMetadata(guid: $guid, name: $name, categories: $categories, description: $description, shortDescription: $shortDescription, guiDescription: $guiDescription, useCases: $useCases, specifications: $specifications, parameters: $parameters, features: $features, inputPorts: $inputPorts, outputPorts: $outputPorts)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmMetadataCopyWith<$Res> implements $AlgorithmMetadataCopyWith<$Res> {
  factory _$AlgorithmMetadataCopyWith(_AlgorithmMetadata value, $Res Function(_AlgorithmMetadata) _then) = __$AlgorithmMetadataCopyWithImpl;
@override @useResult
$Res call({
 String guid, String name, List<String> categories, String description,@JsonKey(name: 'short_description') String? shortDescription,@JsonKey(name: 'gui_description') String? guiDescription,@JsonKey(name: 'use_cases') List<String> useCases, List<AlgorithmSpecification> specifications,@JsonKey(fromJson: _parametersFromJson) List<AlgorithmParameter> parameters, List<String> features,@JsonKey(name: 'input_ports', fromJson: _portsFromJson) List<AlgorithmPort> inputPorts,@JsonKey(name: 'output_ports', fromJson: _portsFromJson) List<AlgorithmPort> outputPorts
});




}
/// @nodoc
class __$AlgorithmMetadataCopyWithImpl<$Res>
    implements _$AlgorithmMetadataCopyWith<$Res> {
  __$AlgorithmMetadataCopyWithImpl(this._self, this._then);

  final _AlgorithmMetadata _self;
  final $Res Function(_AlgorithmMetadata) _then;

/// Create a copy of AlgorithmMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? guid = null,Object? name = null,Object? categories = null,Object? description = null,Object? shortDescription = freezed,Object? guiDescription = freezed,Object? useCases = null,Object? specifications = null,Object? parameters = null,Object? features = null,Object? inputPorts = null,Object? outputPorts = null,}) {
  return _then(_AlgorithmMetadata(
guid: null == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,categories: null == categories ? _self._categories : categories // ignore: cast_nullable_to_non_nullable
as List<String>,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,shortDescription: freezed == shortDescription ? _self.shortDescription : shortDescription // ignore: cast_nullable_to_non_nullable
as String?,guiDescription: freezed == guiDescription ? _self.guiDescription : guiDescription // ignore: cast_nullable_to_non_nullable
as String?,useCases: null == useCases ? _self._useCases : useCases // ignore: cast_nullable_to_non_nullable
as List<String>,specifications: null == specifications ? _self._specifications : specifications // ignore: cast_nullable_to_non_nullable
as List<AlgorithmSpecification>,parameters: null == parameters ? _self._parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<AlgorithmParameter>,features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<String>,inputPorts: null == inputPorts ? _self._inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<AlgorithmPort>,outputPorts: null == outputPorts ? _self._outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<AlgorithmPort>,
  ));
}


}

// dart format on
