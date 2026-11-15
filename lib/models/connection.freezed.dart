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

 String get id; int get sourceAlgorithmIndex; String get sourcePortId; int get targetAlgorithmIndex; String get targetPortId; int get assignedBus; bool get replaceMode; bool get isValid; String? get edgeLabel;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Connection&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sourceAlgorithmIndex, _this.sourceAlgorithmIndex) || other.sourceAlgorithmIndex == _this.sourceAlgorithmIndex)&&(identical(other.sourcePortId, _this.sourcePortId) || other.sourcePortId == _this.sourcePortId)&&(identical(other.targetAlgorithmIndex, _this.targetAlgorithmIndex) || other.targetAlgorithmIndex == _this.targetAlgorithmIndex)&&(identical(other.targetPortId, _this.targetPortId) || other.targetPortId == _this.targetPortId)&&(identical(other.assignedBus, _this.assignedBus) || other.assignedBus == _this.assignedBus)&&(identical(other.replaceMode, _this.replaceMode) || other.replaceMode == _this.replaceMode)&&(identical(other.isValid, _this.isValid) || other.isValid == _this.isValid)&&(identical(other.edgeLabel, _this.edgeLabel) || other.edgeLabel == _this.edgeLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Connection;
  return Object.hash(runtimeType,_this.id,_this.sourceAlgorithmIndex,_this.sourcePortId,_this.targetAlgorithmIndex,_this.targetPortId,_this.assignedBus,_this.replaceMode,_this.isValid,_this.edgeLabel);
}

@override
String toString() {
  final _this = this as Connection;
  return 'Connection(id: ${_this.id}, sourceAlgorithmIndex: ${_this.sourceAlgorithmIndex}, sourcePortId: ${_this.sourcePortId}, targetAlgorithmIndex: ${_this.targetAlgorithmIndex}, targetPortId: ${_this.targetPortId}, assignedBus: ${_this.assignedBus}, replaceMode: ${_this.replaceMode}, isValid: ${_this.isValid}, edgeLabel: ${_this.edgeLabel})';
}


}

/// @nodoc
abstract mixin class $ConnectionCopyWith<$Res>  {
  factory $ConnectionCopyWith(Connection value, $Res Function(Connection) _then) = _$ConnectionCopyWithImpl;
@useResult
$Res call({
 String id, int sourceAlgorithmIndex, String sourcePortId, int targetAlgorithmIndex, String targetPortId, int assignedBus, bool replaceMode, bool isValid, String? edgeLabel
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sourceAlgorithmIndex = null,Object? sourcePortId = null,Object? targetAlgorithmIndex = null,Object? targetPortId = null,Object? assignedBus = null,Object? replaceMode = null,Object? isValid = null,Object? edgeLabel = freezed,}) {
  return _then(Connection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceAlgorithmIndex: null == sourceAlgorithmIndex ? _self.sourceAlgorithmIndex : sourceAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetAlgorithmIndex: null == targetAlgorithmIndex ? _self.targetAlgorithmIndex : targetAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,assignedBus: null == assignedBus ? _self.assignedBus : assignedBus // ignore: cast_nullable_to_non_nullable
as int,replaceMode: null == replaceMode ? _self.replaceMode : replaceMode // ignore: cast_nullable_to_non_nullable
as bool,isValid: null == isValid ? _self.isValid : isValid // ignore: cast_nullable_to_non_nullable
as bool,edgeLabel: freezed == edgeLabel ? _self.edgeLabel : edgeLabel // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int assignedBus,  bool replaceMode,  bool isValid,  String? edgeLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Connection() when $default != null:
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.assignedBus,_that.replaceMode,_that.isValid,_that.edgeLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int assignedBus,  bool replaceMode,  bool isValid,  String? edgeLabel)  $default,) {final _that = this;
switch (_that) {
case _Connection():
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.assignedBus,_that.replaceMode,_that.isValid,_that.edgeLabel);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int sourceAlgorithmIndex,  String sourcePortId,  int targetAlgorithmIndex,  String targetPortId,  int assignedBus,  bool replaceMode,  bool isValid,  String? edgeLabel)?  $default,) {final _that = this;
switch (_that) {
case _Connection() when $default != null:
return $default(_that.id,_that.sourceAlgorithmIndex,_that.sourcePortId,_that.targetAlgorithmIndex,_that.targetPortId,_that.assignedBus,_that.replaceMode,_that.isValid,_that.edgeLabel);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Connection implements Connection {
  const _Connection({required this.id, required this.sourceAlgorithmIndex, required this.sourcePortId, required this.targetAlgorithmIndex, required this.targetPortId, required this.assignedBus, required this.replaceMode, this.isValid = false, this.edgeLabel});
  factory _Connection.fromJson(Map<String, dynamic> json) => _$ConnectionFromJson(json);

@override final  String id;
@override final  int sourceAlgorithmIndex;
@override final  String sourcePortId;
@override final  int targetAlgorithmIndex;
@override final  String targetPortId;
@override final  int assignedBus;
@override final  bool replaceMode;
@override@JsonKey() final  bool isValid;
@override final  String? edgeLabel;

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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Connection&&(identical(other.id, id) || other.id == id)&&(identical(other.sourceAlgorithmIndex, sourceAlgorithmIndex) || other.sourceAlgorithmIndex == sourceAlgorithmIndex)&&(identical(other.sourcePortId, sourcePortId) || other.sourcePortId == sourcePortId)&&(identical(other.targetAlgorithmIndex, targetAlgorithmIndex) || other.targetAlgorithmIndex == targetAlgorithmIndex)&&(identical(other.targetPortId, targetPortId) || other.targetPortId == targetPortId)&&(identical(other.assignedBus, assignedBus) || other.assignedBus == assignedBus)&&(identical(other.replaceMode, replaceMode) || other.replaceMode == replaceMode)&&(identical(other.isValid, isValid) || other.isValid == isValid)&&(identical(other.edgeLabel, edgeLabel) || other.edgeLabel == edgeLabel));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,sourceAlgorithmIndex,sourcePortId,targetAlgorithmIndex,targetPortId,assignedBus,replaceMode,isValid,edgeLabel);
}

