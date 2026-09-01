// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routing_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RoutingBus {

 String get id; String get name; BusStatus get status; List<String> get connectionIds; OutputMode get defaultOutputMode; double get masterGain; DateTime? get createdAt; DateTime? get modifiedAt;
/// Create a copy of RoutingBus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutingBusCopyWith<RoutingBus> get copyWith => _$RoutingBusCopyWithImpl<RoutingBus>(this as RoutingBus, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingBus&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.connectionIds, connectionIds)&&(identical(other.defaultOutputMode, defaultOutputMode) || other.defaultOutputMode == defaultOutputMode)&&(identical(other.masterGain, masterGain) || other.masterGain == masterGain)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,status,const DeepCollectionEquality().hash(connectionIds),defaultOutputMode,masterGain,createdAt,modifiedAt);

@override
String toString() {
  return 'RoutingBus(id: $id, name: $name, status: $status, connectionIds: $connectionIds, defaultOutputMode: $defaultOutputMode, masterGain: $masterGain, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class $RoutingBusCopyWith<$Res>  {
  factory $RoutingBusCopyWith(RoutingBus value, $Res Function(RoutingBus) _then) = _$RoutingBusCopyWithImpl;
@useResult
$Res call({
 String id, String name, BusStatus status, List<String> connectionIds, OutputMode defaultOutputMode, double masterGain, DateTime? createdAt, DateTime? modifiedAt
});




}
/// @nodoc
class _$RoutingBusCopyWithImpl<$Res>
    implements $RoutingBusCopyWith<$Res> {
  _$RoutingBusCopyWithImpl(this._self, this._then);

  final RoutingBus _self;
  final $Res Function(RoutingBus) _then;

/// Create a copy of RoutingBus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? status = null,Object? connectionIds = null,Object? defaultOutputMode = null,Object? masterGain = null,Object? createdAt = freezed,Object? modifiedAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BusStatus,connectionIds: null == connectionIds ? _self.connectionIds : connectionIds // ignore: cast_nullable_to_non_nullable
as List<String>,defaultOutputMode: null == defaultOutputMode ? _self.defaultOutputMode : defaultOutputMode // ignore: cast_nullable_to_non_nullable
as OutputMode,masterGain: null == masterGain ? _self.masterGain : masterGain // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,modifiedAt: freezed == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutingBus].
extension RoutingBusPatterns on RoutingBus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutingBus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutingBus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutingBus value)  $default,){
final _that = this;
switch (_that) {
case _RoutingBus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutingBus value)?  $default,){
final _that = this;
switch (_that) {
case _RoutingBus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  BusStatus status,  List<String> connectionIds,  OutputMode defaultOutputMode,  double masterGain,  DateTime? createdAt,  DateTime? modifiedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutingBus() when $default != null:
return $default(_that.id,_that.name,_that.status,_that.connectionIds,_that.defaultOutputMode,_that.masterGain,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  BusStatus status,  List<String> connectionIds,  OutputMode defaultOutputMode,  double masterGain,  DateTime? createdAt,  DateTime? modifiedAt)  $default,) {final _that = this;
switch (_that) {
case _RoutingBus():
return $default(_that.id,_that.name,_that.status,_that.connectionIds,_that.defaultOutputMode,_that.masterGain,_that.createdAt,_that.modifiedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  BusStatus status,  List<String> connectionIds,  OutputMode defaultOutputMode,  double masterGain,  DateTime? createdAt,  DateTime? modifiedAt)?  $default,) {final _that = this;
switch (_that) {
case _RoutingBus() when $default != null:
return $default(_that.id,_that.name,_that.status,_that.connectionIds,_that.defaultOutputMode,_that.masterGain,_that.createdAt,_that.modifiedAt);case _:
  return null;

}
}

}

/// @nodoc


class _RoutingBus implements RoutingBus {
  const _RoutingBus({required this.id, required this.name, required this.status, final  List<String> connectionIds = const [], this.defaultOutputMode = OutputMode.replace, this.masterGain = 1.0, this.createdAt, this.modifiedAt}): _connectionIds = connectionIds;
  

@override final  String id;
@override final  String name;
@override final  BusStatus status;
 final  List<String> _connectionIds;
@override@JsonKey() List<String> get connectionIds {
  if (_connectionIds is EqualUnmodifiableListView) return _connectionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_connectionIds);
}

@override@JsonKey() final  OutputMode defaultOutputMode;
@override@JsonKey() final  double masterGain;
@override final  DateTime? createdAt;
@override final  DateTime? modifiedAt;

/// Create a copy of RoutingBus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutingBusCopyWith<_RoutingBus> get copyWith => __$RoutingBusCopyWithImpl<_RoutingBus>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutingBus&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._connectionIds, _connectionIds)&&(identical(other.defaultOutputMode, defaultOutputMode) || other.defaultOutputMode == defaultOutputMode)&&(identical(other.masterGain, masterGain) || other.masterGain == masterGain)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,status,const DeepCollectionEquality().hash(_connectionIds),defaultOutputMode,masterGain,createdAt,modifiedAt);

@override
String toString() {
  return 'RoutingBus(id: $id, name: $name, status: $status, connectionIds: $connectionIds, defaultOutputMode: $defaultOutputMode, masterGain: $masterGain, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class _$RoutingBusCopyWith<$Res> implements $RoutingBusCopyWith<$Res> {
  factory _$RoutingBusCopyWith(_RoutingBus value, $Res Function(_RoutingBus) _then) = __$RoutingBusCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, BusStatus status, List<String> connectionIds, OutputMode defaultOutputMode, double masterGain, DateTime? createdAt, DateTime? modifiedAt
});




}
/// @nodoc
class __$RoutingBusCopyWithImpl<$Res>
    implements _$RoutingBusCopyWith<$Res> {
  __$RoutingBusCopyWithImpl(this._self, this._then);

  final _RoutingBus _self;
  final $Res Function(_RoutingBus) _then;

/// Create a copy of RoutingBus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? status = null,Object? connectionIds = null,Object? defaultOutputMode = null,Object? masterGain = null,Object? createdAt = freezed,Object? modifiedAt = freezed,}) {
  return _then(_RoutingBus(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BusStatus,connectionIds: null == connectionIds ? _self._connectionIds : connectionIds // ignore: cast_nullable_to_non_nullable
as List<String>,defaultOutputMode: null == defaultOutputMode ? _self.defaultOutputMode : defaultOutputMode // ignore: cast_nullable_to_non_nullable
as OutputMode,masterGain: null == masterGain ? _self.masterGain : masterGain // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,modifiedAt: freezed == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$RoutingAlgorithm {

/// Stable unique identifier for this algorithm instance
 String get id;/// Current slot index (0-7), can change when algorithms are reordered
 int get index;/// The algorithm definition
 Algorithm get algorithm;/// Input ports for this algorithm
 List<Port> get inputPorts;/// Output ports for this algorithm
 List<Port> get outputPorts;
/// Create a copy of RoutingAlgorithm
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutingAlgorithmCopyWith<RoutingAlgorithm> get copyWith => _$RoutingAlgorithmCopyWithImpl<RoutingAlgorithm>(this as RoutingAlgorithm, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingAlgorithm&&(identical(other.id, id) || other.id == id)&&(identical(other.index, index) || other.index == index)&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm)&&const DeepCollectionEquality().equals(other.inputPorts, inputPorts)&&const DeepCollectionEquality().equals(other.outputPorts, outputPorts));
}


@override
int get hashCode => Object.hash(runtimeType,id,index,algorithm,const DeepCollectionEquality().hash(inputPorts),const DeepCollectionEquality().hash(outputPorts));

@override
String toString() {
  return 'RoutingAlgorithm(id: $id, index: $index, algorithm: $algorithm, inputPorts: $inputPorts, outputPorts: $outputPorts)';
}


}

