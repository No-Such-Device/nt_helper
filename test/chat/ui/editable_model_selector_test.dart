import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/chat/services/model_catalog_service.dart';
import 'package:nt_helper/chat/ui/editable_model_selector.dart';

void main() {
  testWidgets('offers discovered models and accepts an arbitrary model ID', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'saved-model');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EditableModelSelector(
              fieldKey: const ValueKey('model'),
              controller: controller,
              suggestions: const [
                LlmModelOption(
                  id: 'discovered-model',
                  displayName: 'Discovered Model',
                ),
              ],
              hintText: 'model-id',
              loading: false,
              error: null,
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );

    final dropdown = tester.widget<DropdownMenu<String>>(
      find.byKey(const ValueKey('model')),
    );
    expect(dropdown.enableFilter, isTrue);
    expect(dropdown.requestFocusOnTap, isTrue);
    expect(dropdown.dropdownMenuEntries.map((entry) => entry.value), [
      'saved-model',
      'discovered-model',
    ]);

    await tester.enterText(find.byType(TextField), 'future-model');

    expect(controller.text, 'future-model');
  });

  testWidgets('announces discovery state and exposes refresh action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var refreshCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: EditableModelSelector(
              fieldKey: const ValueKey('model'),
              controller: controller,
              suggestions: const [],
              hintText: 'model-id',
              loading: false,
              error: 'Model discovery failed. Manual entry is still allowed.',
              onRefresh: () async => refreshCount++,
            ),
          ),
        ),
      ),
    );

    final errorSemantics = tester.getSemantics(
      find.text('Model discovery failed. Manual entry is still allowed.'),
    );
    expect(
      errorSemantics.getSemanticsData().flagsCollection.isLiveRegion,
      true,
    );
    expect(find.bySemanticsLabel('Refresh model list'), findsOneWidget);

    await tester.tap(find.text('Refresh model list'));
    await tester.pump();

    expect(refreshCount, 1);
    semantics.dispose();
  });
}
