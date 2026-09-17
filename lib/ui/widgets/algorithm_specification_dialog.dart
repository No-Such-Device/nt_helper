import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';

bool isBooleanSpecification(Specification spec) =>
    spec.type == 2 && spec.min == 0 && spec.max == 1;

class AlgorithmSpecificationEditor extends StatefulWidget {
  const AlgorithmSpecificationEditor({
    super.key,
    required this.algorithm,
    required this.initialValues,
    required this.readOnly,
    required this.onChanged,
    this.focusNodes,
  });

  final AlgorithmInfo algorithm;
  final List<int> initialValues;
  final bool readOnly;
  final ValueChanged<List<int>> onChanged;
  final List<FocusNode>? focusNodes;

  @override
  State<AlgorithmSpecificationEditor> createState() =>
      AlgorithmSpecificationEditorState();
}

class AlgorithmSpecificationEditorState
    extends State<AlgorithmSpecificationEditor> {
  final _formKey = GlobalKey<FormState>();
  late List<int> _values;
  late List<TextEditingController?> _controllers;
  late List<FocusNode> _focusNodes;
  late List<bool> _ownsFocusNode;
  String? _firstValidationError;
  int? _firstInvalidIndex;

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  @override
  void didUpdateWidget(covariant AlgorithmSpecificationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.algorithm.guid != widget.algorithm.guid ||
        oldWidget.initialValues.length != widget.initialValues.length ||
        oldWidget.readOnly != widget.readOnly) {
      _disposeControllersAndOwnedFocusNodes();
      _initializeState();
    }
  }

  @override
  void dispose() {
    _disposeControllersAndOwnedFocusNodes();
    super.dispose();
  }

  void _initializeState() {
    _values = List.generate(widget.algorithm.numSpecifications, (index) {
      final spec = widget.algorithm.specifications[index];
      final initial = index < widget.initialValues.length
          ? widget.initialValues[index]
          : spec.safeDefaultValue;
      return _normalizedInitialValue(spec, initial);
    });

    _controllers = List<TextEditingController?>.generate(
      widget.algorithm.numSpecifications,
      (index) {
        final spec = widget.algorithm.specifications[index];
        if (isBooleanSpecification(spec)) return null;
        return TextEditingController(text: _values[index].toString());
      },
    );

    _focusNodes = List<FocusNode>.generate(widget.algorithm.numSpecifications, (
      index,
    ) {
      if (widget.focusNodes != null && index < widget.focusNodes!.length) {
        return widget.focusNodes![index];
      }
      return FocusNode();
    });

    _ownsFocusNode = List<bool>.generate(
      widget.algorithm.numSpecifications,
      (index) =>
          widget.focusNodes == null || index >= widget.focusNodes!.length,
    );
  }

  void _disposeControllersAndOwnedFocusNodes() {
    for (final controller in _controllers) {
      controller?.dispose();
    }
    for (var i = 0; i < _focusNodes.length; i++) {
      if (_ownsFocusNode[i]) {
        _focusNodes[i].dispose();
      }
    }
  }

  int _normalizedInitialValue(Specification spec, int value) {
    if (isBooleanSpecification(spec)) {
      if (value == 0 || value == 1) return value;
      return spec.safeDefaultValue == 1 ? 1 : 0;
    }
    return value;
  }

  String _specName(Specification spec, int index) {
    final name = spec.name.trim();
    return name.isNotEmpty ? name : 'Specification ${index + 1}';
  }

  String _rangeText(Specification spec) => '${spec.min}-${spec.max}';

  void focusFirstControl() {
    if (_focusNodes.isEmpty) return;
    _focusNodes.first.requestFocus();
  }

  List<int>? validateAndGetValues({bool announceError = false}) {
    _firstValidationError = null;
    _firstInvalidIndex = null;
    final valid = _formKey.currentState?.validate() ?? true;
    if (!valid) {
      final invalidIndex = _firstInvalidIndex;
      if (invalidIndex != null && invalidIndex < _focusNodes.length) {
        _focusNodes[invalidIndex].requestFocus();
      }
      if (announceError && _firstValidationError != null) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          _firstValidationError!,
          TextDirection.ltr,
        );
      }
      return null;
    }

    for (var i = 0; i < widget.algorithm.numSpecifications; i++) {
      final spec = widget.algorithm.specifications[i];
      if (isBooleanSpecification(spec)) continue;
      final text = _controllers[i]?.text.trim() ?? '';
      final parsed = int.tryParse(text);
      if (parsed != null) {
        _values[i] = parsed;
      }
    }

    widget.onChanged(List<int>.from(_values));
    return List<int>.from(_values);
  }

  void _recordValidationError(int index, String message) {
    _firstValidationError ??= message;
    _firstInvalidIndex ??= index;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.algorithm.numSpecifications, (index) {
          final spec = widget.algorithm.specifications[index];
          if (isBooleanSpecification(spec)) {
            return _buildBooleanInput(spec, index);
          }
          return _buildNumericInput(spec, index);
        }),
      ),
    );
  }

  Widget _buildBooleanInput(Specification spec, int index) {
    final name = _specName(spec, index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        hint: 'Off sends 0, on sends 1',
        toggled: _values[index] == 1,
        enabled: !widget.readOnly,
        child: SwitchListTile(
          key: ValueKey('${widget.algorithm.guid}_spec_$index'),
          focusNode: _focusNodes[index],
          title: Text(name),
          subtitle: Text('Off = 0, On = 1'),
          value: _values[index] == 1,
          onChanged: widget.readOnly
              ? null
              : (enabled) {
                  setState(() {
                    _values[index] = enabled ? 1 : 0;
                  });
                  widget.onChanged(List<int>.from(_values));
                },
        ),
      ),
    );
  }

  Widget _buildNumericInput(Specification spec, int index) {
    final name = _specName(spec, index);
    final field = TextFormField(
      key: ValueKey('${widget.algorithm.guid}_spec_$index'),
      controller: _controllers[index],
      focusNode: _focusNodes[index],
      readOnly: widget.readOnly,
      decoration: InputDecoration(
        labelText: '$name (${_rangeText(spec)})',
        helperText: widget.readOnly
            ? 'Defaults are used in offline mode'
            : null,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))],
      onChanged: widget.readOnly
          ? null
          : (value) {
              final parsed = int.tryParse(value.trim());
              if (parsed == null) return;
              _values[index] = parsed;
              widget.onChanged(List<int>.from(_values));
            },
      validator: (value) {
        if (widget.readOnly) return null;
        final text = value?.trim() ?? '';
        if (text.isEmpty) {
          final message = 'Enter a value for $name';
          _recordValidationError(index, message);
          return message;
        }
        final parsed = int.tryParse(text);
        if (parsed == null) {
          final message = '$name must be a whole number';
          _recordValidationError(index, message);
          return message;
        }
        if (parsed < spec.min || parsed > spec.max) {
          final message = '$name must be between ${spec.min} and ${spec.max}';
          _recordValidationError(index, message);
          return message;
        }
        return null;
      },
      autovalidateMode: AutovalidateMode.onUserInteraction,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DigitShortcutBlocker(
        child: widget.readOnly
            ? Tooltip(
                message: 'Defaults are used in offline mode',
                child: field,
              )
            : field,
      ),
    );
  }
}

