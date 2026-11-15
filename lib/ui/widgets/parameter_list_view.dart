import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/parameter_editor_view.dart';
import 'package:nt_helper/ui/widgets/parameter_value_edit_traversal_scope.dart';

class ParameterListView extends StatelessWidget {
  final Slot slot;
  final List<String> units;

  const ParameterListView({super.key, required this.slot, required this.units});

  @override
  Widget build(BuildContext context) {
    return ParameterValueEditTraversalScope(
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView.builder(
          // ignore: deprecated_member_use
          cacheExtent: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          itemCount: slot.parameters.length,
          itemBuilder: (context, index) {
            // Use safe access with bounds checking
            final parameter = slot.parameters.elementAtOrNull(index);
            final value = slot.values.elementAtOrNull(index);
            final enumStrings = slot.enums.elementAtOrNull(index);
            final mapping = slot.mappings.elementAtOrNull(index);
            final valueString = slot.valueStrings.elementAtOrNull(index);

            // Skip this parameter if we don't have essential data
            // Note: valueString and enumStrings can be empty/filler for many parameters
            if (parameter == null || value == null) {
              return const SizedBox.shrink();
            }

            // Use filler/empty data if not available
            final safeEnumStrings =
                enumStrings ?? ParameterEnumStrings.filler();
            final safeValueString =
                valueString ?? ParameterValueString.filler();

            // For string-type parameters, don't fetch unit - they use value strings
            // The registry handles firmware version differences automatically
            final shouldShowUnit = !ParameterEditorRegistry.isStringTypeUnit(
              parameter.unit,
            );
            final unit = shouldShowUnit ? parameter.getUnitString(units) : null;

            return FocusTraversalOrder(
              order: NumericFocusOrder(index.toDouble()),
              child: ParameterEditorView(
                slot: slot,
                parameterInfo: parameter,
                value: value,
                enumStrings: safeEnumStrings,
                mapping: mapping,
                valueString: safeValueString,
                unit: unit,
                parameterValueTraversalId:
                    'parameter-list-${slot.algorithm.algorithmIndex}-$index',
                parameterValueTraversalOrder: index.toDouble(),
              ),
            );
          },
        ),
      ),
    );
  }
}
