// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'disting_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Slot implements DiagnosticableTreeMixin {

 Algorithm get algorithm; RoutingInfo get routing; ParameterPages get pages; List<ParameterInfo> get parameters; List<ParameterValue> get values; List<ParameterEnumStrings> get enums; List<Mapping> get mappings; List<ParameterValueString> get valueStrings;/// Output mode usage map: parameter number -> list of affected parameter numbers
/// Populated from SysEx 0x55 responses (Story 7.4)
 Map<int, List<int>> get outputModeMap;
/// Create a copy of Slot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SlotCopyWith<Slot> get copyWith => _$SlotCopyWithImpl<Slot>(this as Slot, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'Slot'))
    ..add(DiagnosticsProperty('algorithm', algorithm))..add(DiagnosticsProperty('routing', routing))..add(DiagnosticsProperty('pages', pages))..add(DiagnosticsProperty('parameters', parameters))..add(DiagnosticsProperty('values', values))..add(DiagnosticsProperty('enums', enums))..add(DiagnosticsProperty('mappings', mappings))..add(DiagnosticsProperty('valueStrings', valueStrings))..add(DiagnosticsProperty('outputModeMap', outputModeMap));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Slot&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm)&&(identical(other.routing, routing) || other.routing == routing)&&(identical(other.pages, pages) || other.pages == pages)&&const DeepCollectionEquality().equals(other.parameters, parameters)&&const DeepCollectionEquality().equals(other.values, values)&&const DeepCollectionEquality().equals(other.enums, enums)&&const DeepCollectionEquality().equals(other.mappings, mappings)&&const DeepCollectionEquality().equals(other.valueStrings, valueStrings)&&const DeepCollectionEquality().equals(other.outputModeMap, outputModeMap));
}


@override
int get hashCode => Object.hash(runtimeType,algorithm,routing,pages,const DeepCollectionEquality().hash(parameters),const DeepCollectionEquality().hash(values),const DeepCollectionEquality().hash(enums),const DeepCollectionEquality().hash(mappings),const DeepCollectionEquality().hash(valueStrings),const DeepCollectionEquality().hash(outputModeMap));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'Slot(algorithm: $algorithm, routing: $routing, pages: $pages, parameters: $parameters, values: $values, enums: $enums, mappings: $mappings, valueStrings: $valueStrings, outputModeMap: $outputModeMap)';
}


}

/// @nodoc
abstract mixin class $SlotCopyWith<$Res>  {
  factory $SlotCopyWith(Slot value, $Res Function(Slot) _then) = _$SlotCopyWithImpl;
@useResult
$Res call({
 Algorithm algorithm, RoutingInfo routing, ParameterPages pages, List<ParameterInfo> parameters, List<ParameterValue> values, List<ParameterEnumStrings> enums, List<Mapping> mappings, List<ParameterValueString> valueStrings, Map<int, List<int>> outputModeMap
});




}
/// @nodoc
class _$SlotCopyWithImpl<$Res>
    implements $SlotCopyWith<$Res> {
  _$SlotCopyWithImpl(this._self, this._then);

  final Slot _self;
  final $Res Function(Slot) _then;

/// Create a copy of Slot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? algorithm = null,Object? routing = null,Object? pages = null,Object? parameters = null,Object? values = null,Object? enums = null,Object? mappings = null,Object? valueStrings = null,Object? outputModeMap = null,}) {
  return _then(_self.copyWith(
algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,routing: null == routing ? _self.routing : routing // ignore: cast_nullable_to_non_nullable
as RoutingInfo,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as ParameterPages,parameters: null == parameters ? _self.parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<ParameterInfo>,values: null == values ? _self.values : values // ignore: cast_nullable_to_non_nullable
as List<ParameterValue>,enums: null == enums ? _self.enums : enums // ignore: cast_nullable_to_non_nullable
as List<ParameterEnumStrings>,mappings: null == mappings ? _self.mappings : mappings // ignore: cast_nullable_to_non_nullable
as List<Mapping>,valueStrings: null == valueStrings ? _self.valueStrings : valueStrings // ignore: cast_nullable_to_non_nullable
as List<ParameterValueString>,outputModeMap: null == outputModeMap ? _self.outputModeMap : outputModeMap // ignore: cast_nullable_to_non_nullable
as Map<int, List<int>>,
  ));
}

}


/// Adds pattern-matching-related methods to [Slot].
extension SlotPatterns on Slot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Slot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Slot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Slot value)  $default,){
final _that = this;
switch (_that) {
case _Slot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Slot value)?  $default,){
final _that = this;
switch (_that) {
case _Slot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Algorithm algorithm,  RoutingInfo routing,  ParameterPages pages,  List<ParameterInfo> parameters,  List<ParameterValue> values,  List<ParameterEnumStrings> enums,  List<Mapping> mappings,  List<ParameterValueString> valueStrings,  Map<int, List<int>> outputModeMap)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Slot() when $default != null:
return $default(_that.algorithm,_that.routing,_that.pages,_that.parameters,_that.values,_that.enums,_that.mappings,_that.valueStrings,_that.outputModeMap);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Algorithm algorithm,  RoutingInfo routing,  ParameterPages pages,  List<ParameterInfo> parameters,  List<ParameterValue> values,  List<ParameterEnumStrings> enums,  List<Mapping> mappings,  List<ParameterValueString> valueStrings,  Map<int, List<int>> outputModeMap)  $default,) {final _that = this;
switch (_that) {
case _Slot():
return $default(_that.algorithm,_that.routing,_that.pages,_that.parameters,_that.values,_that.enums,_that.mappings,_that.valueStrings,_that.outputModeMap);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Algorithm algorithm,  RoutingInfo routing,  ParameterPages pages,  List<ParameterInfo> parameters,  List<ParameterValue> values,  List<ParameterEnumStrings> enums,  List<Mapping> mappings,  List<ParameterValueString> valueStrings,  Map<int, List<int>> outputModeMap)?  $default,) {final _that = this;
switch (_that) {
case _Slot() when $default != null:
return $default(_that.algorithm,_that.routing,_that.pages,_that.parameters,_that.values,_that.enums,_that.mappings,_that.valueStrings,_that.outputModeMap);case _:
  return null;

}
}

}

