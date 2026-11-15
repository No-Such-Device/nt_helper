// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metadata_sync_cubit.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MetadataSyncState implements DiagnosticableTreeMixin {




@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState'))
    ;
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSyncState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState()';
}


}

/// @nodoc
class $MetadataSyncStateCopyWith<$Res>  {
$MetadataSyncStateCopyWith(MetadataSyncState _, $Res Function(MetadataSyncState) __);
}


/// Adds pattern-matching-related methods to [MetadataSyncState].
extension MetadataSyncStatePatterns on MetadataSyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Idle value)?  idle,TResult Function( SyncingMetadata value)?  syncingMetadata,TResult Function( CheckpointFound value)?  checkpointFound,TResult Function( MetadataSyncSuccess value)?  metadataSyncSuccess,TResult Function( MetadataSyncFailure value)?  metadataSyncFailure,TResult Function( SavingPreset value)?  savingPreset,TResult Function( LoadingPreset value)?  loadingPreset,TResult Function( InjectingTemplate value)?  injectingTemplate,TResult Function( PresetSaveSuccess value)?  presetSaveSuccess,TResult Function( PresetSaveFailure value)?  presetSaveFailure,TResult Function( PresetLoadSuccess value)?  presetLoadSuccess,TResult Function( PresetLoadFailure value)?  presetLoadFailure,TResult Function( DeletingPreset value)?  deletingPreset,TResult Function( PresetDeleteSuccess value)?  presetDeleteSuccess,TResult Function( PresetDeleteFailure value)?  presetDeleteFailure,TResult Function( ViewingLocalData value)?  viewingLocalData,TResult Function( Failure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Idle() when idle != null:
return idle(_that);case SyncingMetadata() when syncingMetadata != null:
return syncingMetadata(_that);case CheckpointFound() when checkpointFound != null:
return checkpointFound(_that);case MetadataSyncSuccess() when metadataSyncSuccess != null:
return metadataSyncSuccess(_that);case MetadataSyncFailure() when metadataSyncFailure != null:
return metadataSyncFailure(_that);case SavingPreset() when savingPreset != null:
return savingPreset(_that);case LoadingPreset() when loadingPreset != null:
return loadingPreset(_that);case InjectingTemplate() when injectingTemplate != null:
return injectingTemplate(_that);case PresetSaveSuccess() when presetSaveSuccess != null:
return presetSaveSuccess(_that);case PresetSaveFailure() when presetSaveFailure != null:
return presetSaveFailure(_that);case PresetLoadSuccess() when presetLoadSuccess != null:
return presetLoadSuccess(_that);case PresetLoadFailure() when presetLoadFailure != null:
return presetLoadFailure(_that);case DeletingPreset() when deletingPreset != null:
return deletingPreset(_that);case PresetDeleteSuccess() when presetDeleteSuccess != null:
return presetDeleteSuccess(_that);case PresetDeleteFailure() when presetDeleteFailure != null:
return presetDeleteFailure(_that);case ViewingLocalData() when viewingLocalData != null:
return viewingLocalData(_that);case Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Idle value)  idle,required TResult Function( SyncingMetadata value)  syncingMetadata,required TResult Function( CheckpointFound value)  checkpointFound,required TResult Function( MetadataSyncSuccess value)  metadataSyncSuccess,required TResult Function( MetadataSyncFailure value)  metadataSyncFailure,required TResult Function( SavingPreset value)  savingPreset,required TResult Function( LoadingPreset value)  loadingPreset,required TResult Function( InjectingTemplate value)  injectingTemplate,required TResult Function( PresetSaveSuccess value)  presetSaveSuccess,required TResult Function( PresetSaveFailure value)  presetSaveFailure,required TResult Function( PresetLoadSuccess value)  presetLoadSuccess,required TResult Function( PresetLoadFailure value)  presetLoadFailure,required TResult Function( DeletingPreset value)  deletingPreset,required TResult Function( PresetDeleteSuccess value)  presetDeleteSuccess,required TResult Function( PresetDeleteFailure value)  presetDeleteFailure,required TResult Function( ViewingLocalData value)  viewingLocalData,required TResult Function( Failure value)  failure,}){
final _that = this;
switch (_that) {
case Idle():
return idle(_that);case SyncingMetadata():
return syncingMetadata(_that);case CheckpointFound():
return checkpointFound(_that);case MetadataSyncSuccess():
return metadataSyncSuccess(_that);case MetadataSyncFailure():
return metadataSyncFailure(_that);case SavingPreset():
return savingPreset(_that);case LoadingPreset():
return loadingPreset(_that);case InjectingTemplate():
return injectingTemplate(_that);case PresetSaveSuccess():
return presetSaveSuccess(_that);case PresetSaveFailure():
return presetSaveFailure(_that);case PresetLoadSuccess():
return presetLoadSuccess(_that);case PresetLoadFailure():
return presetLoadFailure(_that);case DeletingPreset():
return deletingPreset(_that);case PresetDeleteSuccess():
return presetDeleteSuccess(_that);case PresetDeleteFailure():
return presetDeleteFailure(_that);case ViewingLocalData():
return viewingLocalData(_that);case Failure():
return failure(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Idle value)?  idle,TResult? Function( SyncingMetadata value)?  syncingMetadata,TResult? Function( CheckpointFound value)?  checkpointFound,TResult? Function( MetadataSyncSuccess value)?  metadataSyncSuccess,TResult? Function( MetadataSyncFailure value)?  metadataSyncFailure,TResult? Function( SavingPreset value)?  savingPreset,TResult? Function( LoadingPreset value)?  loadingPreset,TResult? Function( InjectingTemplate value)?  injectingTemplate,TResult? Function( PresetSaveSuccess value)?  presetSaveSuccess,TResult? Function( PresetSaveFailure value)?  presetSaveFailure,TResult? Function( PresetLoadSuccess value)?  presetLoadSuccess,TResult? Function( PresetLoadFailure value)?  presetLoadFailure,TResult? Function( DeletingPreset value)?  deletingPreset,TResult? Function( PresetDeleteSuccess value)?  presetDeleteSuccess,TResult? Function( PresetDeleteFailure value)?  presetDeleteFailure,TResult? Function( ViewingLocalData value)?  viewingLocalData,TResult? Function( Failure value)?  failure,}){
final _that = this;
switch (_that) {
case Idle() when idle != null:
return idle(_that);case SyncingMetadata() when syncingMetadata != null:
return syncingMetadata(_that);case CheckpointFound() when checkpointFound != null:
return checkpointFound(_that);case MetadataSyncSuccess() when metadataSyncSuccess != null:
return metadataSyncSuccess(_that);case MetadataSyncFailure() when metadataSyncFailure != null:
return metadataSyncFailure(_that);case SavingPreset() when savingPreset != null:
return savingPreset(_that);case LoadingPreset() when loadingPreset != null:
return loadingPreset(_that);case InjectingTemplate() when injectingTemplate != null:
return injectingTemplate(_that);case PresetSaveSuccess() when presetSaveSuccess != null:
return presetSaveSuccess(_that);case PresetSaveFailure() when presetSaveFailure != null:
return presetSaveFailure(_that);case PresetLoadSuccess() when presetLoadSuccess != null:
return presetLoadSuccess(_that);case PresetLoadFailure() when presetLoadFailure != null:
return presetLoadFailure(_that);case DeletingPreset() when deletingPreset != null:
return deletingPreset(_that);case PresetDeleteSuccess() when presetDeleteSuccess != null:
return presetDeleteSuccess(_that);case PresetDeleteFailure() when presetDeleteFailure != null:
return presetDeleteFailure(_that);case ViewingLocalData() when viewingLocalData != null:
return viewingLocalData(_that);case Failure() when failure != null:
return failure(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( double progress,  String mainMessage,  String subMessage,  int? algorithmsProcessed,  int? totalAlgorithms)?  syncingMetadata,TResult Function( String algorithmName,  int algorithmIndex)?  checkpointFound,TResult Function( String message)?  metadataSyncSuccess,TResult Function( String error)?  metadataSyncFailure,TResult Function()?  savingPreset,TResult Function()?  loadingPreset,TResult Function( int applied,  int total)?  injectingTemplate,TResult Function( String message)?  presetSaveSuccess,TResult Function( String error)?  presetSaveFailure,TResult Function( String message)?  presetLoadSuccess,TResult Function( String error)?  presetLoadFailure,TResult Function()?  deletingPreset,TResult Function( String message)?  presetDeleteSuccess,TResult Function( String error)?  presetDeleteFailure,TResult Function( List<AlgorithmEntry> algorithms,  Map<String, int> parameterCounts,  List<PresetEntry> presets)?  viewingLocalData,TResult Function( String error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Idle() when idle != null:
return idle();case SyncingMetadata() when syncingMetadata != null:
return syncingMetadata(_that.progress,_that.mainMessage,_that.subMessage,_that.algorithmsProcessed,_that.totalAlgorithms);case CheckpointFound() when checkpointFound != null:
return checkpointFound(_that.algorithmName,_that.algorithmIndex);case MetadataSyncSuccess() when metadataSyncSuccess != null:
return metadataSyncSuccess(_that.message);case MetadataSyncFailure() when metadataSyncFailure != null:
return metadataSyncFailure(_that.error);case SavingPreset() when savingPreset != null:
return savingPreset();case LoadingPreset() when loadingPreset != null:
return loadingPreset();case InjectingTemplate() when injectingTemplate != null:
return injectingTemplate(_that.applied,_that.total);case PresetSaveSuccess() when presetSaveSuccess != null:
return presetSaveSuccess(_that.message);case PresetSaveFailure() when presetSaveFailure != null:
return presetSaveFailure(_that.error);case PresetLoadSuccess() when presetLoadSuccess != null:
return presetLoadSuccess(_that.message);case PresetLoadFailure() when presetLoadFailure != null:
return presetLoadFailure(_that.error);case DeletingPreset() when deletingPreset != null:
return deletingPreset();case PresetDeleteSuccess() when presetDeleteSuccess != null:
return presetDeleteSuccess(_that.message);case PresetDeleteFailure() when presetDeleteFailure != null:
return presetDeleteFailure(_that.error);case ViewingLocalData() when viewingLocalData != null:
return viewingLocalData(_that.algorithms,_that.parameterCounts,_that.presets);case Failure() when failure != null:
return failure(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( double progress,  String mainMessage,  String subMessage,  int? algorithmsProcessed,  int? totalAlgorithms)  syncingMetadata,required TResult Function( String algorithmName,  int algorithmIndex)  checkpointFound,required TResult Function( String message)  metadataSyncSuccess,required TResult Function( String error)  metadataSyncFailure,required TResult Function()  savingPreset,required TResult Function()  loadingPreset,required TResult Function( int applied,  int total)  injectingTemplate,required TResult Function( String message)  presetSaveSuccess,required TResult Function( String error)  presetSaveFailure,required TResult Function( String message)  presetLoadSuccess,required TResult Function( String error)  presetLoadFailure,required TResult Function()  deletingPreset,required TResult Function( String message)  presetDeleteSuccess,required TResult Function( String error)  presetDeleteFailure,required TResult Function( List<AlgorithmEntry> algorithms,  Map<String, int> parameterCounts,  List<PresetEntry> presets)  viewingLocalData,required TResult Function( String error)  failure,}) {final _that = this;
switch (_that) {
case Idle():
return idle();case SyncingMetadata():
return syncingMetadata(_that.progress,_that.mainMessage,_that.subMessage,_that.algorithmsProcessed,_that.totalAlgorithms);case CheckpointFound():
return checkpointFound(_that.algorithmName,_that.algorithmIndex);case MetadataSyncSuccess():
return metadataSyncSuccess(_that.message);case MetadataSyncFailure():
return metadataSyncFailure(_that.error);case SavingPreset():
return savingPreset();case LoadingPreset():
return loadingPreset();case InjectingTemplate():
return injectingTemplate(_that.applied,_that.total);case PresetSaveSuccess():
return presetSaveSuccess(_that.message);case PresetSaveFailure():
return presetSaveFailure(_that.error);case PresetLoadSuccess():
return presetLoadSuccess(_that.message);case PresetLoadFailure():
return presetLoadFailure(_that.error);case DeletingPreset():
return deletingPreset();case PresetDeleteSuccess():
return presetDeleteSuccess(_that.message);case PresetDeleteFailure():
return presetDeleteFailure(_that.error);case ViewingLocalData():
return viewingLocalData(_that.algorithms,_that.parameterCounts,_that.presets);case Failure():
return failure(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( double progress,  String mainMessage,  String subMessage,  int? algorithmsProcessed,  int? totalAlgorithms)?  syncingMetadata,TResult? Function( String algorithmName,  int algorithmIndex)?  checkpointFound,TResult? Function( String message)?  metadataSyncSuccess,TResult? Function( String error)?  metadataSyncFailure,TResult? Function()?  savingPreset,TResult? Function()?  loadingPreset,TResult? Function( int applied,  int total)?  injectingTemplate,TResult? Function( String message)?  presetSaveSuccess,TResult? Function( String error)?  presetSaveFailure,TResult? Function( String message)?  presetLoadSuccess,TResult? Function( String error)?  presetLoadFailure,TResult? Function()?  deletingPreset,TResult? Function( String message)?  presetDeleteSuccess,TResult? Function( String error)?  presetDeleteFailure,TResult? Function( List<AlgorithmEntry> algorithms,  Map<String, int> parameterCounts,  List<PresetEntry> presets)?  viewingLocalData,TResult? Function( String error)?  failure,}) {final _that = this;
switch (_that) {
case Idle() when idle != null:
return idle();case SyncingMetadata() when syncingMetadata != null:
return syncingMetadata(_that.progress,_that.mainMessage,_that.subMessage,_that.algorithmsProcessed,_that.totalAlgorithms);case CheckpointFound() when checkpointFound != null:
return checkpointFound(_that.algorithmName,_that.algorithmIndex);case MetadataSyncSuccess() when metadataSyncSuccess != null:
return metadataSyncSuccess(_that.message);case MetadataSyncFailure() when metadataSyncFailure != null:
return metadataSyncFailure(_that.error);case SavingPreset() when savingPreset != null:
return savingPreset();case LoadingPreset() when loadingPreset != null:
return loadingPreset();case InjectingTemplate() when injectingTemplate != null:
return injectingTemplate(_that.applied,_that.total);case PresetSaveSuccess() when presetSaveSuccess != null:
return presetSaveSuccess(_that.message);case PresetSaveFailure() when presetSaveFailure != null:
return presetSaveFailure(_that.error);case PresetLoadSuccess() when presetLoadSuccess != null:
return presetLoadSuccess(_that.message);case PresetLoadFailure() when presetLoadFailure != null:
return presetLoadFailure(_that.error);case DeletingPreset() when deletingPreset != null:
return deletingPreset();case PresetDeleteSuccess() when presetDeleteSuccess != null:
return presetDeleteSuccess(_that.message);case PresetDeleteFailure() when presetDeleteFailure != null:
return presetDeleteFailure(_that.error);case ViewingLocalData() when viewingLocalData != null:
return viewingLocalData(_that.algorithms,_that.parameterCounts,_that.presets);case Failure() when failure != null:
return failure(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class Idle with DiagnosticableTreeMixin implements MetadataSyncState {
  const Idle();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.idle'))
    ;
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.idle()';
}


}




/// @nodoc


class SyncingMetadata with DiagnosticableTreeMixin implements MetadataSyncState {
  const SyncingMetadata({required this.progress, required this.mainMessage, required this.subMessage, this.algorithmsProcessed, this.totalAlgorithms});


 final  double progress;
 final  String mainMessage;
 final  String subMessage;
 final  int? algorithmsProcessed;
 final  int? totalAlgorithms;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncingMetadataCopyWith<SyncingMetadata> get copyWith => _$SyncingMetadataCopyWithImpl<SyncingMetadata>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.syncingMetadata'))
    ..add(DiagnosticsProperty('progress', progress))..add(DiagnosticsProperty('mainMessage', mainMessage))..add(DiagnosticsProperty('subMessage', subMessage))..add(DiagnosticsProperty('algorithmsProcessed', algorithmsProcessed))..add(DiagnosticsProperty('totalAlgorithms', totalAlgorithms));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncingMetadata&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.mainMessage, mainMessage) || other.mainMessage == mainMessage)&&(identical(other.subMessage, subMessage) || other.subMessage == subMessage)&&(identical(other.algorithmsProcessed, algorithmsProcessed) || other.algorithmsProcessed == algorithmsProcessed)&&(identical(other.totalAlgorithms, totalAlgorithms) || other.totalAlgorithms == totalAlgorithms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,progress,mainMessage,subMessage,algorithmsProcessed,totalAlgorithms);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.syncingMetadata(progress: $progress, mainMessage: $mainMessage, subMessage: $subMessage, algorithmsProcessed: $algorithmsProcessed, totalAlgorithms: $totalAlgorithms)';
}


}

/// @nodoc
abstract mixin class $SyncingMetadataCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $SyncingMetadataCopyWith(SyncingMetadata value, $Res Function(SyncingMetadata) _then) = _$SyncingMetadataCopyWithImpl;
@useResult
$Res call({
 double progress, String mainMessage, String subMessage, int? algorithmsProcessed, int? totalAlgorithms
});




}
/// @nodoc
class _$SyncingMetadataCopyWithImpl<$Res>
    implements $SyncingMetadataCopyWith<$Res> {
  _$SyncingMetadataCopyWithImpl(this._self, this._then);

  final SyncingMetadata _self;
  final $Res Function(SyncingMetadata) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,Object? mainMessage = null,Object? subMessage = null,Object? algorithmsProcessed = freezed,Object? totalAlgorithms = freezed,}) {
  return _then(SyncingMetadata(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,mainMessage: null == mainMessage ? _self.mainMessage : mainMessage // ignore: cast_nullable_to_non_nullable
as String,subMessage: null == subMessage ? _self.subMessage : subMessage // ignore: cast_nullable_to_non_nullable
as String,algorithmsProcessed: freezed == algorithmsProcessed ? _self.algorithmsProcessed : algorithmsProcessed // ignore: cast_nullable_to_non_nullable
as int?,totalAlgorithms: freezed == totalAlgorithms ? _self.totalAlgorithms : totalAlgorithms // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class CheckpointFound with DiagnosticableTreeMixin implements MetadataSyncState {
  const CheckpointFound({required this.algorithmName, required this.algorithmIndex});


 final  String algorithmName;
 final  int algorithmIndex;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckpointFoundCopyWith<CheckpointFound> get copyWith => _$CheckpointFoundCopyWithImpl<CheckpointFound>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.checkpointFound'))
    ..add(DiagnosticsProperty('algorithmName', algorithmName))..add(DiagnosticsProperty('algorithmIndex', algorithmIndex));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckpointFound&&(identical(other.algorithmName, algorithmName) || other.algorithmName == algorithmName)&&(identical(other.algorithmIndex, algorithmIndex) || other.algorithmIndex == algorithmIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,algorithmName,algorithmIndex);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.checkpointFound(algorithmName: $algorithmName, algorithmIndex: $algorithmIndex)';
}


}

/// @nodoc
abstract mixin class $CheckpointFoundCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $CheckpointFoundCopyWith(CheckpointFound value, $Res Function(CheckpointFound) _then) = _$CheckpointFoundCopyWithImpl;
@useResult
$Res call({
 String algorithmName, int algorithmIndex
});




}
/// @nodoc
class _$CheckpointFoundCopyWithImpl<$Res>
    implements $CheckpointFoundCopyWith<$Res> {
  _$CheckpointFoundCopyWithImpl(this._self, this._then);

  final CheckpointFound _self;
  final $Res Function(CheckpointFound) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? algorithmName = null,Object? algorithmIndex = null,}) {
  return _then(CheckpointFound(
algorithmName: null == algorithmName ? _self.algorithmName : algorithmName // ignore: cast_nullable_to_non_nullable
as String,algorithmIndex: null == algorithmIndex ? _self.algorithmIndex : algorithmIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class MetadataSyncSuccess with DiagnosticableTreeMixin implements MetadataSyncState {
  const MetadataSyncSuccess(this.message);


 final  String message;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSyncSuccessCopyWith<MetadataSyncSuccess> get copyWith => _$MetadataSyncSuccessCopyWithImpl<MetadataSyncSuccess>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.metadataSyncSuccess'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSyncSuccess&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.metadataSyncSuccess(message: $message)';
}


}

/// @nodoc
abstract mixin class $MetadataSyncSuccessCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $MetadataSyncSuccessCopyWith(MetadataSyncSuccess value, $Res Function(MetadataSyncSuccess) _then) = _$MetadataSyncSuccessCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$MetadataSyncSuccessCopyWithImpl<$Res>
    implements $MetadataSyncSuccessCopyWith<$Res> {
  _$MetadataSyncSuccessCopyWithImpl(this._self, this._then);

  final MetadataSyncSuccess _self;
  final $Res Function(MetadataSyncSuccess) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MetadataSyncSuccess(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class MetadataSyncFailure with DiagnosticableTreeMixin implements MetadataSyncState {
  const MetadataSyncFailure(this.error);


 final  String error;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataSyncFailureCopyWith<MetadataSyncFailure> get copyWith => _$MetadataSyncFailureCopyWithImpl<MetadataSyncFailure>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.metadataSyncFailure'))
    ..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataSyncFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.metadataSyncFailure(error: $error)';
}


}

/// @nodoc
abstract mixin class $MetadataSyncFailureCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $MetadataSyncFailureCopyWith(MetadataSyncFailure value, $Res Function(MetadataSyncFailure) _then) = _$MetadataSyncFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$MetadataSyncFailureCopyWithImpl<$Res>
    implements $MetadataSyncFailureCopyWith<$Res> {
  _$MetadataSyncFailureCopyWithImpl(this._self, this._then);

  final MetadataSyncFailure _self;
  final $Res Function(MetadataSyncFailure) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(MetadataSyncFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SavingPreset with DiagnosticableTreeMixin implements MetadataSyncState {
  const SavingPreset();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.savingPreset'))
    ;
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SavingPreset);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.savingPreset()';
}


}




/// @nodoc


class LoadingPreset with DiagnosticableTreeMixin implements MetadataSyncState {
  const LoadingPreset();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.loadingPreset'))
    ;
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingPreset);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.loadingPreset()';
}


}




/// @nodoc


class InjectingTemplate with DiagnosticableTreeMixin implements MetadataSyncState {
  const InjectingTemplate({required this.applied, required this.total});


 final  int applied;
 final  int total;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InjectingTemplateCopyWith<InjectingTemplate> get copyWith => _$InjectingTemplateCopyWithImpl<InjectingTemplate>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.injectingTemplate'))
    ..add(DiagnosticsProperty('applied', applied))..add(DiagnosticsProperty('total', total));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InjectingTemplate&&(identical(other.applied, applied) || other.applied == applied)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,applied,total);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.injectingTemplate(applied: $applied, total: $total)';
}


}

