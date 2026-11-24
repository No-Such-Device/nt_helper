import 'dart:typed_data';

import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

Slot cvSlot(
  int index, {
  List<int> outputs = const [],
  List<String> outputNames = const [],
  List<OutputMode> modes = const [],
  List<int> inputs = const [],
  List<int> cvBuses = const [],
  List<String> cvNames = const [],
  int source = 0,
  String? guid,
  String? algorithmName,
  String pageName = 'Main',
}) {
  final parameters = <ParameterInfo>[];
  final values = <ParameterValue>[];
  final mappings = <Mapping>[];
  final outputModeMap = <int, List<int>>{};
  void add(String name, int value, int flags, {int cvBus = 0}) {
    final p = parameters.length;
    parameters.add(
      ParameterInfo(
        algorithmIndex: index,
        parameterNumber: p,
        min: 0,
        max: flags == 0 ? 127 : 64,
        defaultValue: 0,
        unit: flags == 0 ? 0 : 1,
        name: name,
        powerOfTen: 0,
        ioFlags: flags,
      ),
    );
    values.add(
      ParameterValue(algorithmIndex: index, parameterNumber: p, value: value),
    );
    mappings.add(
      Mapping(
        algorithmIndex: index,
        parameterNumber: p,
        packedMappingData: PackedMappingData.fromBytes(
          8,
          Uint8List(25),
        ).copyWith(cvInput: cvBus, source: source, delta: 100),
      ),
    );
  }

  for (var i = 0; i < outputs.length; i++) {
    final outputNumber = parameters.length;
    add(
      i < outputNames.length ? outputNames[i] : 'Step output ${i + 1}',
      outputs[i],
      2,
    );
    if (i < modes.length) {
      outputModeMap[parameters.length] = [outputNumber];
      add(
        'Step output ${i + 1} mode',
        modes[i] == OutputMode.replace ? 1 : 0,
        8,
      );
    }
  }
  for (var i = 0; i < inputs.length; i++) {
    add('Input ${i + 1}', inputs[i], 1);
  }
  for (var i = 0; i < cvBuses.length; i++) {
    add(
      i < cvNames.length ? cvNames[i] : 'CC ${i + 1}',
      64,
      0,
      cvBus: cvBuses[i],
    );
  }
  return Slot(
    algorithm: Algorithm(
      algorithmIndex: index,
      guid: guid ?? 's$index',
      name:
          algorithmName ??
          (outputs.isEmpty ? 'MIDI CC Generator $index' : 'Step $index'),
    ),
    routing: RoutingInfo(algorithmIndex: index, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(
      algorithmIndex: index,
      pages: [
        ParameterPage(
          name: pageName,
          parameters: List.generate(parameters.length, (i) => i),
        ),
      ],
    ),
    parameters: parameters,
    values: values,
    mappings: mappings,
    enums: const [],
    valueStrings: const [],
    outputModeMap: outputModeMap,
    parameterCountFromDevice: true,
  );
}

List<CvModulation> cvProjection(
  List<Slot> slots, {
  DeviceIoProfile profile = DeviceIoProfile.distingExtended,
}) {
  final ids = routingAlgorithmIds(slots);
  return projectCvModulations(
    slots: slots,
    algorithmIds: ids,
    profile: profile,
    routings: [
      for (var i = 0; i < slots.length; i++)
        AlgorithmRouting.fromSlot(
          slots[i],
          algorithmUuid: ids[i],
          deviceIoProfile: profile,
        ),
    ],
  );
}
