import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/services/key_binding_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/parameter_numeric_editing.dart';
import 'package:nt_helper/ui/widgets/slot_bypass_control.dart';
import 'package:nt_helper/util/ui_helpers.dart';

class ParameterSpreadsheetView extends StatefulWidget {
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final ParameterPages pages;

  const ParameterSpreadsheetView({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.pages,
  });

  @override
  State<ParameterSpreadsheetView> createState() =>
      _ParameterSpreadsheetViewState();
}

class _ParameterSpreadsheetViewState extends State<ParameterSpreadsheetView> {
  static const double _rowExtent = 52;

  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  int? _editingIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ParameterSpreadsheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rowCount = _rows.length;
    if (rowCount == 0) {
      _selectedIndex = 0;
      _editingIndex = null;
      return;
    }
    if (_selectedIndex >= rowCount) _selectedIndex = rowCount - 1;
    if (_editingIndex != null && _editingIndex! >= rowCount) {
      _editingIndex = null;
    }
  }

  List<_SpreadsheetParameter> get _rows {
    final rowsByParameter = <int, _SpreadsheetParameter>{};
    final performanceNumbers = _performanceParameterNumbers();

    for (final parameterNumber in performanceNumbers) {
      final row = _rowForParameter(parameterNumber);
      if (row != null) rowsByParameter[parameterNumber] = row;
    }

    for (final parameterNumber in _regularParameterNumbers()) {
      if (rowsByParameter.containsKey(parameterNumber)) continue;
      if (isUniversalBypassParameter(widget.slot, parameterNumber)) continue;
      final row = _rowForParameter(parameterNumber);
      if (row != null) rowsByParameter[parameterNumber] = row;
    }

    return rowsByParameter.values.whereType<_SpreadsheetParameter>().toList();
  }

  List<int> _performanceParameterNumbers() {
    final state = context.read<DistingCubit>().state;
    if (state is DistingStateSynchronized &&
        state.firmwareVersion.hasPerfPageItems) {
      final items = state.perfPageItems
          .where((item) => item.enabled && item.slotIndex == widget.slotIndex)
          .toList();
      items.sort((a, b) {
        final indexCompare = a.itemIndex.compareTo(b.itemIndex);
        if (indexCompare != 0) return indexCompare;
        return a.parameterNumber.compareTo(b.parameterNumber);
      });
      return [for (final item in items) item.parameterNumber];
    }

    final numbers = <int>[];
    for (int i = 0; i < widget.slot.mappings.length; i++) {
      final mapping = widget.slot.mappings[i];
      if (mapping.packedMappingData.perfPageIndex > 0) numbers.add(i);
    }
    numbers.sort((a, b) {
      final mappingA = widget.slot.mappings[a];
      final mappingB = widget.slot.mappings[b];
      final pageCompare = mappingA.packedMappingData.perfPageIndex.compareTo(
        mappingB.packedMappingData.perfPageIndex,
      );
      if (pageCompare != 0) return pageCompare;
      return a.compareTo(b);
    });
    return numbers;
  }

  Iterable<int> _regularParameterNumbers() sync* {
    final seen = <int>{};
    for (final page in widget.pages.pages) {
      for (final parameterNumber in page.parameters) {
        if (seen.add(parameterNumber)) yield parameterNumber;
      }
    }
    for (int i = 0; i < widget.slot.parameters.length; i++) {
      if (seen.add(i)) yield i;
    }
  }

  _SpreadsheetParameter? _rowForParameter(int parameterNumber) {
    final parameterInfo = widget.slot.parameters.elementAtOrNull(
      parameterNumber,
    );
    final value = widget.slot.values.elementAtOrNull(parameterNumber);
    if (parameterInfo == null || value == null) return null;

    final enumStrings =
        widget.slot.enums.elementAtOrNull(parameterNumber) ??
        ParameterEnumStrings.filler();
    final valueString =
        widget.slot.valueStrings.elementAtOrNull(parameterNumber) ??
        ParameterValueString.filler();

    final hasCompleteEnumStrings =
        enumStrings.values.isNotEmpty &&
        enumStrings.values.every((text) => text.isNotEmpty);
    final currentValueHasEnumString =
        enumStrings.values.isNotEmpty &&
        value.value >= 0 &&
        value.value < enumStrings.values.length &&
        enumStrings.values[value.value].isNotEmpty;
    final effectiveDisplayString = currentValueHasEnumString
        ? enumStrings.values[value.value]
        : (parameterInfo.unit == 16
              ? (value.value == 0 && valueString.value.isNotEmpty
                    ? valueString.value
                    : null)
              : (valueString.value.isNotEmpty ? valueString.value : null));
    final shouldShowUnit = !ParameterEditorRegistry.isStringTypeUnit(
      parameterInfo.unit,
    );
    final unit = shouldShowUnit
        ? parameterInfo.getUnitString(widget.units)
        : null;
    final isBpmUnit = ParameterEditorRegistry.isBpmUnit(
      parameterInfo.unit,
      unitString: unit,
    );
    final fileEditor = ParameterEditorRegistry.findEditorFor(
      slot: widget.slot,
      parameterInfo: parameterInfo,
      parameterNumber: parameterNumber,
      currentValue: value.value,
      onValueChanged: (_) {},
    );
    final isOnOff =
        hasCompleteEnumStrings &&
        enumStrings.values.length >= 2 &&
        enumStrings.values[0] == "Off" &&
        enumStrings.values[1] == "On";

    final editable = isEditableNumericParameterValue(
      enabled: !value.isDisabled,
      name: parameterInfo.name,
      unit: unit,
      displayString: effectiveDisplayString,
      dropdownItems: hasCompleteEnumStrings ? enumStrings.values : null,
      isOnOff: isOnOff,
      isBpmUnit: isBpmUnit,
      hasFileEditor: fileEditor != null,
    );
    if (!editable) return null;

    final currentValue =
        value.value >= parameterInfo.min && value.value <= parameterInfo.max
        ? value.value
        : parameterInfo.defaultValue;

    return _SpreadsheetParameter(
      name: cleanTitle(parameterInfo.name),
      unit: unit,
      value: currentValue,
      min: parameterInfo.min,
      max: parameterInfo.max,
      powerOfTen: parameterInfo.powerOfTen,
      algorithmIndex: parameterInfo.algorithmIndex,
      parameterNumber: parameterInfo.parameterNumber,
    );
  }

  void _scrollSelectedIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final targetTop = index * _rowExtent;
      final targetBottom = targetTop + _rowExtent;
      final viewportTop = position.pixels;
      final viewportBottom = viewportTop + position.viewportDimension;
      double? nextOffset;

      if (targetTop < viewportTop) {
        nextOffset = targetTop;
      } else if (targetBottom > viewportBottom) {
        nextOffset = targetBottom - position.viewportDimension;
      }

      if (nextOffset == null) return;
      _scrollController.jumpTo(
        nextOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  void _select(int index) {
    if (_rows.isEmpty) return;
    setState(() {
      _selectedIndex = index % _rows.length;
      _editingIndex = null;
    });
    _scrollSelectedIntoView(_selectedIndex);
  }

  void _move({required bool reverse}) {
    if (_rows.isEmpty) return;
    final next = reverse
        ? (_selectedIndex - 1 + _rows.length) % _rows.length
        : (_selectedIndex + 1) % _rows.length;
    _select(next);
  }

  void _startEditing(int index) {
    setState(() {
      _selectedIndex = index;
      _editingIndex = index;
    });
    _scrollSelectedIntoView(index);
  }

  void _startEditingWithText(int index, String _) {
    setState(() {
      _selectedIndex = index;
      _editingIndex = index;
    });
    _scrollSelectedIntoView(index);
  }

  bool _commit(int index, String text) {
    final rows = _rows;
    if (index < 0 || index >= rows.length) return false;
    final row = rows[index];
    final value = parseEditableNumericValue(
      text: text,
      min: row.min,
      max: row.max,
      powerOfTen: row.powerOfTen,
    );
    if (value == null) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Invalid ${row.name} value',
        Directionality.of(context),
      );
      return false;
    }

    final cubit = context.read<DistingCubit>();
    cubit.updateParameterValue(
      algorithmIndex: row.algorithmIndex,
      parameterNumber: row.parameterNumber,
      value: value,
      userIsChangingTheValue: false,
    );
    cubit.scheduleParameterRefresh(row.algorithmIndex);
    return true;
  }

  void _commitAndMove(int index, String text, {required bool reverse}) {
    if (!_commit(index, text)) return;
    setState(() {
      _selectedIndex = reverse
          ? (index - 1 + _rows.length) % _rows.length
          : (index + 1) % _rows.length;
      _editingIndex = null;
    });
    _scrollSelectedIntoView(_selectedIndex);
  }

  void _cancelEditing(int index) {
    setState(() {
      _selectedIndex = index;
      _editingIndex = null;
    });
    _scrollSelectedIntoView(index);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) {
      return SafeArea(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Text('No editable numeric parameters'),
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final row = rows[index];
          return _SpreadsheetParameterRow(
            key: ValueKey(row.parameterNumber),
            row: row,
            selected: index == _selectedIndex,
            editing: index == _editingIndex,
            rowExtent: _rowExtent - 4,
            onSelected: () => _select(index),
            onStartEditing: () => _startEditing(index),
            onStartEditingWithText: (text) =>
                _startEditingWithText(index, text),
            onMove: ({required reverse}) => _move(reverse: reverse),
            onCommitAndMove: (text, {required reverse}) =>
                _commitAndMove(index, text, reverse: reverse),
            onCancelEditing: () => _cancelEditing(index),
          );
        },
      ),
    );
  }
}