/// @nodoc
abstract mixin class $RoutingAlgorithmCopyWith<$Res>  {
  factory $RoutingAlgorithmCopyWith(RoutingAlgorithm value, $Res Function(RoutingAlgorithm) _then) = _$RoutingAlgorithmCopyWithImpl;
@useResult
$Res call({
 String id, int index, Algorithm algorithm, List<Port> inputPorts, List<Port> outputPorts
});




}
/// @nodoc
class _$RoutingAlgorithmCopyWithImpl<$Res>
    implements $RoutingAlgorithmCopyWith<$Res> {
  _$RoutingAlgorithmCopyWithImpl(this._self, this._then);

  final RoutingAlgorithm _self;
  final $Res Function(RoutingAlgorithm) _then;

/// Create a copy of RoutingAlgorithm
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? index = null,Object? algorithm = null,Object? inputPorts = null,Object? outputPorts = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,inputPorts: null == inputPorts ? _self.inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,outputPorts: null == outputPorts ? _self.outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutingAlgorithm].
extension RoutingAlgorithmPatterns on RoutingAlgorithm {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutingAlgorithm value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutingAlgorithm() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutingAlgorithm value)  $default,){
final _that = this;
switch (_that) {
case _RoutingAlgorithm():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutingAlgorithm value)?  $default,){
final _that = this;
switch (_that) {
case _RoutingAlgorithm() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int index,  Algorithm algorithm,  List<Port> inputPorts,  List<Port> outputPorts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutingAlgorithm() when $default != null:
return $default(_that.id,_that.index,_that.algorithm,_that.inputPorts,_that.outputPorts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int index,  Algorithm algorithm,  List<Port> inputPorts,  List<Port> outputPorts)  $default,) {final _that = this;
switch (_that) {
case _RoutingAlgorithm():
return $default(_that.id,_that.index,_that.algorithm,_that.inputPorts,_that.outputPorts);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int index,  Algorithm algorithm,  List<Port> inputPorts,  List<Port> outputPorts)?  $default,) {final _that = this;
switch (_that) {
case _RoutingAlgorithm() when $default != null:
return $default(_that.id,_that.index,_that.algorithm,_that.inputPorts,_that.outputPorts);case _:
  return null;

}
}

}

