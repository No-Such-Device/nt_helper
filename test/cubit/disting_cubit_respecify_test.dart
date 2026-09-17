import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/memory_query_input.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_info_response.dart';
import 'package:nt_helper/domain/sysex/responses/algorithm_response.dart';
import 'package:nt_helper/models/algorithm_respecification.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/memory_usage.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

final class _TestDistingCubit extends DistingCubit {
  _TestDistingCubit(
    super.database, {
    super.midiCommand,
    super.isWindowsOverride,
  });

  Future<Slot> Function(IDistingMidiManager disting, int algorithmIndex)?
  fetchSlotOverride;

  @override
  Future<Slot> fetchSlot(IDistingMidiManager disting, int algorithmIndex) {
    final override = fetchSlotOverride;
    if (override != null) return override(disting, algorithmIndex);
    return super.fetchSlot(disting, algorithmIndex);
  }
}

final class _RecordingManager extends Mock
    implements IDistingMidiManager, AlgorithmRespecificationWriter {
  _RecordingManager({this.onRequestAlgorithm, this.onRequestRouting});

  final Future<Algorithm?> Function(int requestNumber)? onRequestAlgorithm;
  final Future<RoutingInfo?> Function(int algorithmIndex)? onRequestRouting;
  final List<String> mutationCommands = [];
  final List<int> respecifiedSlots = [];
  final List<List<int>> respecifiedValues = [];
  final List<int> readbackSlots = [];
  final List<Duration?> readbackTimeouts = [];
  final List<int?> readbackMaxRetries = [];
  final List<bool> readbackRejectAmbiguous = [];
  int activeReadbacks = 0;
  int cancelledReadbacks = 0;
  int memoryRequests = 0;
  final List<int> routingRequests = [];
  final List<String> operationEvents = [];
  bool failRouting = false;
  void Function(int channel, int cc, int value)? _ccCallback;

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
  Future<Algorithm?> requestAlgorithmGuid(
    int algorithmIndex, {
    Duration? timeout,
    int? maxRetries,
    DistingRequestCancellation? cancellation,
    bool rejectAmbiguousResponse = false,
  }) {
    final requestNumber = readbackSlots.length;
    operationEvents.add(
      cancellation == null ? 'hydrate:algorithm' : 'observe:algorithm',
    );
    readbackSlots.add(algorithmIndex);
    readbackTimeouts.add(timeout);
    readbackMaxRetries.add(maxRetries);
    readbackRejectAmbiguous.add(rejectAmbiguousResponse);
    final source = onRequestAlgorithm?.call(requestNumber) ?? Future.value();
    if (cancellation == null) return source;

    activeReadbacks++;
    final completer = Completer<Algorithm?>();
    void Function()? removeCancellationListener;
    void completeValue(Algorithm? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }

    removeCancellationListener = cancellation.addListener(() {
      if (completer.isCompleted) return;
      cancelledReadbacks++;
      completer.completeError(const DistingRequestCancelledException());
    });
    source.then(completeValue, onError: completeError);
    return completer.future.whenComplete(() {
      removeCancellationListener?.call();
      activeReadbacks--;
    });
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
  Future<RoutingInfo?> requestRoutingInformation(int algorithmIndex) async {
    operationEvents.add('routing:$algorithmIndex');
    routingRequests.add(algorithmIndex);
    if (failRouting) throw StateError('routing failed');
    final override = onRequestRouting;
    if (override != null) return override(algorithmIndex);
    return RoutingInfo(
      algorithmIndex: algorithmIndex,
      routingInfo: List<int>.filled(6, algorithmIndex + 1),
    );
  }

  @override
  void setCcCallback(void Function(int channel, int cc, int value)? callback) {
    _ccCallback = callback;
  }

  @override
  void clearCcCallback() {
    _ccCallback = null;
  }

  void emitCc(int channel, int cc, int value) {
    _ccCallback?.call(channel, cc, value);
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

Slot _hydratedSlot({
  List<int> specifications = const [1, 12],
  RoutingInfo? routing,
}) {
  final mapping = Mapping(
    algorithmIndex: 2,
    parameterNumber: 0,
    packedMappingData: PackedMappingData.filler().copyWith(
      version: 6,
      midiChannel: 2,
      midiCC: 74,
      isMidiEnabled: true,
      midiMin: 0,
      midiMax: 127,
    ),
  );
  return Slot(
    algorithm: _fixtureSlotAlgorithm().copyWith(
      specifications: specifications,
      hasAuthoritativeSpecifications: true,
    ),
    routing: routing ?? RoutingInfo.filler(),
    pages: ParameterPages(
      algorithmIndex: 2,
      pages: [
        ParameterPage(name: 'Main', parameters: const [0]),
      ],
    ),
    parameters: [
      ParameterInfo(
        algorithmIndex: 2,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 50,
        unit: 1,
        name: 'Device parameter',
        powerOfTen: 0,
      ),
    ],
    values: [ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 25)],
    enums: [
      ParameterEnumStrings(
        algorithmIndex: 2,
        parameterNumber: 0,
        values: const ['Low', 'High'],
      ),
    ],
    mappings: [mapping],
    valueStrings: [ParameterValueString.filler()],
    parameterCountFromDevice: true,
    parameterPagesFromDevice: true,
    parameterValuesFromDevice: true,
  );
}

FullAlgorithmDetails _cachedSingleParameterMetadata() => FullAlgorithmDetails(
  algorithm: const AlgorithmEntry(
    guid: 'TEST',
    name: 'Fixture algorithm',
    numSpecifications: 2,
  ),
  specifications: const [],
  parameters: const [],
  parameterPages: [
    ParameterPageWithItems(
      page: const ParameterPageEntry(
        algorithmGuid: 'TEST',
        pageIndex: 0,
        name: 'Cached page',
      ),
      parameterNumbers: const [0],
    ),
  ],
  enums: const {},
);

void _stubSingleParameterHydration(
  _RecordingManager manager, {
  required Future<ParameterPages?> Function() requestPages,
}) {
  when(
    () => manager.requestNumberOfParameters(2),
  ).thenAnswer((_) async => NumParameters(algorithmIndex: 2, numParameters: 1));
  when(
    () => manager.requestParameterPages(2),
  ).thenAnswer((_) => requestPages());
  when(() => manager.requestAllParameterValues(2)).thenAnswer(
    (_) async => AllParameterValues(
      algorithmIndex: 2,
      values: [
        ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 25),
      ],
    ),
  );
  when(() => manager.requestParameterInfo(2, 0)).thenAnswer(
    (_) async => ParameterInfo(
      algorithmIndex: 2,
      parameterNumber: 0,
      min: 0,
      max: 100,
      defaultValue: 50,
      unit: -1,
      name: 'Device parameter',
      powerOfTen: 0,
    ),
  );
}

DistingStateSynchronized _synchronizedState(
  IDistingMidiManager manager, {
  String firmware = '1.19beta',
  bool offline = false,
  bool demo = false,
  Algorithm? selectedAlgorithm,
  Slot? selectedSlot,
  List<AlgorithmInfo>? algorithms,
  MidiDevice? inputDevice,
  MidiDevice? outputDevice,
}) {
  final selected =
      selectedSlot?.algorithm ?? selectedAlgorithm ?? _fixtureSlotAlgorithm();
  return DistingState.synchronized(
        disting: manager,
        distingVersion: firmware,
        firmwareVersion: FirmwareVersion(firmware),
        presetName: 'Fixture preset',
        algorithms: algorithms ?? [_fixtureAlgorithmInfo()],
        slots: [
          _slot(Algorithm(algorithmIndex: 0, guid: 'ONE ', name: 'First')),
          _slot(Algorithm(algorithmIndex: 1, guid: 'TWO ', name: 'Second')),
          selectedSlot ?? _slot(selected),
        ],
        unitStrings: const [],
        inputDevice: inputDevice,
        outputDevice: outputDevice,
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
  late _TestDistingCubit cubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    midiCommand = MockMidiCommand();
    when(() => database.metadataDao).thenReturn(metadataDao);
    when(
      () => metadataDao.getFullAlgorithmDetails(any()),
    ).thenAnswer((_) async => null);
    cubit = _TestDistingCubit(
      database,
      midiCommand: midiCommand,
      isWindowsOverride: true,
    );
  });

  tearDown(() => cubit.close());

  test(
    'null page response without metadata cannot verify or install hydration',
    () {
      fakeAsync((async) {
        final manager = _RecordingManager(
          onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
            specifications: const [1, 12],
            hasAuthoritativeSpecifications: true,
          ),
        );
        _stubSingleParameterHydration(manager, requestPages: () async => null);
        final initialState = _synchronizedState(manager);
        cubit.emit(initialState);

        AlgorithmRespecificationStatus? status;
        cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
          status = value;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(status, AlgorithmRespecificationStatus.refreshIncomplete);
        expect(cubit.state, same(initialState));
        expect(manager.routingRequests, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('failed page response with cached metadata cannot verify or install '
      'hydration', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      _stubSingleParameterHydration(
        manager,
        requestPages: () async => throw StateError('pages unavailable'),
      );
      when(
        () => metadataDao.getFullAlgorithmDetails('TEST'),
      ).thenAnswer((_) async => _cachedSingleParameterMetadata());
      final initialState = _synchronizedState(manager);
      cubit.emit(initialState);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshIncomplete);
      expect(cubit.state, same(initialState));
      expect(manager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('ordinary refresh still installs cached page fallback', () async {
    final manager = _RecordingManager(
      onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
        specifications: const [1, 12],
        hasAuthoritativeSpecifications: true,
      ),
    );
    _stubSingleParameterHydration(
      manager,
      requestPages: () async => throw StateError('pages unavailable'),
    );
    when(
      () => metadataDao.getFullAlgorithmDetails('TEST'),
    ).thenAnswer((_) async => _cachedSingleParameterMetadata());
    final initialState = _synchronizedState(manager);
    cubit.emit(initialState);

    await cubit.refreshSlot(2);

    final refreshedState = cubit.state as DistingStateSynchronized;
    expect(refreshedState, isNot(same(initialState)));
    expect(refreshedState.slots[2].pages.pages.single.name, 'Cached page');
    expect(refreshedState.slots[2].parameters.single.name, 'Device parameter');
    expect(manager.routingRequests, isEmpty);
  });

  test('missing parameter count and values cannot verify empty hydration', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      _stubSingleParameterHydration(
        manager,
        requestPages: () async =>
            ParameterPages(algorithmIndex: 2, pages: const []),
      );
      when(
        () => manager.requestNumberOfParameters(2),
      ).thenAnswer((_) async => null);
      when(
        () => manager.requestAllParameterValues(2),
      ).thenAnswer((_) async => null);
      final initialState = _synchronizedState(manager);
      cubit.emit(initialState);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshIncomplete);
      expect(cubit.state, same(initialState));
      expect(manager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('device-returned empty pages remain valid hydration', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      _stubSingleParameterHydration(
        manager,
        requestPages: () async =>
            ParameterPages(algorithmIndex: 2, pages: const []),
      );
      final initialState = _synchronizedState(manager);
      cubit.emit(initialState);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.observedMatchingState);
      expect(cubit.state, isNot(same(initialState)));
      expect(manager.routingRequests, [0, 1, 2]);
      expect(
        (cubit.state as DistingStateSynchronized)
            .slots[2]
            .parameters
            .single
            .name,
        'Device parameter',
      );
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'waits for installed hydration before routing and verified completion',
    () {
      fakeAsync((async) {
        final hydration = Completer<Slot>();
        final manager = _RecordingManager(
          onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
            specifications: const [1, 12],
            hasAuthoritativeSpecifications: true,
          ),
        );
        cubit.fetchSlotOverride = (disting, algorithmIndex) {
          expect(disting, same(manager));
          expect(algorithmIndex, 2);
          manager.operationEvents.add('hydrate:start');
          return hydration.future.then((slot) {
            manager.operationEvents.add('hydrate:done');
            return slot;
          });
        };
        cubit.emit(_synchronizedState(manager));

        AlgorithmRespecificationStatus? status;
        cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
          status = value;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(status, isNull);
        expect(manager.routingRequests, isEmpty);

        hydration.complete(_hydratedSlot());
        async.flushMicrotasks();

        expect(status, AlgorithmRespecificationStatus.observedMatchingState);
        expect(manager.routingRequests, [0, 1, 2]);
        expect(manager.operationEvents, [
          'observe:algorithm',
          'hydrate:start',
          'hydrate:done',
          'routing:0',
          'routing:1',
          'routing:2',
        ]);
        final slot = (cubit.state as DistingStateSynchronized).slots[2];
        expect(slot.parameters.single.name, 'Device parameter');
        expect(slot.values.single.value, 25);
        expect(slot.enums.single.values, const ['Low', 'High']);
        expect(slot.mappings.single.packedMappingData.midiCC, 74);
        expect(slot.routing.routingInfo, List<int>.filled(6, 3));
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('disconnect cancels polling and releases the operation', () {
    fakeAsync((async) {
      final pendingReadback = Completer<Algorithm?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) => pendingReadback.future,
      );
      final initialState = _synchronizedState(manager);
      cubit.emit(initialState);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(manager.activeReadbacks, 1);

      cubit.disconnect();
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.cancelledReadbacks, 1);
      expect(manager.mutationCommands, ['respecify']);
      expect(manager.routingRequests, isEmpty);
      expect(cubit.state, same(initialState));

      pendingReadback.complete(
        _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      async.flushMicrotasks();
      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('another manager and device reject a late polling reply', () {
    fakeAsync((async) {
      final pendingReadback = Completer<Algorithm?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) => pendingReadback.future,
      );
      final originalInput = MidiDevice(
        'old-input',
        'Disting NT',
        MidiDeviceType.serial,
        true,
      );
      final originalOutput = MidiDevice(
        'old-output',
        'Disting NT',
        MidiDeviceType.serial,
        true,
      );
      cubit.emit(
        _synchronizedState(
          manager,
          inputDevice: originalInput,
          outputDevice: originalOutput,
        ),
      );

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(manager.activeReadbacks, 1);

      final replacementManager = _RecordingManager();
      final replacementState = _synchronizedState(
        replacementManager,
        inputDevice: MidiDevice(
          'new-input',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        ),
        outputDevice: MidiDevice(
          'new-output',
          'Disting NT',
          MidiDeviceType.serial,
          true,
        ),
      );
      cubit.emit(replacementState);
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.cancelledReadbacks, 1);
      expect(cubit.state, same(replacementState));

      pendingReadback.complete(
        _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      async.flushMicrotasks();
      expect(cubit.state, same(replacementState));
      expect(manager.routingRequests, isEmpty);
      expect(replacementManager.mutationCommands, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('cancelled hydration cannot overwrite output-mode cache', () {
    fakeAsync((async) {
      final outputModeUsage = Completer<OutputModeUsage?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      when(() => manager.requestNumberOfParameters(2)).thenAnswer(
        (_) async => NumParameters(algorithmIndex: 2, numParameters: 1),
      );
      when(() => manager.requestParameterPages(2)).thenAnswer(
        (_) async => ParameterPages(
          algorithmIndex: 2,
          pages: [
            ParameterPage(name: 'Main', parameters: const [0]),
          ],
        ),
      );
      when(() => manager.requestAllParameterValues(2)).thenAnswer(
        (_) async => AllParameterValues(
          algorithmIndex: 2,
          values: [
            ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 0),
          ],
        ),
      );
      when(() => manager.requestParameterInfo(2, 0)).thenAnswer(
        (_) async => ParameterInfo(
          algorithmIndex: 2,
          parameterNumber: 0,
          min: 0,
          max: 1,
          defaultValue: 0,
          unit: -1,
          name: 'Output mode',
          powerOfTen: 0,
          ioFlags: 8,
        ),
      );
      when(
        () => manager.requestOutputModeUsage(2, 0),
      ).thenAnswer((_) => outputModeUsage.future);
      when(() => manager.requestParameterValue(2, 0)).thenAnswer(
        (_) async =>
            ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 1),
      );

      final seededSlot = _hydratedSlot().copyWith(
        outputModeMap: const {
          0: [7],
        },
      );
      cubit.fetchSlotOverride = (_, _) async => seededSlot;
      cubit.emit(_synchronizedState(manager, selectedSlot: seededSlot));
      var seeded = false;
      cubit.refreshSlot(2).then((_) => seeded = true);
      async.flushMicrotasks();
      expect(seeded, isTrue);
      expect(cubit.getSlotOutputModeUsage(2), const {
        0: [7],
      });
      cubit.fetchSlotOverride = null;

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(status, isNull);

      final replacementManager = _RecordingManager();
      final replacementState = _synchronizedState(replacementManager);
      cubit.emit(replacementState);
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshSkipped);
      expect(cubit.state, same(replacementState));
      expect(cubit.getSlotOutputModeUsage(2), const {
        0: [7],
      });

      outputModeUsage.complete(
        OutputModeUsage(
          algorithmIndex: 2,
          parameterNumber: 0,
          affectedParameterNumbers: const [0],
        ),
      );
      async.flushMicrotasks();

      expect(cubit.state, same(replacementState));
      expect(cubit.getSlotOutputModeUsage(2), const {
        0: [7],
      });
      expect(manager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('cancelled hydration discards queued shape retries', () {
    fakeAsync((async) {
      final lateParameterInfo = Completer<ParameterInfo?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      when(() => manager.requestNumberOfParameters(2)).thenAnswer(
        (_) async => NumParameters(algorithmIndex: 2, numParameters: 2),
      );
      when(() => manager.requestParameterPages(2)).thenAnswer(
        (_) async => ParameterPages(
          algorithmIndex: 2,
          pages: [
            ParameterPage(name: 'Main', parameters: const [0, 1]),
          ],
        ),
      );
      when(() => manager.requestAllParameterValues(2)).thenAnswer(
        (_) async => AllParameterValues(
          algorithmIndex: 2,
          values: [
            ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 0),
            ParameterValue(algorithmIndex: 2, parameterNumber: 1, value: 0),
          ],
        ),
      );
      when(
        () => manager.requestParameterInfo(2, 0),
      ).thenAnswer((_) async => null);
      when(
        () => manager.requestParameterInfo(2, 1),
      ).thenAnswer((_) => lateParameterInfo.future);
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, isNull);
      expect(cubit.pendingParameterRetryCount, 1);

      final replacementManager = _RecordingManager();
      final replacementState = _synchronizedState(replacementManager);
      cubit.emit(replacementState);
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshSkipped);
      expect(cubit.pendingParameterRetryCount, 0);
      expect(cubit.state, same(replacementState));

      lateParameterInfo.complete();
      async.flushMicrotasks();

      expect(cubit.pendingParameterRetryCount, 0);
      expect(cubit.state, same(replacementState));
      expect(manager.routingRequests, isEmpty);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('late routing cannot update a replacement connection', () {
    fakeAsync((async) {
      final routing = List.generate(3, (_) => Completer<RoutingInfo?>());
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
        onRequestRouting: (algorithmIndex) => routing[algorithmIndex].future,
      );
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot();
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, isNull);
      expect(manager.routingRequests, [0, 1, 2]);

      final replacementManager = _RecordingManager();
      final replacementState = _synchronizedState(replacementManager);
      cubit.emit(replacementState);
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshSkipped);
      expect(cubit.state, same(replacementState));

      for (var index = 0; index < routing.length; index++) {
        routing[index].complete(
          RoutingInfo(
            algorithmIndex: index,
            routingInfo: List<int>.filled(6, 99),
          ),
        );
      }
      async.flushMicrotasks();

      expect(cubit.state, same(replacementState));
      expect(
        (cubit.state as DistingStateSynchronized).slots.map(
          (slot) => slot.routing.routingInfo,
        ),
        everyElement(isNot(List<int>.filled(6, 99))),
      );
      expect(replacementManager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('does not report verified completion for incomplete hydration', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      final initialState = _synchronizedState(manager);
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot().copyWith(
        parameters: [ParameterInfo.filler()],
        values: [ParameterValue.filler()],
        enums: [ParameterEnumStrings.filler()],
        mappings: [Mapping.filler()],
      );
      cubit.emit(initialState);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.refreshIncomplete);
      expect(cubit.state, same(initialState));
      expect(manager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('distinguishes failed and skipped hydration from completion', () {
    fakeAsync((async) {
      final failedManager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      failedManager.failRouting = true;
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot();
      cubit.emit(_synchronizedState(failedManager));

      AlgorithmRespecificationStatus? failedStatus;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        failedStatus = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(failedStatus, AlgorithmRespecificationStatus.refreshFailed);
      expect(failedManager.routingRequests, [0, 1, 2]);

      final skippedHydration = Completer<Slot>();
      final skippedManager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      cubit.fetchSlotOverride = (_, _) => skippedHydration.future;
      cubit.emit(_synchronizedState(skippedManager));

      AlgorithmRespecificationStatus? skippedStatus;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        skippedStatus = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(skippedStatus, isNull);

      final replacementBase = _synchronizedState(skippedManager);
      final replacementSlots = List<Slot>.from(replacementBase.slots);
      final replacedAlgorithm = replacementSlots[2].algorithm;
      replacementSlots[2] = replacementSlots[2].copyWith(
        algorithm: Algorithm(
          algorithmIndex: replacedAlgorithm.algorithmIndex,
          guid: 'NEXT',
          name: replacedAlgorithm.name,
          specifications: replacedAlgorithm.specifications,
          hasAuthoritativeSpecifications:
              replacedAlgorithm.hasAuthoritativeSpecifications,
          visualStyle: replacedAlgorithm.visualStyle,
        ),
      );
      final replacementState = replacementBase.copyWith(
        slots: replacementSlots,
      );
      cubit.emit(replacementState);
      skippedHydration.complete(_hydratedSlot());
      async.flushMicrotasks();

      expect(skippedStatus, AlgorithmRespecificationStatus.refreshSkipped);
      expect(cubit.state, same(replacementState));
      expect(skippedManager.routingRequests, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('real hydration replaces device collections, rebuilds CC lookup, and '
      'finishes before routing', () {
    fakeAsync((async) {
      final valueStringResult = Completer<ParameterValueString?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      final enumParameter = ParameterInfo(
        algorithmIndex: 2,
        parameterNumber: 0,
        min: 0,
        max: 100,
        defaultValue: 40,
        unit: 1,
        name: 'Device enum',
        powerOfTen: 0,
      );
      final stringParameter = ParameterInfo(
        algorithmIndex: 2,
        parameterNumber: 1,
        min: 0,
        max: 10,
        defaultValue: 3,
        unit: 16,
        name: 'Device string',
        powerOfTen: 0,
      );
      final ccMapping = Mapping(
        algorithmIndex: 2,
        parameterNumber: 0,
        packedMappingData: PackedMappingData.filler().copyWith(
          version: 6,
          midiChannel: 2,
          midiCC: 74,
          isMidiEnabled: true,
          midiMin: 0,
          midiMax: 127,
        ),
      );
      final disabledMapping = Mapping(
        algorithmIndex: 2,
        parameterNumber: 1,
        packedMappingData: PackedMappingData.filler().copyWith(
          version: 6,
          midiChannel: 0,
          midiCC: 1,
          isMidiEnabled: false,
          midiMin: 0,
          midiMax: 127,
        ),
      );

      when(() => manager.requestNumberOfParameters(2)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:count');
        return NumParameters(algorithmIndex: 2, numParameters: 2);
      });
      when(() => manager.requestParameterPages(2)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:pages');
        return ParameterPages(
          algorithmIndex: 2,
          pages: [
            ParameterPage(name: 'Device page', parameters: const [0, 1]),
          ],
        );
      });
      when(() => manager.requestAllParameterValues(2)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:values');
        return AllParameterValues(
          algorithmIndex: 2,
          values: [
            ParameterValue(algorithmIndex: 2, parameterNumber: 0, value: 25),
            ParameterValue(algorithmIndex: 2, parameterNumber: 1, value: 7),
          ],
        );
      });
      when(() => manager.requestParameterInfo(2, 0)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:info:0');
        return enumParameter;
      });
      when(() => manager.requestParameterInfo(2, 1)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:info:1');
        return stringParameter;
      });
      when(() => manager.requestParameterEnumStrings(2, 0)).thenAnswer((
        _,
      ) async {
        manager.operationEvents.add('hydrate:enums:0');
        return ParameterEnumStrings(
          algorithmIndex: 2,
          parameterNumber: 0,
          values: const ['Device low', 'Device high'],
        );
      });
      when(() => manager.requestMappings(2, 0)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:mapping:0');
        return ccMapping;
      });
      when(() => manager.requestMappings(2, 1)).thenAnswer((_) async {
        manager.operationEvents.add('hydrate:mapping:1');
        return disabledMapping;
      });
      when(() => manager.requestParameterValueString(2, 1)).thenAnswer((_) {
        manager.operationEvents.add('hydrate:string:1');
        return valueStringResult.future.then((value) {
          manager.operationEvents.add('hydrate:string:done');
          return value;
        });
      });

      final staleSlot =
          _hydratedSlot(
            specifications: const [-1, 8],
            routing: RoutingInfo(
              algorithmIndex: 2,
              routingInfo: List<int>.filled(6, 99),
            ),
          ).copyWith(
            mappings: [
              Mapping(
                algorithmIndex: 2,
                parameterNumber: 0,
                packedMappingData: PackedMappingData.filler().copyWith(
                  version: 6,
                  midiChannel: 2,
                  midiCC: 10,
                  isMidiEnabled: true,
                  midiMin: 0,
                  midiMax: 127,
                ),
              ),
            ],
            outputModeMap: const {
              0: [0],
            },
          );
      cubit.emit(_synchronizedState(manager, selectedSlot: staleSlot));
      cubit.fetchSlotOverride = (_, _) async => staleSlot;
      var seededShapeState = false;
      cubit.refreshSlot(2).then((_) => seededShapeState = true);
      async.flushMicrotasks();
      expect(seededShapeState, isTrue);
      expect(cubit.getSlotOutputModeUsage(2), const {
        0: [0],
      });
      cubit.fetchSlotOverride = null;

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, isNull);
      expect(manager.routingRequests, isEmpty);
      expect(manager.operationEvents, contains('hydrate:string:1'));

      valueStringResult.complete(
        ParameterValueString(
          algorithmIndex: 2,
          parameterNumber: 1,
          value: 'device value',
        ),
      );
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.observedMatchingState);
      expect(manager.routingRequests, [0, 1, 2]);
      expect(
        manager.operationEvents.indexOf('routing:0'),
        greaterThan(manager.operationEvents.indexOf('hydrate:string:done')),
      );

      final hydrated = (cubit.state as DistingStateSynchronized).slots[2];
      expect(hydrated.algorithm.specifications, const [1, 12]);
      expect(hydrated.algorithm.hasAuthoritativeSpecifications, isTrue);
      expect(hydrated.pages.pages.single.parameters, const [0, 1]);
      expect(hydrated.parameters, [enumParameter, stringParameter]);
      expect(hydrated.values.map((value) => value.value), [25, 7]);
      expect(hydrated.enums.first.values, const ['Device low', 'Device high']);
      expect(hydrated.mappings, [ccMapping, disabledMapping]);
      expect(hydrated.valueStrings[1].value, 'device value');
      expect(hydrated.outputModeMap, isEmpty);
      expect(hydrated.routing.routingInfo, List<int>.filled(6, 3));

      manager.emitCc(2, 10, 0);
      expect(
        (cubit.state as DistingStateSynchronized).slots[2].values[0].value,
        25,
      );
      manager.emitCc(2, 74, 127);
      expect(
        (cubit.state as DistingStateSynchronized).slots[2].values[0].value,
        100,
      );
      async.elapse(const Duration(milliseconds: 200));
      async.flushMicrotasks();
      expect(
        (cubit.state as DistingStateSynchronized).slots[2].routing.routingInfo,
        List<int>.filled(6, 3),
      );
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('uses decoded metadata, sends 0x3A once, and waits one second for '
      'matching fresh 0x40 state', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      final synchronized = _synchronizedState(manager);
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot();
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

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();

      expect(status, isNull, reason: 'send completion is not success');
      expect(manager.mutationCommands, ['respecify']);
      expect(manager.respecifiedSlots, [2]);
      expect(manager.respecifiedValues, [
        [1, 12],
      ]);
      expect(manager.readbackSlots, isEmpty);

      async.elapse(const Duration(milliseconds: 999));
      expect(manager.readbackSlots, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.observedMatchingState);
      expect(manager.readbackSlots, [2]);
      expect(manager.readbackTimeouts, [const Duration(seconds: 1)]);
      expect(manager.readbackMaxRetries, [1]);
      expect(manager.readbackRejectAmbiguous, [isTrue]);
      expect(manager.memoryRequests, 0);
      expect(cubit.state, isNot(same(synchronized)));
      expect(manager.routingRequests, [0, 1, 2]);
      expect(
        (cubit.state as DistingStateSynchronized).slots.map(
          (slot) => slot.algorithm.guid,
        ),
        ['ONE ', 'TWO ', 'TEST'],
      );
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('accepts matching state after fractional response latency', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) => Future<Algorithm?>.delayed(
          const Duration(milliseconds: 250),
          () => _fixtureSlotAlgorithm().copyWith(
            specifications: const [1, 12],
            hasAuthoritativeSpecifications: true,
          ),
        ),
      );
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot();
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(manager.readbackSlots, [2]);
      expect(manager.activeReadbacks, 1);
      expect(status, isNull);

      async.elapse(const Duration(milliseconds: 249));
      async.flushMicrotasks();
      expect(status, isNull);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.observedMatchingState);
      expect(manager.activeReadbacks, 0);
      expect(manager.cancelledReadbacks, 0);
      expect(manager.readbackRejectAmbiguous, [isTrue]);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('deadline cancels a polling delay that would span ten seconds', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) => Future<Algorithm?>.delayed(
          const Duration(milliseconds: 400),
          () => null,
        ),
      );
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.readbackSlots, [2, 2, 2, 2, 2, 2, 2]);
      expect(manager.activeReadbacks, 0);
      expect(manager.cancelledReadbacks, 0);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);

      final sendsAtDeadline = manager.readbackSlots.length;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(manager.readbackSlots, hasLength(sendsAtDeadline));
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('deadline cancels an in-flight readback without later sends', () {
    fakeAsync((async) {
      final pendingReadback = Completer<Algorithm?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) => pendingReadback.future,
      );
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(manager.readbackSlots, [2]);
      expect(manager.activeReadbacks, 1);
      expect(status, isNull);

      async.elapse(const Duration(seconds: 9));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.activeReadbacks, 0);
      expect(manager.cancelledReadbacks, 1);
      expect(manager.readbackSlots, [2]);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(manager.readbackSlots, [2]);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('polls at one-second intervals and exposes differing fresh state', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (requestNumber) async {
          if (requestNumber == 0) return null;
          return _fixtureSlotAlgorithm().copyWith(
            specifications: const [0, 8],
            hasAuthoritativeSpecifications: true,
          );
        },
      );
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(manager.readbackSlots, [2]);
      expect(status, isNull);

      async.elapse(const Duration(milliseconds: 999));
      expect(manager.readbackSlots, [2]);
      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(manager.readbackSlots, [2, 2]);
      expect(manager.readbackTimeouts, [
        const Duration(seconds: 1),
        const Duration(seconds: 1),
      ]);
      expect(manager.readbackMaxRetries, [1, 1]);
      expect(status, AlgorithmRespecificationStatus.observedDifferingState);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test(
    'ambiguous stale readback cannot become matching or differing state',
    () {
      fakeAsync((async) {
        final manager = _RecordingManager(
          onRequestAlgorithm: (_) =>
              Future<Algorithm?>.error(AmbiguousResponseAttributionException()),
        );
        cubit.emit(_synchronizedState(manager));

        AlgorithmRespecificationStatus? status;
        cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
          status = value;
        });
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(status, AlgorithmRespecificationStatus.unverifiable);
        expect(manager.readbackSlots, isNotEmpty);
        expect(manager.readbackRejectAmbiguous, everyElement(isTrue));
        expect(manager.mutationCommands, ['respecify']);
        expect(async.pendingTimers, isEmpty);
      });
    },
  );

  test('missing, malformed, cached, wrong-target, and late data cannot become '
      'a valid observation', () {
    fakeAsync((async) {
      final lateReadback = Completer<Algorithm?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (requestNumber) {
          return switch (requestNumber) {
            0 => Future<Algorithm?>.value(),
            1 => Future<Algorithm?>.error(
              const FormatException('malformed extended response'),
            ),
            2 => Future<Algorithm?>.value(
              _fixtureSlotAlgorithm().copyWith(
                specifications: const [1, 12],
                hasAuthoritativeSpecifications: false,
              ),
            ),
            3 => Future<Algorithm?>.value(
              _fixtureSlotAlgorithm().copyWith(
                algorithmIndex: 1,
                specifications: const [1, 12],
                hasAuthoritativeSpecifications: true,
              ),
            ),
            4 => Future<Algorithm?>.value(
              Algorithm(
                algorithmIndex: 2,
                guid: 'NOPE',
                name: 'Wrong algorithm',
                specifications: const [1, 12],
                hasAuthoritativeSpecifications: true,
              ),
            ),
            _ => lateReadback.future,
          };
        },
      );
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        status = value;
      });
      async.flushMicrotasks();

      for (var second = 1; second <= 6; second++) {
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
      }
      expect(manager.readbackSlots, [2, 2, 2, 2, 2, 2]);
      expect(status, isNull);

      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(manager.mutationCommands, ['respecify']);

      lateReadback.complete(
        _fixtureSlotAlgorithm().copyWith(
          specifications: const [1, 12],
          hasAuthoritativeSpecifications: true,
        ),
      );
      async.flushMicrotasks();
      expect(status, AlgorithmRespecificationStatus.unverifiable);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('suppresses duplicate submissions until the bounded operation ends', () {
    fakeAsync((async) {
      final pendingReadback = Completer<Algorithm?>();
      final manager = _RecordingManager(
        onRequestAlgorithm: (requestNumber) => requestNumber == 0
            ? pendingReadback.future
            : Future<Algorithm?>.value(
                _fixtureSlotAlgorithm().copyWith(
                  specifications: const [1, 12],
                  hasAuthoritativeSpecifications: true,
                ),
              ),
      );
      cubit.fetchSlotOverride = (_, _) async => _hydratedSlot();
      cubit.emit(_synchronizedState(manager));

      AlgorithmRespecificationStatus? firstStatus;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        firstStatus = value;
      });
      async.flushMicrotasks();

      Object? duplicateError;
      cubit.respecifyAlgorithm(2, const [1, 12]).catchError((Object error) {
        duplicateError = error;
        return AlgorithmRespecificationStatus.unverifiable;
      });
      async.flushMicrotasks();

      expect(duplicateError, isA<AlgorithmRespecificationException>());
      expect(manager.mutationCommands, ['respecify']);

      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      expect(firstStatus, AlgorithmRespecificationStatus.unverifiable);

      AlgorithmRespecificationStatus? nextStatus;
      cubit.respecifyAlgorithm(2, const [1, 12]).then((value) {
        nextStatus = value;
      });
      async.flushMicrotasks();
      expect(manager.mutationCommands, ['respecify', 'respecify']);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(nextStatus, AlgorithmRespecificationStatus.observedMatchingState);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('matching unchanged values still hydrate authoritative state', () {
    fakeAsync((async) {
      final manager = _RecordingManager(
        onRequestAlgorithm: (_) async => _fixtureSlotAlgorithm(),
      );
      final synchronized = _synchronizedState(manager);
      cubit.fetchSlotOverride = (_, _) async =>
          _hydratedSlot(specifications: const [-1, 8]);
      cubit.emit(synchronized);

      AlgorithmRespecificationStatus? status;
      cubit.respecifyAlgorithm(2, const [-1, 8]).then((value) {
        status = value;
      });
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(status, AlgorithmRespecificationStatus.observedMatchingState);
      expect(cubit.state, isNot(same(synchronized)));
      expect(manager.routingRequests, [0, 1, 2]);
      expect(manager.mutationCommands, ['respecify']);
      expect(async.pendingTimers, isEmpty);
    });
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
