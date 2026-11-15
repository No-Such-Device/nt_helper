// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gallery_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GalleryState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GalleryState()';
}


}

/// @nodoc
class $GalleryStateCopyWith<$Res>  {
$GalleryStateCopyWith(GalleryState _, $Res Function(GalleryState) __);
}


/// Adds pattern-matching-related methods to [GalleryState].
extension GalleryStatePatterns on GalleryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GalleryInitial value)?  initial,TResult Function( GalleryLoading value)?  loading,TResult Function( GalleryLoaded value)?  loaded,TResult Function( GalleryUnavailable value)?  unavailable,TResult Function( GalleryError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GalleryInitial() when initial != null:
return initial(_that);case GalleryLoading() when loading != null:
return loading(_that);case GalleryLoaded() when loaded != null:
return loaded(_that);case GalleryUnavailable() when unavailable != null:
return unavailable(_that);case GalleryError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GalleryInitial value)  initial,required TResult Function( GalleryLoading value)  loading,required TResult Function( GalleryLoaded value)  loaded,required TResult Function( GalleryUnavailable value)  unavailable,required TResult Function( GalleryError value)  error,}){
final _that = this;
switch (_that) {
case GalleryInitial():
return initial(_that);case GalleryLoading():
return loading(_that);case GalleryLoaded():
return loaded(_that);case GalleryUnavailable():
return unavailable(_that);case GalleryError():
return error(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GalleryInitial value)?  initial,TResult? Function( GalleryLoading value)?  loading,TResult? Function( GalleryLoaded value)?  loaded,TResult? Function( GalleryUnavailable value)?  unavailable,TResult? Function( GalleryError value)?  error,}){
final _that = this;
switch (_that) {
case GalleryInitial() when initial != null:
return initial(_that);case GalleryLoading() when loading != null:
return loading(_that);case GalleryLoaded() when loaded != null:
return loaded(_that);case GalleryUnavailable() when unavailable != null:
return unavailable(_that);case GalleryError() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function()?  loading,TResult Function( Gallery gallery,  List<GalleryPlugin> filteredPlugins,  String searchQuery,  String? selectedCategory,  GalleryPluginType? selectedType,  bool showFeaturedOnly,  bool showVerifiedOnly,  Map<String, PluginUpdateInfo> updateInfo,  bool isRefreshing,  Map<String, PluginInstallStatus> installStatuses,  Map<String, CollectionExpansion> expandedCollections)?  loaded,TResult Function( String message,  bool retrying)?  unavailable,TResult Function( String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GalleryInitial() when initial != null:
return initial();case GalleryLoading() when loading != null:
return loading();case GalleryLoaded() when loaded != null:
return loaded(_that.gallery,_that.filteredPlugins,_that.searchQuery,_that.selectedCategory,_that.selectedType,_that.showFeaturedOnly,_that.showVerifiedOnly,_that.updateInfo,_that.isRefreshing,_that.installStatuses,_that.expandedCollections);case GalleryUnavailable() when unavailable != null:
return unavailable(_that.message,_that.retrying);case GalleryError() when error != null:
return error(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function()  loading,required TResult Function( Gallery gallery,  List<GalleryPlugin> filteredPlugins,  String searchQuery,  String? selectedCategory,  GalleryPluginType? selectedType,  bool showFeaturedOnly,  bool showVerifiedOnly,  Map<String, PluginUpdateInfo> updateInfo,  bool isRefreshing,  Map<String, PluginInstallStatus> installStatuses,  Map<String, CollectionExpansion> expandedCollections)  loaded,required TResult Function( String message,  bool retrying)  unavailable,required TResult Function( String message)  error,}) {final _that = this;
switch (_that) {
case GalleryInitial():
return initial();case GalleryLoading():
return loading();case GalleryLoaded():
return loaded(_that.gallery,_that.filteredPlugins,_that.searchQuery,_that.selectedCategory,_that.selectedType,_that.showFeaturedOnly,_that.showVerifiedOnly,_that.updateInfo,_that.isRefreshing,_that.installStatuses,_that.expandedCollections);case GalleryUnavailable():
return unavailable(_that.message,_that.retrying);case GalleryError():
return error(_that.message);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function()?  loading,TResult? Function( Gallery gallery,  List<GalleryPlugin> filteredPlugins,  String searchQuery,  String? selectedCategory,  GalleryPluginType? selectedType,  bool showFeaturedOnly,  bool showVerifiedOnly,  Map<String, PluginUpdateInfo> updateInfo,  bool isRefreshing,  Map<String, PluginInstallStatus> installStatuses,  Map<String, CollectionExpansion> expandedCollections)?  loaded,TResult? Function( String message,  bool retrying)?  unavailable,TResult? Function( String message)?  error,}) {final _that = this;
switch (_that) {
case GalleryInitial() when initial != null:
return initial();case GalleryLoading() when loading != null:
return loading();case GalleryLoaded() when loaded != null:
return loaded(_that.gallery,_that.filteredPlugins,_that.searchQuery,_that.selectedCategory,_that.selectedType,_that.showFeaturedOnly,_that.showVerifiedOnly,_that.updateInfo,_that.isRefreshing,_that.installStatuses,_that.expandedCollections);case GalleryUnavailable() when unavailable != null:
return unavailable(_that.message,_that.retrying);case GalleryError() when error != null:
return error(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class GalleryInitial implements GalleryState {
  const GalleryInitial();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryInitial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GalleryState.initial()';
}


}




/// @nodoc


class GalleryLoading implements GalleryState {
  const GalleryLoading();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'GalleryState.loading()';
}


}




/// @nodoc


class GalleryLoaded implements GalleryState {
  const GalleryLoaded({required this.gallery, required  List<GalleryPlugin> filteredPlugins, required this.searchQuery, this.selectedCategory, this.selectedType, required this.showFeaturedOnly, required this.showVerifiedOnly,  Map<String, PluginUpdateInfo> updateInfo = const {}, this.isRefreshing = false,  Map<String, PluginInstallStatus> installStatuses = const {},  Map<String, CollectionExpansion> expandedCollections = const {}}): _filteredPlugins = filteredPlugins,_updateInfo = updateInfo,_installStatuses = installStatuses,_expandedCollections = expandedCollections;


 final  Gallery gallery;
 final  List<GalleryPlugin> _filteredPlugins;
 List<GalleryPlugin> get filteredPlugins {
  if (_filteredPlugins is EqualUnmodifiableListView) return _filteredPlugins;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_filteredPlugins);
}

 final  String searchQuery;
 final  String? selectedCategory;
 final  GalleryPluginType? selectedType;
 final  bool showFeaturedOnly;
 final  bool showVerifiedOnly;
 final  Map<String, PluginUpdateInfo> _updateInfo;
@JsonKey() Map<String, PluginUpdateInfo> get updateInfo {
  if (_updateInfo is EqualUnmodifiableMapView) return _updateInfo;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_updateInfo);
}

@JsonKey() final  bool isRefreshing;
 final  Map<String, PluginInstallStatus> _installStatuses;
@JsonKey() Map<String, PluginInstallStatus> get installStatuses {
  if (_installStatuses is EqualUnmodifiableMapView) return _installStatuses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_installStatuses);
}

 final  Map<String, CollectionExpansion> _expandedCollections;
@JsonKey() Map<String, CollectionExpansion> get expandedCollections {
  if (_expandedCollections is EqualUnmodifiableMapView) return _expandedCollections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_expandedCollections);
}


