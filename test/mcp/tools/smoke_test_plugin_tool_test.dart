import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/models/allowed_file_root.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/mcp/tools/plugin_tools.dart';
import 'package:nt_helper/models/cpu_usage.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

/// Serves slot hydration from [_FakeNt] instead of the full SysEx sequence.
class _TestCubit extends DistingCubit {
  _TestCubit(super.database, {super.midiCommand});

  late _FakeNt device;

  @override
  Future<Slot> fetchSlot(IDistingMidiManager disting, int algorithmIndex) =>
      Future.value(device.slot(algorithmIndex));

  @override
  Future<List<Slot>> fetchSlots(
    int numAlgorithmsInPreset,
    IDistingMidiManager disting, {
    void Function(int, int)? onSlotProgress,
  }) => Future.value([
    for (var i = 0; i < numAlgorithmsInPreset; i++) device.slot(i),
  ]);
}

const _guid = 'MyFl';
const _pluginFile = '/programs/plug-ins/myfilter.o';

/// A Disting NT preset behind the mocked MIDI manager. Device reads hang
/// while [responding] is false, so the tool's timeouts are exercised.
class _FakeNt {
  _FakeNt({List<String> saved = const ['clck', 'quan']})
    : saved = List.of(saved),
      guids = List.of(saved);

  /// Slot lineup of the preset file on the SD card.
  List<String> saved;

  /// Slot lineup the device is running.
  List<String> guids;

  /// Parameter 0 value of each slot as the device reports it.
  final values = <int, int>{};

  bool responding = true;
  bool acceptAdds = true;
  bool acceptRemoves = true;
  bool reloadFails = false;
  bool loadSucceeds = true;
  bool testSlotAnswersCount = true;
  int testSlotParameters = 2;
  List<String> testSlotNames = const ['Cutoff', 'Resonance'];
  String? testSlotGuid;
  List<int> slotCpu = const [20];
  List<int> coreCpu = const [40];
  bool cpuCoversTestSlot = true;

  /// Runs after an accepted add, for example to go silent.
  void Function()? afterAdd;

  /// Runs on the first read of the test slot, once its add is confirmed.
  void Function()? onChecks;

  /// Runs when a removal is requested, before it is applied.
  void Function()? onRemove;

  int adds = 0;
  int removes = 0;
  int reloads = 0;
  int cpuReads = 0;
  List<int>? addedSpecs;

  int get testIndex => saved.length;

  Future<T?> answer<T>(T? Function() value) =>
      responding ? Future.value(value()) : Completer<T?>().future;

  Slot slot(int i) => Slot(
    algorithm: Algorithm(
      algorithmIndex: i,
      guid: guids[i],
      name: guids[i],
      specifications: const [],
    ),
    routing: RoutingInfo(algorithmIndex: i, routingInfo: List.filled(6, 0)),
    pages: ParameterPages(algorithmIndex: i, pages: const []),
    parameters: [_parameter(i, 0, 'Level')],
    values: [
      ParameterValue(
        algorithmIndex: i,
        parameterNumber: 0,
        value: values[i] ?? 0,
      ),
    ],
    enums: const [],
    mappings: const [],
    valueStrings: const [],
  );

  void _startChecks() {
    final hook = onChecks;
    onChecks = null;
    hook?.call();
  }

