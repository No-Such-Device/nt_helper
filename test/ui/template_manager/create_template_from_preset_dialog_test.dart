import 'dart:convert';

import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/ui/template_manager/create_template_from_preset_dialog.dart';

FullPresetSlot _slot(
  int index,
  String guid, {
  List<int> specificationValues = const [],
}) {
  return FullPresetSlot(
    slot: PresetSlotEntry(
      id: -1,
      presetId: -1,
      slotIndex: index,
      algorithmGuid: guid,
      customName: 'Slot $index',
    ),
    algorithm: AlgorithmEntry(
      guid: guid,
      name: 'Alg $guid',
      numSpecifications: specificationValues.length,
    ),
    specificationValues: specificationValues,
    parameterValues: {index: index + 100},
    parameterStringValues: {},
    mappings: {},
  );
}

Future<void> _seedAlgorithm(AppDatabase db, String guid) async {
  await db.metadataDao.upsertAlgorithms([
    AlgorithmEntry(guid: guid, name: 'Alg $guid', numSpecifications: 0),
  ]);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seedAlgorithm(db, 'AAAA');
    await _seedAlgorithm(db, 'BBBB');
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('creates a template from selected preset slots with metadata', (
    tester,
  ) async {
    final source = FullPresetDetails(
      preset: PresetEntry(
        id: 7,
        name: 'Source',
        lastModified: DateTime(2026),
        isTemplate: false,
      ),
      slots: [_slot(0, 'AAAA'), _slot(1, 'BBBB')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => CreateTemplateFromPresetDialog(
                    database: db,
                    source: source,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('template-name')),
      'FX Pair',
    );
    await tester.enterText(
      find.byKey(const ValueKey('template-category')),
      'Ambience',
    );
    await tester.enterText(
      find.byKey(const ValueKey('template-description')),
      'Delay and reverb',
    );
    await tester.enterText(
      find.byKey(const ValueKey('template-tags')),
      'wide, live',
    );
    await tester.enterText(
      find.byKey(const ValueKey('template-author')),
      'Neal',
    );
    await tester.tap(find.byTooltip('Select all visible slots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create template'));
    await tester.pumpAndSettle();

    final templates = await db.presetsDao.getTemplates();
    expect(templates, hasLength(1));
    final created = templates.single;
    expect(created.preset.name, 'FX Pair');
    expect(created.preset.category, 'Ambience');
    expect(created.slots, hasLength(2));
    expect(created.slots.map((slot) => slot.slot.slotIndex), [0, 1]);
    expect(created.slots.map((slot) => slot.slot.algorithmGuid), [
      'AAAA',
      'BBBB',
    ]);
    expect(created.slots.last.parameterValues[1], 101);

    final metadata =
        jsonDecode(created.preset.templateMetadata!) as Map<String, dynamic>;
    expect(metadata['description'], 'Delay and reverb');
    expect(metadata['tags'], ['wide', 'live']);
    expect(metadata['author'], 'Neal');
    expect(metadata['schemaVersion'], 1);
  });

  testWidgets('preserves user-selected specifications in the template', (
    tester,
  ) async {
    final source = FullPresetDetails(
      preset: PresetEntry(
        id: 7,
        name: 'Quantizer Source',
        lastModified: DateTime(2026),
        isTemplate: false,
      ),
      slots: [
        _slot(0, 'AAAA', specificationValues: const [4]),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => CreateTemplateFromPresetDialog(
                    database: db,
                    source: source,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible slots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create template'));
    await tester.pumpAndSettle();

    final created = (await db.presetsDao.getTemplates()).single;
    expect(created.slots.single.specificationValues, const [4]);
  });
}
