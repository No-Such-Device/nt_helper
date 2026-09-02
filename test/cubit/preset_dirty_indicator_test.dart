import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class MockAppDatabase extends Mock implements AppDatabase {}

class MockMetadataDao extends Mock implements MetadataDao {}

class MockDistingMidiManager extends Mock
    implements IDistingMidiManager, AlgorithmVisualStyleWriter {}

class TestDistingCubit extends DistingCubit {
  TestDistingCubit(super.database, {super.midiCommand});

  Future<Slot> Function(IDistingMidiManager disting, int algorithmIndex)?
  fetchSlotOverride;
  Future<List<Slot>> Function(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting,
  )?
  fetchSlotsOverride;

  @override
  Future<Slot> fetchSlot(IDistingMidiManager disting, int algorithmIndex) {
    final override = fetchSlotOverride;
    if (override != null) return override(disting, algorithmIndex);
    return super.fetchSlot(disting, algorithmIndex);
  }

  @override
  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int completed, int total)? onSlotProgress,
  }) {
    final override = fetchSlotsOverride;
    if (override != null) return override(numAlgorithmsInPreset, disting);
    return super.fetchSlots(
      numAlgorithmsInPreset,
      disting,
      onSlotProgress: onSlotProgress,
    );
  }
}

void main() {
  late TestDistingCubit cubit;
  late MockAppDatabase mockDatabase;
  late MockMetadataDao mockMetadataDao;
  late MockDistingMidiManager mockDisting;
  late MockMidiCommand mockMidiCommand;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    registerFallbackValue(DistingState.initial());
    registerFallbackValue(
      AlgorithmInfo(
        algorithmIndex: 0,
        name: 'fallback',
        guid: 'fallback',
        specifications: const [],
      ),
    );
    registerFallbackValue(PackedMappingData.filler());
    registerFallbackValue(PerformancePageItem.empty(0));
    registerFallbackValue(const AlgorithmVisualStyle());
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    mockDatabase = MockAppDatabase();
    mockMetadataDao = MockMetadataDao();
    mockDisting = MockDistingMidiManager();
    mockMidiCommand = MockMidiCommand();

    when(() => mockDatabase.metadataDao).thenReturn(mockMetadataDao);
    when(
      () => mockMetadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    when(
      () => mockMetadataDao.getAlgorithmInfoCache(
        any(),
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => const []);

    cubit = TestDistingCubit(mockDatabase, midiCommand: mockMidiCommand);
  });

  tearDown(() async {
    await cubit.close();
  });

  Slot makeSlot({int algorithmIndex = 0, int paramCount = 1}) {
    return Slot(
      algorithm: Algorithm(
        algorithmIndex: algorithmIndex,
        guid: 'test',
        name: 'Test',
      ),
      routing: RoutingInfo.filler(),
      pages: ParameterPages(algorithmIndex: algorithmIndex, pages: const []),
      parameters: List.generate(
        paramCount,
        (i) => ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: i,
          min: 0,
          max: 100,
          defaultValue: 0,
          unit: 0,
          name: 'p$i',
          powerOfTen: 0,
        ),
      ),
      values: List.generate(
        paramCount,
        (i) => ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: i,
          value: 0,
        ),
      ),
      enums: List.generate(
        paramCount,
        (i) => ParameterEnumStrings(
          algorithmIndex: algorithmIndex,
          parameterNumber: i,
          values: const [],
        ),
      ),
      mappings: List.generate(
        paramCount,
        (i) => Mapping(
          algorithmIndex: algorithmIndex,
          parameterNumber: i,
          packedMappingData: PackedMappingData.filler(),
        ),
      ),
      valueStrings: List.generate(
        paramCount,
        (i) => ParameterValueString(
          algorithmIndex: algorithmIndex,
          parameterNumber: i,
          value: '',
        ),
      ),
    );
  }

  DistingStateSynchronized makeSyncState({
    String presetName = 'Test Preset',
    String firmwareVersion = '1.14.0',
    bool isDirty = false,
    bool offline = false,
    List<AlgorithmInfo> algorithms = const [],
    List<Slot>? slots,
  }) {
    return DistingStateSynchronized(
      disting: mockDisting,
      distingVersion: firmwareVersion,
      firmwareVersion: FirmwareVersion(firmwareVersion),
      presetName: presetName,
      algorithms: algorithms,
      slots: slots ?? const [],
      unitStrings: const [],
      offline: offline,
      isDirty: isDirty,
    );
  }

  group('DistingStateSynchronized.isDirty default', () {
    test('a freshly constructed synchronized state has isDirty == false', () {
      final s = DistingStateSynchronized(
        disting: mockDisting,
        distingVersion: '1.10.0',
        firmwareVersion: FirmwareVersion('1.14.0'),
        presetName: 'New',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      );
      expect(s.isDirty, isFalse);
    });

    test('makeSyncState helper still respects explicit isDirty values', () {
      expect(makeSyncState().isDirty, isFalse);
      expect(makeSyncState(isDirty: true).isDirty, isTrue);
    });
  });

  group('cubit.updateParameterValue()', () {
    test('marks state dirty (real-time slider scrub)', () async {
      cubit.emit(makeSyncState(slots: [makeSlot()]));
      expect((cubit.state as DistingStateSynchronized).isDirty, isFalse);

      await cubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 42,
        userIsChangingTheValue: true,
      );

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test('marks state dirty (slider release)', () async {
      cubit.emit(makeSyncState(slots: [makeSlot()]));
      expect((cubit.state as DistingStateSynchronized).isDirty, isFalse);

      await cubit.updateParameterValue(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 50,
        userIsChangingTheValue: false,
      );

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('cubit.updateParameterString()', () {
    test('marks state dirty after setting and refreshing string', () async {
      when(
        () => mockDisting.setParameterString(any(), any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.requestParameterValueString(any(), any()),
      ).thenAnswer(
        (_) async => ParameterValueString(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 'hi',
        ),
      );
      cubit.emit(makeSyncState(slots: [makeSlot()]));
      expect((cubit.state as DistingStateSynchronized).isDirty, isFalse);

      await cubit.updateParameterString(
        algorithmIndex: 0,
        parameterNumber: 0,
        value: 'hi',
      );

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test(
      'refreshes entire slot after committing editable Name string',
      () async {
        ParameterInfo parameter({
          required int parameterNumber,
          required int unit,
          required String name,
        }) {
          return ParameterInfo(
            algorithmIndex: 0,
            parameterNumber: parameterNumber,
            min: 0,
            max: 100,
            defaultValue: 0,
            unit: unit,
            name: name,
            powerOfTen: 0,
          );
        }

        final originalSlot = makeSlot(paramCount: 2).copyWith(
          parameters: [
            parameter(
              parameterNumber: 0,
              unit: ParameterUnits.modernTextInput,
              name: '2:Name',
            ),
            parameter(parameterNumber: 1, unit: 0, name: '2:Solo'),
          ],
        );

        when(
          () => mockDisting.setParameterString(0, 0, 'B'),
        ).thenAnswer((_) async {});
        when(() => mockDisting.requestParameterValueString(0, 0)).thenAnswer(
          (_) async => ParameterValueString(
            algorithmIndex: 0,
            parameterNumber: 0,
            value: 'B',
          ),
        );
        when(() => mockDisting.requestParameterPages(0)).thenAnswer(
          (_) async => ParameterPages(
            algorithmIndex: 0,
            pages: [
              ParameterPage(name: 'All', parameters: [0, 1]),
            ],
          ),
        );
        when(() => mockDisting.requestNumberOfParameters(0)).thenAnswer(
          (_) async => NumParameters(algorithmIndex: 0, numParameters: 2),
        );
        when(() => mockDisting.requestAlgorithmGuid(0)).thenAnswer(
          (_) async => Algorithm(algorithmIndex: 0, guid: 'test', name: 'Test'),
        );
        when(() => mockDisting.requestAllParameterValues(0)).thenAnswer(
          (_) async => AllParameterValues(
            algorithmIndex: 0,
            values: [
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 0),
              ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 0),
            ],
          ),
        );
        when(() => mockDisting.requestParameterInfo(0, 0)).thenAnswer(
          (_) async => parameter(
            parameterNumber: 0,
            unit: ParameterUnits.modernTextInput,
            name: '2:Name',
          ),
        );
        when(() => mockDisting.requestParameterInfo(0, 1)).thenAnswer(
          (_) async => parameter(parameterNumber: 1, unit: 0, name: 'B:Solo'),
        );
        when(() => mockDisting.requestMappings(0, any())).thenAnswer(
          (invocation) async => Mapping(
            algorithmIndex: 0,
            parameterNumber: invocation.positionalArguments[1] as int,
            packedMappingData: PackedMappingData.filler(),
          ),
        );

        cubit.emit(makeSyncState(slots: [originalSlot]));

        await cubit.updateParameterString(
          algorithmIndex: 0,
          parameterNumber: 0,
          value: 'B',
        );

        final state = cubit.state as DistingStateSynchronized;
        expect(state.isDirty, isTrue);
        expect(state.slots[0].valueStrings[0].value, 'B');
        expect(state.slots[0].parameters[1].name, 'B:Solo');
        verify(() => mockDisting.requestParameterInfo(0, 1)).called(1);
      },
    );
  });

  group('cubit algorithm ops', () {
    test(
      'refresh preserves known specifications for the same preset slot',
      () async {
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        cubit.fetchSlotsOverride = (_, _) async => [
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        ];

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        await cubit.refresh();

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [4]);
      },
    );

    test(
      'refresh does not carry specifications to a different preset',
      () async {
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Different Preset');
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        cubit.fetchSlotsOverride = (_, _) async => [
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        ];

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        await cubit.refresh();

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, isEmpty);
      },
    );

    test('refresh does not carry specifications to a different GUID', () async {
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Test Preset');
      when(
        () => mockDisting.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => 0);
      cubit.fetchSlotsOverride = (_, _) async => [makeSlot()];

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      await cubit.refresh();

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, isEmpty);
    });

    test(
      'refresh keeps nonempty specifications returned by the manager',
      () async {
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        cubit.fetchSlotsOverride = (_, _) async => [
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
              specifications: const [8],
            ),
          ),
        ];

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        await cubit.refresh();

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [8]);
      },
    );

    test('late refresh does not overwrite newer specification state', () async {
      final fetchedSlots = Completer<List<Slot>>();
      final fetchStarted = Completer<void>();
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Test Preset');
      when(
        () => mockDisting.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => 0);
      cubit.fetchSlotsOverride = (_, _) {
        fetchStarted.complete();
        return fetchedSlots.future;
      };

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      final refresh = cubit.refresh();
      await fetchStarted.future;
      cubit.emit(
        makeSyncState(
          slots: [
            quantizerSlot.copyWith(
              algorithm: quantizerSlot.algorithm.copyWith(
                specifications: const [8],
              ),
            ),
          ],
        ),
      );
      fetchedSlots.complete([
        quantizerSlot.copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
          ),
        ),
      ]);
      await refresh;

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, const [8]);
    });

    test(
      'newer overlapping refresh wins even when the older finishes first',
      () async {
        final firstFetchedSlots = Completer<List<Slot>>();
        final secondFetchedSlots = Completer<List<Slot>>();
        final firstFetchStarted = Completer<void>();
        final secondFetchStarted = Completer<void>();
        var fetchCount = 0;
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        cubit.fetchSlotsOverride = (_, _) {
          fetchCount++;
          if (fetchCount == 1) {
            firstFetchStarted.complete();
            return firstFetchedSlots.future;
          }
          secondFetchStarted.complete();
          return secondFetchedSlots.future;
        };

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        final firstRefresh = cubit.refresh();
        await firstFetchStarted.future;
        final secondRefresh = cubit.refresh();
        await secondFetchStarted.future;

        firstFetchedSlots.complete([
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        ]);
        await firstRefresh;
        secondFetchedSlots.complete([
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
              specifications: const [8],
            ),
          ),
        ]);
        await secondRefresh;

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [8]);
      },
    );

    test('late refresh does not restore a replaced manager', () async {
      final replacementManager = MockDistingMidiManager();
      when(
        () => replacementManager.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => 0);
      final fetchedSlots = Completer<List<Slot>>();
      final fetchStarted = Completer<void>();
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Test Preset');
      when(
        () => mockDisting.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => 0);
      cubit.fetchSlotsOverride = (_, _) {
        fetchStarted.complete();
        return fetchedSlots.future;
      };

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      final refresh = cubit.refresh();
      await fetchStarted.future;
      cubit.emit(
        makeSyncState(
          slots: [quantizerSlot],
        ).copyWith(disting: replacementManager),
      );
      fetchedSlots.complete([
        quantizerSlot.copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
          ),
        ),
      ]);
      await refresh;

      final state = cubit.state as DistingStateSynchronized;
      expect(state.disting, same(replacementManager));
      expect(state.slots.single.algorithm.specifications, const [4]);
    });

    test(
      'full refresh preserves known specifications for the same slot',
      () async {
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestVersionString(),
        ).thenAnswer((_) async => '1.14.0');
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        when(
          () => mockDisting.requestUnitStrings(),
        ).thenAnswer((_) async => const []);
        cubit.fetchSlotsOverride = (_, _) async => [
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        ];

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        await cubit.refresh(fullRefresh: true);

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [4]);
      },
    );

    test('late full refresh does not overwrite newer specifications', () async {
      final fetchedSlots = Completer<List<Slot>>();
      final fetchStarted = Completer<void>();
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      when(
        () => mockDisting.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDisting.requestVersionString(),
      ).thenAnswer((_) async => '1.14.0');
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Test Preset');
      when(
        () => mockDisting.requestUnitStrings(),
      ).thenAnswer((_) async => const []);
      cubit.fetchSlotsOverride = (_, _) {
        fetchStarted.complete();
        return fetchedSlots.future;
      };

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      final refresh = cubit.refresh(fullRefresh: true);
      await fetchStarted.future;
      cubit.emit(
        makeSyncState(
          slots: [
            quantizerSlot.copyWith(
              algorithm: quantizerSlot.algorithm.copyWith(
                specifications: const [8],
              ),
            ),
          ],
        ),
      );
      fetchedSlots.complete([
        quantizerSlot.copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
          ),
        ),
      ]);
      await refresh;

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, const [8]);
    });

    test('timed-out full refresh cannot emit a late result', () {
      fakeAsync((async) {
        final fetchedSlots = Completer<List<Slot>>();
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestNumberOfAlgorithms(),
        ).thenAnswer((_) async => 0);
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestVersionString(),
        ).thenAnswer((_) async => '1.14.0');
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        when(
          () => mockDisting.requestUnitStrings(),
        ).thenAnswer((_) async => const []);
        cubit.fetchSlotsOverride = (_, _) => fetchedSlots.future;

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        unawaited(cubit.refresh(fullRefresh: true));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        fetchedSlots.complete([
          quantizerSlot.copyWith(
            algorithm: quantizerSlot.algorithm.copyWith(
              specifications: const [8],
            ),
          ),
        ]);
        async.flushMicrotasks();

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [4]);
      });
    });

    test(
      'replacement load forgets specifications even when name and GUID match',
      () async {
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        when(
          () => mockDisting.requestLoadPreset('same-name.json', false),
        ).thenAnswer((_) async {});
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(),
        ).thenAnswer((_) async => 1);
        when(
          () => mockDisting.requestPresetName(),
        ).thenAnswer((_) async => 'Test Preset');
        cubit.fetchSlotsOverride = (_, _) async => [
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        ];

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        await cubit.loadPreset('same-name.json', false);

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, isEmpty);
      },
    );

    test('append load preserves specifications for existing slots', () async {
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      when(
        () => mockDisting.requestLoadPreset('append.json', true),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 1);
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Test Preset');
      cubit.fetchSlotsOverride = (_, _) async => [
        quantizerSlot.copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
          ),
        ),
      ];

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      await cubit.loadPreset('append.json', true);

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, const [4]);
    });

    test('single-slot refresh preserves known specifications', () async {
      final quantizerSlot = makeSlot().copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
          specifications: const [4],
        ),
      );
      cubit.fetchSlotOverride = (_, _) async => quantizerSlot.copyWith(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'quan',
          name: 'Quantizer',
        ),
      );

      cubit.emit(makeSyncState(slots: [quantizerSlot]));
      await cubit.refreshSlot(0);

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, const [4]);
    });

    test(
      'single-slot refresh does not carry specifications between managers',
      () async {
        final replacementManager = MockDistingMidiManager();
        final fetchedSlot = Completer<Slot>();
        final quantizerSlot = makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
            specifications: const [4],
          ),
        );
        cubit.fetchSlotOverride = (_, _) => fetchedSlot.future;

        cubit.emit(makeSyncState(slots: [quantizerSlot]));
        final refresh = cubit.refreshSlot(0);
        await Future<void>.delayed(Duration.zero);
        cubit.emit(
          makeSyncState(
            slots: [
              quantizerSlot.copyWith(
                algorithm: quantizerSlot.algorithm.copyWith(
                  specifications: const [8],
                ),
              ),
            ],
          ).copyWith(disting: replacementManager),
        );
        fetchedSlot.complete(
          quantizerSlot.copyWith(
            algorithm: Algorithm(
              algorithmIndex: 0,
              guid: 'quan',
              name: 'Quantizer',
            ),
          ),
        );
        await refresh;

        final state = cubit.state as DistingStateSynchronized;
        expect(state.disting, same(replacementManager));
        expect(state.slots.single.algorithm.specifications, const [8]);
      },
    );

    test('onAlgorithmSelected marks state dirty', () async {
      final algorithmInfo = AlgorithmInfo(
        algorithmIndex: 0,
        name: 'Test Algo',
        guid: 'test',
        specifications: const [],
      );
      when(
        () => mockDisting.requestAddAlgorithm(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(
          timeout: any(named: 'timeout'),
          maxRetries: any(named: 'maxRetries'),
        ),
      ).thenAnswer((_) async => 1);

      cubit.emit(makeSyncState());
      await cubit.onAlgorithmSelected(algorithmInfo, const []);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
      expect((cubit.state as DistingStateSynchronized).slots, hasLength(1));
      verifyNever(() => mockDisting.setParameterValue(any(), any(), any()));
    });

    test(
      'onAlgorithmSelected retains the user-selected specifications',
      () async {
        final algorithmInfo = AlgorithmInfo(
          algorithmIndex: 0,
          name: 'Quantizer',
          guid: 'quan',
          specifications: [
            Specification(
              name: 'Channels',
              min: 1,
              max: 12,
              defaultValue: 1,
              type: 0,
            ),
          ],
        );
        when(
          () => mockDisting.requestAddAlgorithm(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(
            timeout: any(named: 'timeout'),
            maxRetries: any(named: 'maxRetries'),
          ),
        ).thenAnswer((_) async => 1);
        cubit.fetchSlotOverride = (_, _) async => throw StateError(
          'Hydration is intentionally unavailable for this state assertion.',
        );

        cubit.emit(makeSyncState(offline: true, algorithms: [algorithmInfo]));
        await cubit.onAlgorithmSelected(algorithmInfo, const [4]);

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots.single.algorithm.specifications, const [4]);
        verify(
          () => mockDisting.requestAddAlgorithm(algorithmInfo, const [4]),
        ).called(1);
      },
    );

    test('slot hydration preserves the user-selected specifications', () async {
      final algorithmInfo = AlgorithmInfo(
        algorithmIndex: 0,
        name: 'Quantizer',
        guid: 'quan',
        specifications: [
          Specification(
            name: 'Channels',
            min: 1,
            max: 12,
            defaultValue: 1,
            type: 0,
          ),
        ],
      );
      final fetchedSlot = Completer<Slot>();
      when(
        () => mockDisting.requestAddAlgorithm(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(
          timeout: any(named: 'timeout'),
          maxRetries: any(named: 'maxRetries'),
        ),
      ).thenAnswer((_) async => 1);
      cubit.fetchSlotOverride = (_, _) => fetchedSlot.future;

      cubit.emit(makeSyncState());
      await cubit.onAlgorithmSelected(algorithmInfo, const [4]);
      fetchedSlot.complete(
        makeSlot().copyWith(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'quan',
            name: 'Quantizer',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.specifications, const [4]);
    });

    test('onAlgorithmSelected can add bypassed immediately', () async {
      final algorithmInfo = AlgorithmInfo(
        algorithmIndex: 0,
        name: 'Bypassed Algo',
        guid: 'bypa',
        specifications: const [],
      );
      when(
        () => mockDisting.requestAddAlgorithm(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.setParameterValue(0, 0, 1),
      ).thenAnswer((_) async {});
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(
          timeout: any(named: 'timeout'),
          maxRetries: any(named: 'maxRetries'),
        ),
      ).thenAnswer((_) async => 1);

      cubit.emit(makeSyncState());
      await cubit.onAlgorithmSelected(
        algorithmInfo,
        const [],
        addBypassed: true,
      );

      verifyInOrder([
        () => mockDisting.requestAddAlgorithm(any(), any()),
        () => mockDisting.setParameterValue(0, 0, 1),
        () => mockDisting.requestNumAlgorithmsInPreset(
          timeout: any(named: 'timeout'),
          maxRetries: any(named: 'maxRetries'),
        ),
      ]);
      expect((cubit.state as DistingStateSynchronized).slots, hasLength(1));
    });

    test(
      'onAlgorithmSelected reports bypass write failure separately',
      () async {
        final algorithmInfo = AlgorithmInfo(
          algorithmIndex: 0,
          name: 'Bypass Failed Algo',
          guid: 'byfl',
          specifications: const [],
        );
        when(
          () => mockDisting.requestAddAlgorithm(any(), any()),
        ).thenAnswer((_) async {});
        when(
          () => mockDisting.setParameterValue(0, 0, 1),
        ).thenAnswer((_) async => throw Exception('send failed'));
        when(
          () => mockDisting.requestNumAlgorithmsInPreset(
            timeout: any(named: 'timeout'),
            maxRetries: any(named: 'maxRetries'),
          ),
        ).thenAnswer((_) async => 1);

        cubit.emit(makeSyncState());

        await expectLater(
          cubit.onAlgorithmSelected(algorithmInfo, const [], addBypassed: true),
          throwsA(isA<AlgorithmAddBypassFailedException>()),
        );

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots, hasLength(1));
        expect(state.isDirty, isTrue);
        verifyInOrder([
          () => mockDisting.requestAddAlgorithm(any(), any()),
          () => mockDisting.setParameterValue(0, 0, 1),
          () => mockDisting.requestNumAlgorithmsInPreset(
            timeout: any(named: 'timeout'),
            maxRetries: any(named: 'maxRetries'),
          ),
        ]);
      },
    );

    test(
      'onAlgorithmSelected removes placeholder when slot count does not grow',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Rejected Algo',
            guid: 'reject',
            specifications: const [],
          );
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => 0);

          cubit.emit(makeSyncState());
          cubit
              .onAlgorithmSelected(algorithmInfo, const [])
              .catchError((Object e) => error = e);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 10));

          expect(error, isA<AlgorithmAddFailedException>());
          final state = cubit.state as DistingStateSynchronized;
          expect(state.slots, isEmpty);
          expect(state.isDirty, isFalse);
          verify(
            () => mockDisting.requestAddAlgorithm(algorithmInfo, const []),
          ).called(1);
          verify(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).called(9);
        });
      },
    );

    test(
      'onAlgorithmSelected waits and keeps checking for delayed slot growth',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Eventually Added Algo',
            guid: 'eventual',
            specifications: const [],
          );
          var countRequests = 0;
          var completed = false;
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => ++countRequests == 1 ? 0 : 1);

          cubit.emit(makeSyncState());
          unawaited(
            cubit
                .onAlgorithmSelected(algorithmInfo, const [])
                .then<void>(
                  (_) {
                    completed = true;
                  },
                  onError: (Object e, StackTrace _) {
                    error = e;
                  },
                ),
          );
          async.flushMicrotasks();

          expect(countRequests, 0);
          expect(completed, isFalse);

          async.elapse(const Duration(seconds: 1));
          expect(countRequests, 1);
          expect(completed, isFalse);

          async.elapse(const Duration(seconds: 1));
          expect(countRequests, 2);
          expect(completed, isTrue);
          expect(error, isNull);

          final state = cubit.state as DistingStateSynchronized;
          expect(state.slots, hasLength(1));
          expect(state.isDirty, isTrue);
        });
      },
    );

    test(
      'slow unchanged response only gives the next request the remaining window',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Slow Algo',
            guid: 'slow',
            specifications: const [],
          );
          final retryBudgets = <int>[];
          var completed = false;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((invocation) {
            retryBudgets.add(invocation.namedArguments[#maxRetries]! as int);
            if (retryBudgets.length == 1) {
              return Future<int?>.delayed(const Duration(seconds: 5), () => 0);
            }
            return Future<int?>.value(1);
          });
          cubit.fetchSlotOverride = (_, _) async =>
              (cubit.state as DistingStateSynchronized).slots.single;

          cubit.emit(makeSyncState());
          unawaited(
            cubit.onAlgorithmSelected(algorithmInfo, const []).then<void>((_) {
              completed = true;
            }),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 7));

          expect(completed, isTrue);
          expect(retryBudgets, [9, 3]);
        });
      },
    );

    test(
      'failed add rollback preserves other edits made during verification',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 1,
            name: 'Rejected Algo',
            guid: 'reject',
            specifications: const [],
          );
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => 1);

          cubit.emit(makeSyncState(slots: [makeSlot()]));
          cubit
              .onAlgorithmSelected(algorithmInfo, const [])
              .catchError((Object e) => error = e);
          async.flushMicrotasks();

          final pending = cubit.state as DistingStateSynchronized;
          cubit.emit(
            pending.copyWith(presetName: 'Edited while waiting', isDirty: true),
          );
          async.elapse(const Duration(seconds: 10));

          expect(error, isA<AlgorithmAddFailedException>());
          final state = cubit.state as DistingStateSynchronized;
          expect(state.slots, hasLength(1));
          expect(state.presetName, 'Edited while waiting');
          expect(state.isDirty, isTrue);
        });
      },
    );

    test(
      'failed add rollback does not remove a refreshed replacement slot',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Rejected Algo',
            guid: 'reject',
            specifications: const [],
          );
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => 0);

          cubit.emit(makeSyncState());
          cubit
              .onAlgorithmSelected(algorithmInfo, const [])
              .catchError((Object e) => error = e);
          async.flushMicrotasks();

          final pending = cubit.state as DistingStateSynchronized;
          final replacement = pending.slots.single.copyWith(
            values: [
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 42),
            ],
          );
          cubit.emit(pending.copyWith(slots: [replacement]));
          async.elapse(const Duration(seconds: 10));

          expect(error, isA<AlgorithmAddFailedException>());
          expect((cubit.state as DistingStateSynchronized).slots, [
            replacement,
          ]);
        });
      },
    );

    test(
      'onAlgorithmSelected retries verification without resending the add',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Unresponsive Algo',
            guid: 'silent',
            specifications: const [],
          );
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer(
            (_) => Future<int?>.delayed(
              const Duration(seconds: 9),
              () => throw TimeoutException(
                'no response',
                const Duration(seconds: 1),
              ),
            ),
          );

          cubit.emit(makeSyncState());
          cubit
              .onAlgorithmSelected(algorithmInfo, const [])
              .catchError((Object e) => error = e);
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 9));
          expect(error, isNull);
          expect((cubit.state as DistingStateSynchronized).slots, hasLength(1));

          async.elapse(const Duration(seconds: 1));

          expect(error, isA<AlgorithmAddFailedException>());
          expect((cubit.state as DistingStateSynchronized).slots, isEmpty);
          verify(
            () => mockDisting.requestAddAlgorithm(algorithmInfo, const []),
          ).called(1);
          verify(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: const Duration(seconds: 1),
              maxRetries: 9,
            ),
          ).called(1);
        });
      },
    );

    test(
      'onAlgorithmSelected keeps the confirmed placeholder when hydration fails',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Broken Pages Algo',
            guid: 'pages',
            specifications: const [],
          );
          var completed = false;
          Object? error;
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => 1);
          when(
            () => mockDisting.requestNumberOfParameters(0),
          ).thenThrow(StateError('broken slot details'));
          when(() => mockDisting.requestAlgorithmGuid(0)).thenAnswer(
            (_) async =>
                Algorithm(algorithmIndex: 0, guid: 'pages', name: 'Broken'),
          );

          cubit.emit(makeSyncState());
          unawaited(
            cubit
                .onAlgorithmSelected(algorithmInfo, const [])
                .then<void>(
                  (_) {
                    completed = true;
                  },
                  onError: (Object e, StackTrace _) {
                    error = e;
                  },
                ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 4));

          expect(completed, isTrue);
          expect(error, isNull);
          final state = cubit.state as DistingStateSynchronized;
          expect(state.slots, hasLength(1));
          expect(state.slots.single.algorithm.guid, 'pages');
          verify(() => mockDisting.requestNumberOfParameters(0)).called(1);
        });
      },
    );

    test(
      'completed hydration does not overwrite a refreshed replacement slot',
      () {
        fakeAsync((async) {
          final algorithmInfo = AlgorithmInfo(
            algorithmIndex: 0,
            name: 'Hydrating Algo',
            guid: 'hydrate',
            specifications: const [],
          );
          final fetchedSlot = Completer<Slot>();
          when(
            () => mockDisting.requestAddAlgorithm(any(), any()),
          ).thenAnswer((_) async {});
          when(
            () => mockDisting.requestNumAlgorithmsInPreset(
              timeout: any(named: 'timeout'),
              maxRetries: any(named: 'maxRetries'),
            ),
          ).thenAnswer((_) async => 1);
          cubit.fetchSlotOverride = (_, _) => fetchedSlot.future;

          cubit.emit(makeSyncState());
          unawaited(cubit.onAlgorithmSelected(algorithmInfo, const []));
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 1));

          final pending = cubit.state as DistingStateSynchronized;
          final replacement = pending.slots.single.copyWith(
            values: [
              ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 42),
            ],
          );
          cubit.emit(pending.copyWith(slots: [replacement]));
          fetchedSlot.complete(
            pending.slots.single.copyWith(
              values: [
                ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 1),
              ],
            ),
          );
          async.flushMicrotasks();

          expect((cubit.state as DistingStateSynchronized).slots, [
            replacement,
          ]);
        });
      },
    );

    test(
      'onAlgorithmSelected removes placeholder when add request throws',
      () async {
        final algorithmInfo = AlgorithmInfo(
          algorithmIndex: 0,
          name: 'Rejected Algo',
          guid: 'reject',
          specifications: const [],
        );
        when(
          () => mockDisting.requestAddAlgorithm(any(), any()),
        ).thenAnswer((_) async => throw Exception('rejected'));

        cubit.emit(makeSyncState());

        await expectLater(
          cubit.onAlgorithmSelected(algorithmInfo, const []),
          throwsA(isA<AlgorithmAddFailedException>()),
        );

        final state = cubit.state as DistingStateSynchronized;
        expect(state.slots, isEmpty);
        expect(state.isDirty, isFalse);
      },
    );

    test('onRemoveAlgorithm marks state dirty', () async {
      when(
        () => mockDisting.requestRemoveAlgorithm(any()),
      ).thenAnswer((_) async {});

      cubit.emit(makeSyncState(slots: [makeSlot()]));
      await cubit.onRemoveAlgorithm(0);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test('moveAlgorithmUp marks state dirty', () async {
      when(
        () => mockDisting.requestMoveAlgorithmUp(any()),
      ).thenAnswer((_) async {});

      cubit.emit(
        makeSyncState(
          slots: [makeSlot(algorithmIndex: 0), makeSlot(algorithmIndex: 1)],
        ),
      );
      await cubit.moveAlgorithmUp(1);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test('moveAlgorithmDown marks state dirty', () async {
      when(
        () => mockDisting.requestMoveAlgorithmDown(any()),
      ).thenAnswer((_) async {});

      cubit.emit(
        makeSyncState(
          slots: [makeSlot(algorithmIndex: 0), makeSlot(algorithmIndex: 1)],
        ),
      );
      await cubit.moveAlgorithmDown(0);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('cubit slot ops', () {
    test('renameSlot marks state dirty', () async {
      when(
        () => mockDisting.requestSendSlotName(any(), any()),
      ).thenAnswer((_) async {});

      cubit.emit(makeSyncState(slots: [makeSlot()]));
      cubit.renameSlot(0, 'New Name');
      // Allow microtask queue to flush so the optimistic emit lands.
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('device-truth refreshes preserve isDirty', () {
    test('refreshRouting (slot state delegate) preserves dirty flag', () async {
      when(
        () => mockDisting.requestRoutingInformation(any()),
      ).thenAnswer((_) async => RoutingInfo.filler());

      cubit.emit(makeSyncState(isDirty: true, slots: [makeSlot()]));
      await cubit.refreshRouting();

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test('refreshRouting does not falsely mark dirty when clean', () async {
      when(
        () => mockDisting.requestRoutingInformation(any()),
      ).thenAnswer((_) async => RoutingInfo.filler());

      cubit.emit(makeSyncState(slots: [makeSlot()]));
      await cubit.refreshRouting();

      expect((cubit.state as DistingStateSynchronized).isDirty, isFalse);
    });
  });

  group('cubit mapping ops', () {
    test('saveMapping coalesces rapid edits to the latest mapping', () async {
      final first = PackedMappingData.filler().copyWith(
        version: 6,
        i2cCC: 12,
        isI2cEnabled: true,
        i2cMin: 0,
        i2cMax: 100,
      );
      final latest = first.copyWith(i2cCC: 32);
      final writes = <PackedMappingData>[];
      var hardwareMapping = PackedMappingData.filler();

      when(() => mockDisting.requestSetMapping(any(), any(), any())).thenAnswer(
        (invocation) async {
          hardwareMapping =
              invocation.positionalArguments[2] as PackedMappingData;
          writes.add(hardwareMapping);
        },
      );
      when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: hardwareMapping,
        ),
      );
      cubit.emit(makeSyncState(slots: [makeSlot()]));

      await Future.wait([
        cubit.saveMapping(0, 0, first),
        cubit.saveMapping(0, 0, latest),
      ]);

      expect(writes, [latest]);
      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots[0].mappings[0].packedMappingData, latest);
      expect(state.isDirty, isTrue);
    });

    test('saveMapping rewrites until exact readback is verified', () async {
      final desired = PackedMappingData.filler().copyWith(
        version: 6,
        midiChannel: 4,
        midiCC: 74,
        isMidiEnabled: true,
        midiMin: 0,
        midiMax: 100,
      );
      var writeCount = 0;

      when(() => mockDisting.requestSetMapping(any(), any(), any())).thenAnswer(
        (_) async {
          writeCount++;
        },
      );
      when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: writeCount >= 2
              ? desired
              : PackedMappingData.filler(),
        ),
      );
      cubit.emit(makeSyncState(slots: [makeSlot()]));

      await cubit.saveMapping(0, 0, desired);

      expect(writeCount, 2);
      verify(() => mockDisting.requestMappings(0, 0)).called(2);
    });

    test(
      'saveMapping preserves a separate performance-page assignment',
      () async {
        final original = PackedMappingData.filler().copyWith(
          version: 6,
          perfPageIndex: 5,
        );
        final desired = original.copyWith(
          i2cCC: 32,
          isI2cEnabled: true,
          i2cMin: 0,
          i2cMax: 100,
        );

        when(
          () => mockDisting.requestSetMapping(any(), any(), any()),
        ).thenAnswer((_) async {});
        when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
          (_) async => Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            // Performance pages are managed by a separate command and are
            // therefore absent from mapping readback on current firmware.
            packedMappingData: desired.copyWith(perfPageIndex: 0),
          ),
        );
        cubit.emit(
          makeSyncState(
            slots: [
              makeSlot().copyWith(
                mappings: [
                  Mapping(
                    algorithmIndex: 0,
                    parameterNumber: 0,
                    packedMappingData: original,
                  ),
                ],
              ),
            ],
          ),
        );

        await cubit.saveMappingImmediately(0, 0, desired);

        verify(() => mockDisting.requestSetMapping(0, 0, desired)).called(1);
        final saved = (cubit.state as DistingStateSynchronized)
            .slots[0]
            .mappings[0]
            .packedMappingData;
        expect(saved.i2cCC, 32);
        expect(saved.perfPageIndex, 5);
      },
    );

    test('saveMapping retains intent until synchronization returns', () async {
      final desired = PackedMappingData.filler().copyWith(
        version: 6,
        cvInput: 3,
        volts: 5,
        delta: 100,
      );
      var completed = false;

      when(
        () => mockDisting.requestSetMapping(any(), any(), any()),
      ).thenAnswer((_) async {});
      when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: desired,
        ),
      );

      final save = cubit
          .saveMapping(0, 0, desired)
          .whenComplete(() => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      verifyNever(() => mockDisting.requestSetMapping(any(), any(), any()));

      cubit.emit(makeSyncState(slots: [makeSlot()]));
      await save.timeout(const Duration(seconds: 3));

      verify(() => mockDisting.requestSetMapping(0, 0, desired)).called(1);
    });

    test('saveMapping keeps failed intent queued until it succeeds', () async {
      final desired = PackedMappingData.filler().copyWith(
        version: 6,
        i2cCC: 32,
        isI2cEnabled: true,
        i2cMin: 0,
        i2cMax: 100,
      );
      var writeCount = 0;

      when(() => mockDisting.requestSetMapping(any(), any(), any())).thenAnswer(
        (_) async {
          writeCount++;
        },
      );
      when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: writeCount >= 5
              ? desired
              : desired.copyWith(i2cCC: 31),
        ),
      );
      cubit.emit(makeSyncState(slots: [makeSlot()]));

      final recovered = cubit.stream.firstWhere(
        (state) =>
            state is DistingStateSynchronized &&
            state.slots[0].mappings[0].packedMappingData == desired,
      );
      await expectLater(
        cubit.saveMappingImmediately(0, 0, desired),
        throwsA(isA<StateError>()),
      );

      expect(writeCount, 4);
      await recovered.timeout(const Duration(seconds: 3));
      expect(writeCount, 5);
    });

    test('saveMapping marks state dirty after verified write', () async {
      PackedMappingData? deviceMapping;
      when(
        () => mockDisting.requestSetMapping(any(), any(), any()),
      ).thenAnswer((invocation) async {
        deviceMapping = invocation.positionalArguments[2] as PackedMappingData;
      });
      when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: deviceMapping!,
        ),
      );
      cubit.emit(
        DistingStateSynchronized(
          disting: mockDisting,
          distingVersion: '1.10.0',
          firmwareVersion: FirmwareVersion('1.14.0'),
          presetName: 'Test Preset',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
          offline: true,
        ),
      );

      await cubit.saveMapping(0, 0, PackedMappingData.filler());

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });

    test(
      'saveMapping downgrades non-expressive v7 mappings before 1.17',
      () async {
        PackedMappingData? deviceMapping;
        when(
          () => mockDisting.requestSetMapping(any(), any(), any()),
        ).thenAnswer((invocation) async {
          deviceMapping =
              invocation.positionalArguments[2] as PackedMappingData;
        });
        when(() => mockDisting.requestMappings(0, 0)).thenAnswer(
          (_) async => Mapping(
            algorithmIndex: 0,
            parameterNumber: 0,
            packedMappingData: deviceMapping!,
          ),
        );
        cubit.emit(makeSyncState(firmwareVersion: '1.16.0'));

        await cubit.saveMapping(
          0,
          0,
          PackedMappingData.filler().copyWith(
            version: 7,
            midiMappingType: MidiMappingType.cc,
            midiCC: 74,
            isMidiEnabled: true,
          ),
        );

        final captured =
            verify(
                  () => mockDisting.requestSetMapping(0, 0, captureAny()),
                ).captured.single
                as PackedMappingData;
        expect(captured.version, equals(6));
        expect(captured.midiMappingType, equals(MidiMappingType.cc));
        expect(captured.midiCC, equals(74));
      },
    );

    test('setPerformancePageMapping marks state dirty (optimistic)', () async {
      when(
        () => mockDisting.setPerformancePageMapping(any(), any(), any()),
      ).thenAnswer((_) async {});
      when(() => mockDisting.requestMappings(any(), any())).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: PackedMappingData.filler().copyWith(
            perfPageIndex: 1,
          ),
        ),
      );

      cubit.emit(makeSyncState(slots: [makeSlot()]));
      // Don't await — verification retries take seconds. We only care about
      // the optimistic emit.
      unawaited(cubit.setPerformancePageMapping(0, 0, 1));
      // Allow microtask queue to flush so the optimistic emit lands.
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('cubit preset rename', () {
    test('renamePreset marks state dirty (optimistic)', () async {
      when(
        () => mockDisting.requestSetPresetName(any()),
      ).thenAnswer((_) async {});
      when(() => mockDisting.requestSavePreset()).thenAnswer((_) async {});

      cubit.emit(makeSyncState(presetName: 'Old'));
      cubit.renamePreset('New');
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('cubit algorithm visual style', () {
    test('writes firmware 1.18 style and marks the preset dirty', () async {
      const style = AlgorithmVisualStyle(
        leftIndent: 1,
        rightIndent: 3,
        lineAbove: true,
        bracket: AlgorithmVisualBracket.open,
      );
      when(
        () => mockDisting.requestSetAlgorithmVisualStyle(0, style),
      ).thenAnswer((_) async {});

      cubit.emit(
        makeSyncState(firmwareVersion: '1.18.0beta', slots: [makeSlot()]),
      );
      await cubit.setAlgorithmVisualStyle(0, style);

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.visualStyle, style);
      expect(state.isDirty, isTrue);
      verify(
        () => mockDisting.requestSetAlgorithmVisualStyle(0, style),
      ).called(1);
    });

    test('rejects style writes before firmware 1.18', () async {
      cubit.emit(makeSyncState(firmwareVersion: '1.17.9', slots: [makeSlot()]));

      await expectLater(
        cubit.setAlgorithmVisualStyle(0, const AlgorithmVisualStyle()),
        throwsUnsupportedError,
      );
      verifyNever(
        () => mockDisting.requestSetAlgorithmVisualStyle(any(), any()),
      );
    });

    test('simulates style writes in offline mode on older firmware', () async {
      const style = AlgorithmVisualStyle(
        lineBelow: true,
        bracket: AlgorithmVisualBracket.close,
      );
      when(
        () => mockDisting.requestSetAlgorithmVisualStyle(0, style),
      ).thenAnswer((_) async {});

      cubit.emit(
        makeSyncState(
          firmwareVersion: '1.15.0',
          offline: true,
          slots: [makeSlot()],
        ),
      );
      await cubit.setAlgorithmVisualStyle(0, style);

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.visualStyle, style);
      expect(state.isDirty, isTrue);
      verify(
        () => mockDisting.requestSetAlgorithmVisualStyle(0, style),
      ).called(1);
    });

    test('reconciles the optimistic style with the device readback', () async {
      const requestedStyle = AlgorithmVisualStyle(leftIndent: 4);
      const deviceStyle = AlgorithmVisualStyle(
        rightIndent: 2,
        bracket: AlgorithmVisualBracket.close,
      );
      when(
        () => mockDisting.requestSetAlgorithmVisualStyle(0, requestedStyle),
      ).thenAnswer((_) async {});
      when(() => mockDisting.requestAlgorithmGuid(0)).thenAnswer(
        (_) async => Algorithm(
          algorithmIndex: 0,
          guid: 'test',
          name: 'Test',
          visualStyle: deviceStyle,
        ),
      );

      cubit.emit(makeSyncState(firmwareVersion: '1.18.0', slots: [makeSlot()]));
      await cubit.setAlgorithmVisualStyle(0, requestedStyle);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final state = cubit.state as DistingStateSynchronized;
      expect(state.slots.single.algorithm.visualStyle, deviceStyle);
      verify(() => mockDisting.requestAlgorithmGuid(0)).called(1);
    });
  });

  group('cubit perf page ops', () {
    test('setPerfPageItem marks state dirty (optimistic)', () async {
      when(() => mockDisting.setPerfPageItem(any())).thenAnswer((_) async {});
      when(
        () => mockDisting.requestPerfPageItem(any()),
      ).thenAnswer((_) async => PerformancePageItem.empty(0));

      cubit.emit(makeSyncState());
      // Don't await — verification retries take seconds.
      unawaited(cubit.setPerfPageItem(PerformancePageItem.empty(0)));
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DistingStateSynchronized).isDirty, isTrue);
    });
  });

  group('cubit.refresh()', () {
    test('clears isDirty when state refresh from device succeeds', () async {
      when(
        () => mockDisting.requestNumAlgorithmsInPreset(),
      ).thenAnswer((_) async => 0);
      when(
        () => mockDisting.requestPresetName(),
      ).thenAnswer((_) async => 'Refreshed');

      // Offline avoids the background algorithm refresh side-effect.
      cubit.emit(
        DistingStateSynchronized(
          disting: mockDisting,
          distingVersion: '1.10.0',
          firmwareVersion: FirmwareVersion('1.14.0'),
          presetName: 'Test Preset',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
          offline: true,
          isDirty: true,
        ),
      );

      await cubit.refresh();

      expect((cubit.state as DistingStateSynchronized).isDirty, isFalse);
    });
  });

  group('cubit.savePreset()', () {
    test('clears isDirty on success', () async {
      when(() => mockDisting.requestSavePreset()).thenAnswer((_) async {});
      cubit.emit(makeSyncState(isDirty: true));

      await cubit.savePreset();

      verify(() => mockDisting.requestSavePreset()).called(1);
      final s = cubit.state as DistingStateSynchronized;
      expect(s.isDirty, isFalse);
    });

    test('leaves isDirty set when save throws', () async {
      when(
        () => mockDisting.requestSavePreset(),
      ).thenAnswer((_) async => throw Exception('save failed'));
      cubit.emit(makeSyncState(isDirty: true));

      await expectLater(cubit.savePreset(), throwsA(isA<Exception>()));

      final s = cubit.state as DistingStateSynchronized;
      expect(s.isDirty, isTrue);
    });

    test('is a no-op when state is not synchronized', () async {
      // Initial state is DistingStateInitial; no synchronized state present.
      await cubit.savePreset();

      verifyNever(() => mockDisting.requestSavePreset());
      expect(cubit.state, isA<DistingStateInitial>());
    });
  });
}
