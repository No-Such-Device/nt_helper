import 'dart:collection';

import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/slot_count_info.dart';

enum DeviceBusGroup { input, output, aux }

/// Immutable description of the buses exposed by the connected firmware.
///
/// Bus numbers are contiguous: inputs start at 1, followed by outputs and AUX.
/// ES-5 is intentionally not part of this profile because it is contextual to
/// USB From Host and dedicated ES-5 routing algorithms.
class DeviceIoProfile {
  static const int maximumBusNumber = 127;

  static const DeviceIoProfile distingLegacy = DeviceIoProfile._(
    inputBusCount: 12,
    outputBusCount: 8,
    auxBusCount: 8,
  );

  static const DeviceIoProfile distingExtended = DeviceIoProfile._(
    inputBusCount: 12,
    outputBusCount: 8,
    auxBusCount: 44,
  );

  final int inputBusCount;
  final int outputBusCount;
  final int auxBusCount;

  const DeviceIoProfile._({
    required this.inputBusCount,
    required this.outputBusCount,
    required this.auxBusCount,
  });

  static DeviceIoProfile? tryCreate({
    required int inputBusCount,
    required int outputBusCount,
    required int auxBusCount,
  }) {
    final counts = [inputBusCount, outputBusCount, auxBusCount];
    if (counts.any((count) => count < 0 || count > maximumBusNumber)) {
      return null;
    }
    if (inputBusCount + outputBusCount + auxBusCount > maximumBusNumber) {
      return null;
    }
    return DeviceIoProfile._(
      inputBusCount: inputBusCount,
      outputBusCount: outputBusCount,
      auxBusCount: auxBusCount,
    );
  }

  static DeviceIoProfile distingForFirmware(FirmwareVersion firmwareVersion) =>
      firmwareVersion.hasExtendedAuxBuses ? distingExtended : distingLegacy;

  static DeviceIoProfile resolve({
    required SlotCountInfo? slotCountInfo,
    required FirmwareVersion firmwareVersion,
  }) {
    final fallback = distingForFirmware(firmwareVersion);
    if (slotCountInfo == null || !slotCountInfo.hasCompleteBusCounts) {
      return fallback;
    }
    return tryCreate(
          inputBusCount: slotCountInfo.inputBusCount!,
          outputBusCount: slotCountInfo.outputBusCount!,
          auxBusCount: slotCountInfo.auxBusCount!,
        ) ??
        fallback;
  }

  int get inputStart => 1;
  int get outputStart => inputStart + inputBusCount;
  int get auxStart => outputStart + outputBusCount;
  int get maxBus => inputBusCount + outputBusCount + auxBusCount;

  List<int> get inputBuses => _range(inputStart, inputBusCount);
  List<int> get outputBuses => _range(outputStart, outputBusCount);
  List<int> get auxBuses => _range(auxStart, auxBusCount);
  List<int> get buses =>
      UnmodifiableListView<int>([...inputBuses, ...outputBuses, ...auxBuses]);

  /// The two contextual ES-5 bus values immediately after AUX.
  ///
  /// These are not generally valid profile buses. USB From Host may expose
  /// them when its parameter range includes them.
  List<int> get contextualEs5Buses => maxBus <= maximumBusNumber - 2
      ? UnmodifiableListView<int>([maxBus + 1, maxBus + 2])
      : const [];

  bool isInput(int bus) => _contains(inputStart, inputBusCount, bus);
  bool isOutput(int bus) => _contains(outputStart, outputBusCount, bus);
  bool isAux(int bus) => _contains(auxStart, auxBusCount, bus);
  bool contains(int bus) => isInput(bus) || isOutput(bus) || isAux(bus);

  DeviceBusGroup? groupOf(int bus) {
    if (isInput(bus)) return DeviceBusGroup.input;
    if (isOutput(bus)) return DeviceBusGroup.output;
    if (isAux(bus)) return DeviceBusGroup.aux;
    return null;
  }

  int? localNumber(int bus) {
    return switch (groupOf(bus)) {
      DeviceBusGroup.input => bus - inputStart + 1,
      DeviceBusGroup.output => bus - outputStart + 1,
      DeviceBusGroup.aux => bus - auxStart + 1,
      null => null,
    };
  }

  String? labelForBus(int bus) {
    final local = localNumber(bus);
    if (local == null) return null;
    return switch (groupOf(bus)!) {
      DeviceBusGroup.input => 'Input $local',
      DeviceBusGroup.output => 'Output $local',
      DeviceBusGroup.aux => 'Aux $local',
    };
  }

  int? busForLocalNumber(DeviceBusGroup group, int localNumber) {
    if (localNumber < 1) return null;
    final (start, count) = switch (group) {
      DeviceBusGroup.input => (inputStart, inputBusCount),
      DeviceBusGroup.output => (outputStart, outputBusCount),
      DeviceBusGroup.aux => (auxStart, auxBusCount),
    };
    if (localNumber > count) return null;
    return start + localNumber - 1;
  }

  List<int> busesWithin(int minimum, int maximum) {
    if (minimum > maximum) return const [];
    return UnmodifiableListView<int>(
      buses.where((bus) => bus >= minimum && bus <= maximum),
    );
  }

  static List<int> _range(int start, int count) => UnmodifiableListView<int>(
    List<int>.generate(count, (index) => start + index),
  );

  static bool _contains(int start, int count, int bus) =>
      count > 0 && bus >= start && bus < start + count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceIoProfile &&
          inputBusCount == other.inputBusCount &&
          outputBusCount == other.outputBusCount &&
          auxBusCount == other.auxBusCount;

  @override
  int get hashCode => Object.hash(inputBusCount, outputBusCount, auxBusCount);

  @override
  String toString() =>
      'DeviceIoProfile(inputs: $inputBusCount, outputs: $outputBusCount, aux: $auxBusCount)';
}
