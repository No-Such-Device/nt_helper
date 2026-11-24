import 'package:flutter/foundation.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/module_settings.dart';

import 'models/connection.dart';
import 'models/port.dart';

enum Ntx8cvRoutingMode { cv, audio32, audio16 }

/// One NTX on its default first channel group. NT Settings do not report the
/// expander's independent Channel Group or its local audio-output enables.
@immutable
class Ntx8cvRouting {
  const Ntx8cvRouting({
    required this.mode,
    required this.channelEnables,
    this.available = true,
  });

  static const nodeId = 'ntx8cv_outputs';
  final Ntx8cvRoutingMode? mode;
  final BigInt? channelEnables;
  final bool available;

  String get scopeLabel => 'NTX-8CV · channels 1–8';
  String get description => available
      ? 'Configured first channel group; NTX attachment and local output enables are not detected.'
      : 'NTX configuration unavailable. Refresh NT Settings.';

  bool enabled(int jack) =>
      available &&
      mode != null &&
      (mode != Ntx8cvRoutingMode.cv ||
          channelEnables != null &&
              (channelEnables! & (BigInt.one << (jack - 1))) != BigInt.zero);

  List<Port> ports(DeviceIoProfile profile) => List.generate(
    8,
    (i) => Port(
      id: 'ntx8cv_out_${i + 1}',
      name: '${i + 1}',
      type: PortType.audio,
      direction: PortDirection.input,
      role: PortRole.expanderOutputBus,
      hardwareIndex: i + 1,
      nodeId: nodeId,
      busValue: profile.busForLocalNumber(DeviceBusGroup.aux, i + 1),
      isActive: enabled(i + 1),
      description:
          'NTX-8CV ${i + 1}: ${profile.labelForBus(profile.auxStart + i)}${!available
              ? ', unavailable'
              : !enabled(i + 1)
              ? ', disabled'
              : mode == Ntx8cvRoutingMode.cv
              ? ', enabled'
              : ', transmitted; local audio enable unknown'}',
    ),
  );

  Set<int> protectedBuses(DeviceIoProfile profile) => {
    for (var i = 0; i < 8; i++)
      if (!available || enabled(i + 1)) profile.auxStart + i,
  };

  Map<String, Object?> toJson(DeviceIoProfile profile) => {
    'scope': 'first_channel_group',
    'available': available,
    'mode': mode?.name,
    'hardware_presence': 'not_detected',
    'outputs': [
      for (final port in ports(profile))
        {
          'jack': port.hardwareIndex,
          'bus': port.busValue,
          'bus_name': profile.labelForBus(port.busValue!),
          'enabled': port.isActive,
        },
    ],
  };

  static Ntx8cvRouting? fromSettings(
    ModuleSettingsState state,
    DeviceIoProfile profile,
  ) {
    if (state.unavailableReason != null ||
        profile != DeviceIoProfile.distingExtended) {
      return null;
    }
    final groups = state.tree?.groups;
    if (groups == null) return null;
    ModuleSettingsGroup? child(ModuleSettingsGroup? parent, String name) {
      if (parent == null) return null;
      final matches = parent.children
          .where((c) => c.isGroup)
          .map((c) => groups[c.id])
          .whereType<ModuleSettingsGroup>()
          .where((g) => g.name == name)
          .toList();
      return matches.length == 1 ? matches.single : null;
    }

    final group = child(
      child(child(groups[0], 'Settings'), 'Engine'),
      'NTX-8CV',
    );
    if (group == null) return null;
    ModuleSettingEdit? setting(String name) {
      final matches = group.children
          .where((c) => !c.isGroup)
          .map((c) => state.settings[c.id])
          .whereType<ModuleSettingEdit>()
          .where((e) => e.info.name == name)
          .toList();
      return matches.length == 1 ? matches.single : null;
    }

    final mode = setting('Mode');
    final enables = setting('Channel enables');
    if (mode == null ||
        enables == null ||
        !mode.info.isNumeric ||
        mode.info.unit != 1 ||
        enables.info.type != 6 ||
        enables.observed.value is! BigInt ||
        !listEquals(mode.info.enums, const [
          'CV (8x8)',
          'Audio 32 bit (1x8)',
          'Audio 16 bit (2x8)',
        ]) ||
        mode.info.min != 0 ||
        mode.info.max != 2) {
      return null;
    }
    final value = mode.observed.value;
    final mask = enables.observed.value as BigInt;
    final valid =
        value is int &&
        value >= 0 &&
        value <= 2 &&
        !mask.isNegative &&
        mask.bitLength <= 64;
    return Ntx8cvRouting(
      mode: valid ? Ntx8cvRoutingMode.values[value] : null,
      channelEnables: valid ? mask : null,
      available:
          valid &&
          !state.busy &&
          !state.actionUncertain &&
          !mode.needsRefresh &&
          !enables.needsRefresh,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Ntx8cvRouting &&
      other.mode == mode &&
      other.channelEnables == channelEnables &&
      other.available == available;
  @override
  int get hashCode => Object.hash(mode, channelEnables, available);
}

/// Read-only physical taps supplement ordinary AUX and CV connections.
List<Connection> ntx8cvConnections({
  required List<Port> ports,
  required Iterable<({String id, int index, List<Port> outputs})> algorithms,
}) => [
  for (final algorithm in algorithms)
    for (final output in algorithm.outputs)
      for (final sink in ports)
        if (sink.isActive &&
            output.isActive &&
            output.busValue == sink.busValue &&
            output.busParam != 'es5_direct')
          Connection(
            id: 'ntx8cv_${output.id}_to_${sink.id}',
            sourcePortId: output.id,
            destinationPortId: sink.id,
            connectionType: ConnectionType.hardwareOutput,
            busNumber: sink.busValue,
            algorithmId: algorithm.id,
            algorithmIndex: algorithm.index,
            parameterNumber: output.parameterNumber,
            signalType: SignalType.audio,
            isOutput: true,
            outputMode: output.outputMode,
          ),
];
