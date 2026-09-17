import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_info_response.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_response.dart';
import 'package:nt_helper/models/algorithm_respecification.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

final class _RecordingManager extends Mock
    implements IDistingMidiManager, AlgorithmRespecificationWriter {
  final List<String> mutationCommands = [];
  final List<int> respecifiedSlots = [];
  final List<List<int>> respecifiedValues = [];
  int memoryRequests = 0;

  @override
  Future<void> requestRespecifyAlgorithm(
    int algorithmIndex,
    List<int> specifications,
  ) async {
    mutationCommands.add('respecify');
    respecifiedSlots.add(algorithmIndex);
    respecifiedValues.add(List<int>.unmodifiable(specifications));
  }

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    mutationCommands.add('add');
  }

  @override
  Future<void> requestRemoveAlgorithm(int algorithmIndex) async {
    mutationCommands.add('remove');
  }

  @override
  Future<MemoryUsage?> requestMemoryUsage(MemoryQueryInput input) async {
    memoryRequests++;
    throw StateError('Memory information is unavailable');
  }

  @override
  void dispose() {}
}

// Captured-format 0x31 payload: catalogue index 17, GUID TEST, two signed
// specification records, followed by the algorithm and specification names.
const _algorithmInfo31Fixture = <int>[
  0x00, 0x00, 0x11,
  0x54, 0x45, 0x53, 0x54,
  0x02,
  0x03, 0x7F, 0x7F, // -1 minimum
  0x00, 0x00, 0x01, // 1 maximum
  0x00, 0x00, 0x00, // 0 default
  0x02, // type
  0x00, 0x00, 0x01, // 1 minimum
  0x00, 0x00, 0x10, // 16 maximum
  0x00, 0x00, 0x04, // 4 default
  0x00, // type
  0x46, 0x69, 0x78, 0x74, 0x75, 0x72, 0x65, 0x20,
  0x61, 0x6C, 0x67, 0x6F, 0x72, 0x69, 0x74, 0x68, 0x6D, 0x00,
  0x4D, 0x6F, 0x64, 0x65, 0x00,
  0x43, 0x68, 0x61, 0x6E, 0x6E, 0x65, 0x6C, 0x73, 0x00,
];

// Captured-format extended 0x40 payload for wire slot 2. The six-byte visual
// style is followed by the authoritative count and ordered values [-1, 8].
const _algorithm40Fixture = <int>[
  0x02,
  0x54,
  0x45,
  0x53,
  0x54,
  0x46,
  0x69,
  0x78,
  0x74,
  0x75,
  0x72,
  0x65,
  0x20,
  0x73,
  0x6C,
  0x6F,
  0x74,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x02,
  0x03,
  0x7F,
  0x7F,
  0x00,
  0x00,
  0x08,
];

AlgorithmInfo _fixtureAlgorithmInfo() =>
    AlgorithmInfoResponse(Uint8List.fromList(_algorithmInfo31Fixture)).parse();

Algorithm _fixtureSlotAlgorithm() =>
    AlgorithmResponse(Uint8List.fromList(_algorithm40Fixture)).parse();

Slot _slot(Algorithm algorithm) => Slot(
  algorithm: algorithm,
  routing: RoutingInfo(
    algorithmIndex: algorithm.algorithmIndex,
    routingInfo: List<int>.filled(6, 0),
  ),
  pages: ParameterPages(
    algorithmIndex: algorithm.algorithmIndex,
    pages: const [],
  ),
  parameters: const [],
  values: const [],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
);

