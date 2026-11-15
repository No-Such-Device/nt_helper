import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/ui/template_manager/template_slot_selection_list.dart';

FullPresetDetails _template() {
  FullPresetSlot slot(int index, String guid, String name) {
    return FullPresetSlot(
      slot: PresetSlotEntry(
        id: index + 1,
        presetId: 1,
        slotIndex: index,
        algorithmGuid: guid,
      ),
      algorithm: AlgorithmEntry(guid: guid, name: name, numSpecifications: 0),
      parameterValues: {0: index},
      parameterStringValues: {},
      mappings: {},
    );
  }

  return FullPresetDetails(
    preset: PresetEntry(
      id: 1,
      name: 'Starter',
      lastModified: DateTime(2026),
      isTemplate: true,
    ),
    slots: [
      slot(0, 'dely', 'Delay'),
      slot(1, 'chor', 'Chorus'),
      slot(2, 'rvb', 'Reverb'),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Set<int> selected,
  required ValueChanged<Set<int>> onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TemplateSlotSelectionList(
          template: _template(),
          selectedIndices: selected,
          onSelectionChanged: onChanged,
          currentTargetSlotCount: 4,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('toggles rows and supports the visible selection toggle', (
    tester,
  ) async {
    var selected = <int>{};

    await _pump(
      tester,
      selected: selected,
      onChanged: (next) => selected = next,
    );

    await tester.tap(find.text('Delay'));
    await tester.pumpAndSettle();
    expect(selected, {0});

    await _pump(
      tester,
      selected: selected,
      onChanged: (next) => selected = next,
    );
    await tester.tap(find.byTooltip('Select all visible slots'));
    await tester.pumpAndSettle();
    expect(selected, {0, 1, 2});

    await _pump(
      tester,
      selected: selected,
      onChanged: (next) => selected = next,
    );
    await tester.tap(find.byTooltip('Clear visible slot selection'));
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
  });

  testWidgets('filters by algorithm name and renders space readout', (
    tester,
  ) async {
    await _pump(tester, selected: {0, 2}, onChanged: (_) {});

    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('Chorus'), findsOneWidget);
    expect(
      find.textContaining('2 selected + 4 current = 6 / 40'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), 'verb');
    await tester.pumpAndSettle();

    expect(find.text('Delay'), findsNothing);
    expect(find.text('Chorus'), findsNothing);
    expect(find.text('Reverb'), findsOneWidget);
  });
}
