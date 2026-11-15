// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'algorithm_connection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlgorithmConnection {

/// Unique identifier for this connection using format: alg_${source}_${sourcePort}->alg_${target}_${targetPort}_bus_${busNumber}
 String get id;/// Index of the source algorithm slot (0-7)
 int get sourceAlgorithmIndex;/// ID of the source port/parameter that outputs to this bus
 String get sourcePortId;/// Index of the target algorithm slot (0-7)
 int get targetAlgorithmIndex;/// ID of the target port/parameter that receives from this bus
 String get targetPortId;/// Bus number used for this connection (1-28)
/// 1-12: Input/CV buses, 13-20: Output buses, 21-28: Audio buses
 int get busNumber;/// Type of connection based on signal flow and bus usage
 AlgorithmConnectionType get connectionType;/// Whether this connection is currently valid based on algorithm states
 bool get isValid;/// Optional validation message if connection is invalid
 String? get validationMessage;/// Human-readable label for the connection edge (e.g., "Bus 5", "CV 3")
 String? get edgeLabel;
/// Create a copy of AlgorithmConnection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AlgorithmConnectionCopyWith<AlgorithmConnection> get copyWith => _$AlgorithmConnectionCopyWithImpl<AlgorithmConnection>(this as AlgorithmConnection, _$identity);

  /// Serializes this AlgorithmConnection to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as AlgorithmConnection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AlgorithmConnection&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sourceAlgorithmIndex, _this.sourceAlgorithmIndex) || other.sourceAlgorithmIndex == _this.sourceAlgorithmIndex)&&(identical(other.sourcePortId, _this.sourcePortId) || other.sourcePortId == _this.sourcePortId)&&(identical(other.targetAlgorithmIndex, _this.targetAlgorithmIndex) || other.targetAlgorithmIndex == _this.targetAlgorithmIndex)&&(identical(other.targetPortId, _this.targetPortId) || other.targetPortId == _this.targetPortId)&&(identical(other.busNumber, _this.busNumber) || other.busNumber == _this.busNumber)&&(identical(other.connectionType, _this.connectionType) || other.connectionType == _this.connectionType)&&(identical(other.isValid, _this.isValid) || other.isValid == _this.isValid)&&(identical(other.validationMessage, _this.validationMessage) || other.validationMessage == _this.validationMessage)&&(identical(other.edgeLabel, _this.edgeLabel) || other.edgeLabel == _this.edgeLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as AlgorithmConnection;
  return Object.hash(runtimeType,_this.id,_this.sourceAlgorithmIndex,_this.sourcePortId,_this.targetAlgorithmIndex,_this.targetPortId,_this.busNumber,_this.connectionType,_this.isValid,_this.validationMessage,_this.edgeLabel);
}

@override
String toString() {
  final _this = this as AlgorithmConnection;
  return 'AlgorithmConnection(id: ${_this.id}, sourceAlgorithmIndex: ${_this.sourceAlgorithmIndex}, sourcePortId: ${_this.sourcePortId}, targetAlgorithmIndex: ${_this.targetAlgorithmIndex}, targetPortId: ${_this.targetPortId}, busNumber: ${_this.busNumber}, connectionType: ${_this.connectionType}, isValid: ${_this.isValid}, validationMessage: ${_this.validationMessage}, edgeLabel: ${_this.edgeLabel})';
}


}