/// @nodoc


class _Slot with DiagnosticableTreeMixin implements Slot {
  const _Slot({required this.algorithm, required this.routing, required this.pages, required final  List<ParameterInfo> parameters, required final  List<ParameterValue> values, required final  List<ParameterEnumStrings> enums, required final  List<Mapping> mappings, required final  List<ParameterValueString> valueStrings, final  Map<int, List<int>> outputModeMap = const {}}): _parameters = parameters,_values = values,_enums = enums,_mappings = mappings,_valueStrings = valueStrings,_outputModeMap = outputModeMap;
  

@override final  Algorithm algorithm;
@override final  RoutingInfo routing;
@override final  ParameterPages pages;
 final  List<ParameterInfo> _parameters;
@override List<ParameterInfo> get parameters {
  if (_parameters is EqualUnmodifiableListView) return _parameters;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parameters);
}

 final  List<ParameterValue> _values;
@override List<ParameterValue> get values {
  if (_values is EqualUnmodifiableListView) return _values;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_values);
}

 final  List<ParameterEnumStrings> _enums;
@override List<ParameterEnumStrings> get enums {
  if (_enums is EqualUnmodifiableListView) return _enums;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_enums);
}

 final  List<Mapping> _mappings;
@override List<Mapping> get mappings {
  if (_mappings is EqualUnmodifiableListView) return _mappings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_mappings);
}

 final  List<ParameterValueString> _valueStrings;
@override List<ParameterValueString> get valueStrings {
  if (_valueStrings is EqualUnmodifiableListView) return _valueStrings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_valueStrings);
}

/// Output mode usage map: parameter number -> list of affected parameter numbers
/// Populated from SysEx 0x55 responses (Story 7.4)
 final  Map<int, List<int>> _outputModeMap;
/// Output mode usage map: parameter number -> list of affected parameter numbers
/// Populated from SysEx 0x55 responses (Story 7.4)
@override@JsonKey() Map<int, List<int>> get outputModeMap {
  if (_outputModeMap is EqualUnmodifiableMapView) return _outputModeMap;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_outputModeMap);
}


/// Create a copy of Slot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SlotCopyWith<_Slot> get copyWith => __$SlotCopyWithImpl<_Slot>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'Slot'))
    ..add(DiagnosticsProperty('algorithm', algorithm))..add(DiagnosticsProperty('routing', routing))..add(DiagnosticsProperty('pages', pages))..add(DiagnosticsProperty('parameters', parameters))..add(DiagnosticsProperty('values', values))..add(DiagnosticsProperty('enums', enums))..add(DiagnosticsProperty('mappings', mappings))..add(DiagnosticsProperty('valueStrings', valueStrings))..add(DiagnosticsProperty('outputModeMap', outputModeMap));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Slot&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm)&&(identical(other.routing, routing) || other.routing == routing)&&(identical(other.pages, pages) || other.pages == pages)&&const DeepCollectionEquality().equals(other._parameters, _parameters)&&const DeepCollectionEquality().equals(other._values, _values)&&const DeepCollectionEquality().equals(other._enums, _enums)&&const DeepCollectionEquality().equals(other._mappings, _mappings)&&const DeepCollectionEquality().equals(other._valueStrings, _valueStrings)&&const DeepCollectionEquality().equals(other._outputModeMap, _outputModeMap));
}


@override
int get hashCode => Object.hash(runtimeType,algorithm,routing,pages,const DeepCollectionEquality().hash(_parameters),const DeepCollectionEquality().hash(_values),const DeepCollectionEquality().hash(_enums),const DeepCollectionEquality().hash(_mappings),const DeepCollectionEquality().hash(_valueStrings),const DeepCollectionEquality().hash(_outputModeMap));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'Slot(algorithm: $algorithm, routing: $routing, pages: $pages, parameters: $parameters, values: $values, enums: $enums, mappings: $mappings, valueStrings: $valueStrings, outputModeMap: $outputModeMap)';
}


}

/// @nodoc
abstract mixin class _$SlotCopyWith<$Res> implements $SlotCopyWith<$Res> {
  factory _$SlotCopyWith(_Slot value, $Res Function(_Slot) _then) = __$SlotCopyWithImpl;
@override @useResult
$Res call({
 Algorithm algorithm, RoutingInfo routing, ParameterPages pages, List<ParameterInfo> parameters, List<ParameterValue> values, List<ParameterEnumStrings> enums, List<Mapping> mappings, List<ParameterValueString> valueStrings, Map<int, List<int>> outputModeMap
});




}
/// @nodoc
class __$SlotCopyWithImpl<$Res>
    implements _$SlotCopyWith<$Res> {
  __$SlotCopyWithImpl(this._self, this._then);

  final _Slot _self;
  final $Res Function(_Slot) _then;

/// Create a copy of Slot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? algorithm = null,Object? routing = null,Object? pages = null,Object? parameters = null,Object? values = null,Object? enums = null,Object? mappings = null,Object? valueStrings = null,Object? outputModeMap = null,}) {
  return _then(_Slot(
algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,routing: null == routing ? _self.routing : routing // ignore: cast_nullable_to_non_nullable
as RoutingInfo,pages: null == pages ? _self.pages : pages // ignore: cast_nullable_to_non_nullable
as ParameterPages,parameters: null == parameters ? _self._parameters : parameters // ignore: cast_nullable_to_non_nullable
as List<ParameterInfo>,values: null == values ? _self._values : values // ignore: cast_nullable_to_non_nullable
as List<ParameterValue>,enums: null == enums ? _self._enums : enums // ignore: cast_nullable_to_non_nullable
as List<ParameterEnumStrings>,mappings: null == mappings ? _self._mappings : mappings // ignore: cast_nullable_to_non_nullable
as List<Mapping>,valueStrings: null == valueStrings ? _self._valueStrings : valueStrings // ignore: cast_nullable_to_non_nullable
as List<ParameterValueString>,outputModeMap: null == outputModeMap ? _self._outputModeMap : outputModeMap // ignore: cast_nullable_to_non_nullable
as Map<int, List<int>>,
  ));
}


}

