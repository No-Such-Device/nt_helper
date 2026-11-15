import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/parameter_number_lookup.dart';

const universalBypassParameterNumber = 0;

ParameterInfo? universalBypassParameter(Slot slot) {
  final parameter = slot.parameters.byParameterNumber(
    universalBypassParameterNumber,
  );
  if (parameter == null ||
      parameter.name != 'Bypass' ||
      parameter.min != 0 ||
      parameter.max != 1) {
    return null;
  }
  return parameter;
}

bool isUniversalBypassParameter(Slot slot, int parameterNumber) {
  return parameterNumber == universalBypassParameterNumber &&
      universalBypassParameter(slot) != null;
}

bool isBypassOnlyPage(Slot slot, int pageIndex) {
  if (pageIndex < 0 || pageIndex >= slot.pages.pages.length) return false;
  final parameters = slot.pages.pages[pageIndex].parameters;
  return parameters.isNotEmpty &&
      parameters.every(
        (parameterNumber) => isUniversalBypassParameter(slot, parameterNumber),
      );
}

class SlotBypassControl extends StatefulWidget {
  const SlotBypassControl({super.key, required this.slot, this.focusNode});

  final Slot slot;
  final FocusNode? focusNode;

  @override
  State<SlotBypassControl> createState() => _SlotBypassControlState();
}

class _SlotBypassControlState extends State<SlotBypassControl> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final binding = _binding();
    final name = binding?.parameter.name ?? 'Bypass';
    final displayValue = binding == null
        ? 'unavailable'
        : _displayValue(binding, binding.value);
    final selected = binding != null && binding.value == binding.parameter.max;
    final enabled = binding != null && !binding.disabled && !_updating;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      toggled: selected,
      label: name,
      value: displayValue,
      hint: enabled ? 'Toggle algorithm bypass' : null,
      child: ExcludeSemantics(
        child: FilterChip(
          key: const ValueKey('slot-bypass-toggle'),
          focusNode: widget.focusNode,
          avatar: Icon(
            selected
                ? Icons.power_off_rounded
                : Icons.power_settings_new_rounded,
            size: 18,
          ),
          label: _fixedWidthLabel(binding, name, displayValue),
          selected: selected,
          showCheckmark: false,
          onSelected: enabled ? (_) => _toggle(binding) : null,
        ),
      ),
    );
  }

  Widget _fixedWidthLabel(
    _BypassBinding? binding,
    String name,
    String displayValue,
  ) {
    final currentLabel = '$name: $displayValue';
    final labels = <String>{currentLabel};
    if (binding != null) {
      for (
        var value = binding.parameter.min;
        value <= binding.parameter.max;
        value++
      ) {
        labels.add('$name: ${_displayValue(binding, value)}');
      }
    }

    return _FixedWidthBypassLabel(currentLabel: currentLabel, labels: labels);
  }

  _BypassBinding? _binding() {
    final parameter = universalBypassParameter(widget.slot);
    if (parameter == null) return null;
    final value = widget.slot.values.byParameterNumber(
      parameter.parameterNumber,
    );
    final enums = widget.slot.enums.byParameterNumber(
      parameter.parameterNumber,
    );
    final valueString = widget.slot.valueStrings.byParameterNumber(
      parameter.parameterNumber,
    );
    return _BypassBinding(
      parameter: parameter,
      value: value?.value ?? parameter.defaultValue,
      disabled: value?.isDisabled ?? false,
      enumValues: [
        for (final enumValue in enums?.values ?? const <String>[])
          enumValue.trim(),
      ],
      displayValue: valueString?.value.trim() ?? '',
    );
  }

  String _displayValue(_BypassBinding binding, int value) {
    if (value == binding.value && binding.displayValue.isNotEmpty) {
      return binding.displayValue;
    }
    if (value >= 0 &&
        value < binding.enumValues.length &&
        binding.enumValues[value].isNotEmpty) {
      return binding.enumValues[value];
    }
    return value.toString();
  }

  Future<void> _toggle(_BypassBinding binding) async {
    final nextValue = binding.value == binding.parameter.max
        ? binding.parameter.min
        : binding.parameter.max;
    setState(() => _updating = true);
    try {
      await context.read<DistingCubit>().updateParameterValue(
        algorithmIndex: widget.slot.algorithm.algorithmIndex,
        parameterNumber: binding.parameter.parameterNumber,
        value: nextValue,
        userIsChangingTheValue: false,
      );
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${binding.parameter.name} ${_displayValue(binding, nextValue)}',
        Directionality.of(context),
      );
    } catch (error) {
      if (!mounted) return;
      const message = 'Could not change Bypass';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$message: $error')));
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
}

class _FixedWidthBypassLabel extends StatelessWidget {
  const _FixedWidthBypassLabel({
    required this.currentLabel,
    required this.labels,
  });

  final String currentLabel;
  final Set<String> labels;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    var widestLabel = 0.0;

    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widestLabel) widestLabel = painter.width;
    }

    return SizedBox(
      width: widestLabel,
      child: Text(currentLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

final class _BypassBinding {
  const _BypassBinding({
    required this.parameter,
    required this.value,
    required this.disabled,
    required this.enumValues,
    required this.displayValue,
  });

  final ParameterInfo parameter;
  final int value;
  final bool disabled;
  final List<String> enumValues;
  final String displayValue;
}
