// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Port {

/// Unique identifier for this port
 String get id;/// Human-readable name of the port
 String get name;/// The type of signal this port handles
 PortType get type;/// The direction of signal flow for this port
 PortDirection get direction;/// Optional description of the port's purpose
 String? get description;/// Optional constraints for this port (e.g., voltage range, frequency)
 Map<String, dynamic>? get constraints;/// Whether this port is currently active/enabled
 bool get isActive;/// Optional output mode for output ports (add or replace)
 OutputMode? get outputMode;/// Whether this port represents a polyphonic voice
 bool get isPolyVoice;/// The voice number for polyphonic ports (1-based indexing)
 int? get voiceNumber;/// Whether this port is a virtual CV port
 bool get isVirtualCV;/// Whether this port is part of a multi-channel configuration
 bool get isMultiChannel;/// The channel number for multi-channel ports (0-based indexing)
 int? get channelNumber;/// Whether this port is part of a stereo channel pair
 bool get isStereoChannel;/// The stereo side for stereo channel ports ('left' or 'right')
 String? get stereoSide;/// Whether this port represents the master mix output
 bool get isMasterMix;/// The bus number this port is connected to (1-20)
 int? get busValue;/// The parameter name associated with this port's bus assignment
 String? get busParam;/// The parameter number associated with this port
 int? get parameterNumber;/// The mode parameter number for this port's output mode (Add/Replace)
 int? get modeParameterNumber;/// The hardware index for physical/ES-5 ports (1-based).
/// For physical ports this equals the bus number for inputs (1-12)
/// or the jack number for outputs (1-8, mapped to buses 13-20).
 int? get hardwareIndex;/// The node identifier for grouping related ports
 String? get nodeId;/// The role this port plays in the bus-assignment routing model.
/// If not set, derived from [direction] and port ID conventions.
 PortRole? get role;
/// Create a copy of Port
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PortCopyWith<Port> get copyWith => _$PortCopyWithImpl<Port>(this as Port, _$identity);

  /// Serializes this Port to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Port;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Port&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.direction, _this.direction) || other.direction == _this.direction)&&(identical(other.description, _this.description) || other.description == _this.description)&&const DeepCollectionEquality().equals(other.constraints, _this.constraints)&&(identical(other.isActive, _this.isActive) || other.isActive == _this.isActive)&&(identical(other.outputMode, _this.outputMode) || other.outputMode == _this.outputMode)&&(identical(other.isPolyVoice, _this.isPolyVoice) || other.isPolyVoice == _this.isPolyVoice)&&(identical(other.voiceNumber, _this.voiceNumber) || other.voiceNumber == _this.voiceNumber)&&(identical(other.isVirtualCV, _this.isVirtualCV) || other.isVirtualCV == _this.isVirtualCV)&&(identical(other.isMultiChannel, _this.isMultiChannel) || other.isMultiChannel == _this.isMultiChannel)&&(identical(other.channelNumber, _this.channelNumber) || other.channelNumber == _this.channelNumber)&&(identical(other.isStereoChannel, _this.isStereoChannel) || other.isStereoChannel == _this.isStereoChannel)&&(identical(other.stereoSide, _this.stereoSide) || other.stereoSide == _this.stereoSide)&&(identical(other.isMasterMix, _this.isMasterMix) || other.isMasterMix == _this.isMasterMix)&&(identical(other.busValue, _this.busValue) || other.busValue == _this.busValue)&&(identical(other.busParam, _this.busParam) || other.busParam == _this.busParam)&&(identical(other.parameterNumber, _this.parameterNumber) || other.parameterNumber == _this.parameterNumber)&&(identical(other.modeParameterNumber, _this.modeParameterNumber) || other.modeParameterNumber == _this.modeParameterNumber)&&(identical(other.hardwareIndex, _this.hardwareIndex) || other.hardwareIndex == _this.hardwareIndex)&&(identical(other.nodeId, _this.nodeId) || other.nodeId == _this.nodeId)&&(identical(other.role, _this.role) || other.role == _this.role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Port;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.type,_this.direction,_this.description,const DeepCollectionEquality().hash(_this.constraints),_this.isActive,_this.outputMode,_this.isPolyVoice,_this.voiceNumber,_this.isVirtualCV,_this.isMultiChannel,_this.channelNumber,_this.isStereoChannel,_this.stereoSide,_this.isMasterMix,_this.busValue,_this.busParam,_this.parameterNumber,_this.modeParameterNumber,_this.hardwareIndex,_this.nodeId,_this.role]);
}