DistingStateSynchronized _synchronizedState(
  IDistingMidiManager manager, {
  String firmware = '1.19beta',
  bool offline = false,
  bool demo = false,
  Algorithm? selectedAlgorithm,
  List<AlgorithmInfo>? algorithms,
}) {
  final selected = selectedAlgorithm ?? _fixtureSlotAlgorithm();
  return DistingState.synchronized(
        disting: manager,
        distingVersion: firmware,
        firmwareVersion: FirmwareVersion(firmware),
        presetName: 'Fixture preset',
        algorithms: algorithms ?? [_fixtureAlgorithmInfo()],
        slots: [
          _slot(Algorithm(algorithmIndex: 0, guid: 'ONE ', name: 'First')),
          _slot(Algorithm(algorithmIndex: 1, guid: 'TWO ', name: 'Second')),
          _slot(selected),
        ],
        unitStrings: const [],
        offline: offline,
        demo: demo,
      )
      as DistingStateSynchronized;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppDatabase database;
  late _MockMetadataDao metadataDao;
  late MockMidiCommand midiCommand;
  late DistingCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    midiCommand = MockMidiCommand();
    when(() => database.metadataDao).thenReturn(metadataDao);
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: true,
    );
  });

  tearDown(() => cubit.close());

  test('uses decoded 0x31 metadata and current 0x40 values, then sends only '
      'the existing slot 0x3A without memory preflight', () async {
    final manager = _RecordingManager();
    final synchronized = _synchronizedState(manager);
    cubit.emit(synchronized);

    final preparation = cubit.prepareAlgorithmRespecification(2);

    expect(preparation.slotIndex, 2);
    expect(preparation.algorithmGuid, 'TEST');
    expect(preparation.algorithmName, 'Fixture slot');
    expect(preparation.specifications.map((value) => value.currentValue), [
      -1,
      8,
    ]);
    expect(preparation.specifications.map((value) => value.metadata.name), [
      'Mode',
      'Channels',
    ]);
    expect(preparation.specifications.map((value) => value.metadata.min), [
      -1,
      1,
    ]);
    expect(preparation.specifications.map((value) => value.metadata.max), [
      1,
      16,
    ]);
    expect(
      preparation.specifications.map((value) => value.metadata.defaultValue),
      [0, 4],
    );
    expect(preparation.specifications.map((value) => value.metadata.type), [
      2,
      0,
    ]);

    final status = await cubit.respecifyAlgorithm(2, const [1, 12]);

    expect(status, AlgorithmRespecificationStatus.sentPendingVerification);
    expect(manager.mutationCommands, ['respecify']);
    expect(manager.respecifiedSlots, [2]);
    expect(manager.respecifiedValues, [
      [1, 12],
    ]);
    expect(manager.memoryRequests, 0);
    expect(cubit.state, same(synchronized));
    expect(
      (cubit.state as DistingStateSynchronized).slots.map(
        (slot) => slot.algorithm.guid,
      ),
      ['ONE ', 'TWO ', 'TEST'],
    );
  });

  test(
    'rejects invalid proposal count, integer, and range before sending',
    () async {
      final manager = _RecordingManager();
      cubit.emit(_synchronizedState(manager));

      for (final proposal in <List<Object?>>[
        const [1],
        const [0.5, 8],
        const [2, 8],
      ]) {
        await expectLater(
          cubit.respecifyAlgorithm(2, proposal),
          throwsA(isA<AlgorithmRespecificationException>()),
        );
      }

      expect(manager.mutationCommands, isEmpty);
      expect(manager.memoryRequests, 0);
    },
  );

  test('rejects unavailable or inconsistent 0x31/0x40 metadata', () async {
    final manager = _RecordingManager();
    final info = _fixtureAlgorithmInfo();
    final selected = _fixtureSlotAlgorithm();
    final countMismatch = AlgorithmInfo(
      algorithmIndex: info.algorithmIndex,
      name: info.name,
      guid: info.guid,
      specifications: [info.specifications.first],
      isPlugin: info.isPlugin,
      isLoaded: info.isLoaded,
      filename: info.filename,
    );

    final invalidStates = <DistingStateSynchronized>[
      _synchronizedState(
        manager,
        selectedAlgorithm: selected.copyWith(
          hasAuthoritativeSpecifications: false,
        ),
      ),
      _synchronizedState(manager, algorithms: const []),
      _synchronizedState(manager, algorithms: [countMismatch]),
      _synchronizedState(
        manager,
        selectedAlgorithm: selected.copyWith(
          specifications: const [2, 8],
          hasAuthoritativeSpecifications: true,
        ),
      ),
      _synchronizedState(
        manager,
        selectedAlgorithm: Algorithm(
          algorithmIndex: 1,
          guid: selected.guid,
          name: selected.name,
          specifications: selected.specifications,
          hasAuthoritativeSpecifications: true,
        ),
      ),
    ];

    for (final invalidState in invalidStates) {
      cubit.emit(invalidState);
      await expectLater(
        cubit.respecifyAlgorithm(2, const [1, 12]),
        throwsA(isA<AlgorithmRespecificationException>()),
      );
    }

    expect(manager.mutationCommands, isEmpty);
    expect(manager.memoryRequests, 0);
  });

  test(
    'enforces connected confirmed 1.19 owner-provided eligibility at mutation',
    () async {
      final manager = _RecordingManager();
      final ineligibleStates = <DistingState>[
        const DistingState.initial(),
        DistingState.connected(disting: manager),
        _synchronizedState(manager, firmware: '1.18.9'),
        _synchronizedState(manager, firmware: 'unknown'),
        _synchronizedState(manager, offline: true),
        _synchronizedState(manager, demo: true),
      ];

      for (final ineligibleState in ineligibleStates) {
        cubit.emit(ineligibleState);
        await expectLater(
          cubit.respecifyAlgorithm(2, const [1, 12]),
          throwsA(isA<AlgorithmRespecificationException>()),
        );
      }

      expect(ownerProvidedRespecifyMinimumFirmwareVersion, '1.19.0');
      expect(manager.mutationCommands, isEmpty);
      expect(manager.memoryRequests, 0);
    },
  );
}
