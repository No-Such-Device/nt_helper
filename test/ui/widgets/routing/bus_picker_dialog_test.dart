import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/bus_picker_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';
import 'package:nt_helper/models/device_io_profile.dart';

void main() {
  testWidgets(
    'bus picker displays all supplied buses and marks current bus selected',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BusPickerDialog(
              portLabel: 'Output',
              model: BusSelectionModel.fromProfile(
                deviceIoProfile: DeviceIoProfile.distingLegacy,
                currentValue: 13,
                minimum: 11,
                maximum: 14,
                allowNone: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('I11'), findsOneWidget);
      expect(find.text('I12'), findsOneWidget);
      expect(find.text('O1'), findsOneWidget);
      expect(find.text('O2'), findsOneWidget);
      expect(find.bySemanticsLabel('Current bus O1'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Current bus O1'));
      // ignore: deprecated_member_use
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(find.bySemanticsLabel('Route to O2'), findsOneWidget);

      semantics.dispose();
    },
  );

  testWidgets('bus picker scrolls current bus near vertical center', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(440, 360));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusPickerDialog(
            portLabel: 'Output',
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: DeviceIoProfile.distingExtended,
              currentValue: 50,
              minimum: 1,
              maximum: 64,
              allowNone: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    final selectedY = tester.getCenter(find.text('A30')).dy;
    expect(selectedY, greaterThan(dialogRect.top + dialogRect.height * 0.30));
    expect(selectedY, lessThan(dialogRect.top + dialogRect.height * 0.80));
  });

  testWidgets('bus choices can be selected with Tab and Enter', (tester) async {
    int? selected;
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: DeviceIoProfile.distingLegacy,
      currentValue: 13,
      minimum: 13,
      maximum: 14,
      allowNone: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showDialog<int>(
                context: context,
                builder: (context) =>
                    BusPickerDialog(portLabel: 'Output', model: model),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 14);
  });
}
