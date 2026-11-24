import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/core/routing/cv_modulation.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/cv_routing_fixture.dart';
import '../test_helpers/mock_midi_command.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Manager extends Mock implements IDistingMidiManager {}

class _Controller extends Mock implements DistingController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DistingCubit cubit;
  late _Manager manager;
  late DistingStateSynchronized original;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final db = _Database();
    final metadata = _Metadata();
    manager = _Manager();
    when(() => db.metadataDao).thenReturn(metadata);
    cubit = DistingCubit(db, midiCommand: MockMidiCommand());
    original = DistingState.synchronized(
      disting: manager,
      distingVersion: '1.20beta',
      firmwareVersion: FirmwareVersion('1.20beta'),
      presetName: 'CV fixture',
      algorithms: const [],
      slots: [
        cvSlot(0, outputs: [32]),
        cvSlot(1, cvBuses: [32], source: 2),
      ],
      unitStrings: const [],
    ) as DistingStateSynchronized;
    cubit.emit(original);
  });
  tearDown(() => cubit.close());

  test(
    'shared up/down entry points reject before optimistic mutation or MIDI',
    () async {
      await expectLater(cubit.moveAlgorithmUp(1), throwsStateError);
      await expectLater(cubit.moveAlgorithmDown(0), throwsStateError);
      expect(cubit.state, same(original));
      verifyZeroInteractions(manager);
    },
  );

  test(
    'notes insertion composite fails before adding, editing or moving anything',
    () async {
      final controller = _Controller();
      final result = jsonDecode(
        await DistingTools(controller, cubit).setNotes({'text': 'Notes'}),
      ) as Map;
      expect(result['success'], false);
      expect(result['error'].toString(), contains('CV mapping'));
      expect(cubit.state, same(original));
      verifyZeroInteractions(controller);
      verifyZeroInteractions(manager);
    },
  );
  test('shared move guard accepts proven Module inputs and rejects incomplete coverage', () {
    final safe = original.copyWith(
      slots: [
        cvSlot(0),
        cvSlot(1, cvBuses: [1], source: 1),
      ],
    );
    cubit.emit(safe);
    expect(cubit.ensureCvRoutingOrderChangeSafe, returnsNormally);
    cubit.emit(
      safe.copyWith(
        slots: [
          cvSlot(0).copyWith(parameterCountFromDevice: false),
          safe.slots[1],
        ],
      ),
    );
    expect(cubit.ensureCvRoutingOrderChangeSafe, throwsStateError);
    verifyZeroInteractions(manager);
  });
  for (final hiddenMappable in [false, true]) {
    test(
      'coverage follows actual hydration: nonmappable filler, hidden mappable=$hiddenMappable',
      () async {
        final template = cvSlot(0, cvBuses: [0]);
        final parameters = [
          template.parameters.single,
          ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: 1,
            min: 0,
            max: 1,
            defaultValue: 0,
            unit: -1,
            name: 'Read only',
            powerOfTen: 0,
          ),
          if (hiddenMappable)
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 2,
              min: 0,
              max: 127,
              defaultValue: 0,
              unit: 0,
              name: 'Hidden',
              powerOfTen: 0,
            ),
        ];
        when(() => manager.requestNumberOfParameters(0)).thenAnswer(
          (_) async => NumParameters(
            algorithmIndex: 0,
            numParameters: parameters.length,
          ),
        );
        when(() => manager.requestAlgorithmGuid(0))
            .thenAnswer((_) async => template.algorithm);
        when(() => manager.requestParameterPages(0)).thenAnswer(
          (_) async => ParameterPages(
            algorithmIndex: 0,
            pages: [
              ParameterPage(name: 'Main', parameters: [0, 1]),
            ],
          ),
        );
        when(() => manager.requestAllParameterValues(0)).thenAnswer(
          (_) async => AllParameterValues(
            algorithmIndex: 0,
            values: [
              for (final p in parameters)
                ParameterValue(
                  algorithmIndex: 0,
                  parameterNumber: p.parameterNumber,
                  value: 0,
                ),
            ],
          ),
        );
        when(() => manager.requestParameterInfo(0, any())).thenAnswer(
          (call) async => parameters[call.positionalArguments[1] as int],
        );
        when(() => manager.requestMappings(0, 0))
            .thenAnswer((_) async => template.mappings.single);
        final slot = await cubit.fetchSlot(manager, 0);
        expect(slot.parameterCountFromDevice, isTrue);
        expect(slot.parameters[1].unit, -1);
        expect(slot.mappings[1].packedMappingData.version, -1);
        expect(hasCompleteMappingCoverage([slot]), !hiddenMappable);
        verify(() => manager.requestMappings(0, 0)).called(1);
        verifyNever(() => manager.requestMappings(0, 1));
        if (hiddenMappable) verifyNever(() => manager.requestMappings(0, 2));
      },
    );
  }
}