class AlgorithmSpecificationDialog {
  static Future<List<int>?> show({
    required BuildContext context,
    required AlgorithmInfo algorithm,
    required List<int> initialValues,
    required bool readOnly,
    String? title,
    String primaryActionLabel = 'Add',
    Future<void> Function(List<int> values)? onSubmit,
    String pendingTitle = 'Submitting…',
    String pendingMessage = 'Waiting for device data…',
  }) {
    return showDialog<List<int>>(
      context: context,
      barrierDismissible: onSubmit == null,
      builder: (context) => _AlgorithmSpecificationDialogContent(
        algorithm: algorithm,
        initialValues: initialValues,
        readOnly: readOnly,
        title: title ?? 'Configure ${algorithm.name}',
        primaryActionLabel: primaryActionLabel,
        onSubmit: onSubmit,
        pendingTitle: pendingTitle,
        pendingMessage: pendingMessage,
      ),
    );
  }
}

class _AlgorithmSpecificationDialogContent extends StatefulWidget {
  const _AlgorithmSpecificationDialogContent({
    required this.algorithm,
    required this.initialValues,
    required this.readOnly,
    required this.title,
    required this.primaryActionLabel,
    required this.onSubmit,
    required this.pendingTitle,
    required this.pendingMessage,
  });

  final AlgorithmInfo algorithm;
  final List<int> initialValues;
  final bool readOnly;
  final String title;
  final String primaryActionLabel;
  final Future<void> Function(List<int> values)? onSubmit;
  final String pendingTitle;
  final String pendingMessage;

  @override
  State<_AlgorithmSpecificationDialogContent> createState() =>
      _AlgorithmSpecificationDialogContentState();
}

class _AlgorithmSpecificationDialogContentState
    extends State<_AlgorithmSpecificationDialogContent> {
  final _editorKey = GlobalKey<AlgorithmSpecificationEditorState>();
  final _primaryActionFocusNode = FocusNode();
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.readOnly) {
        _primaryActionFocusNode.requestFocus();
      } else {
        _editorKey.currentState?.focusFirstControl();
      }
    });
  }

  @override
  void dispose() {
    _primaryActionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final specCount = widget.algorithm.numSpecifications;
    return PopScope(
      canPop: !_pending,
      child: FocusTraversalGroup(
        child: AlertDialog(
          title: Semantics(
            header: true,
            liveRegion: _pending,
            child: Text(_pending ? widget.pendingTitle : widget.title),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _pending
                ? Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LinearProgressIndicator(
                          semanticsLabel: 'Waiting for slot data',
                        ),
                        const SizedBox(height: 16),
                        Text(widget.pendingMessage),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$specCount specification${specCount == 1 ? '' : 's'} required',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (widget.readOnly) ...[
                          const SizedBox(height: 8),
                          const Text('Defaults are used in offline mode.'),
                        ],
                        const SizedBox(height: 16),
                        AlgorithmSpecificationEditor(
                          key: _editorKey,
                          algorithm: widget.algorithm,
                          initialValues: widget.initialValues,
                          readOnly: widget.readOnly,
                          onChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
          ),
          actions: _pending
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    focusNode: _primaryActionFocusNode,
                    onPressed: _submit,
                    child: Text(widget.primaryActionLabel),
                  ),
                ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_pending) return;
    final values = _editorKey.currentState?.validateAndGetValues(
      announceError: true,
    );
    if (values == null) return;

    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.of(context).pop(values);
      return;
    }

    setState(() => _pending = true);
    await onSubmit(values);
    if (mounted) Navigator.of(context).pop(values);
  }
}
