// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'firmware_update_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FirmwareUpdateState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FirmwareUpdateState()';
}


}

/// @nodoc
class $FirmwareUpdateStateCopyWith<$Res>  {
$FirmwareUpdateStateCopyWith(FirmwareUpdateState _, $Res Function(FirmwareUpdateState) __);
}


/// Adds pattern-matching-related methods to [FirmwareUpdateState].
extension FirmwareUpdateStatePatterns on FirmwareUpdateState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FirmwareUpdateStateInitial value)?  initial,TResult Function( FirmwareUpdateStateDownloading value)?  downloading,TResult Function( FirmwareUpdateStateWaitingForBootloader value)?  waitingForBootloader,TResult Function( FirmwareUpdateStateEnteringBootloader value)?  enteringBootloader,TResult Function( FirmwareUpdateStateFlashing value)?  flashing,TResult Function( FirmwareUpdateStateVerifyingMidi value)?  verifyingMidi,TResult Function( FirmwareUpdateStateMidiRecoveryRequired value)?  midiRecoveryRequired,TResult Function( FirmwareUpdateStateSuccess value)?  success,TResult Function( FirmwareUpdateStateError value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial() when initial != null:
return initial(_that);case FirmwareUpdateStateDownloading() when downloading != null:
return downloading(_that);case FirmwareUpdateStateWaitingForBootloader() when waitingForBootloader != null:
return waitingForBootloader(_that);case FirmwareUpdateStateEnteringBootloader() when enteringBootloader != null:
return enteringBootloader(_that);case FirmwareUpdateStateFlashing() when flashing != null:
return flashing(_that);case FirmwareUpdateStateVerifyingMidi() when verifyingMidi != null:
return verifyingMidi(_that);case FirmwareUpdateStateMidiRecoveryRequired() when midiRecoveryRequired != null:
return midiRecoveryRequired(_that);case FirmwareUpdateStateSuccess() when success != null:
return success(_that);case FirmwareUpdateStateError() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FirmwareUpdateStateInitial value)  initial,required TResult Function( FirmwareUpdateStateDownloading value)  downloading,required TResult Function( FirmwareUpdateStateWaitingForBootloader value)  waitingForBootloader,required TResult Function( FirmwareUpdateStateEnteringBootloader value)  enteringBootloader,required TResult Function( FirmwareUpdateStateFlashing value)  flashing,required TResult Function( FirmwareUpdateStateVerifyingMidi value)  verifyingMidi,required TResult Function( FirmwareUpdateStateMidiRecoveryRequired value)  midiRecoveryRequired,required TResult Function( FirmwareUpdateStateSuccess value)  success,required TResult Function( FirmwareUpdateStateError value)  error,}){
final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial():
return initial(_that);case FirmwareUpdateStateDownloading():
return downloading(_that);case FirmwareUpdateStateWaitingForBootloader():
return waitingForBootloader(_that);case FirmwareUpdateStateEnteringBootloader():
return enteringBootloader(_that);case FirmwareUpdateStateFlashing():
return flashing(_that);case FirmwareUpdateStateVerifyingMidi():
return verifyingMidi(_that);case FirmwareUpdateStateMidiRecoveryRequired():
return midiRecoveryRequired(_that);case FirmwareUpdateStateSuccess():
return success(_that);case FirmwareUpdateStateError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FirmwareUpdateStateInitial value)?  initial,TResult? Function( FirmwareUpdateStateDownloading value)?  downloading,TResult? Function( FirmwareUpdateStateWaitingForBootloader value)?  waitingForBootloader,TResult? Function( FirmwareUpdateStateEnteringBootloader value)?  enteringBootloader,TResult? Function( FirmwareUpdateStateFlashing value)?  flashing,TResult? Function( FirmwareUpdateStateVerifyingMidi value)?  verifyingMidi,TResult? Function( FirmwareUpdateStateMidiRecoveryRequired value)?  midiRecoveryRequired,TResult? Function( FirmwareUpdateStateSuccess value)?  success,TResult? Function( FirmwareUpdateStateError value)?  error,}){
final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial() when initial != null:
return initial(_that);case FirmwareUpdateStateDownloading() when downloading != null:
return downloading(_that);case FirmwareUpdateStateWaitingForBootloader() when waitingForBootloader != null:
return waitingForBootloader(_that);case FirmwareUpdateStateEnteringBootloader() when enteringBootloader != null:
return enteringBootloader(_that);case FirmwareUpdateStateFlashing() when flashing != null:
return flashing(_that);case FirmwareUpdateStateVerifyingMidi() when verifyingMidi != null:
return verifyingMidi(_that);case FirmwareUpdateStateMidiRecoveryRequired() when midiRecoveryRequired != null:
return midiRecoveryRequired(_that);case FirmwareUpdateStateSuccess() when success != null:
return success(_that);case FirmwareUpdateStateError() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String currentVersion,  List<FirmwareRelease>? availableVersions,  bool isLoadingVersions,  String? fetchError)?  initial,TResult Function( FirmwareRelease version,  double progress)?  downloading,TResult Function( String firmwarePath,  String targetVersion,  bool canAutoEnter)?  waitingForBootloader,TResult Function( String firmwarePath,  String targetVersion,  double progress)?  enteringBootloader,TResult Function( String targetVersion,  FlashProgress progress)?  flashing,TResult Function( String newVersion,  int completedAttempts,  int totalAttempts,  bool requiresVersion)?  verifyingMidi,TResult Function( String newVersion,  bool isWindows,  String? verificationMessage)?  midiRecoveryRequired,TResult Function( String newVersion)?  success,TResult Function( String message,  FirmwareErrorType errorType,  FlashStage? failedStage,  String? firmwarePath,  String? targetVersion)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial() when initial != null:
return initial(_that.currentVersion,_that.availableVersions,_that.isLoadingVersions,_that.fetchError);case FirmwareUpdateStateDownloading() when downloading != null:
return downloading(_that.version,_that.progress);case FirmwareUpdateStateWaitingForBootloader() when waitingForBootloader != null:
return waitingForBootloader(_that.firmwarePath,_that.targetVersion,_that.canAutoEnter);case FirmwareUpdateStateEnteringBootloader() when enteringBootloader != null:
return enteringBootloader(_that.firmwarePath,_that.targetVersion,_that.progress);case FirmwareUpdateStateFlashing() when flashing != null:
return flashing(_that.targetVersion,_that.progress);case FirmwareUpdateStateVerifyingMidi() when verifyingMidi != null:
return verifyingMidi(_that.newVersion,_that.completedAttempts,_that.totalAttempts,_that.requiresVersion);case FirmwareUpdateStateMidiRecoveryRequired() when midiRecoveryRequired != null:
return midiRecoveryRequired(_that.newVersion,_that.isWindows,_that.verificationMessage);case FirmwareUpdateStateSuccess() when success != null:
return success(_that.newVersion);case FirmwareUpdateStateError() when error != null:
return error(_that.message,_that.errorType,_that.failedStage,_that.firmwarePath,_that.targetVersion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String currentVersion,  List<FirmwareRelease>? availableVersions,  bool isLoadingVersions,  String? fetchError)  initial,required TResult Function( FirmwareRelease version,  double progress)  downloading,required TResult Function( String firmwarePath,  String targetVersion,  bool canAutoEnter)  waitingForBootloader,required TResult Function( String firmwarePath,  String targetVersion,  double progress)  enteringBootloader,required TResult Function( String targetVersion,  FlashProgress progress)  flashing,required TResult Function( String newVersion,  int completedAttempts,  int totalAttempts,  bool requiresVersion)  verifyingMidi,required TResult Function( String newVersion,  bool isWindows,  String? verificationMessage)  midiRecoveryRequired,required TResult Function( String newVersion)  success,required TResult Function( String message,  FirmwareErrorType errorType,  FlashStage? failedStage,  String? firmwarePath,  String? targetVersion)  error,}) {final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial():
return initial(_that.currentVersion,_that.availableVersions,_that.isLoadingVersions,_that.fetchError);case FirmwareUpdateStateDownloading():
return downloading(_that.version,_that.progress);case FirmwareUpdateStateWaitingForBootloader():
return waitingForBootloader(_that.firmwarePath,_that.targetVersion,_that.canAutoEnter);case FirmwareUpdateStateEnteringBootloader():
return enteringBootloader(_that.firmwarePath,_that.targetVersion,_that.progress);case FirmwareUpdateStateFlashing():
return flashing(_that.targetVersion,_that.progress);case FirmwareUpdateStateVerifyingMidi():
return verifyingMidi(_that.newVersion,_that.completedAttempts,_that.totalAttempts,_that.requiresVersion);case FirmwareUpdateStateMidiRecoveryRequired():
return midiRecoveryRequired(_that.newVersion,_that.isWindows,_that.verificationMessage);case FirmwareUpdateStateSuccess():
return success(_that.newVersion);case FirmwareUpdateStateError():
return error(_that.message,_that.errorType,_that.failedStage,_that.firmwarePath,_that.targetVersion);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String currentVersion,  List<FirmwareRelease>? availableVersions,  bool isLoadingVersions,  String? fetchError)?  initial,TResult? Function( FirmwareRelease version,  double progress)?  downloading,TResult? Function( String firmwarePath,  String targetVersion,  bool canAutoEnter)?  waitingForBootloader,TResult? Function( String firmwarePath,  String targetVersion,  double progress)?  enteringBootloader,TResult? Function( String targetVersion,  FlashProgress progress)?  flashing,TResult? Function( String newVersion,  int completedAttempts,  int totalAttempts,  bool requiresVersion)?  verifyingMidi,TResult? Function( String newVersion,  bool isWindows,  String? verificationMessage)?  midiRecoveryRequired,TResult? Function( String newVersion)?  success,TResult? Function( String message,  FirmwareErrorType errorType,  FlashStage? failedStage,  String? firmwarePath,  String? targetVersion)?  error,}) {final _that = this;
switch (_that) {
case FirmwareUpdateStateInitial() when initial != null:
return initial(_that.currentVersion,_that.availableVersions,_that.isLoadingVersions,_that.fetchError);case FirmwareUpdateStateDownloading() when downloading != null:
return downloading(_that.version,_that.progress);case FirmwareUpdateStateWaitingForBootloader() when waitingForBootloader != null:
return waitingForBootloader(_that.firmwarePath,_that.targetVersion,_that.canAutoEnter);case FirmwareUpdateStateEnteringBootloader() when enteringBootloader != null:
return enteringBootloader(_that.firmwarePath,_that.targetVersion,_that.progress);case FirmwareUpdateStateFlashing() when flashing != null:
return flashing(_that.targetVersion,_that.progress);case FirmwareUpdateStateVerifyingMidi() when verifyingMidi != null:
return verifyingMidi(_that.newVersion,_that.completedAttempts,_that.totalAttempts,_that.requiresVersion);case FirmwareUpdateStateMidiRecoveryRequired() when midiRecoveryRequired != null:
return midiRecoveryRequired(_that.newVersion,_that.isWindows,_that.verificationMessage);case FirmwareUpdateStateSuccess() when success != null:
return success(_that.newVersion);case FirmwareUpdateStateError() when error != null:
return error(_that.message,_that.errorType,_that.failedStage,_that.firmwarePath,_that.targetVersion);case _:
  return null;

}
}

}

