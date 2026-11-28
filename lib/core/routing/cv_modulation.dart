import 'package:flutter/foundation.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/device_io_profile.dart';

import 'algorithm_routing.dart';
import 'models/port.dart';

@immutable
class CvModulationContributor {
  final String portId;
  final int? slotIndex;
  final String algorithmName;
  final String portName;
  final bool inferred;

  const CvModulationContributor({
    required this.portId,
    required this.slotIndex,
    required this.algorithmName,
    required this.portName,
    required this.inferred,
  });

  String get description =>
      '${inferred ? 'Inferred producer' : 'Producer'}: '
      '${slotIndex == null ? algorithmName : 'Slot ${slotIndex! + 1}: $algorithmName'} — $portName';

  Map<String, dynamic> toJson() => {
    'port_id': portId,
    'slot_index': slotIndex,
    'algorithm_name': algorithmName,
    'port_name': portName,
    'inferred': inferred,
  };

  @override
  bool operator ==(Object other) =>
      other is CvModulationContributor &&
      portId == other.portId &&
      slotIndex == other.slotIndex &&
      algorithmName == other.algorithmName &&
      portName == other.portName &&
      inferred == other.inferred;

  @override
  int get hashCode =>
      Object.hash(portId, slotIndex, algorithmName, portName, inferred);
}

/// A configured parameter modulation, not an editable signal-routing port.
@immutable
class CvModulation {
  final String id;
  final String destinationAlgorithmId;
  final int destinationSlot;
  final int parameterNumber;
  final String parameterName;
  final int bus;
  final String busLabel;
  final int source;
  final String snapshot;
  final List<CvModulationContributor> contributors;
  List<String> get contributorPortIds =>
      List.unmodifiable(contributors.map((c) => c.portId));
  final List<String> caveats;

  CvModulation({
    required this.destinationAlgorithmId,
    required this.destinationSlot,
    required this.parameterNumber,
    required this.parameterName,
    required this.bus,
    required this.busLabel,
    required this.source,
    required this.snapshot,
    required Iterable<CvModulationContributor> contributors,
    required Iterable<String> caveats,
  }) : id = 'cv_${destinationAlgorithmId}_${parameterNumber}_${bus}_$source',
       contributors = List.unmodifiable(contributors),
       caveats = List.unmodifiable(caveats);

  String get label => 'CV → $parameterName';
  bool get usesOwnInputSnapshot => source == 0;
  bool get usesModuleInputSnapshot => source == 1;
  int? get sourceSlotIndex => source >= 2 ? source - 2 : null;
  String get description => [
    '$busLabel → Slot ${destinationSlot + 1}: $parameterName (parameter $parameterNumber)',
    snapshot,
    ...contributors.map((c) => c.description),
    'Configured modulation; cached state, not voltage telemetry',
    ...caveats,
  ].join('\n');

  Map<String, dynamic> toJson() => {
    'parameter_number': parameterNumber,
    'parameter_name': parameterName,
    'bus': bus,
    'bus_label': busLabel,
    'source': source,
    'snapshot': snapshot,
    'contributor_port_ids': contributorPortIds,
    'contributors': contributors.map((c) => c.toJson()).toList(),
    'caveats': caveats,
    'cached': true,
  };

  @override
  bool operator ==(Object other) =>
      other is CvModulation &&
      id == other.id &&
      destinationSlot == other.destinationSlot &&
      parameterName == other.parameterName &&
      busLabel == other.busLabel &&
      snapshot == other.snapshot &&
      listEquals(contributors, other.contributors) &&
      listEquals(caveats, other.caveats);

  @override
  int get hashCode => Object.hash(
    id,
    destinationSlot,
    parameterName,
    busLabel,
    snapshot,
    Object.hashAll(contributors),
    Object.hashAll(caveats),
  );
}

