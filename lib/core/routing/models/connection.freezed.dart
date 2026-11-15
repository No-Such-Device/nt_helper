// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Connection {

/// Unique identifier for this connection
 String get id;/// ID of the source port
 String get sourcePortId;/// ID of the destination port
 String get destinationPortId;/// Type of connection
 ConnectionType get connectionType;/// Current status of the connection
 ConnectionStatus get status;/// Whether this is a partial connection (one endpoint is a bus without match)
 bool get isPartial;/// Bus number for connections (1-12 for inputs, 13-20 for outputs, 21+ for algorithm buses)
 int? get busNumber;/// Optional bus ID for UI routing buses
 String? get busId;/// Bus label for rendering (e.g., "A1", "Out3")
 String? get busLabel;/// Algorithm identifier for the connection
 String? get algorithmId;/// Algorithm slot index (0-7)
 int? get algorithmIndex;/// Parameter number for the port
 int? get parameterNumber;/// Parameter name
 String? get parameterName;/// Name of the port
 String? get portName;/// Type of signal carried by this connection
 SignalType? get signalType;/// Whether this is an output connection
 bool get isOutput;/// Whether this is a backward edge (for algorithm connections)
 bool get isBackwardEdge;/// Output mode for the source port (add or replace)
 OutputMode? get outputMode;/// Optional name for the connection
 String? get name;/// Optional description of what this connection does
 String? get description;/// Signal gain/attenuation factor (1.0 = no change)
 double get gain;/// Whether the connection is muted
 bool get isMuted;/// Whether this is a ghost connection (for UI visualization)
 bool get isGhostConnection;/// Whether the connection is inverted
 bool get isInverted;/// Optional delay in milliseconds
 double get delayMs;/// Timestamp when the connection was created
 DateTime? get createdAt;/// Timestamp when the connection was last modified
 DateTime? get modifiedAt;
/// Create a copy of Connection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConnectionCopyWith<Connection> get copyWith => _$ConnectionCopyWithImpl<Connection>(this as Connection, _$identity);

  /// Serializes this Connection to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Connection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Connection&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sourcePortId, _this.sourcePortId) || other.sourcePortId == _this.sourcePortId)&&(identical(other.destinationPortId, _this.destinationPortId) || other.destinationPortId == _this.destinationPortId)&&(identical(other.connectionType, _this.connectionType) || other.connectionType == _this.connectionType)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.isPartial, _this.isPartial) || other.isPartial == _this.isPartial)&&(identical(other.busNumber, _this.busNumber) || other.busNumber == _this.busNumber)&&(identical(other.busId, _this.busId) || other.busId == _this.busId)&&(identical(other.busLabel, _this.busLabel) || other.busLabel == _this.busLabel)&&(identical(other.algorithmId, _this.algorithmId) || other.algorithmId == _this.algorithmId)&&(identical(other.algorithmIndex, _this.algorithmIndex) || other.algorithmIndex == _this.algorithmIndex)&&(identical(other.parameterNumber, _this.parameterNumber) || other.parameterNumber == _this.parameterNumber)&&(identical(other.parameterName, _this.parameterName) || other.parameterName == _this.parameterName)&&(identical(other.portName, _this.portName) || other.portName == _this.portName)&&(identical(other.signalType, _this.signalType) || other.signalType == _this.signalType)&&(identical(other.isOutput, _this.isOutput) || other.isOutput == _this.isOutput)&&(identical(other.isBackwardEdge, _this.isBackwardEdge) || other.isBackwardEdge == _this.isBackwardEdge)&&(identical(other.outputMode, _this.outputMode) || other.outputMode == _this.outputMode)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.gain, _this.gain) || other.gain == _this.gain)&&(identical(other.isMuted, _this.isMuted) || other.isMuted == _this.isMuted)&&(identical(other.isGhostConnection, _this.isGhostConnection) || other.isGhostConnection == _this.isGhostConnection)&&(identical(other.isInverted, _this.isInverted) || other.isInverted == _this.isInverted)&&(identical(other.delayMs, _this.delayMs) || other.delayMs == _this.delayMs)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.modifiedAt, _this.modifiedAt) || other.modifiedAt == _this.modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Connection;
  return Object.hashAll([runtimeType,_this.id,_this.sourcePortId,_this.destinationPortId,_this.connectionType,_this.status,_this.isPartial,_this.busNumber,_this.busId,_this.busLabel,_this.algorithmId,_this.algorithmIndex,_this.parameterNumber,_this.parameterName,_this.portName,_this.signalType,_this.isOutput,_this.isBackwardEdge,_this.outputMode,_this.name,_this.description,_this.gain,_this.isMuted,_this.isGhostConnection,_this.isInverted,_this.delayMs,_this.createdAt,_this.modifiedAt]);
}