/// @nodoc


class FirmwareUpdateStateInitial implements FirmwareUpdateState {
  const FirmwareUpdateStateInitial({required this.currentVersion, final  List<FirmwareRelease>? availableVersions = null, this.isLoadingVersions = false, this.fetchError = null}): _availableVersions = availableVersions;


/// Currently installed firmware version string
 final  String currentVersion;
/// Available firmware releases (null if not yet fetched)
 final  List<FirmwareRelease>? _availableVersions;
/// Available firmware releases (null if not yet fetched)
@JsonKey() List<FirmwareRelease>? get availableVersions {
  final value = _availableVersions;
  if (value == null) return null;
  if (_availableVersions is EqualUnmodifiableListView) return _availableVersions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Whether we're loading available versions
@JsonKey() final  bool isLoadingVersions;
/// Error message if fetching versions failed
@JsonKey() final  String? fetchError;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateInitialCopyWith<FirmwareUpdateStateInitial> get copyWith => _$FirmwareUpdateStateInitialCopyWithImpl<FirmwareUpdateStateInitial>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateInitial&&(identical(other.currentVersion, currentVersion) || other.currentVersion == currentVersion)&&const DeepCollectionEquality().equals(other._availableVersions, _availableVersions)&&(identical(other.isLoadingVersions, isLoadingVersions) || other.isLoadingVersions == isLoadingVersions)&&(identical(other.fetchError, fetchError) || other.fetchError == fetchError));
}