/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryLoadedCopyWith<GalleryLoaded> get copyWith => _$GalleryLoadedCopyWithImpl<GalleryLoaded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryLoaded&&(identical(other.gallery, gallery) || other.gallery == gallery)&&const DeepCollectionEquality().equals(other.filteredPlugins, _filteredPlugins)&&(identical(other.searchQuery, searchQuery) || other.searchQuery == searchQuery)&&(identical(other.selectedCategory, selectedCategory) || other.selectedCategory == selectedCategory)&&(identical(other.selectedType, selectedType) || other.selectedType == selectedType)&&(identical(other.showFeaturedOnly, showFeaturedOnly) || other.showFeaturedOnly == showFeaturedOnly)&&(identical(other.showVerifiedOnly, showVerifiedOnly) || other.showVerifiedOnly == showVerifiedOnly)&&const DeepCollectionEquality().equals(other.updateInfo, _updateInfo)&&(identical(other.isRefreshing, isRefreshing) || other.isRefreshing == isRefreshing)&&const DeepCollectionEquality().equals(other.installStatuses, _installStatuses)&&const DeepCollectionEquality().equals(other.expandedCollections, _expandedCollections));
}


@override
int get hashCode {
    return Object.hash(runtimeType,gallery,const DeepCollectionEquality().hash(_filteredPlugins),searchQuery,selectedCategory,selectedType,showFeaturedOnly,showVerifiedOnly,const DeepCollectionEquality().hash(_updateInfo),isRefreshing,const DeepCollectionEquality().hash(_installStatuses),const DeepCollectionEquality().hash(_expandedCollections));
}

@override
String toString() {
    return 'GalleryState.loaded(gallery: $gallery, filteredPlugins: $filteredPlugins, searchQuery: $searchQuery, selectedCategory: $selectedCategory, selectedType: $selectedType, showFeaturedOnly: $showFeaturedOnly, showVerifiedOnly: $showVerifiedOnly, updateInfo: $updateInfo, isRefreshing: $isRefreshing, installStatuses: $installStatuses, expandedCollections: $expandedCollections)';
}


}

