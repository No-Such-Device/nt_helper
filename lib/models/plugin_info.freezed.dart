// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plugin_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PluginInfo {

 String get name; String get path; PluginType get type; int get sizeBytes; String? get description; DateTime? get lastModified;
/// Create a copy of PluginInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginInfoCopyWith<PluginInfo> get copyWith => _$PluginInfoCopyWithImpl<PluginInfo>(this as PluginInfo, _$identity);

  /// Serializes this PluginInfo to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.sizeBytes, _this.sizeBytes) || other.sizeBytes == _this.sizeBytes)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.lastModified, _this.lastModified) || other.lastModified == _this.lastModified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginInfo;
  return Object.hash(runtimeType,_this.name,_this.path,_this.type,_this.sizeBytes,_this.description,_this.lastModified);
}

@override
String toString() {
  final _this = this as PluginInfo;
  return 'PluginInfo(name: ${_this.name}, path: ${_this.path}, type: ${_this.type}, sizeBytes: ${_this.sizeBytes}, description: ${_this.description}, lastModified: ${_this.lastModified})';
}


}

/// @nodoc
abstract mixin class $PluginInfoCopyWith<$Res>  {
  factory $PluginInfoCopyWith(PluginInfo value, $Res Function(PluginInfo) _then) = _$PluginInfoCopyWithImpl;
@useResult
$Res call({
 String name, String path, PluginType type, int sizeBytes, String? description, DateTime? lastModified
});




}
/// @nodoc
class _$PluginInfoCopyWithImpl<$Res>
    implements $PluginInfoCopyWith<$Res> {
  _$PluginInfoCopyWithImpl(this._self, this._then);

  final PluginInfo _self;
  final $Res Function(PluginInfo) _then;

/// Create a copy of PluginInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? path = null,Object? type = null,Object? sizeBytes = null,Object? description = freezed,Object? lastModified = freezed,}) {
  return _then(PluginInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as PluginType,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,lastModified: freezed == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginInfo].
extension PluginInfoPatterns on PluginInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginInfo value)  $default,){
final _that = this;
switch (_that) {
case _PluginInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginInfo value)?  $default,){
final _that = this;
switch (_that) {
case _PluginInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String path,  PluginType type,  int sizeBytes,  String? description,  DateTime? lastModified)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginInfo() when $default != null:
return $default(_that.name,_that.path,_that.type,_that.sizeBytes,_that.description,_that.lastModified);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String path,  PluginType type,  int sizeBytes,  String? description,  DateTime? lastModified)  $default,) {final _that = this;
switch (_that) {
case _PluginInfo():
return $default(_that.name,_that.path,_that.type,_that.sizeBytes,_that.description,_that.lastModified);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String path,  PluginType type,  int sizeBytes,  String? description,  DateTime? lastModified)?  $default,) {final _that = this;
switch (_that) {
case _PluginInfo() when $default != null:
return $default(_that.name,_that.path,_that.type,_that.sizeBytes,_that.description,_that.lastModified);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginInfo implements PluginInfo {
  const _PluginInfo({required this.name, required this.path, required this.type, required this.sizeBytes, this.description, this.lastModified});
  factory _PluginInfo.fromJson(Map<String, dynamic> json) => _$PluginInfoFromJson(json);

@override final  String name;
@override final  String path;
@override final  PluginType type;
@override final  int sizeBytes;
@override final  String? description;
@override final  DateTime? lastModified;

/// Create a copy of PluginInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginInfoCopyWith<_PluginInfo> get copyWith => __$PluginInfoCopyWithImpl<_PluginInfo>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginInfoToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.type, type) || other.type == type)&&(identical(other.sizeBytes, sizeBytes) || other.sizeBytes == sizeBytes)&&(identical(other.description, description) || other.description == description)&&(identical(other.lastModified, lastModified) || other.lastModified == lastModified));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,path,type,sizeBytes,description,lastModified);
}

@override
String toString() {
    return 'PluginInfo(name: $name, path: $path, type: $type, sizeBytes: $sizeBytes, description: $description, lastModified: $lastModified)';
}


}

/// @nodoc
abstract mixin class _$PluginInfoCopyWith<$Res> implements $PluginInfoCopyWith<$Res> {
  factory _$PluginInfoCopyWith(_PluginInfo value, $Res Function(_PluginInfo) _then) = __$PluginInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, String path, PluginType type, int sizeBytes, String? description, DateTime? lastModified
});




}
/// @nodoc
class __$PluginInfoCopyWithImpl<$Res>
    implements _$PluginInfoCopyWith<$Res> {
  __$PluginInfoCopyWithImpl(this._self, this._then);

  final _PluginInfo _self;
  final $Res Function(_PluginInfo) _then;

/// Create a copy of PluginInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? path = null,Object? type = null,Object? sizeBytes = null,Object? description = freezed,Object? lastModified = freezed,}) {
  return _then(_PluginInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as PluginType,sizeBytes: null == sizeBytes ? _self.sizeBytes : sizeBytes // ignore: cast_nullable_to_non_nullable
as int,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,lastModified: freezed == lastModified ? _self.lastModified : lastModified // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
