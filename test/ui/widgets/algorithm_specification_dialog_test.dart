import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/algorithm_specification_dialog.dart';

void main() {
  late List<Object?> accessibilityMessages;
  late AlgorithmInfo algorithm;

  setUp(() {
    accessibilityMessages = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
          Object? message,
        ) async {
          accessibilityMessages.add(message);
          return null;
        });

    algorithm = AlgorithmInfo(
      algorithmIndex: 0,
      guid: 'spec-test',
      name: 'Specification Test',
      specifications: [
        Specification(name: 'Stereo', min: 0, max: 1, defaultValue: 0, type: 2),
        Specification(
          name: 'Offset',
          min: -12,
          max: 12,
          defaultValue: 0,
          type: 0,
        ),
        Specification(name: 'Voices', min: 1, max: 4, defaultValue: 2, type: 0),
      ],
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        );
  });

  Widget buildLauncher({
    required List<int> initialValues,
    required ValueChanged<List<int>?> onResult,
    String? title,
    String primaryActionLabel = 'Add',
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              onResult(
                await AlgorithmSpecificationDialog.show(
                  context: context,
                  algorithm: algorithm,
                  initialValues: initialValues,
                  readOnly: false,
                  title: title,
                  primaryActionLabel: primaryActionLabel,
                ),
              );
            },
            child: const Text('Open dialog'),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Respecify labels accessible controls and returns edited current values',
    (tester) async {
      final semantics = tester.ensureSemantics();
      List<int>? result;

      await tester.pumpWidget(
        buildLauncher(
          initialValues: const [1, -7, 3],
          title: 'Respecify Specification Test',
          primaryActionLabel: 'Respecify',
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      final titleNode = tester.getSemantics(
        find.text('Respecify Specification Test'),
      );
      expect(titleNode.flagsCollection.isHeader, isTrue);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('spec-test_spec_0')))
            .label,
        contains('Stereo'),
      );
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any(
              (widget) =>
                  widget.properties.hint == 'Off sends 0, on sends 1' &&
                  widget.properties.toggled == true,
            ),
        isTrue,
      );

      final offsetField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('spec-test_spec_1')),
          matching: find.byType(TextField),
        ),
      );
      final voicesField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('spec-test_spec_2')),
          matching: find.byType(TextField),
        ),
      );
      expect(offsetField.controller?.text, '-7');
      expect(voicesField.controller?.text, '3');
      expect(
        offsetField.keyboardType,
        const TextInputType.numberWithOptions(signed: true),
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('spec-test_spec_1')))
            .label,
        contains('Offset (-12-12)'),
      );
      expect(
        tester
            .getSemantics(find.widgetWithText(ElevatedButton, 'Respecify'))
            .label,
        'Respecify',
      );

      await tester.tap(find.byKey(const ValueKey('spec-test_spec_0')));
      await tester.enterText(
        find.byKey(const ValueKey('spec-test_spec_1')),
        '-9',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pumpAndSettle();

      expect(result, [0, -9, 3]);
      expect(find.text('Respecify Specification Test'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'invalid values focus the first invalid field and announce error',
    (tester) async {
      List<int>? result;

      await tester.pumpWidget(
        buildLauncher(
          initialValues: const [0, -2, 2],
          title: 'Respecify Specification Test',
          primaryActionLabel: 'Respecify',
          onResult: (value) => result = value,
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('spec-test_spec_1')),
        '-13',
      );
      await tester.enterText(
        find.byKey(const ValueKey('spec-test_spec_2')),
        '5',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Respecify'));
      await tester.pumpAndSettle();

      expect(find.text('Respecify Specification Test'), findsOneWidget);
      expect(find.text('Offset must be between -12 and 12'), findsOneWidget);
      expect(find.text('Voices must be between 1 and 4'), findsOneWidget);
      final offsetField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('spec-test_spec_1')),
          matching: find.byType(TextField),
        ),
      );
      expect(offsetField.focusNode?.hasFocus, isTrue);
      expect(
        accessibilityMessages.map((message) => message.toString()).join('\n'),
        contains('Offset must be between -12 and 12'),
      );
      expect(result, isNull);
    },
  );

  testWidgets('default mode retains Configure title and Add action', (
    tester,
  ) async {
    List<int>? result;

    await tester.pumpWidget(
      buildLauncher(
        initialValues: const [0, 4, 2],
        onResult: (value) => result = value,
      ),
    );
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Configure Specification Test'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Add'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
    await tester.pumpAndSettle();

    expect(result, [0, 4, 2]);
  });
}