/// @nodoc
abstract mixin class $GalleryLoadedCopyWith<$Res> implements $GalleryStateCopyWith<$Res> {
  factory $GalleryLoadedCopyWith(GalleryLoaded value, $Res Function(GalleryLoaded) _then) = _$GalleryLoadedCopyWithImpl;
@useResult
$Res call({
 Gallery gallery, List<GalleryPlugin> filteredPlugins, String searchQuery, String? selectedCategory, GalleryPluginType? selectedType, bool showFeaturedOnly, bool showVerifiedOnly, Map<String, PluginUpdateInfo> updateInfo, bool isRefreshing, Map<String, PluginInstallStatus> installStatuses, Map<String, CollectionExpansion> expandedCollections
});


$GalleryCopyWith<$Res> get gallery;

}
/// @nodoc
class _$GalleryLoadedCopyWithImpl<$Res>
    implements $GalleryLoadedCopyWith<$Res> {
  _$GalleryLoadedCopyWithImpl(this._self, this._then);

  final GalleryLoaded _self;
  final $Res Function(GalleryLoaded) _then;

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? gallery = null,Object? filteredPlugins = null,Object? searchQuery = null,Object? selectedCategory = freezed,Object? selectedType = freezed,Object? showFeaturedOnly = null,Object? showVerifiedOnly = null,Object? updateInfo = null,Object? isRefreshing = null,Object? installStatuses = null,Object? expandedCollections = null,}) {
  return _then(GalleryLoaded(
gallery: null == gallery ? _self.gallery : gallery // ignore: cast_nullable_to_non_nullable
as Gallery,filteredPlugins: null == filteredPlugins ? _self._filteredPlugins : filteredPlugins // ignore: cast_nullable_to_non_nullable
as List<GalleryPlugin>,searchQuery: null == searchQuery ? _self.searchQuery : searchQuery // ignore: cast_nullable_to_non_nullable
as String,selectedCategory: freezed == selectedCategory ? _self.selectedCategory : selectedCategory // ignore: cast_nullable_to_non_nullable
as String?,selectedType: freezed == selectedType ? _self.selectedType : selectedType // ignore: cast_nullable_to_non_nullable
as GalleryPluginType?,showFeaturedOnly: null == showFeaturedOnly ? _self.showFeaturedOnly : showFeaturedOnly // ignore: cast_nullable_to_non_nullable
as bool,showVerifiedOnly: null == showVerifiedOnly ? _self.showVerifiedOnly : showVerifiedOnly // ignore: cast_nullable_to_non_nullable
as bool,updateInfo: null == updateInfo ? _self._updateInfo : updateInfo // ignore: cast_nullable_to_non_nullable
as Map<String, PluginUpdateInfo>,isRefreshing: null == isRefreshing ? _self.isRefreshing : isRefreshing // ignore: cast_nullable_to_non_nullable
as bool,installStatuses: null == installStatuses ? _self._installStatuses : installStatuses // ignore: cast_nullable_to_non_nullable
as Map<String, PluginInstallStatus>,expandedCollections: null == expandedCollections ? _self._expandedCollections : expandedCollections // ignore: cast_nullable_to_non_nullable
as Map<String, CollectionExpansion>,
  ));
}

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GalleryCopyWith<$Res> get gallery {

  return $GalleryCopyWith<$Res>(_self.gallery, (value) {
    return _then(_self.copyWith(gallery: value));
  });
}
}

/// @nodoc


class GalleryUnavailable implements GalleryState {
  const GalleryUnavailable(this.message, {this.retrying = false});


 final  String message;
@JsonKey() final  bool retrying;

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryUnavailableCopyWith<GalleryUnavailable> get copyWith => _$GalleryUnavailableCopyWithImpl<GalleryUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryUnavailable&&(identical(other.message, message) || other.message == message)&&(identical(other.retrying, retrying) || other.retrying == retrying));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,retrying);
}

@override
String toString() {
    return 'GalleryState.unavailable(message: $message, retrying: $retrying)';
}


}

/// @nodoc
abstract mixin class $GalleryUnavailableCopyWith<$Res> implements $GalleryStateCopyWith<$Res> {
  factory $GalleryUnavailableCopyWith(GalleryUnavailable value, $Res Function(GalleryUnavailable) _then) = _$GalleryUnavailableCopyWithImpl;
@useResult
$Res call({
 String message, bool retrying
});




}
/// @nodoc
class _$GalleryUnavailableCopyWithImpl<$Res>
    implements $GalleryUnavailableCopyWith<$Res> {
  _$GalleryUnavailableCopyWithImpl(this._self, this._then);

  final GalleryUnavailable _self;
  final $Res Function(GalleryUnavailable) _then;

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? retrying = null,}) {
  return _then(GalleryUnavailable(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retrying: null == retrying ? _self.retrying : retrying // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class GalleryError implements GalleryState {
  const GalleryError(this.message);


 final  String message;

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GalleryErrorCopyWith<GalleryError> get copyWith => _$GalleryErrorCopyWithImpl<GalleryError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GalleryError&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'GalleryState.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $GalleryErrorCopyWith<$Res> implements $GalleryStateCopyWith<$Res> {
  factory $GalleryErrorCopyWith(GalleryError value, $Res Function(GalleryError) _then) = _$GalleryErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$GalleryErrorCopyWithImpl<$Res>
    implements $GalleryErrorCopyWith<$Res> {
  _$GalleryErrorCopyWithImpl(this._self, this._then);

  final GalleryError _self;
  final $Res Function(GalleryError) _then;

/// Create a copy of GalleryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(GalleryError(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