@override
String toString() {
  final _this = this as Port;
  return 'Port(id: ${_this.id}, name: ${_this.name}, type: ${_this.type}, direction: ${_this.direction}, description: ${_this.description}, constraints: ${_this.constraints}, isActive: ${_this.isActive}, outputMode: ${_this.outputMode}, isPolyVoice: ${_this.isPolyVoice}, voiceNumber: ${_this.voiceNumber}, isVirtualCV: ${_this.isVirtualCV}, isMultiChannel: ${_this.isMultiChannel}, channelNumber: ${_this.channelNumber}, isStereoChannel: ${_this.isStereoChannel}, stereoSide: ${_this.stereoSide}, isMasterMix: ${_this.isMasterMix}, busValue: ${_this.busValue}, busParam: ${_this.busParam}, parameterNumber: ${_this.parameterNumber}, modeParameterNumber: ${_this.modeParameterNumber}, hardwareIndex: ${_this.hardwareIndex}, nodeId: ${_this.nodeId}, role: ${_this.role})';
}


}

/// @nodoc
abstract mixin class $PortCopyWith<$Res>  {
  factory $PortCopyWith(Port value, $Res Function(Port) _then) = _$PortCopyWithImpl;
@useResult
$Res call({
 String id, String name, PortType type, PortDirection direction, String? description, Map<String, dynamic>? constraints, bool isActive, OutputMode? outputMode, bool isPolyVoice, int? voiceNumber, bool isVirtualCV, bool isMultiChannel, int? channelNumber, bool isStereoChannel, String? stereoSide, bool isMasterMix, int? busValue, String? busParam, int? parameterNumber, int? modeParameterNumber, int? hardwareIndex, String? nodeId, PortRole? role
});




}
/// @nodoc
class _$PortCopyWithImpl<$Res>
    implements $PortCopyWith<$Res> {
  _$PortCopyWithImpl(this._self, this._then);

  final Port _self;
  final $Res Function(Port) _then;

/// Create a copy of Port
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? type = null,Object? direction = null,Object? description = freezed,Object? constraints = freezed,Object? isActive = null,Object? outputMode = freezed,Object? isPolyVoice = null,Object? voiceNumber = freezed,Object? isVirtualCV = null,Object? isMultiChannel = null,Object? channelNumber = freezed,Object? isStereoChannel = null,Object? stereoSide = freezed,Object? isMasterMix = null,Object? busValue = freezed,Object? busParam = freezed,Object? parameterNumber = freezed,Object? modeParameterNumber = freezed,Object? hardwareIndex = freezed,Object? nodeId = freezed,Object? role = freezed,}) {
  return _then(Port(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as PortType,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as PortDirection,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,constraints: freezed == constraints ? _self.constraints : constraints // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,outputMode: freezed == outputMode ? _self.outputMode : outputMode // ignore: cast_nullable_to_non_nullable
as OutputMode?,isPolyVoice: null == isPolyVoice ? _self.isPolyVoice : isPolyVoice // ignore: cast_nullable_to_non_nullable
as bool,voiceNumber: freezed == voiceNumber ? _self.voiceNumber : voiceNumber // ignore: cast_nullable_to_non_nullable
as int?,isVirtualCV: null == isVirtualCV ? _self.isVirtualCV : isVirtualCV // ignore: cast_nullable_to_non_nullable
as bool,isMultiChannel: null == isMultiChannel ? _self.isMultiChannel : isMultiChannel // ignore: cast_nullable_to_non_nullable
as bool,channelNumber: freezed == channelNumber ? _self.channelNumber : channelNumber // ignore: cast_nullable_to_non_nullable
as int?,isStereoChannel: null == isStereoChannel ? _self.isStereoChannel : isStereoChannel // ignore: cast_nullable_to_non_nullable
as bool,stereoSide: freezed == stereoSide ? _self.stereoSide : stereoSide // ignore: cast_nullable_to_non_nullable
as String?,isMasterMix: null == isMasterMix ? _self.isMasterMix : isMasterMix // ignore: cast_nullable_to_non_nullable
as bool,busValue: freezed == busValue ? _self.busValue : busValue // ignore: cast_nullable_to_non_nullable
as int?,busParam: freezed == busParam ? _self.busParam : busParam // ignore: cast_nullable_to_non_nullable
as String?,parameterNumber: freezed == parameterNumber ? _self.parameterNumber : parameterNumber // ignore: cast_nullable_to_non_nullable
as int?,modeParameterNumber: freezed == modeParameterNumber ? _self.modeParameterNumber : modeParameterNumber // ignore: cast_nullable_to_non_nullable
as int?,hardwareIndex: freezed == hardwareIndex ? _self.hardwareIndex : hardwareIndex // ignore: cast_nullable_to_non_nullable
as int?,nodeId: freezed == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as PortRole?,
  ));
}

}


