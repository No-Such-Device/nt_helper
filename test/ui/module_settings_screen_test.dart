import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
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
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump();
          expect(rects(), original);
          expect(tester.takeException(), isNull);
        }
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
      expect(find.text('Change not confirmed. · Last read: 0'), findsOneWidget);
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
    for (final scale in [1.0, 2.0, 3.0]) {
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
          await tester.pump();
          expect(tester.getRect(find.byType(TextField).last), before);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'nested groups preserve menu order and bound their own settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      current = ModuleSettingsState(
        connectionId: 1,
        tree: ModuleSettingsTree(
          opaqueHeader: [0, 0, 0],
          groups: {
            0: ModuleSettingsGroup(
              id: 0,
              name: '',
              children: const [
                ModuleSettingChild(id: 3, isGroup: true),
                ModuleSettingChild(id: 9, isGroup: false),
              ],
            ),
            3: ModuleSettingsGroup(
              id: 3,
              name: 'Engine',
              children: const [
                ModuleSettingChild(id: 5, isGroup: false),
                ModuleSettingChild(id: 4, isGroup: true),
              ],
            ),
            4: ModuleSettingsGroup(
              id: 4,
              name: 'Tuning',
              children: const [ModuleSettingChild(id: 7, isGroup: false)],
            ),
          },
        ),
        settings: {
          ...current.settings,
          7: ModuleSettingEdit(
            info: settingInfo(7),
            observed: const ModuleSettingValue(0),
          ),
        },
      );
      await tester.pumpWidget(app());
      Rect field(int id) => tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('module-setting-1-$id')),
          matching: find.byType(TextField),
        ),
      );
      final engine = tester.getRect(
        find.byKey(const ValueKey('module-settings-group-3')),
      );
      expect(field(5).top, lessThan(field(7).top));
      expect(field(7).top, lessThan(field(9).top));
      expect(field(7).left, greaterThan(field(5).left));
      expect(field(9).left, lessThan(field(5).left));
      expect(engine.contains(field(5).center), isTrue);
      expect(engine.contains(field(9).center), isFalse);
      expect(
        tester
            .getSemantics(find.text('Engine'))
            .getSemanticsData()
            .headingLevel,
        1,
      );
      expect(
        tester
            .getSemantics(find.text('Tuning'))
            .getSemanticsData()
            .headingLevel,
        2,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'echoed numeric drafts preserve spelling and caret while discard restores observed text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      void publishDraft(ModuleSettingValue? value) {
        final before = current.settings[5]!;
        emit(
          ModuleSettingsState(
            connectionId: current.connectionId,
            tree: current.tree,
            settings: {
              ...current.settings,
              5: ModuleSettingEdit(
                info: before.info,
                observed: before.observed,
                draft: value,
              ),
            },
          ),
        );
      }

      when(() => cubit.editModuleSetting(5, any())).thenAnswer((i) {
        publishDraft(i.positionalArguments[1] as ModuleSettingValue);
      });
      when(() => cubit.discardModuleSettingsDrafts())
          .thenAnswer((_) => publishDraft(null));
      await tester.pumpWidget(app());
      final field = find.byType(TextField).first;
      await tester.tap(field);
      for (final text in ['007', '+5', '-0']) {
        await tester.enterText(field, text);
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, text);
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '008',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      final controller = tester.widget<TextField>(field).controller!;
      expect(controller.text, '008');
      expect(controller.selection.baseOffset, 1);
      await tester.tap(find.byTooltip('Discard drafts'));
      await tester.pump();
      expect(controller.text, '0');
    },
  );

  testWidgets('Apply retains native visible-label focus and tap semantics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    current = settingsScreenState(draft: true);
    await tester.pumpWidget(app());
    final apply = find.byKey(const ValueKey('module-settings-apply-3'));
    SemanticsData data() => tester.getSemantics(apply).getSemanticsData();
    expect(data().label, 'Apply Engine');
    expect(data().flagsCollection.isFocused, isNot(Tristate.none));
    expect(data().hasAction(SemanticsAction.tap), isTrue);
    for (
      var i = 0;
      i < 12 && data().flagsCollection.isFocused != Tristate.isTrue;
      i++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(data().flagsCollection.isFocused, Tristate.isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Apply changes to Engine?'), findsOneWidget);
    verifyNever(() => cubit.applyModuleSettingsGroup(any()));
    semantics.dispose();
  });

  testWidgets(
    'short field feedback reserves one line without a redundant detail button',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final scale in [1.0, 2.0]) {
        current = settingsScreenState(draft: true);
        await tester.pumpWidget(app(scale: scale));
        emit(current);
        await tester.pump();
        final feedback = find.byKey(
          const ValueKey('module-setting-feedback-5'),
        );
        final height = tester.getSize(feedback).height;
        expect(
          height,
          lessThanOrEqualTo((21 * scale + 8).clamp(48.0, double.infinity)),
        );
        expect(find.byTooltip('Read full status for Setting 5'), findsNothing);
        emit(
          settingsScreenState(
            draft: true,
            error: 'Change not confirmed. ' * 40,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Change not confirmed.'), findsOneWidget);
        expect(tester.getSize(feedback).height, height);
        expect(
          find.byTooltip('Read full status for Setting 5'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Read full status for Setting 5'));
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(
            SelectableText,
            '${'Change not confirmed. ' * 40}\nLast read: 0',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'three-times text labels fit buttons without async geometry changes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      current = settingsScreenState(draft: true);
      await tester.pumpWidget(app(scale: 3));
      final buttons = {
        'Commit to flash': find.widgetWithText(FilledButton, 'Commit to flash'),
        'Revert to saved': find.widgetWithText(
          OutlinedButton,
          'Revert to saved',
        ),
        'Apply Engine': find.byKey(const ValueKey('module-settings-apply-3')),
        'Apply changes': find.byKey(const ValueKey('module-settings-apply-0')),
      };
      Map<String, Rect> rects() => {
        for (final e in buttons.entries) e.key: tester.getRect(e.value),
      };
      final original = rects();
      for (final entry in buttons.entries) {
        final button = tester.getRect(entry.value);
        final label = tester.getRect(
          find.descendant(of: entry.value, matching: find.text(entry.key)),
        );
        expect(label.left, greaterThanOrEqualTo(button.left));
        expect(label.right, lessThanOrEqualTo(button.right));
        expect(label.top, greaterThanOrEqualTo(button.top));
        expect(label.bottom, lessThanOrEqualTo(button.bottom));
      }
      for (final state in [
        settingsScreenState(busy: true, draft: true, message: 'Applying…'),
        settingsScreenState(draft: true, error: 'Readback unconfirmed. ' * 30),
        settingsScreenState(draft: true),
      ]) {
        emit(state);
        for (var frame = 0; frame < 2; frame++) {
          await tester.pump();
          expect(rects(), original);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('dropdown discard restores the observed item in the same field', (
    tester,
  ) async {
    final info = settingInfo(
      5,
      unit: 1,
      min: 0,
      max: 1,
      enums: ['Left', 'Right'],
    );
    ModuleSettingsState selection(ModuleSettingValue? draft) =>
        ModuleSettingsState(
          connectionId: 1,
          tree: current.tree,
          settings: {
            ...current.settings,
            5: ModuleSettingEdit(
              info: info,
              observed: const ModuleSettingValue(0),
              draft: draft,
            ),
          },
        );
    current = selection(const ModuleSettingValue(1));
    when(() => cubit.discardModuleSettingsDrafts())
        .thenAnswer((_) => emit(selection(null)));
    await tester.pumpWidget(app());
    final finder = find.byType(DropdownButtonFormField<int>);
    final field = tester.state<FormFieldState<int>>(finder);
    expect(field.value, 1);
    await tester.tap(find.byTooltip('Discard drafts'));
    await tester.pump();
    expect(tester.state<FormFieldState<int>>(finder), same(field));
    expect(field.value, 0);
  });

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
