// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'preset_browser_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BrowserFrame {

 String get path; String? get selectedName;
/// Create a copy of BrowserFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrowserFrameCopyWith<BrowserFrame> get copyWith => _$BrowserFrameCopyWithImpl<BrowserFrame>(this as BrowserFrame, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrowserFrame&&(identical(other.path, path) || other.path == path)&&(identical(other.selectedName, selectedName) || other.selectedName == selectedName));
}


@override
int get hashCode => Object.hash(runtimeType,path,selectedName);

@override
String toString() {
  return 'BrowserFrame(path: $path, selectedName: $selectedName)';
}


}

/// @nodoc
abstract mixin class $BrowserFrameCopyWith<$Res>  {
  factory $BrowserFrameCopyWith(BrowserFrame value, $Res Function(BrowserFrame) _then) = _$BrowserFrameCopyWithImpl;
@useResult
$Res call({
 String path, String? selectedName
});




}
/// @nodoc
class _$BrowserFrameCopyWithImpl<$Res>
    implements $BrowserFrameCopyWith<$Res> {
  _$BrowserFrameCopyWithImpl(this._self, this._then);

  final BrowserFrame _self;
  final $Res Function(BrowserFrame) _then;

/// Create a copy of BrowserFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,Object? selectedName = freezed,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,selectedName: freezed == selectedName ? _self.selectedName : selectedName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BrowserFrame].
extension BrowserFramePatterns on BrowserFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BrowserFrame value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BrowserFrame() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BrowserFrame value)  $default,){
final _that = this;
switch (_that) {
case _BrowserFrame():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BrowserFrame value)?  $default,){
final _that = this;
switch (_that) {
case _BrowserFrame() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path,  String? selectedName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BrowserFrame() when $default != null:
return $default(_that.path,_that.selectedName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path,  String? selectedName)  $default,) {final _that = this;
switch (_that) {
case _BrowserFrame():
return $default(_that.path,_that.selectedName);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path,  String? selectedName)?  $default,) {final _that = this;
switch (_that) {
case _BrowserFrame() when $default != null:
return $default(_that.path,_that.selectedName);case _:
  return null;

}
}

}

/// @nodoc


class _BrowserFrame implements BrowserFrame {
  const _BrowserFrame({required this.path, this.selectedName});


@override final  String path;
@override final  String? selectedName;

/// Create a copy of BrowserFrame
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrowserFrameCopyWith<_BrowserFrame> get copyWith => __$BrowserFrameCopyWithImpl<_BrowserFrame>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrowserFrame&&(identical(other.path, path) || other.path == path)&&(identical(other.selectedName, selectedName) || other.selectedName == selectedName));
}


@override
int get hashCode => Object.hash(runtimeType,path,selectedName);

@override
String toString() {
  return 'BrowserFrame(path: $path, selectedName: $selectedName)';
}


}

