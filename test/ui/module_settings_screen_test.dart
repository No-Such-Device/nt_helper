import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/module_settings.dart';
import 'package:nt_helper/ui/module_settings_screen.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

import '../test_helpers/module_settings_fixtures.dart';

class CubitMock extends Mock implements DistingCubit {}

class ManagerMock extends Mock implements IDistingMidiManager {}

void main() {
  setUpAll(() => registerFallbackValue(const ModuleSettingValue(0)));
  late CubitMock cubit;
  late StreamController<ModuleSettingsState> states;
  late ModuleSettingsState current;
  setUp(() {
    cubit = CubitMock();
    states = StreamController.broadcast();
    current = settingsScreenState();
    when(() => cubit.moduleSettingsState).thenAnswer((_) => current);
    when(() => cubit.moduleSettingsStream).thenAnswer((_) => states.stream);
    when(() => cubit.loadModuleSettings(force: any(named: 'force')))
        .thenAnswer((_) async {});
    when(() => cubit.loadModuleSettings()).thenAnswer((_) async {});
    when(() => cubit.applyModuleSettingsGroup(any())).thenAnswer((_) async {});
    when(() => cubit.commitModuleSettings()).thenAnswer((_) async {});
    when(() => cubit.revertModuleSettings()).thenAnswer((_) async {});
    when(() => cubit.state).thenReturn(
      DistingState.synchronized(
        disting: ManagerMock(),
        distingVersion: '1.20beta',
        firmwareVersion: FirmwareVersion('1.20beta'),
        presetName: 'Test',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );
  });
  tearDown(() => states.close());

  Widget app({double scale = 1, Brightness brightness = Brightness.light}) =>
      MaterialApp(
        theme: AppTheme.build(
          seedColor: AppTheme.defaultSeedColor,
          brightness: brightness,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ModuleSettingsScreen(cubit: cubit),
      );
  void emit(ModuleSettingsState state) {
    current = state;
    states.add(state);
  }

  testWidgets(
    'initial discovery mounts a coherent form without moving toolbar or status',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      current = ModuleSettingsState(
        connectionId: 1,
        busy: true,
        message: 'Reading module settings…',
      );
      await tester.pumpWidget(app());
      expect(find.byType(TextField), findsNothing);
      final commit = tester.getRect(
        find.widgetWithText(FilledButton, 'Commit to flash'),
      );
      final status = tester.getRect(
        find.byKey(const Key('module-settings-status')),
      );
      emit(settingsScreenState());
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Commit to flash')),
        commit,
      );
      expect(
        tester.getRect(find.byKey(const Key('module-settings-status'))),
        status,
      );
    },
  );

  testWidgets(
    'pending, errors, retry, disconnect and stale refresh retain control geometry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app());
      Map<String, Rect> rects() => {
        'status': tester.getRect(
          find.byKey(const Key('module-settings-status')),
        ),
        'first': tester.getRect(find.byType(TextField).first),
        'second': tester.getRect(find.byType(TextField).last),
        'apply': tester.getRect(
          find.byKey(const ValueKey('module-settings-apply-3')),
        ),
        'commit': tester.getRect(
          find.widgetWithText(FilledButton, 'Commit to flash'),
        ),
      };
      final original = rects();
      for (final state in [
        settingsScreenState(busy: true, message: 'Reading…'),
        settingsScreenState(
          error: 'Change not confirmed. ' * 30,
          draft: true,
          message: 'Could not verify',
        ),
        settingsScreenState(
          busy: true,
          draft: true,
          message: 'Retrying readback',
        ),
        settingsScreenState(draft: true),
        settingsScreenState(
          unavailable:
              'Connect to a disting NT to read or change module settings.',
        ),
        settingsScreenState(message: 'Values read back'),
      ]) {
        emit(state);
        await tester.pump();
        expect(rects(), original);
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(SnackBar), findsNothing);
      expect(find.bySemanticsLabel('NT Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('Engine'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'concise screen has one home per action, no introductory prose or repeated helpers',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app());
      expect(find.byKey(const Key('refresh-module-settings')), findsOneWidget);
      expect(find.byTooltip('Discard drafts'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Commit to flash'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Revert to saved'),
        findsOneWidget,
      );
      expect(find.text('Apply changes'), findsOneWidget);
      expect(find.text('Apply Engine'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('module-settings-apply-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('module-settings-apply-3')),
        findsOneWidget,
      );
      expect(find.textContaining('Settings on the connected'), findsNothing);
      expect(find.textContaining('Drafts stay'), findsNothing);
      expect(find.textContaining('Default'), findsNothing);
      expect(find.text('Discard drafts'), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byTooltip(RegExp('Default 0')), findsNWidgets(2));
    },
  );

  testWidgets('read-only groups do not offer redundant Apply buttons', (
    tester,
  ) async {
    final tree = current.tree;
    current = ModuleSettingsState(
      connectionId: 1,
      tree: tree,
      settings: {
        for (final id in [5, 9])
          id: ModuleSettingEdit(
            info: settingInfo(id, flags: 4),
            observed: const ModuleSettingValue(0),
          ),
      },
    );
    await tester.pumpWidget(app());
    expect(find.text('Apply changes'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'failed draft exposes last observed value in a labelled live region',
    (tester) async {
      final semantics = tester.ensureSemantics();
      current = settingsScreenState(
        draft: true,
        error: 'Change not confirmed.',
      );
      await tester.pumpWidget(app());
      expect(find.text('Last read: 0'), findsOneWidget);
      final status = find.bySemanticsLabel(
        'Setting 5: Change not confirmed.\nLast read: 0',
      );
      expect(status, findsOneWidget);
      expect(
        tester
            .getSemantics(status)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '4',
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'keyboard editing validates without sending; Apply requires explicit impact confirmation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      current = settingsScreenState(draft: true);
      await tester.pumpWidget(app());
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.enterText(field, '-42');
      verify(
        () => cubit.editModuleSetting(
          5,
          any(
            that: isA<ModuleSettingValue>().having(
              (v) => v.value,
              'value',
              -42,
            ),
          ),
        ),
      ).called(1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull);
      final apply = find.byKey(const ValueKey('module-settings-apply-3'));
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.textContaining('Applied one at a time'), findsOneWidget);
      expect(
        find.text('Settings on the connected disting NT module.'),
        findsNothing,
      );
      expect(
        find.textContaining('Drafts stay in this connection'),
        findsNothing,
      );
      verifyNever(() => cubit.applyModuleSettingsGroup(any()));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => cubit.applyModuleSettingsGroup(any()));
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apply changes'));
      await tester.pumpAndSettle();
      verify(() => cubit.applyModuleSettingsGroup(3)).called(1);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('confirmation cannot apply to a replacement connection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    current = settingsScreenState(draft: true);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('module-settings-apply-3')));
    await tester.pumpAndSettle();
    emit(ModuleSettingsState(connectionId: 2));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply changes'));
    await tester.pumpAndSettle();
    verifyNever(() => cubit.applyModuleSettingsGroup(any()));
  });

  testWidgets(
    'types render standard controls with full bit64 semantics, read-only enforcement and flags',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final infos = [
        settingInfo(
          1,
          unit: 1,
          min: 0,
          max: 1,
          enums: ['Off', 'On'],
          name: 'Toggle',
        ),
        settingInfo(
          2,
          unit: 1,
          min: 0,
          max: 1,
          enums: ['Left', 'Right'],
          name: 'Selection',
        ),
        settingInfo(3, type: 4, name: 'Name'),
        settingInfo(4, type: 5, name: 'Path'),
        settingInfo(5, type: 6, name: 'Bits'),
        settingInfo(6, flags: 4, name: 'Locked'),
        settingInfo(7, flags: 3, name: 'Engine value'),
      ];
      current = ModuleSettingsState(
        connectionId: 1,
        tree: ModuleSettingsTree(
          opaqueHeader: [0, 0, 0],
          groups: {
            0: ModuleSettingsGroup(
              id: 0,
              name: '',
              children: [
                for (final info in infos)
                  ModuleSettingChild(id: info.id, isGroup: false),
              ],
            ),
          },
        ),
        settings: {
          for (final info in infos)
            info.id: ModuleSettingEdit(
              info: info,
              observed: ModuleSettingValue(switch (info.type) {
                4 => 'NT name',
                5 => '/mts/tuning.syx',
                6 => BigInt.one << 63,
                _ => 0,
              }),
            ),
        },
      );
      await tester.pumpWidget(app());
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(64));
      final lastBit = find.bySemanticsLabel('Bits, bit 64');
      expect(lastBit, findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(of: lastBit, matching: find.byType(Checkbox)),
            )
            .value,
        isTrue,
      );
      await tester.ensureVisible(lastBit);
      await tester.tap(lastBit);
      verify(
        () => cubit.editModuleSetting(
          5,
          any(
            that: isA<ModuleSettingValue>().having(
              (v) => v.value,
              'bits',
              BigInt.zero,
            ),
          ),
        ),
      ).called(1);
      expect(find.text('/mts/tuning.syx'), findsOneWidget);
      expect(find.bySemanticsLabel('Locked, read only'), findsOneWidget);
      expect(find.text('Reboot required'), findsOneWidget);
      expect(
        find.byTooltip(RegExp('Restarts the audio engine')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final width in [390.0, 600.0, 900.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'responsive width $width scale $scale has no overflow in light/dark and stable feedback',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 2000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            app(scale: scale, brightness: Brightness.dark),
          );
          final before = tester.getRect(find.byType(TextField).last);
          emit(
            settingsScreenState(
              error: 'Enter a value from -100 to 100. ' * 10,
              draft: true,
            ),
          );
          await tester.pump();
          expect(tester.getRect(find.byType(TextField).last), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'unavailable screen explains demo/unsupported/offline and has no editable form',
    (tester) async {
      for (final reason in [
        'Module settings are unavailable in Demo mode.',
        'NT Settings requires recognized firmware 1.20 or later.',
        'Connect to a disting NT.',
      ]) {
        current = ModuleSettingsState(unavailableReason: reason);
        await tester.pumpWidget(app());
        emit(current);
        await tester.pump();
        expect(find.text(reason), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const Key('refresh-module-settings')),
              )
              .onPressed,
          isNull,
        );
      }
    },
  );
}
