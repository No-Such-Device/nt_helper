// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gallery_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$GalleryMetadata {

 String get name; String get description; GalleryMaintainer get maintainer;
/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryMetadataCopyWith<GalleryMetadata> get copyWith => _$GalleryMetadataCopyWithImpl<GalleryMetadata>(this as GalleryMetadata, _$identity);

  /// Serializes this GalleryMetadata to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GalleryMetadata;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryMetadata&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.maintainer, _this.maintainer) || other.maintainer == _this.maintainer));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GalleryMetadata;
  return Object.hash(runtimeType,_this.name,_this.description,_this.maintainer);
}

@override
String toString() {
  final _this = this as GalleryMetadata;
  return 'GalleryMetadata(name: ${_this.name}, description: ${_this.description}, maintainer: ${_this.maintainer})';
}


}

/// @nodoc
abstract mixin class $GalleryMetadataCopyWith<$Res>  {
  factory $GalleryMetadataCopyWith(GalleryMetadata value, $Res Function(GalleryMetadata) _then) = _$GalleryMetadataCopyWithImpl;
@useResult
$Res call({
 String name, String description, GalleryMaintainer maintainer
});


$GalleryMaintainerCopyWith<$Res> get maintainer;

}
/// @nodoc
class _$GalleryMetadataCopyWithImpl<$Res>
    implements $GalleryMetadataCopyWith<$Res> {
  _$GalleryMetadataCopyWithImpl(this._self, this._then);

  final GalleryMetadata _self;
  final $Res Function(GalleryMetadata) _then;

/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? description = null,Object? maintainer = null,}) {
  return _then(GalleryMetadata(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,maintainer: null == maintainer ? _self.maintainer : maintainer // ignore: cast_nullable_to_non_nullable
as GalleryMaintainer,
  ));
}
/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryMaintainerCopyWith<$Res> get maintainer {

  return $GalleryMaintainerCopyWith<$Res>(_self.maintainer, (value) {
    return _then(_self.copyWith(maintainer: value));
  });
}
}


/// Adds pattern-matching-related methods to [GalleryMetadata].
extension GalleryMetadataPatterns on GalleryMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryMetadata value)  $default,){
final _that = this;
switch (_that) {
case _GalleryMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String description,  GalleryMaintainer maintainer)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryMetadata() when $default != null:
return $default(_that.name,_that.description,_that.maintainer);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String description,  GalleryMaintainer maintainer)  $default,) {final _that = this;
switch (_that) {
case _GalleryMetadata():
return $default(_that.name,_that.description,_that.maintainer);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String description,  GalleryMaintainer maintainer)?  $default,) {final _that = this;
switch (_that) {
case _GalleryMetadata() when $default != null:
return $default(_that.name,_that.description,_that.maintainer);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GalleryMetadata implements GalleryMetadata {
  const _GalleryMetadata({required this.name, required this.description, required this.maintainer});
  factory _GalleryMetadata.fromJson(Map<String, dynamic> json) => _$GalleryMetadataFromJson(json);

@override final  String name;
@override final  String description;
@override final  GalleryMaintainer maintainer;

/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryMetadataCopyWith<_GalleryMetadata> get copyWith => __$GalleryMetadataCopyWithImpl<_GalleryMetadata>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryMetadataToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryMetadata&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.maintainer, maintainer) || other.maintainer == maintainer));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,description,maintainer);
}

@override
String toString() {
    return 'GalleryMetadata(name: $name, description: $description, maintainer: $maintainer)';
}


}

/// @nodoc
abstract mixin class _$GalleryMetadataCopyWith<$Res> implements $GalleryMetadataCopyWith<$Res> {
  factory _$GalleryMetadataCopyWith(_GalleryMetadata value, $Res Function(_GalleryMetadata) _then) = __$GalleryMetadataCopyWithImpl;
@override @useResult
$Res call({
 String name, String description, GalleryMaintainer maintainer
});


@override $GalleryMaintainerCopyWith<$Res> get maintainer;

}
/// @nodoc
class __$GalleryMetadataCopyWithImpl<$Res>
    implements _$GalleryMetadataCopyWith<$Res> {
  __$GalleryMetadataCopyWithImpl(this._self, this._then);

  final _GalleryMetadata _self;
  final $Res Function(_GalleryMetadata) _then;

/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? description = null,Object? maintainer = null,}) {
  return _then(_GalleryMetadata(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,maintainer: null == maintainer ? _self.maintainer : maintainer // ignore: cast_nullable_to_non_nullable
as GalleryMaintainer,
  ));
}

/// Create a copy of GalleryMetadata
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryMaintainerCopyWith<$Res> get maintainer {

  return $GalleryMaintainerCopyWith<$Res>(_self.maintainer, (value) {
    return _then(_self.copyWith(maintainer: value));
  });
}
}


/// @nodoc
mixin _$GalleryMaintainer {

 String get name; String? get email; String? get url;
/// Create a copy of GalleryMaintainer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryMaintainerCopyWith<GalleryMaintainer> get copyWith => _$GalleryMaintainerCopyWithImpl<GalleryMaintainer>(this as GalleryMaintainer, _$identity);

  /// Serializes this GalleryMaintainer to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GalleryMaintainer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryMaintainer&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.email, _this.email) || other.email == _this.email)&&(identical(other.url, _this.url) || other.url == _this.url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GalleryMaintainer;
  return Object.hash(runtimeType,_this.name,_this.email,_this.url);
}

@override
String toString() {
  final _this = this as GalleryMaintainer;
  return 'GalleryMaintainer(name: ${_this.name}, email: ${_this.email}, url: ${_this.url})';
}


}

/// @nodoc
abstract mixin class $GalleryMaintainerCopyWith<$Res>  {
  factory $GalleryMaintainerCopyWith(GalleryMaintainer value, $Res Function(GalleryMaintainer) _then) = _$GalleryMaintainerCopyWithImpl;
@useResult
$Res call({
 String name, String? email, String? url
});




}
/// @nodoc
class _$GalleryMaintainerCopyWithImpl<$Res>
    implements $GalleryMaintainerCopyWith<$Res> {
  _$GalleryMaintainerCopyWithImpl(this._self, this._then);

  final GalleryMaintainer _self;
  final $Res Function(GalleryMaintainer) _then;

/// Create a copy of GalleryMaintainer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? email = freezed,Object? url = freezed,}) {
  return _then(GalleryMaintainer(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [GalleryMaintainer].
extension GalleryMaintainerPatterns on GalleryMaintainer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryMaintainer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryMaintainer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryMaintainer value)  $default,){
final _that = this;
switch (_that) {
case _GalleryMaintainer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryMaintainer value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryMaintainer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? email,  String? url)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryMaintainer() when $default != null:
return $default(_that.name,_that.email,_that.url);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? email,  String? url)  $default,) {final _that = this;
switch (_that) {
case _GalleryMaintainer():
return $default(_that.name,_that.email,_that.url);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? email,  String? url)?  $default,) {final _that = this;
switch (_that) {
case _GalleryMaintainer() when $default != null:
return $default(_that.name,_that.email,_that.url);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GalleryMaintainer implements GalleryMaintainer {
  const _GalleryMaintainer({required this.name, this.email, this.url});
  factory _GalleryMaintainer.fromJson(Map<String, dynamic> json) => _$GalleryMaintainerFromJson(json);

@override final  String name;
@override final  String? email;
@override final  String? url;

/// Create a copy of GalleryMaintainer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryMaintainerCopyWith<_GalleryMaintainer> get copyWith => __$GalleryMaintainerCopyWithImpl<_GalleryMaintainer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryMaintainerToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryMaintainer&&(identical(other.name, name) || other.name == name)&&(identical(other.email, email) || other.email == email)&&(identical(other.url, url) || other.url == url));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,email,url);
}

@override
String toString() {
    return 'GalleryMaintainer(name: $name, email: $email, url: $url)';
}


}

/// @nodoc
abstract mixin class _$GalleryMaintainerCopyWith<$Res> implements $GalleryMaintainerCopyWith<$Res> {
  factory _$GalleryMaintainerCopyWith(_GalleryMaintainer value, $Res Function(_GalleryMaintainer) _then) = __$GalleryMaintainerCopyWithImpl;
@override @useResult
$Res call({
 String name, String? email, String? url
});




}
/// @nodoc
class __$GalleryMaintainerCopyWithImpl<$Res>
    implements _$GalleryMaintainerCopyWith<$Res> {
  __$GalleryMaintainerCopyWithImpl(this._self, this._then);

  final _GalleryMaintainer _self;
  final $Res Function(_GalleryMaintainer) _then;

/// Create a copy of GalleryMaintainer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? email = freezed,Object? url = freezed,}) {
  return _then(_GalleryMaintainer(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,url: freezed == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginCategory {

 String get id; String get name; String? get description; String? get icon;
/// Create a copy of PluginCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginCategoryCopyWith<PluginCategory> get copyWith => _$PluginCategoryCopyWithImpl<PluginCategory>(this as PluginCategory, _$identity);

  /// Serializes this PluginCategory to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginCategory;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginCategory&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.icon, _this.icon) || other.icon == _this.icon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginCategory;
  return Object.hash(runtimeType,_this.id,_this.name,_this.description,_this.icon);
}

@override
String toString() {
  final _this = this as PluginCategory;
  return 'PluginCategory(id: ${_this.id}, name: ${_this.name}, description: ${_this.description}, icon: ${_this.icon})';
}


}

/// @nodoc
abstract mixin class $PluginCategoryCopyWith<$Res>  {
  factory $PluginCategoryCopyWith(PluginCategory value, $Res Function(PluginCategory) _then) = _$PluginCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, String? icon
});




}
/// @nodoc
class _$PluginCategoryCopyWithImpl<$Res>
    implements $PluginCategoryCopyWith<$Res> {
  _$PluginCategoryCopyWithImpl(this._self, this._then);

  final PluginCategory _self;
  final $Res Function(PluginCategory) _then;

/// Create a copy of PluginCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? icon = freezed,}) {
  return _then(PluginCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginCategory].
extension PluginCategoryPatterns on PluginCategory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginCategory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginCategory() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginCategory value)  $default,){
final _that = this;
switch (_that) {
case _PluginCategory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginCategory value)?  $default,){
final _that = this;
switch (_that) {
case _PluginCategory() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? icon)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginCategory() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.icon);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String? icon)  $default,) {final _that = this;
switch (_that) {
case _PluginCategory():
return $default(_that.id,_that.name,_that.description,_that.icon);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  String? icon)?  $default,) {final _that = this;
switch (_that) {
case _PluginCategory() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.icon);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginCategory implements PluginCategory {
  const _PluginCategory({required this.id, required this.name, this.description, this.icon});
  factory _PluginCategory.fromJson(Map<String, dynamic> json) => _$PluginCategoryFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  String? icon;

/// Create a copy of PluginCategory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginCategoryCopyWith<_PluginCategory> get copyWith => __$PluginCategoryCopyWithImpl<_PluginCategory>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginCategoryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.icon, icon) || other.icon == icon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description,icon);
}

@override
String toString() {
    return 'PluginCategory(id: $id, name: $name, description: $description, icon: $icon)';
}


}

/// @nodoc
abstract mixin class _$PluginCategoryCopyWith<$Res> implements $PluginCategoryCopyWith<$Res> {
  factory _$PluginCategoryCopyWith(_PluginCategory value, $Res Function(_PluginCategory) _then) = __$PluginCategoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, String? icon
});




}
/// @nodoc
class __$PluginCategoryCopyWithImpl<$Res>
    implements _$PluginCategoryCopyWith<$Res> {
  __$PluginCategoryCopyWithImpl(this._self, this._then);

  final _PluginCategory _self;
  final $Res Function(_PluginCategory) _then;

/// Create a copy of PluginCategory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? icon = freezed,}) {
  return _then(_PluginCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,icon: freezed == icon ? _self.icon : icon // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginAuthor {

 String get name; String? get bio; String? get website; String? get avatar; bool get verified; PluginAuthorSocialLinks? get socialLinks;
/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginAuthorCopyWith<PluginAuthor> get copyWith => _$PluginAuthorCopyWithImpl<PluginAuthor>(this as PluginAuthor, _$identity);

  /// Serializes this PluginAuthor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginAuthor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginAuthor&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.bio, _this.bio) || other.bio == _this.bio)&&(identical(other.website, _this.website) || other.website == _this.website)&&(identical(other.avatar, _this.avatar) || other.avatar == _this.avatar)&&(identical(other.verified, _this.verified) || other.verified == _this.verified)&&(identical(other.socialLinks, _this.socialLinks) || other.socialLinks == _this.socialLinks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginAuthor;
  return Object.hash(runtimeType,_this.name,_this.bio,_this.website,_this.avatar,_this.verified,_this.socialLinks);
}

@override
String toString() {
  final _this = this as PluginAuthor;
  return 'PluginAuthor(name: ${_this.name}, bio: ${_this.bio}, website: ${_this.website}, avatar: ${_this.avatar}, verified: ${_this.verified}, socialLinks: ${_this.socialLinks})';
}


}

/// @nodoc
abstract mixin class $PluginAuthorCopyWith<$Res>  {
  factory $PluginAuthorCopyWith(PluginAuthor value, $Res Function(PluginAuthor) _then) = _$PluginAuthorCopyWithImpl;
@useResult
$Res call({
 String name, String? bio, String? website, String? avatar, bool verified, PluginAuthorSocialLinks? socialLinks
});


$PluginAuthorSocialLinksCopyWith<$Res>? get socialLinks;

}
/// @nodoc
class _$PluginAuthorCopyWithImpl<$Res>
    implements $PluginAuthorCopyWith<$Res> {
  _$PluginAuthorCopyWithImpl(this._self, this._then);

  final PluginAuthor _self;
  final $Res Function(PluginAuthor) _then;

/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? bio = freezed,Object? website = freezed,Object? avatar = freezed,Object? verified = null,Object? socialLinks = freezed,}) {
  return _then(PluginAuthor(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,avatar: freezed == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String?,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,socialLinks: freezed == socialLinks ? _self.socialLinks : socialLinks // ignore: cast_nullable_to_non_nullable
as PluginAuthorSocialLinks?,
  ));
}
/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginAuthorSocialLinksCopyWith<$Res>? get socialLinks {
    if (_self.socialLinks == null) {
    return null;
  }

  return $PluginAuthorSocialLinksCopyWith<$Res>(_self.socialLinks!, (value) {
    return _then(_self.copyWith(socialLinks: value));
  });
}
}


