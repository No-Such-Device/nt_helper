import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/parameter_numeric_editing.dart';

/// Range slider for the mapping editor with double-tap-to-edit Min/Max labels.
///
/// Mirrors the double-tap-to-edit behavior of [ParameterValueDisplay]: double
/// -tapping the "Min" or "Max" label swaps it for an inline numeric text field
/// wrapped in [DigitShortcutBlocker] so bare digit keys reach the field instead
/// of triggering application shortcuts (e.g. performance-page navigation on the
/// main synchronized screen). Submitting parses, clamps to the parameter range
/// (and to the opposite bound so `min <= max` is preserved), then reports the
/// new range through [onChanged] followed by [onChangeEnd] — the same lifecycle
/// the slider uses for a drag gesture.
class MappingRangeSlider extends StatefulWidget {
  final int minValue;
  final int maxValue;
  final int parameterMin;
  final int parameterMax;
  final int powerOfTen;
  final String? unitString;
  final void Function(int rawMin, int rawMax) onChanged;
  final void Function(int rawMin, int rawMax)? onChangeEnd;

  const MappingRangeSlider({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.parameterMin,
    required this.parameterMax,
    required this.powerOfTen,
    required this.onChanged,
    this.onChangeEnd,
    this.unitString,
  });

  @override
  State<MappingRangeSlider> createState() => _MappingRangeSliderState();
}

