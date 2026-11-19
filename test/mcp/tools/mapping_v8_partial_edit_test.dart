import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/services/disting_controller.dart';

import '../../test_helpers/mapping_v8.dart';

class _Controller extends Mock implements DistingController {}

class _Cubit extends Mock implements DistingCubit {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  setUpAll(() => registerFallbackValue(PackedMappingData.filler()));
  for (final type in [null, 'pitch_bend', 'channel_pressure']) {
    test(
      'MCP partial mapping edit type=$type preserves omitted v8 options',
      () async {
        final controller = _Controller();
        final cubit = _Cubit();
        final original = PackedMappingData.fromBytes(8, mappingV8Fixture());
        final algorithm = Algorithm(
          algorithmIndex: 0,
          guid: 'test',
          name: 'test',
        );
        final parameter = ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 5,
          min: 0,
          max: 100,
          defaultValue: 0,
          unit: 0,
          name: 'Level',
          powerOfTen: 0,
        );
        final mapping = Mapping(
          algorithmIndex: 0,
          parameterNumber: 5,
          packedMappingData: original,
        );
        when(() => cubit.state).thenReturn(
          DistingState.synchronized(
            disting: _Manager(),
            distingVersion: '1.20beta',
            firmwareVersion: FirmwareVersion('1.20beta'),
            presetName: 'Test',
            algorithms: [],
            slots: [],
            unitStrings: [],
          ),
        );
        when(() => controller.isSynchronized).thenReturn(true);
        when(() => controller.getAlgorithmInSlot(0))
            .thenAnswer((_) async => algorithm);
        when(() => controller.getParametersForSlot(0))
            .thenAnswer((_) async => [parameter]);
        when(() => controller.getValuesForSlot(0)).thenAnswer(
          (_) async => [
            ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 0),
          ],
        );
        when(() => controller.getMappingsForSlot(0))
            .thenAnswer((_) async => [mapping]);
        when(() => controller.getSlotName(0)).thenAnswer((_) async => null);
        when(() => controller.getParameterMapping(0, 5))
            .thenAnswer((_) async => mapping);
        when(() => controller.getParameterValue(0, 5)).thenAnswer(
          (_) async =>
              ParameterValue(algorithmIndex: 0, parameterNumber: 5, value: 0),
        );
        when(() => controller.flushParameterQueue()).thenAnswer((_) async {});
        when(() => controller.savePreset()).thenAnswer((_) async {});
        PackedMappingData? saved;
        when(() => controller.saveMapping(0, 5, any())).thenAnswer((inv) async {
          saved = inv.positionalArguments[2] as PackedMappingData;
        });
        final response = jsonDecode(
          await DistingTools(controller, cubit).editSlot({
            'slot_index': 0,
            'data': {
              'parameters': [
                {
                  'parameter_number': 5,
                  'mapping': {
                    if (type == null) 'cv': {'source': 1},
                    if (type != null)
                      'midi': {'is_midi_enabled': true, 'midi_type': type},
                  },
                },
              ],
            },
          }),
        ) as Map<String, dynamic>;
        expect(response['success'], isTrue, reason: response.toString());
        expect(saved, isNotNull);
        expect(saved!.version, 8);
        expect(saved!.midiViewChange, isFalse);
        expect(saved!.midiIgnoreWhenBypassed, isTrue);
        expect(saved!.i2cIgnoreWhenBypassed, isTrue);
        expect(saved!.cvFlagsExtra, original.cvFlagsExtra);
      },
    );
  }
}