/// @nodoc
abstract mixin class _$BrowserFrameCopyWith<$Res> implements $BrowserFrameCopyWith<$Res> {
  factory _$BrowserFrameCopyWith(_BrowserFrame value, $Res Function(_BrowserFrame) _then) = __$BrowserFrameCopyWithImpl;
@override @useResult
$Res call({
 String path, String? selectedName
});




}
/// @nodoc
class __$BrowserFrameCopyWithImpl<$Res>
    implements _$BrowserFrameCopyWith<$Res> {
  __$BrowserFrameCopyWithImpl(this._self, this._then);

  final _BrowserFrame _self;
  final $Res Function(_BrowserFrame) _then;

/// Create a copy of BrowserFrame
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,Object? selectedName = freezed,}) {
  return _then(_BrowserFrame(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,selectedName: freezed == selectedName ? _self.selectedName : selectedName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BrowserSnapshot {

 List<BrowserFrame> get stack; int get activeDepth; bool get sortByDate; Map<String, List<DirectoryEntry>> get listings; Set<String> get refreshing; Map<String, String> get errors; Set<String> get busyPaths; String? get warning;
/// Create a copy of BrowserSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BrowserSnapshotCopyWith<BrowserSnapshot> get copyWith => _$BrowserSnapshotCopyWithImpl<BrowserSnapshot>(this as BrowserSnapshot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BrowserSnapshot&&const DeepCollectionEquality().equals(other.stack, stack)&&(identical(other.activeDepth, activeDepth) || other.activeDepth == activeDepth)&&(identical(other.sortByDate, sortByDate) || other.sortByDate == sortByDate)&&const DeepCollectionEquality().equals(other.listings, listings)&&const DeepCollectionEquality().equals(other.refreshing, refreshing)&&const DeepCollectionEquality().equals(other.errors, errors)&&const DeepCollectionEquality().equals(other.busyPaths, busyPaths)&&(identical(other.warning, warning) || other.warning == warning));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(stack),activeDepth,sortByDate,const DeepCollectionEquality().hash(listings),const DeepCollectionEquality().hash(refreshing),const DeepCollectionEquality().hash(errors),const DeepCollectionEquality().hash(busyPaths),warning);

@override
String toString() {
  return 'BrowserSnapshot(stack: $stack, activeDepth: $activeDepth, sortByDate: $sortByDate, listings: $listings, refreshing: $refreshing, errors: $errors, busyPaths: $busyPaths, warning: $warning)';
}


}

/// @nodoc
abstract mixin class $BrowserSnapshotCopyWith<$Res>  {
  factory $BrowserSnapshotCopyWith(BrowserSnapshot value, $Res Function(BrowserSnapshot) _then) = _$BrowserSnapshotCopyWithImpl;
@useResult
$Res call({
 List<BrowserFrame> stack, int activeDepth, bool sortByDate, Map<String, List<DirectoryEntry>> listings, Set<String> refreshing, Map<String, String> errors, Set<String> busyPaths, String? warning
});




}
/// @nodoc
class _$BrowserSnapshotCopyWithImpl<$Res>
    implements $BrowserSnapshotCopyWith<$Res> {
  _$BrowserSnapshotCopyWithImpl(this._self, this._then);

  final BrowserSnapshot _self;
  final $Res Function(BrowserSnapshot) _then;

/// Create a copy of BrowserSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stack = null,Object? activeDepth = null,Object? sortByDate = null,Object? listings = null,Object? refreshing = null,Object? errors = null,Object? busyPaths = null,Object? warning = freezed,}) {
  return _then(_self.copyWith(
stack: null == stack ? _self.stack : stack // ignore: cast_nullable_to_non_nullable
as List<BrowserFrame>,activeDepth: null == activeDepth ? _self.activeDepth : activeDepth // ignore: cast_nullable_to_non_nullable
as int,sortByDate: null == sortByDate ? _self.sortByDate : sortByDate // ignore: cast_nullable_to_non_nullable
as bool,listings: null == listings ? _self.listings : listings // ignore: cast_nullable_to_non_nullable
as Map<String, List<DirectoryEntry>>,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as Set<String>,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,busyPaths: null == busyPaths ? _self.busyPaths : busyPaths // ignore: cast_nullable_to_non_nullable
as Set<String>,warning: freezed == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BrowserSnapshot].
extension BrowserSnapshotPatterns on BrowserSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BrowserSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BrowserSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BrowserSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _BrowserSnapshot():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BrowserSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _BrowserSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<BrowserFrame> stack,  int activeDepth,  bool sortByDate,  Map<String, List<DirectoryEntry>> listings,  Set<String> refreshing,  Map<String, String> errors,  Set<String> busyPaths,  String? warning)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BrowserSnapshot() when $default != null:
return $default(_that.stack,_that.activeDepth,_that.sortByDate,_that.listings,_that.refreshing,_that.errors,_that.busyPaths,_that.warning);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<BrowserFrame> stack,  int activeDepth,  bool sortByDate,  Map<String, List<DirectoryEntry>> listings,  Set<String> refreshing,  Map<String, String> errors,  Set<String> busyPaths,  String? warning)  $default,) {final _that = this;
switch (_that) {
case _BrowserSnapshot():
return $default(_that.stack,_that.activeDepth,_that.sortByDate,_that.listings,_that.refreshing,_that.errors,_that.busyPaths,_that.warning);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<BrowserFrame> stack,  int activeDepth,  bool sortByDate,  Map<String, List<DirectoryEntry>> listings,  Set<String> refreshing,  Map<String, String> errors,  Set<String> busyPaths,  String? warning)?  $default,) {final _that = this;
switch (_that) {
case _BrowserSnapshot() when $default != null:
return $default(_that.stack,_that.activeDepth,_that.sortByDate,_that.listings,_that.refreshing,_that.errors,_that.busyPaths,_that.warning);case _:
  return null;

}
}

}

/// @nodoc


class _BrowserSnapshot extends BrowserSnapshot {
  const _BrowserSnapshot({required final  List<BrowserFrame> stack, this.activeDepth = 0, this.sortByDate = false, final  Map<String, List<DirectoryEntry>> listings = const {}, final  Set<String> refreshing = const {}, final  Map<String, String> errors = const {}, final  Set<String> busyPaths = const {}, this.warning}): _stack = stack,_listings = listings,_refreshing = refreshing,_errors = errors,_busyPaths = busyPaths,super._();


 final  List<BrowserFrame> _stack;
@override List<BrowserFrame> get stack {
  if (_stack is EqualUnmodifiableListView) return _stack;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_stack);
}

@override@JsonKey() final  int activeDepth;
@override@JsonKey() final  bool sortByDate;
 final  Map<String, List<DirectoryEntry>> _listings;
@override@JsonKey() Map<String, List<DirectoryEntry>> get listings {
  if (_listings is EqualUnmodifiableMapView) return _listings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_listings);
}

 final  Set<String> _refreshing;
