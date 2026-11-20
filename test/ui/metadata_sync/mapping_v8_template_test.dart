import '../../test_helpers/mapping_v8.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockPresetsDao extends Mock implements PresetsDao {}

class FakeAlgorithmInfo extends Fake implements AlgorithmInfo {}

class FakePackedMappingData extends Fake implements PackedMappingData {}

class FakeFullPresetDetails extends Fake implements FullPresetDetails {}

FullAlgorithmDetails _fullAlgorithmDetails(String guid, String name) {
  return FullAlgorithmDetails(
    algorithm: AlgorithmEntry(guid: guid, name: name, numSpecifications: 0),
    specifications: [],
    parameters: [],
    parameterPages: [],
    enums: {},
  );
}

void _stubRefreshableDevice(
  MockDistingMidiManager manager,
  List<Algorithm> deviceAlgorithms, {
  String presetName = 'Device Preset',
}) {
  when(() => manager.requestNumAlgorithmsInPreset())
      .thenAnswer((_) async => deviceAlgorithms.length);
  when(() => manager.requestPresetName()).thenAnswer((_) async => presetName);
  when(() => manager.requestParameterPages(any())).thenAnswer((invocation) {
    final index = invocation.positionalArguments[0] as int;
    return Future.value(ParameterPages(algorithmIndex: index, pages: []));
  });
  when(() => manager.requestNumberOfParameters(any())).thenAnswer((invocation) {
    final index = invocation.positionalArguments[0] as int;
    return Future.value(NumParameters(algorithmIndex: index, numParameters: 0));
  });
  when(() => manager.requestAlgorithmGuid(any())).thenAnswer((invocation) {
    final index = invocation.positionalArguments[0] as int;
    return Future.value(deviceAlgorithms[index]);
  });
  when(() => manager.requestAllParameterValues(any())).thenAnswer((invocation) {
    final index = invocation.positionalArguments[0] as int;
    return Future.value(AllParameterValues(algorithmIndex: index, values: []));
  });
}

DistingStateSynchronized _synchronizedState(
  IDistingMidiManager manager, {
  String firmwareVersion = '1.10.0',
  String presetName = 'Device Preset',
  List<Slot> slots = const [],
}) {
  return DistingStateSynchronized(
    disting: manager,
    distingVersion: firmwareVersion,
    firmwareVersion: FirmwareVersion(firmwareVersion),
    presetName: presetName,
    algorithms: const [],
    slots: slots,
    unitStrings: const [],
    offline: false,
  );
}

FullPresetDetails _template({required List<FullPresetSlot> slots}) =>
    FullPresetDetails(
      preset: PresetEntry(
        id: 1,
        name: 'V8 template',
        lastModified: DateTime(2026),
        isTemplate: true,
      ),
      slots: slots,
    );
