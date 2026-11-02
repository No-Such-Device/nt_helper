import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_clipboard_service.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';

class _MockMidiManager extends Mock implements IDistingMidiManager {}

class _RecordingMetadataSyncCubit extends MetadataSyncCubit {
  _RecordingMetadataSyncCubit(super.database);

  FullPresetDetails? capturedTemplate;
  List<int>? capturedIndices;
  IDistingMidiManager? capturedManager;
  int applyCallCount = 0;

  @override
  Future<void> applyTemplateToDevice({
    required FullPresetDetails template,
    required List<int> templateSlotIndices,
    required IDistingMidiManager manager,
  }) async {
    applyCallCount++;
    capturedTemplate = template;
    capturedIndices = templateSlotIndices;
    capturedManager = manager;
    emit(const MetadataSyncState.presetLoadSuccess('injected'));
  }
}

Slot _slot(int index, String guid, String name, {List<ParameterValue> values = const []}) =>
    Slot(
      algorithm: Algorithm(
        algorithmIndex: index,
        guid: guid,
        name: name,
      ),
      routing: RoutingInfo.filler(),
      pages: ParameterPages(algorithmIndex: index, pages: const []),
      parameters: const [],
      values: values,
      enums: const [],
      mappings: const [],
      valueStrings: const [],
    );

DistingStateSynchronized _syncedState(List<Slot> slots) =>
    DistingStateSynchronized(
      disting: _MockMidiManager(),
      distingVersion: '1.10.0',
      firmwareVersion: FirmwareVersion('1.10.0'),
      presetName: 'Source Preset',
      algorithms: const [],
      slots: slots,
      unitStrings: const [],
    );

void main() {
  late AppDatabase database;
  late AlgorithmClipboardService service;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = AlgorithmClipboardService(database);
  });

  tearDown(() async {
    await database.close();
  });

  group('AlgorithmClipboardService.copyFromDistingState', () {
    test('returns 0 when not synchronized', () async {
      final copied = await service.copyFromDistingState(
        const DistingState.initial(),
        [0],
      );
      expect(copied, 0);
      expect(await service.clipboardSlotCount(), 0);
    });

    test('returns 0 for an empty selection', () async {
      final copied = await service.copyFromDistingState(
        _syncedState([_slot(0, 'G1', 'A')]),
        const [],
      );
      expect(copied, 0);
    });

    test('stores slots in ascending source-slot order regardless of click order', () async {
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(guid: 'G1', name: 'A', numSpecifications: 0),
        AlgorithmEntry(guid: 'G2', name: 'B', numSpecifications: 0),
        AlgorithmEntry(guid: 'G3', name: 'C', numSpecifications: 0),
      ]);

      final state = _syncedState([
        _slot(0, 'G1', 'A'),
        _slot(1, 'G2', 'B'),
        _slot(2, 'G3', 'C'),
      ]);

      // Out-of-order and duplicated selection. Signals only flow down the
      // stack, so the clipboard MUST store the source slot order (A, B, C),
      // not the click order (C, A).
      final copied = await service.copyFromDistingState(state, [2, 0, 2, 1]);
      expect(copied, 3);

      final clipboard = await database.presetsDao.getClipboardTemplate();
      expect(clipboard, isNotNull);
      expect(clipboard!.slots.map((s) => s.slot.algorithmGuid).toList(), [
        'G1',
        'G2',
        'G3',
      ]);
      // Reindexed 0..n-1 in the stored clipboard.
      expect(
        clipboard.slots.map((s) => s.slot.slotIndex).toList(),
        [0, 1, 2],
      );
    }, tags: ['regression']);

    test('upserts missing algorithm metadata before persisting', () async {
      final state = _syncedState([_slot(0, 'NEW1', 'New Algo')]);

      final copied = await service.copyFromDistingState(state, [0]);
      expect(copied, 1);

      final stored = await database.metadataDao.getAlgorithmByGuid('NEW1');
      expect(stored, isNotNull);
      expect(stored!.name, 'New Algo');
    });

    test('replacing the clipboard drops previous slots', () async {
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(guid: 'G1', name: 'A', numSpecifications: 0),
        AlgorithmEntry(guid: 'G2', name: 'B', numSpecifications: 0),
      ]);
      final state = _syncedState([
        _slot(0, 'G1', 'A'),
        _slot(1, 'G2', 'B'),
      ]);

      await service.copyFromDistingState(state, [0, 1]);
      expect(await service.clipboardSlotCount(), 2);

      await service.copyFromDistingState(state, [0]);
      expect(await service.clipboardSlotCount(), 1);

      final clipboard = await database.presetsDao.getClipboardTemplate();
      expect(clipboard!.slots.single.slot.algorithmGuid, 'G1');
    });
  });

  group('AlgorithmClipboardService.pasteToCurrentDevice', () {
    test('throws when the clipboard is empty', () async {
      final manager = _MockMidiManager();
      final cubit = _RecordingMetadataSyncCubit(database);
      try {
        await expectLater(
          service.pasteToCurrentDevice(cubit, manager),
          throwsA(isA<StateError>()),
        );
        expect(cubit.applyCallCount, 0);
      } finally {
        await cubit.close();
      }
    });

    test('delegates to applyTemplateToDevice with all clipboard indices',
        () async {
      await database.metadataDao.upsertAlgorithms([
        AlgorithmEntry(guid: 'G1', name: 'A', numSpecifications: 0),
        AlgorithmEntry(guid: 'G2', name: 'B', numSpecifications: 0),
      ]);
      final state = _syncedState([
        _slot(0, 'G1', 'A'),
        _slot(1, 'G2', 'B'),
      ]);
      await service.copyFromDistingState(state, [1, 0]);

      final manager = _MockMidiManager();
      final cubit = _RecordingMetadataSyncCubit(database);
      try {
        await service.pasteToCurrentDevice(cubit, manager);
        expect(cubit.applyCallCount, 1);
        expect(cubit.capturedIndices, [0, 1]);
        expect(cubit.capturedTemplate!.slots.length, 2);
        expect(cubit.capturedManager, same(manager));
      } finally {
        await cubit.close();
      }
    });
  });

  test('describeClipboardCount pluralizes', () {
    expect(describeClipboardCount(1), '1 algorithm');
    expect(describeClipboardCount(3), '3 algorithms');
  });
}
