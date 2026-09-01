import 'package:flutter/material.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/parameter_view_row.dart';

class ParameterEditorView extends StatelessWidget {
  final Slot slot;
  final ParameterInfo parameterInfo;
  final ParameterValue value;
  final ParameterEnumStrings enumStrings;
  final Mapping? mapping;
  final ParameterValueString valueString;
  final String? unit;
  final Object? parameterValueTraversalId;
  final double? parameterValueTraversalOrder;
  final bool parameterValueEditingEnabled;

  const ParameterEditorView({
    super.key,
    required this.slot,
    required this.parameterInfo,
    required this.value,
    required this.enumStrings,
    required this.mapping,
    required this.valueString,
    this.unit,
    this.parameterValueTraversalId,
    this.parameterValueTraversalOrder,
    this.parameterValueEditingEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    // For string-type parameters, don't pass unit - they use value strings
    // The registry handles firmware version differences automatically
    final shouldShowUnit = !ParameterEditorRegistry.isStringTypeUnit(
      parameterInfo.unit,
    );

    // I/O (routing) parameters carry a bus number as their value. They render
    // the routing bus picker instead of a flat enum dropdown.
    final isRoutingParameter = parameterInfo.isInput || parameterInfo.isOutput;

    // Check if we have a complete set of enum strings (all non-empty)
    // Partial enums (e.g., ["Off", "", "", ...]) should not be treated as dropdowns
    final hasCompleteEnumStrings =
        enumStrings.values.isNotEmpty &&
        enumStrings.values.every((s) => s.isNotEmpty);

    // For the current value, check if there's a valid enum string to display
    // This handles partial enums where only some indices have strings (e.g., only index 0 = "Off")
    final currentValueHasEnumString =
        enumStrings.values.isNotEmpty &&
        value.value >= 0 &&
        value.value < enumStrings.values.length &&
        enumStrings.values[value.value].isNotEmpty;

    // Determine the display string to use
    // For partial enums (like unit 16 file/folder), prefer enum string over valueString,
    // but only if the enum string is non-empty
    // Unit 16 is also used by parameters whose firmware value string carries
    // the useful display unit (for example Looper envelope times). Some ES-5
    // output parameters can return a stale "Off" string after moving away from
    // value 0, so suppress only that known stale case.
    final unit16ValueString =
        valueString.value.isNotEmpty &&
            !(parameterInfo.unit == 16 &&
                value.value != 0 &&
                valueString.value == 'Off')
        ? valueString.value
        : null;

    final effectiveDisplayString = currentValueHasEnumString
        ? enumStrings.values[value.value]
        : (parameterInfo.unit == 16
              ? unit16ValueString
              : (valueString.value.isNotEmpty ? valueString.value : null));

    return ParameterViewRow(
      name: parameterInfo.name,
      min: parameterInfo.min,
      max: parameterInfo.max,
      algorithmIndex: parameterInfo.algorithmIndex,
      parameterNumber: parameterInfo.parameterNumber,
      powerOfTen: parameterInfo.powerOfTen,
      defaultValue: parameterInfo.defaultValue,
      isRoutingParameter: isRoutingParameter,
      displayString: effectiveDisplayString,
      dropdownItems: (hasCompleteEnumStrings && !isRoutingParameter)
          ? enumStrings.values
          : null,
      isOnOff:
          (hasCompleteEnumStrings &&
          enumStrings.values.length >= 2 &&
          enumStrings.values[0] == "Off" &&
          enumStrings.values[1] == "On"),
      initialValue:
          isRoutingParameter ||
              (value.value >= parameterInfo.min &&
                  value.value <= parameterInfo.max)
          ? value.value
          : parameterInfo.defaultValue,
      unit: shouldShowUnit ? unit : null,
      parameterUnit: parameterInfo.unit,
      mappingData: mapping?.packedMappingData,
      slot: slot,
      isDisabled: value.isDisabled,
      parameterValueTraversalId: parameterValueTraversalId,
      parameterValueTraversalOrder: parameterValueTraversalOrder,
      parameterValueEditingEnabled:
          parameterValueEditingEnabled && !value.isDisabled,
    );
  }
}