class _MappingRangeSliderState extends State<MappingRangeSlider> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;
  late final FocusNode _minFocus;
  late final FocusNode _maxFocus;
  bool _editingMin = false;
  bool _editingMax = false;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController();
    _maxController = TextEditingController();
    _minFocus = FocusNode(onKeyEvent: (n, e) => _onKeyEvent(e, isMin: true));
    _maxFocus = FocusNode(onKeyEvent: (n, e) => _onKeyEvent(e, isMin: false));
    _minFocus.addListener(() => _onFocusChange(isMin: true));
    _maxFocus.addListener(() => _onFocusChange(isMin: false));
  }

  @override
  void didUpdateWidget(covariant MappingRangeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cancel an in-flight edit if the underlying values/bounds changed
    // externally (e.g. another control updated the mapping).
    if (_editingMin &&
        (oldWidget.minValue != widget.minValue ||
            oldWidget.parameterMin != widget.parameterMin ||
            oldWidget.parameterMax != widget.parameterMax)) {
      _cancel(isMin: true);
    }
    if (_editingMax &&
        (oldWidget.maxValue != widget.maxValue ||
            oldWidget.parameterMin != widget.parameterMin ||
            oldWidget.parameterMax != widget.parameterMax)) {
      _cancel(isMin: false);
    }
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    _minFocus.dispose();
    _maxFocus.dispose();
    super.dispose();
  }

  double get _scale => pow(10, widget.powerOfTen).toDouble();

  String _formatDisplayValue(double displayValue) {
    final decimalPlaces = widget.powerOfTen.abs();
    return displayValue.toStringAsFixed(decimalPlaces);
  }

  String _formatRaw(int raw) => _formatDisplayValue(raw * _scale);

  String _labelFor(int raw) {
    final unit = widget.unitString?.trim();
    final base = _formatRaw(raw);
    return (unit != null && unit.isNotEmpty) ? '$base $unit' : base;
  }

  void _enterEdit({required bool isMin}) {
    setState(() {
      if (isMin) {
        _editingMin = true;
        _minController.text = _formatRaw(widget.minValue);
      } else {
        _editingMax = true;
        _maxController.text = _formatRaw(widget.maxValue);
      }
      final c = isMin ? _minController : _maxController;
      c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
    });
    (isMin ? _minFocus : _maxFocus).requestFocus();
  }

  void _submit({required bool isMin}) {
    final controller = isMin ? _minController : _maxController;
    final parsed = parseEditableNumericValue(
      text: controller.text,
      min: widget.parameterMin,
      max: widget.parameterMax,
      powerOfTen: widget.powerOfTen,
    );
    // Exit edit mode regardless of validity.
    setState(() {
      if (isMin) {
        _editingMin = false;
      } else {
        _editingMax = false;
      }
    });
    if (parsed == null) return;

    // Preserve the min <= max invariant the RangeSlider requires.
    final newMin = isMin
        ? parsed.clamp(widget.parameterMin, widget.maxValue)
        : widget.minValue;
    final newMax = isMin
        ? widget.maxValue
        : parsed.clamp(widget.minValue, widget.parameterMax);

    widget.onChanged(newMin, newMax);
    widget.onChangeEnd?.call(newMin, newMax);
  }

  void _cancel({required bool isMin}) {
    setState(() {
      if (isMin) {
        _editingMin = false;
      } else {
        _editingMax = false;
      }
    });
  }

  KeyEventResult _onKeyEvent(KeyEvent event, {required bool isMin}) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel(isMin: isMin);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit(isMin: isMin);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange({required bool isMin}) {
    final hasFocus = isMin ? _minFocus.hasFocus : _maxFocus.hasFocus;
    final editing = isMin ? _editingMin : _editingMax;
    if (!hasFocus && editing) {
      _submit(isMin: isMin);
    }
  }

  @override
  Widget build(BuildContext context) {
    var sliderMin = widget.parameterMin;
    var sliderMax = widget.parameterMax;
    if (sliderMin > sliderMax) {
      final tmp = sliderMin;
      sliderMin = sliderMax;
      sliderMax = tmp;
    }

    if (sliderMin == sliderMax) {
      // Only one possible value — show a label instead of a slider.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'Range: ${_labelFor(sliderMin)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final displayMin = sliderMin * _scale;
    final displayMax = sliderMax * _scale;

    final clampedMin = widget.minValue.clamp(sliderMin, sliderMax);
    final clampedMax = widget.maxValue.clamp(sliderMin, sliderMax);
    final displayStart = clampedMin * _scale;
    final displayEnd = clampedMax * _scale;
    final divisions = sliderMax - sliderMin;

    return Column(
      children: [
        RangeSlider(
          values: RangeValues(displayStart, displayEnd),
          min: displayMin,
          max: displayMax,
          divisions: divisions,
          labels: RangeLabels(_labelFor(clampedMin), _labelFor(clampedMax)),
          semanticFormatterCallback: (value) => _formatDisplayValue(value),
          onChanged: (RangeValues values) {
            final rawMin = (values.start / _scale).round();
            final rawMax = (values.end / _scale).round();
            widget.onChanged(rawMin, rawMax);
          },
          onChangeEnd: widget.onChangeEnd != null
              ? (RangeValues values) {
                  final rawMin = (values.start / _scale).round();
                  final rawMax = (values.end / _scale).round();
                  widget.onChangeEnd!(rawMin, rawMax);
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel(isMin: true, raw: clampedMin),
              _buildLabel(isMin: false, raw: clampedMax),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabel({required bool isMin, required int raw}) {
    final editing = isMin ? _editingMin : _editingMax;
    if (editing) {
      return _buildEditField(isMin: isMin);
    }
    final prefix = isMin ? 'Min' : 'Max';
    final text = '$prefix: ${_labelFor(raw)}';
    return Semantics(
      label: text,
      hint: 'Double tap to edit',
      child: GestureDetector(
        onDoubleTap: () => _enterEdit(isMin: isMin),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  Widget _buildEditField({required bool isMin}) {
    final controller = isMin ? _minController : _maxController;
    final focusNode = isMin ? _minFocus : _maxFocus;
    final hasDecimal = widget.powerOfTen < 0;
    final allowNegative = widget.parameterMin < 0;
    final pattern = editableNumericInputPattern(
      min: widget.parameterMin,
      powerOfTen: widget.powerOfTen,
    );
    final unitText = widget.unitString?.trim();
    final hasSuffix = unitText != null && unitText.isNotEmpty;

    return SizedBox(
      width: 96,
      child: DigitShortcutBlocker(
        includePeriod: hasDecimal,
        child: Semantics(
          label: 'Edit ${isMin ? "Min" : "Max"}',
          textField: true,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.numberWithOptions(
              signed: allowNegative,
              decimal: hasDecimal,
            ),
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.bodySmall,
            inputFormatters: [FilteringTextInputFormatter.allow(pattern)],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: const OutlineInputBorder(),
              suffixText: hasSuffix ? unitText : null,
            ),
            onSubmitted: (_) => _submit(isMin: isMin),
          ),
        ),
      ),
    );
  }
}