/// @nodoc
mixin _$MappedParameter implements DiagnosticableTreeMixin {

 ParameterInfo get parameter; ParameterValue get value; ParameterEnumStrings get enums; ParameterValueString get valueString; Mapping get mapping; Algorithm get algorithm;
/// Create a copy of MappedParameter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MappedParameterCopyWith<MappedParameter> get copyWith => _$MappedParameterCopyWithImpl<MappedParameter>(this as MappedParameter, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'MappedParameter'))
    ..add(DiagnosticsProperty('parameter', parameter))..add(DiagnosticsProperty('value', value))..add(DiagnosticsProperty('enums', enums))..add(DiagnosticsProperty('valueString', valueString))..add(DiagnosticsProperty('mapping', mapping))..add(DiagnosticsProperty('algorithm', algorithm));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MappedParameter&&(identical(other.parameter, parameter) || other.parameter == parameter)&&(identical(other.value, value) || other.value == value)&&(identical(other.enums, enums) || other.enums == enums)&&(identical(other.valueString, valueString) || other.valueString == valueString)&&(identical(other.mapping, mapping) || other.mapping == mapping)&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm));
}


@override
int get hashCode => Object.hash(runtimeType,parameter,value,enums,valueString,mapping,algorithm);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'MappedParameter(parameter: $parameter, value: $value, enums: $enums, valueString: $valueString, mapping: $mapping, algorithm: $algorithm)';
}


}

/// @nodoc
abstract mixin class $MappedParameterCopyWith<$Res>  {
  factory $MappedParameterCopyWith(MappedParameter value, $Res Function(MappedParameter) _then) = _$MappedParameterCopyWithImpl;
@useResult
$Res call({
 ParameterInfo parameter, ParameterValue value, ParameterEnumStrings enums, ParameterValueString valueString, Mapping mapping, Algorithm algorithm
});




}
/// @nodoc
class _$MappedParameterCopyWithImpl<$Res>
    implements $MappedParameterCopyWith<$Res> {
  _$MappedParameterCopyWithImpl(this._self, this._then);

  final MappedParameter _self;
  final $Res Function(MappedParameter) _then;

/// Create a copy of MappedParameter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parameter = null,Object? value = null,Object? enums = null,Object? valueString = null,Object? mapping = null,Object? algorithm = null,}) {
  return _then(_self.copyWith(
parameter: null == parameter ? _self.parameter : parameter // ignore: cast_nullable_to_non_nullable
as ParameterInfo,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ParameterValue,enums: null == enums ? _self.enums : enums // ignore: cast_nullable_to_non_nullable
as ParameterEnumStrings,valueString: null == valueString ? _self.valueString : valueString // ignore: cast_nullable_to_non_nullable
as ParameterValueString,mapping: null == mapping ? _self.mapping : mapping // ignore: cast_nullable_to_non_nullable
as Mapping,algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,
  ));
}

}


/// Adds pattern-matching-related methods to [MappedParameter].
extension MappedParameterPatterns on MappedParameter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MappedParameter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MappedParameter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MappedParameter value)  $default,){
final _that = this;
switch (_that) {
case _MappedParameter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MappedParameter value)?  $default,){
final _that = this;
switch (_that) {
case _MappedParameter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ParameterInfo parameter,  ParameterValue value,  ParameterEnumStrings enums,  ParameterValueString valueString,  Mapping mapping,  Algorithm algorithm)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MappedParameter() when $default != null:
return $default(_that.parameter,_that.value,_that.enums,_that.valueString,_that.mapping,_that.algorithm);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ParameterInfo parameter,  ParameterValue value,  ParameterEnumStrings enums,  ParameterValueString valueString,  Mapping mapping,  Algorithm algorithm)  $default,) {final _that = this;
switch (_that) {
case _MappedParameter():
return $default(_that.parameter,_that.value,_that.enums,_that.valueString,_that.mapping,_that.algorithm);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ParameterInfo parameter,  ParameterValue value,  ParameterEnumStrings enums,  ParameterValueString valueString,  Mapping mapping,  Algorithm algorithm)?  $default,) {final _that = this;
switch (_that) {
case _MappedParameter() when $default != null:
return $default(_that.parameter,_that.value,_that.enums,_that.valueString,_that.mapping,_that.algorithm);case _:
  return null;

}
}

}

/// @nodoc


class _MappedParameter with DiagnosticableTreeMixin implements MappedParameter {
  const _MappedParameter({required this.parameter, required this.value, required this.enums, required this.valueString, required this.mapping, required this.algorithm});
  

@override final  ParameterInfo parameter;
@override final  ParameterValue value;
@override final  ParameterEnumStrings enums;
@override final  ParameterValueString valueString;
@override final  Mapping mapping;
@override final  Algorithm algorithm;

/// Create a copy of MappedParameter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MappedParameterCopyWith<_MappedParameter> get copyWith => __$MappedParameterCopyWithImpl<_MappedParameter>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'MappedParameter'))
    ..add(DiagnosticsProperty('parameter', parameter))..add(DiagnosticsProperty('value', value))..add(DiagnosticsProperty('enums', enums))..add(DiagnosticsProperty('valueString', valueString))..add(DiagnosticsProperty('mapping', mapping))..add(DiagnosticsProperty('algorithm', algorithm));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MappedParameter&&(identical(other.parameter, parameter) || other.parameter == parameter)&&(identical(other.value, value) || other.value == value)&&(identical(other.enums, enums) || other.enums == enums)&&(identical(other.valueString, valueString) || other.valueString == valueString)&&(identical(other.mapping, mapping) || other.mapping == mapping)&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm));
}