/// @nodoc
abstract mixin class $AlgorithmConnectionCopyWith<$Res>  {
  factory $AlgorithmConnectionCopyWith(AlgorithmConnection value, $Res Function(AlgorithmConnection) _then) = _$AlgorithmConnectionCopyWithImpl;
@useResult
$Res call({
 String id, int sourceAlgorithmIndex, String sourcePortId, int targetAlgorithmIndex, String targetPortId, int busNumber, AlgorithmConnectionType connectionType, bool isValid, String? validationMessage, String? edgeLabel
});




}
/// @nodoc
class _$AlgorithmConnectionCopyWithImpl<$Res>
    implements $AlgorithmConnectionCopyWith<$Res> {
  _$AlgorithmConnectionCopyWithImpl(this._self, this._then);

  final AlgorithmConnection _self;
  final $Res Function(AlgorithmConnection) _then;

/// Create a copy of AlgorithmConnection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sourceAlgorithmIndex = null,Object? sourcePortId = null,Object? targetAlgorithmIndex = null,Object? targetPortId = null,Object? busNumber = null,Object? connectionType = null,Object? isValid = null,Object? validationMessage = freezed,Object? edgeLabel = freezed,}) {
  return _then(AlgorithmConnection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceAlgorithmIndex: null == sourceAlgorithmIndex ? _self.sourceAlgorithmIndex : sourceAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetAlgorithmIndex: null == targetAlgorithmIndex ? _self.targetAlgorithmIndex : targetAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,busNumber: null == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as AlgorithmConnectionType,isValid: null == isValid ? _self.isValid : isValid // ignore: cast_nullable_to_non_nullable
as bool,validationMessage: freezed == validationMessage ? _self.validationMessage : validationMessage // ignore: cast_nullable_to_non_nullable
as String?,edgeLabel: freezed == edgeLabel ? _self.edgeLabel : edgeLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AlgorithmConnection].
extension AlgorithmConnectionPatterns on AlgorithmConnection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AlgorithmConnection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AlgorithmConnection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AlgorithmConnection value)  $default,){
final _that = this;
switch (_that) {
case _AlgorithmConnection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AlgorithmConnection value)?  $default,){
final _that = this;
switch (_that) {
case _AlgorithmConnection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int busNumber,  AlgorithmConnectionType connectionType,  bool isValid,  String? validationMessage,  String? edgeLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AlgorithmConnection() when $default != null:
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.busNumber,_that.connectionType,_that.isValid,_that.validationMessage,_that.edgeLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int busNumber,  AlgorithmConnectionType connectionType,  bool isValid,  String? validationMessage,  String? edgeLabel)  $default,) {final _that = this;
switch (_that) {
case _AlgorithmConnection():
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.busNumber,_that.connectionType,_that.isValid,_that.validationMessage,_that.edgeLabel);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int busNumber,  AlgorithmConnectionType connectionType,  bool isValid,  String? validationMessage,  String? edgeLabel)?  $default,) {final _that = this;
switch (_that) {
case _AlgorithmConnection() when $default != null:
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.busNumber,_that.connectionType,_that.isValid,_that.validationMessage,_that.edgeLabel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _AlgorithmConnection implements AlgorithmConnection {
  const _AlgorithmConnection({required this.id, required this.sourceAlgorithmIndex, required this.sourcePortId, required this.targetAlgorithmIndex, required this.targetPortId, required this.busNumber, required this.connectionType, this.isValid = true, this.validationMessage, this.edgeLabel});
  factory _AlgorithmConnection.fromJson(Map<String, dynamic> json) => _$AlgorithmConnectionFromJson(json);

/// Unique identifier for this connection using format: alg_${source}_${sourcePort}->alg_${target}_${targetPort}_bus_${busNumber}
@override final  String id;
/// Index of the source algorithm slot (0-7)
@override final  int sourceAlgorithmIndex;
/// ID of the source port/parameter that outputs to this bus
@override final  String sourcePortId;
/// Index of the target algorithm slot (0-7)
@override final  int targetAlgorithmIndex;
/// ID of the target port/parameter that receives from this bus
@override final  String targetPortId;
/// Bus number used for this connection (1-28)
/// 1-12: Input/CV buses, 13-20: Output buses, 21-28: Audio buses
@override final  int busNumber;
/// Type of connection based on signal flow and bus usage
@override final  AlgorithmConnectionType connectionType;
/// Whether this connection is currently valid based on algorithm states
@override@JsonKey() final  bool isValid;
/// Optional validation message if connection is invalid
@override final  String? validationMessage;
/// Human-readable label for the connection edge (e.g., "Bus 5", "CV 3")
@override final  String? edgeLabel;

/// Create a copy of AlgorithmConnection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AlgorithmConnectionCopyWith<_AlgorithmConnection> get copyWith => __$AlgorithmConnectionCopyWithImpl<_AlgorithmConnection>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$AlgorithmConnectionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AlgorithmConnection&&(identical(other.id, id) || other.id == id)&&(identical(other.sourceAlgorithmIndex, sourceAlgorithmIndex) || other.sourceAlgorithmIndex == sourceAlgorithmIndex)&&(identical(other.sourcePortId, sourcePortId) || other.sourcePortId == sourcePortId)&&(identical(other.targetAlgorithmIndex, targetAlgorithmIndex) || other.targetAlgorithmIndex == targetAlgorithmIndex)&&(identical(other.targetPortId, targetPortId) || other.targetPortId == targetPortId)&&(identical(other.busNumber, busNumber) || other.busNumber == busNumber)&&(identical(other.connectionType, connectionType) || other.connectionType == connectionType)&&(identical(other.isValid, isValid) || other.isValid == isValid)&&(identical(other.validationMessage, validationMessage) || other.validationMessage == validationMessage)&&(identical(other.edgeLabel, edgeLabel) || other.edgeLabel == edgeLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,sourceAlgorithmIndex,sourcePortId,targetAlgorithmIndex,targetPortId,busNumber,connectionType,isValid,validationMessage,edgeLabel);
}

@override
String toString() {
    return 'AlgorithmConnection(id: $id, sourceAlgorithmIndex: $sourceAlgorithmIndex, sourcePortId: $sourcePortId, targetAlgorithmIndex: $targetAlgorithmIndex, targetPortId: $targetPortId, busNumber: $busNumber, connectionType: $connectionType, isValid: $isValid, validationMessage: $validationMessage, edgeLabel: $edgeLabel)';
}


}

/// @nodoc
abstract mixin class _$AlgorithmConnectionCopyWith<$Res> implements $AlgorithmConnectionCopyWith<$Res> {
  factory _$AlgorithmConnectionCopyWith(_AlgorithmConnection value, $Res Function(_AlgorithmConnection) _then) = __$AlgorithmConnectionCopyWithImpl;
@override @useResult
$Res call({
 String id, int sourceAlgorithmIndex, String sourcePortId, int targetAlgorithmIndex, String targetPortId, int busNumber, AlgorithmConnectionType connectionType, bool isValid, String? validationMessage, String? edgeLabel
});




}
/// @nodoc
class __$AlgorithmConnectionCopyWithImpl<$Res>
    implements _$AlgorithmConnectionCopyWith<$Res> {
  __$AlgorithmConnectionCopyWithImpl(this._self, this._then);

  final _AlgorithmConnection _self;
  final $Res Function(_AlgorithmConnection) _then;

/// Create a copy of AlgorithmConnection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sourceAlgorithmIndex = null,Object? sourcePortId = null,Object? targetAlgorithmIndex = null,Object? targetPortId = null,Object? busNumber = null,Object? connectionType = null,Object? isValid = null,Object? validationMessage = freezed,Object? edgeLabel = freezed,}) {
  return _then(_AlgorithmConnection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceAlgorithmIndex: null == sourceAlgorithmIndex ? _self.sourceAlgorithmIndex : sourceAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetAlgorithmIndex: null == targetAlgorithmIndex ? _self.targetAlgorithmIndex : targetAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,busNumber: null == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int,connectionType: null == connectionType ? _self.connectionType : connectionType // ignore: cast_nullable_to_non_nullable
as AlgorithmConnectionType,isValid: null == isValid ? _self.isValid : isValid // ignore: cast_nullable_to_non_nullable
as bool,validationMessage: freezed == validationMessage ? _self.validationMessage : validationMessage // ignore: cast_nullable_to_non_nullable
as String?,edgeLabel: freezed == edgeLabel ? _self.edgeLabel : edgeLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