void main() {
  late MockDistingMidiManager mockManager;
  late MockAppDatabase mockDatabase;
  late MockMetadataDao mockMetadataDao;
  late MockPresetsDao mockPresetsDao;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(FakeAlgorithmInfo());
    registerFallbackValue(FakePackedMappingData());
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockManager = MockDistingMidiManager();
    mockDatabase = MockAppDatabase();
    mockMetadataDao = MockMetadataDao();
    mockPresetsDao = MockPresetsDao();
    when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
    when(() => mockDatabase.presetsDao).thenReturn(mockPresetsDao);
    when(
      () => mockMetadataDao.getAlgorithmInfoCache(
        any(),
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => []);
    when(() => mockManager.requestNumberOfAlgorithms())
        .thenAnswer((_) async => 0);
    when(() => mockManager.requestPerfPageItem(any()))
        .thenAnswer((_) async => null);
  });
  test(
    'rejects v8 mappings on old firmware before any device mutations',
    () async {
      final deviceAlgorithms = <Algorithm>[];
      _stubRefreshableDevice(mockManager, deviceAlgorithms);
      when(() => mockManager.requestAddAlgorithm(any(), any()))
          .thenAnswer((invocation) async {
            final info = invocation.positionalArguments[0] as AlgorithmInfo;
            deviceAlgorithms.add(
              Algorithm(
                algorithmIndex: deviceAlgorithms.length,
                guid: info.guid,
                name: info.name,
              ),
            );
          });
      when(() => mockManager.requestSendSlotName(any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.setParameterValue(any(), any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.requestSetMapping(any(), any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockMetadataDao.getFullAlgorithmDetails('guid-1'))
          .thenAnswer((_) async => _fullAlgorithmDetails('guid-1', 'Alg 1'));
      when(() => mockMetadataDao.getAllAlgorithms())
          .thenAnswer((_) async => []);
      when(() => mockMetadataDao.getAlgorithmParameterCounts())
          .thenAnswer((_) async => <String, int>{});
      when(() => mockPresetsDao.getAllPresets())
          .thenAnswer((_) async => <PresetEntry>[]);

      final distingCubit = DistingCubit(
        mockDatabase,
        midiCommand: MockMidiCommand(),
      )..emit(_synchronizedState(mockManager, firmwareVersion: '1.19.99'));
      final syncCubit = MetadataSyncCubit(mockDatabase, distingCubit);
      final states = <MetadataSyncState>[];
      final subscription = syncCubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(syncCubit.close);
      addTearDown(distingCubit.close);

      await syncCubit.applyTemplateToDevice(
        template: _template(
          slots: [
            FullPresetSlot(
              slot: const PresetSlotEntry(
                id: 1,
                presetId: 1,
                slotIndex: 0,
                algorithmGuid: 'guid-1',
              ),
              algorithm: const AlgorithmEntry(
                guid: 'guid-1',
                name: 'Alg 1',
                numSpecifications: 0,
              ),
              parameterValues: {},
              parameterStringValues: {},
              mappings: {0: PackedMappingData.fromBytes(8, mappingV8Fixture())},
            ),
          ],
        ),
        templateSlotIndices: const [0],
        manager: mockManager,
      );

      expect(
        syncCubit.state,
        isA<PresetLoadFailure>().having(
          (state) => state.error,
          'error',
          contains('firmware 1.20 or newer'),
        ),
      );
      verifyNever(() => mockManager.requestSetMapping(any(), any(), any()));
      verifyNever(() => mockManager.requestNewPreset());
      verifyNever(() => mockManager.requestAddAlgorithm(any(), any()));
    },
    tags: ['regression'],
  );

  test(
    'template application preserves v8 expressive mapping options',
    () async {
      final deviceAlgorithms = <Algorithm>[];
      _stubRefreshableDevice(mockManager, deviceAlgorithms);
      when(() => mockManager.requestAddAlgorithm(any(), any()))
          .thenAnswer((invocation) async {
            final info = invocation.positionalArguments[0] as AlgorithmInfo;
            deviceAlgorithms.add(
              Algorithm(
                algorithmIndex: deviceAlgorithms.length,
                guid: info.guid,
                name: info.name,
              ),
            );
          });
      when(() => mockManager.requestSendSlotName(any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.setParameterValue(any(), any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockManager.requestSetMapping(any(), any(), any()))
          .thenAnswer((_) async => {});
      when(() => mockMetadataDao.getFullAlgorithmDetails('guid-1'))
          .thenAnswer((_) async => _fullAlgorithmDetails('guid-1', 'Alg 1'));
      when(() => mockMetadataDao.getAllAlgorithms())
          .thenAnswer((_) async => []);
      when(() => mockMetadataDao.getAlgorithmParameterCounts())
          .thenAnswer((_) async => <String, int>{});
      when(() => mockPresetsDao.getAllPresets())
          .thenAnswer((_) async => <PresetEntry>[]);

      final distingCubit = DistingCubit(
        mockDatabase,
        midiCommand: MockMidiCommand(),
      )..emit(_synchronizedState(mockManager, firmwareVersion: '1.20beta'));
      final syncCubit = MetadataSyncCubit(mockDatabase, distingCubit);
      final states = <MetadataSyncState>[];
      final subscription = syncCubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(syncCubit.close);
      addTearDown(distingCubit.close);

      await syncCubit.applyTemplateToDevice(
        template: _template(
          slots: [
            FullPresetSlot(
              slot: const PresetSlotEntry(
                id: 1,
                presetId: 1,
                slotIndex: 0,
                algorithmGuid: 'guid-1',
              ),
              algorithm: const AlgorithmEntry(
                guid: 'guid-1',
                name: 'Alg 1',
                numSpecifications: 0,
              ),
              parameterValues: {},
              parameterStringValues: {},
              mappings: {
                0: PackedMappingData.fromBytes(
                  8,
                  mappingV8Fixture(),
                ).copyWith(midiMappingType: MidiMappingType.pitchBend),
              },
            ),
          ],
        ),
        templateSlotIndices: const [0],
        manager: mockManager,
      );

      final captured =
          verify(() => mockManager.requestSetMapping(0, 0, captureAny()))
                  .captured
                  .single
              as PackedMappingData;
      expect(states.whereType<PresetLoadSuccess>(), isNotEmpty);
      expect(states.whereType<PresetLoadFailure>(), isEmpty);
      expect(captured.version, equals(8));
      expect(captured.midiMappingType, equals(MidiMappingType.pitchBend));
      expect(captured.midiCC, equals(0));
      expect(captured.midiViewChange, isFalse);
      expect(captured.midiIgnoreWhenBypassed, isTrue);
      expect(captured.i2cIgnoreWhenBypassed, isTrue);
      expect(captured.cvFlagsExtra, 64);
    },
    tags: ['regression'],
  );
}