@override
int get hashCode => Object.hash(runtimeType,parameter,value,enums,valueString,mapping,algorithm);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'MappedParameter(parameter: $parameter, value: $value, enums: $enums, valueString: $valueString, mapping: $mapping, algorithm: $algorithm)';
}


}

/// @nodoc
abstract mixin class _$MappedParameterCopyWith<$Res> implements $MappedParameterCopyWith<$Res> {
  factory _$MappedParameterCopyWith(_MappedParameter value, $Res Function(_MappedParameter) _then) = __$MappedParameterCopyWithImpl;
@override @useResult
$Res call({
 ParameterInfo parameter, ParameterValue value, ParameterEnumStrings enums, ParameterValueString valueString, Mapping mapping, Algorithm algorithm
});




}
/// @nodoc
class __$MappedParameterCopyWithImpl<$Res>
    implements _$MappedParameterCopyWith<$Res> {
  __$MappedParameterCopyWithImpl(this._self, this._then);

  final _MappedParameter _self;
  final $Res Function(_MappedParameter) _then;

/// Create a copy of MappedParameter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parameter = null,Object? value = null,Object? enums = null,Object? valueString = null,Object? mapping = null,Object? algorithm = null,}) {
  return _then(_MappedParameter(
parameter: null == parameter ? _self.parameter : parameter // ignore: cast_nullable_to_non_nullable
as ParameterInfo,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ParameterValue,enums: null == enums ? _self.enums : enums // ignore: cast_nullable_to_non_nullable
as ParameterEnumStrings,valueString: null == valueString ? _self.valueString : valueString // ignore: cast_nullable_to_non_nullable
as ParameterValueString,mapping: null == mapping ? _self.mapping : mapping // ignore: cast_nullable_to_non_nullable
as Mapping,algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,
  ));
}


}

/// @nodoc
mixin _$DistingState implements DiagnosticableTreeMixin {




@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DistingState'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DistingState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DistingState()';
}


}

/// @nodoc
class $DistingStateCopyWith<$Res>  {
$DistingStateCopyWith(DistingState _, $Res Function(DistingState) __);
}


