import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';

import '../../test_helpers/grouped_audio_routing_fixture.dart';

AlgorithmRouting routing(Slot slot, {AlgorithmInfo? info}) =>
    AlgorithmRouting.fromSlot(
      slot,
      deviceIoProfile: DeviceIoProfile.distingExtended,
      algorithmUuid: 'algo_${slot.algorithm.guid}',
      algorithmInfo: info,
    );

void main() {
  for (final (guid, name) in [
    ('ATo6', 'ToTape6'),
    ('ATay', 'TapeDelay'),
    ('gain', 'SDK-style gain'),
  ]) {
    test(
      '$name expands its single audio bus pair from Channels specification',
      () {
        final slot = groupedAudioSlot(guid: guid, name: name);
        final ports = routing(
          slot,
          info: groupedAudioInfo(guid: guid, name: name),
        );
        expect(ports.inputPorts.map((p) => p.busValue), [11, 12]);
        expect(ports.outputPorts.map((p) => p.busValue), [23, 24]);
        expect(ports.inputPorts.first.parameterNumber, 1);
        expect(ports.outputPorts.first.parameterNumber, 2);
        expect(ports.inputPorts.last.parameterNumber, isNull);
        expect(ports.outputPorts.last.parameterNumber, isNull);
        expect(ports.inputPorts.last.busParam, isNull);
        expect(ports.outputPorts.last.busParam, isNull);
        expect(ports.inputPorts.map((p) => p.name), ['Input 1', 'Input 2']);
        expect(ports.outputPorts.map((p) => p.name), ['Output 1', 'Output 2']);
        expect(ports.inputPorts.last.channelNumber, 2);
        expect(ports.outputPorts.last.isMultiChannel, isTrue);
        expect(ports.outputPorts.last.modeParameterNumber, isNull);
        expect(ports.outputPorts.last.outputMode, OutputMode.replace);
        expect(
          ports.outputPorts.last.description,
          contains('Implicit channel 2'),
        );
        expect(
          slot.parameters,
          hasLength(3),
        ); // No synthetic device parameters.
      },
    );
  }

  for (final (base, second, third) in [
    ('Input 9', 'Input 10', 'Input 11'),
    ('Output12', 'Output13', 'Output14'),
    ('Channel 99', 'Channel 100', 'Channel 101'),
    ('Input', 'Input 2', 'Input 3'),
  ]) {
    test('increments the complete numeric suffix of "$base"', () {
      final ports = routing(
        groupedAudioSlot(
          specifications: [3],
          inputName: base,
          outputName: 'Output $base',
        ),
        info: groupedAudioInfo(),
      );
      expect(ports.inputPorts.map((p) => p.name), [base, second, third]);
      expect(ports.outputPorts.map((p) => p.name), [
        'Output $base',
        'Output $second',
        'Output $third',
      ]);
    });
  }

  test('resolves named specification by index, not first integer', () {
    final slot = groupedAudioSlot(specifications: [5, 3]);
    final info = groupedAudioInfo(
      definitions: [
        channelSpecification(name: 'Max delay time'),
        channelSpecification(),
      ],
    );
    final ports = routing(slot, info: info);
    expect(ports.inputPorts.map((p) => p.busValue), [11, 12, 13]);
  }, tags: ['regression']);

  for (final name in ['Channels', 'channel count', ' Width ']) {
    test('accepts the explicit channel-span definition "$name"', () {
      expect(
        routing(
          groupedAudioSlot(),
          info: groupedAudioInfo(
            definitions: [channelSpecification(name: name)],
          ),
        ).inputPorts,
        hasLength(2),
      );
    });
  }

  test('does not expand unrelated CV/control ports', () {
    final ports = routing(
      groupedAudioSlot(controlPorts: true),
      info: groupedAudioInfo(),
    );
    expect(
      ports.inputPorts
          .where((p) => p.type == PortType.audio)
          .map((p) => p.busValue),
      [11, 12],
    );
    expect(
      ports.inputPorts
          .where((p) => p.type == PortType.cv)
          .map((p) => p.busValue),
      [3],
    );
    expect(
      ports.outputPorts
          .where((p) => p.type == PortType.cv)
          .map((p) => p.busValue),
      [27],
    );
  });

  test(
    'explicit stereo ports are not multiplied by a Channels specification',
    () {
      final ports = routing(
        groupedAudioSlot(explicitStereo: true),
        info: groupedAudioInfo(),
      );
      expect(ports.inputPorts.map((p) => p.busValue), [11, 12]);
      expect(ports.outputPorts.map((p) => p.busValue), [23, 24]);
      expect(ports.inputPorts.every((p) => p.parameterNumber != null), isTrue);
    },
  tags: ['regression']);

  test('factory-style numbered routing is not treated as an implicit span', () {
    final base = groupedAudioSlot(guid: 'eqpa', name: 'EQ Parametric');
    final slot = base.copyWith(
      parameters: [
        for (final p in base.parameters)
          ParameterInfo(
            algorithmIndex: p.algorithmIndex,
            parameterNumber: p.parameterNumber,
            name: '1:${p.name}',
            min: p.min,
            max: p.max,
            defaultValue: p.defaultValue,
            unit: p.unit,
            powerOfTen: p.powerOfTen,
            ioFlags: p.ioFlags,
          ),
      ],
    );
    final ports = routing(slot, info: groupedAudioInfo(guid: 'eqpa'));
    expect(ports.inputPorts, hasLength(1));
    expect(ports.outputPorts, hasLength(1));
  });

  test('explicit Width parameter takes precedence, including mono', () {
    final ports = routing(groupedAudioSlot(width: 1), info: groupedAudioInfo());
    expect(ports.inputPorts, hasLength(1));
    expect(ports.outputPorts, hasLength(1));
  });

  test('never guesses a channel count without matching definitions', () {
    final slot = groupedAudioSlot();
    for (final info in <AlgorithmInfo?>[
      null,
      groupedAudioInfo(guid: 'Other'),
      groupedAudioInfo(definitions: []),
      groupedAudioInfo(definitions: [channelSpecification(name: 'Voices')]),
      groupedAudioInfo(
        definitions: [channelSpecification(name: 'Max delay time')],
      ),
      groupedAudioInfo(
        definitions: [
          channelSpecification(),
          channelSpecification(name: 'Width'),
        ],
      ),
    ]) {
      expect(routing(slot, info: info).inputPorts, hasLength(1));
    }
  });

  for (final values in <List<int>>[
    [],
    [0],
    [-1],
    [9],
    [2, 3],
  ]) {
    test('missing/invalid construction values $values do not expand ports', () {
      expect(
        routing(
          groupedAudioSlot(specifications: values),
          info: groupedAudioInfo(),
        ).inputPorts,
        hasLength(1),
      );
    });
  }

  test('None and bus-range boundaries never produce invented buses', () {
    final none = routing(
      groupedAudioSlot(input: 0, output: 0),
      info: groupedAudioInfo(),
    );
    expect(none.inputPorts.map((p) => p.busValue), [0]);
    expect(none.outputPorts.map((p) => p.busValue), [0]);
    final edge = routing(
      groupedAudioSlot(input: 64, output: 63, specifications: [4]),
      info: groupedAudioInfo(),
    );
    expect(edge.inputPorts.map((p) => p.busValue), [64]);
    expect(edge.outputPorts.map((p) => p.busValue), [63, 64]);
  });

  test(
    'right-channel connections are discovered across the Airwindows chain',
    () {
      final tape = routing(groupedAudioSlot(), info: groupedAudioInfo());
      final delay = routing(
        groupedAudioSlot(
          guid: 'ATay',
          name: 'TapeDelay',
          slotIndex: 1,
          input: 23,
          output: 25,
        ),
        info: groupedAudioInfo(guid: 'ATay', name: 'TapeDelay'),
      );
      final reverb = routing(
        groupedAudioSlot(
          guid: 'AGac',
          name: 'Galactic',
          slotIndex: 2,
          specifications: [],
          input: 25,
          output: 21,
          explicitStereo: true,
        ),
      );
      final connections = ConnectionDiscoveryService.discoverConnections([
        tape,
        delay,
        reverb,
      ], deviceIoProfile: DeviceIoProfile.distingExtended);
      expect(
        connections.any(
          (c) =>
              c.sourcePortId == tape.outputPorts[1].id &&
              c.destinationPortId == delay.inputPorts[1].id,
        ),
        isTrue,
      );
      expect(
        connections.any(
          (c) =>
              c.sourcePortId == delay.outputPorts[1].id &&
              c.destinationPortId == reverb.inputPorts[1].id,
        ),
        isTrue,
      );
    },
  );
}