/// Adds pattern-matching-related methods to [Port].
extension PortPatterns on Port {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Port value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Port() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Port value)  $default,){
final _that = this;
switch (_that) {
case _Port():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Port value)?  $default,){
final _that = this;
switch (_that) {
case _Port() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  PortType type,  PortDirection direction,  String? description,  Map<String, dynamic>? constraints,  bool isActive,  OutputMode? outputMode,  bool isPolyVoice,  int? voiceNumber,  bool isVirtualCV,  bool isMultiChannel,  int? channelNumber,  bool isStereoChannel,  String? stereoSide,  bool isMasterMix,  int? busValue,  String? busParam,  int? parameterNumber,  int? modeParameterNumber,  int? hardwareIndex,  String? nodeId,  PortRole? role)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Port() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.direction,_that.description,_that.constraints,_that.isActive,_that.outputMode,_that.isPolyVoice,_that.voiceNumber,_that.isVirtualCV,_that.isMultiChannel,_that.channelNumber,_that.isStereoChannel,_that.stereoSide,_that.isMasterMix,_that.busValue,_that.busParam,_that.parameterNumber,_that.modeParameterNumber,_that.hardwareIndex,_that.nodeId,_that.role);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  PortType type,  PortDirection direction,  String? description,  Map<String, dynamic>? constraints,  bool isActive,  OutputMode? outputMode,  bool isPolyVoice,  int? voiceNumber,  bool isVirtualCV,  bool isMultiChannel,  int? channelNumber,  bool isStereoChannel,  String? stereoSide,  bool isMasterMix,  int? busValue,  String? busParam,  int? parameterNumber,  int? modeParameterNumber,  int? hardwareIndex,  String? nodeId,  PortRole? role)  $default,) {final _that = this;
switch (_that) {
case _Port():
return $default(_that.id,_that.name,_that.type,_that.direction,_that.description,_that.constraints,_that.isActive,_that.outputMode,_that.isPolyVoice,_that.voiceNumber,_that.isVirtualCV,_that.isMultiChannel,_that.channelNumber,_that.isStereoChannel,_that.stereoSide,_that.isMasterMix,_that.busValue,_that.busParam,_that.parameterNumber,_that.modeParameterNumber,_that.hardwareIndex,_that.nodeId,_that.role);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  PortType type,  PortDirection direction,  String? description,  Map<String, dynamic>? constraints,  bool isActive,  OutputMode? outputMode,  bool isPolyVoice,  int? voiceNumber,  bool isVirtualCV,  bool isMultiChannel,  int? channelNumber,  bool isStereoChannel,  String? stereoSide,  bool isMasterMix,  int? busValue,  String? busParam,  int? parameterNumber,  int? modeParameterNumber,  int? hardwareIndex,  String? nodeId,  PortRole? role)?  $default,) {final _that = this;
switch (_that) {
case _Port() when $default != null:
return $default(_that.id,_that.name,_that.type,_that.direction,_that.description,_that.constraints,_that.isActive,_that.outputMode,_that.isPolyVoice,_that.voiceNumber,_that.isVirtualCV,_that.isMultiChannel,_that.channelNumber,_that.isStereoChannel,_that.stereoSide,_that.isMasterMix,_that.busValue,_that.busParam,_that.parameterNumber,_that.modeParameterNumber,_that.hardwareIndex,_that.nodeId,_that.role);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Port extends Port {
  const _Port({required this.id, required this.name, required this.type, required this.direction, this.description,  Map<String, dynamic>? constraints, this.isActive = true, this.outputMode, this.isPolyVoice = false, this.voiceNumber, this.isVirtualCV = false, this.isMultiChannel = false, this.channelNumber, this.isStereoChannel = false, this.stereoSide, this.isMasterMix = false, this.busValue, this.busParam, this.parameterNumber, this.modeParameterNumber, this.hardwareIndex, this.nodeId, this.role}): _constraints = constraints,super._();
  factory _Port.fromJson(Map<String, dynamic> json) => _$PortFromJson(json);

/// Unique identifier for this port
@override final  String id;
/// Human-readable name of the port
@override final  String name;
/// The type of signal this port handles
@override final  PortType type;
/// The direction of signal flow for this port
@override final  PortDirection direction;
/// Optional description of the port's purpose
@override final  String? description;
/// Optional constraints for this port (e.g., voltage range, frequency)
 final  Map<String, dynamic>? _constraints;
/// Optional constraints for this port (e.g., voltage range, frequency)
@override Map<String, dynamic>? get constraints {
  final value = _constraints;
  if (value == null) return null;
  if (_constraints is EqualUnmodifiableMapView) return _constraints;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

/// Whether this port is currently active/enabled
@override@JsonKey() final  bool isActive;
/// Optional output mode for output ports (add or replace)
@override final  OutputMode? outputMode;
/// Whether this port represents a polyphonic voice
@override@JsonKey() final  bool isPolyVoice;
/// The voice number for polyphonic ports (1-based indexing)
@override final  int? voiceNumber;
/// Whether this port is a virtual CV port
@override@JsonKey() final  bool isVirtualCV;
/// Whether this port is part of a multi-channel configuration
@override@JsonKey() final  bool isMultiChannel;
/// The channel number for multi-channel ports (0-based indexing)
@override final  int? channelNumber;
/// Whether this port is part of a stereo channel pair
@override@JsonKey() final  bool isStereoChannel;
/// The stereo side for stereo channel ports ('left' or 'right')
@override final  String? stereoSide;
/// Whether this port represents the master mix output
@override@JsonKey() final  bool isMasterMix;
/// The bus number this port is connected to (1-20)
@override final  int? busValue;
/// The parameter name associated with this port's bus assignment
@override final  String? busParam;
/// The parameter number associated with this port
@override final  int? parameterNumber;
/// The mode parameter number for this port's output mode (Add/Replace)
@override final  int? modeParameterNumber;
/// The hardware index for physical/ES-5 ports (1-based).
/// For physical ports this equals the bus number for inputs (1-12)
/// or the jack number for outputs (1-8, mapped to buses 13-20).
@override final  int? hardwareIndex;
/// The node identifier for grouping related ports
@override final  String? nodeId;
/// The role this port plays in the bus-assignment routing model.
/// If not set, derived from [direction] and port ID conventions.
@override final  PortRole? role;

/// Create a copy of Port
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PortCopyWith<_Port> get copyWith => __$PortCopyWithImpl<_Port>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PortToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Port&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.type, type) || other.type == type)&&(identical(other.direction, direction) || other.direction == direction)&&(identical(other.description, description) || other.description == description)&&const DeepCollectionEquality().equals(other.constraints, _constraints)&&(identical(other.isActive, isActive) || other.isActive == isActive)&&(identical(other.outputMode, outputMode) || other.outputMode == outputMode)&&(identical(other.isPolyVoice, isPolyVoice) || other.isPolyVoice == isPolyVoice)&&(identical(other.voiceNumber, voiceNumber) || other.voiceNumber == voiceNumber)&&(identical(other.isVirtualCV, isVirtualCV) || other.isVirtualCV == isVirtualCV)&&(identical(other.isMultiChannel, isMultiChannel) || other.isMultiChannel == isMultiChannel)&&(identical(other.channelNumber, channelNumber) || other.channelNumber == channelNumber)&&(identical(other.isStereoChannel, isStereoChannel) || other.isStereoChannel == isStereoChannel)&&(identical(other.stereoSide, stereoSide) || other.stereoSide == stereoSide)&&(identical(other.isMasterMix, isMasterMix) || other.isMasterMix == isMasterMix)&&(identical(other.busValue, busValue) || other.busValue == busValue)&&(identical(other.busParam, busParam) || other.busParam == busParam)&&(identical(other.parameterNumber, parameterNumber) || other.parameterNumber == parameterNumber)&&(identical(other.modeParameterNumber, modeParameterNumber) || other.modeParameterNumber == modeParameterNumber)&&(identical(other.hardwareIndex, hardwareIndex) || other.hardwareIndex == hardwareIndex)&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.role, role) || other.role == role));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,type,direction,description,const DeepCollectionEquality().hash(_constraints),isActive,outputMode,isPolyVoice,voiceNumber,isVirtualCV,isMultiChannel,channelNumber,isStereoChannel,stereoSide,isMasterMix,busValue,busParam,parameterNumber,modeParameterNumber,hardwareIndex,nodeId,role]);
}

