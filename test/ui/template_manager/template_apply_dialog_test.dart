import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/ui/template_manager/template_apply_dialog.dart';

FullPresetSlot _slot(int index, String guid) {
  return FullPresetSlot(
    slot: PresetSlotEntry(
      id: -1,
      presetId: -1,
      slotIndex: index,
      algorithmGuid: guid,
    ),
    algorithm: AlgorithmEntry(
      guid: guid,
      name: 'Alg $guid',
      numSpecifications: 0,
    ),
    parameterValues: {index: index * 10},
    parameterStringValues: {},
    mappings: {},
  );
}

Future<void> _seedAlgorithm(AppDatabase db, String guid) async {
  await db.metadataDao.upsertAlgorithms([
    AlgorithmEntry(guid: guid, name: 'Alg $guid', numSpecifications: 0),
  ]);
}

Future<int> _savePreset(
  AppDatabase db,
  String name, {
  required bool isTemplate,
  required List<FullPresetSlot> slots,
}) {
  return db.presetsDao.saveFullPreset(
    FullPresetDetails(
      preset: PresetEntry(
        id: -1,
        name: name,
        lastModified: DateTime(2026),
        isTemplate: isTemplate,
      ),
      slots: slots,
    ),
    isTemplate: isTemplate,
  );
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required AppDatabase db,
  required FullPresetDetails template,
  required Set<int> selected,
  Future<void> Function()? onApplyDevice,
  VoidCallback? onCancelDeviceApply,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TemplateApplyDialog(
          database: db,
          template: template,
          selectedIndices: selected,
          onApplyDevice: onApplyDevice,
          onCancelDeviceApply: onCancelDeviceApply,
        ),
      ),
    ),
  );
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

  testWidgets('applies selected slots to an existing preset', (tester) async {
    final templateId = await _savePreset(
      db,
      'Starter',
      isTemplate: true,
      slots: [_slot(0, 'AAAA'), _slot(1, 'BBBB')],
    );
    final targetId = await _savePreset(
      db,
      'Target',
      isTemplate: false,
      slots: const [],
    );
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;

    await _pumpDialog(tester, db: db, template: template, selected: {1});
    await tester.pumpAndSettle();

    expect(find.text('Target'), findsOneWidget);
    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Applied 1 slot'), findsOneWidget);
    final target = (await db.presetsDao.getFullPresetDetails(targetId))!;
    expect(target.slots.map((slot) => slot.slot.algorithmGuid), ['BBBB']);
  });

  testWidgets('replace mode replaces from the selected start slot', (
    tester,
  ) async {
    final templateId = await _savePreset(
      db,
      'Starter',
      isTemplate: true,
      slots: [_slot(0, 'BBBB')],
    );
    final targetId = await _savePreset(
      db,
      'Target',
      isTemplate: false,
      slots: [_slot(0, 'AAAA'), _slot(1, 'AAAA')],
    );
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;

    await _pumpDialog(tester, db: db, template: template, selected: {0});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Replace existing slots'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Applied 1 slot'), findsOneWidget);
    final target = (await db.presetsDao.getFullPresetDetails(targetId))!;
    expect(target.slots.map((slot) => slot.slot.algorithmGuid), [
      'BBBB',
      'AAAA',
    ]);
  });

  testWidgets('renders TemplateSpaceException diagnostics', (tester) async {
    final templateId = await _savePreset(
      db,
      'Too Big',
      isTemplate: true,
      slots: [_slot(0, 'AAAA'), _slot(1, 'BBBB')],
    );
    await _savePreset(
      db,
      'Crowded',
      isTemplate: false,
      slots: [for (var i = 0; i < 39; i++) _slot(i, 'AAAA')],
    );
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;

    await _pumpDialog(tester, db: db, template: template, selected: {0, 1});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(find.textContaining('39 existing'), findsOneWidget);
    expect(
      find.text('39 existing + 2 selected exceeds the 40-slot limit.'),
      findsOneWidget,
    );
    expect(find.textContaining('40-slot limit'), findsOneWidget);
  });

  testWidgets('device apply cancel button invokes cancellation callback', (
    tester,
  ) async {
    final templateId = await _savePreset(
      db,
      'Starter',
      isTemplate: true,
      slots: [_slot(0, 'AAAA')],
    );
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;
    final completer = Completer<void>();
    var cancelled = false;

    await _pumpDialog(
      tester,
      db: db,
      template: template,
      selected: {0},
      onApplyDevice: () => completer.future,
      onCancelDeviceApply: () => cancelled = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected'));
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelled, isTrue);
    completer.complete();
  });

  testWidgets('current device target is disabled without apply callback', (
    tester,
  ) async {
    final templateId = await _savePreset(
      db,
      'Starter',
      isTemplate: true,
      slots: [_slot(0, 'AAAA')],
    );
    await _savePreset(db, 'Target', isTemplate: false, slots: const []);
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;

    await _pumpDialog(tester, db: db, template: template, selected: {0});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current device'));
    await tester.pumpAndSettle();

    expect(find.text('Target preset'), findsOneWidget);
  });

  testWidgets('device apply surfaces callback failures instead of success', (
    tester,
  ) async {
    final templateId = await _savePreset(
      db,
      'Starter',
      isTemplate: true,
      slots: [_slot(0, 'AAAA')],
    );
    final template = (await db.presetsDao.getFullPresetDetails(templateId))!;

    await _pumpDialog(
      tester,
      db: db,
      template: template,
      selected: {0},
      onApplyDevice: () async => throw StateError('device failed'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Current device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply selected'));
    await tester.pumpAndSettle();

    expect(find.textContaining('device failed'), findsOneWidget);
    expect(find.textContaining('Applied 1 slot'), findsNothing);
  }, tags: ['regression']);
}
