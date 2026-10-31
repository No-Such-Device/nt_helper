import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/offline_disting_midi_manager.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_page.dart';
import 'package:nt_helper/ui/metadata_sync/metadata_sync_cubit.dart';
import 'package:nt_helper/ui/widgets/slot_detail_view.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode_selector.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

Future<void> _waitForLocalData(WidgetTester tester) async {
  final metadata = tester
      .element(find.byType(Scaffold).last)
      .read<MetadataSyncCubit>();
  await tester.runAsync(() async {
    if (metadata.state is! ViewingLocalData) {
      await metadata.stream.firstWhere((state) => state is ViewingLocalData);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'saved offline preset is loaded in controller and selected in both lists',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final cubit = DistingCubit(database, midiCommand: MockMidiCommand());
      addTearDown(() async {
        await cubit.close();
        await database.close();
      });
      await database
          .into(database.algorithms)
          .insert(
            const AlgorithmsCompanion(
              guid: Value('plug'),
              name: Value('Cached Plugin'),
              numSpecifications: Value(0),
            ),
          );
      final presetId = await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Saved Offline',
            lastModified: DateTime(2026),
            isTemplate: true,
          ),
          slots: [
            FullPresetSlot(
              slot: const PresetSlotEntry(
                id: -1,
                presetId: -1,
                slotIndex: 0,
                algorithmGuid: 'plug',
                customName: 'My Plugin',
              ),
              algorithm: const AlgorithmEntry(
                guid: 'plug',
                name: 'Cached Plugin',
                numSpecifications: 0,
              ),
              parameterValues: const {0: -12, 2: 73},
              parameterStringValues: const {},
              mappings: const {},
            ),
          ],
        ),
        isTemplate: true,
      );
      final details = (await database.presetsDao.getFullPresetDetails(
        presetId,
      ))!;
      await cubit.goOffline();
      await cubit.loadPresetOffline(details);

      final controller = DistingControllerImpl(cubit);
      expect((await controller.getAllSlots()).length, 1);
      expect((await controller.getAlgorithmInSlot(0))?.guid, 'plug');
      expect((await controller.getAlgorithmInSlot(0))?.name, 'My Plugin');
      expect(await controller.getAlgorithmInSlot(1), isNull);
      expect((await controller.getParametersForSlot(0)).length, 3);
      expect((await controller.getParameterValue(0, 0))?.value, -12);
      expect((await controller.getParameterValue(0, 2))?.value, 73);
      expect(
        (cubit.requireDisting() as OfflineDistingMidiManager).loadedPresetId,
        presetId,
      );

      await tester.pumpWidget(
        RepositoryProvider<AppDatabase>.value(
          value: database,
          child: MaterialApp(home: MetadataSyncPage(distingCubit: cubit)),
        ),
      );
      await _waitForLocalData(tester);
      await tester.pumpAndSettle();

      final savedTile = find.byKey(ValueKey(presetId));
      expect(savedTile, findsOneWidget);
      expect(tester.widget<ListTile>(savedTile).selected, isTrue);

      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await _waitForLocalData(tester);
      await tester.pumpAndSettle();
      final templateTiles = tester.widgetList<ListTile>(
        find.byKey(ValueKey(presetId)),
      );
      expect(templateTiles, isNotEmpty);
      expect(templateTiles.every((tile) => tile.selected), isTrue);

      await tester.runAsync(cubit.newPreset);
      await tester.pumpAndSettle();
      await _waitForLocalData(tester);
      await tester.pumpAndSettle();
      expect(
        (cubit.requireDisting() as OfflineDistingMidiManager).loadedPresetId,
        isNull,
      );
      expect(await controller.getAllSlots(), isEmpty);
      expect(
        tester
            .widgetList<ListTile>(find.byKey(ValueKey(presetId)))
            .every((tile) => !tile.selected),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'unknown algorithm warns after load and exposes no editing controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final cubit = DistingCubit(database, midiCommand: MockMidiCommand());
      addTearDown(() async {
        await cubit.close();
        await database.close();
      });
      await database.customStatement('PRAGMA foreign_keys = OFF');
      // An interrupted metadata import can leave parameter rows without their
      // catalog entry. They must not make an unavailable algorithm editable.
      await database
          .into(database.parameters)
          .insert(
            const ParametersCompanion(
              algorithmGuid: Value('miss'),
              parameterNumber: Value(0),
              name: Value('Orphaned parameter'),
              minValue: Value(0),
              maxValue: Value(100),
              defaultValue: Value(50),
            ),
          );
      await database.presetsDao.saveFullPreset(
        FullPresetDetails(
          preset: PresetEntry(
            id: -1,
            name: 'Downloaded',
            lastModified: DateTime(2026),
            isTemplate: false,
          ),
          slots: [
            FullPresetSlot(
              slot: const PresetSlotEntry(
                id: -1,
                presetId: -1,
                slotIndex: 0,
                algorithmGuid: 'miss',
              ),
              algorithm: const AlgorithmEntry(
                guid: 'miss',
                name: 'Missing Plugin',
                numSpecifications: 0,
              ),
              parameterValues: const {0: 42},
              parameterStringValues: const {},
              mappings: const {},
            ),
          ],
        ),
      );
      await cubit.goOffline();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepositoryProvider<AppDatabase>.value(
          value: database,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Main screen')),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MetadataSyncPage(distingCubit: cubit),
        ),
      );
      await tester.pumpAndSettle();
      await _waitForLocalData(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Load Preset Offline'));
      await tester.pumpAndSettle();
      final loaded = cubit.stream.firstWhere(
        (state) =>
            state is DistingStateSynchronized &&
            !state.loading &&
            state.slots.length == 1,
      );
      await tester.tap(find.text('Load Offline'));
      await tester.runAsync(() async {
        await loaded;
      });
      await tester.pumpAndSettle();
      expect(find.byType(MetadataSyncPage), findsNothing);
      expect(find.text('Main screen'), findsOneWidget);
      expect(
        find.textContaining('1 algorithm(s) unavailable offline (miss)'),
        findsOneWidget,
      );
      final state = cubit.state as DistingStateSynchronized;
      final manager = state.disting as OfflineDistingMidiManager;
      expect(manager.unavailableSlotIndices, {0});
      expect((await manager.requestNumberOfParameters(0))!.numParameters, 0);
      expect(await manager.requestParameterInfo(0, 0), isNull);
      expect((await manager.requestParameterPages(0))!.pages, isEmpty);
      expect(state.slots.single.parameters, isEmpty);
      expect(
        (await manager.requestCurrentPresetDetails())!
            .slots
            .single
            .parameterValues,
        {0: 42},
      );

      final sections = AlgorithmControllerSectionController(
        initiallyCollapsed: false,
      );
      addTearDown(sections.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: SlotDetailView(
            slot: state.slots.single,
            slotIndex: 0,
            units: state.unitStrings,
            firmwareVersion: state.firmwareVersion,
            algorithmControllerSections: sections,
            editorMode: SlotEditorMode.standard,
            onEditorModeChanged: (_) {},
            unavailableOffline: true,
          ),
        ),
      );
      expect(find.byType(SlotEditorModeSelector), findsNothing);
      final notice = find.textContaining(
        'Algorithm miss is unavailable offline.',
      );
      expect(notice, findsOneWidget);
      expect(
        tester.getSemantics(notice).label,
        contains('saved data are preserved'),
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
