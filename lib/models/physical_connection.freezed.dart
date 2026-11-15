// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'physical_connection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PhysicalConnection {

/// Unique identifier for this connection using format: phys_${sourcePortId}->${targetPortId}
 String get id;/// ID of the source port (e.g., 'hw_in_1', 'alg_0_audio_output')
 String get sourcePortId;/// ID of the target port (e.g., 'alg_0_audio_input', 'hw_out_1')
 String get targetPortId;/// Bus number this connection uses (1-12 for inputs, 13-20 for outputs)
 int get busNumber;/// True if this is a connection from physical input to algorithm input,
/// false if this is a connection from algorithm output to physical output
 bool get isInputConnection;/// Index of the algorithm involved in this connection
 int get algorithmIndex;
/// Create a copy of PhysicalConnection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhysicalConnectionCopyWith<PhysicalConnection> get copyWith => _$PhysicalConnectionCopyWithImpl<PhysicalConnection>(this as PhysicalConnection, _$identity);

  /// Serializes this PhysicalConnection to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PhysicalConnection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PhysicalConnection&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sourcePortId, _this.sourcePortId) || other.sourcePortId == _this.sourcePortId)&&(identical(other.targetPortId, _this.targetPortId) || other.targetPortId == _this.targetPortId)&&(identical(other.busNumber, _this.busNumber) || other.busNumber == _this.busNumber)&&(identical(other.isInputConnection, _this.isInputConnection) || other.isInputConnection == _this.isInputConnection)&&(identical(other.algorithmIndex, _this.algorithmIndex) || other.algorithmIndex == _this.algorithmIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PhysicalConnection;
  return Object.hash(runtimeType,_this.id,_this.sourcePortId,_this.targetPortId,_this.busNumber,_this.isInputConnection,_this.algorithmIndex);
}

@override
String toString() {
  final _this = this as PhysicalConnection;
  return 'PhysicalConnection(id: ${_this.id}, sourcePortId: ${_this.sourcePortId}, targetPortId: ${_this.targetPortId}, busNumber: ${_this.busNumber}, isInputConnection: ${_this.isInputConnection}, algorithmIndex: ${_this.algorithmIndex})';
}


}