  void wire(_MockDistingMidiManager m) {
    when(() => m.requestWake()).thenAnswer((_) async {});
    when(
      () => m.requestNumAlgorithmsInPreset(
        timeout: any(named: 'timeout'),
        maxRetries: any(named: 'maxRetries'),
      ),
    ).thenAnswer((_) => answer(() => guids.length));
    when(() => m.requestPresetName()).thenAnswer((_) => answer(() => 'Test'));
    when(() => m.requestAddAlgorithm(any(), any())).thenAnswer((call) async {
      adds++;
      addedSpecs = List.of(call.positionalArguments[1] as List<int>);
      if (!responding || !acceptAdds) return;
      guids.add((call.positionalArguments[0] as AlgorithmInfo).guid);
      afterAdd?.call();
    });
    when(() => m.requestRemoveAlgorithm(any())).thenAnswer((call) async {
      removes++;
      onRemove?.call();
      if (!responding || !acceptRemoves) return;
      guids.removeAt(call.positionalArguments[0] as int);
    });
    when(
      () => m.requestAlgorithmGuid(
        any(),
        timeout: any(named: 'timeout'),
        maxRetries: any(named: 'maxRetries'),
        cancellation: any(named: 'cancellation'),
        rejectAmbiguousResponse: any(named: 'rejectAmbiguousResponse'),
      ),
    ).thenAnswer((call) {
      final i = call.positionalArguments[0] as int;
      if (i == testIndex) _startChecks();
      return answer(() {
        if (i >= guids.length) return null;
        final guid = i == testIndex ? testSlotGuid ?? guids[i] : guids[i];
        return Algorithm(
          algorithmIndex: i,
          guid: guid,
          name: guid,
          specifications: const [],
        );
      });
    });
    when(() => m.requestNumberOfParameters(any())).thenAnswer((call) {
      final i = call.positionalArguments[0] as int;
      if (i == testIndex) _startChecks();
      if (i == testIndex && !testSlotAnswersCount) {
        return Completer<NumParameters?>().future;
      }
      return answer(
        () => NumParameters(
          algorithmIndex: i,
          numParameters: i == testIndex ? testSlotParameters : 1,
        ),
      );
    });
    when(() => m.requestParameterInfo(any(), any())).thenAnswer((call) {
      final i = call.positionalArguments[0] as int;
      final p = call.positionalArguments[1] as int;
      return answer(() => _parameter(i, p, testSlotNames[p]));
    });
    when(() => m.requestCpuUsage()).thenAnswer((_) {
      final sample = cpuReads++;
      return answer(
        () => CpuUsage(
          cpu1: coreCpu[sample % coreCpu.length],
          cpu2: 10,
          slotUsages: [
            for (var i = 0; i < guids.length; i++)
              if (i != testIndex || cpuCoversTestSlot)
                i == testIndex ? slotCpu[sample % slotCpu.length] : 5,
          ],
        ),
      );
    });
    when(() => m.requestLoadPreset(any(), any())).thenAnswer((_) async {
      reloads++;
      if (reloadFails) throw StateError('SD card busy');
      if (!responding) return Completer<void>().future;
      guids = List.of(saved);
      values.clear();
    });
    when(() => m.requestAllParameterValues(any())).thenAnswer((call) {
      final index = call.positionalArguments[0] as int;
      return answer(
        () => AllParameterValues(
          algorithmIndex: index,
          values: slot(index).values,
        ),
      );
    });
    when(() => m.requestLoadPlugin(any())).thenAnswer((_) async {});
    when(() => m.requestAlgorithmInfo(any())).thenAnswer(
      (call) async =>
          _myFilter(call.positionalArguments[0] as int, loaded: loadSucceeds),
    );
    when(
      () => m.requestSavePreset(option: any(named: 'option')),
    ).thenAnswer((_) async {});
  }
}

ParameterInfo _parameter(int slot, int number, String name) => ParameterInfo(
  algorithmIndex: slot,
  parameterNumber: number,
  min: 0,
  max: 100,
  defaultValue: 0,
  unit: 0,
  name: name,
  powerOfTen: 0,
);