@override
String toString() {
    return 'Connection(id: $id, sourceAlgorithmIndex: $sourceAlgorithmIndex, sourcePortId: $sourcePortId, targetAlgorithmIndex: $targetAlgorithmIndex, targetPortId: $targetPortId, assignedBus: $assignedBus, replaceMode: $replaceMode, isValid: $isValid, edgeLabel: $edgeLabel)';
}


}

/// @nodoc
abstract mixin class _$ConnectionCopyWith<$Res> implements $ConnectionCopyWith<$Res> {
  factory _$ConnectionCopyWith(_Connection value, $Res Function(_Connection) _then) = __$ConnectionCopyWithImpl;
@override @useResult
$Res call({
 String id, int sourceAlgorithmIndex, String sourcePortId, int targetAlgorithmIndex, String targetPortId, int assignedBus, bool replaceMode, bool isValid, String? edgeLabel
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sourceAlgorithmIndex = null,Object? sourcePortId = null,Object? targetAlgorithmIndex = null,Object? targetPortId = null,Object? assignedBus = null,Object? replaceMode = null,Object? isValid = null,Object? edgeLabel = freezed,}) {
  return _then(_Connection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sourceAlgorithmIndex: null == sourceAlgorithmIndex ? _self.sourceAlgorithmIndex : sourceAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,sourcePortId: null == sourcePortId ? _self.sourcePortId : sourcePortId // ignore: cast_nullable_to_non_nullable
as String,targetAlgorithmIndex: null == targetAlgorithmIndex ? _self.targetAlgorithmIndex : targetAlgorithmIndex // ignore: cast_nullable_to_non_nullable
as int,targetPortId: null == targetPortId ? _self.targetPortId : targetPortId // ignore: cast_nullable_to_non_nullable
as String,assignedBus: null == assignedBus ? _self.assignedBus : assignedBus // ignore: cast_nullable_to_non_nullable
as int,replaceMode: null == replaceMode ? _self.replaceMode : replaceMode // ignore: cast_nullable_to_non_nullable
as bool,isValid: null == isValid ? _self.isValid : isValid // ignore: cast_nullable_to_non_nullable
as bool,edgeLabel: freezed == edgeLabel ? _self.edgeLabel : edgeLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
