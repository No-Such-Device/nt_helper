import 'package:flutter/material.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

/// Shows a dialog to reset all outputs with CV input selection
Future<void> showResetOutputsDialog({
  required BuildContext context,
  required int initialCvInput,
  required DeviceIoProfile deviceIoProfile,
  required int minimum,
  required int maximum,
  required void Function(int selectedInput) onReset,
}) {
  int selectedInput = initialCvInput;

  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Semantics(header: true, child: const Text('Reset all Outputs')),
        content: SizedBox(
          width: double.infinity,
          child: BusSelectionField(
            label: 'CV Input',
            model: BusSelectionModel.fromProfile(
              deviceIoProfile: deviceIoProfile,
              currentValue: selectedInput,
              minimum: minimum,
              maximum: maximum,
              allowNone: true,
            ),
            onChanged: (newValue) {
              setState(() {
                selectedInput = newValue;
              });
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onReset(selectedInput);
              Navigator.of(context).pop();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  );
}