/// Adds pattern-matching-related methods to [DistingState].
extension DistingStatePatterns on DistingState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DistingStateInitial value)?  initial,TResult Function( DistingStateSelectDevice value)?  selectDevice,TResult Function( DistingStateConnected value)?  connected,TResult Function( DistingStateSynchronized value)?  synchronized,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DistingStateInitial() when initial != null:
return initial(_that);case DistingStateSelectDevice() when selectDevice != null:
return selectDevice(_that);case DistingStateConnected() when connected != null:
return connected(_that);case DistingStateSynchronized() when synchronized != null:
return synchronized(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DistingStateInitial value)  initial,required TResult Function( DistingStateSelectDevice value)  selectDevice,required TResult Function( DistingStateConnected value)  connected,required TResult Function( DistingStateSynchronized value)  synchronized,}){
final _that = this;
switch (_that) {
case DistingStateInitial():
return initial(_that);case DistingStateSelectDevice():
return selectDevice(_that);case DistingStateConnected():
return connected(_that);case DistingStateSynchronized():
return synchronized(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DistingStateInitial value)?  initial,TResult? Function( DistingStateSelectDevice value)?  selectDevice,TResult? Function( DistingStateConnected value)?  connected,TResult? Function( DistingStateSynchronized value)?  synchronized,}){
final _that = this;
switch (_that) {
case DistingStateInitial() when initial != null:
return initial(_that);case DistingStateSelectDevice() when selectDevice != null:
return selectDevice(_that);case DistingStateConnected() when connected != null:
return connected(_that);case DistingStateSynchronized() when synchronized != null:
return synchronized(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function( List<MidiDevice> inputDevices,  List<MidiDevice> outputDevices,  bool canWorkOffline,  MidiDevice? selectedInputDevice,  MidiDevice? selectedOutputDevice,  int selectedSysExId)?  selectDevice,TResult Function( IDistingMidiManager disting,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool offline,  bool loading,  String? syncStatus,  double? syncProgress)?  connected,TResult Function( IDistingMidiManager disting,  String distingVersion,  FirmwareVersion firmwareVersion,  String presetName,  List<AlgorithmInfo> algorithms,  List<Slot> slots,  List<String> unitStrings,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool loading,  bool offline,  Uint8List? screenshot,  bool demo,  VideoStreamState? videoStream,  FirmwareRelease? availableFirmwareUpdate,  List<PerformancePageItem> perfPageItems,  bool isDirty,  String? renameConfirmationName)?  synchronized,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DistingStateInitial() when initial != null:
return initial();case DistingStateSelectDevice() when selectDevice != null:
return selectDevice(_that.inputDevices,_that.outputDevices,_that.canWorkOffline,_that.selectedInputDevice,_that.selectedOutputDevice,_that.selectedSysExId);case DistingStateConnected() when connected != null:
return connected(_that.disting,_that.inputDevice,_that.outputDevice,_that.offline,_that.loading,_that.syncStatus,_that.syncProgress);case DistingStateSynchronized() when synchronized != null:
return synchronized(_that.disting,_that.distingVersion,_that.firmwareVersion,_that.presetName,_that.algorithms,_that.slots,_that.unitStrings,_that.inputDevice,_that.outputDevice,_that.loading,_that.offline,_that.screenshot,_that.demo,_that.videoStream,_that.availableFirmwareUpdate,_that.perfPageItems,_that.isDirty,_that.renameConfirmationName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function( List<MidiDevice> inputDevices,  List<MidiDevice> outputDevices,  bool canWorkOffline,  MidiDevice? selectedInputDevice,  MidiDevice? selectedOutputDevice,  int selectedSysExId)  selectDevice,required TResult Function( IDistingMidiManager disting,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool offline,  bool loading,  String? syncStatus,  double? syncProgress)  connected,required TResult Function( IDistingMidiManager disting,  String distingVersion,  FirmwareVersion firmwareVersion,  String presetName,  List<AlgorithmInfo> algorithms,  List<Slot> slots,  List<String> unitStrings,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool loading,  bool offline,  Uint8List? screenshot,  bool demo,  VideoStreamState? videoStream,  FirmwareRelease? availableFirmwareUpdate,  List<PerformancePageItem> perfPageItems,  bool isDirty,  String? renameConfirmationName)  synchronized,}) {final _that = this;
switch (_that) {
case DistingStateInitial():
return initial();case DistingStateSelectDevice():
return selectDevice(_that.inputDevices,_that.outputDevices,_that.canWorkOffline,_that.selectedInputDevice,_that.selectedOutputDevice,_that.selectedSysExId);case DistingStateConnected():
return connected(_that.disting,_that.inputDevice,_that.outputDevice,_that.offline,_that.loading,_that.syncStatus,_that.syncProgress);case DistingStateSynchronized():
return synchronized(_that.disting,_that.distingVersion,_that.firmwareVersion,_that.presetName,_that.algorithms,_that.slots,_that.unitStrings,_that.inputDevice,_that.outputDevice,_that.loading,_that.offline,_that.screenshot,_that.demo,_that.videoStream,_that.availableFirmwareUpdate,_that.perfPageItems,_that.isDirty,_that.renameConfirmationName);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function( List<MidiDevice> inputDevices,  List<MidiDevice> outputDevices,  bool canWorkOffline,  MidiDevice? selectedInputDevice,  MidiDevice? selectedOutputDevice,  int selectedSysExId)?  selectDevice,TResult? Function( IDistingMidiManager disting,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool offline,  bool loading,  String? syncStatus,  double? syncProgress)?  connected,TResult? Function( IDistingMidiManager disting,  String distingVersion,  FirmwareVersion firmwareVersion,  String presetName,  List<AlgorithmInfo> algorithms,  List<Slot> slots,  List<String> unitStrings,  MidiDevice? inputDevice,  MidiDevice? outputDevice,  bool loading,  bool offline,  Uint8List? screenshot,  bool demo,  VideoStreamState? videoStream,  FirmwareRelease? availableFirmwareUpdate,  List<PerformancePageItem> perfPageItems,  bool isDirty,  String? renameConfirmationName)?  synchronized,}) {final _that = this;
switch (_that) {
case DistingStateInitial() when initial != null:
return initial();case DistingStateSelectDevice() when selectDevice != null:
return selectDevice(_that.inputDevices,_that.outputDevices,_that.canWorkOffline,_that.selectedInputDevice,_that.selectedOutputDevice,_that.selectedSysExId);case DistingStateConnected() when connected != null:
return connected(_that.disting,_that.inputDevice,_that.outputDevice,_that.offline,_that.loading,_that.syncStatus,_that.syncProgress);case DistingStateSynchronized() when synchronized != null:
return synchronized(_that.disting,_that.distingVersion,_that.firmwareVersion,_that.presetName,_that.algorithms,_that.slots,_that.unitStrings,_that.inputDevice,_that.outputDevice,_that.loading,_that.offline,_that.screenshot,_that.demo,_that.videoStream,_that.availableFirmwareUpdate,_that.perfPageItems,_that.isDirty,_that.renameConfirmationName);case _:
  return null;

}
}

}

/// @nodoc


class DistingStateInitial with DiagnosticableTreeMixin implements DistingState {
  const DistingStateInitial();
  





@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DistingState.initial'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DistingStateInitial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DistingState.initial()';
}


}




/// @nodoc


class DistingStateSelectDevice with DiagnosticableTreeMixin implements DistingState {
  const DistingStateSelectDevice({required final  List<MidiDevice> inputDevices, required final  List<MidiDevice> outputDevices, required this.canWorkOffline, this.selectedInputDevice = null, this.selectedOutputDevice = null, this.selectedSysExId = 0}): _inputDevices = inputDevices,_outputDevices = outputDevices;
  

 final  List<MidiDevice> _inputDevices;
 List<MidiDevice> get inputDevices {
  if (_inputDevices is EqualUnmodifiableListView) return _inputDevices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_inputDevices);
}

 final  List<MidiDevice> _outputDevices;
 List<MidiDevice> get outputDevices {
  if (_outputDevices is EqualUnmodifiableListView) return _outputDevices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputDevices);
}

 final  bool canWorkOffline;
@JsonKey() final  MidiDevice? selectedInputDevice;
@JsonKey() final  MidiDevice? selectedOutputDevice;
@JsonKey() final  int selectedSysExId;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DistingStateSelectDeviceCopyWith<DistingStateSelectDevice> get copyWith => _$DistingStateSelectDeviceCopyWithImpl<DistingStateSelectDevice>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DistingState.selectDevice'))
    ..add(DiagnosticsProperty('inputDevices', inputDevices))..add(DiagnosticsProperty('outputDevices', outputDevices))..add(DiagnosticsProperty('canWorkOffline', canWorkOffline))..add(DiagnosticsProperty('selectedInputDevice', selectedInputDevice))..add(DiagnosticsProperty('selectedOutputDevice', selectedOutputDevice))..add(DiagnosticsProperty('selectedSysExId', selectedSysExId));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DistingStateSelectDevice&&const DeepCollectionEquality().equals(other._inputDevices, _inputDevices)&&const DeepCollectionEquality().equals(other._outputDevices, _outputDevices)&&(identical(other.canWorkOffline, canWorkOffline) || other.canWorkOffline == canWorkOffline)&&(identical(other.selectedInputDevice, selectedInputDevice) || other.selectedInputDevice == selectedInputDevice)&&(identical(other.selectedOutputDevice, selectedOutputDevice) || other.selectedOutputDevice == selectedOutputDevice)&&(identical(other.selectedSysExId, selectedSysExId) || other.selectedSysExId == selectedSysExId));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_inputDevices),const DeepCollectionEquality().hash(_outputDevices),canWorkOffline,selectedInputDevice,selectedOutputDevice,selectedSysExId);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DistingState.selectDevice(inputDevices: $inputDevices, outputDevices: $outputDevices, canWorkOffline: $canWorkOffline, selectedInputDevice: $selectedInputDevice, selectedOutputDevice: $selectedOutputDevice, selectedSysExId: $selectedSysExId)';
}


}

