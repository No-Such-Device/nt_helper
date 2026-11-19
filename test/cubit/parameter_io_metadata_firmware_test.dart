import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DistingCubit cubit;
  late _Manager manager;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final database = _Database();
    when(() => database.metadataDao).thenReturn(_Metadata());
    manager = _Manager();
    cubit = DistingCubit(database, midiCommand: MockMidiCommand());
    when(() => manager.requestNumberOfParameters(0)).thenAnswer(
      (_) async => NumParameters(algorithmIndex: 0, numParameters: 1),
    );
    when(() => manager.requestAlgorithmGuid(0)).thenAnswer(
      (_) async => Algorithm(algorithmIndex: 0, guid: 'TEST', name: 'Mixer'),
    );
    when(() => manager.requestParameterPages(0)).thenAnswer(
      (_) async => ParameterPages(
        algorithmIndex: 0,
        pages: [
          ParameterPage(name: 'Main', parameters: [0]),
        ],
      ),
    );
    when(() => manager.requestAllParameterValues(0)).thenAnswer(
      (_) async => AllParameterValues(
        algorithmIndex: 0,
        values: [
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
        ],
      ),
    );
    when(() => manager.requestParameterInfo(0, 0)).thenAnswer(
      (_) async => ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 1,
        defaultValue: 0,
        unit: 1,
        name: 'Output mode',
        powerOfTen: 0,
      ),
    );
    when(() => manager.requestParameterEnumStrings(0, 0)).thenAnswer(
      (_) async => ParameterEnumStrings(
        algorithmIndex: 0,
        parameterNumber: 0,
        values: ['Add', 'Replace'],
      ),
    );
    when(() => manager.requestMappings(0, 0))
        .thenAnswer((_) async => Mapping.filler());
  });
  tearDown(() => cubit.close());

  void setFirmware(String version) {
    cubit.emit(
      DistingState.synchronized(
        disting: manager,
        distingVersion: version,
        firmwareVersion: FirmwareVersion(version),
        presetName: 'Fixture',
        algorithms: [],
        slots: [],
        unitStrings: [],
      ),
    );
  }

  // Decoder-only tests cannot catch the hydration invariant rejecting legacy
  // Add/Replace enums: firmware before 1.12 does not supply the required flags.
  for (final version in ['1.11.0', '', 'unknown', 'custom 1.12.0']) {
    test(
      'hydrates unflagged output enums on older or unknown firmware "$version"',
      () async {
        setFirmware(version);
        final slot = await cubit.fetchSlot(manager, 0);
        expect(slot.values.single.value, 1);
        expect(slot.enums.single.values, ['Add', 'Replace']);
        expect(slot.outputModeMap, isEmpty);
        verifyNever(() => manager.requestOutputModeUsage(any(), any()));
      },
    );
  }

  for (final version in ['1.12.0', '1.12.0-beta.2', '1.19.0']) {
    test(
      'retains missing output metadata safety on supported firmware $version',
      () async {
        setFirmware(version);
        await expectLater(
          cubit.fetchSlot(manager, 0),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Output mode parameters missing ioFlags; fallback is not permitted.',
            ),
          ),
        );
        verifyNever(() => manager.requestOutputModeUsage(any(), any()));
      },
    );
  }

  test('hydrates flagged output relationships on firmware 1.12', () async {
    setFirmware('1.12.0');
    when(() => manager.requestParameterInfo(0, 0)).thenAnswer(
      (_) async => ParameterInfo(
        algorithmIndex: 0,
        parameterNumber: 0,
        min: 0,
        max: 1,
        defaultValue: 0,
        unit: 1,
        name: 'Output mode',
        powerOfTen: 0,
        ioFlags: 8,
      ),
    );
    when(() => manager.requestOutputModeUsage(0, 0)).thenAnswer(
      (_) async => OutputModeUsage(
        algorithmIndex: 0,
        parameterNumber: 0,
        affectedParameterNumbers: [0],
      ),
    );
    when(() => manager.requestParameterValue(0, 0)).thenAnswer(
      (_) async =>
          ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
    );
    final slot = await cubit.fetchSlot(manager, 0);
    expect(slot.outputModeMap, {
      0: [0],
    });
    expect(slot.values.single.value, 0);
    verify(() => manager.requestOutputModeUsage(0, 0)).called(1);
  });
}
