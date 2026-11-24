import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/ntx8cv_routing.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/cv_routing_fixture.dart';

class _Disting extends Mock implements DistingCubit {}

class _Live extends Mock
    implements IDistingMidiManager, ModuleSettingsTransport {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Disting disting;
  late _Live manager;
  late RoutingEditorCubit routing;
  late StreamController<DistingState> states;
  late StreamController<ModuleSettingsState> settings;
  late DistingStateSynchronized snapshot;
  late ModuleSettingsState settingsState;
  Ntx8cvRouting? config;
  late Completer<void> load;
  late Completer<void> loadStarted;
  late List<int> writes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    disting = _Disting();
    manager = _Live();
    states = StreamController<DistingState>.broadcast(sync: true);
    settings = StreamController<ModuleSettingsState>.broadcast(sync: true);
    snapshot = DistingState.synchronized(
      disting: manager,
      distingVersion: '1.20beta',
      firmwareVersion: FirmwareVersion('1.20beta'),
      presetName: 'Unknown NTX',
      algorithms: const [],
      slots: [
        cvSlot(0, outputs: [0]),
        cvSlot(1, inputs: [0]),
      ],
      unitStrings: const [],
    ) as DistingStateSynchronized;
    settingsState = ModuleSettingsState(connectionId: 1);
    config = null;
    load = Completer<void>();
    loadStarted = Completer<void>();
    writes = [];
    when(() => disting.state).thenAnswer((_) => snapshot);
    when(() => disting.stream).thenAnswer((_) => states.stream);
    when(() => disting.moduleSettingsState).thenAnswer((_) => settingsState);
    when(() => disting.moduleSettingsStream).thenAnswer((_) => settings.stream);
    when(() => disting.ntx8cvRouting).thenAnswer((_) => config);
    when(() => disting.loadModuleSettings()).thenAnswer((_) {
      if (!loadStarted.isCompleted) loadStarted.complete();
      return load.future;
    });
    when(
      () => disting.updateParameterValue(
        algorithmIndex: any(named: 'algorithmIndex'),
        parameterNumber: any(named: 'parameterNumber'),
        value: any(named: 'value'),
        userIsChangingTheValue: any(named: 'userIsChangingTheValue'),
      ),
    ).thenAnswer((invocation) async {
      writes.add(invocation.namedArguments[#value] as int);
    });
    routing = RoutingEditorCubit(disting);
  });
  tearDown(() async {
    await routing.close();
    load.complete();
    await states.close();
    await settings.close();
  });

  Future<void> connect() async {
    final loaded = routing.state as RoutingEditorStateLoaded;
    await routing.createConnection(
      sourcePortId: loaded.algorithms[0].outputPorts.first.id,
      targetPortId: loaded.algorithms[1].inputPorts.first.id,
    );
  }

  test('unresolved and pending discovery reserve first-group buses without claiming known configuration', () async {
    expect((routing.state as RoutingEditorStateLoaded).ntx8cvRouting, isNull);
    await connect();
    expect(writes, [29, 29]);
    writes.clear();
    routing.ensureNtx8cvRoutingLoaded();
    routing.ensureNtx8cvRoutingLoaded();
    await loadStarted.future;
    verify(() => disting.loadModuleSettings()).called(1);
    settingsState = ModuleSettingsState(connectionId: 1, busy: true);
    settings.add(settingsState);
    await Future<void>.value();
    await connect();
    expect(writes, [29, 29]);
    writes.clear();
    config = Ntx8cvRouting(
      mode: Ntx8cvRoutingMode.cv,
      channelEnables: BigInt.zero,
    );
    settings.add(ModuleSettingsState(connectionId: 1));
    await Future<void>.value();
    await connect();
    expect(writes, [21, 21]);
    writes.clear();
    config = Ntx8cvRouting(
      mode: Ntx8cvRoutingMode.cv,
      channelEnables: BigInt.one,
    );
    settings.add(ModuleSettingsState(connectionId: 1));
    await Future<void>.value();
    await connect();
    expect(writes, [22, 22]);
    verifyNever(() => disting.loadModuleSettings());
    verifyZeroInteractions(manager);
  });

  test('failed or stale candidate discovery stays protected; reconnect coalesces a new load', () async {
    routing.ensureNtx8cvRoutingLoaded();
    await loadStarted.future;
    verify(() => disting.loadModuleSettings()).called(1);
    settingsState = ModuleSettingsState(connectionId: 1, actionUncertain: true);
    settings.add(settingsState);
    await Future<void>.value();
    await connect();
    expect(writes, [29, 29]);
    writes.clear();
    config = Ntx8cvRouting(
      mode: Ntx8cvRoutingMode.cv,
      channelEnables: BigInt.zero,
    );
    settings.add(ModuleSettingsState(connectionId: 1));
    await Future<void>.value();
    await connect();
    expect(writes, [21, 21]);
    writes.clear();
    config = null;
    snapshot = snapshot.copyWith(disting: _Live());
    settingsState = ModuleSettingsState(connectionId: 2, busy: true);
    loadStarted = Completer<void>();
    states.add(snapshot);
    await loadStarted.future;
    verify(() => disting.loadModuleSettings()).called(1);
    await connect();
    expect(writes, [29, 29]);
    settings.add(settingsState);
    await Future<void>.value();
    verifyNever(() => disting.loadModuleSettings());
    verifyZeroInteractions(manager);
  });

  test('older unsupported firmware retains legacy AUX allocation without settings queries', () async {
    snapshot = snapshot.copyWith(firmwareVersion: FirmwareVersion('1.19'));
    states.add(snapshot);
    await connect();
    expect(writes, [21, 21]);
    verifyNever(() => disting.loadModuleSettings());
    verifyZeroInteractions(manager);
  });

  for (final slotIndex in [0, 1]) {
    test(
      'pending reservation cannot clamp a chosen bus onto protected AUX at endpoint $slotIndex',
      () async {
        final slots = List<Slot>.of(snapshot.slots);
        final slot = slots[slotIndex];
        final parameter = slot.parameters.first;
        slots[slotIndex] = slot.copyWith(
          parameters: [
            ParameterInfo(
              algorithmIndex: slotIndex,
              parameterNumber: parameter.parameterNumber,
              min: parameter.min,
              max: 28,
              defaultValue: parameter.defaultValue,
              unit: parameter.unit,
              name: parameter.name,
              powerOfTen: parameter.powerOfTen,
              ioFlags: parameter.ioFlags,
            ),
          ],
        );
        snapshot = snapshot.copyWith(slots: slots);
        states.add(snapshot);
        await expectLater(connect(), throwsStateError);
        expect(writes, isEmpty);
        verifyZeroInteractions(manager);
      },
    );
  }

  test('pending configuration does not block reader-only fanout from an unchanged writer', () async {
    snapshot = snapshot.copyWith(
      slots: [
        cvSlot(0, outputs: [21], modes: [OutputMode.replace]),
        cvSlot(1, inputs: [0]),
      ],
    );
    states.add(snapshot);
    await connect();
    expect(writes, [21]);
    verifyNever(() => disting.loadModuleSettings());
    verifyZeroInteractions(manager);
  });
}