AlgorithmInfo _myFilter(int index, {bool loaded = true}) => AlgorithmInfo(
  algorithmIndex: index,
  guid: _guid,
  name: 'My Filter',
  specifications: [
    Specification(name: 'Channels', min: 1, max: 8, defaultValue: 2, type: 0),
  ],
  isPlugin: true,
  isLoaded: loaded,
  filename: _pluginFile,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDistingMidiManager manager;
  late _FakeNt device;
  late _TestCubit cubit;
  late PluginTools tools;
  late _MockMetadataDao metadataDao;

  setUpAll(() {
    registerFallbackValue(_myFilter(0));
    registerFallbackValue(<int>[]);
  });

  /// A live session over [device]'s current lineup.
  DistingStateSynchronized synchronized({
    bool offline = false,
    bool demo = false,
    bool isDirty = false,
    bool pluginLoaded = true,
    List<Slot>? slots,
  }) => DistingStateSynchronized(
    disting: manager,
    distingVersion: '1.12.0',
    firmwareVersion: FirmwareVersion('1.12.0'),
    presetName: 'Test',
    algorithms: [
      AlgorithmInfo(
        algorithmIndex: 0,
        guid: 'clck',
        name: 'Clock',
        specifications: const [],
      ),
      AlgorithmInfo(
        algorithmIndex: 1,
        guid: 'quan',
        name: 'Quantizer',
        specifications: const [],
      ),
      _myFilter(2, loaded: pluginLoaded),
    ],
    slots:
        slots ?? [for (var i = 0; i < device.guids.length; i++) device.slot(i)],
    unitStrings: const [],
    inputDevice: null,
    outputDevice: null,
    loading: false,
    offline: offline,
    screenshot: null,
    demo: demo,
    videoStream: null,
    isDirty: isDirty,
  );

  /// Runs the tool under fake time, so the add's verification window, the
  /// settle delay and every timeout pass instantly.
  Map<String, dynamic> smoke(Map<String, dynamic> args) {
    Map<String, dynamic>? result;
    fakeAsync((async) {
      tools
          .smokeTestPlugin(args)
          .then((r) => result = jsonDecode(r) as Map<String, dynamic>);
      async.elapse(const Duration(minutes: 3));
    });
    expect(result, isNotNull, reason: 'smoke_test_plugin did not finish');
    return result!;
  }

  Map<String, dynamic> base([Map<String, dynamic> extra = const {}]) => {
    'guid': _guid,
    'cpu_budget_percent': 50,
    ...extra,
  };

  List<String> checkNames(Map<String, dynamic> result) => [
    for (final c in result['checks'] as List) (c as Map)['name'] as String,
  ];

  Map<String, dynamic> check(Map<String, dynamic> result, String name) =>
      (result['checks'] as List).cast<Map<String, dynamic>>().singleWhere(
        (c) => c['name'] == name,
      );

  DistingStateSynchronized current() => cubit.state as DistingStateSynchronized;

  void expectBaselineRestored() {
    expect(device.guids, ['clck', 'quan']);
    expect(current().slots.map((s) => s.algorithm.guid), ['clck', 'quan']);
  }

  void expectPresetUntouched() {
    verifyNever(() => manager.requestAddAlgorithm(any(), any()));
    verifyNever(() => manager.requestRemoveAlgorithm(any()));
    verifyNever(() => manager.requestLoadPreset(any(), any()));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final database = _MockAppDatabase();
    metadataDao = _MockMetadataDao();
    when(() => database.metadataDao).thenReturn(metadataDao);
    manager = _MockDistingMidiManager();
    device = _FakeNt()..wire(manager);
    cubit = _TestCubit(database, midiCommand: MockMidiCommand())
      ..device = device;
    cubit.emit(synchronized());
    tools = PluginTools(cubit, actor: FileRootActor.mcp);
  });

  tearDown(() async {
    // The preset file must never be written, whatever the outcome.
    verifyNever(() => manager.requestSavePreset(option: any(named: 'option')));
    expect(cubit.checkpoints, isEmpty);
    await cubit.close();
  });

  group('preset preservation regressions', () {
    test('never removes an unrelated slot when the app baseline is stale', () {
      cubit.emit(synchronized(isDirty: true));
      // A user has appended an algorithm on the module since the last app sync.
      device.guids.add('USER');
      final result = smoke(base());
      expect(device.guids, contains('USER'), reason: '$result');
      verifyNever(() => manager.requestRemoveAlgorithm(2));
    });

    test('preserves edits and their dirty flag during a successful test', () {
      device.onChecks = () {
        device.values[0] = 77; // Simulate a knob edit while sampling.
        final state = current();
        cubit.emit(
          state.copyWith(
            slots: [device.slot(0), ...state.slots.skip(1)],
            isDirty: true,
          ),
        );
      };
      final result = smoke(base());
      expect(result['success'], isTrue);
      expect(device.values[0], 77);
      expect(current().isDirty, isTrue, reason: '$result');
    });

    test('does not reload away edits made after starting clean', () {
      device.acceptRemoves = false;
      device.onChecks = () {
        device.values[0] = 77;
        final state = current();
        cubit.emit(
          state.copyWith(
            slots: [device.slot(0), ...state.slots.skip(1)],
            isDirty: true,
          ),
        );
      };
      final result = smoke(base());
      expect(device.reloads, 0, reason: '$result');
      expect(device.values[0], 77, reason: '$result');
    });

    test('refuses an out-of-range Channels specification before adding', () {
      final result = smoke(
        base({
          'specifications': [0],
        }),
      );
      expect(result['success'], isFalse, reason: '$result');
      expectPresetUntouched();
    });

    test('same-count hardware changes are refused before appending', () {
      device.guids[0] = 'USER';
      final result = smoke(base());
      expect(result['error'], 'preset_changed');
      expectPresetUntouched();
      expect(device.guids.first, 'USER');
    });

    test(
      'panel structural edits during the test never trigger deletion or reload',
      () {
        device.onChecks = () => device.guids[0] = 'USER';
        final result = smoke(base());
        expect(result['rollback'], 'failed');
        expect(device.guids.first, 'USER');
        expect(device.removes, 0);
        expect(device.reloads, 0);
      },
    );

    test(
      'panel parameter edits not yet reflected in app state block reload',
      () {
        device.acceptRemoves = false;
        device.onChecks = () => device.values[0] = 77;
        final result = smoke(base());
        expect(result['rollback'], 'failed');
        expect(device.reloads, 0);
        expect(device.values[0], 77);
      },
    );

    test('structural app edits during the test are left alone', () {
      device.onChecks = () {
        device.guids.add('USER');
        cubit.emit(synchronized(isDirty: true));
      };
      final result = smoke(base());
      expect(result['rollback'], 'failed');
      expect(device.guids.last, 'USER');
      expect(device.removes, 0);
      expect(device.reloads, 0);
    });

    for (final specs in <List<int>>[
      [],
      [9],
      [-1],
      [2, 3],
    ]) {
      test('refuses invalid specification count/range $specs', () {
        final result = smoke(base({'specifications': specs}));
        expect(result['error'], 'invalid_specifications');
        expectPresetUntouched();
      });
    }

    test(
      'switching sessions during checks never cleans up the new session',
      () {
        final originalManager = manager;
        device.onChecks = () {
          manager = _MockDistingMidiManager();
          device.wire(manager);
          cubit.emit(synchronized());
        };
        final result = smoke(base());
        expect(result['rollback'], 'failed');
        verifyNever(() => originalManager.requestRemoveAlgorithm(any()));
        verifyNever(() => manager.requestRemoveAlgorithm(any()));
        verifyNever(() => manager.requestLoadPreset(any(), any()));
      },
    );

    test(
      'null required budget returns a validation error without mutation',
      () {
        final result = smoke(base({'cpu_budget_percent': null}));
        expect(result['error'], 'invalid_cpu_budget_percent');
        expectPresetUntouched();
      },
    );

    test('a concurrent second smoke test is refused without adding a slot', () {
      Map<String, dynamic>? first;
      Map<String, dynamic>? second;
      fakeAsync((async) {
        tools.smokeTestPlugin(base()).then((r) => first = jsonDecode(r));
        async.elapse(const Duration(milliseconds: 500));
        expect(first, isNull);
        tools.smokeTestPlugin(base()).then((r) => second = jsonDecode(r));
        async.flushMicrotasks();
        expect(second?['error'], 'smoke_test_busy');
        expect(device.adds, 1);
        async.elapse(const Duration(minutes: 3));
      });
      expect(first?['success'], isTrue);
      expectBaselineRestored();
    });
  });

  group('registration', () {
    test('describes the tool and every parameter', () {
      final entries = <ToolRegistryEntry>[];
      registerPluginTools(entries, cubit, actor: FileRootActor.mcp);

      final entry = entries.singleWhere((e) => e.name == 'smoke_test_plugin');
      expect(entry.description, contains('never saved'));
      expect(entry.description, contains('offline and demo mode'));
      expect(entry.description, contains('reload_saved_on_failure'));
      expect(entry.inputSchema['required'], ['guid', 'cpu_budget_percent']);
      expect(entry.inputSchema['additionalProperties'], isFalse);
      final properties = entry.inputSchema['properties'] as Map;
      expect(
        properties.keys,
        unorderedEquals([
          'guid',
          'cpu_budget_percent',
          'max_core_percent',
          'specifications',
          'expected_parameter_count',
          'expected_parameter_names',
          'settle_ms',
          'cpu_samples',
          'keep',
          'reload_saved_on_failure',
        ]),
      );
      for (final property in properties.values) {
        expect((property as Map)['description'], isNotEmpty);
      }
      expect(entry.timeout, greaterThanOrEqualTo(const Duration(seconds: 60)));
    });
  });

  group('passing test', () {
    test('appends, checks, removes, and confirms the original slots', () {
      final result = smoke(base());

      expect(result['success'], isTrue, reason: result['message']);
      expect(result.containsKey('error'), isFalse);
      expect(result['slot_index'], 2);
      expect(result['name'], 'My Filter');
      expect(result['loaded_plugin'], isFalse);
      expect(checkNames(result), [
        'slot_added',
        'slot_responds',
        'algorithm_guid',
        'parameter_count',
        'slot_cpu',
      ]);
      expect(
        (result['checks'] as List).every((c) => c['passed'] == true),
        isTrue,
      );
      expect(result['cpu'], {
        'budget_percent': 50,
        'max_core_percent': null,
        'slot_samples': [20, 20, 20],
        'slot_peak': 20,
        'core_samples': [40, 40, 40],
        'core_peak': 40,
      });
      expect(result['rollback'], 'removed_slot');
      expect(result['rolled_back'], isTrue);
      expect(result['message'], contains('original slots are confirmed'));
      expect(device.adds, 1);
      expect(device.removes, 1);
      verify(() => manager.requestRemoveAlgorithm(2)).called(1);
      expectBaselineRestored();
      expect(current().isDirty, isFalse);
      expect(device.reloads, 0);
    });

    test('a preset with unsaved edits stays marked dirty', () {
      cubit.emit(synchronized(isDirty: true));

      final result = smoke(base());

      expect(result['rollback'], 'removed_slot');
      expect(current().isDirty, isTrue);
    });

    test('keep leaves the slot at the end without saving', () {
      final result = smoke(base({'keep': true}));

      expect(result['success'], isTrue);
      expect(result['rollback'], 'kept');
      expect(result['rolled_back'], isFalse);
      expect(result['message'], contains('not saved'));
      expect(device.guids, ['clck', 'quan', _guid]);
      expect(current().slots.last.algorithm.guid, _guid);
      expect(device.removes, 0);
    });

    test('loads an unloaded plug-in before adding it', () {
      cubit.emit(synchronized(pluginLoaded: false));

      final result = smoke(base());

      expect(result['success'], isTrue);
      expect(result['loaded_plugin'], isTrue);
      verify(() => manager.requestLoadPlugin(_guid)).called(1);
    });

    test('adds with default specifications unless given', () {
      smoke(base());
      expect(device.addedSpecs, [2]);

      cubit.emit(synchronized());
      smoke(
        base({
          'specifications': [4],
        }),
      );
      expect(device.addedSpecs, [4]);
    });

    test('tests in an empty preset as slot 0', () {
      device = _FakeNt(saved: const [])..wire(manager);
      cubit.device = device;
      cubit.emit(synchronized());

      final result = smoke(base());

      expect(result['success'], isTrue);
      expect(result['slot_index'], 0);
      expect(device.guids, isEmpty);
    });

    test('passes stricter parameter checks when they match', () {
      final result = smoke(
        base({
          'expected_parameter_count': 2,
          'expected_parameter_names': ['Cutoff', ' Resonance '],
        }),
      );

      expect(result['success'], isTrue);
      expect(check(result, 'parameter_names')['passed'], isTrue);
    });

    test('a slot peak equal to the budget passes', () {
      device.slotCpu = const [50];

      final result = smoke(base());

      expect(result['success'], isTrue);
      expect(check(result, 'slot_cpu')['passed'], isTrue);
    });

    test('max_core_percent passes when both cores stay under it', () {
      final result = smoke(base({'max_core_percent': 60}));

      expect(result['success'], isTrue);
      expect(check(result, 'core_cpu')['passed'], isTrue);
      expect((result['cpu'] as Map)['max_core_percent'], 60);
    });

    test('takes cpu_samples samples', () {
      final result = smoke(base({'cpu_samples': 5}));

      expect((result['cpu'] as Map)['slot_samples'], hasLength(5));
      expect(device.cpuReads, 5);
    });
  });

  group('refused before the preset is touched', () {
    test('offline mode', () {
      cubit.emit(synchronized(offline: true));
      final result = smoke(base());
      expect(result['error'], 'offline_mode');
      expectPresetUntouched();
    });

    test('demo mode', () {
      cubit.emit(synchronized(demo: true));
      final result = smoke(base());
      expect(result['error'], 'demo_mode');
      expectPresetUntouched();
    });

    test('no synchronized device', () {
      cubit.emit(const DistingState.initial());
      final result = smoke(base());
      expect(result['error'], 'not_connected');
      expectPresetUntouched();
    });

    test('unknown GUID', () {
      final result = smoke(base({'guid': 'Nope'}));
      expect(result['error'], 'unknown_guid');
      expect(result['message'], contains('install_plugin'));
      expectPresetUntouched();
    });

    test('built-in algorithm', () {
      final result = smoke(base({'guid': 'clck'}));
      expect(result['error'], 'not_a_plugin');
      expectPresetUntouched();
    });

    test('every slot already used', () {
      device = _FakeNt(saved: List.filled(DistingLimits.maxPresetSlots, 'clck'))
        ..wire(manager);
      cubit.device = device;
      cubit.emit(synchronized());

      final result = smoke(base());

      expect(result['error'], 'preset_full');
      expect(result['max_slots'], DistingLimits.maxPresetSlots);
      expectPresetUntouched();
    });

    test('the plug-in does not load', () {
      device.loadSucceeds = false;
      cubit.emit(synchronized(pluginLoaded: false));

      final result = smoke(base());

      expect(result['error'], 'load_failed');
      expect(result['message'], contains('preset was not changed'));
      expectPresetUntouched();
    });
  });

  group('algorithm library still loading', () {
    // The device's full library; the plug-in under test is its last entry.
    final library = [
      AlgorithmInfo(
        algorithmIndex: 0,
        guid: 'clck',
        name: 'Clock',
        specifications: const [],
      ),
      AlgorithmInfo(
        algorithmIndex: 1,
        guid: 'quan',
        name: 'Quantizer',
        specifications: const [],
      ),
      _myFilter(2),
    ];

    List<AlgorithmInfo> currentAlgorithms() => current().algorithms;

    /// Starts a background library load whose plug-in reads after the quick
    /// first pass wait for [release], and returns once the partial list
    /// (built-ins only) is in state.
    void startPartialLibraryLoad(FakeAsync async, Future<void> release) {
      when(
        () => metadataDao.hasCachedAlgorithms(),
      ).thenAnswer((_) async => false);
      when(
        () => metadataDao.invalidateAlgorithmInfoCache(),
      ).thenAnswer((_) async {});
      when(
        () => metadataDao.getAlgorithmInfoCache(
          any(),
          cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => metadataDao.saveAlgorithmInfoCache(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => manager.requestNumberOfAlgorithms(),
      ).thenAnswer((_) async => library.length);
      var pluginReads = 0;
      // Typed as nullable like the real manager, so the delegate's
      // `onTimeout: () => null` type-checks.
      Future<AlgorithmInfo?> read(int index) async {
        final algorithm = library[index];
        if (algorithm.isPlugin && pluginReads++ > 0) await release;
        return algorithm;
      }

      when(
        () => manager.requestAlgorithmInfo(any()),
      ).thenAnswer((call) => read(call.positionalArguments[0] as int));
      cubit.emit(current().copyWith(algorithms: const []));
      cubit.refreshAlgorithms();
      async.elapse(const Duration(seconds: 1));
      expect(cubit.isAlgorithmLibraryLoading, isTrue);
      expect(currentAlgorithms().map((a) => a.guid), ['clck', 'quan']);
    }

    test('waits for the full list and then finds the plug-in', () {
      Map<String, dynamic>? result;
      fakeAsync((async) {
        // Created inside the fake zone so its completion is delivered there.
        final release = Completer<void>();
        startPartialLibraryLoad(async, release.future);
        tools
            .smokeTestPlugin(base())
            .then((r) => result = jsonDecode(r) as Map<String, dynamic>);
        // Without the wait it would look the GUID up in the partial list
        // now and refuse it as unknown_guid.
        async.elapse(const Duration(seconds: 5));
        expect(result, isNull);
        expectPresetUntouched();
        release.complete();
        async.elapse(const Duration(minutes: 3));
      });

      expect(result, isNotNull, reason: 'smoke_test_plugin did not finish');
      expect(result!['success'], isTrue, reason: '$result');
      expect(cubit.isAlgorithmLibraryLoading, isFalse);
      expectBaselineRestored();
    });

    test('refuses with algorithm_library_loading if loading never ends', () {
      Map<String, dynamic>? result;
      fakeAsync((async) {
        startPartialLibraryLoad(async, Completer<void>().future);
        tools
            .smokeTestPlugin(base())
            .then((r) => result = jsonDecode(r) as Map<String, dynamic>);
        async.elapse(const Duration(minutes: 3));
      });

      expect(result, isNotNull, reason: 'smoke_test_plugin did not finish');
      expect(result!['success'], isFalse);
      expect(result!['error'], 'algorithm_library_loading');
      expect(result!['message'], contains('preset was not changed'));
      expectPresetUntouched();
    });
  });

  group('argument validation', () {
    test('requires guid and cpu_budget_percent', () {
      expect(smoke({'cpu_budget_percent': 50})['error'], 'missing_guid');
      expect(smoke({'guid': ' '})['error'], 'missing_guid');
      expect(smoke({'guid': _guid})['error'], 'missing_cpu_budget');
      expectPresetUntouched();
    });

    test('rejects unknown arguments', () {
      final result = smoke(base({'slot_index': 3}));
      expect(result['error'], 'unknown_argument');
      expect(result['message'], contains('slot_index'));
      expectPresetUntouched();
    });

    test('rejects wrong types and out-of-range values', () {
      final cases = <String, Map<String, dynamic>>{
        'invalid_cpu_budget_percent': {'cpu_budget_percent': 0},
        'invalid_max_core_percent': {'max_core_percent': 101},
        'invalid_specifications': {
          'specifications': ['two'],
        },
        'invalid_expected_parameter_count': {'expected_parameter_count': 0},
        'invalid_expected_parameter_names': {
          'expected_parameter_names': [1],
        },
        'invalid_settle_ms': {'settle_ms': 6000},
        'invalid_cpu_samples': {'cpu_samples': 0},
        'invalid_keep': {'keep': 'yes'},
        'invalid_reload_saved_on_failure': {'reload_saved_on_failure': 1},
      };
      for (final MapEntry(key: code, value: args) in cases.entries) {
        expect(smoke(base(args))['error'], code, reason: '$args');
      }
      expect(
        smoke(base({'cpu_budget_percent': 50.5}))['error'],
        'invalid_cpu_budget_percent',
      );
      expectPresetUntouched();
    });

    test('accepts whole-number doubles from JSON clients', () {
      final result = smoke(base({'cpu_budget_percent': 50.0}));
      expect(result['success'], isTrue);
    });
  });

  group('failing test rolls back', () {
    test('add not confirmed: nothing to remove', () {
      device.acceptAdds = false;

      final result = smoke(base());

      expect(result['success'], isFalse);
      expect(result['error'], 'add_failed');
      expect(check(result, 'slot_added')['passed'], isFalse);
      expect(result['rollback'], 'not_needed');
      expect(result['rolled_back'], isTrue);
      expect(result['cpu'], isNull);
      expect(device.removes, 0);
      expectBaselineRestored();
    });

    test('slot does not answer: parameters_unavailable', () {
      device.testSlotAnswersCount = false;

      final result = smoke(base());

      expect(result['error'], 'parameters_unavailable');
      expect(check(result, 'slot_responds')['passed'], isFalse);
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });

    test('no parameters fails the default check', () {
      device.testSlotParameters = 0;

      final result = smoke(base());

      expect(result['error'], 'parameter_mismatch');
      expect(
        check(result, 'parameter_count')['detail'],
        contains('at least 1'),
      );
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });

    test('parameter count differs from expected_parameter_count', () {
      final result = smoke(base({'expected_parameter_count': 3}));

      expect(result['error'], 'parameter_mismatch');
      expect(check(result, 'parameter_count')['passed'], isFalse);
      expect(result['rollback'], 'removed_slot');
    });

    test('parameter names differ from expected_parameter_names', () {
      final result = smoke(
        base({
          'expected_parameter_names': ['Cutoff', 'Drive'],
        }),
      );

      expect(result['error'], 'parameter_mismatch');
      expect(check(result, 'parameter_names')['detail'], contains('Drive'));
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });

    test('slot reports a different GUID', () {
      device.testSlotGuid = 'Othr';

      final result = smoke(base());

      expect(result['error'], 'parameter_mismatch');
      expect(check(result, 'algorithm_guid')['passed'], isFalse);
      expect(result['rollback'], 'failed');
      expect(device.removes, 0);
      expect(device.reloads, 0);
    });

    test('slot CPU over budget, judged on the peak sample', () {
      device.slotCpu = const [20, 70, 30];

      final result = smoke(base());

      expect(result['success'], isFalse);
      expect(result['error'], 'cpu_over_budget');
      final cpu = result['cpu'] as Map;
      expect(cpu['slot_samples'], [20, 70, 30]);
      expect(cpu['slot_peak'], 70);
      expect(check(result, 'slot_cpu')['passed'], isFalse);
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });

    test('a core over max_core_percent fails with its own code', () {
      device.coreCpu = const [40, 85, 40];

      final result = smoke(base({'max_core_percent': 80}));

      expect(result['error'], 'core_cpu_over_budget');
      expect(check(result, 'slot_cpu')['passed'], isTrue);
      expect(check(result, 'core_cpu')['passed'], isFalse);
      expect((result['cpu'] as Map)['core_peak'], 85);
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });

    test('slot CPU failure is reported before a core failure', () {
      device.slotCpu = const [90];
      device.coreCpu = const [95];

      final result = smoke(base({'max_core_percent': 80}));

      expect(result['error'], 'cpu_over_budget');
      expect(check(result, 'core_cpu')['passed'], isFalse);
    });

    test('CPU sample missing the test slot: cpu_unavailable', () {
      device.cpuCoversTestSlot = false;

      final result = smoke(base());

      expect(result['error'], 'cpu_unavailable');
      expect(check(result, 'cpu')['detail'], contains('slot 2'));
      expect(result['rollback'], 'removed_slot');
      expectBaselineRestored();
    });
  });

  group('device stops answering', () {
    test('during checks, then removal is still confirmed', () {
      device.onChecks = () => device.responding = false;
      device.onRemove = () => device.responding = true;

      final result = smoke(base());

      expect(result['error'], 'device_unresponsive');
      expect(result['rollback'], 'removed_slot');
      expect(result['rolled_back'], isTrue);
      expectBaselineRestored();
    });

    test('from the add on, with a clean preset: reload also fails', () {
      device.afterAdd = () => device.responding = false;

      final result = smoke(base());

      expect(result['error'], 'device_unresponsive');
      expect(check(result, 'slot_added')['passed'], isFalse);
      expect(result['rollback'], 'failed');
      expect(result['rolled_back'], isFalse);
      expect(result['rollback_error'], contains('power-cycle'));
      expect(device.reloads, 1);
    });

    test('for good, with unsaved edits: no reload without opt-in', () {
      cubit.emit(synchronized(isDirty: true));
      device.onChecks = () => device.responding = false;

      final result = smoke(base());

      expect(result['error'], 'device_unresponsive');
      expect(check(result, 'slot_added')['passed'], isTrue);
      expect(check(result, 'slot_responds')['passed'], isFalse);
      expect(result['rollback'], 'failed');
      expect(result['rollback_error'], contains('reload_saved_on_failure'));
      expect(device.reloads, 0);
    });
  });

  group('removal not confirmed', () {
    setUp(() => device.acceptRemoves = false);

    test('clean preset: reloads the saved preset automatically', () {
      final result = smoke(base());

      expect(result['success'], isTrue);
      expect(result['rollback'], 'reloaded_saved_preset');
      expect(result['rolled_back'], isTrue);
      expect(result['rollback_error'], contains('no unsaved edits'));
      expect(result.containsKey('restored_parameter_values'), isFalse);
      verify(
        () => manager.requestLoadPreset('/presets/Test.json', false),
      ).called(1);
      expectBaselineRestored();
    });

    test('unsaved edits without opt-in: reports rollback_failed', () {
      cubit.emit(synchronized(isDirty: true));

      final result = smoke(base());

      expect(result['success'], isFalse);
      expect(result['error'], 'rollback_failed');
      expect(
        (result['checks'] as List).every((c) => c['passed'] == true),
        isTrue,
      );
      expect(result['rollback'], 'failed');
      expect(result['rolled_back'], isFalse);
      expect(result['rollback_error'], contains('Remove slot 2'));
      expect(device.reloads, 0);
      expect(device.guids, ['clck', 'quan', _guid]);
    });

    test('unsaved edits with opt-in: reloads and rewrites values', () {
      device.values[0] = 42;
      cubit.emit(synchronized(isDirty: true));

      final result = smoke(base({'reload_saved_on_failure': true}));

      expect(result['success'], isTrue);
      expect(result['rollback'], 'reloaded_saved_preset');
      expect(result['restored_parameter_values'], 1);
      expect(result['rollback_error'], contains('pre-test parameter snapshot'));
      expect(result['rollback_error'], contains('were discarded'));
      expect(device.reloads, 1);
      expectBaselineRestored();
    });

    test('reload fails too: both errors are reported', () {
      device.reloadFails = true;

      final result = smoke(base());

      expect(result['error'], 'rollback_failed');
      expect(result['rollback'], 'failed');
      final error = result['rollback_error'] as String;
      expect(error, contains('was not confirmed'));
      expect(error, contains('SD card busy'));
    });

    test('saved preset has a different lineup: rollback failed', () {
      device.saved = const ['clck'];

      final result = smoke(base());

      expect(result['rollback'], 'failed');
      expect(result['rollback_error'], contains('After reloading'));
    });
  });

  group('removeAlgorithmConfirmed', () {
    bool remove(int index) {
      bool? removed;
      fakeAsync((async) {
        cubit
            .removeAlgorithmConfirmed(index, pollInterval: Duration.zero)
            .then((r) => removed = r);
        async.elapse(const Duration(minutes: 1));
      });
      return removed!;
    }

    test('removes from state only after the device confirms', () {
      expect(remove(1), isTrue);
      expect(device.guids, ['clck']);
      expect(current().slots.map((s) => s.algorithm.guid), ['clck']);
    });

    test('unconfirmed removal leaves state unchanged', () {
      device.acceptRemoves = false;

      expect(remove(1), isFalse);
      expect(current().slots, hasLength(2));
      verify(
        () => manager.requestNumAlgorithmsInPreset(
          timeout: any(named: 'timeout'),
          maxRetries: 1,
        ),
      ).called(10);
    });

    test('refuses an index outside the preset without sending', () {
      expect(remove(2), isFalse);
      verifyNever(() => manager.requestRemoveAlgorithm(any()));
    });
  });
}