/// @nodoc
abstract mixin class $DistingStateSelectDeviceCopyWith<$Res> implements $DistingStateCopyWith<$Res> {
  factory $DistingStateSelectDeviceCopyWith(DistingStateSelectDevice value, $Res Function(DistingStateSelectDevice) _then) = _$DistingStateSelectDeviceCopyWithImpl;
@useResult
$Res call({
 List<MidiDevice> inputDevices, List<MidiDevice> outputDevices, bool canWorkOffline, MidiDevice? selectedInputDevice, MidiDevice? selectedOutputDevice, int selectedSysExId
});




}
/// @nodoc
class _$DistingStateSelectDeviceCopyWithImpl<$Res>
    implements $DistingStateSelectDeviceCopyWith<$Res> {
  _$DistingStateSelectDeviceCopyWithImpl(this._self, this._then);

  final DistingStateSelectDevice _self;
  final $Res Function(DistingStateSelectDevice) _then;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inputDevices = null,Object? outputDevices = null,Object? canWorkOffline = null,Object? selectedInputDevice = freezed,Object? selectedOutputDevice = freezed,Object? selectedSysExId = null,}) {
  return _then(DistingStateSelectDevice(
inputDevices: null == inputDevices ? _self._inputDevices : inputDevices // ignore: cast_nullable_to_non_nullable
as List<MidiDevice>,outputDevices: null == outputDevices ? _self._outputDevices : outputDevices // ignore: cast_nullable_to_non_nullable
as List<MidiDevice>,canWorkOffline: null == canWorkOffline ? _self.canWorkOffline : canWorkOffline // ignore: cast_nullable_to_non_nullable
as bool,selectedInputDevice: freezed == selectedInputDevice ? _self.selectedInputDevice : selectedInputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,selectedOutputDevice: freezed == selectedOutputDevice ? _self.selectedOutputDevice : selectedOutputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,selectedSysExId: null == selectedSysExId ? _self.selectedSysExId : selectedSysExId // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DistingStateConnected with DiagnosticableTreeMixin implements DistingState {
  const DistingStateConnected({required this.disting, this.inputDevice, this.outputDevice, this.offline = false, this.loading = false, this.syncStatus = null, this.syncProgress = null});
  

 final  IDistingMidiManager disting;
 final  MidiDevice? inputDevice;
 final  MidiDevice? outputDevice;
@JsonKey() final  bool offline;
@JsonKey() final  bool loading;
@JsonKey() final  String? syncStatus;
@JsonKey() final  double? syncProgress;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DistingStateConnectedCopyWith<DistingStateConnected> get copyWith => _$DistingStateConnectedCopyWithImpl<DistingStateConnected>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DistingState.connected'))
    ..add(DiagnosticsProperty('disting', disting))..add(DiagnosticsProperty('inputDevice', inputDevice))..add(DiagnosticsProperty('outputDevice', outputDevice))..add(DiagnosticsProperty('offline', offline))..add(DiagnosticsProperty('loading', loading))..add(DiagnosticsProperty('syncStatus', syncStatus))..add(DiagnosticsProperty('syncProgress', syncProgress));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DistingStateConnected&&(identical(other.disting, disting) || other.disting == disting)&&(identical(other.inputDevice, inputDevice) || other.inputDevice == inputDevice)&&(identical(other.outputDevice, outputDevice) || other.outputDevice == outputDevice)&&(identical(other.offline, offline) || other.offline == offline)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.syncStatus, syncStatus) || other.syncStatus == syncStatus)&&(identical(other.syncProgress, syncProgress) || other.syncProgress == syncProgress));
}


@override
int get hashCode => Object.hash(runtimeType,disting,inputDevice,outputDevice,offline,loading,syncStatus,syncProgress);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DistingState.connected(disting: $disting, inputDevice: $inputDevice, outputDevice: $outputDevice, offline: $offline, loading: $loading, syncStatus: $syncStatus, syncProgress: $syncProgress)';
}


}

