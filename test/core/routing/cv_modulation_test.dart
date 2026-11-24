import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/device_io_profile.dart';

import '../../test_helpers/cv_routing_fixture.dart';

void main() {
  test('two CC targets use Aux 12/13, not physical input numbers', () {
    final result = cvProjection([
      cvSlot(0, outputs: [32, 33]),
      cvSlot(1, cvBuses: [32, 33]),
    ]);
    expect(result.map((m) => m.busLabel), ['Aux 12', 'Aux 13']);
    expect(result.map((m) => m.parameterNumber), [0, 1]);
    expect(result.map((m) => m.parameterName), ['Main: CC 1', 'Main: CC 2']);
    expect(result.map((m) => m.id).toSet(), hasLength(2));
    expect(result.first.contributorPortIds, ['algo_s0_1_Step_output_1_0']);
    expect(result.last.contributorPortIds, ['algo_s0_1_Step_output_2_1']);
  });

  test('real source slot survives no-IO gaps and duplicate instances', () {
    final result = cvProjection([
      cvSlot(0, guid: 'same'),
      cvSlot(1, outputs: [32], guid: 'same'),
      cvSlot(2),
      cvSlot(3, cvBuses: [32], source: 3),
    ]).single;
    expect(result.contributorPortIds, ['algo_same_2_Step_output_1_0']);
    expect(result.snapshot, contains('Slot 2 outputs'));
    expect(result.destinationSlot, 3);
  });

  test('own inputs and module inputs differ after a Replace writer', () {
    final slots = [
      cvSlot(0, outputs: [1], modes: [OutputMode.replace]),
      cvSlot(1, cvBuses: [1]),
      cvSlot(2, cvBuses: [1], source: 1),
    ];
    final result = cvProjection(slots);
    expect(result[0].contributorPortIds, ['algo_s0_1_Step_output_1_0']);
    expect(result[1].contributorPortIds, ['hw_in_1']);
    expect(result[1].snapshot, contains('original physical'));
  });

  test('Add/Replace contributors and fanout are not reduced to one source', () {
    final result = cvProjection([
      cvSlot(0, outputs: [32]),
      cvSlot(1, outputs: [32], modes: [OutputMode.replace]),
      cvSlot(2, outputs: [32]),
      cvSlot(3, cvBuses: [32, 32]),
    ]);
    for (final relation in result) {
      expect(relation.contributorPortIds, [
        'algo_s1_1_Step_output_1_0',
        'algo_s2_1_Step_output_1_0',
      ]);
    }
    expect(result.map((m) => m.id).toSet(), hasLength(2));
  });

  test('self output snapshot is not an invented ordering dependency', () {
    final result = cvProjection([
      cvSlot(0, outputs: [32], cvBuses: [32], source: 2),
    ]).single;
    expect(result.contributorPortIds, ['algo_s0_1_Step_output_1_0']);
    expect(result.parameterNumber, 1);
  });

  test('missing/later/invalid source and nonphysical module bus remain inspectable', () {
    for (final source in [-1, 1, 3, 99]) {
      final relation = cvProjection([
        cvSlot(0, cvBuses: [32], source: source),
        cvSlot(1, outputs: [32]),
      ]).single;
      expect(relation.contributorPortIds, isEmpty);
      expect(
        relation.caveats,
        contains('Bus/snapshot only; contributor unresolved'),
      );
    }
  });

  test(
    'cvInput zero is not a relation even when source or MIDI is enabled',
    () {
      expect(
        cvProjection([
          cvSlot(0, cvBuses: [0], source: 2),
        ]),
        isEmpty,
      );
    },
  );

  test('legacy mapping ignores source and uses own input snapshot', () {
    final slot = cvSlot(1, cvBuses: [32], source: 99);
    final mapping = slot.mappings.single;
    final result = cvProjection([
      cvSlot(0, outputs: [32]),
      slot.copyWith(
        mappings: [
          Mapping(
            algorithmIndex: 1,
            parameterNumber: 0,
            packedMappingData: mapping.packedMappingData.copyWith(version: 3),
          ),
        ],
      ),
    ]).single;
    expect(result.source, 0);
    expect(result.contributorPortIds, ['algo_s0_1_Step_output_1_0']);
  });

  test(
    'profile owns bus 64, custom boundaries and invalid-bus diagnostics',
    () {
      final custom = DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!;
      expect(
        cvProjection([
          cvSlot(0, cvBuses: [8]),
        ], profile: custom).single.busLabel,
        'Aux 1',
      );
      expect(
        cvProjection([
          cvSlot(0, cvBuses: [64]),
        ]).single.busLabel,
        'Aux 44',
      );
      final invalid = cvProjection([
        cvSlot(0, cvBuses: [64]),
      ], profile: DeviceIoProfile.distingLegacy).single;
      expect(invalid.caveats, contains('Bus outside this device profile'));
      expect(invalid.contributorPortIds, isEmpty);
    },
  );

  test('filler storage positions retain targets; contradictory IDs fail attribution', () {
    final slot = cvSlot(1, cvBuses: [32]);
    final data = slot.mappings.single.packedMappingData;
    for (final number in [-1, 12]) {
      final result = cvProjection([
        cvSlot(0, outputs: [32]),
        slot.copyWith(
          mappings: [
            Mapping(
              algorithmIndex: number == -1 ? -1 : 1,
              parameterNumber: number,
              packedMappingData: data,
            ),
          ],
        ),
      ]).single;
      expect(result.parameterNumber, 0);
      expect(
        result.contributorPortIds,
        number == -1 ? ['algo_s0_1_Step_output_1_0'] : isEmpty,
      );
    }
  });

  test('zero depth/disabled is configured topology, not active telemetry', () {
    final slot = cvSlot(0, cvBuses: [1]);
    final relation = cvProjection([
      slot.copyWith(
        values: [
          ParameterValue(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 64,
            isDisabled: true,
          ),
        ],
        mappings: [
          Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: slot.mappings.single.packedMappingData.copyWith(
              delta: 0,
            ),
          ),
        ],
      ),
    ]).single;
    expect(relation.caveats, containsAll(['Zero depth', 'Parameter disabled']));
    expect(relation.description, contains('not voltage telemetry'));
  });

  test(
    'multiple same-slot writes are not assigned a guessed internal order',
    () {
      final result = cvProjection([
        cvSlot(0, outputs: [32, 32]),
        cvSlot(1, cvBuses: [32]),
      ]).single;
      expect(result.contributorPortIds, isEmpty);
      expect(result.caveats, contains('Same-slot write order unknown'));
    },
  );

  test('ordinary signal discovery is unchanged by mappings', () {
    final slots = [
      cvSlot(0, outputs: [32]),
      cvSlot(1, inputs: [32], cvBuses: [32]),
    ];
    final ids = routingAlgorithmIds(slots);
    final routings = [
      for (var i = 0; i < slots.length; i++)
        AlgorithmRouting.fromSlot(
          slots[i],
          algorithmUuid: ids[i],
          deviceIoProfile: DeviceIoProfile.distingExtended,
        ),
    ];
    final before = ConnectionDiscoveryService.discoverConnections(
      routings,
      deviceIoProfile: DeviceIoProfile.distingExtended,
    );
    cvProjection(slots);
    expect(
      ConnectionDiscoveryService.discoverConnections(
        routings,
        deviceIoProfile: DeviceIoProfile.distingExtended,
      ),
      before,
    );
    expect(
      before.where(
        (c) =>
            c.sourcePortId == 'algo_s0_1_Step_output_1_0' &&
            c.destinationPortId == 'algo_s1_1_Input_1_0',
      ),
      hasLength(1),
    );
  });

  test(
    'optimization requires complete cache and respects configured buses',
    () {
      final slot = cvSlot(0, cvBuses: [32]);
      expect(cvMappingBuses([slot]), {32});
      expect(
        hasCompleteMappingCoverage([
          slot.copyWith(parameterCountFromDevice: false),
        ]),
        isFalse,
      );
      expect(cvRoutingOptimizationBlockReason([slot]), contains('CV mapping'));
      expect(
        cvRoutingOptimizationBlockReason([slot.copyWith(mappings: [])]),
        contains('Refresh'),
      );
      expect(
        cvRoutingOptimizationBlockReason([
          cvSlot(0, cvBuses: [0]),
        ]),
        isNull,
      );
    },
  );
}
