import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reset Outputs never writes output-mode parameters', () async {
    SharedPreferences.setMockInitialValues({});
    final database = _MockAppDatabase();
    final metadataDao = _MockMetadataDao();
    final manager = _MockDistingMidiManager();
    final midiCommand = MockMidiCommand();
    final slot = _slotWithOutputAndMode();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.getAlgorithmInfoCache(
        0,
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => []);
    when(
      () => manager.setParameterValue(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => manager.requestNumAlgorithmsInPreset(),
    ).thenAnswer((_) async => 0);
    when(() => manager.requestNumberOfAlgorithms()).thenAnswer((_) async => 0);
    when(() => manager.requestPresetName()).thenAnswer((_) async => 'Test');
    when(() => manager.dispose()).thenReturn(null);
    final cubit = DistingCubit(database, midiCommand: midiCommand);
    cubit.emit(
      DistingState.synchronized(
        disting: manager,
        distingVersion: '1.20',
        firmwareVersion: FirmwareVersion('1.20'),
        deviceIoProfile: DeviceIoProfile.tryCreate(
          inputBusCount: 4,
          outputBusCount: 3,
          auxBusCount: 5,
        )!,
        presetName: 'Test',
        algorithms: const [],
        slots: [slot],
        unitStrings: const [],
      ),
    );

    await cubit.resetOutputs(slot, 0);

    verify(() => manager.setParameterValue(0, 0, 0)).called(1);
    verifyNever(() => manager.setParameterValue(0, 1, any()));

    await Future<void>.delayed(const Duration(milliseconds: 75));
    await cubit.close();
  });
}

Slot _slotWithOutputAndMode() => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
  pages: ParameterPages(algorithmIndex: 0, pages: const []),
  parameters: [
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 0,
      min: 0,
      max: 12,
      defaultValue: 5,
      unit: 1,
      name: 'Output A',
      powerOfTen: 0,
      ioFlags: 2,
    ),
    ParameterInfo(
      algorithmIndex: 0,
      parameterNumber: 1,
      min: 0,
      max: 1,
      defaultValue: 1,
      unit: 1,
      name: 'Output A mode',
      powerOfTen: 0,
      ioFlags: 8,
    ),
  ],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);