/// @nodoc


class _RoutingAlgorithm implements RoutingAlgorithm {
  const _RoutingAlgorithm({required this.id, required this.index, required this.algorithm, required final  List<Port> inputPorts, required final  List<Port> outputPorts}): _inputPorts = inputPorts,_outputPorts = outputPorts;
  

/// Stable unique identifier for this algorithm instance
@override final  String id;
/// Current slot index (0-7), can change when algorithms are reordered
@override final  int index;
/// The algorithm definition
@override final  Algorithm algorithm;
/// Input ports for this algorithm
 final  List<Port> _inputPorts;
/// Input ports for this algorithm
@override List<Port> get inputPorts {
  if (_inputPorts is EqualUnmodifiableListView) return _inputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_inputPorts);
}

/// Output ports for this algorithm
 final  List<Port> _outputPorts;
/// Output ports for this algorithm
@override List<Port> get outputPorts {
  if (_outputPorts is EqualUnmodifiableListView) return _outputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputPorts);
}


/// Create a copy of RoutingAlgorithm
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutingAlgorithmCopyWith<_RoutingAlgorithm> get copyWith => __$RoutingAlgorithmCopyWithImpl<_RoutingAlgorithm>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutingAlgorithm&&(identical(other.id, id) || other.id == id)&&(identical(other.index, index) || other.index == index)&&(identical(other.algorithm, algorithm) || other.algorithm == algorithm)&&const DeepCollectionEquality().equals(other._inputPorts, _inputPorts)&&const DeepCollectionEquality().equals(other._outputPorts, _outputPorts));
}


@override
int get hashCode => Object.hash(runtimeType,id,index,algorithm,const DeepCollectionEquality().hash(_inputPorts),const DeepCollectionEquality().hash(_outputPorts));

@override
String toString() {
  return 'RoutingAlgorithm(id: $id, index: $index, algorithm: $algorithm, inputPorts: $inputPorts, outputPorts: $outputPorts)';
}


}

/// @nodoc
abstract mixin class _$RoutingAlgorithmCopyWith<$Res> implements $RoutingAlgorithmCopyWith<$Res> {
  factory _$RoutingAlgorithmCopyWith(_RoutingAlgorithm value, $Res Function(_RoutingAlgorithm) _then) = __$RoutingAlgorithmCopyWithImpl;
@override @useResult
$Res call({
 String id, int index, Algorithm algorithm, List<Port> inputPorts, List<Port> outputPorts
});




}
/// @nodoc
class __$RoutingAlgorithmCopyWithImpl<$Res>
    implements _$RoutingAlgorithmCopyWith<$Res> {
  __$RoutingAlgorithmCopyWithImpl(this._self, this._then);

  final _RoutingAlgorithm _self;
  final $Res Function(_RoutingAlgorithm) _then;

/// Create a copy of RoutingAlgorithm
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? index = null,Object? algorithm = null,Object? inputPorts = null,Object? outputPorts = null,}) {
  return _then(_RoutingAlgorithm(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,algorithm: null == algorithm ? _self.algorithm : algorithm // ignore: cast_nullable_to_non_nullable
as Algorithm,inputPorts: null == inputPorts ? _self._inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,outputPorts: null == outputPorts ? _self._outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,
  ));
}


}