@override
int get hashCode => Object.hash(runtimeType,currentVersion,const DeepCollectionEquality().hash(_availableVersions),isLoadingVersions,fetchError);

@override
String toString() {
  return 'FirmwareUpdateState.initial(currentVersion: $currentVersion, availableVersions: $availableVersions, isLoadingVersions: $isLoadingVersions, fetchError: $fetchError)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateInitialCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateInitialCopyWith(FirmwareUpdateStateInitial value, $Res Function(FirmwareUpdateStateInitial) _then) = _$FirmwareUpdateStateInitialCopyWithImpl;
@useResult
$Res call({
 String currentVersion, List<FirmwareRelease>? availableVersions, bool isLoadingVersions, String? fetchError
});




}
/// @nodoc
class _$FirmwareUpdateStateInitialCopyWithImpl<$Res>
    implements $FirmwareUpdateStateInitialCopyWith<$Res> {
  _$FirmwareUpdateStateInitialCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateInitial _self;
  final $Res Function(FirmwareUpdateStateInitial) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? currentVersion = null,Object? availableVersions = freezed,Object? isLoadingVersions = null,Object? fetchError = freezed,}) {
  return _then(FirmwareUpdateStateInitial(
currentVersion: null == currentVersion ? _self.currentVersion : currentVersion // ignore: cast_nullable_to_non_nullable
as String,availableVersions: freezed == availableVersions ? _self._availableVersions : availableVersions // ignore: cast_nullable_to_non_nullable
as List<FirmwareRelease>?,isLoadingVersions: null == isLoadingVersions ? _self.isLoadingVersions : isLoadingVersions // ignore: cast_nullable_to_non_nullable
as bool,fetchError: freezed == fetchError ? _self.fetchError : fetchError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateDownloading implements FirmwareUpdateState {
  const FirmwareUpdateStateDownloading({required this.version, required this.progress});


 final  FirmwareRelease version;
 final  double progress;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateDownloadingCopyWith<FirmwareUpdateStateDownloading> get copyWith => _$FirmwareUpdateStateDownloadingCopyWithImpl<FirmwareUpdateStateDownloading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateDownloading&&(identical(other.version, version) || other.version == version)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,version,progress);

@override
String toString() {
  return 'FirmwareUpdateState.downloading(version: $version, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateDownloadingCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateDownloadingCopyWith(FirmwareUpdateStateDownloading value, $Res Function(FirmwareUpdateStateDownloading) _then) = _$FirmwareUpdateStateDownloadingCopyWithImpl;
@useResult
$Res call({
 FirmwareRelease version, double progress
});


$FirmwareReleaseCopyWith<$Res> get version;

}
/// @nodoc
class _$FirmwareUpdateStateDownloadingCopyWithImpl<$Res>
    implements $FirmwareUpdateStateDownloadingCopyWith<$Res> {
  _$FirmwareUpdateStateDownloadingCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateDownloading _self;
  final $Res Function(FirmwareUpdateStateDownloading) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? version = null,Object? progress = null,}) {
  return _then(FirmwareUpdateStateDownloading(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as FirmwareRelease,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FirmwareReleaseCopyWith<$Res> get version {
  
  return $FirmwareReleaseCopyWith<$Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}
}

/// @nodoc


class FirmwareUpdateStateWaitingForBootloader implements FirmwareUpdateState {
  const FirmwareUpdateStateWaitingForBootloader({required this.firmwarePath, required this.targetVersion, this.canAutoEnter = false});
  

 final  String firmwarePath;
 final  String targetVersion;
/// Whether the device supports automatic bootloader entry via SysEx
@JsonKey() final  bool canAutoEnter;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateWaitingForBootloaderCopyWith<FirmwareUpdateStateWaitingForBootloader> get copyWith => _$FirmwareUpdateStateWaitingForBootloaderCopyWithImpl<FirmwareUpdateStateWaitingForBootloader>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateWaitingForBootloader&&(identical(other.firmwarePath, firmwarePath) || other.firmwarePath == firmwarePath)&&(identical(other.targetVersion, targetVersion) || other.targetVersion == targetVersion)&&(identical(other.canAutoEnter, canAutoEnter) || other.canAutoEnter == canAutoEnter));
}


@override
int get hashCode => Object.hash(runtimeType,firmwarePath,targetVersion,canAutoEnter);

@override
String toString() {
  return 'FirmwareUpdateState.waitingForBootloader(firmwarePath: $firmwarePath, targetVersion: $targetVersion, canAutoEnter: $canAutoEnter)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateWaitingForBootloaderCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateWaitingForBootloaderCopyWith(FirmwareUpdateStateWaitingForBootloader value, $Res Function(FirmwareUpdateStateWaitingForBootloader) _then) = _$FirmwareUpdateStateWaitingForBootloaderCopyWithImpl;
@useResult
$Res call({
 String firmwarePath, String targetVersion, bool canAutoEnter
});




}
/// @nodoc
class _$FirmwareUpdateStateWaitingForBootloaderCopyWithImpl<$Res>
    implements $FirmwareUpdateStateWaitingForBootloaderCopyWith<$Res> {
  _$FirmwareUpdateStateWaitingForBootloaderCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateWaitingForBootloader _self;
  final $Res Function(FirmwareUpdateStateWaitingForBootloader) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? firmwarePath = null,Object? targetVersion = null,Object? canAutoEnter = null,}) {
  return _then(FirmwareUpdateStateWaitingForBootloader(
firmwarePath: null == firmwarePath ? _self.firmwarePath : firmwarePath // ignore: cast_nullable_to_non_nullable
as String,targetVersion: null == targetVersion ? _self.targetVersion : targetVersion // ignore: cast_nullable_to_non_nullable
as String,canAutoEnter: null == canAutoEnter ? _self.canAutoEnter : canAutoEnter // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateEnteringBootloader implements FirmwareUpdateState {
  const FirmwareUpdateStateEnteringBootloader({required this.firmwarePath, required this.targetVersion, this.progress = 0});
  

 final  String firmwarePath;
 final  String targetVersion;
/// Progress 0.0 to 1.0 of the bootloader switch wait period
@JsonKey() final  double progress;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateEnteringBootloaderCopyWith<FirmwareUpdateStateEnteringBootloader> get copyWith => _$FirmwareUpdateStateEnteringBootloaderCopyWithImpl<FirmwareUpdateStateEnteringBootloader>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateEnteringBootloader&&(identical(other.firmwarePath, firmwarePath) || other.firmwarePath == firmwarePath)&&(identical(other.targetVersion, targetVersion) || other.targetVersion == targetVersion)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,firmwarePath,targetVersion,progress);

@override
String toString() {
  return 'FirmwareUpdateState.enteringBootloader(firmwarePath: $firmwarePath, targetVersion: $targetVersion, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateEnteringBootloaderCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateEnteringBootloaderCopyWith(FirmwareUpdateStateEnteringBootloader value, $Res Function(FirmwareUpdateStateEnteringBootloader) _then) = _$FirmwareUpdateStateEnteringBootloaderCopyWithImpl;
@useResult
$Res call({
 String firmwarePath, String targetVersion, double progress
});




}
/// @nodoc
class _$FirmwareUpdateStateEnteringBootloaderCopyWithImpl<$Res>
    implements $FirmwareUpdateStateEnteringBootloaderCopyWith<$Res> {
  _$FirmwareUpdateStateEnteringBootloaderCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateEnteringBootloader _self;
  final $Res Function(FirmwareUpdateStateEnteringBootloader) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? firmwarePath = null,Object? targetVersion = null,Object? progress = null,}) {
  return _then(FirmwareUpdateStateEnteringBootloader(
firmwarePath: null == firmwarePath ? _self.firmwarePath : firmwarePath // ignore: cast_nullable_to_non_nullable
as String,targetVersion: null == targetVersion ? _self.targetVersion : targetVersion // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateFlashing implements FirmwareUpdateState {
  const FirmwareUpdateStateFlashing({required this.targetVersion, required this.progress});
  

 final  String targetVersion;
 final  FlashProgress progress;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateFlashingCopyWith<FirmwareUpdateStateFlashing> get copyWith => _$FirmwareUpdateStateFlashingCopyWithImpl<FirmwareUpdateStateFlashing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateFlashing&&(identical(other.targetVersion, targetVersion) || other.targetVersion == targetVersion)&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,targetVersion,progress);

@override
String toString() {
  return 'FirmwareUpdateState.flashing(targetVersion: $targetVersion, progress: $progress)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateFlashingCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateFlashingCopyWith(FirmwareUpdateStateFlashing value, $Res Function(FirmwareUpdateStateFlashing) _then) = _$FirmwareUpdateStateFlashingCopyWithImpl;
@useResult
$Res call({
 String targetVersion, FlashProgress progress
});


$FlashProgressCopyWith<$Res> get progress;

}
/// @nodoc
class _$FirmwareUpdateStateFlashingCopyWithImpl<$Res>
    implements $FirmwareUpdateStateFlashingCopyWith<$Res> {
  _$FirmwareUpdateStateFlashingCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateFlashing _self;
  final $Res Function(FirmwareUpdateStateFlashing) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetVersion = null,Object? progress = null,}) {
  return _then(FirmwareUpdateStateFlashing(
targetVersion: null == targetVersion ? _self.targetVersion : targetVersion // ignore: cast_nullable_to_non_nullable
as String,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as FlashProgress,
  ));
}

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FlashProgressCopyWith<$Res> get progress {
  
  return $FlashProgressCopyWith<$Res>(_self.progress, (value) {
    return _then(_self.copyWith(progress: value));
  });
}
}

/// @nodoc


class FirmwareUpdateStateVerifyingMidi implements FirmwareUpdateState {
  const FirmwareUpdateStateVerifyingMidi({required this.newVersion, this.completedAttempts = 0, this.totalAttempts = 12, this.requiresVersion = false});


 final  String newVersion;
@JsonKey() final  int completedAttempts;
@JsonKey() final  int totalAttempts;
@JsonKey() final  bool requiresVersion;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateVerifyingMidiCopyWith<FirmwareUpdateStateVerifyingMidi> get copyWith => _$FirmwareUpdateStateVerifyingMidiCopyWithImpl<FirmwareUpdateStateVerifyingMidi>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateVerifyingMidi&&(identical(other.newVersion, newVersion) || other.newVersion == newVersion)&&(identical(other.completedAttempts, completedAttempts) || other.completedAttempts == completedAttempts)&&(identical(other.totalAttempts, totalAttempts) || other.totalAttempts == totalAttempts)&&(identical(other.requiresVersion, requiresVersion) || other.requiresVersion == requiresVersion));
}


@override
int get hashCode => Object.hash(runtimeType,newVersion,completedAttempts,totalAttempts,requiresVersion);

@override
String toString() {
  return 'FirmwareUpdateState.verifyingMidi(newVersion: $newVersion, completedAttempts: $completedAttempts, totalAttempts: $totalAttempts, requiresVersion: $requiresVersion)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateVerifyingMidiCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateVerifyingMidiCopyWith(FirmwareUpdateStateVerifyingMidi value, $Res Function(FirmwareUpdateStateVerifyingMidi) _then) = _$FirmwareUpdateStateVerifyingMidiCopyWithImpl;
@useResult
$Res call({
 String newVersion, int completedAttempts, int totalAttempts, bool requiresVersion
});




}
/// @nodoc
class _$FirmwareUpdateStateVerifyingMidiCopyWithImpl<$Res>
    implements $FirmwareUpdateStateVerifyingMidiCopyWith<$Res> {
  _$FirmwareUpdateStateVerifyingMidiCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateVerifyingMidi _self;
  final $Res Function(FirmwareUpdateStateVerifyingMidi) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? newVersion = null,Object? completedAttempts = null,Object? totalAttempts = null,Object? requiresVersion = null,}) {
  return _then(FirmwareUpdateStateVerifyingMidi(
newVersion: null == newVersion ? _self.newVersion : newVersion // ignore: cast_nullable_to_non_nullable
as String,completedAttempts: null == completedAttempts ? _self.completedAttempts : completedAttempts // ignore: cast_nullable_to_non_nullable
as int,totalAttempts: null == totalAttempts ? _self.totalAttempts : totalAttempts // ignore: cast_nullable_to_non_nullable
as int,requiresVersion: null == requiresVersion ? _self.requiresVersion : requiresVersion // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateMidiRecoveryRequired implements FirmwareUpdateState {
  const FirmwareUpdateStateMidiRecoveryRequired({required this.newVersion, required this.isWindows, this.verificationMessage});


 final  String newVersion;
 final  bool isWindows;
 final  String? verificationMessage;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateMidiRecoveryRequiredCopyWith<FirmwareUpdateStateMidiRecoveryRequired> get copyWith => _$FirmwareUpdateStateMidiRecoveryRequiredCopyWithImpl<FirmwareUpdateStateMidiRecoveryRequired>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateMidiRecoveryRequired&&(identical(other.newVersion, newVersion) || other.newVersion == newVersion)&&(identical(other.isWindows, isWindows) || other.isWindows == isWindows)&&(identical(other.verificationMessage, verificationMessage) || other.verificationMessage == verificationMessage));
}


@override
int get hashCode => Object.hash(runtimeType,newVersion,isWindows,verificationMessage);

@override
String toString() {
  return 'FirmwareUpdateState.midiRecoveryRequired(newVersion: $newVersion, isWindows: $isWindows, verificationMessage: $verificationMessage)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateMidiRecoveryRequiredCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateMidiRecoveryRequiredCopyWith(FirmwareUpdateStateMidiRecoveryRequired value, $Res Function(FirmwareUpdateStateMidiRecoveryRequired) _then) = _$FirmwareUpdateStateMidiRecoveryRequiredCopyWithImpl;
@useResult
$Res call({
 String newVersion, bool isWindows, String? verificationMessage
});




}
/// @nodoc
class _$FirmwareUpdateStateMidiRecoveryRequiredCopyWithImpl<$Res>
    implements $FirmwareUpdateStateMidiRecoveryRequiredCopyWith<$Res> {
  _$FirmwareUpdateStateMidiRecoveryRequiredCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateMidiRecoveryRequired _self;
  final $Res Function(FirmwareUpdateStateMidiRecoveryRequired) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? newVersion = null,Object? isWindows = null,Object? verificationMessage = freezed,}) {
  return _then(FirmwareUpdateStateMidiRecoveryRequired(
newVersion: null == newVersion ? _self.newVersion : newVersion // ignore: cast_nullable_to_non_nullable
as String,isWindows: null == isWindows ? _self.isWindows : isWindows // ignore: cast_nullable_to_non_nullable
as bool,verificationMessage: freezed == verificationMessage ? _self.verificationMessage : verificationMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateSuccess implements FirmwareUpdateState {
  const FirmwareUpdateStateSuccess({required this.newVersion});
  

 final  String newVersion;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateSuccessCopyWith<FirmwareUpdateStateSuccess> get copyWith => _$FirmwareUpdateStateSuccessCopyWithImpl<FirmwareUpdateStateSuccess>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateSuccess&&(identical(other.newVersion, newVersion) || other.newVersion == newVersion));
}


@override
int get hashCode => Object.hash(runtimeType,newVersion);

@override
String toString() {
  return 'FirmwareUpdateState.success(newVersion: $newVersion)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateSuccessCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateSuccessCopyWith(FirmwareUpdateStateSuccess value, $Res Function(FirmwareUpdateStateSuccess) _then) = _$FirmwareUpdateStateSuccessCopyWithImpl;
@useResult
$Res call({
 String newVersion
});




}
/// @nodoc
class _$FirmwareUpdateStateSuccessCopyWithImpl<$Res>
    implements $FirmwareUpdateStateSuccessCopyWith<$Res> {
  _$FirmwareUpdateStateSuccessCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateSuccess _self;
  final $Res Function(FirmwareUpdateStateSuccess) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? newVersion = null,}) {
  return _then(FirmwareUpdateStateSuccess(
newVersion: null == newVersion ? _self.newVersion : newVersion // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FirmwareUpdateStateError implements FirmwareUpdateState {
  const FirmwareUpdateStateError({required this.message, this.errorType = FirmwareErrorType.general, this.failedStage = null, this.firmwarePath = null, this.targetVersion = null});
  

 final  String message;
/// Type of error that occurred
@JsonKey() final  FirmwareErrorType errorType;
/// The stage at which the error occurred (if during flash process)
@JsonKey() final  FlashStage? failedStage;
/// Path to the firmware file (for retry operations)
@JsonKey() final  String? firmwarePath;
/// Target version being installed (for display)
@JsonKey() final  String? targetVersion;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirmwareUpdateStateErrorCopyWith<FirmwareUpdateStateError> get copyWith => _$FirmwareUpdateStateErrorCopyWithImpl<FirmwareUpdateStateError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FirmwareUpdateStateError&&(identical(other.message, message) || other.message == message)&&(identical(other.errorType, errorType) || other.errorType == errorType)&&(identical(other.failedStage, failedStage) || other.failedStage == failedStage)&&(identical(other.firmwarePath, firmwarePath) || other.firmwarePath == firmwarePath)&&(identical(other.targetVersion, targetVersion) || other.targetVersion == targetVersion));
}


@override
int get hashCode => Object.hash(runtimeType,message,errorType,failedStage,firmwarePath,targetVersion);

@override
String toString() {
  return 'FirmwareUpdateState.error(message: $message, errorType: $errorType, failedStage: $failedStage, firmwarePath: $firmwarePath, targetVersion: $targetVersion)';
}


}

/// @nodoc
abstract mixin class $FirmwareUpdateStateErrorCopyWith<$Res> implements $FirmwareUpdateStateCopyWith<$Res> {
  factory $FirmwareUpdateStateErrorCopyWith(FirmwareUpdateStateError value, $Res Function(FirmwareUpdateStateError) _then) = _$FirmwareUpdateStateErrorCopyWithImpl;
@useResult
$Res call({
 String message, FirmwareErrorType errorType, FlashStage? failedStage, String? firmwarePath, String? targetVersion
});




}
/// @nodoc
class _$FirmwareUpdateStateErrorCopyWithImpl<$Res>
    implements $FirmwareUpdateStateErrorCopyWith<$Res> {
  _$FirmwareUpdateStateErrorCopyWithImpl(this._self, this._then);

  final FirmwareUpdateStateError _self;
  final $Res Function(FirmwareUpdateStateError) _then;

/// Create a copy of FirmwareUpdateState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? errorType = null,Object? failedStage = freezed,Object? firmwarePath = freezed,Object? targetVersion = freezed,}) {
  return _then(FirmwareUpdateStateError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,errorType: null == errorType ? _self.errorType : errorType // ignore: cast_nullable_to_non_nullable
as FirmwareErrorType,failedStage: freezed == failedStage ? _self.failedStage : failedStage // ignore: cast_nullable_to_non_nullable
as FlashStage?,firmwarePath: freezed == firmwarePath ? _self.firmwarePath : firmwarePath // ignore: cast_nullable_to_non_nullable
as String?,targetVersion: freezed == targetVersion ? _self.targetVersion : targetVersion // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