@override
String toString() {
    return 'Port(id: $id, name: $name, type: $type, direction: $direction, description: $description, constraints: $constraints, isActive: $isActive, outputMode: $outputMode, isPolyVoice: $isPolyVoice, voiceNumber: $voiceNumber, isVirtualCV: $isVirtualCV, isMultiChannel: $isMultiChannel, channelNumber: $channelNumber, isStereoChannel: $isStereoChannel, stereoSide: $stereoSide, isMasterMix: $isMasterMix, busValue: $busValue, busParam: $busParam, parameterNumber: $parameterNumber, modeParameterNumber: $modeParameterNumber, hardwareIndex: $hardwareIndex, nodeId: $nodeId, role: $role)';
}


}

/// @nodoc
abstract mixin class _$PortCopyWith<$Res> implements $PortCopyWith<$Res> {
  factory _$PortCopyWith(_Port value, $Res Function(_Port) _then) = __$PortCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, PortType type, PortDirection direction, String? description, Map<String, dynamic>? constraints, bool isActive, OutputMode? outputMode, bool isPolyVoice, int? voiceNumber, bool isVirtualCV, bool isMultiChannel, int? channelNumber, bool isStereoChannel, String? stereoSide, bool isMasterMix, int? busValue, String? busParam, int? parameterNumber, int? modeParameterNumber, int? hardwareIndex, String? nodeId, PortRole? role
});




}
/// @nodoc
class __$PortCopyWithImpl<$Res>
    implements _$PortCopyWith<$Res> {
  __$PortCopyWithImpl(this._self, this._then);

  final _Port _self;
  final $Res Function(_Port) _then;

/// Create a copy of Port
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? type = null,Object? direction = null,Object? description = freezed,Object? constraints = freezed,Object? isActive = null,Object? outputMode = freezed,Object? isPolyVoice = null,Object? voiceNumber = freezed,Object? isVirtualCV = null,Object? isMultiChannel = null,Object? channelNumber = freezed,Object? isStereoChannel = null,Object? stereoSide = freezed,Object? isMasterMix = null,Object? busValue = freezed,Object? busParam = freezed,Object? parameterNumber = freezed,Object? modeParameterNumber = freezed,Object? hardwareIndex = freezed,Object? nodeId = freezed,Object? role = freezed,}) {
  return _then(_Port(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as PortType,direction: null == direction ? _self.direction : direction // ignore: cast_nullable_to_non_nullable
as PortDirection,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,constraints: freezed == constraints ? _self._constraints : constraints // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,outputMode: freezed == outputMode ? _self.outputMode : outputMode // ignore: cast_nullable_to_non_nullable
as OutputMode?,isPolyVoice: null == isPolyVoice ? _self.isPolyVoice : isPolyVoice // ignore: cast_nullable_to_non_nullable
as bool,voiceNumber: freezed == voiceNumber ? _self.voiceNumber : voiceNumber // ignore: cast_nullable_to_non_nullable
as int?,isVirtualCV: null == isVirtualCV ? _self.isVirtualCV : isVirtualCV // ignore: cast_nullable_to_non_nullable
as bool,isMultiChannel: null == isMultiChannel ? _self.isMultiChannel : isMultiChannel // ignore: cast_nullable_to_non_nullable
as bool,channelNumber: freezed == channelNumber ? _self.channelNumber : channelNumber // ignore: cast_nullable_to_non_nullable
as int?,isStereoChannel: null == isStereoChannel ? _self.isStereoChannel : isStereoChannel // ignore: cast_nullable_to_non_nullable
as bool,stereoSide: freezed == stereoSide ? _self.stereoSide : stereoSide // ignore: cast_nullable_to_non_nullable
as String?,isMasterMix: null == isMasterMix ? _self.isMasterMix : isMasterMix // ignore: cast_nullable_to_non_nullable
as bool,busValue: freezed == busValue ? _self.busValue : busValue // ignore: cast_nullable_to_non_nullable
as int?,busParam: freezed == busParam ? _self.busParam : busParam // ignore: cast_nullable_to_non_nullable
as String?,parameterNumber: freezed == parameterNumber ? _self.parameterNumber : parameterNumber // ignore: cast_nullable_to_non_nullable
as int?,modeParameterNumber: freezed == modeParameterNumber ? _self.modeParameterNumber : modeParameterNumber // ignore: cast_nullable_to_non_nullable
as int?,hardwareIndex: freezed == hardwareIndex ? _self.hardwareIndex : hardwareIndex // ignore: cast_nullable_to_non_nullable
as int?,nodeId: freezed == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String?,role: freezed == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as PortRole?,
  ));
}


}

// dart format on