/// @nodoc
abstract mixin class $DistingStateConnectedCopyWith<$Res> implements $DistingStateCopyWith<$Res> {
  factory $DistingStateConnectedCopyWith(DistingStateConnected value, $Res Function(DistingStateConnected) _then) = _$DistingStateConnectedCopyWithImpl;
@useResult
$Res call({
 IDistingMidiManager disting, MidiDevice? inputDevice, MidiDevice? outputDevice, bool offline, bool loading, String? syncStatus, double? syncProgress
});




}
/// @nodoc
class _$DistingStateConnectedCopyWithImpl<$Res>
    implements $DistingStateConnectedCopyWith<$Res> {
  _$DistingStateConnectedCopyWithImpl(this._self, this._then);

  final DistingStateConnected _self;
  final $Res Function(DistingStateConnected) _then;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? disting = null,Object? inputDevice = freezed,Object? outputDevice = freezed,Object? offline = null,Object? loading = null,Object? syncStatus = freezed,Object? syncProgress = freezed,}) {
  return _then(DistingStateConnected(
disting: null == disting ? _self.disting : disting // ignore: cast_nullable_to_non_nullable
as IDistingMidiManager,inputDevice: freezed == inputDevice ? _self.inputDevice : inputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,outputDevice: freezed == outputDevice ? _self.outputDevice : outputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,offline: null == offline ? _self.offline : offline // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,syncStatus: freezed == syncStatus ? _self.syncStatus : syncStatus // ignore: cast_nullable_to_non_nullable
as String?,syncProgress: freezed == syncProgress ? _self.syncProgress : syncProgress // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc


class DistingStateSynchronized with DiagnosticableTreeMixin implements DistingState {
  const DistingStateSynchronized({required this.disting, required this.distingVersion, required this.firmwareVersion, required this.presetName, required final  List<AlgorithmInfo> algorithms, required final  List<Slot> slots, required final  List<String> unitStrings, this.inputDevice = null, this.outputDevice = null, this.loading = false, this.offline = false, this.screenshot = null, this.demo = false, this.videoStream = null, this.availableFirmwareUpdate = null, final  List<PerformancePageItem> perfPageItems = const [], this.isDirty = false, this.renameConfirmationName = null}): _algorithms = algorithms,_slots = slots,_unitStrings = unitStrings,_perfPageItems = perfPageItems;
  

 final  IDistingMidiManager disting;
 final  String distingVersion;
 final  FirmwareVersion firmwareVersion;
 final  String presetName;
 final  List<AlgorithmInfo> _algorithms;
 List<AlgorithmInfo> get algorithms {
  if (_algorithms is EqualUnmodifiableListView) return _algorithms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_algorithms);
}

 final  List<Slot> _slots;
 List<Slot> get slots {
  if (_slots is EqualUnmodifiableListView) return _slots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_slots);
}

 final  List<String> _unitStrings;
 List<String> get unitStrings {
  if (_unitStrings is EqualUnmodifiableListView) return _unitStrings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unitStrings);
}

@JsonKey() final  MidiDevice? inputDevice;
@JsonKey() final  MidiDevice? outputDevice;
@JsonKey() final  bool loading;
@JsonKey() final  bool offline;
@JsonKey() final  Uint8List? screenshot;
@JsonKey() final  bool demo;
@JsonKey() final  VideoStreamState? videoStream;
/// Available firmware update (null if no update available or not checked)
@JsonKey() final  FirmwareRelease? availableFirmwareUpdate;
/// Performance page items (firmware v1.16+, populated via SysEx 0x57/0x58)
 final  List<PerformancePageItem> _perfPageItems;
/// Performance page items (firmware v1.16+, populated via SysEx 0x57/0x58)
@JsonKey() List<PerformancePageItem> get perfPageItems {
  if (_perfPageItems is EqualUnmodifiableListView) return _perfPageItems;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_perfPageItems);
}

/// True when the in-memory preset has been mutated since the last
/// save / load / new / device refresh. Cleared on save/load/new/refresh.
@JsonKey() final  bool isDirty;
/// The name of a preset that is currently awaiting confirmation to be overwritten
@JsonKey() final  String? renameConfirmationName;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DistingStateSynchronizedCopyWith<DistingStateSynchronized> get copyWith => _$DistingStateSynchronizedCopyWithImpl<DistingStateSynchronized>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'DistingState.synchronized'))
    ..add(DiagnosticsProperty('disting', disting))..add(DiagnosticsProperty('distingVersion', distingVersion))..add(DiagnosticsProperty('firmwareVersion', firmwareVersion))..add(DiagnosticsProperty('presetName', presetName))..add(DiagnosticsProperty('algorithms', algorithms))..add(DiagnosticsProperty('slots', slots))..add(DiagnosticsProperty('unitStrings', unitStrings))..add(DiagnosticsProperty('inputDevice', inputDevice))..add(DiagnosticsProperty('outputDevice', outputDevice))..add(DiagnosticsProperty('loading', loading))..add(DiagnosticsProperty('offline', offline))..add(DiagnosticsProperty('screenshot', screenshot))..add(DiagnosticsProperty('demo', demo))..add(DiagnosticsProperty('videoStream', videoStream))..add(DiagnosticsProperty('availableFirmwareUpdate', availableFirmwareUpdate))..add(DiagnosticsProperty('perfPageItems', perfPageItems))..add(DiagnosticsProperty('isDirty', isDirty))..add(DiagnosticsProperty('renameConfirmationName', renameConfirmationName));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DistingStateSynchronized&&(identical(other.disting, disting) || other.disting == disting)&&(identical(other.distingVersion, distingVersion) || other.distingVersion == distingVersion)&&(identical(other.firmwareVersion, firmwareVersion) || other.firmwareVersion == firmwareVersion)&&(identical(other.presetName, presetName) || other.presetName == presetName)&&const DeepCollectionEquality().equals(other._algorithms, _algorithms)&&const DeepCollectionEquality().equals(other._slots, _slots)&&const DeepCollectionEquality().equals(other._unitStrings, _unitStrings)&&(identical(other.inputDevice, inputDevice) || other.inputDevice == inputDevice)&&(identical(other.outputDevice, outputDevice) || other.outputDevice == outputDevice)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.offline, offline) || other.offline == offline)&&const DeepCollectionEquality().equals(other.screenshot, screenshot)&&(identical(other.demo, demo) || other.demo == demo)&&(identical(other.videoStream, videoStream) || other.videoStream == videoStream)&&(identical(other.availableFirmwareUpdate, availableFirmwareUpdate) || other.availableFirmwareUpdate == availableFirmwareUpdate)&&const DeepCollectionEquality().equals(other._perfPageItems, _perfPageItems)&&(identical(other.isDirty, isDirty) || other.isDirty == isDirty)&&(identical(other.renameConfirmationName, renameConfirmationName) || other.renameConfirmationName == renameConfirmationName));
}