class _SpreadsheetParameter {
  final String name;
  final String? unit;
  final int value;
  final int min;
  final int max;
  final int powerOfTen;
  final int algorithmIndex;
  final int parameterNumber;

  const _SpreadsheetParameter({
    required this.name,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.powerOfTen,
    required this.algorithmIndex,
    required this.parameterNumber,
  });

  String get textValue => formatEditableNumericValue(value, powerOfTen);
  String get accessibleValue {
    final suffix = unit?.trim();
    if (suffix == null || suffix.isEmpty) return textValue;
    return '$textValue $suffix';
  }
}

class _SpreadsheetParameterRow extends StatefulWidget {
  final _SpreadsheetParameter row;
  final bool selected;
  final bool editing;
  final double rowExtent;
  final VoidCallback onSelected;
  final VoidCallback onStartEditing;
  final ValueChanged<String> onStartEditingWithText;
  final void Function({required bool reverse}) onMove;
  final void Function(String text, {required bool reverse}) onCommitAndMove;
  final VoidCallback onCancelEditing;

  const _SpreadsheetParameterRow({
    super.key,
    required this.row,
    required this.selected,
    required this.editing,
    required this.rowExtent,
    required this.onSelected,
    required this.onStartEditing,
    required this.onStartEditingWithText,
    required this.onMove,
    required this.onCommitAndMove,
    required this.onCancelEditing,
  });

