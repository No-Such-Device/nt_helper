import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/ui/widgets/parameter_numeric_editing.dart';
import 'package:nt_helper/ui/widgets/parameter_value_edit_traversal_scope.dart';
import 'package:nt_helper/util/ui_helpers.dart';

/// Widget that displays parameter values with appropriate formatting.
///
/// Handles all parameter value display cases including:
/// - On/Off checkboxes
/// - Enum dropdowns
/// - MIDI note names
/// - MIDI channels
/// - Hardware displayStrings
/// - Unit-based formatting with powerOfTen scaling
/// - Raw integer values
///
/// Unit-based and raw integer displays support double-tap to enter
/// inline text editing for precise value entry.
class ParameterValueDisplay extends StatefulWidget {
  final int currentValue;
  final int min;
  final int max;
  final String name;
  final String? unit;
  final int powerOfTen;
  final String? displayString;
  final List<String>? dropdownItems;
  final bool isOnOff;
  final bool widescreen;
  final bool isBpmUnit;
  final bool hasFileEditor;
  final bool showAlternateEditor;
  final bool enabled;
  final Object? traversalId;
  final double? traversalOrder;
  final Function(int) onValueChanged;
  final VoidCallback onLongPress;

  const ParameterValueDisplay({
    super.key,
    required this.currentValue,
    required this.min,
    required this.max,
    required this.name,
    this.unit,
    this.powerOfTen = 0,
    this.displayString,
    this.dropdownItems,
    this.isOnOff = false,
    required this.widescreen,
    this.isBpmUnit = false,
    this.hasFileEditor = false,
    this.showAlternateEditor = false,
    this.enabled = true,
    this.traversalId,
    this.traversalOrder,
    required this.onValueChanged,
    required this.onLongPress,
  });

  @override
  State<ParameterValueDisplay> createState() => _ParameterValueDisplayState();
}