/// @nodoc
mixin _$RoutingEditorState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingEditorState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RoutingEditorState()';
}


}

/// @nodoc
class $RoutingEditorStateCopyWith<$Res>  {
$RoutingEditorStateCopyWith(RoutingEditorState _, $Res Function(RoutingEditorState) __);
}


/// Adds pattern-matching-related methods to [RoutingEditorState].
extension RoutingEditorStatePatterns on RoutingEditorState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RoutingEditorStateInitial value)?  initial,TResult Function( RoutingEditorStateDisconnected value)?  disconnected,TResult Function( RoutingEditorStateLoaded value)?  loaded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RoutingEditorStateInitial() when initial != null:
return initial(_that);case RoutingEditorStateDisconnected() when disconnected != null:
return disconnected(_that);case RoutingEditorStateLoaded() when loaded != null:
return loaded(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RoutingEditorStateInitial value)  initial,required TResult Function( RoutingEditorStateDisconnected value)  disconnected,required TResult Function( RoutingEditorStateLoaded value)  loaded,}){
final _that = this;
switch (_that) {
case RoutingEditorStateInitial():
return initial(_that);case RoutingEditorStateDisconnected():
return disconnected(_that);case RoutingEditorStateLoaded():
return loaded(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RoutingEditorStateInitial value)?  initial,TResult? Function( RoutingEditorStateDisconnected value)?  disconnected,TResult? Function( RoutingEditorStateLoaded value)?  loaded,}){
final _that = this;
switch (_that) {
case RoutingEditorStateInitial() when initial != null:
return initial(_that);case RoutingEditorStateDisconnected() when disconnected != null:
return disconnected(_that);case RoutingEditorStateLoaded() when loaded != null:
return loaded(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function()?  disconnected,TResult Function( DeviceIoProfile deviceIoProfile,  List<Port> physicalInputs,  List<Port> physicalOutputs,  List<Port> es5Inputs,  List<RoutingAlgorithm> algorithms,  List<Connection> connections,  List<RoutingBus> buses,  Map<String, OutputMode> portOutputModes,  Map<String, NodePosition> nodePositions,  double zoomLevel,  Offset panOffset,  bool isHardwareSynced,  bool isPersistenceEnabled,  DateTime? lastSyncTime,  DateTime? lastPersistTime,  String? lastError,  SubState subState,  Set<String> focusedAlgorithmIds,  Offset? cascadeScrollTarget,  Map<int, AuxBusUsageInfo> auxBusUsage,  bool hasExtendedAuxBuses)?  loaded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RoutingEditorStateInitial() when initial != null:
return initial();case RoutingEditorStateDisconnected() when disconnected != null:
return disconnected();case RoutingEditorStateLoaded() when loaded != null:
return loaded(_that.deviceIoProfile,_that.physicalInputs,_that.physicalOutputs,_that.es5Inputs,_that.algorithms,_that.connections,_that.buses,_that.portOutputModes,_that.nodePositions,_that.zoomLevel,_that.panOffset,_that.isHardwareSynced,_that.isPersistenceEnabled,_that.lastSyncTime,_that.lastPersistTime,_that.lastError,_that.subState,_that.focusedAlgorithmIds,_that.cascadeScrollTarget,_that.auxBusUsage,_that.hasExtendedAuxBuses);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function()  disconnected,required TResult Function( DeviceIoProfile deviceIoProfile,  List<Port> physicalInputs,  List<Port> physicalOutputs,  List<Port> es5Inputs,  List<RoutingAlgorithm> algorithms,  List<Connection> connections,  List<RoutingBus> buses,  Map<String, OutputMode> portOutputModes,  Map<String, NodePosition> nodePositions,  double zoomLevel,  Offset panOffset,  bool isHardwareSynced,  bool isPersistenceEnabled,  DateTime? lastSyncTime,  DateTime? lastPersistTime,  String? lastError,  SubState subState,  Set<String> focusedAlgorithmIds,  Offset? cascadeScrollTarget,  Map<int, AuxBusUsageInfo> auxBusUsage,  bool hasExtendedAuxBuses)  loaded,}) {final _that = this;
switch (_that) {
case RoutingEditorStateInitial():
return initial();case RoutingEditorStateDisconnected():
return disconnected();case RoutingEditorStateLoaded():
return loaded(_that.deviceIoProfile,_that.physicalInputs,_that.physicalOutputs,_that.es5Inputs,_that.algorithms,_that.connections,_that.buses,_that.portOutputModes,_that.nodePositions,_that.zoomLevel,_that.panOffset,_that.isHardwareSynced,_that.isPersistenceEnabled,_that.lastSyncTime,_that.lastPersistTime,_that.lastError,_that.subState,_that.focusedAlgorithmIds,_that.cascadeScrollTarget,_that.auxBusUsage,_that.hasExtendedAuxBuses);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function()?  disconnected,TResult? Function( DeviceIoProfile deviceIoProfile,  List<Port> physicalInputs,  List<Port> physicalOutputs,  List<Port> es5Inputs,  List<RoutingAlgorithm> algorithms,  List<Connection> connections,  List<RoutingBus> buses,  Map<String, OutputMode> portOutputModes,  Map<String, NodePosition> nodePositions,  double zoomLevel,  Offset panOffset,  bool isHardwareSynced,  bool isPersistenceEnabled,  DateTime? lastSyncTime,  DateTime? lastPersistTime,  String? lastError,  SubState subState,  Set<String> focusedAlgorithmIds,  Offset? cascadeScrollTarget,  Map<int, AuxBusUsageInfo> auxBusUsage,  bool hasExtendedAuxBuses)?  loaded,}) {final _that = this;
switch (_that) {
case RoutingEditorStateInitial() when initial != null:
return initial();case RoutingEditorStateDisconnected() when disconnected != null:
return disconnected();case RoutingEditorStateLoaded() when loaded != null:
return loaded(_that.deviceIoProfile,_that.physicalInputs,_that.physicalOutputs,_that.es5Inputs,_that.algorithms,_that.connections,_that.buses,_that.portOutputModes,_that.nodePositions,_that.zoomLevel,_that.panOffset,_that.isHardwareSynced,_that.isPersistenceEnabled,_that.lastSyncTime,_that.lastPersistTime,_that.lastError,_that.subState,_that.focusedAlgorithmIds,_that.cascadeScrollTarget,_that.auxBusUsage,_that.hasExtendedAuxBuses);case _:
  return null;

}
}

}

