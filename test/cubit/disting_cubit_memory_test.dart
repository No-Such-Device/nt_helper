import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_display_state.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

final class _ControlledMemoryManager extends Mock
    implements IDistingMidiManager {
  final List<Completer<MemoryUsage?>> memoryResponses = [];
  int catalogueCountRequests = 0;
  int catalogueRecordRequests = 0;
  int memoryRequests = 0;
  int activeMemoryRequests = 0;
  int maximumActiveMemoryRequests = 0;
  int disposeCalls = 0;

  @override
  Future<int?> requestNumberOfAlgorithms() async {
    catalogueCountRequests++;
    return 1;
  }

  @override
  Future<AlgorithmInfo?> requestAlgorithmInfo(int algorithmIndex) async {
    catalogueRecordRequests++;
    return AlgorithmInfo(
      algorithmIndex: algorithmIndex,
      name: 'Test algorithm',
      guid: 'TEST',
      specifications: const [],
    );
  }

  @override
  Future<MemoryUsage?> requestMemoryUsage(MemoryQueryInput input) {
    memoryRequests++;
    activeMemoryRequests++;
    if (activeMemoryRequests > maximumActiveMemoryRequests) {
      maximumActiveMemoryRequests = activeMemoryRequests;
    }

    final response = Completer<MemoryUsage?>();
    memoryResponses.add(response);
    return response.future.whenComplete(() {
      activeMemoryRequests--;
    });
  }

  @override
  void dispose() {
    disposeCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppDatabase database;
  late _MockMetadataDao metadataDao;
  late MockMidiCommand midiCommand;
  late DistingCubit cubit;
  var cubitClosed = false;

  const firstSample = MemoryUsage(
    sram: MemoryPoolUsage(total: 1000, current: 100),
    dram: MemoryPoolUsage(total: 2000, current: 200),
    dtc: MemoryPoolUsage(total: 3000, current: 300),
    itc: MemoryPoolUsage(total: 4000, current: 400),
  );
  const secondSample = MemoryUsage(
    sram: MemoryPoolUsage(total: 1100, current: 110),
    dram: MemoryPoolUsage(total: 2200, current: 220),
    dtc: MemoryPoolUsage(total: 3300, current: 330),
    itc: MemoryPoolUsage(total: 4400, current: 440),
  );

  DistingState synchronizedState(
    IDistingMidiManager manager, {
    String firmware = '1.19.0',
    bool offline = false,
    bool demo = false,
  }) {
    return DistingState.synchronized(
      disting: manager,
      distingVersion: firmware,
      firmwareVersion: FirmwareVersion(firmware),
      presetName: 'Test',
      algorithms: const [],
      slots: const [],
      unitStrings: const [],
      offline: offline,
      demo: demo,
    );
  }

  Future<void> waitForMemoryRequests(
    _ControlledMemoryManager manager,
    int count,
  ) async {
    while (manager.memoryRequests < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    midiCommand = MockMidiCommand();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.hasCachedAlgorithms(),
    ).thenAnswer((_) async => false);
    cubit = DistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: true,
    );
    cubitClosed = false;
  });

  tearDown(() async {
    if (!cubitClosed) {
      await cubit.close();
    }
  });

  test(
    'retains a successful sample while refreshing and after failure',
    () async {
      final manager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(manager));
      final emitted = <MemoryDisplayState>[];
      final subscription = cubit.displayMemoryStateStream.listen(emitted.add);
      addTearDown(subscription.cancel);

      final firstRefresh = cubit.refreshDisplayMemory();
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.refreshing);
      expect(cubit.displayMemoryState.sample, isNull);
      await waitForMemoryRequests(manager, 1);
      manager.memoryResponses[0].complete(firstSample);
      await firstRefresh;

      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.available);
      expect(cubit.displayMemoryState.sample, same(firstSample));

      final failedRefresh = cubit.refreshDisplayMemory();
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.refreshing);
      expect(cubit.displayMemoryState.sample, same(firstSample));
      await waitForMemoryRequests(manager, 2);
      manager.memoryResponses[1].completeError(
        TimeoutException('memory response timed out'),
      );
      await failedRefresh;

      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unfresh);
      expect(cubit.displayMemoryState.sample, same(firstSample));
      expect(cubit.supportsMemoryUsage, isTrue);
      expect(emitted.map((state) => state.status), [
        MemoryDisplayStatus.refreshing,
        MemoryDisplayStatus.available,
        MemoryDisplayStatus.refreshing,
        MemoryDisplayStatus.unfresh,
      ]);
    },
  );

  test(
    'failed first refresh is unavailable and never fabricates a sample',
    () async {
      final manager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(manager));

      final refresh = cubit.refreshDisplayMemory();
      await waitForMemoryRequests(manager, 1);
      manager.memoryResponses.single.complete(null);
      await refresh;

      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
      expect(cubit.displayMemoryState.sample, isNull);
    },
  );

  test('fresh-only failure never falls back to the display sample', () async {
    final manager = _ControlledMemoryManager();
    cubit.emit(synchronizedState(manager));

    final displayRefresh = cubit.refreshDisplayMemory();
    await waitForMemoryRequests(manager, 1);
    manager.memoryResponses[0].complete(firstSample);
    await displayRefresh;

    final freshOnly = cubit.requestFreshMemoryUsage();
    await waitForMemoryRequests(manager, 2);
    manager.memoryResponses[1].completeError(
      TimeoutException('fresh query timed out'),
    );

    await expectLater(freshOnly, throwsA(isA<TimeoutException>()));
    expect(cubit.displayMemoryState.status, MemoryDisplayStatus.available);
    expect(cubit.displayMemoryState.sample, same(firstSample));
    expect(cubit.supportsMemoryUsage, isTrue);
  });

  test('unsupported firmware makes no catalogue or memory request', () async {
    final manager = _ControlledMemoryManager();
    cubit.emit(synchronizedState(manager, firmware: '1.18.9'));

    await cubit.refreshDisplayMemory();
    await expectLater(
      cubit.requestFreshMemoryUsage(),
      throwsA(isA<UnsupportedError>()),
    );

    expect(cubit.supportsMemoryUsage, isFalse);
    expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
    expect(manager.catalogueCountRequests, 0);
    expect(manager.catalogueRecordRequests, 0);
    expect(manager.memoryRequests, 0);
  });

  test(
    'concurrent consumers never overlap same-connection memory requests',
    () async {
      final manager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(manager));

      final displayRefresh = cubit.refreshDisplayMemory();
      final freshOnly = cubit.requestFreshMemoryUsage();
      await waitForMemoryRequests(manager, 1);

      expect(manager.memoryRequests, 1);
      expect(manager.activeMemoryRequests, 1);
      expect(manager.maximumActiveMemoryRequests, 1);

      manager.memoryResponses[0].complete(firstSample);
      await displayRefresh;
      await waitForMemoryRequests(manager, 2);

      expect(manager.activeMemoryRequests, 1);
      expect(manager.maximumActiveMemoryRequests, 1);
      manager.memoryResponses[1].complete(secondSample);

      expect(await freshOnly, same(secondSample));
      expect(manager.maximumActiveMemoryRequests, 1);
    },
  );

  test(
    'a delayed old completion cannot cross a connection replacement',
    () async {
      final firstManager = _ControlledMemoryManager();
      final secondManager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(firstManager));

      final oldRefresh = cubit.refreshDisplayMemory();
      await waitForMemoryRequests(firstManager, 1);

      cubit.emit(synchronizedState(secondManager));
      final newFresh = cubit.requestFreshMemoryUsage();
      await waitForMemoryRequests(secondManager, 1);
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);

      secondManager.memoryResponses.single.complete(secondSample);
      expect(await newFresh, same(secondSample));
      expect(cubit.displayMemoryState.sample, isNull);

      firstManager.memoryResponses.single.complete(firstSample);
      await oldRefresh;
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
      expect(cubit.displayMemoryState.sample, isNull);
      expect(firstManager.maximumActiveMemoryRequests, 1);
      expect(secondManager.maximumActiveMemoryRequests, 1);
    },
  );

  test(
    'an old fresh-only completion fails after connection replacement',
    () async {
      final firstManager = _ControlledMemoryManager();
      final secondManager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(firstManager));

      final oldFresh = cubit.requestFreshMemoryUsage();
      await waitForMemoryRequests(firstManager, 1);
      cubit.emit(synchronizedState(secondManager));
      final newFresh = cubit.requestFreshMemoryUsage();
      await waitForMemoryRequests(secondManager, 1);
      secondManager.memoryResponses.single.complete(secondSample);
      expect(await newFresh, same(secondSample));

      firstManager.memoryResponses.single.complete(firstSample);
      await expectLater(oldFresh, throwsA(isA<StateError>()));
    },
  );

  test(
    'disconnect and offline or demo state discard the remembered sample',
    () async {
      final manager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(manager));

      final refresh = cubit.refreshDisplayMemory();
      await waitForMemoryRequests(manager, 1);
      manager.memoryResponses.single.complete(firstSample);
      await refresh;
      expect(cubit.displayMemoryState.sample, same(firstSample));

      cubit.disconnect();
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
      expect(cubit.displayMemoryState.sample, isNull);

      cubit.emit(synchronizedState(manager));
      final secondRefresh = cubit.refreshDisplayMemory();
      await waitForMemoryRequests(manager, 2);
      manager.memoryResponses[1].complete(secondSample);
      await secondRefresh;

      cubit.emit(synchronizedState(manager, offline: true));
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
      expect(cubit.displayMemoryState.sample, isNull);

      cubit.emit(synchronizedState(manager, demo: true));
      expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
      expect(cubit.displayMemoryState.sample, isNull);
    },
  );

  test(
    'does not query on connection, listener attachment, or elapsed time',
    () {
      final manager = _ControlledMemoryManager();
      cubit.emit(synchronizedState(manager));

      fakeAsync((async) {
        final subscription = cubit.displayMemoryStateStream.listen((_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(hours: 24));
        async.flushMicrotasks();
        subscription.cancel();
      });

      expect(manager.catalogueCountRequests, 0);
      expect(manager.catalogueRecordRequests, 0);
      expect(manager.memoryRequests, 0);
    },
  );

  test('close discards the sample and ignores a pending completion', () async {
    final manager = _ControlledMemoryManager();
    cubit.emit(synchronizedState(manager));

    final refresh = cubit.refreshDisplayMemory();
    await waitForMemoryRequests(manager, 1);
    await cubit.close();
    cubitClosed = true;

    expect(cubit.displayMemoryState.status, MemoryDisplayStatus.unavailable);
    expect(cubit.displayMemoryState.sample, isNull);

    manager.memoryResponses.single.complete(firstSample);
    await refresh;
    expect(cubit.displayMemoryState.sample, isNull);
  });
}