/// @nodoc
abstract mixin class $InjectingTemplateCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $InjectingTemplateCopyWith(InjectingTemplate value, $Res Function(InjectingTemplate) _then) = _$InjectingTemplateCopyWithImpl;
@useResult
$Res call({
 int applied, int total
});




}
/// @nodoc
class _$InjectingTemplateCopyWithImpl<$Res>
    implements $InjectingTemplateCopyWith<$Res> {
  _$InjectingTemplateCopyWithImpl(this._self, this._then);

  final InjectingTemplate _self;
  final $Res Function(InjectingTemplate) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? applied = null,Object? total = null,}) {
  return _then(InjectingTemplate(
applied: null == applied ? _self.applied : applied // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PresetSaveSuccess with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetSaveSuccess(this.message);


 final  String message;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetSaveSuccessCopyWith<PresetSaveSuccess> get copyWith => _$PresetSaveSuccessCopyWithImpl<PresetSaveSuccess>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetSaveSuccess'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetSaveSuccess&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetSaveSuccess(message: $message)';
}


}

/// @nodoc
abstract mixin class $PresetSaveSuccessCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetSaveSuccessCopyWith(PresetSaveSuccess value, $Res Function(PresetSaveSuccess) _then) = _$PresetSaveSuccessCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$PresetSaveSuccessCopyWithImpl<$Res>
    implements $PresetSaveSuccessCopyWith<$Res> {
  _$PresetSaveSuccessCopyWithImpl(this._self, this._then);

  final PresetSaveSuccess _self;
  final $Res Function(PresetSaveSuccess) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(PresetSaveSuccess(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PresetSaveFailure with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetSaveFailure(this.error);


 final  String error;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetSaveFailureCopyWith<PresetSaveFailure> get copyWith => _$PresetSaveFailureCopyWithImpl<PresetSaveFailure>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetSaveFailure'))
    ..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetSaveFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetSaveFailure(error: $error)';
}


}

/// @nodoc
abstract mixin class $PresetSaveFailureCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetSaveFailureCopyWith(PresetSaveFailure value, $Res Function(PresetSaveFailure) _then) = _$PresetSaveFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$PresetSaveFailureCopyWithImpl<$Res>
    implements $PresetSaveFailureCopyWith<$Res> {
  _$PresetSaveFailureCopyWithImpl(this._self, this._then);

  final PresetSaveFailure _self;
  final $Res Function(PresetSaveFailure) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(PresetSaveFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PresetLoadSuccess with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetLoadSuccess(this.message);


 final  String message;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetLoadSuccessCopyWith<PresetLoadSuccess> get copyWith => _$PresetLoadSuccessCopyWithImpl<PresetLoadSuccess>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetLoadSuccess'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetLoadSuccess&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetLoadSuccess(message: $message)';
}


}

/// @nodoc
abstract mixin class $PresetLoadSuccessCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetLoadSuccessCopyWith(PresetLoadSuccess value, $Res Function(PresetLoadSuccess) _then) = _$PresetLoadSuccessCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$PresetLoadSuccessCopyWithImpl<$Res>
    implements $PresetLoadSuccessCopyWith<$Res> {
  _$PresetLoadSuccessCopyWithImpl(this._self, this._then);

  final PresetLoadSuccess _self;
  final $Res Function(PresetLoadSuccess) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(PresetLoadSuccess(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PresetLoadFailure with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetLoadFailure(this.error);


 final  String error;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetLoadFailureCopyWith<PresetLoadFailure> get copyWith => _$PresetLoadFailureCopyWithImpl<PresetLoadFailure>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetLoadFailure'))
    ..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetLoadFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetLoadFailure(error: $error)';
}


}

/// @nodoc
abstract mixin class $PresetLoadFailureCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetLoadFailureCopyWith(PresetLoadFailure value, $Res Function(PresetLoadFailure) _then) = _$PresetLoadFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$PresetLoadFailureCopyWithImpl<$Res>
    implements $PresetLoadFailureCopyWith<$Res> {
  _$PresetLoadFailureCopyWithImpl(this._self, this._then);

  final PresetLoadFailure _self;
  final $Res Function(PresetLoadFailure) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(PresetLoadFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DeletingPreset with DiagnosticableTreeMixin implements MetadataSyncState {
  const DeletingPreset();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.deletingPreset'))
    ;
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeletingPreset);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.deletingPreset()';
}


}




/// @nodoc


class PresetDeleteSuccess with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetDeleteSuccess(this.message);


 final  String message;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetDeleteSuccessCopyWith<PresetDeleteSuccess> get copyWith => _$PresetDeleteSuccessCopyWithImpl<PresetDeleteSuccess>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetDeleteSuccess'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetDeleteSuccess&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetDeleteSuccess(message: $message)';
}


}

/// @nodoc
abstract mixin class $PresetDeleteSuccessCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetDeleteSuccessCopyWith(PresetDeleteSuccess value, $Res Function(PresetDeleteSuccess) _then) = _$PresetDeleteSuccessCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$PresetDeleteSuccessCopyWithImpl<$Res>
    implements $PresetDeleteSuccessCopyWith<$Res> {
  _$PresetDeleteSuccessCopyWithImpl(this._self, this._then);

  final PresetDeleteSuccess _self;
  final $Res Function(PresetDeleteSuccess) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(PresetDeleteSuccess(
null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PresetDeleteFailure with DiagnosticableTreeMixin implements MetadataSyncState {
  const PresetDeleteFailure(this.error);


 final  String error;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PresetDeleteFailureCopyWith<PresetDeleteFailure> get copyWith => _$PresetDeleteFailureCopyWithImpl<PresetDeleteFailure>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.presetDeleteFailure'))
    ..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PresetDeleteFailure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.presetDeleteFailure(error: $error)';
}


}

/// @nodoc
abstract mixin class $PresetDeleteFailureCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $PresetDeleteFailureCopyWith(PresetDeleteFailure value, $Res Function(PresetDeleteFailure) _then) = _$PresetDeleteFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$PresetDeleteFailureCopyWithImpl<$Res>
    implements $PresetDeleteFailureCopyWith<$Res> {
  _$PresetDeleteFailureCopyWithImpl(this._self, this._then);

  final PresetDeleteFailure _self;
  final $Res Function(PresetDeleteFailure) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(PresetDeleteFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ViewingLocalData with DiagnosticableTreeMixin implements MetadataSyncState {
  const ViewingLocalData({required  List<AlgorithmEntry> algorithms, required  Map<String, int> parameterCounts, required  List<PresetEntry> presets}): _algorithms = algorithms,_parameterCounts = parameterCounts,_presets = presets;


 final  List<AlgorithmEntry> _algorithms;
 List<AlgorithmEntry> get algorithms {
  if (_algorithms is EqualUnmodifiableListView) return _algorithms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_algorithms);
}

 final  Map<String, int> _parameterCounts;
 Map<String, int> get parameterCounts {
  if (_parameterCounts is EqualUnmodifiableMapView) return _parameterCounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_parameterCounts);
}

 final  List<PresetEntry> _presets;
 List<PresetEntry> get presets {
  if (_presets is EqualUnmodifiableListView) return _presets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_presets);
}


/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ViewingLocalDataCopyWith<ViewingLocalData> get copyWith => _$ViewingLocalDataCopyWithImpl<ViewingLocalData>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.viewingLocalData'))
    ..add(DiagnosticsProperty('algorithms', algorithms))..add(DiagnosticsProperty('parameterCounts', parameterCounts))..add(DiagnosticsProperty('presets', presets));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ViewingLocalData&&const DeepCollectionEquality().equals(other.algorithms, _algorithms)&&const DeepCollectionEquality().equals(other.parameterCounts, _parameterCounts)&&const DeepCollectionEquality().equals(other.presets, _presets));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_algorithms),const DeepCollectionEquality().hash(_parameterCounts),const DeepCollectionEquality().hash(_presets));
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.viewingLocalData(algorithms: $algorithms, parameterCounts: $parameterCounts, presets: $presets)';
}


}