/// @nodoc


class RoutingEditorStateInitial implements RoutingEditorState {
  const RoutingEditorStateInitial();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingEditorStateInitial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RoutingEditorState.initial()';
}


}




/// @nodoc


class RoutingEditorStateDisconnected implements RoutingEditorState {
  const RoutingEditorStateDisconnected();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingEditorStateDisconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RoutingEditorState.disconnected()';
}


}




/// @nodoc


class RoutingEditorStateLoaded implements RoutingEditorState {
  const RoutingEditorStateLoaded({this.deviceIoProfile = DeviceIoProfile.distingExtended, required final  List<Port> physicalInputs, required final  List<Port> physicalOutputs, final  List<Port> es5Inputs = const [], required final  List<RoutingAlgorithm> algorithms, required final  List<Connection> connections, final  List<RoutingBus> buses = const [], final  Map<String, OutputMode> portOutputModes = const {}, final  Map<String, NodePosition> nodePositions = const {}, this.zoomLevel = 1.0, this.panOffset = Offset.zero, this.isHardwareSynced = false, this.isPersistenceEnabled = false, this.lastSyncTime, this.lastPersistTime, this.lastError, this.subState = SubState.idle, final  Set<String> focusedAlgorithmIds = const {}, this.cascadeScrollTarget, final  Map<int, AuxBusUsageInfo> auxBusUsage = const {}, this.hasExtendedAuxBuses = false}): _physicalInputs = physicalInputs,_physicalOutputs = physicalOutputs,_es5Inputs = es5Inputs,_algorithms = algorithms,_connections = connections,_buses = buses,_portOutputModes = portOutputModes,_nodePositions = nodePositions,_focusedAlgorithmIds = focusedAlgorithmIds,_auxBusUsage = auxBusUsage;
  

@JsonKey() final  DeviceIoProfile deviceIoProfile;
 final  List<Port> _physicalInputs;
 List<Port> get physicalInputs {
  if (_physicalInputs is EqualUnmodifiableListView) return _physicalInputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_physicalInputs);
}

