// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routing_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoutingState {

/// Current status of the routing system
 RoutingSystemStatus get status;/// List of all available input ports
 List<Port> get inputPorts;/// List of all available output ports
 List<Port> get outputPorts;/// List of all active connections
 List<Connection> get connections;/// Optional error message if status is error
 String? get errorMessage;/// Timestamp when the state was created
 DateTime? get createdAt;/// Timestamp when the state was last updated
 DateTime? get lastUpdated;/// Whether the routing system is in read-only mode
 bool get isReadOnly;/// Configuration parameters for the routing system
 Map<String, dynamic>? get configuration;/// Additional metadata for the routing state
 Map<String, dynamic>? get metadata;
/// Create a copy of RoutingState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoutingStateCopyWith<RoutingState> get copyWith => _$RoutingStateCopyWithImpl<RoutingState>(this as RoutingState, _$identity);

  /// Serializes this RoutingState to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as RoutingState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoutingState&&(identical(other.status, _this.status) || other.status == _this.status)&&const DeepCollectionEquality().equals(other.inputPorts, _this.inputPorts)&&const DeepCollectionEquality().equals(other.outputPorts, _this.outputPorts)&&const DeepCollectionEquality().equals(other.connections, _this.connections)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.lastUpdated, _this.lastUpdated) || other.lastUpdated == _this.lastUpdated)&&(identical(other.isReadOnly, _this.isReadOnly) || other.isReadOnly == _this.isReadOnly)&&const DeepCollectionEquality().equals(other.configuration, _this.configuration)&&const DeepCollectionEquality().equals(other.metadata, _this.metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as RoutingState;
  return Object.hash(runtimeType,_this.status,const DeepCollectionEquality().hash(_this.inputPorts),const DeepCollectionEquality().hash(_this.outputPorts),const DeepCollectionEquality().hash(_this.connections),_this.errorMessage,_this.createdAt,_this.lastUpdated,_this.isReadOnly,const DeepCollectionEquality().hash(_this.configuration),const DeepCollectionEquality().hash(_this.metadata));
}

@override
String toString() {
  final _this = this as RoutingState;
  return 'RoutingState(status: ${_this.status}, inputPorts: ${_this.inputPorts}, outputPorts: ${_this.outputPorts}, connections: ${_this.connections}, errorMessage: ${_this.errorMessage}, createdAt: ${_this.createdAt}, lastUpdated: ${_this.lastUpdated}, isReadOnly: ${_this.isReadOnly}, configuration: ${_this.configuration}, metadata: ${_this.metadata})';
}


}

/// @nodoc
abstract mixin class $RoutingStateCopyWith<$Res>  {
  factory $RoutingStateCopyWith(RoutingState value, $Res Function(RoutingState) _then) = _$RoutingStateCopyWithImpl;
@useResult
$Res call({
 RoutingSystemStatus status, List<Port> inputPorts, List<Port> outputPorts, List<Connection> connections, String? errorMessage, DateTime? createdAt, DateTime? lastUpdated, bool isReadOnly, Map<String, dynamic>? configuration, Map<String, dynamic>? metadata
});




}
/// @nodoc
class _$RoutingStateCopyWithImpl<$Res>
    implements $RoutingStateCopyWith<$Res> {
  _$RoutingStateCopyWithImpl(this._self, this._then);

  final RoutingState _self;
  final $Res Function(RoutingState) _then;

/// Create a copy of RoutingState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? inputPorts = null,Object? outputPorts = null,Object? connections = null,Object? errorMessage = freezed,Object? createdAt = freezed,Object? lastUpdated = freezed,Object? isReadOnly = null,Object? configuration = freezed,Object? metadata = freezed,}) {
  return _then(RoutingState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutingSystemStatus,inputPorts: null == inputPorts ? _self.inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,outputPorts: null == outputPorts ? _self.outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,connections: null == connections ? _self.connections : connections // ignore: cast_nullable_to_non_nullable
as List<Connection>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastUpdated: freezed == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime?,isReadOnly: null == isReadOnly ? _self.isReadOnly : isReadOnly // ignore: cast_nullable_to_non_nullable
as bool,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,metadata: freezed == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoutingState].
extension RoutingStatePatterns on RoutingState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoutingState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoutingState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoutingState value)  $default,){
final _that = this;
switch (_that) {
case _RoutingState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoutingState value)?  $default,){
final _that = this;
switch (_that) {
case _RoutingState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RoutingSystemStatus status,  List<Port> inputPorts,  List<Port> outputPorts,  List<Connection> connections,  String? errorMessage,  DateTime? createdAt,  DateTime? lastUpdated,  bool isReadOnly,  Map<String, dynamic>? configuration,  Map<String, dynamic>? metadata)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoutingState() when $default != null:
return $default(_that.status,_that.inputPorts,_that.outputPorts,_that.connections,_that.errorMessage,_that.createdAt,_that.lastUpdated,_that.isReadOnly,_that.configuration,_that.metadata);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RoutingSystemStatus status,  List<Port> inputPorts,  List<Port> outputPorts,  List<Connection> connections,  String? errorMessage,  DateTime? createdAt,  DateTime? lastUpdated,  bool isReadOnly,  Map<String, dynamic>? configuration,  Map<String, dynamic>? metadata)  $default,) {final _that = this;
switch (_that) {
case _RoutingState():
return $default(_that.status,_that.inputPorts,_that.outputPorts,_that.connections,_that.errorMessage,_that.createdAt,_that.lastUpdated,_that.isReadOnly,_that.configuration,_that.metadata);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RoutingSystemStatus status,  List<Port> inputPorts,  List<Port> outputPorts,  List<Connection> connections,  String? errorMessage,  DateTime? createdAt,  DateTime? lastUpdated,  bool isReadOnly,  Map<String, dynamic>? configuration,  Map<String, dynamic>? metadata)?  $default,) {final _that = this;
switch (_that) {
case _RoutingState() when $default != null:
return $default(_that.status,_that.inputPorts,_that.outputPorts,_that.connections,_that.errorMessage,_that.createdAt,_that.lastUpdated,_that.isReadOnly,_that.configuration,_that.metadata);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoutingState extends RoutingState {
  const _RoutingState({this.status = RoutingSystemStatus.uninitialized,  List<Port> inputPorts = const [],  List<Port> outputPorts = const [],  List<Connection> connections = const [], this.errorMessage, this.createdAt, this.lastUpdated, this.isReadOnly = false,  Map<String, dynamic>? configuration,  Map<String, dynamic>? metadata}): _inputPorts = inputPorts,_outputPorts = outputPorts,_connections = connections,_configuration = configuration,_metadata = metadata,super._();
  factory _RoutingState.fromJson(Map<String, dynamic> json) => _$RoutingStateFromJson(json);

/// Current status of the routing system
@override@JsonKey() final  RoutingSystemStatus status;
/// List of all available input ports
 final  List<Port> _inputPorts;
/// List of all available input ports
@override@JsonKey() List<Port> get inputPorts {
  if (_inputPorts is EqualUnmodifiableListView) return _inputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_inputPorts);
}

/// List of all available output ports
 final  List<Port> _outputPorts;
/// List of all available output ports
@override@JsonKey() List<Port> get outputPorts {
  if (_outputPorts is EqualUnmodifiableListView) return _outputPorts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_outputPorts);
}

/// List of all active connections
 final  List<Connection> _connections;
/// List of all active connections
@override@JsonKey() List<Connection> get connections {
  if (_connections is EqualUnmodifiableListView) return _connections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_connections);
}

