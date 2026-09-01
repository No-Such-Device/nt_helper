import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/reset_outputs_dialog.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';

void main() {
  testWidgets('Reset Outputs uses the shared picker and saves its value', (
    tester,
  ) async {
    final profile = DeviceIoProfile.tryCreate(
      inputBusCount: 4,
      outputBusCount: 3,
      auxBusCount: 5,
    )!;
    int? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showResetOutputsDialog(
              context: context,
              initialCvInput: 0,
              deviceIoProfile: profile,
              minimum: 0,
              maximum: 10,
              onReset: (value) => selected = value,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(BusSelectionField), findsOneWidget);
    expect(find.byType(DropdownMenu<int>), findsNothing);
    final picker = tester.widget<BusSelectionField>(
      find.byType(BusSelectionField),
    );
    expect(picker.model.choices.map((choice) => choice.value), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
    ]);

    picker.onChanged(5);
    await tester.pump();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(selected, 5);
  });
}