// 12 physical input ports
 final  List<Port> _physicalOutputs;
// 12 physical input ports
 List<Port> get physicalOutputs {
  if (_physicalOutputs is EqualUnmodifiableListView) return _physicalOutputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_physicalOutputs);
}

// 8 physical output ports
 final  List<Port> _es5Inputs;
// 8 physical output ports
@JsonKey() List<Port> get es5Inputs {
  if (_es5Inputs is EqualUnmodifiableListView) return _es5Inputs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_es5Inputs);
}

// ES-5 expander input ports (conditional)
 final  List<RoutingAlgorithm> _algorithms;
// ES-5 expander input ports (conditional)
 List<RoutingAlgorithm> get algorithms {
  if (_algorithms is EqualUnmodifiableListView) return _algorithms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_algorithms);
}

// Algorithms with their ports
 final  List<Connection> _connections;
// Algorithms with their ports
 List<Connection> get connections {
  if (_connections is EqualUnmodifiableListView) return _connections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_connections);
}

// All routing connections
 final  List<RoutingBus> _buses;
// All routing connections
@JsonKey() List<RoutingBus> get buses {
  if (_buses is EqualUnmodifiableListView) return _buses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_buses);
}

// Available routing buses
 final  Map<String, OutputMode> _portOutputModes;
// Available routing buses
@JsonKey() Map<String, OutputMode> get portOutputModes {
  if (_portOutputModes is EqualUnmodifiableMapView) return _portOutputModes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_portOutputModes);
}

// Output modes per port
 final  Map<String, NodePosition> _nodePositions;
// Output modes per port
@JsonKey() Map<String, NodePosition> get nodePositions {
  if (_nodePositions is EqualUnmodifiableMapView) return _nodePositions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_nodePositions);
}

// Node positions for layout
@JsonKey() final  double zoomLevel;
// Current zoom level (1.0 = 100%)
@JsonKey() final  Offset panOffset;
// Current pan offset
@JsonKey() final  bool isHardwareSynced;
// Hardware sync status
@JsonKey() final  bool isPersistenceEnabled;
// State persistence status
 final  DateTime? lastSyncTime;
// Last hardware sync timestamp
 final  DateTime? lastPersistTime;
// Last persistence save timestamp
 final  String? lastError;
// Last error message
@JsonKey() final  SubState subState;
// Current sub-state
 final  Set<String> _focusedAlgorithmIds;
// Current sub-state
@JsonKey() Set<String> get focusedAlgorithmIds {
  if (_focusedAlgorithmIds is EqualUnmodifiableSetView) return _focusedAlgorithmIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_focusedAlgorithmIds);
}

// IDs of algorithms in focus mode
 final  Offset? cascadeScrollTarget;
// Target position to scroll to after cascade layout
 final  Map<int, AuxBusUsageInfo> _auxBusUsage;
// Target position to scroll to after cascade layout
@JsonKey() Map<int, AuxBusUsageInfo> get auxBusUsage {
  if (_auxBusUsage is EqualUnmodifiableMapView) return _auxBusUsage;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_auxBusUsage);
}

// Per-AUX-bus usage info
@JsonKey() final  bool hasExtendedAuxBuses;

