import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/mock_disting_midi_manager.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';

import '../test_helpers/mapping_v8.dart' show mappingV8Fixture;

void main() {
  test(
    'performance reassignment retains v8 options in demo mapping state',
    () async {
      final manager = MockDistingMidiManager();
      addTearDown(manager.dispose);
      final mapping = PackedMappingData.fromBytes(8, mappingV8Fixture());
      await manager.requestSetMapping(0, 0, mapping);
      await manager.setPerformancePageMapping(0, 0, 4);
      final actual = (await manager.requestMappings(0, 0))!.packedMappingData;
      expect(actual, mapping.copyWith(perfPageIndex: 4));
      expect(actual.toBytes(), mappingV8Fixture());
    },
  );

  test('requestSetMapping updates demo readback without replacing performance assignment', () async {
    final manager = MockDistingMidiManager();
    addTearDown(manager.dispose);

    await manager.setPerformancePageMapping(0, 0, 11);
    final before = await manager.requestMappings(0, 0);
    final desired = before!.packedMappingData.copyWith(
      source: 2,
      cvInput: 3,
      isUnipolar: true,
      volts: 5,
      delta: 12,
      midiChannel: 4,
      midiCC: 74,
      isMidiEnabled: true,
      midiMin: -100,
      midiMax: 100,
      i2cCC: 201,
      isI2cEnabled: true,
      i2cMin: -50,
      i2cMax: 50,
      perfPageIndex: 27,
      version: 7,
    );

    await manager.requestSetMapping(0, 0, desired);

    final actual = await manager.requestMappings(0, 0);
    expect(actual, isNotNull);
    expect(actual!.algorithmIndex, 0);
    expect(actual.parameterNumber, 0);
    expect(actual.packedMappingData, desired.copyWith(perfPageIndex: 11));
  });
}