class _ParameterValueDisplayState extends State<ParameterValueDisplay> {
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _focusNode;
  ParameterValueEditTraversalScopeState? _traversalScope;
  Object? _registeredTraversalId;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode(onKeyEvent: _onKeyEvent);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ParameterValueDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isEditing &&
        (oldWidget.name != widget.name ||
            oldWidget.min != widget.min ||
            oldWidget.max != widget.max ||
            !_isEditableNumeric)) {
      _cancelEdit();
    }
    _updateTraversalRegistration();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTraversalRegistration();
  }

  @override
  void dispose() {
    _unregisterTraversal();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _isEditableNumeric {
    return isEditableNumericParameterValue(
      enabled: widget.enabled,
      name: widget.name,
      unit: widget.unit,
      displayString: widget.displayString,
      dropdownItems: widget.dropdownItems,
      isOnOff: widget.isOnOff,
      isBpmUnit: widget.isBpmUnit,
      hasFileEditor: widget.hasFileEditor,
    );
  }

  void _updateTraversalRegistration() {
    final nextScope = ParameterValueEditTraversalScope.maybeOf(context);
    final nextId = widget.traversalId;

    if (_traversalScope != nextScope || _registeredTraversalId != nextId) {
      _unregisterTraversal();
    }

    if (nextScope == null ||
        nextId == null ||
        widget.traversalOrder == null ||
        !_isEditableNumeric) {
      _unregisterTraversal();
      return;
    }

    nextScope.register(
      ParameterValueEditTraversalEntry(
        id: nextId,
        order: widget.traversalOrder!,
        enterEditMode: _enterEditMode,
      ),
    );
    _traversalScope = nextScope;
    _registeredTraversalId = nextId;
  }

  void _unregisterTraversal() {
    final registeredId = _registeredTraversalId;
    if (registeredId != null) {
      _traversalScope?.unregister(registeredId);
    }
    _traversalScope = null;
    _registeredTraversalId = null;
  }

  String _formatDisplayValue() {
    return formatEditableNumericValue(widget.currentValue, widget.powerOfTen);
  }

  void _enterEditMode() {
    if (!_isEditableNumeric) return;
    setState(() {
      _isEditing = true;
      _textController.text = _formatDisplayValue();
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
    });
    _focusNode.requestFocus();
  }

  void _submitEdit() {
    if (!_isEditing) return;
    final text = _textController.text.trim();
    final clamped = parseEditableNumericValue(
      text: text,
      min: widget.min,
      max: widget.max,
      powerOfTen: widget.powerOfTen,
    );
    if (clamped != null) {
      widget.onValueChanged(clamped);
    }
    setState(() {
      _isEditing = false;
    });
  }

  void _submitAndMove({required bool reverse}) {
    final traversalId = widget.traversalId;
    final traversalScope = _traversalScope;
    _submitEdit();
    if (traversalId == null || traversalScope == null) return;
    traversalScope.moveFrom(traversalId, reverse: reverse);
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
    });
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _submitEdit();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelEdit();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      final pressed = HardwareKeyboard.instance.logicalKeysPressed;
      _submitAndMove(
        reverse:
            pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            pressed.contains(LogicalKeyboardKey.shiftRight),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTextField(TextStyle? textStyle) {
    final hasDecimal = widget.powerOfTen < 0;
    final allowNegative = widget.min < 0;
    final pattern = editableNumericInputPattern(
      min: widget.min,
      powerOfTen: widget.powerOfTen,
    );

    final unitText = widget.unit?.trim();
    final hasSuffix = unitText != null && unitText.isNotEmpty;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (final key in [
          LogicalKeyboardKey.digit0,
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
          LogicalKeyboardKey.digit7,
          LogicalKeyboardKey.digit8,
          LogicalKeyboardKey.digit9,
        ])
          SingleActivator(key): const DoNothingAndStopPropagationTextIntent(),
      },
      child: Semantics(
        label: 'Edit ${cleanTitle(widget.name)} value',
        textField: true,
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(
            signed: allowNegative,
            decimal: hasDecimal,
          ),
          style: textStyle,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 8.0,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            suffixText: hasSuffix ? unitText : null,
          ),
          onSubmitted: (_) => _submitEdit(),
          inputFormatters: [FilteringTextInputFormatter.allow(pattern)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textStyle = widget.widescreen
        ? textTheme.labelLarge
        : textTheme.labelSmall;

    // If BPM or file editor, hide default display (handled elsewhere)
    if (widget.isBpmUnit || widget.hasFileEditor) {
      return const SizedBox.shrink();
    }

    // On/Off checkbox
    if (widget.isOnOff) {
      return Semantics(
        label: '${widget.name}: ${widget.currentValue == 1 ? "On" : "Off"}',
        toggled: widget.currentValue == 1,
        child: Checkbox(
          value: widget.currentValue == 1,
          onChanged: (value) {
            widget.onValueChanged(value! ? 1 : 0);
          },
        ),
      );
    }

    // Enum dropdown
    if (widget.dropdownItems != null) {
      return Semantics(
        label: widget.name,
        value: widget.dropdownItems![widget.currentValue],
        child: DropdownMenu(
          requestFocusOnTap: false,
          initialSelection: widget.dropdownItems![widget.currentValue],
          inputDecorationTheme: const InputDecorationTheme(
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          textStyle: widget.widescreen
              ? textTheme.labelLarge
              : textTheme.labelMedium,
          dropdownMenuEntries: widget.dropdownItems!
              .map((item) => DropdownMenuEntry(value: item, label: item))
              .toList(),
          onSelected: (value) {
            final newValue = widget.dropdownItems!
                .indexOf(value!)
                .clamp(widget.min, widget.max);
            widget.onValueChanged(newValue);
          },
        ),
      );
    }

    // MIDI note parameters (but not percentages)
    if (widget.name.toLowerCase().contains("note") && widget.unit != "%") {
      final noteStr = midiNoteToNoteString(widget.currentValue);
      return Semantics(
        liveRegion: true,
        label: '${widget.name}: $noteStr',
        child: Text(noteStr, style: textStyle),
      );
    }

    // MIDI channel parameters
    if (widget.name.toLowerCase().contains("midi channel")) {
      final channelStr = widget.currentValue == 0
          ? "None"
          : widget.currentValue.toString();
      return Semantics(
        liveRegion: true,
        label: '${widget.name}: $channelStr',
        child: Text(channelStr, style: textStyle),
      );
    }

    // Hardware-provided display string
    if (widget.displayString != null) {
      return Semantics(
        liveRegion: true,
        label: '${widget.name}: ${widget.displayString}',
        customSemanticsActions: {
          CustomSemanticsAction(label: 'Switch to step editor'):
              widget.onLongPress,
        },
        child: GestureDetector(
          onLongPress: widget.onLongPress,
          child: Text(
            widget.displayString!,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      );
    }

    // Unit-based formatting with powerOfTen scaling
    if (widget.unit != null) {
      if (_isEditing && _isEditableNumeric) {
        return _buildTextField(textStyle);
      }
      final formatted = formatWithUnit(
        widget.currentValue,
        name: widget.name,
        min: widget.min,
        max: widget.max,
        unit: widget.unit,
        powerOfTen: widget.powerOfTen,
      );
      return Semantics(
        liveRegion: true,
        label: '${widget.name}: $formatted',
        child: GestureDetector(
          onDoubleTap: _enterEditMode,
          child: Text(formatted, style: textStyle),
        ),
      );
    }

    // Default: raw integer value
    if (_isEditing && _isEditableNumeric) {
      return _buildTextField(textStyle);
    }
    return Semantics(
      liveRegion: true,
      label: '${widget.name}: ${widget.currentValue}',
      child: GestureDetector(
        onDoubleTap: _enterEditMode,
        child: Text(widget.currentValue.toString(), style: textStyle),
      ),
    );
  }
}