/// Create a copy of RoutingEditorState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutingEditorStateLoadedCopyWith<RoutingEditorStateLoaded> get copyWith => _$RoutingEditorStateLoadedCopyWithImpl<RoutingEditorStateLoaded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingEditorStateLoaded&&(identical(other.deviceIoProfile, deviceIoProfile) || other.deviceIoProfile == deviceIoProfile)&&const DeepCollectionEquality().equals(other._physicalInputs, _physicalInputs)&&const DeepCollectionEquality().equals(other._physicalOutputs, _physicalOutputs)&&const DeepCollectionEquality().equals(other._es5Inputs, _es5Inputs)&&const DeepCollectionEquality().equals(other._algorithms, _algorithms)&&const DeepCollectionEquality().equals(other._connections, _connections)&&const DeepCollectionEquality().equals(other._buses, _buses)&&const DeepCollectionEquality().equals(other._portOutputModes, _portOutputModes)&&const DeepCollectionEquality().equals(other._nodePositions, _nodePositions)&&(identical(other.zoomLevel, zoomLevel) || other.zoomLevel == zoomLevel)&&(identical(other.panOffset, panOffset) || other.panOffset == panOffset)&&(identical(other.isHardwareSynced, isHardwareSynced) || other.isHardwareSynced == isHardwareSynced)&&(identical(other.isPersistenceEnabled, isPersistenceEnabled) || other.isPersistenceEnabled == isPersistenceEnabled)&&(identical(other.lastSyncTime, lastSyncTime) || other.lastSyncTime == lastSyncTime)&&(identical(other.lastPersistTime, lastPersistTime) || other.lastPersistTime == lastPersistTime)&&(identical(other.lastError, lastError) || other.lastError == lastError)&&(identical(other.subState, subState) || other.subState == subState)&&const DeepCollectionEquality().equals(other._focusedAlgorithmIds, _focusedAlgorithmIds)&&(identical(other.cascadeScrollTarget, cascadeScrollTarget) || other.cascadeScrollTarget == cascadeScrollTarget)&&const DeepCollectionEquality().equals(other._auxBusUsage, _auxBusUsage)&&(identical(other.hasExtendedAuxBuses, hasExtendedAuxBuses) || other.hasExtendedAuxBuses == hasExtendedAuxBuses));
}


@override
int get hashCode => Object.hashAll([runtimeType,deviceIoProfile,const DeepCollectionEquality().hash(_physicalInputs),const DeepCollectionEquality().hash(_physicalOutputs),const DeepCollectionEquality().hash(_es5Inputs),const DeepCollectionEquality().hash(_algorithms),const DeepCollectionEquality().hash(_connections),const DeepCollectionEquality().hash(_buses),const DeepCollectionEquality().hash(_portOutputModes),const DeepCollectionEquality().hash(_nodePositions),zoomLevel,panOffset,isHardwareSynced,isPersistenceEnabled,lastSyncTime,lastPersistTime,lastError,subState,const DeepCollectionEquality().hash(_focusedAlgorithmIds),cascadeScrollTarget,const DeepCollectionEquality().hash(_auxBusUsage),hasExtendedAuxBuses]);

@override
String toString() {
  return 'RoutingEditorState.loaded(deviceIoProfile: $deviceIoProfile, physicalInputs: $physicalInputs, physicalOutputs: $physicalOutputs, es5Inputs: $es5Inputs, algorithms: $algorithms, connections: $connections, buses: $buses, portOutputModes: $portOutputModes, nodePositions: $nodePositions, zoomLevel: $zoomLevel, panOffset: $panOffset, isHardwareSynced: $isHardwareSynced, isPersistenceEnabled: $isPersistenceEnabled, lastSyncTime: $lastSyncTime, lastPersistTime: $lastPersistTime, lastError: $lastError, subState: $subState, focusedAlgorithmIds: $focusedAlgorithmIds, cascadeScrollTarget: $cascadeScrollTarget, auxBusUsage: $auxBusUsage, hasExtendedAuxBuses: $hasExtendedAuxBuses)';
}


}