@override@JsonKey() Set<String> get refreshing {
  if (_refreshing is EqualUnmodifiableSetView) return _refreshing;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_refreshing);
}

 final  Map<String, String> _errors;
@override@JsonKey() Map<String, String> get errors {
  if (_errors is EqualUnmodifiableMapView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_errors);
}

 final  Set<String> _busyPaths;
@override@JsonKey() Set<String> get busyPaths {
  if (_busyPaths is EqualUnmodifiableSetView) return _busyPaths;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_busyPaths);
}

@override final  String? warning;

/// Create a copy of BrowserSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BrowserSnapshotCopyWith<_BrowserSnapshot> get copyWith => __$BrowserSnapshotCopyWithImpl<_BrowserSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BrowserSnapshot&&const DeepCollectionEquality().equals(other._stack, _stack)&&(identical(other.activeDepth, activeDepth) || other.activeDepth == activeDepth)&&(identical(other.sortByDate, sortByDate) || other.sortByDate == sortByDate)&&const DeepCollectionEquality().equals(other._listings, _listings)&&const DeepCollectionEquality().equals(other._refreshing, _refreshing)&&const DeepCollectionEquality().equals(other._errors, _errors)&&const DeepCollectionEquality().equals(other._busyPaths, _busyPaths)&&(identical(other.warning, warning) || other.warning == warning));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_stack),activeDepth,sortByDate,const DeepCollectionEquality().hash(_listings),const DeepCollectionEquality().hash(_refreshing),const DeepCollectionEquality().hash(_errors),const DeepCollectionEquality().hash(_busyPaths),warning);

@override
String toString() {
  return 'BrowserSnapshot(stack: $stack, activeDepth: $activeDepth, sortByDate: $sortByDate, listings: $listings, refreshing: $refreshing, errors: $errors, busyPaths: $busyPaths, warning: $warning)';
}


}

