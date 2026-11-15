// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'firmware_release.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$FirmwareRelease {

/// Version string (e.g., "1.12.0")
 String get version;/// Release date
 DateTime get releaseDate;/// List of changelog entries for this release
 List<String> get changelog;/// Download URL for the firmware package
 String get downloadUrl;
/// Create a copy of FirmwareRelease
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareReleaseCopyWith<FirmwareRelease> get copyWith => _$FirmwareReleaseCopyWithImpl<FirmwareRelease>(this as FirmwareRelease, _$identity);

  /// Serializes this FirmwareRelease to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as FirmwareRelease;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareRelease&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.releaseDate, _this.releaseDate) || other.releaseDate == _this.releaseDate)&&const DeepCollectionEquality().equals(other.changelog, _this.changelog)&&(identical(other.downloadUrl, _this.downloadUrl) || other.downloadUrl == _this.downloadUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as FirmwareRelease;
  return Object.hash(runtimeType,_this.version,_this.releaseDate,const DeepCollectionEquality().hash(_this.changelog),_this.downloadUrl);
}

@override
String toString() {
  final _this = this as FirmwareRelease;
  return 'FirmwareRelease(version: ${_this.version}, releaseDate: ${_this.releaseDate}, changelog: ${_this.changelog}, downloadUrl: ${_this.downloadUrl})';
}


}

/// @nodoc
abstract mixin class $FirmwareReleaseCopyWith<$Res>  {
  factory $FirmwareReleaseCopyWith(FirmwareRelease value, $Res Function(FirmwareRelease) _then) = _$FirmwareReleaseCopyWithImpl;
@useResult
$Res call({
 String version, DateTime releaseDate, List<String> changelog, String downloadUrl
});




}
/// @nodoc
class _$FirmwareReleaseCopyWithImpl<$Res>
    implements $FirmwareReleaseCopyWith<$Res> {
  _$FirmwareReleaseCopyWithImpl(this._self, this._then);

  final FirmwareRelease _self;
  final $Res Function(FirmwareRelease) _then;

/// Create a copy of FirmwareRelease
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? releaseDate = null,Object? changelog = null,Object? downloadUrl = null,}) {
  return _then(FirmwareRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,releaseDate: null == releaseDate ? _self.releaseDate : releaseDate // ignore: cast_nullable_to_non_nullable
as DateTime,changelog: null == changelog ? _self.changelog : changelog // ignore: cast_nullable_to_non_nullable
as List<String>,downloadUrl: null == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FirmwareRelease].
extension FirmwareReleasePatterns on FirmwareRelease {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FirmwareRelease value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FirmwareRelease() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FirmwareRelease value)  $default,){
final _that = this;
switch (_that) {
case _FirmwareRelease():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FirmwareRelease value)?  $default,){
final _that = this;
switch (_that) {
case _FirmwareRelease() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  DateTime releaseDate,  List<String> changelog,  String downloadUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FirmwareRelease() when $default != null:
return $default(_that.version,_that.releaseDate,_that.changelog,_that.downloadUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  DateTime releaseDate,  List<String> changelog,  String downloadUrl)  $default,) {final _that = this;
switch (_that) {
case _FirmwareRelease():
return $default(_that.version,_that.releaseDate,_that.changelog,_that.downloadUrl);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  DateTime releaseDate,  List<String> changelog,  String downloadUrl)?  $default,) {final _that = this;
switch (_that) {
case _FirmwareRelease() when $default != null:
return $default(_that.version,_that.releaseDate,_that.changelog,_that.downloadUrl);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FirmwareRelease implements FirmwareRelease {
  const _FirmwareRelease({required this.version, required this.releaseDate, required  List<String> changelog, required this.downloadUrl}): _changelog = changelog;
  factory _FirmwareRelease.fromJson(Map<String, dynamic> json) => _$FirmwareReleaseFromJson(json);

/// Version string (e.g., "1.12.0")
@override final  String version;
/// Release date
@override final  DateTime releaseDate;
/// List of changelog entries for this release
 final  List<String> _changelog;
/// List of changelog entries for this release
@override List<String> get changelog {
  if (_changelog is EqualUnmodifiableListView) return _changelog;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changelog);
}

/// Download URL for the firmware package
@override final  String downloadUrl;

/// Create a copy of FirmwareRelease
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FirmwareReleaseCopyWith<_FirmwareRelease> get copyWith => __$FirmwareReleaseCopyWithImpl<_FirmwareRelease>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FirmwareReleaseToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FirmwareRelease&&(identical(other.version, version) || other.version == version)&&(identical(other.releaseDate, releaseDate) || other.releaseDate == releaseDate)&&const DeepCollectionEquality().equals(other.changelog, _changelog)&&(identical(other.downloadUrl, downloadUrl) || other.downloadUrl == downloadUrl));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,releaseDate,const DeepCollectionEquality().hash(_changelog),downloadUrl);
}

@override
String toString() {
    return 'FirmwareRelease(version: $version, releaseDate: $releaseDate, changelog: $changelog, downloadUrl: $downloadUrl)';
}


}

/// @nodoc
abstract mixin class _$FirmwareReleaseCopyWith<$Res> implements $FirmwareReleaseCopyWith<$Res> {
  factory _$FirmwareReleaseCopyWith(_FirmwareRelease value, $Res Function(_FirmwareRelease) _then) = __$FirmwareReleaseCopyWithImpl;
@override @useResult
$Res call({
 String version, DateTime releaseDate, List<String> changelog, String downloadUrl
});




}
/// @nodoc
class __$FirmwareReleaseCopyWithImpl<$Res>
    implements _$FirmwareReleaseCopyWith<$Res> {
  __$FirmwareReleaseCopyWithImpl(this._self, this._then);

  final _FirmwareRelease _self;
  final $Res Function(_FirmwareRelease) _then;

/// Create a copy of FirmwareRelease
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? releaseDate = null,Object? changelog = null,Object? downloadUrl = null,}) {
  return _then(_FirmwareRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,releaseDate: null == releaseDate ? _self.releaseDate : releaseDate // ignore: cast_nullable_to_non_nullable
as DateTime,changelog: null == changelog ? _self._changelog : changelog // ignore: cast_nullable_to_non_nullable
as List<String>,downloadUrl: null == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
