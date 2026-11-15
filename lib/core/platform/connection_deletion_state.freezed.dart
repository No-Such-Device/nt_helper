// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'connection_deletion_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConnectionDeletionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConnectionDeletionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectionDeletionState()';
}


}

/// @nodoc
class $ConnectionDeletionStateCopyWith<$Res>  {
$ConnectionDeletionStateCopyWith(ConnectionDeletionState _, $Res Function(ConnectionDeletionState) __);
}


/// Adds pattern-matching-related methods to [ConnectionDeletionState].
extension ConnectionDeletionStatePatterns on ConnectionDeletionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Initial value)?  initial,TResult Function( _Hovering value)?  hovering,TResult Function( _TapSelected value)?  tapSelected,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial(_that);case _Hovering() when hovering != null:
return hovering(_that);case _TapSelected() when tapSelected != null:
return tapSelected(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Initial value)  initial,required TResult Function( _Hovering value)  hovering,required TResult Function( _TapSelected value)  tapSelected,}){
final _that = this;
switch (_that) {
case _Initial():
return initial(_that);case _Hovering():
return hovering(_that);case _TapSelected():
return tapSelected(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Initial value)?  initial,TResult? Function( _Hovering value)?  hovering,TResult? Function( _TapSelected value)?  tapSelected,}){
final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial(_that);case _Hovering() when hovering != null:
return hovering(_that);case _TapSelected() when tapSelected != null:
return tapSelected(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  initial,TResult Function( String connectionId)?  hovering,TResult Function( Set<String> selectedConnectionIds)?  tapSelected,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial();case _Hovering() when hovering != null:
return hovering(_that.connectionId);case _TapSelected() when tapSelected != null:
return tapSelected(_that.selectedConnectionIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  initial,required TResult Function( String connectionId)  hovering,required TResult Function( Set<String> selectedConnectionIds)  tapSelected,}) {final _that = this;
switch (_that) {
case _Initial():
return initial();case _Hovering():
return hovering(_that.connectionId);case _TapSelected():
return tapSelected(_that.selectedConnectionIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  initial,TResult? Function( String connectionId)?  hovering,TResult? Function( Set<String> selectedConnectionIds)?  tapSelected,}) {final _that = this;
switch (_that) {
case _Initial() when initial != null:
return initial();case _Hovering() when hovering != null:
return hovering(_that.connectionId);case _TapSelected() when tapSelected != null:
return tapSelected(_that.selectedConnectionIds);case _:
  return null;

}
}

}

/// @nodoc


class _Initial extends ConnectionDeletionState {
  const _Initial(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Initial);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ConnectionDeletionState.initial()';
}


}




/// @nodoc


class _Hovering extends ConnectionDeletionState {
  const _Hovering(this.connectionId): super._();


 final  String connectionId;

/// Create a copy of ConnectionDeletionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HoveringCopyWith<_Hovering> get copyWith => __$HoveringCopyWithImpl<_Hovering>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Hovering&&(identical(other.connectionId, connectionId) || other.connectionId == connectionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,connectionId);
}

@override
String toString() {
    return 'ConnectionDeletionState.hovering(connectionId: $connectionId)';
}


}

/// @nodoc
abstract mixin class _$HoveringCopyWith<$Res> implements $ConnectionDeletionStateCopyWith<$Res> {
  factory _$HoveringCopyWith(_Hovering value, $Res Function(_Hovering) _then) = __$HoveringCopyWithImpl;
@useResult
$Res call({
 String connectionId
});




}
/// @nodoc
class __$HoveringCopyWithImpl<$Res>
    implements _$HoveringCopyWith<$Res> {
  __$HoveringCopyWithImpl(this._self, this._then);

  final _Hovering _self;
  final $Res Function(_Hovering) _then;

/// Create a copy of ConnectionDeletionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? connectionId = null,}) {
  return _then(_Hovering(
null == connectionId ? _self.connectionId : connectionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class _TapSelected extends ConnectionDeletionState {
  const _TapSelected( Set<String> selectedConnectionIds): _selectedConnectionIds = selectedConnectionIds,super._();


 final  Set<String> _selectedConnectionIds;
 Set<String> get selectedConnectionIds {
  if (_selectedConnectionIds is EqualUnmodifiableSetView) return _selectedConnectionIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_selectedConnectionIds);
}


/// Create a copy of ConnectionDeletionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TapSelectedCopyWith<_TapSelected> get copyWith => __$TapSelectedCopyWithImpl<_TapSelected>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TapSelected&&const DeepCollectionEquality().equals(other.selectedConnectionIds, _selectedConnectionIds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_selectedConnectionIds));
}

@override
String toString() {
    return 'ConnectionDeletionState.tapSelected(selectedConnectionIds: $selectedConnectionIds)';
}


}

/// @nodoc
abstract mixin class _$TapSelectedCopyWith<$Res> implements $ConnectionDeletionStateCopyWith<$Res> {
  factory _$TapSelectedCopyWith(_TapSelected value, $Res Function(_TapSelected) _then) = __$TapSelectedCopyWithImpl;
@useResult
$Res call({
 Set<String> selectedConnectionIds
});




}
/// @nodoc
class __$TapSelectedCopyWithImpl<$Res>
    implements _$TapSelectedCopyWith<$Res> {
  __$TapSelectedCopyWithImpl(this._self, this._then);

  final _TapSelected _self;
  final $Res Function(_TapSelected) _then;

/// Create a copy of ConnectionDeletionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? selectedConnectionIds = null,}) {
  return _then(_TapSelected(
null == selectedConnectionIds ? _self._selectedConnectionIds : selectedConnectionIds // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}


}

// dart format on