  @override
  State<_SpreadsheetParameterRow> createState() =>
      _SpreadsheetParameterRowState();
}

class _SpreadsheetParameterRowState extends State<_SpreadsheetParameterRow> {
  late final FocusNode _cellFocusNode;
  late final FocusNode _editFocusNode;
  late final TextEditingController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _cellFocusNode = FocusNode(onKeyEvent: _onCellKeyEvent);
    _editFocusNode = FocusNode(onKeyEvent: _onEditKeyEvent);
    _controller = TextEditingController(text: widget.row.textValue);
    _requestCurrentFocus();
  }

  @override
  void didUpdateWidget(_SpreadsheetParameterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editing && oldWidget.row.value != widget.row.value) {
      _controller.text = widget.row.textValue;
    }
    if (widget.editing && !oldWidget.editing) {
      _controller.text = widget.row.textValue;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      _hasError = false;
    }
    if (!widget.editing) _hasError = false;
    _requestCurrentFocus();
  }

  @override
  void dispose() {
    _cellFocusNode.dispose();
    _editFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _requestCurrentFocus() {
    if (!widget.selected) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.selected) return;
      if (widget.editing) {
        _editFocusNode.requestFocus();
      } else {
        _cellFocusNode.requestFocus();
      }
    });
  }

  bool _isReplacementCharacter(String? character) {
    if (character == null || character.isEmpty) return false;
    final pattern = editableNumericInputPattern(
      min: widget.row.min,
      powerOfTen: widget.row.powerOfTen,
    );
    return character.length == 1 && pattern.hasMatch(character);
  }

  bool _hasNonShiftModifierPressed() {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed;
  }

  KeyEventResult _onCellKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onMove(reverse: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onMove(reverse: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.onMove(reverse: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onStartEditing();
      return KeyEventResult.handled;
    }
    if (!_hasNonShiftModifierPressed() &&
        _isReplacementCharacter(event.character)) {
      widget.onStartEditingWithText(event.character!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.text = event.character!;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onEditKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.text = widget.row.textValue;
      widget.onCancelEditing();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _commitAndMove(reverse: false);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _commitAndMove(reverse: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _commitAndMove(reverse: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Map<ShortcutActivator, Intent> get _textEntryShortcuts => {
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
    ]) ...<SingleActivator, Intent>{
      SingleActivator(key): const DoNothingAndStopPropagationTextIntent(),
      SingleActivator(key, shift: true):
          const DoNothingAndStopPropagationTextIntent(),
    },
    for (final activator in KeyBindingService().globalShortcuts.keys)
      activator: const DoNothingAndStopPropagationTextIntent(),
  };

  void _commitAndMove({required bool reverse}) {
    final previousText = _controller.text;
    widget.onCommitAndMove(previousText, reverse: reverse);
    final invalid =
        parseEditableNumericValue(
          text: previousText,
          min: widget.row.min,
          max: widget.row.max,
          powerOfTen: widget.row.powerOfTen,
        ) ==
        null;
    if (mounted && invalid) {
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tertiary = theme.colorScheme.tertiary;
    final unitText = widget.row.unit?.trim();
    final hasSuffix = unitText != null && unitText.isNotEmpty;
    final pattern = editableNumericInputPattern(
      min: widget.row.min,
      powerOfTen: widget.row.powerOfTen,
    );
    final cellBorder = Border.all(
      color: widget.selected ? tertiary : theme.dividerColor,
      width: widget.selected ? 2 : 1,
    );
    final backgroundColor = widget.selected
        ? tertiary.withValues(alpha: 0.08)
        : theme.colorScheme.surface;

    return SizedBox(
      height: widget.rowExtent,
      child: Semantics(
        container: true,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Semantics(
                label: widget.row.name,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Text(
                    widget.row.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Semantics(
                excludeSemantics: true,
                label: 'Edit ${widget.row.name} value',
                value: _hasError
                    ? 'Invalid value, ${widget.row.accessibleValue}'
                    : widget.row.accessibleValue,
                hint: _hasError
                    ? 'Invalid value. Enter a numeric value'
                    : widget.editing
                    ? 'Enter a numeric value'
                    : 'Press Enter or type a number to edit',
                liveRegion: _hasError,
                textField: true,
                selected: widget.selected,
                onTap: widget.onStartEditing,
                child: GestureDetector(
                  onTap: widget.onSelected,
                  onDoubleTap: widget.onStartEditing,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    constraints: const BoxConstraints(minHeight: 40),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(6),
                      border: cellBorder,
                    ),
                    child: widget.editing
                        ? Shortcuts(
                            shortcuts: _textEntryShortcuts,
                            child: TextField(
                              controller: _controller,
                              focusNode: _editFocusNode,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.numberWithOptions(
                                signed: widget.row.min < 0,
                                decimal: widget.row.powerOfTen < 0,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                errorText: _hasError ? 'Invalid value' : null,
                                errorMaxLines: 1,
                                suffixText: hasSuffix ? unitText : null,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(pattern),
                              ],
                              onSubmitted: (_) =>
                                  _commitAndMove(reverse: false),
                            ),
                          )
                        : Focus(
                            focusNode: _cellFocusNode,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                child: Text(
                                  widget.row.accessibleValue,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