@override
int get hashCode => Object.hash(runtimeType,disting,distingVersion,firmwareVersion,presetName,const DeepCollectionEquality().hash(_algorithms),const DeepCollectionEquality().hash(_slots),const DeepCollectionEquality().hash(_unitStrings),inputDevice,outputDevice,loading,offline,const DeepCollectionEquality().hash(screenshot),demo,videoStream,availableFirmwareUpdate,const DeepCollectionEquality().hash(_perfPageItems),isDirty,renameConfirmationName);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'DistingState.synchronized(disting: $disting, distingVersion: $distingVersion, firmwareVersion: $firmwareVersion, presetName: $presetName, algorithms: $algorithms, slots: $slots, unitStrings: $unitStrings, inputDevice: $inputDevice, outputDevice: $outputDevice, loading: $loading, offline: $offline, screenshot: $screenshot, demo: $demo, videoStream: $videoStream, availableFirmwareUpdate: $availableFirmwareUpdate, perfPageItems: $perfPageItems, isDirty: $isDirty, renameConfirmationName: $renameConfirmationName)';
}


}

/// @nodoc
abstract mixin class $DistingStateSynchronizedCopyWith<$Res> implements $DistingStateCopyWith<$Res> {
  factory $DistingStateSynchronizedCopyWith(DistingStateSynchronized value, $Res Function(DistingStateSynchronized) _then) = _$DistingStateSynchronizedCopyWithImpl;
@useResult
$Res call({
 IDistingMidiManager disting, String distingVersion, FirmwareVersion firmwareVersion, String presetName, List<AlgorithmInfo> algorithms, List<Slot> slots, List<String> unitStrings, MidiDevice? inputDevice, MidiDevice? outputDevice, bool loading, bool offline, Uint8List? screenshot, bool demo, VideoStreamState? videoStream, FirmwareRelease? availableFirmwareUpdate, List<PerformancePageItem> perfPageItems, bool isDirty, String? renameConfirmationName
});


$VideoStreamStateCopyWith<$Res>? get videoStream;$FirmwareReleaseCopyWith<$Res>? get availableFirmwareUpdate;

}
/// @nodoc
class _$DistingStateSynchronizedCopyWithImpl<$Res>
    implements $DistingStateSynchronizedCopyWith<$Res> {
  _$DistingStateSynchronizedCopyWithImpl(this._self, this._then);

  final DistingStateSynchronized _self;
  final $Res Function(DistingStateSynchronized) _then;

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? disting = null,Object? distingVersion = null,Object? firmwareVersion = null,Object? presetName = null,Object? algorithms = null,Object? slots = null,Object? unitStrings = null,Object? inputDevice = freezed,Object? outputDevice = freezed,Object? loading = null,Object? offline = null,Object? screenshot = freezed,Object? demo = null,Object? videoStream = freezed,Object? availableFirmwareUpdate = freezed,Object? perfPageItems = null,Object? isDirty = null,Object? renameConfirmationName = freezed,}) {
  return _then(DistingStateSynchronized(
disting: null == disting ? _self.disting : disting // ignore: cast_nullable_to_non_nullable
as IDistingMidiManager,distingVersion: null == distingVersion ? _self.distingVersion : distingVersion // ignore: cast_nullable_to_non_nullable
as String,firmwareVersion: null == firmwareVersion ? _self.firmwareVersion : firmwareVersion // ignore: cast_nullable_to_non_nullable
as FirmwareVersion,presetName: null == presetName ? _self.presetName : presetName // ignore: cast_nullable_to_non_nullable
as String,algorithms: null == algorithms ? _self._algorithms : algorithms // ignore: cast_nullable_to_non_nullable
as List<AlgorithmInfo>,slots: null == slots ? _self._slots : slots // ignore: cast_nullable_to_non_nullable
as List<Slot>,unitStrings: null == unitStrings ? _self._unitStrings : unitStrings // ignore: cast_nullable_to_non_nullable
as List<String>,inputDevice: freezed == inputDevice ? _self.inputDevice : inputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,outputDevice: freezed == outputDevice ? _self.outputDevice : outputDevice // ignore: cast_nullable_to_non_nullable
as MidiDevice?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,offline: null == offline ? _self.offline : offline // ignore: cast_nullable_to_non_nullable
as bool,screenshot: freezed == screenshot ? _self.screenshot : screenshot // ignore: cast_nullable_to_non_nullable
as Uint8List?,demo: null == demo ? _self.demo : demo // ignore: cast_nullable_to_non_nullable
as bool,videoStream: freezed == videoStream ? _self.videoStream : videoStream // ignore: cast_nullable_to_non_nullable
as VideoStreamState?,availableFirmwareUpdate: freezed == availableFirmwareUpdate ? _self.availableFirmwareUpdate : availableFirmwareUpdate // ignore: cast_nullable_to_non_nullable
as FirmwareRelease?,perfPageItems: null == perfPageItems ? _self._perfPageItems : perfPageItems // ignore: cast_nullable_to_non_nullable
as List<PerformancePageItem>,isDirty: null == isDirty ? _self.isDirty : isDirty // ignore: cast_nullable_to_non_nullable
as bool,renameConfirmationName: freezed == renameConfirmationName ? _self.renameConfirmationName : renameConfirmationName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$VideoStreamStateCopyWith<$Res>? get videoStream {
    if (_self.videoStream == null) {
    return null;
  }

  return $VideoStreamStateCopyWith<$Res>(_self.videoStream!, (value) {
    return _then(_self.copyWith(videoStream: value));
  });
}/// Create a copy of DistingState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FirmwareReleaseCopyWith<$Res>? get availableFirmwareUpdate {
    if (_self.availableFirmwareUpdate == null) {
    return null;
  }

  return $FirmwareReleaseCopyWith<$Res>(_self.availableFirmwareUpdate!, (value) {
    return _then(_self.copyWith(availableFirmwareUpdate: value));
  });
}
}

// dart format on
