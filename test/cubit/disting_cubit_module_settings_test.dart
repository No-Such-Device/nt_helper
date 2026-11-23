import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/sysex/module_settings_codec.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/module_settings_fixtures.dart';
import '../test_helpers/mock_midi_command.dart';

class Database extends Mock implements AppDatabase {}

class Metadata extends Mock implements MetadataDao {}

class LiveSettings extends Mock
    implements IDistingMidiManager, ModuleSettingsTransport {}

DistingState synchronized(
  IDistingMidiManager manager, {
  bool demo = false,
  bool offline = false,
  String firmware = '1.20beta',
}) => DistingState.synchronized(
  disting: manager,
  distingVersion: firmware,
  firmwareVersion: FirmwareVersion(firmware),
  presetName: 'Settings',
  algorithms: const [],
  slots: const [],
  unitStrings: const [],
  demo: demo,
  offline: offline,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(DistingRequestCancellation());
    registerFallbackValue(const ModuleSettingValue(0));
  });
  late DistingCubit cubit;
  late LiveSettings manager;
  late Map<int, int> values;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    manager = LiveSettings();
    values = {5: 0, 9: 0};
    when(() => manager.discoverModuleSettings(any())).thenAnswer(
      (_) async => ModuleSettingsCodec.groups(settingsGroupsPayload()),
    );
    when(() => manager.requestModuleSettingInfo(any(), any())).thenAnswer(
      (i) async => settingInfo(
        i.positionalArguments[0] as int,
        flags: i.positionalArguments[0] == 5 ? 1 : 0,
      ),
    );
    when(() => manager.requestModuleSettingValue(any(), any())).thenAnswer(
      (i) async => ModuleSettingValue(values[i.positionalArguments[0]]!),
    );
    when(() => manager.writeModuleSetting(any(), any(), any()))
        .thenAnswer((i) async {
          final id = i.positionalArguments[0] as int;
          final value = i.positionalArguments[1] as ModuleSettingValue;
          values[id] = value.value as int;
          return value;
        });
    when(() => manager.sendModuleSettingsAction(any(), any()))
        .thenAnswer((_) async {});
    final database = Database();
    final metadata = Metadata();
    when(() => database.metadataDao).thenReturn(metadata);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    cubit = DistingCubit(
      database,
      midiCommand: MockMidiCommand(),
      isWindowsOverride: true,
    );
    cubit.emit(synchronized(manager));
  });
  tearDown(() => cubit.close());

  test('one discovery per connection; drafts survive reopen/refresh and only explicit Apply writes', () async {
    await cubit.loadModuleSettings();
    final initial = cubit.moduleSettingsState;
    expect(initial.tree!.settingIds, [5, 9]);
    expect(initial.ready, isTrue);
    cubit.editModuleSetting(5, const ModuleSettingValue(7));
    expect(cubit.moduleSettingsState.settings[5]!.observed.value, 0);
    expect(cubit.moduleSettingsState.settings[5]!.draft!.value, 7);
    await cubit.loadModuleSettings();
    verify(() => manager.discoverModuleSettings(any())).called(1);
    verifyNever(() => manager.writeModuleSetting(any(), any(), any()));
    await cubit.loadModuleSettings(force: true);
    expect(cubit.moduleSettingsState.settings[5]!.draft!.value, 7);
    await cubit.applyModuleSettingsGroup(3);
    expect(cubit.moduleSettingsState.settings[5]!.observed.value, 7);
    expect(cubit.moduleSettingsState.hasDrafts, isFalse);
    expect(cubit.moduleSettingsState.canCommit, isTrue);
    expect(initial.settings[5]!.observed.value, 0);
    await cubit.commitModuleSettings();
    expect(cubit.moduleSettingsState.message, contains('not acknowledged'));
    expect(cubit.moduleSettingsState.changedOnModule, isFalse);
  });

  test(
    'invalid drafts/read-only/path/future types never call writer',
    () async {
      when(() => manager.requestModuleSettingInfo(9, any()))
          .thenAnswer((_) async => settingInfo(9, flags: 4));
      await cubit.loadModuleSettings();
      cubit.editModuleSetting(9, const ModuleSettingValue(9));
      expect(cubit.moduleSettingsState.settings[9]!.draft, isNull);
      cubit.editModuleSetting(5, const ModuleSettingValue('bad'));
      expect(cubit.moduleSettingsState.settings[5]!.error, isNotNull);
      await cubit.applyModuleSettingsGroup(3);
      await cubit.commitModuleSettings();
      verifyNever(() => manager.writeModuleSetting(any(), any(), any()));
      verifyNever(() => manager.sendModuleSettingsAction(any(), any()));
      cubit.discardModuleSettingsDrafts();
      expect(cubit.moduleSettingsState.hasDrafts, isFalse);
    },
  );

  test('mismatch retains requested vs observed; refresh resolves uncertainty, not a hidden replay', () async {
    when(() => manager.writeModuleSetting(any(), any(), any()))
        .thenAnswer((_) async => const ModuleSettingValue(2));
    await cubit.loadModuleSettings();
    cubit.editModuleSetting(5, const ModuleSettingValue(7));
    await cubit.applyModuleSettingsGroup(3);
    final result = cubit.moduleSettingsState;
    expect(result.settings[5]!.observed.value, 2);
    expect(result.settings[5]!.draft!.value, 7);
    expect(result.settings[5]!.uncertain, isTrue);
    expect(result.canCommit, isFalse);
    await cubit.applyModuleSettingsGroup(3);
    verify(() => manager.writeModuleSetting(5, any(), any())).called(1);
    await cubit.loadModuleSettings(force: true);
    expect(cubit.moduleSettingsState.settings[5]!.draft!.value, 7);
    expect(cubit.moduleSettingsState.hasUncertainty, isFalse);
    verifyNever(() => manager.writeModuleSetting(any(), any(), any()));
  });

  test('revert is explicit, unacknowledged and blocks further writes until a refresh', () async {
    await cubit.loadModuleSettings();
    cubit.editModuleSetting(5, const ModuleSettingValue(1));
    await cubit.applyModuleSettingsGroup(3);
    await cubit.revertModuleSettings();
    expect(cubit.moduleSettingsState.actionUncertain, isTrue);
    expect(cubit.moduleSettingsState.message, contains('Revert sent'));
    await cubit.commitModuleSettings();
    verify(() => manager.sendModuleSettingsAction(2, any())).called(1);
    verifyNever(() => manager.sendModuleSettingsAction(0, any()));
    await cubit.loadModuleSettings(force: true);
    expect(cubit.moduleSettingsState.actionUncertain, isFalse);
  });

  test('offline/demo/earlier/unknown firmware do not probe or write', () async {
    for (final state in [
      synchronized(manager, demo: true),
      synchronized(manager, offline: true),
      synchronized(manager, firmware: '1.19.0'),
      synchronized(manager, firmware: 'unknown 1.20'),
    ]) {
      cubit.emit(state);
      await cubit.loadModuleSettings(force: true);
      expect(cubit.moduleSettingsState.unavailableReason, isNotNull);
      await cubit.commitModuleSettings();
      await cubit.applyModuleSettingsGroup(3);
    }
    verifyNever(() => manager.discoverModuleSettings(any()));
    verifyNever(() => manager.sendModuleSettingsAction(any(), any()));
  });

  test('failed/unsupported discovery stays fail closed and does not auto-retry on reopen', () async {
    when(() => manager.discoverModuleSettings(any()))
        .thenThrow(UnsupportedError('version 2'));
    await cubit.loadModuleSettings();
    expect(cubit.moduleSettingsState.tree, isNull);
    expect(cubit.moduleSettingsState.message, contains('version 2'));
    expect(cubit.moduleSettingsState.ready, isFalse);
    await cubit.loadModuleSettings();
    await cubit.applyModuleSettingsGroup(3);
    verify(() => manager.discoverModuleSettings(any())).called(1);
    verifyNever(() => manager.writeModuleSetting(any(), any(), any()));
  });

  test('disconnect cancels in-flight discovery; late completion never exposes schema on replacement', () async {
    final reply = Completer<ModuleSettingsTree>();
    DistingRequestCancellation? token;
    when(() => manager.discoverModuleSettings(any())).thenAnswer((i) {
      token = i.positionalArguments[0] as DistingRequestCancellation;
      return reply.future;
    });
    final loading = cubit.loadModuleSettings();
    expect(cubit.moduleSettingsState.busy, isTrue);
    cubit.emit(synchronized(manager, offline: true));
    expect(token!.isCancelled, isTrue);
    cubit.emit(synchronized(LiveSettings()));
    reply.complete(ModuleSettingsCodec.groups(settingsGroupsPayload()));
    await loading;
    expect(cubit.moduleSettingsState.tree, isNull);
    verifyNever(() => manager.requestModuleSettingInfo(any(), any()));
  });

  test(
    'disconnect cancels writes and never replays drafts on a new device',
    () async {
      await cubit.loadModuleSettings();
      cubit.editModuleSetting(5, const ModuleSettingValue(3));
      final reply = Completer<ModuleSettingValue>();
      DistingRequestCancellation? token;
      when(() => manager.writeModuleSetting(any(), any(), any()))
          .thenAnswer((i) {
            token = i.positionalArguments[2] as DistingRequestCancellation;
            return reply.future;
          });
      final applying = cubit.applyModuleSettingsGroup(3);
      cubit.emit(synchronized(manager, offline: true));
      expect(token!.isCancelled, isTrue);
      expect(cubit.moduleSettingsState.settings[5]!.draft!.value, 3);
      final replacement = LiveSettings();
      cubit.emit(synchronized(replacement));
      reply.complete(const ModuleSettingValue(3));
      await applying;
      expect(cubit.moduleSettingsState.settings, isEmpty);
      verifyNever(() => replacement.writeModuleSetting(any(), any(), any()));
      verifyNever(() => replacement.discoverModuleSettings(any()));
    },
  );
}
