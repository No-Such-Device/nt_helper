import 'package:nt_helper/core/routing/models/port.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/mcp/tools/algorithm_tools.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/cv_routing_fixture.dart';
import '../test_helpers/ntx8cv_routing_fixture.dart';
import '../test_helpers/mock_midi_command.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Live extends Mock
    implements IDistingMidiManager, ModuleSettingsTransport {}

class _Controller extends Mock implements DistingController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DistingRequestCancellation());
    registerFallbackValue(const ModuleSettingValue(0));
  });
  late DistingCubit disting;
  late RoutingEditorCubit routing;
  late _Live live;
  late ModuleSettingsState settings;
  late Map<int, ModuleSettingValue> values;
  final source = cvSlot(0, outputs: [21, 22, 29]);
  DistingState snapshot({
    bool offline = false,
    bool demo = false,
    String firmware = '1.20.0beta',
  }) => DistingState.synchronized(
    disting: live,
    distingVersion: firmware,
    firmwareVersion: FirmwareVersion(firmware),
    presetName: 'NTX fixture',
    algorithms: const [],
    slots: [source],
    unitStrings: const [],
    offline: offline,
    demo: demo,
  );
  Future<void> settled() async {
    if (routing.state is RoutingEditorStateLoaded &&
        (routing.state as RoutingEditorStateLoaded).ntx8cvRouting != null) {
      return;
    }
    await routing.stream.firstWhere(
      (s) => s is RoutingEditorStateLoaded && s.ntx8cvRouting != null,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    live = _Live();
    settings = ntxSettings();
    values = {
      for (final entry in settings.settings.entries)
        entry.key: entry.value.observed,
    };
    when(() => live.discoverModuleSettings(any()))
        .thenAnswer((_) async => settings.tree!);
    when(() => live.requestModuleSettingInfo(any(), any())).thenAnswer(
      (i) async => settings.settings[i.positionalArguments[0]]!.info,
    );
    when(() => live.requestModuleSettingValue(any(), any()))
        .thenAnswer((i) async => values[i.positionalArguments[0]]!);
    when(() => live.writeModuleSetting(any(), any(), any()))
        .thenAnswer((i) async {
          values[i.positionalArguments[0] as int] =
              i.positionalArguments[1] as ModuleSettingValue;
          return i.positionalArguments[1] as ModuleSettingValue;
        });
    final db = _Database();
    final metadata = _Metadata();
    when(() => db.metadataDao).thenReturn(metadata);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    disting = DistingCubit(
      db,
      midiCommand: MockMidiCommand(),
      isWindowsOverride: true,
    );
    disting.emit(snapshot());
    routing = RoutingEditorCubit(disting);
    routing.ensureNtx8cvRoutingLoaded();
  });
  tearDown(() async {
    await routing.close();
    await disting.close();
  });

  test(
    'constructing a cached/hidden editor does not perform discovery',
    () async {
      await routing.close();
      routing = RoutingEditorCubit(disting);
      await Future<void>.value();
      verifyNever(() => live.discoverModuleSettings(any()));
      routing.ensureNtx8cvRoutingLoaded();
      await settled();
      verify(() => live.discoverModuleSettings(any())).called(1);
    },
  );

  test('single/Add-only NTX writers retain move capability; shared Replace blocks before writes', () async {
    await settled();
    for (final modes in [
      <OutputMode>[],
      [OutputMode.add],
    ]) {
      final state = disting.state as DistingStateSynchronized;
      disting.emit(
        state.copyWith(
          slots: [
            cvSlot(0, outputs: [21], modes: modes),
            cvSlot(1, outputs: [21], modes: modes),
          ],
        ),
      );
      expect(disting.ensureCvRoutingOrderChangeSafe, returnsNormally);
    }
    final state = disting.state as DistingStateSynchronized;
    disting.emit(
      state.copyWith(
        slots: [
          cvSlot(0, outputs: [21], modes: [OutputMode.replace]),
          cvSlot(1, outputs: [21], modes: [OutputMode.add]),
        ],
      ),
    );
    clearInteractions(live);
    expect(disting.ensureCvRoutingOrderChangeSafe, throwsStateError);
    await expectLater(disting.moveAlgorithmUp(1), throwsStateError);
    verifyZeroInteractions(live);
  });

  test('routing demand loads once; cached API reuses settings without hardware I/O', () async {
    await settled();
    final loaded = routing.state as RoutingEditorStateLoaded;
    expect(loaded.ntx8cvOutputs, hasLength(8));
    expect(
      loaded.connections.where(
        (c) => c.destinationPortId.startsWith('ntx8cv_'),
      ),
      hasLength(2),
    );
    expect(loaded.auxBusUsage[21]!.destNames, contains('NTX-8CV 1'));
    verify(() => live.discoverModuleSettings(any())).called(1);
    clearInteractions(live);
    final controller = _Controller();
    final result = jsonDecode(
      await MCPAlgorithmTools(controller, disting).getCurrentRoutingState({}),
    ) as List;
    expect(result.single['ntx8cv_outputs'].map((v) => v['jack']), [1, 2]);
    expect(
      result.single['ntx8cv_outputs'].first['scope'],
      'first_channel_group',
    );
    verifyZeroInteractions(live);
    verifyZeroInteractions(controller);
    final reopened = RoutingEditorCubit(disting);
    reopened.ensureNtx8cvRoutingLoaded();
    await Future<void>.value();
    expect(
      (reopened.state as RoutingEditorStateLoaded).ntx8cvOutputs,
      hasLength(8),
    );
    verifyNever(() => live.discoverModuleSettings(any()));
    await reopened.close();
  });

  test(
    'mask-only readback updates routes without slot changes; drafts do not',
    () async {
      await settled();
      final before = routing.state as RoutingEditorStateLoaded;
      routing.updateNodePosition('ntx8cv_outputs', 3400, 2800);
      disting.editModuleSetting(130, ModuleSettingValue(BigInt.one));
      await Future<void>.value();
      expect(
        (routing.state as RoutingEditorStateLoaded).ntx8cvRouting,
        before.ntx8cvRouting,
      );
      await disting.applyModuleSettingsGroup(19);
      await Future<void>.value();
      final after = routing.state as RoutingEditorStateLoaded;
      expect(
        after.ntx8cvOutputs
            .where((p) => p.isActive)
            .map((p) => p.hardwareIndex),
        [1],
      );
      expect(
        after.connections.where(
          (c) => c.destinationPortId.startsWith('ntx8cv_'),
        ),
        hasLength(1),
      );
      expect(after.nodePositions['ntx8cv_outputs']!.x, 3400);
    },
  );

  test('read-only taps reject deletion and allocation/move cannot reuse external buses', () async {
    await settled();
    final loaded = routing.state as RoutingEditorStateLoaded;
    final edge = loaded.connections.firstWhere(
      (c) => c.destinationPortId.startsWith('ntx8cv_'),
    );
    expect(
      routing.deletionBlockReasonForConnection(edge),
      contains('read only'),
    );
    clearInteractions(live);
    await routing.deleteConnection(edge.id);
    expect(await routing.moveAuxBus(21, 30), -1);
    expect(await routing.moveAuxBus(29, 22), -1);
    verifyZeroInteractions(live);
  });

  test(
    'offline/demo and older firmware do not fetch or retain authoritative taps',
    () async {
      await settled();
      for (final state in [
        snapshot(offline: true),
        snapshot(demo: true),
        snapshot(firmware: '1.19'),
      ]) {
        clearInteractions(live);
        disting.emit(state);
        await Future<void>.value();
        await Future<void>.value();
        expect(
          (routing.state as RoutingEditorStateLoaded).ntx8cvOutputs,
          isEmpty,
        );
        verifyNever(() => live.discoverModuleSettings(any()));
      }
    },
  );

  test(
    'failed discovery is bounded and retried only by explicit refresh',
    () async {
      await settled();
      await routing.close();
      disting.emit(const DistingState.initial());
      final completion = Completer<ModuleSettingsTree>();
      when(() => live.discoverModuleSettings(any()))
          .thenAnswer((_) => completion.future);
      clearInteractions(live);
      disting.emit(snapshot());
      routing = RoutingEditorCubit(disting);
      routing.ensureNtx8cvRoutingLoaded();
      await Future<void>.value();
      completion.completeError(StateError('not supported in this beta'));
      await disting.moduleSettingsStream.firstWhere(
        (s) => s.actionUncertain && !s.busy,
      );
      await Future<void>.value();
      expect(
        (routing.state as RoutingEditorStateLoaded).ntx8cvOutputs,
        isEmpty,
      );
      verify(() => live.discoverModuleSettings(any())).called(1);
      final reopened = RoutingEditorCubit(disting);
      reopened.ensureNtx8cvRoutingLoaded();
      await Future<void>.value();
      verifyNever(() => live.discoverModuleSettings(any()));
      await reopened.close();
    },
  );
}