/// @nodoc
abstract mixin class _$BrowserSnapshotCopyWith<$Res> implements $BrowserSnapshotCopyWith<$Res> {
  factory _$BrowserSnapshotCopyWith(_BrowserSnapshot value, $Res Function(_BrowserSnapshot) _then) = __$BrowserSnapshotCopyWithImpl;
@override @useResult
$Res call({
 List<BrowserFrame> stack, int activeDepth, bool sortByDate, Map<String, List<DirectoryEntry>> listings, Set<String> refreshing, Map<String, String> errors, Set<String> busyPaths, String? warning
});




}
/// @nodoc
class __$BrowserSnapshotCopyWithImpl<$Res>
    implements _$BrowserSnapshotCopyWith<$Res> {
  __$BrowserSnapshotCopyWithImpl(this._self, this._then);

  final _BrowserSnapshot _self;
  final $Res Function(_BrowserSnapshot) _then;

/// Create a copy of BrowserSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stack = null,Object? activeDepth = null,Object? sortByDate = null,Object? listings = null,Object? refreshing = null,Object? errors = null,Object? busyPaths = null,Object? warning = freezed,}) {
  return _then(_BrowserSnapshot(
stack: null == stack ? _self._stack : stack // ignore: cast_nullable_to_non_nullable
as List<BrowserFrame>,activeDepth: null == activeDepth ? _self.activeDepth : activeDepth // ignore: cast_nullable_to_non_nullable
as int,sortByDate: null == sortByDate ? _self.sortByDate : sortByDate // ignore: cast_nullable_to_non_nullable
as bool,listings: null == listings ? _self._listings : listings // ignore: cast_nullable_to_non_nullable
as Map<String, List<DirectoryEntry>>,refreshing: null == refreshing ? _self._refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as Set<String>,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as Map<String, String>,busyPaths: null == busyPaths ? _self._busyPaths : busyPaths // ignore: cast_nullable_to_non_nullable
as Set<String>,warning: freezed == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$PresetBrowserState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetBrowserState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PresetBrowserState()';
}


}

/// @nodoc
class $PresetBrowserStateCopyWith<$Res>  {
$PresetBrowserStateCopyWith(PresetBrowserState _, $Res Function(PresetBrowserState) __);
}


/// Adds pattern-matching-related methods to [PresetBrowserState].
extension PresetBrowserStatePatterns on PresetBrowserState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Initial value)?  initial,TResult Function( _Loading value)?  loading,TResult Function( _Loaded value)?  loaded,TResult Function( _Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial(_that);case _Loading() when loading != null:
return loading(_that);case _Loaded() when loaded != null:
return loaded(_that);case _Error() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Initial value)  initial,required TResult Function( _Loading value)  loading,required TResult Function( _Loaded value)  loaded,required TResult Function( _Error value)  error,}){
final _that = this;
switch (_that) {
case _Initial():
return initial(_that);case _Loading():
return loading(_that);case _Loaded():
return loaded(_that);case _Error():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Initial value)?  initial,TResult? Function( _Loading value)?  loading,TResult? Function( _Loaded value)?  loaded,TResult? Function( _Error value)?  error,}){
final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial(_that);case _Loading() when loading != null:
return loading(_that);case _Loaded() when loaded != null:
return loaded(_that);case _Error() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function()?  loading,TResult Function( BrowserSnapshot browser)?  loaded,TResult Function( String message,  String? lastPath)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial();case _Loading() when loading != null:
return loading();case _Loaded() when loaded != null:
return loaded(_that.browser);case _Error() when error != null:
return error(_that.message,_that.lastPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function()  loading,required TResult Function( BrowserSnapshot browser)  loaded,required TResult Function( String message,  String? lastPath)  error,}) {final _that = this;
switch (_that) {
case _Initial():
return initial();case _Loading():
return loading();case _Loaded():
return loaded(_that.browser);case _Error():
return error(_that.message,_that.lastPath);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function()?  loading,TResult? Function( BrowserSnapshot browser)?  loaded,TResult? Function( String message,  String? lastPath)?  error,}) {final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial();case _Loading() when loading != null:
return loading();case _Loaded() when loaded != null:
return loaded(_that.browser);case _Error() when error != null:
return error(_that.message,_that.lastPath);case _:
  return null;

}
}

}