/// Adds pattern-matching-related methods to [PluginAuthor].
extension PluginAuthorPatterns on PluginAuthor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginAuthor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginAuthor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginAuthor value)  $default,){
final _that = this;
switch (_that) {
case _PluginAuthor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginAuthor value)?  $default,){
final _that = this;
switch (_that) {
case _PluginAuthor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? bio,  String? website,  String? avatar,  bool verified,  PluginAuthorSocialLinks? socialLinks)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginAuthor() when $default != null:
return $default(_that.name,_that.bio,_that.website,_that.avatar,_that.verified,_that.socialLinks);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? bio,  String? website,  String? avatar,  bool verified,  PluginAuthorSocialLinks? socialLinks)  $default,) {final _that = this;
switch (_that) {
case _PluginAuthor():
return $default(_that.name,_that.bio,_that.website,_that.avatar,_that.verified,_that.socialLinks);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? bio,  String? website,  String? avatar,  bool verified,  PluginAuthorSocialLinks? socialLinks)?  $default,) {final _that = this;
switch (_that) {
case _PluginAuthor() when $default != null:
return $default(_that.name,_that.bio,_that.website,_that.avatar,_that.verified,_that.socialLinks);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginAuthor implements PluginAuthor {
  const _PluginAuthor({required this.name, this.bio, this.website, this.avatar, this.verified = false, this.socialLinks});
  factory _PluginAuthor.fromJson(Map<String, dynamic> json) => _$PluginAuthorFromJson(json);

@override final  String name;
@override final  String? bio;
@override final  String? website;
@override final  String? avatar;
@override@JsonKey() final  bool verified;
@override final  PluginAuthorSocialLinks? socialLinks;

/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginAuthorCopyWith<_PluginAuthor> get copyWith => __$PluginAuthorCopyWithImpl<_PluginAuthor>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginAuthorToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginAuthor&&(identical(other.name, name) || other.name == name)&&(identical(other.bio, bio) || other.bio == bio)&&(identical(other.website, website) || other.website == website)&&(identical(other.avatar, avatar) || other.avatar == avatar)&&(identical(other.verified, verified) || other.verified == verified)&&(identical(other.socialLinks, socialLinks) || other.socialLinks == socialLinks));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,bio,website,avatar,verified,socialLinks);
}

@override
String toString() {
    return 'PluginAuthor(name: $name, bio: $bio, website: $website, avatar: $avatar, verified: $verified, socialLinks: $socialLinks)';
}


}

/// @nodoc
abstract mixin class _$PluginAuthorCopyWith<$Res> implements $PluginAuthorCopyWith<$Res> {
  factory _$PluginAuthorCopyWith(_PluginAuthor value, $Res Function(_PluginAuthor) _then) = __$PluginAuthorCopyWithImpl;
@override @useResult
$Res call({
 String name, String? bio, String? website, String? avatar, bool verified, PluginAuthorSocialLinks? socialLinks
});


@override $PluginAuthorSocialLinksCopyWith<$Res>? get socialLinks;

}
/// @nodoc
class __$PluginAuthorCopyWithImpl<$Res>
    implements _$PluginAuthorCopyWith<$Res> {
  __$PluginAuthorCopyWithImpl(this._self, this._then);

  final _PluginAuthor _self;
  final $Res Function(_PluginAuthor) _then;

/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? bio = freezed,Object? website = freezed,Object? avatar = freezed,Object? verified = null,Object? socialLinks = freezed,}) {
  return _then(_PluginAuthor(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,bio: freezed == bio ? _self.bio : bio // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,avatar: freezed == avatar ? _self.avatar : avatar // ignore: cast_nullable_to_non_nullable
as String?,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,socialLinks: freezed == socialLinks ? _self.socialLinks : socialLinks // ignore: cast_nullable_to_non_nullable
as PluginAuthorSocialLinks?,
  ));
}

/// Create a copy of PluginAuthor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginAuthorSocialLinksCopyWith<$Res>? get socialLinks {
    if (_self.socialLinks == null) {
    return null;
  }

  return $PluginAuthorSocialLinksCopyWith<$Res>(_self.socialLinks!, (value) {
    return _then(_self.copyWith(socialLinks: value));
  });
}
}


/// @nodoc
mixin _$PluginAuthorSocialLinks {

 String? get github; String? get twitter; String? get discord;
/// Create a copy of PluginAuthorSocialLinks
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginAuthorSocialLinksCopyWith<PluginAuthorSocialLinks> get copyWith => _$PluginAuthorSocialLinksCopyWithImpl<PluginAuthorSocialLinks>(this as PluginAuthorSocialLinks, _$identity);

  /// Serializes this PluginAuthorSocialLinks to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginAuthorSocialLinks;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginAuthorSocialLinks&&(identical(other.github, _this.github) || other.github == _this.github)&&(identical(other.twitter, _this.twitter) || other.twitter == _this.twitter)&&(identical(other.discord, _this.discord) || other.discord == _this.discord));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginAuthorSocialLinks;
  return Object.hash(runtimeType,_this.github,_this.twitter,_this.discord);
}

@override
String toString() {
  final _this = this as PluginAuthorSocialLinks;
  return 'PluginAuthorSocialLinks(github: ${_this.github}, twitter: ${_this.twitter}, discord: ${_this.discord})';
}


}

/// @nodoc
abstract mixin class $PluginAuthorSocialLinksCopyWith<$Res>  {
  factory $PluginAuthorSocialLinksCopyWith(PluginAuthorSocialLinks value, $Res Function(PluginAuthorSocialLinks) _then) = _$PluginAuthorSocialLinksCopyWithImpl;
@useResult
$Res call({
 String? github, String? twitter, String? discord
});




}
/// @nodoc
class _$PluginAuthorSocialLinksCopyWithImpl<$Res>
    implements $PluginAuthorSocialLinksCopyWith<$Res> {
  _$PluginAuthorSocialLinksCopyWithImpl(this._self, this._then);

  final PluginAuthorSocialLinks _self;
  final $Res Function(PluginAuthorSocialLinks) _then;

/// Create a copy of PluginAuthorSocialLinks
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? github = freezed,Object? twitter = freezed,Object? discord = freezed,}) {
  return _then(PluginAuthorSocialLinks(
github: freezed == github ? _self.github : github // ignore: cast_nullable_to_non_nullable
as String?,twitter: freezed == twitter ? _self.twitter : twitter // ignore: cast_nullable_to_non_nullable
as String?,discord: freezed == discord ? _self.discord : discord // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginAuthorSocialLinks].
extension PluginAuthorSocialLinksPatterns on PluginAuthorSocialLinks {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginAuthorSocialLinks value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginAuthorSocialLinks value)  $default,){
final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginAuthorSocialLinks value)?  $default,){
final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? github,  String? twitter,  String? discord)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks() when $default != null:
return $default(_that.github,_that.twitter,_that.discord);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? github,  String? twitter,  String? discord)  $default,) {final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks():
return $default(_that.github,_that.twitter,_that.discord);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? github,  String? twitter,  String? discord)?  $default,) {final _that = this;
switch (_that) {
case _PluginAuthorSocialLinks() when $default != null:
return $default(_that.github,_that.twitter,_that.discord);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginAuthorSocialLinks implements PluginAuthorSocialLinks {
  const _PluginAuthorSocialLinks({this.github, this.twitter, this.discord});
  factory _PluginAuthorSocialLinks.fromJson(Map<String, dynamic> json) => _$PluginAuthorSocialLinksFromJson(json);

@override final  String? github;
@override final  String? twitter;
@override final  String? discord;

/// Create a copy of PluginAuthorSocialLinks
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginAuthorSocialLinksCopyWith<_PluginAuthorSocialLinks> get copyWith => __$PluginAuthorSocialLinksCopyWithImpl<_PluginAuthorSocialLinks>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginAuthorSocialLinksToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginAuthorSocialLinks&&(identical(other.github, github) || other.github == github)&&(identical(other.twitter, twitter) || other.twitter == twitter)&&(identical(other.discord, discord) || other.discord == discord));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,github,twitter,discord);
}

@override
String toString() {
    return 'PluginAuthorSocialLinks(github: $github, twitter: $twitter, discord: $discord)';
}


}

/// @nodoc
abstract mixin class _$PluginAuthorSocialLinksCopyWith<$Res> implements $PluginAuthorSocialLinksCopyWith<$Res> {
  factory _$PluginAuthorSocialLinksCopyWith(_PluginAuthorSocialLinks value, $Res Function(_PluginAuthorSocialLinks) _then) = __$PluginAuthorSocialLinksCopyWithImpl;
@override @useResult
$Res call({
 String? github, String? twitter, String? discord
});




}
/// @nodoc
class __$PluginAuthorSocialLinksCopyWithImpl<$Res>
    implements _$PluginAuthorSocialLinksCopyWith<$Res> {
  __$PluginAuthorSocialLinksCopyWithImpl(this._self, this._then);

  final _PluginAuthorSocialLinks _self;
  final $Res Function(_PluginAuthorSocialLinks) _then;

/// Create a copy of PluginAuthorSocialLinks
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? github = freezed,Object? twitter = freezed,Object? discord = freezed,}) {
  return _then(_PluginAuthorSocialLinks(
github: freezed == github ? _self.github : github // ignore: cast_nullable_to_non_nullable
as String?,twitter: freezed == twitter ? _self.twitter : twitter // ignore: cast_nullable_to_non_nullable
as String?,discord: freezed == discord ? _self.discord : discord // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginRepository {

 String get owner; String get name; String get url; String? get branch;
/// Create a copy of PluginRepository
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginRepositoryCopyWith<PluginRepository> get copyWith => _$PluginRepositoryCopyWithImpl<PluginRepository>(this as PluginRepository, _$identity);

  /// Serializes this PluginRepository to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginRepository;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginRepository&&(identical(other.owner, _this.owner) || other.owner == _this.owner)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.branch, _this.branch) || other.branch == _this.branch));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginRepository;
  return Object.hash(runtimeType,_this.owner,_this.name,_this.url,_this.branch);
}

@override
String toString() {
  final _this = this as PluginRepository;
  return 'PluginRepository(owner: ${_this.owner}, name: ${_this.name}, url: ${_this.url}, branch: ${_this.branch})';
}


}

/// @nodoc
abstract mixin class $PluginRepositoryCopyWith<$Res>  {
  factory $PluginRepositoryCopyWith(PluginRepository value, $Res Function(PluginRepository) _then) = _$PluginRepositoryCopyWithImpl;
@useResult
$Res call({
 String owner, String name, String url, String? branch
});




}
/// @nodoc
class _$PluginRepositoryCopyWithImpl<$Res>
    implements $PluginRepositoryCopyWith<$Res> {
  _$PluginRepositoryCopyWithImpl(this._self, this._then);

  final PluginRepository _self;
  final $Res Function(PluginRepository) _then;

/// Create a copy of PluginRepository
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? owner = null,Object? name = null,Object? url = null,Object? branch = freezed,}) {
  return _then(PluginRepository(
owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,branch: freezed == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginRepository].
extension PluginRepositoryPatterns on PluginRepository {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginRepository value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginRepository() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginRepository value)  $default,){
final _that = this;
switch (_that) {
case _PluginRepository():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginRepository value)?  $default,){
final _that = this;
switch (_that) {
case _PluginRepository() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String owner,  String name,  String url,  String? branch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginRepository() when $default != null:
return $default(_that.owner,_that.name,_that.url,_that.branch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String owner,  String name,  String url,  String? branch)  $default,) {final _that = this;
switch (_that) {
case _PluginRepository():
return $default(_that.owner,_that.name,_that.url,_that.branch);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String owner,  String name,  String url,  String? branch)?  $default,) {final _that = this;
switch (_that) {
case _PluginRepository() when $default != null:
return $default(_that.owner,_that.name,_that.url,_that.branch);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginRepository implements PluginRepository {
  const _PluginRepository({required this.owner, required this.name, required this.url, this.branch});
  factory _PluginRepository.fromJson(Map<String, dynamic> json) => _$PluginRepositoryFromJson(json);

@override final  String owner;
@override final  String name;
@override final  String url;
@override final  String? branch;

/// Create a copy of PluginRepository
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginRepositoryCopyWith<_PluginRepository> get copyWith => __$PluginRepositoryCopyWithImpl<_PluginRepository>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginRepositoryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginRepository&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.name, name) || other.name == name)&&(identical(other.url, url) || other.url == url)&&(identical(other.branch, branch) || other.branch == branch));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,owner,name,url,branch);
}

@override
String toString() {
    return 'PluginRepository(owner: $owner, name: $name, url: $url, branch: $branch)';
}


}

