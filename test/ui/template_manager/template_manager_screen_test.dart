import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/models/template_metadata.dart';
import 'package:nt_helper/ui/template_manager/template_manager_screen.dart';

FullPresetSlot _slot(int index, String guid, String name) {
  return FullPresetSlot(
    slot: PresetSlotEntry(
      id: -1,
      presetId: -1,
      slotIndex: index,
      algorithmGuid: guid,
    ),
    algorithm: AlgorithmEntry(guid: guid, name: name, numSpecifications: 0),
    parameterValues: {0: 10},
    parameterStringValues: {},
    mappings: {},
  );
}

Future<void> _seedAlgorithm(AppDatabase db, String guid, String name) async {
  await db.metadataDao.upsertAlgorithms([
    AlgorithmEntry(guid: guid, name: name, numSpecifications: 0),
  ]);
}

Future<void> _saveTemplate(
  AppDatabase db,
  String name, {
  String? category,
  required TemplateMetadata metadata,
  required List<FullPresetSlot> slots,
}) async {
  await db.presetsDao.saveFullPreset(
    FullPresetDetails(
      preset: PresetEntry(
        id: -1,
        name: name,
        lastModified: DateTime(2026),
        isTemplate: true,
        category: category,
        templateMetadata: metadata.toJsonString(),
      ),
      slots: slots,
    ),
    isTemplate: true,
  );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seedAlgorithm(db, 'dely', 'Delay');
    await _seedAlgorithm(db, 'rvb', 'Reverb');
    await _saveTemplate(
      db,
      'Space Kit',
      category: 'Ambience',
      metadata: const TemplateMetadata(tags: ['wide'], author: 'Neal'),
      slots: [_slot(0, 'dely', 'Delay'), _slot(1, 'rvb', 'Reverb')],
    );
    await _saveTemplate(
      db,
      'Utility Kit',
      metadata: const TemplateMetadata(tags: ['utility']),
      slots: [_slot(0, 'dely', 'Delay')],
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('renders templates grouped by category and filters slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TemplateManagerScreen(database: db)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ambience'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(find.text('Space Kit'), findsWidgets);
    expect(find.text('wide'), findsWidgets);

    await tester.tap(find.text('Space Kit').first);
    await tester.pumpAndSettle();
    expect(find.text('Neal'), findsOneWidget);
    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('Reverb'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'verb');
    await tester.pumpAndSettle();
    expect(find.text('Delay'), findsNothing);
    expect(find.text('Reverb'), findsOneWidget);
  });

  testWidgets('selects all template slots by default and opens local apply', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: TemplateManagerScreen(database: db)),
    );
    await tester.pumpAndSettle();

    final checkboxes = tester.widgetList<Checkbox>(
      find.descendant(
        of: find.byType(CheckboxListTile),
        matching: find.byType(Checkbox),
      ),
    );
    expect(checkboxes.map((checkbox) => checkbox.value), everyElement(isTrue));

    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(find.text('Apply template slots'), findsOneWidget);
    expect(find.textContaining('2 selected from Space Kit'), findsOneWidget);
  });

  testWidgets('exposes template manager actions and state to semantics', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(home: TemplateManagerScreen(database: db)),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp(r'Template list, 2 templates')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'Space Kit, 2 slots, category Ambience, tag wide, selected'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'2 selected, 0 current slots, 2 of 40')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Import template from file'), findsWidgets);
    expect(find.bySemanticsLabel('Export selected template'), findsWidgets);

    semanticsHandle.dispose();
  });

  testWidgets('edits selected template metadata', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TemplateManagerScreen(database: db)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit metadata'));
    await tester.pumpAndSettle();

    expect(find.text('Edit template metadata'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('edit-template-name')),
      'Space Kit Deluxe',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-template-category')),
      'Performance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-template-description')),
      'Wide space rig',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-template-tags')),
      'wide, stage',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Space Kit Deluxe'), findsWidgets);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Ambience'), findsNothing);

    final edited = (await db.presetsDao.getTemplates()).singleWhere(
      (template) => template.preset.name == 'Space Kit Deluxe',
    );
    expect(edited.preset.category, 'Performance');
    final metadata = TemplateMetadata.fromJsonString(
      edited.preset.templateMetadata,
    );
    expect(metadata.description, 'Wide space rig');
    expect(metadata.tags, ['wide', 'stage']);
  });

  testWidgets('deletes selected template after confirmation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TemplateManagerScreen(database: db)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete template'));
    await tester.pumpAndSettle();

    expect(find.text('Delete template?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Space Kit'), findsNothing);
    final templates = await db.presetsDao.getTemplates();
    expect(templates.map((template) => template.preset.name), ['Utility Kit']);
  });

  testWidgets(
    'New from current preset opens creation dialog and saves template',
    (tester) async {
      final source = FullPresetDetails(
        preset: PresetEntry(
          id: -1,
          name: 'Live Preset',
          lastModified: DateTime(2026),
          isTemplate: false,
        ),
        slots: [
          FullPresetSlot(
            slot: const PresetSlotEntry(
              id: -1,
              presetId: -1,
              slotIndex: 0,
              algorithmGuid: 'dely',
              customName: 'Live Echo',
            ),
            algorithm: const AlgorithmEntry(
              guid: 'dely',
              name: 'Live Echo',
              numSpecifications: 0,
            ),
            parameterValues: {0: 10},
            parameterStringValues: {},
            mappings: {},
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TemplateManagerScreen(
            database: db,
            loadCurrentPresetSource: () async => source,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final createButton = find.byTooltip('New from current preset');
      expect(createButton, findsOneWidget);

      await tester.tap(createButton);
      await tester.pumpAndSettle();
      expect(find.text('Create Template'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('template-slot-0')).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('template-name')),
        'Live Delay Template',
      );
      await tester.tap(find.text('Create template'));
      await tester.pumpAndSettle();

      expect(find.text('Live Delay Template'), findsWidgets);

      final created = (await db.presetsDao.getTemplates()).singleWhere(
        (template) => template.preset.name == 'Live Delay Template',
      );
      expect(created.slots.single.algorithm.name, 'Delay');
      expect(created.slots.single.slot.customName, 'Live Echo');
    },
  );

  testWidgets('passes selected slots to current-device apply callback', (
    tester,
  ) async {
    FullPresetDetails? appliedTemplate;
    List<int>? appliedSlots;

    await tester.pumpWidget(
      MaterialApp(
        home: TemplateManagerScreen(
          database: db,
          onApplyDevice: (template, selectedIndices) async {
            appliedTemplate = template;
            appliedSlots = selectedIndices;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(appliedTemplate?.preset.name, 'Space Kit');
    expect(appliedSlots, [0, 1]);
  });
}