@override
String toString() {
  final _this = this as Connection;
  return 'Connection(id: ${_this.id}, sourcePortId: ${_this.sourcePortId}, destinationPortId: ${_this.destinationPortId}, connectionType: ${_this.connectionType}, status: ${_this.status}, isPartial: ${_this.isPartial}, busNumber: ${_this.busNumber}, busId: ${_this.busId}, busLabel: ${_this.busLabel}, algorithmId: ${_this.algorithmId}, algorithmIndex: ${_this.algorithmIndex}, parameterNumber: ${_this.parameterNumber}, parameterName: ${_this.parameterName}, portName: ${_this.portName}, signalType: ${_this.signalType}, isOutput: ${_this.isOutput}, isBackwardEdge: ${_this.isBackwardEdge}, outputMode: ${_this.outputMode}, name: ${_this.name}, description: ${_this.description}, gain: ${_this.gain}, isMuted: ${_this.isMuted}, isGhostConnection: ${_this.isGhostConnection}, isInverted: ${_this.isInverted}, delayMs: ${_this.delayMs}, createdAt: ${_this.createdAt}, modifiedAt: ${_this.modifiedAt})';
}


}

/// @nodoc
abstract mixin class $ConnectionCopyWith<$Res>  {
  factory $ConnectionCopyWith(Connection value, $Res Function(Connection) _then) = _$ConnectionCopyWithImpl;
@useResult
$Res call({
 String id, String sourcePortId, String destinationPortId, ConnectionType connectionType, ConnectionStatus status, bool isPartial, int? busNumber, String? busId, String? busLabel, String? algorithmId, int? algorithmIndex, int? parameterNumber, String? parameterName, String? portName, SignalType? signalType, bool isOutput, bool isBackwardEdge, OutputMode? outputMode, String? name, String? description, double gain, bool isMuted, bool isGhostConnection, bool isInverted, double delayMs, DateTime? createdAt, DateTime? modifiedAt
});




}
/// @nodoc
class _$ConnectionCopyWithImpl<$Res>
    implements $ConnectionCopyWith<$Res> {
  _$ConnectionCopyWithImpl(this._self, this._then);

  final Connection _self;
  final $Res Function(Connection) _then;

/// Create a copy of Connection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sourcePortId = null,Object? destinationPortId = null,Object? connectionType = null,Object? status = null,Object? isPartial = null,Object? busNumber = freezed,Object? busId = freezed,Object? busLabel = freezed,Object? algorithmId = freezed,Object? algorithmIndex = freezed,Object? parameterNumber = freezed,Object? parameterName = freezed,Object? portName = freezed,Object? signalType = freezed,Object? isOutput = null,Object? isBackwardEdge = null,Object? outputMode = freezed,Object? name = freezed,Object? description = freezed,Object? gain = null,Object? isMuted = null,Object? isGhostConnection = null,Object? isInverted = null,Object? delayMs = null,Object? createdAt = freezed,Object? modifiedAt = freezed,}) {
  return _then(Connection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,destinationPortId: null == destinationPortId ? _self.destinationPortId : destinationPortId // ignore: cast_nullable_to_non_nullable
as String,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as ConnectionType,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConnectionStatus,isPartial: null == isPartial ? _self.isPartial : isPartial // ignore: cast_nullable_to_non_nullable
as bool,busNumber: freezed == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int?,busId: freezed == busId ? _self.busId : busId // ignore: cast_nullable_to_non_nullable
as String?,busLabel: freezed == busLabel ? _self.busLabel : busLabel // ignore: cast_nullable_to_non_nullable
as String?,algorithmId: freezed == algorithmId ? _self.algorithmId : algorithmId // ignore: cast_nullable_to_non_nullable
as String?,algorithmIndex: freezed == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int?,parameterNumber: freezed == parameterNumber ? _self.parameterNumber : parameterNumber // ignore: cast_nullable_to_non_nullable
as int?,parameterName: freezed == parameterName ? _self.parameterName : parameterName // ignore: cast_nullable_to_non_nullable
as String?,portName: freezed == portName ? _self.portName : portName // ignore: cast_nullable_to_non_nullable
as String?,signalType: freezed == signalType ? _self.signalType : signalType // ignore: cast_nullable_to_non_nullable
as SignalType?,isOutput: null == isOutput ? _self.isOutput : isOutput // ignore: cast_nullable_to_non_nullable
as bool,isBackwardEdge: null == isBackwardEdge ? _self.isBackwardEdge : isBackwardEdge // ignore: cast_nullable_to_non_nullable
as bool,outputMode: freezed == outputMode ? _self.outputMode : outputMode // ignore: cast_nullable_to_non_nullable
as OutputMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,gain: null == gain ? _self.gain : gain // ignore: cast_nullable_to_non_nullable
as double,isMuted: null == isMuted ? _self.isMuted : isMuted // ignore: cast_nullable_to_non_nullable
as bool,isGhostConnection: null == isGhostConnection ? _self.isGhostConnection : isGhostConnection // ignore: cast_nullable_to_non_nullable
as bool,isInverted: null == isInverted ? _self.isInverted : isInverted // ignore: cast_nullable_to_non_nullable
as bool,delayMs: null == delayMs ? _self.delayMs : delayMs // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,modifiedAt: freezed == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Connection].
extension ConnectionPatterns on Connection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Connection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Connection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Connection value)  $default,){
final _that = this;
switch (_that) {
case _Connection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Connection value)?  $default,){
final _that = this;
switch (_that) {
case _Connection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sourcePortId,  String destinationPortId,  ConnectionType connectionType,  ConnectionStatus status,  bool isPartial,  int? busNumber,  String? busId,  String? busLabel,  String? algorithmId,  int? algorithmIndex,  int? parameterNumber,  String? parameterName,  String? portName,  SignalType? signalType,  bool isOutput,  bool isBackwardEdge,  OutputMode? outputMode,  String? name,  String? description,  double gain,  bool isMuted,  bool isGhostConnection,  bool isInverted,  double delayMs,  DateTime? createdAt,  DateTime? modifiedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Connection() when $default != null:
return $default(_that.id,_that.sourcePortId,_that.destinationPortId,_that.connectionType,_that.status,_that.isPartial,_that.busNumber,_that.busId,_that.busLabel,_that.algorithmId,_that.algorithmIndex,_that.parameterNumber,_that.parameterName,_that.portName,_that.signalType,_that.isOutput,_that.isBackwardEdge,_that.outputMode,_that.name,_that.description,_that.gain,_that.isMuted,_that.isGhostConnection,_that.isInverted,_that.delayMs,_that.createdAt,_that.modifiedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sourcePortId,  String destinationPortId,  ConnectionType connectionType,  ConnectionStatus status,  bool isPartial,  int? busNumber,  String? busId,  String? busLabel,  String? algorithmId,  int? algorithmIndex,  int? parameterNumber,  String? parameterName,  String? portName,  SignalType? signalType,  bool isOutput,  bool isBackwardEdge,  OutputMode? outputMode,  String? name,  String? description,  double gain,  bool isMuted,  bool isGhostConnection,  bool isInverted,  double delayMs,  DateTime? createdAt,  DateTime? modifiedAt)  $default,) {final _that = this;
switch (_that) {
case _Connection():
return $default(_that.id,_that.sourcePortId,_that.destinationPortId,_that.connectionType,_that.status,_that.isPartial,_that.busNumber,_that.busId,_that.busLabel,_that.algorithmId,_that.algorithmIndex,_that.parameterNumber,_that.parameterName,_that.portName,_that.signalType,_that.isOutput,_that.isBackwardEdge,_that.outputMode,_that.name,_that.description,_that.gain,_that.isMuted,_that.isGhostConnection,_that.isInverted,_that.delayMs,_that.createdAt,_that.modifiedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sourcePortId,  String destinationPortId,  ConnectionType connectionType,  ConnectionStatus status,  bool isPartial,  int? busNumber,  String? busId,  String? busLabel,  String? algorithmId,  int? algorithmIndex,  int? parameterNumber,  String? parameterName,  String? portName,  SignalType? signalType,  bool isOutput,  bool isBackwardEdge,  OutputMode? outputMode,  String? name,  String? description,  double gain,  bool isMuted,  bool isGhostConnection,  bool isInverted,  double delayMs,  DateTime? createdAt,  DateTime? modifiedAt)?  $default,) {final _that = this;
switch (_that) {
case _Connection() when $default != null:
return $default(_that.id,_that.sourcePortId,_that.destinationPortId,_that.connectionType,_that.status,_that.isPartial,_that.busNumber,_that.busId,_that.busLabel,_that.algorithmId,_that.algorithmIndex,_that.parameterNumber,_that.parameterName,_that.portName,_that.signalType,_that.isOutput,_that.isBackwardEdge,_that.outputMode,_that.name,_that.description,_that.gain,_that.isMuted,_that.isGhostConnection,_that.isInverted,_that.delayMs,_that.createdAt,_that.modifiedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Connection extends Connection {
  const _Connection({required this.id, required this.sourcePortId, required this.destinationPortId, required this.connectionType, this.status = ConnectionStatus.active, this.isPartial = false, this.busNumber, this.busId, this.busLabel, this.algorithmId, this.algorithmIndex, this.parameterNumber, this.parameterName, this.portName, this.signalType, this.isOutput = false, this.isBackwardEdge = false, this.outputMode, this.name, this.description, this.gain = 1.0, this.isMuted = false, this.isGhostConnection = false, this.isInverted = false, this.delayMs = 0.0, this.createdAt, this.modifiedAt}): super._();
  factory _Connection.fromJson(Map<String, dynamic> json) => _$ConnectionFromJson(json);

/// Unique identifier for this connection
@override final  String id;
/// ID of the source port
@override final  String sourcePortId;
/// ID of the destination port
@override final  String destinationPortId;
/// Type of connection
@override final  ConnectionType connectionType;
/// Current status of the connection
@override@JsonKey() final  ConnectionStatus status;
/// Whether this is a partial connection (one endpoint is a bus without match)
@override@JsonKey() final  bool isPartial;
/// Bus number for connections (1-12 for inputs, 13-20 for outputs, 21+ for algorithm buses)
@override final  int? busNumber;
/// Optional bus ID for UI routing buses
@override final  String? busId;
/// Bus label for rendering (e.g., "A1", "Out3")
@override final  String? busLabel;
/// Algorithm identifier for the connection
@override final  String? algorithmId;
/// Algorithm slot index (0-7)
@override final  int? algorithmIndex;
/// Parameter number for the port
@override final  int? parameterNumber;
/// Parameter name
@override final  String? parameterName;
/// Name of the port
@override final  String? portName;
/// Type of signal carried by this connection
@override final  SignalType? signalType;
/// Whether this is an output connection
@override@JsonKey() final  bool isOutput;
/// Whether this is a backward edge (for algorithm connections)
@override@JsonKey() final  bool isBackwardEdge;
/// Output mode for the source port (add or replace)
@override final  OutputMode? outputMode;
/// Optional name for the connection
@override final  String? name;
/// Optional description of what this connection does
@override final  String? description;
/// Signal gain/attenuation factor (1.0 = no change)
@override@JsonKey() final  double gain;
/// Whether the connection is muted
@override@JsonKey() final  bool isMuted;
/// Whether this is a ghost connection (for UI visualization)
@override@JsonKey() final  bool isGhostConnection;
/// Whether the connection is inverted
@override@JsonKey() final  bool isInverted;
/// Optional delay in milliseconds
@override@JsonKey() final  double delayMs;
/// Timestamp when the connection was created
@override final  DateTime? createdAt;
/// Timestamp when the connection was last modified
@override final  DateTime? modifiedAt;

/// Create a copy of Connection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConnectionCopyWith<_Connection> get copyWith => __$ConnectionCopyWithImpl<_Connection>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConnectionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Connection&&(identical(other.id, id) || other.id == id)&&(identical(other.sourcePortId, sourcePortId) || other.sourcePortId == sourcePortId)&&(identical(other.destinationPortId, destinationPortId) || other.destinationPortId == destinationPortId)&&(identical(other.connectionType, connectionType) || other.connectionType == connectionType)&&(identical(other.status, status) || other.status == status)&&(identical(other.isPartial, isPartial) || other.isPartial == isPartial)&&(identical(other.busNumber, busNumber) || other.busNumber == busNumber)&&(identical(other.busId, busId) || other.busId == busId)&&(identical(other.busLabel, busLabel) || other.busLabel == busLabel)&&(identical(other.algorithmId, algorithmId) || other.algorithmId == algorithmId)&&(identical(other.algorithmIndex, algorithmIndex) || other.algorithmIndex == algorithmIndex)&&(identical(other.parameterNumber, parameterNumber) || other.parameterNumber == parameterNumber)&&(identical(other.parameterName, parameterName) || other.parameterName == parameterName)&&(identical(other.portName, portName) || other.portName == portName)&&(identical(other.signalType, signalType) || other.signalType == signalType)&&(identical(other.isOutput, isOutput) || other.isOutput == isOutput)&&(identical(other.isBackwardEdge, isBackwardEdge) || other.isBackwardEdge == isBackwardEdge)&&(identical(other.outputMode, outputMode) || other.outputMode == outputMode)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.gain, gain) || other.gain == gain)&&(identical(other.isMuted, isMuted) || other.isMuted == isMuted)&&(identical(other.isGhostConnection, isGhostConnection) || other.isGhostConnection == isGhostConnection)&&(identical(other.isInverted, isInverted) || other.isInverted == isInverted)&&(identical(other.delayMs, delayMs) || other.delayMs == delayMs)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.modifiedAt, modifiedAt) || other.modifiedAt == modifiedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,sourcePortId,destinationPortId,connectionType,status,isPartial,busNumber,busId,busLabel,algorithmId,algorithmIndex,parameterNumber,parameterName,portName,signalType,isOutput,isBackwardEdge,outputMode,name,description,gain,isMuted,isGhostConnection,isInverted,delayMs,createdAt,modifiedAt]);
}

@override
String toString() {
    return 'Connection(id: $id, sourcePortId: $sourcePortId, destinationPortId: $destinationPortId, connectionType: $connectionType, status: $status, isPartial: $isPartial, busNumber: $busNumber, busId: $busId, busLabel: $busLabel, algorithmId: $algorithmId, algorithmIndex: $algorithmIndex, parameterNumber: $parameterNumber, parameterName: $parameterName, portName: $portName, signalType: $signalType, isOutput: $isOutput, isBackwardEdge: $isBackwardEdge, outputMode: $outputMode, name: $name, description: $description, gain: $gain, isMuted: $isMuted, isGhostConnection: $isGhostConnection, isInverted: $isInverted, delayMs: $delayMs, createdAt: $createdAt, modifiedAt: $modifiedAt)';
}


}

/// @nodoc
abstract mixin class _$ConnectionCopyWith<$Res> implements $ConnectionCopyWith<$Res> {
  factory _$ConnectionCopyWith(_Connection value, $Res Function(_Connection) _then) = __$ConnectionCopyWithImpl;
@override @useResult
$Res call({
 String id, String sourcePortId, String destinationPortId, ConnectionType connectionType, ConnectionStatus status, bool isPartial, int? busNumber, String? busId, String? busLabel, String? algorithmId, int? algorithmIndex, int? parameterNumber, String? parameterName, String? portName, SignalType? signalType, bool isOutput, bool isBackwardEdge, OutputMode? outputMode, String? name, String? description, double gain, bool isMuted, bool isGhostConnection, bool isInverted, double delayMs, DateTime? createdAt, DateTime? modifiedAt
});




}
/// @nodoc
class __$ConnectionCopyWithImpl<$Res>
    implements _$ConnectionCopyWith<$Res> {
  __$ConnectionCopyWithImpl(this._self, this._then);

  final _Connection _self;
  final $Res Function(_Connection) _then;

/// Create a copy of Connection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sourcePortId = null,Object? destinationPortId = null,Object? connectionType = null,Object? status = null,Object? isPartial = null,Object? busNumber = freezed,Object? busId = freezed,Object? busLabel = freezed,Object? algorithmId = freezed,Object? algorithmIndex = freezed,Object? parameterNumber = freezed,Object? parameterName = freezed,Object? portName = freezed,Object? signalType = freezed,Object? isOutput = null,Object? isBackwardEdge = null,Object? outputMode = freezed,Object? name = freezed,Object? description = freezed,Object? gain = null,Object? isMuted = null,Object? isGhostConnection = null,Object? isInverted = null,Object? delayMs = null,Object? createdAt = freezed,Object? modifiedAt = freezed,}) {
  return _then(_Connection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,destinationPortId: null == destinationPortId ? _self.destinationPortId : destinationPortId // ignore: cast_nullable_to_non_nullable
as String,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as ConnectionType,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ConnectionStatus,isPartial: null == isPartial ? _self.isPartial : isPartial // ignore: cast_nullable_to_non_nullable
as bool,busNumber: freezed == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int?,busId: freezed == busId ? _self.busId : busId // ignore: cast_nullable_to_non_nullable
as String?,busLabel: freezed == busLabel ? _self.busLabel : busLabel // ignore: cast_nullable_to_non_nullable
as String?,algorithmId: freezed == algorithmId ? _self.algorithmId : algorithmId // ignore: cast_nullable_to_non_nullable
as String?,algorithmIndex: freezed == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int?,parameterNumber: freezed == parameterNumber ? _self.parameterNumber : parameterNumber // ignore: cast_nullable_to_non_nullable
as int?,parameterName: freezed == parameterName ? _self.parameterName : parameterName // ignore: cast_nullable_to_non_nullable
as String?,portName: freezed == portName ? _self.portName : portName // ignore: cast_nullable_to_non_nullable
as String?,signalType: freezed == signalType ? _self.signalType : signalType // ignore: cast_nullable_to_non_nullable
as SignalType?,isOutput: null == isOutput ? _self.isOutput : isOutput // ignore: cast_nullable_to_non_nullable
as bool,isBackwardEdge: null == isBackwardEdge ? _self.isBackwardEdge : isBackwardEdge // ignore: cast_nullable_to_non_nullable
as bool,outputMode: freezed == outputMode ? _self.outputMode : outputMode // ignore: cast_nullable_to_non_nullable
as OutputMode?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,gain: null == gain ? _self.gain : gain // ignore: cast_nullable_to_non_nullable
as double,isMuted: null == isMuted ? _self.isMuted : isMuted // ignore: cast_nullable_to_non_nullable
as bool,isGhostConnection: null == isGhostConnection ? _self.isGhostConnection : isGhostConnection // ignore: cast_nullable_to_non_nullable
as bool,isInverted: null == isInverted ? _self.isInverted : isInverted // ignore: cast_nullable_to_non_nullable
as bool,delayMs: null == delayMs ? _self.delayMs : delayMs // ignore: cast_nullable_to_non_nullable
as double,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,modifiedAt: freezed == modifiedAt ? _self.modifiedAt : modifiedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