/// @nodoc
abstract mixin class _$PluginRepositoryCopyWith<$Res> implements $PluginRepositoryCopyWith<$Res> {
  factory _$PluginRepositoryCopyWith(_PluginRepository value, $Res Function(_PluginRepository) _then) = __$PluginRepositoryCopyWithImpl;
@override @useResult
$Res call({
 String owner, String name, String url, String? branch
});




}
/// @nodoc
class __$PluginRepositoryCopyWithImpl<$Res>
    implements _$PluginRepositoryCopyWith<$Res> {
  __$PluginRepositoryCopyWithImpl(this._self, this._then);

  final _PluginRepository _self;
  final $Res Function(_PluginRepository) _then;

/// Create a copy of PluginRepository
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? owner = null,Object? name = null,Object? url = null,Object? branch = freezed,}) {
  return _then(_PluginRepository(
owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,branch: freezed == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginReleases {

 String get latest; String? get stable; String? get beta;
/// Create a copy of PluginReleases
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginReleasesCopyWith<PluginReleases> get copyWith => _$PluginReleasesCopyWithImpl<PluginReleases>(this as PluginReleases, _$identity);

  /// Serializes this PluginReleases to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginReleases;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginReleases&&(identical(other.latest, _this.latest) || other.latest == _this.latest)&&(identical(other.stable, _this.stable) || other.stable == _this.stable)&&(identical(other.beta, _this.beta) || other.beta == _this.beta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginReleases;
  return Object.hash(runtimeType,_this.latest,_this.stable,_this.beta);
}

@override
String toString() {
  final _this = this as PluginReleases;
  return 'PluginReleases(latest: ${_this.latest}, stable: ${_this.stable}, beta: ${_this.beta})';
}


}

/// @nodoc
abstract mixin class $PluginReleasesCopyWith<$Res>  {
  factory $PluginReleasesCopyWith(PluginReleases value, $Res Function(PluginReleases) _then) = _$PluginReleasesCopyWithImpl;
@useResult
$Res call({
 String latest, String? stable, String? beta
});




}
/// @nodoc
class _$PluginReleasesCopyWithImpl<$Res>
    implements $PluginReleasesCopyWith<$Res> {
  _$PluginReleasesCopyWithImpl(this._self, this._then);

  final PluginReleases _self;
  final $Res Function(PluginReleases) _then;

/// Create a copy of PluginReleases
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? latest = null,Object? stable = freezed,Object? beta = freezed,}) {
  return _then(PluginReleases(
latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,stable: freezed == stable ? _self.stable : stable // ignore: cast_nullable_to_non_nullable
as String?,beta: freezed == beta ? _self.beta : beta // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginReleases].
extension PluginReleasesPatterns on PluginReleases {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginReleases value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginReleases() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginReleases value)  $default,){
final _that = this;
switch (_that) {
case _PluginReleases():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginReleases value)?  $default,){
final _that = this;
switch (_that) {
case _PluginReleases() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String latest,  String? stable,  String? beta)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginReleases() when $default != null:
return $default(_that.latest,_that.stable,_that.beta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String latest,  String? stable,  String? beta)  $default,) {final _that = this;
switch (_that) {
case _PluginReleases():
return $default(_that.latest,_that.stable,_that.beta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String latest,  String? stable,  String? beta)?  $default,) {final _that = this;
switch (_that) {
case _PluginReleases() when $default != null:
return $default(_that.latest,_that.stable,_that.beta);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginReleases implements PluginReleases {
  const _PluginReleases({required this.latest, this.stable, this.beta});
  factory _PluginReleases.fromJson(Map<String, dynamic> json) => _$PluginReleasesFromJson(json);

@override final  String latest;
@override final  String? stable;
@override final  String? beta;

/// Create a copy of PluginReleases
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginReleasesCopyWith<_PluginReleases> get copyWith => __$PluginReleasesCopyWithImpl<_PluginReleases>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginReleasesToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginReleases&&(identical(other.latest, latest) || other.latest == latest)&&(identical(other.stable, stable) || other.stable == stable)&&(identical(other.beta, beta) || other.beta == beta));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,latest,stable,beta);
}

@override
String toString() {
    return 'PluginReleases(latest: $latest, stable: $stable, beta: $beta)';
}


}

/// @nodoc
abstract mixin class _$PluginReleasesCopyWith<$Res> implements $PluginReleasesCopyWith<$Res> {
  factory _$PluginReleasesCopyWith(_PluginReleases value, $Res Function(_PluginReleases) _then) = __$PluginReleasesCopyWithImpl;
@override @useResult
$Res call({
 String latest, String? stable, String? beta
});




}
/// @nodoc
class __$PluginReleasesCopyWithImpl<$Res>
    implements _$PluginReleasesCopyWith<$Res> {
  __$PluginReleasesCopyWithImpl(this._self, this._then);

  final _PluginReleases _self;
  final $Res Function(_PluginReleases) _then;

/// Create a copy of PluginReleases
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? latest = null,Object? stable = freezed,Object? beta = freezed,}) {
  return _then(_PluginReleases(
latest: null == latest ? _self.latest : latest // ignore: cast_nullable_to_non_nullable
as String,stable: freezed == stable ? _self.stable : stable // ignore: cast_nullable_to_non_nullable
as String?,beta: freezed == beta ? _self.beta : beta // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginInstallation {

 String get targetPath; String? get subdirectory; String? get assetPattern; String? get extractPattern; String? get downloadUrl; bool get preserveDirectoryStructure; String? get sourceDirectoryPath;
/// Create a copy of PluginInstallation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginInstallationCopyWith<PluginInstallation> get copyWith => _$PluginInstallationCopyWithImpl<PluginInstallation>(this as PluginInstallation, _$identity);

  /// Serializes this PluginInstallation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginInstallation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginInstallation&&(identical(other.targetPath, _this.targetPath) || other.targetPath == _this.targetPath)&&(identical(other.subdirectory, _this.subdirectory) || other.subdirectory == _this.subdirectory)&&(identical(other.assetPattern, _this.assetPattern) || other.assetPattern == _this.assetPattern)&&(identical(other.extractPattern, _this.extractPattern) || other.extractPattern == _this.extractPattern)&&(identical(other.downloadUrl, _this.downloadUrl) || other.downloadUrl == _this.downloadUrl)&&(identical(other.preserveDirectoryStructure, _this.preserveDirectoryStructure) || other.preserveDirectoryStructure == _this.preserveDirectoryStructure)&&(identical(other.sourceDirectoryPath, _this.sourceDirectoryPath) || other.sourceDirectoryPath == _this.sourceDirectoryPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginInstallation;
  return Object.hash(runtimeType,_this.targetPath,_this.subdirectory,_this.assetPattern,_this.extractPattern,_this.downloadUrl,_this.preserveDirectoryStructure,_this.sourceDirectoryPath);
}

@override
String toString() {
  final _this = this as PluginInstallation;
  return 'PluginInstallation(targetPath: ${_this.targetPath}, subdirectory: ${_this.subdirectory}, assetPattern: ${_this.assetPattern}, extractPattern: ${_this.extractPattern}, downloadUrl: ${_this.downloadUrl}, preserveDirectoryStructure: ${_this.preserveDirectoryStructure}, sourceDirectoryPath: ${_this.sourceDirectoryPath})';
}


}

/// @nodoc
abstract mixin class $PluginInstallationCopyWith<$Res>  {
  factory $PluginInstallationCopyWith(PluginInstallation value, $Res Function(PluginInstallation) _then) = _$PluginInstallationCopyWithImpl;
@useResult
$Res call({
 String targetPath, String? subdirectory, String? assetPattern, String? extractPattern, String? downloadUrl, bool preserveDirectoryStructure, String? sourceDirectoryPath
});




}
/// @nodoc
class _$PluginInstallationCopyWithImpl<$Res>
    implements $PluginInstallationCopyWith<$Res> {
  _$PluginInstallationCopyWithImpl(this._self, this._then);

  final PluginInstallation _self;
  final $Res Function(PluginInstallation) _then;

/// Create a copy of PluginInstallation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? targetPath = null,Object? subdirectory = freezed,Object? assetPattern = freezed,Object? extractPattern = freezed,Object? downloadUrl = freezed,Object? preserveDirectoryStructure = null,Object? sourceDirectoryPath = freezed,}) {
  return _then(PluginInstallation(
targetPath: null == targetPath ? _self.targetPath : targetPath // ignore: cast_nullable_to_non_nullable
as String,subdirectory: freezed == subdirectory ? _self.subdirectory : subdirectory // ignore: cast_nullable_to_non_nullable
as String?,assetPattern: freezed == assetPattern ? _self.assetPattern : assetPattern // ignore: cast_nullable_to_non_nullable
as String?,extractPattern: freezed == extractPattern ? _self.extractPattern : extractPattern // ignore: cast_nullable_to_non_nullable
as String?,downloadUrl: freezed == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String?,preserveDirectoryStructure: null == preserveDirectoryStructure ? _self.preserveDirectoryStructure : preserveDirectoryStructure // ignore: cast_nullable_to_non_nullable
as bool,sourceDirectoryPath: freezed == sourceDirectoryPath ? _self.sourceDirectoryPath : sourceDirectoryPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginInstallation].
extension PluginInstallationPatterns on PluginInstallation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginInstallation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginInstallation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginInstallation value)  $default,){
final _that = this;
switch (_that) {
case _PluginInstallation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginInstallation value)?  $default,){
final _that = this;
switch (_that) {
case _PluginInstallation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String targetPath,  String? subdirectory,  String? assetPattern,  String? extractPattern,  String? downloadUrl,  bool preserveDirectoryStructure,  String? sourceDirectoryPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginInstallation() when $default != null:
return $default(_that.targetPath,_that.subdirectory,_that.assetPattern,_that.extractPattern,_that.downloadUrl,_that.preserveDirectoryStructure,_that.sourceDirectoryPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String targetPath,  String? subdirectory,  String? assetPattern,  String? extractPattern,  String? downloadUrl,  bool preserveDirectoryStructure,  String? sourceDirectoryPath)  $default,) {final _that = this;
switch (_that) {
case _PluginInstallation():
return $default(_that.targetPath,_that.subdirectory,_that.assetPattern,_that.extractPattern,_that.downloadUrl,_that.preserveDirectoryStructure,_that.sourceDirectoryPath);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String targetPath,  String? subdirectory,  String? assetPattern,  String? extractPattern,  String? downloadUrl,  bool preserveDirectoryStructure,  String? sourceDirectoryPath)?  $default,) {final _that = this;
switch (_that) {
case _PluginInstallation() when $default != null:
return $default(_that.targetPath,_that.subdirectory,_that.assetPattern,_that.extractPattern,_that.downloadUrl,_that.preserveDirectoryStructure,_that.sourceDirectoryPath);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginInstallation implements PluginInstallation {
  const _PluginInstallation({required this.targetPath, this.subdirectory, this.assetPattern, this.extractPattern, this.downloadUrl, this.preserveDirectoryStructure = false, this.sourceDirectoryPath});
  factory _PluginInstallation.fromJson(Map<String, dynamic> json) => _$PluginInstallationFromJson(json);

@override final  String targetPath;
@override final  String? subdirectory;
@override final  String? assetPattern;
@override final  String? extractPattern;
@override final  String? downloadUrl;
@override@JsonKey() final  bool preserveDirectoryStructure;
@override final  String? sourceDirectoryPath;

/// Create a copy of PluginInstallation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginInstallationCopyWith<_PluginInstallation> get copyWith => __$PluginInstallationCopyWithImpl<_PluginInstallation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginInstallationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginInstallation&&(identical(other.targetPath, targetPath) || other.targetPath == targetPath)&&(identical(other.subdirectory, subdirectory) || other.subdirectory == subdirectory)&&(identical(other.assetPattern, assetPattern) || other.assetPattern == assetPattern)&&(identical(other.extractPattern, extractPattern) || other.extractPattern == extractPattern)&&(identical(other.downloadUrl, downloadUrl) || other.downloadUrl == downloadUrl)&&(identical(other.preserveDirectoryStructure, preserveDirectoryStructure) || other.preserveDirectoryStructure == preserveDirectoryStructure)&&(identical(other.sourceDirectoryPath, sourceDirectoryPath) || other.sourceDirectoryPath == sourceDirectoryPath));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,targetPath,subdirectory,assetPattern,extractPattern,downloadUrl,preserveDirectoryStructure,sourceDirectoryPath);
}

@override
String toString() {
    return 'PluginInstallation(targetPath: $targetPath, subdirectory: $subdirectory, assetPattern: $assetPattern, extractPattern: $extractPattern, downloadUrl: $downloadUrl, preserveDirectoryStructure: $preserveDirectoryStructure, sourceDirectoryPath: $sourceDirectoryPath)';
}


}

/// @nodoc
abstract mixin class _$PluginInstallationCopyWith<$Res> implements $PluginInstallationCopyWith<$Res> {
  factory _$PluginInstallationCopyWith(_PluginInstallation value, $Res Function(_PluginInstallation) _then) = __$PluginInstallationCopyWithImpl;
@override @useResult
$Res call({
 String targetPath, String? subdirectory, String? assetPattern, String? extractPattern, String? downloadUrl, bool preserveDirectoryStructure, String? sourceDirectoryPath
});




}
/// @nodoc
class __$PluginInstallationCopyWithImpl<$Res>
    implements _$PluginInstallationCopyWith<$Res> {
  __$PluginInstallationCopyWithImpl(this._self, this._then);

  final _PluginInstallation _self;
  final $Res Function(_PluginInstallation) _then;

/// Create a copy of PluginInstallation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? targetPath = null,Object? subdirectory = freezed,Object? assetPattern = freezed,Object? extractPattern = freezed,Object? downloadUrl = freezed,Object? preserveDirectoryStructure = null,Object? sourceDirectoryPath = freezed,}) {
  return _then(_PluginInstallation(
targetPath: null == targetPath ? _self.targetPath : targetPath // ignore: cast_nullable_to_non_nullable
as String,subdirectory: freezed == subdirectory ? _self.subdirectory : subdirectory // ignore: cast_nullable_to_non_nullable
as String?,assetPattern: freezed == assetPattern ? _self.assetPattern : assetPattern // ignore: cast_nullable_to_non_nullable
as String?,extractPattern: freezed == extractPattern ? _self.extractPattern : extractPattern // ignore: cast_nullable_to_non_nullable
as String?,downloadUrl: freezed == downloadUrl ? _self.downloadUrl : downloadUrl // ignore: cast_nullable_to_non_nullable
as String?,preserveDirectoryStructure: null == preserveDirectoryStructure ? _self.preserveDirectoryStructure : preserveDirectoryStructure // ignore: cast_nullable_to_non_nullable
as bool,sourceDirectoryPath: freezed == sourceDirectoryPath ? _self.sourceDirectoryPath : sourceDirectoryPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginCompatibility {

 String? get minFirmwareVersion; String? get maxFirmwareVersion; List<String> get requiredFeatures;
/// Create a copy of PluginCompatibility
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginCompatibilityCopyWith<PluginCompatibility> get copyWith => _$PluginCompatibilityCopyWithImpl<PluginCompatibility>(this as PluginCompatibility, _$identity);

  /// Serializes this PluginCompatibility to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginCompatibility;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginCompatibility&&(identical(other.minFirmwareVersion, _this.minFirmwareVersion) || other.minFirmwareVersion == _this.minFirmwareVersion)&&(identical(other.maxFirmwareVersion, _this.maxFirmwareVersion) || other.maxFirmwareVersion == _this.maxFirmwareVersion)&&const DeepCollectionEquality().equals(other.requiredFeatures, _this.requiredFeatures));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginCompatibility;
  return Object.hash(runtimeType,_this.minFirmwareVersion,_this.maxFirmwareVersion,const DeepCollectionEquality().hash(_this.requiredFeatures));
}

@override
String toString() {
  final _this = this as PluginCompatibility;
  return 'PluginCompatibility(minFirmwareVersion: ${_this.minFirmwareVersion}, maxFirmwareVersion: ${_this.maxFirmwareVersion}, requiredFeatures: ${_this.requiredFeatures})';
}


}

/// @nodoc
abstract mixin class $PluginCompatibilityCopyWith<$Res>  {
  factory $PluginCompatibilityCopyWith(PluginCompatibility value, $Res Function(PluginCompatibility) _then) = _$PluginCompatibilityCopyWithImpl;
@useResult
$Res call({
 String? minFirmwareVersion, String? maxFirmwareVersion, List<String> requiredFeatures
});




}
/// @nodoc
class _$PluginCompatibilityCopyWithImpl<$Res>
    implements $PluginCompatibilityCopyWith<$Res> {
  _$PluginCompatibilityCopyWithImpl(this._self, this._then);

  final PluginCompatibility _self;
  final $Res Function(PluginCompatibility) _then;

/// Create a copy of PluginCompatibility
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? minFirmwareVersion = freezed,Object? maxFirmwareVersion = freezed,Object? requiredFeatures = null,}) {
  return _then(PluginCompatibility(
minFirmwareVersion: freezed == minFirmwareVersion ? _self.minFirmwareVersion : minFirmwareVersion // ignore: cast_nullable_to_non_nullable
as String?,maxFirmwareVersion: freezed == maxFirmwareVersion ? _self.maxFirmwareVersion : maxFirmwareVersion // ignore: cast_nullable_to_non_nullable
as String?,requiredFeatures: null == requiredFeatures ? _self.requiredFeatures : requiredFeatures // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginCompatibility].
extension PluginCompatibilityPatterns on PluginCompatibility {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginCompatibility value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginCompatibility() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginCompatibility value)  $default,){
final _that = this;
switch (_that) {
case _PluginCompatibility():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginCompatibility value)?  $default,){
final _that = this;
switch (_that) {
case _PluginCompatibility() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? minFirmwareVersion,  String? maxFirmwareVersion,  List<String> requiredFeatures)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginCompatibility() when $default != null:
return $default(_that.minFirmwareVersion,_that.maxFirmwareVersion,_that.requiredFeatures);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? minFirmwareVersion,  String? maxFirmwareVersion,  List<String> requiredFeatures)  $default,) {final _that = this;
switch (_that) {
case _PluginCompatibility():
return $default(_that.minFirmwareVersion,_that.maxFirmwareVersion,_that.requiredFeatures);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? minFirmwareVersion,  String? maxFirmwareVersion,  List<String> requiredFeatures)?  $default,) {final _that = this;
switch (_that) {
case _PluginCompatibility() when $default != null:
return $default(_that.minFirmwareVersion,_that.maxFirmwareVersion,_that.requiredFeatures);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginCompatibility implements PluginCompatibility {
  const _PluginCompatibility({this.minFirmwareVersion, this.maxFirmwareVersion,  List<String> requiredFeatures = const []}): _requiredFeatures = requiredFeatures;
  factory _PluginCompatibility.fromJson(Map<String, dynamic> json) => _$PluginCompatibilityFromJson(json);

@override final  String? minFirmwareVersion;
@override final  String? maxFirmwareVersion;
 final  List<String> _requiredFeatures;
@override@JsonKey() List<String> get requiredFeatures {
  if (_requiredFeatures is EqualUnmodifiableListView) return _requiredFeatures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_requiredFeatures);
}


/// Create a copy of PluginCompatibility
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginCompatibilityCopyWith<_PluginCompatibility> get copyWith => __$PluginCompatibilityCopyWithImpl<_PluginCompatibility>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginCompatibilityToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginCompatibility&&(identical(other.minFirmwareVersion, minFirmwareVersion) || other.minFirmwareVersion == minFirmwareVersion)&&(identical(other.maxFirmwareVersion, maxFirmwareVersion) || other.maxFirmwareVersion == maxFirmwareVersion)&&const DeepCollectionEquality().equals(other.requiredFeatures, _requiredFeatures));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,minFirmwareVersion,maxFirmwareVersion,const DeepCollectionEquality().hash(_requiredFeatures));
}

@override
String toString() {
    return 'PluginCompatibility(minFirmwareVersion: $minFirmwareVersion, maxFirmwareVersion: $maxFirmwareVersion, requiredFeatures: $requiredFeatures)';
}


}

/// @nodoc
abstract mixin class _$PluginCompatibilityCopyWith<$Res> implements $PluginCompatibilityCopyWith<$Res> {
  factory _$PluginCompatibilityCopyWith(_PluginCompatibility value, $Res Function(_PluginCompatibility) _then) = __$PluginCompatibilityCopyWithImpl;
@override @useResult
$Res call({
 String? minFirmwareVersion, String? maxFirmwareVersion, List<String> requiredFeatures
});




}
/// @nodoc
class __$PluginCompatibilityCopyWithImpl<$Res>
    implements _$PluginCompatibilityCopyWith<$Res> {
  __$PluginCompatibilityCopyWithImpl(this._self, this._then);

  final _PluginCompatibility _self;
  final $Res Function(_PluginCompatibility) _then;

/// Create a copy of PluginCompatibility
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? minFirmwareVersion = freezed,Object? maxFirmwareVersion = freezed,Object? requiredFeatures = null,}) {
  return _then(_PluginCompatibility(
minFirmwareVersion: freezed == minFirmwareVersion ? _self.minFirmwareVersion : minFirmwareVersion // ignore: cast_nullable_to_non_nullable
as String?,maxFirmwareVersion: freezed == maxFirmwareVersion ? _self.maxFirmwareVersion : maxFirmwareVersion // ignore: cast_nullable_to_non_nullable
as String?,requiredFeatures: null == requiredFeatures ? _self._requiredFeatures : requiredFeatures // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$PluginScreenshot {

 String get url; String? get caption; String? get thumbnail;
/// Create a copy of PluginScreenshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginScreenshotCopyWith<PluginScreenshot> get copyWith => _$PluginScreenshotCopyWithImpl<PluginScreenshot>(this as PluginScreenshot, _$identity);

  /// Serializes this PluginScreenshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginScreenshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginScreenshot&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.caption, _this.caption) || other.caption == _this.caption)&&(identical(other.thumbnail, _this.thumbnail) || other.thumbnail == _this.thumbnail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginScreenshot;
  return Object.hash(runtimeType,_this.url,_this.caption,_this.thumbnail);
}

@override
String toString() {
  final _this = this as PluginScreenshot;
  return 'PluginScreenshot(url: ${_this.url}, caption: ${_this.caption}, thumbnail: ${_this.thumbnail})';
}


}

/// @nodoc
abstract mixin class $PluginScreenshotCopyWith<$Res>  {
  factory $PluginScreenshotCopyWith(PluginScreenshot value, $Res Function(PluginScreenshot) _then) = _$PluginScreenshotCopyWithImpl;
@useResult
$Res call({
 String url, String? caption, String? thumbnail
});




}
/// @nodoc
class _$PluginScreenshotCopyWithImpl<$Res>
    implements $PluginScreenshotCopyWith<$Res> {
  _$PluginScreenshotCopyWithImpl(this._self, this._then);

  final PluginScreenshot _self;
  final $Res Function(PluginScreenshot) _then;

/// Create a copy of PluginScreenshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? caption = freezed,Object? thumbnail = freezed,}) {
  return _then(PluginScreenshot(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,caption: freezed == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String?,thumbnail: freezed == thumbnail ? _self.thumbnail : thumbnail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginScreenshot].
extension PluginScreenshotPatterns on PluginScreenshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginScreenshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginScreenshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginScreenshot value)  $default,){
final _that = this;
switch (_that) {
case _PluginScreenshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginScreenshot value)?  $default,){
final _that = this;
switch (_that) {
case _PluginScreenshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String? caption,  String? thumbnail)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginScreenshot() when $default != null:
return $default(_that.url,_that.caption,_that.thumbnail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String? caption,  String? thumbnail)  $default,) {final _that = this;
switch (_that) {
case _PluginScreenshot():
return $default(_that.url,_that.caption,_that.thumbnail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String? caption,  String? thumbnail)?  $default,) {final _that = this;
switch (_that) {
case _PluginScreenshot() when $default != null:
return $default(_that.url,_that.caption,_that.thumbnail);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginScreenshot implements PluginScreenshot {
  const _PluginScreenshot({required this.url, this.caption, this.thumbnail});
  factory _PluginScreenshot.fromJson(Map<String, dynamic> json) => _$PluginScreenshotFromJson(json);

@override final  String url;
@override final  String? caption;
@override final  String? thumbnail;

/// Create a copy of PluginScreenshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginScreenshotCopyWith<_PluginScreenshot> get copyWith => __$PluginScreenshotCopyWithImpl<_PluginScreenshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginScreenshotToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginScreenshot&&(identical(other.url, url) || other.url == url)&&(identical(other.caption, caption) || other.caption == caption)&&(identical(other.thumbnail, thumbnail) || other.thumbnail == thumbnail));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,url,caption,thumbnail);
}

@override
String toString() {
    return 'PluginScreenshot(url: $url, caption: $caption, thumbnail: $thumbnail)';
}


}

/// @nodoc
abstract mixin class _$PluginScreenshotCopyWith<$Res> implements $PluginScreenshotCopyWith<$Res> {
  factory _$PluginScreenshotCopyWith(_PluginScreenshot value, $Res Function(_PluginScreenshot) _then) = __$PluginScreenshotCopyWithImpl;
@override @useResult
$Res call({
 String url, String? caption, String? thumbnail
});




}
/// @nodoc
class __$PluginScreenshotCopyWithImpl<$Res>
    implements _$PluginScreenshotCopyWith<$Res> {
  __$PluginScreenshotCopyWithImpl(this._self, this._then);

  final _PluginScreenshot _self;
  final $Res Function(_PluginScreenshot) _then;

/// Create a copy of PluginScreenshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? caption = freezed,Object? thumbnail = freezed,}) {
  return _then(_PluginScreenshot(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,caption: freezed == caption ? _self.caption : caption // ignore: cast_nullable_to_non_nullable
as String?,thumbnail: freezed == thumbnail ? _self.thumbnail : thumbnail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginDocumentation {

 String? get readme; String? get manual; String? get examples;
/// Create a copy of PluginDocumentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginDocumentationCopyWith<PluginDocumentation> get copyWith => _$PluginDocumentationCopyWithImpl<PluginDocumentation>(this as PluginDocumentation, _$identity);

  /// Serializes this PluginDocumentation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginDocumentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginDocumentation&&(identical(other.readme, _this.readme) || other.readme == _this.readme)&&(identical(other.manual, _this.manual) || other.manual == _this.manual)&&(identical(other.examples, _this.examples) || other.examples == _this.examples));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginDocumentation;
  return Object.hash(runtimeType,_this.readme,_this.manual,_this.examples);
}

@override
String toString() {
  final _this = this as PluginDocumentation;
  return 'PluginDocumentation(readme: ${_this.readme}, manual: ${_this.manual}, examples: ${_this.examples})';
}


}

/// @nodoc
abstract mixin class $PluginDocumentationCopyWith<$Res>  {
  factory $PluginDocumentationCopyWith(PluginDocumentation value, $Res Function(PluginDocumentation) _then) = _$PluginDocumentationCopyWithImpl;
@useResult
$Res call({
 String? readme, String? manual, String? examples
});




}
/// @nodoc
class _$PluginDocumentationCopyWithImpl<$Res>
    implements $PluginDocumentationCopyWith<$Res> {
  _$PluginDocumentationCopyWithImpl(this._self, this._then);

  final PluginDocumentation _self;
  final $Res Function(PluginDocumentation) _then;

/// Create a copy of PluginDocumentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? readme = freezed,Object? manual = freezed,Object? examples = freezed,}) {
  return _then(PluginDocumentation(
readme: freezed == readme ? _self.readme : readme // ignore: cast_nullable_to_non_nullable
as String?,manual: freezed == manual ? _self.manual : manual // ignore: cast_nullable_to_non_nullable
as String?,examples: freezed == examples ? _self.examples : examples // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginDocumentation].
extension PluginDocumentationPatterns on PluginDocumentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginDocumentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginDocumentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginDocumentation value)  $default,){
final _that = this;
switch (_that) {
case _PluginDocumentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginDocumentation value)?  $default,){
final _that = this;
switch (_that) {
case _PluginDocumentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? readme,  String? manual,  String? examples)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginDocumentation() when $default != null:
return $default(_that.readme,_that.manual,_that.examples);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? readme,  String? manual,  String? examples)  $default,) {final _that = this;
switch (_that) {
case _PluginDocumentation():
return $default(_that.readme,_that.manual,_that.examples);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? readme,  String? manual,  String? examples)?  $default,) {final _that = this;
switch (_that) {
case _PluginDocumentation() when $default != null:
return $default(_that.readme,_that.manual,_that.examples);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginDocumentation implements PluginDocumentation {
  const _PluginDocumentation({this.readme, this.manual, this.examples});
  factory _PluginDocumentation.fromJson(Map<String, dynamic> json) => _$PluginDocumentationFromJson(json);

@override final  String? readme;
@override final  String? manual;
@override final  String? examples;

/// Create a copy of PluginDocumentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginDocumentationCopyWith<_PluginDocumentation> get copyWith => __$PluginDocumentationCopyWithImpl<_PluginDocumentation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginDocumentationToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginDocumentation&&(identical(other.readme, readme) || other.readme == readme)&&(identical(other.manual, manual) || other.manual == manual)&&(identical(other.examples, examples) || other.examples == examples));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,readme,manual,examples);
}

@override
String toString() {
    return 'PluginDocumentation(readme: $readme, manual: $manual, examples: $examples)';
}


}

/// @nodoc
abstract mixin class _$PluginDocumentationCopyWith<$Res> implements $PluginDocumentationCopyWith<$Res> {
  factory _$PluginDocumentationCopyWith(_PluginDocumentation value, $Res Function(_PluginDocumentation) _then) = __$PluginDocumentationCopyWithImpl;
@override @useResult
$Res call({
 String? readme, String? manual, String? examples
});




}
/// @nodoc
class __$PluginDocumentationCopyWithImpl<$Res>
    implements _$PluginDocumentationCopyWith<$Res> {
  __$PluginDocumentationCopyWithImpl(this._self, this._then);

  final _PluginDocumentation _self;
  final $Res Function(_PluginDocumentation) _then;

/// Create a copy of PluginDocumentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? readme = freezed,Object? manual = freezed,Object? examples = freezed,}) {
  return _then(_PluginDocumentation(
readme: freezed == readme ? _self.readme : readme // ignore: cast_nullable_to_non_nullable
as String?,manual: freezed == manual ? _self.manual : manual // ignore: cast_nullable_to_non_nullable
as String?,examples: freezed == examples ? _self.examples : examples // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$PluginMetrics {

 int get downloads; double? get rating; int get ratingCount;
/// Create a copy of PluginMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginMetricsCopyWith<PluginMetrics> get copyWith => _$PluginMetricsCopyWithImpl<PluginMetrics>(this as PluginMetrics, _$identity);

  /// Serializes this PluginMetrics to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PluginMetrics;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginMetrics&&(identical(other.downloads, _this.downloads) || other.downloads == _this.downloads)&&(identical(other.rating, _this.rating) || other.rating == _this.rating)&&(identical(other.ratingCount, _this.ratingCount) || other.ratingCount == _this.ratingCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PluginMetrics;
  return Object.hash(runtimeType,_this.downloads,_this.rating,_this.ratingCount);
}

@override
String toString() {
  final _this = this as PluginMetrics;
  return 'PluginMetrics(downloads: ${_this.downloads}, rating: ${_this.rating}, ratingCount: ${_this.ratingCount})';
}


}

/// @nodoc
abstract mixin class $PluginMetricsCopyWith<$Res>  {
  factory $PluginMetricsCopyWith(PluginMetrics value, $Res Function(PluginMetrics) _then) = _$PluginMetricsCopyWithImpl;
@useResult
$Res call({
 int downloads, double? rating, int ratingCount
});




}
/// @nodoc
class _$PluginMetricsCopyWithImpl<$Res>
    implements $PluginMetricsCopyWith<$Res> {
  _$PluginMetricsCopyWithImpl(this._self, this._then);

  final PluginMetrics _self;
  final $Res Function(PluginMetrics) _then;

/// Create a copy of PluginMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? downloads = null,Object? rating = freezed,Object? ratingCount = null,}) {
  return _then(PluginMetrics(
downloads: null == downloads ? _self.downloads : downloads // ignore: cast_nullable_to_non_nullable
as int,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double?,ratingCount: null == ratingCount ? _self.ratingCount : ratingCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginMetrics].
extension PluginMetricsPatterns on PluginMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginMetrics value)  $default,){
final _that = this;
switch (_that) {
case _PluginMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _PluginMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int downloads,  double? rating,  int ratingCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginMetrics() when $default != null:
return $default(_that.downloads,_that.rating,_that.ratingCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int downloads,  double? rating,  int ratingCount)  $default,) {final _that = this;
switch (_that) {
case _PluginMetrics():
return $default(_that.downloads,_that.rating,_that.ratingCount);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int downloads,  double? rating,  int ratingCount)?  $default,) {final _that = this;
switch (_that) {
case _PluginMetrics() when $default != null:
return $default(_that.downloads,_that.rating,_that.ratingCount);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PluginMetrics implements PluginMetrics {
  const _PluginMetrics({this.downloads = 0, this.rating, this.ratingCount = 0});
  factory _PluginMetrics.fromJson(Map<String, dynamic> json) => _$PluginMetricsFromJson(json);

@override@JsonKey() final  int downloads;
@override final  double? rating;
@override@JsonKey() final  int ratingCount;

/// Create a copy of PluginMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginMetricsCopyWith<_PluginMetrics> get copyWith => __$PluginMetricsCopyWithImpl<_PluginMetrics>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PluginMetricsToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginMetrics&&(identical(other.downloads, downloads) || other.downloads == downloads)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.ratingCount, ratingCount) || other.ratingCount == ratingCount));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,downloads,rating,ratingCount);
}

@override
String toString() {
    return 'PluginMetrics(downloads: $downloads, rating: $rating, ratingCount: $ratingCount)';
}


}

/// @nodoc
abstract mixin class _$PluginMetricsCopyWith<$Res> implements $PluginMetricsCopyWith<$Res> {
  factory _$PluginMetricsCopyWith(_PluginMetrics value, $Res Function(_PluginMetrics) _then) = __$PluginMetricsCopyWithImpl;
@override @useResult
$Res call({
 int downloads, double? rating, int ratingCount
});




}
/// @nodoc
class __$PluginMetricsCopyWithImpl<$Res>
    implements _$PluginMetricsCopyWith<$Res> {
  __$PluginMetricsCopyWithImpl(this._self, this._then);

  final _PluginMetrics _self;
  final $Res Function(_PluginMetrics) _then;

/// Create a copy of PluginMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? downloads = null,Object? rating = freezed,Object? ratingCount = null,}) {
  return _then(_PluginMetrics(
downloads: null == downloads ? _self.downloads : downloads // ignore: cast_nullable_to_non_nullable
as int,rating: freezed == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as double?,ratingCount: null == ratingCount ? _self.ratingCount : ratingCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$GalleryPlugin {

 String get id; String get name; String get description; String? get longDescription; GalleryPluginType get type; String? get category; List<String> get tags; String get author; PluginRepository get repository; PluginReleases get releases; PluginInstallation get installation; PluginCompatibility? get compatibility; List<PluginScreenshot> get screenshots; PluginDocumentation? get documentation; PluginMetrics? get metrics; bool get featured; bool get verified; bool get isCollection; String? get guid; List<String> get collectionGuids; DateTime? get createdAt; DateTime? get updatedAt;
/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryPluginCopyWith<GalleryPlugin> get copyWith => _$GalleryPluginCopyWithImpl<GalleryPlugin>(this as GalleryPlugin, _$identity);

  /// Serializes this GalleryPlugin to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as GalleryPlugin;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryPlugin&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.longDescription, _this.longDescription) || other.longDescription == _this.longDescription)&&(identical(other.type, _this.type) || other.type == _this.type)&&(identical(other.category, _this.category) || other.category == _this.category)&&const DeepCollectionEquality().equals(other.tags, _this.tags)&&(identical(other.author, _this.author) || other.author == _this.author)&&(identical(other.repository, _this.repository) || other.repository == _this.repository)&&(identical(other.releases, _this.releases) || other.releases == _this.releases)&&(identical(other.installation, _this.installation) || other.installation == _this.installation)&&(identical(other.compatibility, _this.compatibility) || other.compatibility == _this.compatibility)&&const DeepCollectionEquality().equals(other.screenshots, _this.screenshots)&&(identical(other.documentation, _this.documentation) || other.documentation == _this.documentation)&&(identical(other.metrics, _this.metrics) || other.metrics == _this.metrics)&&(identical(other.featured, _this.featured) || other.featured == _this.featured)&&(identical(other.verified, _this.verified) || other.verified == _this.verified)&&(identical(other.isCollection, _this.isCollection) || other.isCollection == _this.isCollection)&&(identical(other.guid, _this.guid) || other.guid == _this.guid)&&const DeepCollectionEquality().equals(other.collectionGuids, _this.collectionGuids)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as GalleryPlugin;
  return Object.hashAll([runtimeType,_this.id,_this.name,_this.description,_this.longDescription,_this.type,_this.category,const DeepCollectionEquality().hash(_this.tags),_this.author,_this.repository,_this.releases,_this.installation,_this.compatibility,const DeepCollectionEquality().hash(_this.screenshots),_this.documentation,_this.metrics,_this.featured,_this.verified,_this.isCollection,_this.guid,const DeepCollectionEquality().hash(_this.collectionGuids),_this.createdAt,_this.updatedAt]);
}

@override
String toString() {
  final _this = this as GalleryPlugin;
  return 'GalleryPlugin(id: ${_this.id}, name: ${_this.name}, description: ${_this.description}, longDescription: ${_this.longDescription}, type: ${_this.type}, category: ${_this.category}, tags: ${_this.tags}, author: ${_this.author}, repository: ${_this.repository}, releases: ${_this.releases}, installation: ${_this.installation}, compatibility: ${_this.compatibility}, screenshots: ${_this.screenshots}, documentation: ${_this.documentation}, metrics: ${_this.metrics}, featured: ${_this.featured}, verified: ${_this.verified}, isCollection: ${_this.isCollection}, guid: ${_this.guid}, collectionGuids: ${_this.collectionGuids}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $GalleryPluginCopyWith<$Res>  {
  factory $GalleryPluginCopyWith(GalleryPlugin value, $Res Function(GalleryPlugin) _then) = _$GalleryPluginCopyWithImpl;
@useResult
$Res call({
 String id, String name, String description, String? longDescription, GalleryPluginType type, String? category, List<String> tags, String author, PluginRepository repository, PluginReleases releases, PluginInstallation installation, PluginCompatibility? compatibility, List<PluginScreenshot> screenshots, PluginDocumentation? documentation, PluginMetrics? metrics, bool featured, bool verified, bool isCollection, String? guid, List<String> collectionGuids, DateTime? createdAt, DateTime? updatedAt
});


$PluginRepositoryCopyWith<$Res> get repository;$PluginReleasesCopyWith<$Res> get releases;$PluginInstallationCopyWith<$Res> get installation;$PluginCompatibilityCopyWith<$Res>? get compatibility;$PluginDocumentationCopyWith<$Res>? get documentation;$PluginMetricsCopyWith<$Res>? get metrics;

}
/// @nodoc
class _$GalleryPluginCopyWithImpl<$Res>
    implements $GalleryPluginCopyWith<$Res> {
  _$GalleryPluginCopyWithImpl(this._self, this._then);

  final GalleryPlugin _self;
  final $Res Function(GalleryPlugin) _then;

/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = null,Object? longDescription = freezed,Object? type = null,Object? category = freezed,Object? tags = null,Object? author = null,Object? repository = null,Object? releases = null,Object? installation = null,Object? compatibility = freezed,Object? screenshots = null,Object? documentation = freezed,Object? metrics = freezed,Object? featured = null,Object? verified = null,Object? isCollection = null,Object? guid = freezed,Object? collectionGuids = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(GalleryPlugin(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,longDescription: freezed == longDescription ? _self.longDescription : longDescription // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as GalleryPluginType,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,author: null == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as PluginRepository,releases: null == releases ? _self.releases : releases // ignore: cast_nullable_to_non_nullable
as PluginReleases,installation: null == installation ? _self.installation : installation // ignore: cast_nullable_to_non_nullable
as PluginInstallation,compatibility: freezed == compatibility ? _self.compatibility : compatibility // ignore: cast_nullable_to_non_nullable
as PluginCompatibility?,screenshots: null == screenshots ? _self.screenshots : screenshots // ignore: cast_nullable_to_non_nullable
as List<PluginScreenshot>,documentation: freezed == documentation ? _self.documentation : documentation // ignore: cast_nullable_to_non_nullable
as PluginDocumentation?,metrics: freezed == metrics ? _self.metrics : metrics // ignore: cast_nullable_to_non_nullable
as PluginMetrics?,featured: null == featured ? _self.featured : featured // ignore: cast_nullable_to_non_nullable
as bool,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,isCollection: null == isCollection ? _self.isCollection : isCollection // ignore: cast_nullable_to_non_nullable
as bool,guid: freezed == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String?,collectionGuids: null == collectionGuids ? _self.collectionGuids : collectionGuids // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginRepositoryCopyWith<$Res> get repository {

  return $PluginRepositoryCopyWith<$Res>(_self.repository, (value) {
    return _then(_self.copyWith(repository: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginReleasesCopyWith<$Res> get releases {

  return $PluginReleasesCopyWith<$Res>(_self.releases, (value) {
    return _then(_self.copyWith(releases: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginInstallationCopyWith<$Res> get installation {

  return $PluginInstallationCopyWith<$Res>(_self.installation, (value) {
    return _then(_self.copyWith(installation: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginCompatibilityCopyWith<$Res>? get compatibility {
    if (_self.compatibility == null) {
    return null;
  }

  return $PluginCompatibilityCopyWith<$Res>(_self.compatibility!, (value) {
    return _then(_self.copyWith(compatibility: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginDocumentationCopyWith<$Res>? get documentation {
    if (_self.documentation == null) {
    return null;
  }

  return $PluginDocumentationCopyWith<$Res>(_self.documentation!, (value) {
    return _then(_self.copyWith(documentation: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginMetricsCopyWith<$Res>? get metrics {
    if (_self.metrics == null) {
    return null;
  }

  return $PluginMetricsCopyWith<$Res>(_self.metrics!, (value) {
    return _then(_self.copyWith(metrics: value));
  });
}
}


/// Adds pattern-matching-related methods to [GalleryPlugin].
extension GalleryPluginPatterns on GalleryPlugin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GalleryPlugin value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GalleryPlugin() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GalleryPlugin value)  $default,){
final _that = this;
switch (_that) {
case _GalleryPlugin():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GalleryPlugin value)?  $default,){
final _that = this;
switch (_that) {
case _GalleryPlugin() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String description,  String? longDescription,  GalleryPluginType type,  String? category,  List<String> tags,  String author,  PluginRepository repository,  PluginReleases releases,  PluginInstallation installation,  PluginCompatibility? compatibility,  List<PluginScreenshot> screenshots,  PluginDocumentation? documentation,  PluginMetrics? metrics,  bool featured,  bool verified,  bool isCollection,  String? guid,  List<String> collectionGuids,  DateTime? createdAt,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GalleryPlugin() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.longDescription,_that.type,_that.category,_that.tags,_that.author,_that.repository,_that.releases,_that.installation,_that.compatibility,_that.screenshots,_that.documentation,_that.metrics,_that.featured,_that.verified,_that.isCollection,_that.guid,_that.collectionGuids,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String description,  String? longDescription,  GalleryPluginType type,  String? category,  List<String> tags,  String author,  PluginRepository repository,  PluginReleases releases,  PluginInstallation installation,  PluginCompatibility? compatibility,  List<PluginScreenshot> screenshots,  PluginDocumentation? documentation,  PluginMetrics? metrics,  bool featured,  bool verified,  bool isCollection,  String? guid,  List<String> collectionGuids,  DateTime? createdAt,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _GalleryPlugin():
return $default(_that.id,_that.name,_that.description,_that.longDescription,_that.type,_that.category,_that.tags,_that.author,_that.repository,_that.releases,_that.installation,_that.compatibility,_that.screenshots,_that.documentation,_that.metrics,_that.featured,_that.verified,_that.isCollection,_that.guid,_that.collectionGuids,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String description,  String? longDescription,  GalleryPluginType type,  String? category,  List<String> tags,  String author,  PluginRepository repository,  PluginReleases releases,  PluginInstallation installation,  PluginCompatibility? compatibility,  List<PluginScreenshot> screenshots,  PluginDocumentation? documentation,  PluginMetrics? metrics,  bool featured,  bool verified,  bool isCollection,  String? guid,  List<String> collectionGuids,  DateTime? createdAt,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _GalleryPlugin() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.longDescription,_that.type,_that.category,_that.tags,_that.author,_that.repository,_that.releases,_that.installation,_that.compatibility,_that.screenshots,_that.documentation,_that.metrics,_that.featured,_that.verified,_that.isCollection,_that.guid,_that.collectionGuids,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _GalleryPlugin implements GalleryPlugin {
  const _GalleryPlugin({required this.id, required this.name, required this.description, this.longDescription, required this.type, this.category,  List<String> tags = const [], required this.author, required this.repository, required this.releases, required this.installation, this.compatibility,  List<PluginScreenshot> screenshots = const [], this.documentation, this.metrics, this.featured = false, this.verified = false, this.isCollection = false, this.guid,  List<String> collectionGuids = const [], this.createdAt, this.updatedAt}): _tags = tags,_screenshots = screenshots,_collectionGuids = collectionGuids;
  factory _GalleryPlugin.fromJson(Map<String, dynamic> json) => _$GalleryPluginFromJson(json);

@override final  String id;
@override final  String name;
@override final  String description;
@override final  String? longDescription;
@override final  GalleryPluginType type;
@override final  String? category;
 final  List<String> _tags;
@override@JsonKey() List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}

@override final  String author;
@override final  PluginRepository repository;
@override final  PluginReleases releases;
@override final  PluginInstallation installation;
@override final  PluginCompatibility? compatibility;
 final  List<PluginScreenshot> _screenshots;
@override@JsonKey() List<PluginScreenshot> get screenshots {
  if (_screenshots is EqualUnmodifiableListView) return _screenshots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_screenshots);
}

@override final  PluginDocumentation? documentation;
@override final  PluginMetrics? metrics;
@override@JsonKey() final  bool featured;
@override@JsonKey() final  bool verified;
@override@JsonKey() final  bool isCollection;
@override final  String? guid;
 final  List<String> _collectionGuids;
@override@JsonKey() List<String> get collectionGuids {
  if (_collectionGuids is EqualUnmodifiableListView) return _collectionGuids;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_collectionGuids);
}

@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;

/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryPluginCopyWith<_GalleryPlugin> get copyWith => __$GalleryPluginCopyWithImpl<_GalleryPlugin>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryPluginToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GalleryPlugin&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.longDescription, longDescription) || other.longDescription == longDescription)&&(identical(other.type, type) || other.type == type)&&(identical(other.category, category) || other.category == category)&&const DeepCollectionEquality().equals(other.tags, _tags)&&(identical(other.author, author) || other.author == author)&&(identical(other.repository, repository) || other.repository == repository)&&(identical(other.releases, releases) || other.releases == releases)&&(identical(other.installation, installation) || other.installation == installation)&&(identical(other.compatibility, compatibility) || other.compatibility == compatibility)&&const DeepCollectionEquality().equals(other.screenshots, _screenshots)&&(identical(other.documentation, documentation) || other.documentation == documentation)&&(identical(other.metrics, metrics) || other.metrics == metrics)&&(identical(other.featured, featured) || other.featured == featured)&&(identical(other.verified, verified) || other.verified == verified)&&(identical(other.isCollection, isCollection) || other.isCollection == isCollection)&&(identical(other.guid, guid) || other.guid == guid)&&const DeepCollectionEquality().equals(other.collectionGuids, _collectionGuids)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,name,description,longDescription,type,category,const DeepCollectionEquality().hash(_tags),author,repository,releases,installation,compatibility,const DeepCollectionEquality().hash(_screenshots),documentation,metrics,featured,verified,isCollection,guid,const DeepCollectionEquality().hash(_collectionGuids),createdAt,updatedAt]);
}

@override
String toString() {
    return 'GalleryPlugin(id: $id, name: $name, description: $description, longDescription: $longDescription, type: $type, category: $category, tags: $tags, author: $author, repository: $repository, releases: $releases, installation: $installation, compatibility: $compatibility, screenshots: $screenshots, documentation: $documentation, metrics: $metrics, featured: $featured, verified: $verified, isCollection: $isCollection, guid: $guid, collectionGuids: $collectionGuids, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$GalleryPluginCopyWith<$Res> implements $GalleryPluginCopyWith<$Res> {
  factory _$GalleryPluginCopyWith(_GalleryPlugin value, $Res Function(_GalleryPlugin) _then) = __$GalleryPluginCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String description, String? longDescription, GalleryPluginType type, String? category, List<String> tags, String author, PluginRepository repository, PluginReleases releases, PluginInstallation installation, PluginCompatibility? compatibility, List<PluginScreenshot> screenshots, PluginDocumentation? documentation, PluginMetrics? metrics, bool featured, bool verified, bool isCollection, String? guid, List<String> collectionGuids, DateTime? createdAt, DateTime? updatedAt
});


@override $PluginRepositoryCopyWith<$Res> get repository;@override $PluginReleasesCopyWith<$Res> get releases;@override $PluginInstallationCopyWith<$Res> get installation;@override $PluginCompatibilityCopyWith<$Res>? get compatibility;@override $PluginDocumentationCopyWith<$Res>? get documentation;@override $PluginMetricsCopyWith<$Res>? get metrics;

}
/// @nodoc
class __$GalleryPluginCopyWithImpl<$Res>
    implements _$GalleryPluginCopyWith<$Res> {
  __$GalleryPluginCopyWithImpl(this._self, this._then);

  final _GalleryPlugin _self;
  final $Res Function(_GalleryPlugin) _then;

/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = null,Object? longDescription = freezed,Object? type = null,Object? category = freezed,Object? tags = null,Object? author = null,Object? repository = null,Object? releases = null,Object? installation = null,Object? compatibility = freezed,Object? screenshots = null,Object? documentation = freezed,Object? metrics = freezed,Object? featured = null,Object? verified = null,Object? isCollection = null,Object? guid = freezed,Object? collectionGuids = null,Object? createdAt = freezed,Object? updatedAt = freezed,}) {
  return _then(_GalleryPlugin(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,longDescription: freezed == longDescription ? _self.longDescription : longDescription // ignore: cast_nullable_to_non_nullable
as String?,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as GalleryPluginType,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,author: null == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String,repository: null == repository ? _self.repository : repository // ignore: cast_nullable_to_non_nullable
as PluginRepository,releases: null == releases ? _self.releases : releases // ignore: cast_nullable_to_non_nullable
as PluginReleases,installation: null == installation ? _self.installation : installation // ignore: cast_nullable_to_non_nullable
as PluginInstallation,compatibility: freezed == compatibility ? _self.compatibility : compatibility // ignore: cast_nullable_to_non_nullable
as PluginCompatibility?,screenshots: null == screenshots ? _self._screenshots : screenshots // ignore: cast_nullable_to_non_nullable
as List<PluginScreenshot>,documentation: freezed == documentation ? _self.documentation : documentation // ignore: cast_nullable_to_non_nullable
as PluginDocumentation?,metrics: freezed == metrics ? _self.metrics : metrics // ignore: cast_nullable_to_non_nullable
as PluginMetrics?,featured: null == featured ? _self.featured : featured // ignore: cast_nullable_to_non_nullable
as bool,verified: null == verified ? _self.verified : verified // ignore: cast_nullable_to_non_nullable
as bool,isCollection: null == isCollection ? _self.isCollection : isCollection // ignore: cast_nullable_to_non_nullable
as bool,guid: freezed == guid ? _self.guid : guid // ignore: cast_nullable_to_non_nullable
as String?,collectionGuids: null == collectionGuids ? _self._collectionGuids : collectionGuids // ignore: cast_nullable_to_non_nullable
as List<String>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginRepositoryCopyWith<$Res> get repository {

  return $PluginRepositoryCopyWith<$Res>(_self.repository, (value) {
    return _then(_self.copyWith(repository: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginReleasesCopyWith<$Res> get releases {

  return $PluginReleasesCopyWith<$Res>(_self.releases, (value) {
    return _then(_self.copyWith(releases: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginInstallationCopyWith<$Res> get installation {

  return $PluginInstallationCopyWith<$Res>(_self.installation, (value) {
    return _then(_self.copyWith(installation: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginCompatibilityCopyWith<$Res>? get compatibility {
    if (_self.compatibility == null) {
    return null;
  }

  return $PluginCompatibilityCopyWith<$Res>(_self.compatibility!, (value) {
    return _then(_self.copyWith(compatibility: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginDocumentationCopyWith<$Res>? get documentation {
    if (_self.documentation == null) {
    return null;
  }

  return $PluginDocumentationCopyWith<$Res>(_self.documentation!, (value) {
    return _then(_self.copyWith(documentation: value));
  });
}/// Create a copy of GalleryPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PluginMetricsCopyWith<$Res>? get metrics {
    if (_self.metrics == null) {
    return null;
  }

  return $PluginMetricsCopyWith<$Res>(_self.metrics!, (value) {
    return _then(_self.copyWith(metrics: value));
  });
}
}


/// @nodoc
mixin _$Gallery {

 String get version; DateTime get lastUpdated; GalleryMetadata get metadata; List<PluginCategory> get categories; Map<String, PluginAuthor> get authors; List<GalleryPlugin> get plugins;
/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryCopyWith<Gallery> get copyWith => _$GalleryCopyWithImpl<Gallery>(this as Gallery, _$identity);

  /// Serializes this Gallery to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Gallery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Gallery&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.lastUpdated, _this.lastUpdated) || other.lastUpdated == _this.lastUpdated)&&(identical(other.metadata, _this.metadata) || other.metadata == _this.metadata)&&const DeepCollectionEquality().equals(other.categories, _this.categories)&&const DeepCollectionEquality().equals(other.authors, _this.authors)&&const DeepCollectionEquality().equals(other.plugins, _this.plugins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Gallery;
  return Object.hash(runtimeType,_this.version,_this.lastUpdated,_this.metadata,const DeepCollectionEquality().hash(_this.categories),const DeepCollectionEquality().hash(_this.authors),const DeepCollectionEquality().hash(_this.plugins));
}

@override
String toString() {
  final _this = this as Gallery;
  return 'Gallery(version: ${_this.version}, lastUpdated: ${_this.lastUpdated}, metadata: ${_this.metadata}, categories: ${_this.categories}, authors: ${_this.authors}, plugins: ${_this.plugins})';
}


}

/// @nodoc
abstract mixin class $GalleryCopyWith<$Res>  {
  factory $GalleryCopyWith(Gallery value, $Res Function(Gallery) _then) = _$GalleryCopyWithImpl;
@useResult
$Res call({
 String version, DateTime lastUpdated, GalleryMetadata metadata, List<PluginCategory> categories, Map<String, PluginAuthor> authors, List<GalleryPlugin> plugins
});


$GalleryMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class _$GalleryCopyWithImpl<$Res>
    implements $GalleryCopyWith<$Res> {
  _$GalleryCopyWithImpl(this._self, this._then);

  final Gallery _self;
  final $Res Function(Gallery) _then;

/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? lastUpdated = null,Object? metadata = null,Object? categories = null,Object? authors = null,Object? plugins = null,}) {
  return _then(Gallery(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as GalleryMetadata,categories: null == categories ? _self.categories : categories // ignore: cast_nullable_to_non_nullable
as List<PluginCategory>,authors: null == authors ? _self.authors : authors // ignore: cast_nullable_to_non_nullable
as Map<String, PluginAuthor>,plugins: null == plugins ? _self.plugins : plugins // ignore: cast_nullable_to_non_nullable
as List<GalleryPlugin>,
  ));
}
/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryMetadataCopyWith<$Res> get metadata {

  return $GalleryMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [Gallery].
extension GalleryPatterns on Gallery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Gallery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Gallery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Gallery value)  $default,){
final _that = this;
switch (_that) {
case _Gallery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Gallery value)?  $default,){
final _that = this;
switch (_that) {
case _Gallery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  DateTime lastUpdated,  GalleryMetadata metadata,  List<PluginCategory> categories,  Map<String, PluginAuthor> authors,  List<GalleryPlugin> plugins)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Gallery() when $default != null:
return $default(_that.version,_that.lastUpdated,_that.metadata,_that.categories,_that.authors,_that.plugins);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  DateTime lastUpdated,  GalleryMetadata metadata,  List<PluginCategory> categories,  Map<String, PluginAuthor> authors,  List<GalleryPlugin> plugins)  $default,) {final _that = this;
switch (_that) {
case _Gallery():
return $default(_that.version,_that.lastUpdated,_that.metadata,_that.categories,_that.authors,_that.plugins);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  DateTime lastUpdated,  GalleryMetadata metadata,  List<PluginCategory> categories,  Map<String, PluginAuthor> authors,  List<GalleryPlugin> plugins)?  $default,) {final _that = this;
switch (_that) {
case _Gallery() when $default != null:
return $default(_that.version,_that.lastUpdated,_that.metadata,_that.categories,_that.authors,_that.plugins);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Gallery implements Gallery {
  const _Gallery({required this.version, required this.lastUpdated, required this.metadata,  List<PluginCategory> categories = const [],  Map<String, PluginAuthor> authors = const {},  List<GalleryPlugin> plugins = const []}): _categories = categories,_authors = authors,_plugins = plugins;
  factory _Gallery.fromJson(Map<String, dynamic> json) => _$GalleryFromJson(json);

@override final  String version;
@override final  DateTime lastUpdated;
@override final  GalleryMetadata metadata;
 final  List<PluginCategory> _categories;
@override@JsonKey() List<PluginCategory> get categories {
  if (_categories is EqualUnmodifiableListView) return _categories;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_categories);
}

 final  Map<String, PluginAuthor> _authors;
@override@JsonKey() Map<String, PluginAuthor> get authors {
  if (_authors is EqualUnmodifiableMapView) return _authors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_authors);
}

 final  List<GalleryPlugin> _plugins;
@override@JsonKey() List<GalleryPlugin> get plugins {
  if (_plugins is EqualUnmodifiableListView) return _plugins;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_plugins);
}


/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GalleryCopyWith<_Gallery> get copyWith => __$GalleryCopyWithImpl<_Gallery>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$GalleryToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Gallery&&(identical(other.version, version) || other.version == version)&&(identical(other.lastUpdated, lastUpdated) || other.lastUpdated == lastUpdated)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.categories, _categories)&&const DeepCollectionEquality().equals(other.authors, _authors)&&const DeepCollectionEquality().equals(other.plugins, _plugins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,version,lastUpdated,metadata,const DeepCollectionEquality().hash(_categories),const DeepCollectionEquality().hash(_authors),const DeepCollectionEquality().hash(_plugins));
}

@override
String toString() {
    return 'Gallery(version: $version, lastUpdated: $lastUpdated, metadata: $metadata, categories: $categories, authors: $authors, plugins: $plugins)';
}


}

/// @nodoc
abstract mixin class _$GalleryCopyWith<$Res> implements $GalleryCopyWith<$Res> {
  factory _$GalleryCopyWith(_Gallery value, $Res Function(_Gallery) _then) = __$GalleryCopyWithImpl;
@override @useResult
$Res call({
 String version, DateTime lastUpdated, GalleryMetadata metadata, List<PluginCategory> categories, Map<String, PluginAuthor> authors, List<GalleryPlugin> plugins
});


@override $GalleryMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class __$GalleryCopyWithImpl<$Res>
    implements _$GalleryCopyWith<$Res> {
  __$GalleryCopyWithImpl(this._self, this._then);

  final _Gallery _self;
  final $Res Function(_Gallery) _then;

/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? lastUpdated = null,Object? metadata = null,Object? categories = null,Object? authors = null,Object? plugins = null,}) {
  return _then(_Gallery(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,lastUpdated: null == lastUpdated ? _self.lastUpdated : lastUpdated // ignore: cast_nullable_to_non_nullable
as DateTime,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as GalleryMetadata,categories: null == categories ? _self._categories : categories // ignore: cast_nullable_to_non_nullable
as List<PluginCategory>,authors: null == authors ? _self._authors : authors // ignore: cast_nullable_to_non_nullable
as Map<String, PluginAuthor>,plugins: null == plugins ? _self._plugins : plugins // ignore: cast_nullable_to_non_nullable
as List<GalleryPlugin>,
  ));
}

/// Create a copy of Gallery
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryMetadataCopyWith<$Res> get metadata {

  return $GalleryMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

/// @nodoc
mixin _$PluginInstallStatus {

 PluginInstallPhase get phase; double get progress; String? get errorMessage;
/// Create a copy of PluginInstallStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PluginInstallStatusCopyWith<PluginInstallStatus> get copyWith => _$PluginInstallStatusCopyWithImpl<PluginInstallStatus>(this as PluginInstallStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PluginInstallStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PluginInstallStatus&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage));
}


@override
int get hashCode {
  final _this = this as PluginInstallStatus;
  return Object.hash(runtimeType,_this.phase,_this.progress,_this.errorMessage);
}

@override
String toString() {
  final _this = this as PluginInstallStatus;
  return 'PluginInstallStatus(phase: ${_this.phase}, progress: ${_this.progress}, errorMessage: ${_this.errorMessage})';
}


}

/// @nodoc
abstract mixin class $PluginInstallStatusCopyWith<$Res>  {
  factory $PluginInstallStatusCopyWith(PluginInstallStatus value, $Res Function(PluginInstallStatus) _then) = _$PluginInstallStatusCopyWithImpl;
@useResult
$Res call({
 PluginInstallPhase phase, double progress, String? errorMessage
});




}
/// @nodoc
class _$PluginInstallStatusCopyWithImpl<$Res>
    implements $PluginInstallStatusCopyWith<$Res> {
  _$PluginInstallStatusCopyWithImpl(this._self, this._then);

  final PluginInstallStatus _self;
  final $Res Function(PluginInstallStatus) _then;

/// Create a copy of PluginInstallStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? progress = null,Object? errorMessage = freezed,}) {
  return _then(PluginInstallStatus(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as PluginInstallPhase,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PluginInstallStatus].
extension PluginInstallStatusPatterns on PluginInstallStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PluginInstallStatus value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PluginInstallStatus() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PluginInstallStatus value)  $default,){
final _that = this;
switch (_that) {
case _PluginInstallStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PluginInstallStatus value)?  $default,){
final _that = this;
switch (_that) {
case _PluginInstallStatus() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PluginInstallPhase phase,  double progress,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PluginInstallStatus() when $default != null:
return $default(_that.phase,_that.progress,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PluginInstallPhase phase,  double progress,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _PluginInstallStatus():
return $default(_that.phase,_that.progress,_that.errorMessage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PluginInstallPhase phase,  double progress,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _PluginInstallStatus() when $default != null:
return $default(_that.phase,_that.progress,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _PluginInstallStatus implements PluginInstallStatus {
  const _PluginInstallStatus({required this.phase, this.progress = 0.0, this.errorMessage});


@override final  PluginInstallPhase phase;
@override@JsonKey() final  double progress;
@override final  String? errorMessage;

/// Create a copy of PluginInstallStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PluginInstallStatusCopyWith<_PluginInstallStatus> get copyWith => __$PluginInstallStatusCopyWithImpl<_PluginInstallStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PluginInstallStatus&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,progress,errorMessage);
}

@override
String toString() {
    return 'PluginInstallStatus(phase: $phase, progress: $progress, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$PluginInstallStatusCopyWith<$Res> implements $PluginInstallStatusCopyWith<$Res> {
  factory _$PluginInstallStatusCopyWith(_PluginInstallStatus value, $Res Function(_PluginInstallStatus) _then) = __$PluginInstallStatusCopyWithImpl;
@override @useResult
$Res call({
 PluginInstallPhase phase, double progress, String? errorMessage
});




}
/// @nodoc
class __$PluginInstallStatusCopyWithImpl<$Res>
    implements _$PluginInstallStatusCopyWith<$Res> {
  __$PluginInstallStatusCopyWithImpl(this._self, this._then);

  final _PluginInstallStatus _self;
  final $Res Function(_PluginInstallStatus) _then;

/// Create a copy of PluginInstallStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? progress = null,Object? errorMessage = freezed,}) {
  return _then(_PluginInstallStatus(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as PluginInstallPhase,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$CollectionExpansion {

 List<CollectionPlugin> get plugins; bool get isLoading; String? get error;
/// Create a copy of CollectionExpansion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CollectionExpansionCopyWith<CollectionExpansion> get copyWith => _$CollectionExpansionCopyWithImpl<CollectionExpansion>(this as CollectionExpansion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CollectionExpansion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionExpansion&&const DeepCollectionEquality().equals(other.plugins, _this.plugins)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as CollectionExpansion;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.plugins),_this.isLoading,_this.error);
}

@override
String toString() {
  final _this = this as CollectionExpansion;
  return 'CollectionExpansion(plugins: ${_this.plugins}, isLoading: ${_this.isLoading}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $CollectionExpansionCopyWith<$Res>  {
  factory $CollectionExpansionCopyWith(CollectionExpansion value, $Res Function(CollectionExpansion) _then) = _$CollectionExpansionCopyWithImpl;
@useResult
$Res call({
 List<CollectionPlugin> plugins, bool isLoading, String? error
});




}
/// @nodoc
class _$CollectionExpansionCopyWithImpl<$Res>
    implements $CollectionExpansionCopyWith<$Res> {
  _$CollectionExpansionCopyWithImpl(this._self, this._then);

  final CollectionExpansion _self;
  final $Res Function(CollectionExpansion) _then;

/// Create a copy of CollectionExpansion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? plugins = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(CollectionExpansion(
plugins: null == plugins ? _self.plugins : plugins // ignore: cast_nullable_to_non_nullable
as List<CollectionPlugin>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CollectionExpansion].
extension CollectionExpansionPatterns on CollectionExpansion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CollectionExpansion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CollectionExpansion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CollectionExpansion value)  $default,){
final _that = this;
switch (_that) {
case _CollectionExpansion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CollectionExpansion value)?  $default,){
final _that = this;
switch (_that) {
case _CollectionExpansion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<CollectionPlugin> plugins,  bool isLoading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CollectionExpansion() when $default != null:
return $default(_that.plugins,_that.isLoading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<CollectionPlugin> plugins,  bool isLoading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _CollectionExpansion():
return $default(_that.plugins,_that.isLoading,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<CollectionPlugin> plugins,  bool isLoading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _CollectionExpansion() when $default != null:
return $default(_that.plugins,_that.isLoading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _CollectionExpansion implements CollectionExpansion {
  const _CollectionExpansion({required  List<CollectionPlugin> plugins, this.isLoading = false, this.error}): _plugins = plugins;


 final  List<CollectionPlugin> _plugins;
@override List<CollectionPlugin> get plugins {
  if (_plugins is EqualUnmodifiableListView) return _plugins;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_plugins);
}

@override@JsonKey() final  bool isLoading;
@override final  String? error;

/// Create a copy of CollectionExpansion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CollectionExpansionCopyWith<_CollectionExpansion> get copyWith => __$CollectionExpansionCopyWithImpl<_CollectionExpansion>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CollectionExpansion&&const DeepCollectionEquality().equals(other.plugins, _plugins)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_plugins),isLoading,error);
}

@override
String toString() {
    return 'CollectionExpansion(plugins: $plugins, isLoading: $isLoading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$CollectionExpansionCopyWith<$Res> implements $CollectionExpansionCopyWith<$Res> {
  factory _$CollectionExpansionCopyWith(_CollectionExpansion value, $Res Function(_CollectionExpansion) _then) = __$CollectionExpansionCopyWithImpl;
@override @useResult
$Res call({
 List<CollectionPlugin> plugins, bool isLoading, String? error
});




}
/// @nodoc
class __$CollectionExpansionCopyWithImpl<$Res>
    implements _$CollectionExpansionCopyWith<$Res> {
  __$CollectionExpansionCopyWithImpl(this._self, this._then);

  final _CollectionExpansion _self;
  final $Res Function(_CollectionExpansion) _then;

/// Create a copy of CollectionExpansion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? plugins = null,Object? isLoading = null,Object? error = freezed,}) {
  return _then(_CollectionExpansion(
plugins: null == plugins ? _self._plugins : plugins // ignore: cast_nullable_to_non_nullable
as List<CollectionPlugin>,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$CollectionPlugin {

 String get name; String get relativePath; String get fileType; String? get description; int? get fileSize; bool get selected;
/// Create a copy of CollectionPlugin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CollectionPluginCopyWith<CollectionPlugin> get copyWith => _$CollectionPluginCopyWithImpl<CollectionPlugin>(this as CollectionPlugin, _$identity);

  /// Serializes this CollectionPlugin to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as CollectionPlugin;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionPlugin&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.relativePath, _this.relativePath) || other.relativePath == _this.relativePath)&&(identical(other.fileType, _this.fileType) || other.fileType == _this.fileType)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.fileSize, _this.fileSize) || other.fileSize == _this.fileSize)&&(identical(other.selected, _this.selected) || other.selected == _this.selected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as CollectionPlugin;
  return Object.hash(runtimeType,_this.name,_this.relativePath,_this.fileType,_this.description,_this.fileSize,_this.selected);
}

@override
String toString() {
  final _this = this as CollectionPlugin;
  return 'CollectionPlugin(name: ${_this.name}, relativePath: ${_this.relativePath}, fileType: ${_this.fileType}, description: ${_this.description}, fileSize: ${_this.fileSize}, selected: ${_this.selected})';
}


}

/// @nodoc
abstract mixin class $CollectionPluginCopyWith<$Res>  {
  factory $CollectionPluginCopyWith(CollectionPlugin value, $Res Function(CollectionPlugin) _then) = _$CollectionPluginCopyWithImpl;
@useResult
$Res call({
 String name, String relativePath, String fileType, String? description, int? fileSize, bool selected
});




}
/// @nodoc
class _$CollectionPluginCopyWithImpl<$Res>
    implements $CollectionPluginCopyWith<$Res> {
  _$CollectionPluginCopyWithImpl(this._self, this._then);

  final CollectionPlugin _self;
  final $Res Function(CollectionPlugin) _then;

/// Create a copy of CollectionPlugin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? relativePath = null,Object? fileType = null,Object? description = freezed,Object? fileSize = freezed,Object? selected = null,}) {
  return _then(CollectionPlugin(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,relativePath: null == relativePath ? _self.relativePath : relativePath // ignore: cast_nullable_to_non_nullable
as String,fileType: null == fileType ? _self.fileType : fileType // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int?,selected: null == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CollectionPlugin].
extension CollectionPluginPatterns on CollectionPlugin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CollectionPlugin value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CollectionPlugin() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CollectionPlugin value)  $default,){
final _that = this;
switch (_that) {
case _CollectionPlugin():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CollectionPlugin value)?  $default,){
final _that = this;
switch (_that) {
case _CollectionPlugin() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String relativePath,  String fileType,  String? description,  int? fileSize,  bool selected)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CollectionPlugin() when $default != null:
return $default(_that.name,_that.relativePath,_that.fileType,_that.description,_that.fileSize,_that.selected);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String relativePath,  String fileType,  String? description,  int? fileSize,  bool selected)  $default,) {final _that = this;
switch (_that) {
case _CollectionPlugin():
return $default(_that.name,_that.relativePath,_that.fileType,_that.description,_that.fileSize,_that.selected);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String relativePath,  String fileType,  String? description,  int? fileSize,  bool selected)?  $default,) {final _that = this;
switch (_that) {
case _CollectionPlugin() when $default != null:
return $default(_that.name,_that.relativePath,_that.fileType,_that.description,_that.fileSize,_that.selected);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CollectionPlugin implements CollectionPlugin {
  const _CollectionPlugin({required this.name, required this.relativePath, required this.fileType, this.description, this.fileSize, this.selected = false});
  factory _CollectionPlugin.fromJson(Map<String, dynamic> json) => _$CollectionPluginFromJson(json);

@override final  String name;
@override final  String relativePath;
@override final  String fileType;
@override final  String? description;
@override final  int? fileSize;
@override@JsonKey() final  bool selected;

/// Create a copy of CollectionPlugin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CollectionPluginCopyWith<_CollectionPlugin> get copyWith => __$CollectionPluginCopyWithImpl<_CollectionPlugin>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CollectionPluginToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CollectionPlugin&&(identical(other.name, name) || other.name == name)&&(identical(other.relativePath, relativePath) || other.relativePath == relativePath)&&(identical(other.fileType, fileType) || other.fileType == fileType)&&(identical(other.description, description) || other.description == description)&&(identical(other.fileSize, fileSize) || other.fileSize == fileSize)&&(identical(other.selected, selected) || other.selected == selected));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,name,relativePath,fileType,description,fileSize,selected);
}

@override
String toString() {
    return 'CollectionPlugin(name: $name, relativePath: $relativePath, fileType: $fileType, description: $description, fileSize: $fileSize, selected: $selected)';
}


}

/// @nodoc
abstract mixin class _$CollectionPluginCopyWith<$Res> implements $CollectionPluginCopyWith<$Res> {
  factory _$CollectionPluginCopyWith(_CollectionPlugin value, $Res Function(_CollectionPlugin) _then) = __$CollectionPluginCopyWithImpl;
@override @useResult
$Res call({
 String name, String relativePath, String fileType, String? description, int? fileSize, bool selected
});




}
/// @nodoc
class __$CollectionPluginCopyWithImpl<$Res>
    implements _$CollectionPluginCopyWith<$Res> {
  __$CollectionPluginCopyWithImpl(this._self, this._then);

  final _CollectionPlugin _self;
  final $Res Function(_CollectionPlugin) _then;

/// Create a copy of CollectionPlugin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? relativePath = null,Object? fileType = null,Object? description = freezed,Object? fileSize = freezed,Object? selected = null,}) {
  return _then(_CollectionPlugin(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,relativePath: null == relativePath ? _self.relativePath : relativePath // ignore: cast_nullable_to_non_nullable
as String,fileType: null == fileType ? _self.fileType : fileType // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,fileSize: freezed == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int?,selected: null == selected ? _self.selected : selected // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$QueuedPlugin {

 GalleryPlugin get plugin; String get selectedVersion; bool get isCollection; QueuedPluginStatus get status; String? get errorMessage; double? get progress; List<CollectionPlugin> get selectedPlugins;
/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedPluginCopyWith<QueuedPlugin> get copyWith => _$QueuedPluginCopyWithImpl<QueuedPlugin>(this as QueuedPlugin, _$identity);

  /// Serializes this QueuedPlugin to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as QueuedPlugin;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedPlugin&&(identical(other.plugin, _this.plugin) || other.plugin == _this.plugin)&&(identical(other.selectedVersion, _this.selectedVersion) || other.selectedVersion == _this.selectedVersion)&&(identical(other.isCollection, _this.isCollection) || other.isCollection == _this.isCollection)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&const DeepCollectionEquality().equals(other.selectedPlugins, _this.selectedPlugins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as QueuedPlugin;
  return Object.hash(runtimeType,_this.plugin,_this.selectedVersion,_this.isCollection,_this.status,_this.errorMessage,_this.progress,const DeepCollectionEquality().hash(_this.selectedPlugins));
}

@override
String toString() {
  final _this = this as QueuedPlugin;
  return 'QueuedPlugin(plugin: ${_this.plugin}, selectedVersion: ${_this.selectedVersion}, isCollection: ${_this.isCollection}, status: ${_this.status}, errorMessage: ${_this.errorMessage}, progress: ${_this.progress}, selectedPlugins: ${_this.selectedPlugins})';
}


}

/// @nodoc
abstract mixin class $QueuedPluginCopyWith<$Res>  {
  factory $QueuedPluginCopyWith(QueuedPlugin value, $Res Function(QueuedPlugin) _then) = _$QueuedPluginCopyWithImpl;
@useResult
$Res call({
 GalleryPlugin plugin, String selectedVersion, bool isCollection, QueuedPluginStatus status, String? errorMessage, double? progress, List<CollectionPlugin> selectedPlugins
});


$GalleryPluginCopyWith<$Res> get plugin;

}
/// @nodoc
class _$QueuedPluginCopyWithImpl<$Res>
    implements $QueuedPluginCopyWith<$Res> {
  _$QueuedPluginCopyWithImpl(this._self, this._then);

  final QueuedPlugin _self;
  final $Res Function(QueuedPlugin) _then;

/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? plugin = null,Object? selectedVersion = null,Object? isCollection = null,Object? status = null,Object? errorMessage = freezed,Object? progress = freezed,Object? selectedPlugins = null,}) {
  return _then(QueuedPlugin(
plugin: null == plugin ? _self.plugin : plugin // ignore: cast_nullable_to_non_nullable
as GalleryPlugin,selectedVersion: null == selectedVersion ? _self.selectedVersion : selectedVersion // ignore: cast_nullable_to_non_nullable
as String,isCollection: null == isCollection ? _self.isCollection : isCollection // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as QueuedPluginStatus,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,selectedPlugins: null == selectedPlugins ? _self.selectedPlugins : selectedPlugins // ignore: cast_nullable_to_non_nullable
as List<CollectionPlugin>,
  ));
}
/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryPluginCopyWith<$Res> get plugin {

  return $GalleryPluginCopyWith<$Res>(_self.plugin, (value) {
    return _then(_self.copyWith(plugin: value));
  });
}
}


/// Adds pattern-matching-related methods to [QueuedPlugin].
extension QueuedPluginPatterns on QueuedPlugin {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QueuedPlugin value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QueuedPlugin() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QueuedPlugin value)  $default,){
final _that = this;
switch (_that) {
case _QueuedPlugin():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QueuedPlugin value)?  $default,){
final _that = this;
switch (_that) {
case _QueuedPlugin() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GalleryPlugin plugin,  String selectedVersion,  bool isCollection,  QueuedPluginStatus status,  String? errorMessage,  double? progress,  List<CollectionPlugin> selectedPlugins)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QueuedPlugin() when $default != null:
return $default(_that.plugin,_that.selectedVersion,_that.isCollection,_that.status,_that.errorMessage,_that.progress,_that.selectedPlugins);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GalleryPlugin plugin,  String selectedVersion,  bool isCollection,  QueuedPluginStatus status,  String? errorMessage,  double? progress,  List<CollectionPlugin> selectedPlugins)  $default,) {final _that = this;
switch (_that) {
case _QueuedPlugin():
return $default(_that.plugin,_that.selectedVersion,_that.isCollection,_that.status,_that.errorMessage,_that.progress,_that.selectedPlugins);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GalleryPlugin plugin,  String selectedVersion,  bool isCollection,  QueuedPluginStatus status,  String? errorMessage,  double? progress,  List<CollectionPlugin> selectedPlugins)?  $default,) {final _that = this;
switch (_that) {
case _QueuedPlugin() when $default != null:
return $default(_that.plugin,_that.selectedVersion,_that.isCollection,_that.status,_that.errorMessage,_that.progress,_that.selectedPlugins);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _QueuedPlugin implements QueuedPlugin {
  const _QueuedPlugin({required this.plugin, required this.selectedVersion, required this.isCollection, this.status = QueuedPluginStatus.queued, this.errorMessage, this.progress,  List<CollectionPlugin> selectedPlugins = const []}): _selectedPlugins = selectedPlugins;
  factory _QueuedPlugin.fromJson(Map<String, dynamic> json) => _$QueuedPluginFromJson(json);

@override final  GalleryPlugin plugin;
@override final  String selectedVersion;
@override final  bool isCollection;
@override@JsonKey() final  QueuedPluginStatus status;
@override final  String? errorMessage;
@override final  double? progress;
 final  List<CollectionPlugin> _selectedPlugins;
@override@JsonKey() List<CollectionPlugin> get selectedPlugins {
  if (_selectedPlugins is EqualUnmodifiableListView) return _selectedPlugins;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedPlugins);
}


/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QueuedPluginCopyWith<_QueuedPlugin> get copyWith => __$QueuedPluginCopyWithImpl<_QueuedPlugin>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$QueuedPluginToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QueuedPlugin&&(identical(other.plugin, plugin) || other.plugin == plugin)&&(identical(other.selectedVersion, selectedVersion) || other.selectedVersion == selectedVersion)&&(identical(other.isCollection, isCollection) || other.isCollection == isCollection)&&(identical(other.status, status) || other.status == status)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.progress, progress) || other.progress == progress)&&const DeepCollectionEquality().equals(other.selectedPlugins, _selectedPlugins));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,plugin,selectedVersion,isCollection,status,errorMessage,progress,const DeepCollectionEquality().hash(_selectedPlugins));
}

@override
String toString() {
    return 'QueuedPlugin(plugin: $plugin, selectedVersion: $selectedVersion, isCollection: $isCollection, status: $status, errorMessage: $errorMessage, progress: $progress, selectedPlugins: $selectedPlugins)';
}


}

/// @nodoc
abstract mixin class _$QueuedPluginCopyWith<$Res> implements $QueuedPluginCopyWith<$Res> {
  factory _$QueuedPluginCopyWith(_QueuedPlugin value, $Res Function(_QueuedPlugin) _then) = __$QueuedPluginCopyWithImpl;
@override @useResult
$Res call({
 GalleryPlugin plugin, String selectedVersion, bool isCollection, QueuedPluginStatus status, String? errorMessage, double? progress, List<CollectionPlugin> selectedPlugins
});


@override $GalleryPluginCopyWith<$Res> get plugin;

}
/// @nodoc
class __$QueuedPluginCopyWithImpl<$Res>
    implements _$QueuedPluginCopyWith<$Res> {
  __$QueuedPluginCopyWithImpl(this._self, this._then);

  final _QueuedPlugin _self;
  final $Res Function(_QueuedPlugin) _then;

/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? plugin = null,Object? selectedVersion = null,Object? isCollection = null,Object? status = null,Object? errorMessage = freezed,Object? progress = freezed,Object? selectedPlugins = null,}) {
  return _then(_QueuedPlugin(
plugin: null == plugin ? _self.plugin : plugin // ignore: cast_nullable_to_non_nullable
as GalleryPlugin,selectedVersion: null == selectedVersion ? _self.selectedVersion : selectedVersion // ignore: cast_nullable_to_non_nullable
as String,isCollection: null == isCollection ? _self.isCollection : isCollection // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as QueuedPluginStatus,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,selectedPlugins: null == selectedPlugins ? _self._selectedPlugins : selectedPlugins // ignore: cast_nullable_to_non_nullable
as List<CollectionPlugin>,
  ));
}

/// Create a copy of QueuedPlugin
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryPluginCopyWith<$Res> get plugin {

  return $GalleryPluginCopyWith<$Res>(_self.plugin, (value) {
    return _then(_self.copyWith(plugin: value));
  });
}
}

// dart format on
