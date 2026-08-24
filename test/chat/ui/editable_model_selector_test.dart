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
    expect(dropdown.dropdownMenuEntries.map((entry) => entry.label), [
      'saved-model',
      'Discovered Model',
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

  testWidgets('keeps controls fixed while discovery state changes', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'saved-model');
    addTearDown(controller.dispose);

    Future<(Size, Offset, Offset)> pumpState({
      required double textScale,
      required bool loading,
      required String? error,
      required List<LlmModelOption> suggestions,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: SizedBox(
                width: 400,
                child: Column(
                  children: [
                    EditableModelSelector(
                      fieldKey: const ValueKey('stable-model'),
                      controller: controller,
                      suggestions: suggestions,
                      hintText: 'model-id',
                      loading: loading,
                      error: error,
                      onRefresh: () async {},
                    ),
                    const Text('Following control'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return (
        tester.getSize(find.byType(EditableModelSelector)),
        tester.getTopLeft(find.text('Refresh model list')),
        tester.getTopLeft(find.text('Following control')),
      );
    }

    for (final textScale in [1.0, 1.5]) {
      final loading = await pumpState(
        textScale: textScale,
        loading: true,
        error: null,
        suggestions: const [],
      );
      final empty = await pumpState(
        textScale: textScale,
        loading: false,
        error: null,
        suggestions: const [],
      );
      final success = await pumpState(
        textScale: textScale,
        loading: false,
        error: null,
        suggestions: const [
          LlmModelOption(id: 'new-model', displayName: 'New Model'),
        ],
      );
      final error = await pumpState(
        textScale: textScale,
        loading: false,
        error:
            'Codex version metadata was not found. Open Codex once to '
            'refresh it, then try again.',
        suggestions: const [],
      );

      for (final state in [empty, success, error]) {
        expect(state.$1, loading.$1);
        expect(state.$2, loading.$2);
        expect(state.$3, loading.$3);
      }
    }
  });
}