/// Optional error message if status is error
@override final  String? errorMessage;
/// Timestamp when the state was created
@override final  DateTime? createdAt;
/// Timestamp when the state was last updated
@override final  DateTime? lastUpdated;
/// Whether the routing system is in read-only mode
@override@JsonKey() final  bool isReadOnly;
/// Configuration parameters for the routing system
 final  Map<String, dynamic>? _configuration;
/// Configuration parameters for the routing system
@override Map<String, dynamic>? get configuration {
  final value = _configuration;
  if (value == null) return null;
  if (_configuration is EqualUnmodifiableMapView) return _configuration;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

/// Additional metadata for the routing state
 final  Map<String, dynamic>? _metadata;
/// Additional metadata for the routing state
@override Map<String, dynamic>? get metadata {
  final value = _metadata;
  if (value == null) return null;
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of RoutingState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoutingStateCopyWith<_RoutingState> get copyWith => __$RoutingStateCopyWithImpl<_RoutingState>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoutingStateToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoutingState&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.inputPorts, _inputPorts)&&const DeepCollectionEquality().equals(other.outputPorts, _outputPorts)&&const DeepCollectionEquality().equals(other.connections, _connections)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.isReadOnly, isReadOnly) || other.isReadOnly == isReadOnly)&&const DeepCollectionEquality().equals(other.configuration, _configuration)&&const DeepCollectionEquality().equals(other.metadata, _metadata));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,status,const DeepCollectionEquality().hash(_inputPorts),const DeepCollectionEquality().hash(_outputPorts),const DeepCollectionEquality().hash(_connections),errorMessage,createdAt,lastUpdated,isReadOnly,const DeepCollectionEquality().hash(_configuration),const DeepCollectionEquality().hash(_metadata));
}

@override
String toString() {
    return 'RoutingState(status: $status, inputPorts: $inputPorts, outputPorts: $outputPorts, connections: $connections, errorMessage: $errorMessage, createdAt: $createdAt, lastUpdated: $lastUpdated, isReadOnly: $isReadOnly, configuration: $configuration, metadata: $metadata)';
}


}

/// @nodoc
abstract mixin class _$RoutingStateCopyWith<$Res> implements $RoutingStateCopyWith<$Res> {
  factory _$RoutingStateCopyWith(_RoutingState value, $Res Function(_RoutingState) _then) = __$RoutingStateCopyWithImpl;
@override @useResult
$Res call({
 RoutingSystemStatus status, List<Port> inputPorts, List<Port> outputPorts, List<Connection> connections, String? errorMessage, DateTime? createdAt, DateTime? lastUpdated, bool isReadOnly, Map<String, dynamic>? configuration, Map<String, dynamic>? metadata
});




}
/// @nodoc
class __$RoutingStateCopyWithImpl<$Res>
    implements _$RoutingStateCopyWith<$Res> {
  __$RoutingStateCopyWithImpl(this._self, this._then);

  final _RoutingState _self;
  final $Res Function(_RoutingState) _then;

/// Create a copy of RoutingState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? inputPorts = null,Object? outputPorts = null,Object? connections = null,Object? errorMessage = freezed,Object? createdAt = freezed,Object? lastUpdated = freezed,Object? isReadOnly = null,Object? configuration = freezed,Object? metadata = freezed,}) {
  return _then(_RoutingState(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as RoutingSystemStatus,inputPorts: null == inputPorts ? _self._inputPorts : inputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,outputPorts: null == outputPorts ? _self._outputPorts : outputPorts // ignore: cast_nullable_to_non_nullable
as List<Port>,connections: null == connections ? _self._connections : connections // ignore: cast_nullable_to_non_nullable
as List<Connection>,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lastUpdated: freezed == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime?,isReadOnly: null == isReadOnly ? _self.isReadOnly : isReadOnly // ignore: cast_nullable_to_non_nullable
as bool,configuration: freezed == configuration ? _self._configuration : configuration // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,metadata: freezed == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,
  ));
}


}

// dart format on