/// The roster is unfiltered: a mapping source names a real preset slot.
List<CvModulation> projectCvModulations({
  required List<Slot> slots,
  required List<AlgorithmRouting> routings,
  required List<String> algorithmIds,
  required DeviceIoProfile profile,
}) {
  assert(
    slots.length == routings.length && slots.length == algorithmIds.length,
  );
  final writes = <({int slot, int bus, String portId, OutputMode mode})>[];
  final producers = <String, CvModulationContributor>{};
  for (var i = 0; i < slots.length; i++) {
    for (final port in routings[i].outputPorts) {
      final bus = port.busValue;
      if (!port.isActive || bus == null || !profile.contains(bus)) continue;
      if (slots[i].values.any(
        (v) => v.parameterNumber == port.parameterNumber && v.isDisabled,
      )) {
        continue;
      }
      writes.add((
        slot: i,
        bus: bus,
        portId: port.id,
        mode: port.outputMode ?? OutputMode.add,
      ));
      producers[port.id] = CvModulationContributor(
        portId: port.id,
        slotIndex: i,
        algorithmName: slots[i].algorithm.name,
        portName: port.name,
        inferred: true,
      );
    }
  }
  final result = <CvModulation>[];
  for (var i = 0; i < slots.length; i++) {
    final slot = slots[i];
    for (var p = 0; p < slot.mappings.length; p++) {
      final mapping = slot.mappings[p];
      final data = mapping.packedMappingData;
      if (data.cvInput <= 0) continue;
      // Live/offline storage is positional. A contradictory explicit identity
      // cannot safely be attributed to either parameter.
      final identityValid =
          (mapping.parameterNumber < 0 || mapping.parameterNumber == p) &&
          (mapping.algorithmIndex < 0 || mapping.algorithmIndex == i) &&
          data.version > 0;
      final metadata = slot.parameters
          .where((v) => v.parameterNumber == p)
          .firstOrNull;
      final page = slot.pages.pages
          .where((v) => v.parameters.contains(p))
          .firstOrNull;
      final channel = page == null
          ? null
          : RegExp(r'^Channel (\d+)$').firstMatch(page.name)?.group(1);
      final rawName = metadata?.name ?? '';
      // The prefix is the channel's name: the page's channel number, or a label
      // the channel was renamed to. The page already names the channel, so that
      // prefix is dropped; a different numeric prefix belongs to the parameter.
      final colonIndex = rawName.indexOf(':');
      final prefix = colonIndex >= 0 ? rawName.substring(0, colonIndex) : '';
      final prefixIsChannel =
          colonIndex >= 0 &&
          (prefix == channel || int.tryParse(prefix) == null);
      final parameterName = prefixIsChannel
          ? rawName.substring(colonIndex + 1).trimLeft()
          : rawName;
      final name = metadata == null || metadata.name.isEmpty
          ? 'Parameter $p'
          : '${page == null || page.name.isEmpty ? '' : '${page.name}: '}$parameterName';
      final source = data.version > 0 && data.version < 4 ? 0 : data.source;
      final sourceSlot = source - 2;
      final validBus = profile.contains(data.cvInput);
      final caveats = <String>[
        if (!identityValid) 'Conflicting mapping parameter identity',
        if (metadata == null) 'Parameter metadata unavailable',
        if (!validBus) 'Bus outside this device profile',
        if (data.delta == 0) 'Zero depth',
        if (slot.values.any((v) => v.parameterNumber == p && v.isDisabled))
          'Parameter disabled',
      ];
      final snapshot = source == 0
          ? 'Own inputs (before Slot ${i + 1})'
          : source == 1
          ? 'Module inputs (original physical inputs)'
          : source >= 2 && sourceSlot < slots.length
          ? 'Slot ${sourceSlot + 1} outputs (${slots[sourceSlot].algorithm.name})'
          : 'Unknown source $source';
      final contributors = <String>{};
      final boundary = source == 0 ? i : sourceSlot + 1;
      if (identityValid &&
          validBus &&
          source == 1 &&
          profile.isInput(data.cvInput)) {
        contributors.add('hw_in_${data.cvInput}');
      } else if (identityValid &&
          validBus &&
          (source == 0 ||
              (source >= 2 &&
                  sourceSlot >= 0 &&
                  sourceSlot < slots.length &&
                  sourceSlot <= i))) {
        final groups =
            <
              int,
              List<({int slot, int bus, String portId, OutputMode mode})>
            >{};
        for (final write in writes.where(
          (w) => w.bus == data.cvInput && w.slot < boundary,
        )) {
          (groups[write.slot] ??= []).add(write);
        }
        var ambiguous = false;
        var hardwareSeed = true;
        for (final group in groups.values) {
          if (group.every((w) => w.mode == OutputMode.add)) {
            contributors.addAll(group.map((w) => w.portId));
          } else if (group.length == 1) {
            contributors
              ..clear()
              ..add(group.single.portId);
            hardwareSeed = false;
            ambiguous = false;
          } else {
            contributors.clear();
            hardwareSeed = false;
            ambiguous = true;
          }
        }
        if (ambiguous) {
          contributors.clear();
          caveats.add('Same-slot write order unknown');
        } else {
          if (profile.isInput(data.cvInput) && hardwareSeed) {
            contributors.add('hw_in_${data.cvInput}');
          }
          if (contributors.isNotEmpty) {
            caveats.add('Contributors inferred from Add/Replace order');
          }
        }
      }
      if (contributors.isEmpty) {
        caveats.add('Bus/snapshot only; contributor unresolved');
      }
      result.add(
        CvModulation(
          destinationAlgorithmId: algorithmIds[i],
          destinationSlot: i,
          parameterNumber: p,
          parameterName: name,
          bus: data.cvInput,
          busLabel: profile.labelForBus(data.cvInput) ?? 'Bus ${data.cvInput}',
          source: source,
          snapshot: snapshot,
          contributors: contributors.map(
            (id) =>
                producers[id] ??
                CvModulationContributor(
                  portId: id,
                  slotIndex: null,
                  algorithmName: 'Module inputs',
                  portName:
                      profile.labelForBus(data.cvInput) ??
                      'Bus ${data.cvInput}',
                  inferred: source != 1,
                ),
          ),
          caveats: caveats,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

Set<int> cvMappingBuses(Iterable<Slot> slots) => {
  for (final slot in slots)
    for (final mapping in slot.mappings)
      if (mapping.packedMappingData.cvInput > 0)
        mapping.packedMappingData.cvInput,
};

bool hasCompleteMappingCoverage(Iterable<Slot> slots) => slots.every((slot) {
  if (!slot.parameterCountFromDevice) return false;
  return slot.parameters.every((p) {
    if (p.parameterNumber < 0 ||
        p.algorithmIndex != slot.algorithm.algorithmIndex) {
      return false;
    }
    if (p.unit == -1) return true;
    if (p.parameterNumber >= slot.mappings.length) return false;
    final mapping = slot.mappings[p.parameterNumber];
    return mapping.packedMappingData.version > 0 &&
        (mapping.parameterNumber < 0 ||
            mapping.parameterNumber == p.parameterNumber) &&
        (mapping.algorithmIndex < 0 ||
            mapping.algorithmIndex == slot.algorithm.algorithmIndex);
  });
});

List<String> routingAlgorithmIds(List<Slot> slots) {
  final counts = <String, int>{};
  return [
    for (final slot in slots)
      'algo_${slot.algorithm.guid}_${counts.update(slot.algorithm.guid, (n) => n + 1, ifAbsent: () => 1)}',
  ];
}

String? cvRoutingOptimizationBlockReason(
  Iterable<Slot> slots, {
  DeviceIoProfile profile = DeviceIoProfile.distingExtended,
}) {
  if (!hasCompleteMappingCoverage(slots)) {
    return 'Refresh all parameter mappings before optimizing routing';
  }
  for (final slot in slots) {
    for (final mapping in slot.mappings) {
      final data = mapping.packedMappingData;
      if (data.cvInput <= 0) continue;
      if (data.version >= 4 &&
          data.source == 1 &&
          profile.isInput(data.cvInput)) {
        continue;
      }
      return 'Routing order changes cannot yet preserve CV mapping snapshots';
    }
  }
  return null;
}