/// @nodoc
abstract mixin class $RoutingEditorStateLoadedCopyWith<$Res> implements $RoutingEditorStateCopyWith<$Res> {
  factory $RoutingEditorStateLoadedCopyWith(RoutingEditorStateLoaded value, $Res Function(RoutingEditorStateLoaded) _then) = _$RoutingEditorStateLoadedCopyWithImpl;
@useResult
$Res call({
 DeviceIoProfile deviceIoProfile, List<Port> physicalInputs, List<Port> physicalOutputs, List<Port> es5Inputs, List<RoutingAlgorithm> algorithms, List<Connection> connections, List<RoutingBus> buses, Map<String, OutputMode> portOutputModes, Map<String, NodePosition> nodePositions, double zoomLevel, Offset panOffset, bool isHardwareSynced, bool isPersistenceEnabled, DateTime? lastSyncTime, DateTime? lastPersistTime, String? lastError, SubState subState, Set<String> focusedAlgorithmIds, Offset? cascadeScrollTarget, Map<int, AuxBusUsageInfo> auxBusUsage, bool hasExtendedAuxBuses
});




}
/// @nodoc
class _$RoutingEditorStateLoadedCopyWithImpl<$Res>
    implements $RoutingEditorStateLoadedCopyWith<$Res> {
  _$RoutingEditorStateLoadedCopyWithImpl(this._self, this._then);

  final RoutingEditorStateLoaded _self;
  final $Res Function(RoutingEditorStateLoaded) _then;

/// Create a copy of RoutingEditorState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceIoProfile = null,Object? physicalInputs = null,Object? physicalOutputs = null,Object? es5Inputs = null,Object? algorithms = null,Object? connections = null,Object? buses = null,Object? portOutputModes = null,Object? nodePositions = null,Object? zoomLevel = null,Object? panOffset = null,Object? isHardwareSynced = null,Object? isPersistenceEnabled = null,Object? lastSyncTime = freezed,Object? lastPersistTime = freezed,Object? lastError = freezed,Object? subState = null,Object? focusedAlgorithmIds = null,Object? cascadeScrollTarget = freezed,Object? auxBusUsage = null,Object? hasExtendedAuxBuses = null,}) {
  return _then(RoutingEditorStateLoaded(
deviceIoProfile: null == deviceIoProfile ? _self.deviceIoProfile : deviceIoProfile // ignore: cast_nullable_to_non_nullable
as DeviceIoProfile,physicalInputs: null == physicalInputs ? _self._physicalInputs : physicalInputs // ignore: cast_nullable_to_non_nullable
as List<Port>,physicalOutputs: null == physicalOutputs ? _self._physicalOutputs : physicalOutputs // ignore: cast_nullable_to_non_nullable
as List<Port>,es5Inputs: null == es5Inputs ? _self._es5Inputs : es5Inputs // ignore: cast_nullable_to_non_nullable
as List<Port>,algorithms: null == algorithms ? _self._algorithms : algorithms // ignore: cast_nullable_to_non_nullable
as List<RoutingAlgorithm>,connections: null == connections ? _self._connections : connections // ignore: cast_nullable_to_non_nullable
as List<Connection>,buses: null == buses ? _self._buses : buses // ignore: cast_nullable_to_non_nullable
as List<RoutingBus>,portOutputModes: null == portOutputModes ? _self._portOutputModes : portOutputModes // ignore: cast_nullable_to_non_nullable
as Map<String, OutputMode>,nodePositions: null == nodePositions ? _self._nodePositions : nodePositions // ignore: cast_nullable_to_non_nullable
as Map<String, NodePosition>,zoomLevel: null == zoomLevel ? _self.zoomLevel : zoomLevel // ignore: cast_nullable_to_non_nullable
as double,panOffset: null == panOffset ? _self.panOffset : panOffset // ignore: cast_nullable_to_non_nullable
as Offset,isHardwareSynced: null == isHardwareSynced ? _self.isHardwareSynced : isHardwareSynced // ignore: cast_nullable_to_non_nullable
as bool,isPersistenceEnabled: null == isPersistenceEnabled ? _self.isPersistenceEnabled : isPersistenceEnabled // ignore: cast_nullable_to_non_nullable
as bool,lastSyncTime: freezed == lastSyncTime ? _self.lastSyncTime : lastSyncTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastPersistTime: freezed == lastPersistTime ? _self.lastPersistTime : lastPersistTime // ignore: cast_nullable_to_non_nullable
as DateTime?,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,subState: null == subState ? _self.subState : subState // ignore: cast_nullable_to_non_nullable
as SubState,focusedAlgorithmIds: null == focusedAlgorithmIds ? _self._focusedAlgorithmIds : focusedAlgorithmIds // ignore: cast_nullable_to_non_nullable
as Set<String>,cascadeScrollTarget: freezed == cascadeScrollTarget ? _self.cascadeScrollTarget : cascadeScrollTarget // ignore: cast_nullable_to_non_nullable
as Offset?,auxBusUsage: null == auxBusUsage ? _self._auxBusUsage : auxBusUsage // ignore: cast_nullable_to_non_nullable
as Map<int, AuxBusUsageInfo>,hasExtendedAuxBuses: null == hasExtendedAuxBuses ? _self.hasExtendedAuxBuses : hasExtendedAuxBuses // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
