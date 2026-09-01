part of 'disting_cubit.dart';

@freezed
sealed class Slot with _$Slot {
  const factory Slot({
    required Algorithm algorithm,
    required RoutingInfo routing,
    required ParameterPages pages,
    required List<ParameterInfo> parameters,
    required List<ParameterValue> values,
    required List<ParameterEnumStrings> enums,
    required List<Mapping> mappings,
    required List<ParameterValueString> valueStrings,

    /// Output mode usage map: parameter number -> list of affected parameter numbers
    /// Populated from SysEx 0x55 responses (Story 7.4)
    @Default({}) Map<int, List<int>> outputModeMap,
  }) = _Slot;
}

@freezed
sealed class MappedParameter with _$MappedParameter {
  const factory MappedParameter({
    required final ParameterInfo parameter,
    required final ParameterValue value,
    required final ParameterEnumStrings enums,
    required final ParameterValueString valueString,
    required final Mapping mapping,
    required final Algorithm algorithm,
  }) = _MappedParameter;
}

@freezed
sealed class DistingState with _$DistingState {
  const factory DistingState.initial() = DistingStateInitial;

  const factory DistingState.selectDevice({
    required List<MidiDevice> inputDevices,
    required List<MidiDevice> outputDevices,
    required bool canWorkOffline,
    @Default(null) MidiDevice? selectedInputDevice,
    @Default(null) MidiDevice? selectedOutputDevice,
    @Default(0) int selectedSysExId,
  }) = DistingStateSelectDevice;

  const factory DistingState.connected({
    required IDistingMidiManager disting,
    MidiDevice? inputDevice,
    MidiDevice? outputDevice,
    @Default(false) bool offline,
    @Default(false) bool loading,
    @Default(null) String? syncStatus,
    @Default(null) double? syncProgress,
  }) = DistingStateConnected;

  const factory DistingState.synchronized({
    required IDistingMidiManager disting,
    required String distingVersion,
    required FirmwareVersion firmwareVersion,
    required String presetName,
    required List<AlgorithmInfo> algorithms,
    required List<Slot> slots,
    required List<String> unitStrings,
    @Default(null) MidiDevice? inputDevice,
    @Default(null) MidiDevice? outputDevice,
    @Default(false) bool loading,
    @Default(false) bool offline,
    @Default(null) Uint8List? screenshot,
    @Default(false) bool demo,
    @Default(null) VideoStreamState? videoStream,

    /// Available firmware update (null if no update available or not checked)
    @Default(null) FirmwareRelease? availableFirmwareUpdate,

    /// Performance page items (firmware v1.16+, populated via SysEx 0x57/0x58)
    @Default([]) List<PerformancePageItem> perfPageItems,

    /// True when the in-memory preset has been mutated since the last
    /// save / load / new / device refresh. Cleared on save/load/new/refresh.
    @Default(false) bool isDirty,

    /// The name of a preset that is currently awaiting confirmation to be overwritten
    @Default(null) String? renameConfirmationName,
  }) = DistingStateSynchronized;
}