/// @nodoc
abstract mixin class $ViewingLocalDataCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $ViewingLocalDataCopyWith(ViewingLocalData value, $Res Function(ViewingLocalData) _then) = _$ViewingLocalDataCopyWithImpl;
@useResult
$Res call({
 List<AlgorithmEntry> algorithms, Map<String, int> parameterCounts, List<PresetEntry> presets
});




}
/// @nodoc
class _$ViewingLocalDataCopyWithImpl<$Res>
    implements $ViewingLocalDataCopyWith<$Res> {
  _$ViewingLocalDataCopyWithImpl(this._self, this._then);

  final ViewingLocalData _self;
  final $Res Function(ViewingLocalData) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? algorithms = null,Object? parameterCounts = null,Object? presets = null,}) {
  return _then(ViewingLocalData(
algorithms: null == algorithms ? _self._algorithms : algorithms // ignore: cast_nullable_to_non_nullable
as List<AlgorithmEntry>,parameterCounts: null == parameterCounts ? _self._parameterCounts : parameterCounts // ignore: cast_nullable_to_non_nullable
as Map<String, int>,presets: null == presets ? _self._presets : presets // ignore: cast_nullable_to_non_nullable
as List<PresetEntry>,
  ));
}


}

/// @nodoc


class Failure with DiagnosticableTreeMixin implements MetadataSyncState {
  const Failure(this.error);


 final  String error;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailureCopyWith<Failure> get copyWith => _$FailureCopyWithImpl<Failure>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'MetadataSyncState.failure'))
    ..add(DiagnosticsProperty('error', error));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Failure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'MetadataSyncState.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $FailureCopyWith<$Res> implements $MetadataSyncStateCopyWith<$Res> {
  factory $FailureCopyWith(Failure value, $Res Function(Failure) _then) = _$FailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$FailureCopyWithImpl<$Res>
    implements $FailureCopyWith<$Res> {
  _$FailureCopyWithImpl(this._self, this._then);

  final Failure _self;
  final $Res Function(Failure) _then;

/// Create a copy of MetadataSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(Failure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