/// @nodoc
abstract mixin class $PhysicalConnectionCopyWith<$Res>  {
  factory $PhysicalConnectionCopyWith(PhysicalConnection value, $Res Function(PhysicalConnection) _then) = _$PhysicalConnectionCopyWithImpl;
@useResult
$Res call({
 String id, String sourcePortId, String targetPortId, int busNumber, bool isInputConnection, int algorithmIndex
});




}
/// @nodoc
class _$PhysicalConnectionCopyWithImpl<$Res>
    implements $PhysicalConnectionCopyWith<$Res> {
  _$PhysicalConnectionCopyWithImpl(this._self, this._then);

  final PhysicalConnection _self;
  final $Res Function(PhysicalConnection) _then;

/// Create a copy of PhysicalConnection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sourcePortId = null,Object? targetPortId = null,Object? busNumber = null,Object? isInputConnection = null,Object? algorithmIndex = null,}) {
  return _then(PhysicalConnection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,busNumber: null == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int,isInputConnection: null == isInputConnection ? _self.isInputConnection : isInputConnection // ignore: cast_nullable_to_non_nullable
as bool,algorithmIndex: null == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PhysicalConnection].
extension PhysicalConnectionPatterns on PhysicalConnection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PhysicalConnection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PhysicalConnection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PhysicalConnection value)  $default,){
final _that = this;
switch (_that) {
case _PhysicalConnection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PhysicalConnection value)?  $default,){
final _that = this;
switch (_that) {
case _PhysicalConnection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sourcePortId,  String targetPortId,  int busNumber,  bool isInputConnection,  int algorithmIndex)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PhysicalConnection() when $default != null:
return $default(_that.id,_that.sourcePortId,_that.targetPortId,_that.busNumber,_that.isInputConnection,_that.algorithmIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sourcePortId,  String targetPortId,  int busNumber,  bool isInputConnection,  int algorithmIndex)  $default,) {final _that = this;
switch (_that) {
case _PhysicalConnection():
return $default(_that.id,_that.sourcePortId,_that.targetPortId,_that.busNumber,_that.isInputConnection,_that.algorithmIndex);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sourcePortId,  String targetPortId,  int busNumber,  bool isInputConnection,  int algorithmIndex)?  $default,) {final _that = this;
switch (_that) {
case _PhysicalConnection() when $default != null:
return $default(_that.id,_that.sourcePortId,_that.targetPortId,_that.busNumber,_that.isInputConnection,_that.algorithmIndex);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PhysicalConnection extends PhysicalConnection {
  const _PhysicalConnection({required this.id, required this.sourcePortId, required this.targetPortId, required this.busNumber, required this.isInputConnection, required this.algorithmIndex}): super._();
  factory _PhysicalConnection.fromJson(Map<String, dynamic> json) => _$PhysicalConnectionFromJson(json);

/// Unique identifier for this connection using format: phys_${sourcePortId}->${targetPortId}
@override final  String id;
/// ID of the source port (e.g., 'hw_in_1', 'alg_0_audio_output')
@override final  String sourcePortId;
/// ID of the target port (e.g., 'alg_0_audio_input', 'hw_out_1')
@override final  String targetPortId;
/// Bus number this connection uses (1-12 for inputs, 13-20 for outputs)
@override final  int busNumber;
/// True if this is a connection from physical input to algorithm input,
/// false if this is a connection from algorithm output to physical output
@override final  bool isInputConnection;
/// Index of the algorithm involved in this connection
@override final  int algorithmIndex;

/// Create a copy of PhysicalConnection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhysicalConnectionCopyWith<_PhysicalConnection> get copyWith => __$PhysicalConnectionCopyWithImpl<_PhysicalConnection>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhysicalConnectionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PhysicalConnection&&(identical(other.id, id) || other.id == id)&&(identical(other.sourcePortId, sourcePortId) || other.sourcePortId == sourcePortId)&&(identical(other.targetPortId, targetPortId) || other.targetPortId == targetPortId)&&(identical(other.busNumber, busNumber) || other.busNumber == busNumber)&&(identical(other.isInputConnection, isInputConnection) || other.isInputConnection == isInputConnection)&&(identical(other.algorithmIndex, algorithmIndex) || other.algorithmIndex == algorithmIndex));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,sourcePortId,targetPortId,busNumber,isInputConnection,algorithmIndex);
}

@override
String toString() {
    return 'PhysicalConnection(id: $id, sourcePortId: $sourcePortId, targetPortId: $targetPortId, busNumber: $busNumber, isInputConnection: $isInputConnection, algorithmIndex: $algorithmIndex)';
}


}

/// @nodoc
abstract mixin class _$PhysicalConnectionCopyWith<$Res> implements $PhysicalConnectionCopyWith<$Res> {
  factory _$PhysicalConnectionCopyWith(_PhysicalConnection value, $Res Function(_PhysicalConnection) _then) = __$PhysicalConnectionCopyWithImpl;
@override @useResult
$Res call({
 String id, String sourcePortId, String targetPortId, int busNumber, bool isInputConnection, int algorithmIndex
});




}
/// @nodoc
class __$PhysicalConnectionCopyWithImpl<$Res>
    implements _$PhysicalConnectionCopyWith<$Res> {
  __$PhysicalConnectionCopyWithImpl(this._self, this._then);

  final _PhysicalConnection _self;
  final $Res Function(_PhysicalConnection) _then;

/// Create a copy of PhysicalConnection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sourcePortId = null,Object? targetPortId = null,Object? busNumber = null,Object? isInputConnection = null,Object? algorithmIndex = null,}) {
  return _then(_PhysicalConnection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,busNumber: null == busNumber ? _self.busNumber : busNumber // ignore: cast_nullable_to_non_nullable
as int,isInputConnection: null == isInputConnection ? _self.isInputConnection : isInputConnection // ignore: cast_nullable_to_non_nullable
as bool,algorithmIndex: null == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