/// @nodoc


class _Initial extends PresetBrowserState {
  const _Initial(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Initial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PresetBrowserState.initial()';
}


}




/// @nodoc


class _Loading extends PresetBrowserState {
  const _Loading(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Loading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PresetBrowserState.loading()';
}


}




/// @nodoc


class _Loaded extends PresetBrowserState {
  const _Loaded({required this.browser}): super._();


 final  BrowserSnapshot browser;

/// Create a copy of PresetBrowserState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoadedCopyWith<_Loaded> get copyWith => __$LoadedCopyWithImpl<_Loaded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Loaded&&(identical(other.browser, browser) || other.browser == browser));
}


@override
int get hashCode => Object.hash(runtimeType,browser);

@override
String toString() {
  return 'PresetBrowserState.loaded(browser: $browser)';
}


}

/// @nodoc
abstract mixin class _$LoadedCopyWith<$Res> implements $PresetBrowserStateCopyWith<$Res> {
  factory _$LoadedCopyWith(_Loaded value, $Res Function(_Loaded) _then) = __$LoadedCopyWithImpl;
@useResult
$Res call({
 BrowserSnapshot browser
});


$BrowserSnapshotCopyWith<$Res> get browser;

}
/// @nodoc
class __$LoadedCopyWithImpl<$Res>
    implements _$LoadedCopyWith<$Res> {
  __$LoadedCopyWithImpl(this._self, this._then);

  final _Loaded _self;
  final $Res Function(_Loaded) _then;

/// Create a copy of PresetBrowserState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? browser = null,}) {
  return _then(_Loaded(
browser: null == browser ? _self.browser : browser // ignore: cast_nullable_to_non_nullable
as BrowserSnapshot,
  ));
}

/// Create a copy of PresetBrowserState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BrowserSnapshotCopyWith<$Res> get browser {

  return $BrowserSnapshotCopyWith<$Res>(_self.browser, (value) {
    return _then(_self.copyWith(browser: value));
  });
}
}

/// @nodoc


class _Error extends PresetBrowserState {
  const _Error({required this.message, this.lastPath}): super._();


 final  String message;
 final  String? lastPath;

/// Create a copy of PresetBrowserState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ErrorCopyWith<_Error> get copyWith => __$ErrorCopyWithImpl<_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Error&&(identical(other.message, message) || other.message == message)&&(identical(other.lastPath, lastPath) || other.lastPath == lastPath));
}


@override
int get hashCode => Object.hash(runtimeType,message,lastPath);

@override
String toString() {
  return 'PresetBrowserState.error(message: $message, lastPath: $lastPath)';
}


}

/// @nodoc
abstract mixin class _$ErrorCopyWith<$Res> implements $PresetBrowserStateCopyWith<$Res> {
  factory _$ErrorCopyWith(_Error value, $Res Function(_Error) _then) = __$ErrorCopyWithImpl;
@useResult
$Res call({
 String message, String? lastPath
});




}
/// @nodoc
class __$ErrorCopyWithImpl<$Res>
    implements _$ErrorCopyWith<$Res> {
  __$ErrorCopyWithImpl(this._self, this._then);

  final _Error _self;
  final $Res Function(_Error) _then;

/// Create a copy of PresetBrowserState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? lastPath = freezed,}) {
  return _then(_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,lastPath: freezed == lastPath ? _self.lastPath : lastPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
