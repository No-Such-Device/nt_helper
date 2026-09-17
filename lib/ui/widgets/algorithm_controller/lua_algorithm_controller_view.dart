import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/algorithm_controller/lua_algorithm_controller_engine.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/parameter_number_lookup.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/parameter_numeric_editing.dart';
import 'package:nt_helper/util/ui_helpers.dart';

typedef AlgorithmControllerSourceLoader = Future<String> Function(String path);

const double _algorithmControllerXYPadWidth = 480;
const double _algorithmControllerNoteMaskWidth = 480;
const double _algorithmControllerCanvasWidth = 720;
const double _algorithmControllerNoteTargetSize = 48;

typedef _AlgorithmControllerParameterBinding = ({
  int minimum,
  int maximum,
  int defaultValue,
  int value,
  bool disabled,
  List<String> enumValues,
  String displayValue,
  String name,
  int powerOfTen,
  String? unit,
});

class LuaAlgorithmControllerView extends StatefulWidget {
  const LuaAlgorithmControllerView({
    super.key,
    required this.definition,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.sectionController,
    this.engine = const LuaAlgorithmControllerEngine(),
    this.sourceLoader,
    this.onError,
  });

  final AlgorithmControllerDefinition definition;
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final AlgorithmControllerSectionController sectionController;
  final LuaAlgorithmControllerEngine engine;
  final AlgorithmControllerSourceLoader? sourceLoader;
  final ValueChanged<String>? onError;

  @override
  State<LuaAlgorithmControllerView> createState() =>
      _LuaAlgorithmControllerViewState();
}

class _LuaAlgorithmControllerViewState
    extends State<LuaAlgorithmControllerView> {
  String? _source;
  AlgorithmControllerDocument? _document;
  String? _error;
  String? _lastReportedError;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSource());
  }

  @override
  void didUpdateWidget(covariant LuaAlgorithmControllerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition.assetPath != widget.definition.assetPath ||
        oldWidget.sourceLoader != widget.sourceLoader) {
      _loading = true;
      _document = null;
      _error = null;
      unawaited(_loadSource());
      return;
    }

    if (!identical(oldWidget.slot, widget.slot) ||
        oldWidget.slotIndex != widget.slotIndex ||
        oldWidget.units != widget.units) {
      _evaluateSource();
    }
  }

  Future<void> _loadSource() async {
    final generation = ++_loadGeneration;
    try {
      final loader = widget.sourceLoader ?? rootBundle.loadString;
      final source = await loader(widget.definition.assetPath);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _source = source;
        _loading = false;
        _evaluateSource();
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _setError('Could not load ${widget.definition.name}: $error');
      });
    }
  }

  void _evaluateSource() {
    final source = _source;
    if (source == null) return;
    try {
      _document = widget.engine.evaluate(
        source: source,
        slot: widget.slot,
        slotIndex: widget.slotIndex,
        units: widget.units,
      );
      _error = null;
      _lastReportedError = null;
    } catch (error) {
      _document = null;
      _setError(error.toString());
    }
  }

  void _setError(String message) {
    _error = message;
    if (_lastReportedError == message) return;
    _lastReportedError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onError?.call(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: 'Loading algorithm controller',
          child: const CircularProgressIndicator(),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.extension_off_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final document = _document;
    if (document == null) return const SizedBox.shrink();
    return AlgorithmControllerDocumentView(
      document: document,
      slot: widget.slot,
      slotIndex: widget.slotIndex,
      units: widget.units,
      sectionController: widget.sectionController,
    );
  }
}

class AlgorithmControllerDocumentView extends StatefulWidget {
  const AlgorithmControllerDocumentView({
    super.key,
    required this.document,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.sectionController,
  });

  final AlgorithmControllerDocument document;
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final AlgorithmControllerSectionController sectionController;

  @override
  State<AlgorithmControllerDocumentView> createState() =>
      _AlgorithmControllerDocumentViewState();
}

class _AlgorithmControllerDocumentViewState
    extends State<AlgorithmControllerDocumentView> {
  @override
  void initState() {
    super.initState();
    _synchronizeSections();
  }

  @override
  void didUpdateWidget(covariant AlgorithmControllerDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document) ||
        oldWidget.sectionController != widget.sectionController) {
      _synchronizeSections();
    }
  }

  void _synchronizeSections() {
    final sections = <AlgorithmControllerSectionReference>[];
    _collectSections(widget.document.root, path: 'root', sections: sections);
    widget.sectionController.synchronizeSections(sections);
  }

  void _collectSections(
    AlgorithmControllerNode node, {
    required String path,
    required List<AlgorithmControllerSectionReference> sections,
  }) {
    switch (node) {
      case AlgorithmControllerColumn(:final children):
      case AlgorithmControllerRow(:final children):
        for (var index = 0; index < children.length; index++) {
          _collectSections(
            children[index],
            path: '$path/$index',
            sections: sections,
          );
        }
      case AlgorithmControllerSection(:final title, :final children):
        sections.add((path: path, title: title));
        for (var index = 0; index < children.length; index++) {
          _collectSections(
            children[index],
            path: '$path/$index',
            sections: sections,
          );
        }
      case AlgorithmControllerText():
      case AlgorithmControllerSlider():
      case AlgorithmControllerChoice():
      case AlgorithmControllerToggle():
      case AlgorithmControllerButton():
      case AlgorithmControllerDivider():
      case AlgorithmControllerSpacer():
      case AlgorithmControllerCanvas():
      case AlgorithmControllerXYPad():
      case AlgorithmControllerNoteMask():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AlgorithmControllerDocumentBody(
      document: widget.document,
      slot: widget.slot,
      slotIndex: widget.slotIndex,
      units: widget.units,
      sectionController: widget.sectionController,
    );
  }
}

class _AlgorithmControllerDocumentBody extends StatelessWidget {
  const _AlgorithmControllerDocumentBody({
    required this.document,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.sectionController,
  });

  final AlgorithmControllerDocument document;
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final AlgorithmControllerSectionController sectionController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Semantics(
              header: true,
              child: Text(
                document.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          _buildNode(context, document.root, path: 'root'),
        ],
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    AlgorithmControllerNode node, {
    required String path,
  }) {
    return switch (node) {
      AlgorithmControllerColumn node => Padding(
        padding: EdgeInsets.all(node.padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _withGaps(
            [
              for (var index = 0; index < node.children.length; index++)
                _buildNode(context, node.children[index], path: '$path/$index'),
            ],
            node.gap,
            Axis.vertical,
          ),
        ),
      ),
      AlgorithmControllerRow node => Wrap(
        spacing: node.gap,
        runSpacing: node.gap,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < node.children.length; index++)
            _buildNode(context, node.children[index], path: '$path/$index'),
        ],
      ),
      AlgorithmControllerSection node => _buildSection(context, node, path),
      AlgorithmControllerText node => _buildText(context, node),
      AlgorithmControllerSlider node => _buildSlider(context, node),
      AlgorithmControllerChoice node => _buildChoice(context, node),
      AlgorithmControllerToggle node => _buildToggle(context, node),
      AlgorithmControllerButton node => _buildButton(context, node),
      AlgorithmControllerDivider() => const Divider(),
      AlgorithmControllerSpacer node => SizedBox(height: node.size),
      AlgorithmControllerCanvas node => _buildCanvas(context, node),
      AlgorithmControllerXYPad node => _buildXYPad(context, node),
      AlgorithmControllerNoteMask node => _buildNoteMask(context, node),
    };
  }

  Widget _buildSection(
    BuildContext context,
    AlgorithmControllerSection node,
    String path,
  ) {
    final expansionController = sectionController.controllerFor(path);
    final inheritedListTileTheme = ListTileTheme.of(context);
    final headerListTileTheme = inheritedListTileTheme.copyWith(
      tileColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.10),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme(
        data: headerListTileTheme,
        child: ExpansionTile(
          key: ValueKey('algorithm-controller-section:$path'),
          controller: expansionController,
          initiallyExpanded: expansionController.isExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          title: Semantics(
            header: true,
            child: Text(
              node.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          subtitle: switch (node.subtitle) {
            final subtitle? => Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            null => null,
          },
          children: _withGaps(
            [
              for (var index = 0; index < node.children.length; index++)
                ListTileTheme(
                  data: inheritedListTileTheme,
                  child: _buildNode(
                    context,
                    node.children[index],
                    path: '$path/$index',
                  ),
                ),
            ],
            10,
            Axis.vertical,
          ),
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, AlgorithmControllerText node) {
    final theme = Theme.of(context).textTheme;
    final style = switch (node.style) {
      'title' => theme.titleLarge,
      'subtitle' => theme.titleMedium,
      'caption' => theme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      _ => theme.bodyMedium,
    };
    final align = switch (node.align) {
      'center' => TextAlign.center,
      'end' => TextAlign.end,
      _ => TextAlign.start,
    };
    return Text(node.text, style: style, textAlign: align);
  }

  Widget _buildSlider(BuildContext context, AlgorithmControllerSlider node) {
    final binding = _binding(node.parameterNumber);
    if (binding == null) {
      return _missingParameter(context, node.label, node.parameterNumber);
    }

    final minimum = (node.minimum ?? binding.minimum).clamp(
      binding.minimum,
      binding.maximum,
    );
    final maximum = (node.maximum ?? binding.maximum).clamp(
      binding.minimum,
      binding.maximum,
    );
    final validRange = minimum < maximum;
    final value = validRange ? binding.value.clamp(minimum, maximum) : minimum;
    final enabled = node.enabled && !binding.disabled && validRange;
    final divisions = validRange && maximum - minimum <= 256
        ? maximum - minimum
        : null;
    final displayValue = _formattedValue(binding, value);
    final defaultValue = binding.defaultValue.clamp(
      binding.minimum,
      binding.maximum,
    );
    final resetToDefault = enabled
        ? () {
            _writeParameter(
              context,
              node.parameterNumber,
              defaultValue,
              changing: false,
            );
            SemanticsService.sendAnnouncement(
              View.of(context),
              '${node.label} reset to '
              '${_formattedValue(binding, defaultValue)}',
              Directionality.of(context),
            );
          }
        : null;

    return Semantics(
      customSemanticsActions: resetToDefault == null
          ? null
          : {
              CustomSemanticsAction(label: 'Reset ${node.label} to default'):
                  resetToDefault,
            },
      child: MergeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                node.label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: resetToDefault,
                child: Slider(
                  value: value.toDouble(),
                  min: minimum.toDouble(),
                  max: validRange ? maximum.toDouble() : minimum.toDouble() + 1,
                  divisions: divisions,
                  label: displayValue,
                  semanticFormatterCallback: (newValue) =>
                      '${node.label} '
                      '${_formattedValue(binding, newValue.round())}',
                  onChanged: enabled
                      ? (newValue) => _writeParameter(
                          context,
                          node.parameterNumber,
                          newValue.round(),
                          changing: true,
                        )
                      : null,
                  onChangeEnd: enabled
                      ? (newValue) => _writeParameter(
                          context,
                          node.parameterNumber,
                          newValue.round(),
                          changing: false,
                        )
                      : null,
                ),
              ),
            ),
            SizedBox(
              width: 96,
              child: Text(
                displayValue,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoice(BuildContext context, AlgorithmControllerChoice node) {
    final binding = _binding(node.parameterNumber);
    if (binding == null) {
      return _missingParameter(context, node.label, node.parameterNumber);
    }
    final enumValues = binding.enumValues;
    final complete =
        binding.minimum >= 0 &&
        binding.maximum < enumValues.length &&
        [
          for (var value = binding.minimum; value <= binding.maximum; value++)
            enumValues[value],
        ].every((label) => label.isNotEmpty);
    if (!complete) {
      return _buildSlider(
        context,
        AlgorithmControllerSlider(
          label: node.label,
          parameterNumber: node.parameterNumber,
          enabled: node.enabled,
        ),
      );
    }

    final enabled = node.enabled && !binding.disabled;
    return Semantics(
      container: true,
      label: '${node.label} choices',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node.label, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (
                var value = binding.minimum;
                value <= binding.maximum;
                value++
              )
                Semantics(
                  button: true,
                  selected: binding.value == value,
                  label: '${node.label}: ${enumValues[value]}',
                  child: ExcludeSemantics(
                    child: ChoiceChip(
                      label: Text(enumValues[value]),
                      selected: binding.value == value,
                      onSelected: enabled
                          ? (selected) {
                              if (!selected || binding.value == value) return;
                              _writeParameter(
                                context,
                                node.parameterNumber,
                                value,
                                changing: false,
                              );
                              SemanticsService.sendAnnouncement(
                                View.of(context),
                                '${node.label} ${enumValues[value]} selected',
                                Directionality.of(context),
                              );
                            }
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(BuildContext context, AlgorithmControllerToggle node) {
    final binding = _binding(node.parameterNumber);
    if (binding == null) {
      return _missingParameter(context, node.label, node.parameterNumber);
    }
    final enabled = node.enabled && !binding.disabled;
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(node.label),
      value: binding.value == node.onValue,
      onChanged: enabled
          ? (selected) => _writeParameter(
              context,
              node.parameterNumber,
              selected ? node.onValue : node.offValue,
              changing: false,
            )
          : null,
    );
  }

  Widget _buildButton(BuildContext context, AlgorithmControllerButton node) {
    final binding = _binding(node.action.parameterNumber);
    final enabled = node.enabled && binding != null && !binding.disabled;
    final onPressed = enabled
        ? () => unawaited(_performAction(context, node.action))
        : null;
    return switch (node.style) {
      'text' => TextButton(onPressed: onPressed, child: Text(node.label)),
      'outlined' => OutlinedButton(
        onPressed: onPressed,
        child: Text(node.label),
      ),
      _ => FilledButton(onPressed: onPressed, child: Text(node.label)),
    };
  }

  Widget _buildCanvas(BuildContext context, AlgorithmControllerCanvas node) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _algorithmControllerCanvasWidth,
        ),
        child: Semantics(
          image: true,
          label: node.semanticsLabel,
          child: ExcludeSemantics(
            child: AspectRatio(
              aspectRatio: node.aspectRatio.clamp(0.25, 20),
              child: CustomPaint(
                painter: _AlgorithmControllerCanvasPainter(
                  shapes: node.shapes,
                  colorScheme: colorScheme,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteMask(
    BuildContext context,
    AlgorithmControllerNoteMask node,
  ) {
    final entriesByPitchClass = <int, AlgorithmControllerNoteMaskEntry>{};
    for (final entry in node.notes) {
      final pitchClass = entry.pitchClass;
      if (pitchClass != null) entriesByPitchClass[pitchClass] = entry;
    }
    final content = switch (node.layout) {
      AlgorithmControllerNoteMaskLayout.piano => SizedBox(
        width: _algorithmControllerNoteMaskWidth,
        height: 120,
        child: Stack(
          children: [
            for (var pitchClass = 0; pitchClass < 12; pitchClass++)
              _buildPianoNote(
                context,
                node,
                pitchClass,
                entriesByPitchClass[pitchClass],
              ),
          ],
        ),
      ),
      AlgorithmControllerNoteMaskLayout.degrees => SizedBox(
        width: _algorithmControllerNoteMaskWidth,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in node.notes)
              _buildNoteButton(
                context,
                node,
                entry,
                accidental: false,
                key: ValueKey(
                  'algorithm-controller-note-mask:${node.label}:'
                  'parameter-${entry.parameterNumber}',
                ),
              ),
          ],
        ),
      ),
    };

    return Semantics(
      container: true,
      label: node.label,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _algorithmControllerNoteMaskWidth,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildPianoNote(
    BuildContext context,
    AlgorithmControllerNoteMask node,
    int pitchClass,
    AlgorithmControllerNoteMaskEntry? entry,
  ) {
    const naturalPitchClasses = [0, 2, 4, 5, 7, 9, 11];
    const accidentalPitchClasses = [1, 3, 6, 8, 10];
    final naturalIndex = naturalPitchClasses.indexOf(pitchClass);
    final accidentalIndex = accidentalPitchClasses.indexOf(pitchClass);
    final accidental = accidentalIndex >= 0;
    final center = accidental
        ? const [
            Offset(60, 28),
            Offset(132, 28),
            Offset(276, 28),
            Offset(348, 28),
            Offset(420, 28),
          ][accidentalIndex]
        : Offset(24 + naturalIndex * 72, 88);
    final key = ValueKey(
      'algorithm-controller-note-mask:${node.label}:pitch-$pitchClass',
    );

    return Positioned(
      left: center.dx - _algorithmControllerNoteTargetSize / 2,
      top: center.dy - _algorithmControllerNoteTargetSize / 2,
      width: _algorithmControllerNoteTargetSize,
      height: _algorithmControllerNoteTargetSize,
      child: entry == null
          ? ExcludeSemantics(
              child: _noteCircle(
                context,
                key: key,
                included: false,
                accidental: accidental,
                available: false,
              ),
            )
          : _buildNoteButton(
              context,
              node,
              entry,
              accidental: accidental,
              key: key,
            ),
    );
  }

  Widget _buildNoteButton(
    BuildContext context,
    AlgorithmControllerNoteMask node,
    AlgorithmControllerNoteMaskEntry entry, {
    required bool accidental,
    required Key key,
  }) {
    final binding = _binding(entry.parameterNumber);
    final included = binding?.value == 1;
    final enabled =
        node.enabled &&
        binding != null &&
        !binding.disabled &&
        binding.minimum <= 0 &&
        binding.maximum >= 1;
    final newValue = included ? 0 : 1;

    return Semantics(
      button: true,
      toggled: included,
      enabled: enabled,
      label: entry.label,
      value: included ? 'Included' : 'Excluded',
      onTap: enabled
          ? () => _toggleNote(context, entry, newValue: newValue)
          : null,
      child: ExcludeSemantics(
        child: _noteCircle(
          context,
          key: key,
          included: included,
          accidental: accidental,
          available: true,
          onPressed: enabled
              ? () => _toggleNote(context, entry, newValue: newValue)
              : null,
        ),
      ),
    );
  }

  Widget _noteCircle(
    BuildContext context, {
    required Key key,
    required bool included,
    required bool accidental,
    required bool available,
    VoidCallback? onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    final unselectedColor = accidental
        ? colors.inverseSurface.withValues(alpha: 0.78)
        : colors.surfaceContainerHighest;
    final outlineColor = accidental ? colors.outlineVariant : colors.outline;
    final opacity = available ? 1.0 : 0.28;
    return Opacity(
      opacity: opacity,
      child: IconButton(
        key: key,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(_algorithmControllerNoteTargetSize),
          padding: EdgeInsets.zero,
          shape: CircleBorder(
            side: BorderSide(
              color: included ? colors.primary : outlineColor,
              width: included ? 2 : 1,
            ),
          ),
          backgroundColor: included ? colors.primary : unselectedColor,
          disabledBackgroundColor: included ? colors.primary : unselectedColor,
          foregroundColor: included ? colors.onPrimary : colors.onSurface,
          disabledForegroundColor: included
              ? colors.onPrimary
              : colors.onSurface,
        ),
        icon: const SizedBox.shrink(),
      ),
    );
  }

  void _toggleNote(
    BuildContext context,
    AlgorithmControllerNoteMaskEntry entry, {
    required int newValue,
  }) {
    _writeParameter(context, entry.parameterNumber, newValue, changing: false);
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${entry.label} ${newValue == 1 ? 'included' : 'excluded'}',
      Directionality.of(context),
    );
  }

  Widget _buildXYPad(BuildContext context, AlgorithmControllerXYPad node) {
    final xBinding = _binding(node.xParameterNumber);
    final yBinding = _binding(node.yParameterNumber);
    if (xBinding == null) {
      return _missingParameter(context, node.xLabel, node.xParameterNumber);
    }
    if (yBinding == null) {
      return _missingParameter(context, node.yLabel, node.yParameterNumber);
    }

    final enabled =
        node.enabled &&
        !xBinding.disabled &&
        !yBinding.disabled &&
        xBinding.minimum < xBinding.maximum &&
        yBinding.minimum < yBinding.maximum;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: _algorithmControllerXYPadWidth,
        child: _AlgorithmControllerXYPadView(
          label: node.label,
          xLabel: node.xLabel,
          yLabel: node.yLabel,
          xValue: xBinding.value,
          yValue: yBinding.value,
          xDefault: xBinding.defaultValue,
          yDefault: yBinding.defaultValue,
          xMinimum: xBinding.minimum,
          xMaximum: xBinding.maximum,
          yMinimum: yBinding.minimum,
          yMaximum: yBinding.maximum,
          aspectRatio: node.aspectRatio.clamp(0.25, 20).toDouble(),
          invertY: node.invertY,
          enabled: enabled,
          formatX: (value) => _formattedValue(xBinding, value),
          formatY: (value) => _formattedValue(yBinding, value),
          onXChanged: (value, changing) => _writeParameter(
            context,
            node.xParameterNumber,
            value,
            changing: changing,
          ),
          onYChanged: (value, changing) => _writeParameter(
            context,
            node.yParameterNumber,
            value,
            changing: changing,
          ),
        ),
      ),
    );
  }

  Widget _missingParameter(BuildContext context, String label, int number) {
    return Text(
      '$label is unavailable (parameter $number)',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }

  _AlgorithmControllerParameterBinding? _binding(int parameterNumber) {
    final info = slot.parameters.byParameterNumber(parameterNumber);
    if (info == null) return null;
    final value = slot.values.byParameterNumber(parameterNumber);
    final enums = slot.enums.byParameterNumber(parameterNumber);
    final valueString = slot.valueStrings.byParameterNumber(parameterNumber);
    final rawUnit = info.getUnitString(units)?.trim();
    return (
      minimum: info.min,
      maximum: info.max,
      defaultValue: info.defaultValue,
      value: value?.value ?? info.defaultValue,
      disabled: value?.isDisabled ?? false,
      enumValues: [
        for (final enumValue in enums?.values ?? const <String>[])
          enumValue.trim(),
      ],
      displayValue: valueString?.value.trim() ?? '',
      name: info.name,
      powerOfTen: info.powerOfTen,
      unit: rawUnit == null || rawUnit.isEmpty ? null : rawUnit,
    );
  }

  String _formattedValue(
    _AlgorithmControllerParameterBinding binding,
    int value,
  ) {
    if (value == binding.value && binding.displayValue.isNotEmpty) {
      return binding.displayValue;
    }
    if (value >= 0 &&
        value < binding.enumValues.length &&
        binding.enumValues[value].isNotEmpty) {
      return binding.enumValues[value];
    }
    final unit = binding.unit;
    if (unit == null) {
      return formatEditableNumericValue(value, binding.powerOfTen);
    }
    return formatWithUnit(
      value,
      name: binding.name,
      min: binding.minimum,
      max: binding.maximum,
      unit: unit,
      powerOfTen: binding.powerOfTen,
    );
  }

  Future<void> _performAction(
    BuildContext context,
    AlgorithmControllerAction action,
  ) async {
    final binding = _binding(action.parameterNumber);
    if (binding == null) return;
    switch (action.type) {
      case AlgorithmControllerActionType.setParameter:
        await _writeParameterFuture(
          context,
          action.parameterNumber,
          action.value!,
          changing: false,
        );
      case AlgorithmControllerActionType.adjustParameter:
        await _writeParameterFuture(
          context,
          action.parameterNumber,
          binding.value + action.delta!,
          changing: false,
        );
      case AlgorithmControllerActionType.pulseParameter:
        await _writeParameterFuture(
          context,
          action.parameterNumber,
          action.onValue!,
          changing: true,
        );
        if (!context.mounted) return;
        await Future<void>.delayed(Duration(milliseconds: action.durationMs!));
        if (!context.mounted) return;
        await _writeParameterFuture(
          context,
          action.parameterNumber,
          action.offValue!,
          changing: true,
        );
    }
  }

  void _writeParameter(
    BuildContext context,
    int parameterNumber,
    int value, {
    required bool changing,
  }) {
    unawaited(
      _writeParameterFuture(
        context,
        parameterNumber,
        value,
        changing: changing,
      ),
    );
  }

  Future<void> _writeParameterFuture(
    BuildContext context,
    int parameterNumber,
    int value, {
    required bool changing,
  }) async {
    final binding = _binding(parameterNumber);
    if (binding == null) return;
    await context.read<DistingCubit>().updateParameterValue(
      algorithmIndex: slotIndex,
      parameterNumber: parameterNumber,
      value: value.clamp(binding.minimum, binding.maximum),
      userIsChangingTheValue: changing,
    );
  }

  List<Widget> _withGaps(List<Widget> children, double gap, Axis axis) {
    if (children.length < 2 || gap <= 0) return children;
    final result = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        result.add(
          axis == Axis.vertical ? SizedBox(height: gap) : SizedBox(width: gap),
        );
      }
      result.add(children[index]);
    }
    return result;
  }
}

typedef _AlgorithmControllerXYValueChanged =
    void Function(int value, bool changing);

final class _AlgorithmControllerXYPadView extends StatefulWidget {
  const _AlgorithmControllerXYPadView({
    required this.label,
    required this.xLabel,
    required this.yLabel,
    required this.xValue,
    required this.yValue,
    required this.xDefault,
    required this.yDefault,
    required this.xMinimum,
    required this.xMaximum,
    required this.yMinimum,
    required this.yMaximum,
    required this.aspectRatio,
    required this.invertY,
    required this.enabled,
    required this.formatX,
    required this.formatY,
    required this.onXChanged,
    required this.onYChanged,
  });

  final String label;
  final String xLabel;
  final String yLabel;
  final int xValue;
  final int yValue;
  final int xDefault;
  final int yDefault;
  final int xMinimum;
  final int xMaximum;
  final int yMinimum;
  final int yMaximum;
  final double aspectRatio;
  final bool invertY;
  final bool enabled;
  final String Function(int value) formatX;
  final String Function(int value) formatY;
  final _AlgorithmControllerXYValueChanged onXChanged;
  final _AlgorithmControllerXYValueChanged onYChanged;

  @override
  State<_AlgorithmControllerXYPadView> createState() =>
      _AlgorithmControllerXYPadViewState();
}

final class _AlgorithmControllerXYPadViewState
    extends State<_AlgorithmControllerXYPadView> {
  late int _xValue = widget.xValue
      .clamp(widget.xMinimum, widget.xMaximum)
      .toInt();
  late int _yValue = widget.yValue
      .clamp(widget.yMinimum, widget.yMaximum)
      .toInt();
  bool _dragging = false;
  bool _showFocusHighlight = false;

  int get _xStep =>
      math.max(1, ((widget.xMaximum - widget.xMinimum) / 100).round());
  int get _yStep =>
      math.max(1, ((widget.yMaximum - widget.yMinimum) / 100).round());

  @override
  void didUpdateWidget(covariant _AlgorithmControllerXYPadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging) {
      _xValue = widget.xValue.clamp(widget.xMinimum, widget.xMaximum).toInt();
      _yValue = widget.yValue.clamp(widget.yMinimum, widget.yMaximum).toInt();
    }
  }

  void _setFromPosition(Offset position, Size size, {required bool changing}) {
    if (!widget.enabled || size.width <= 0 || size.height <= 0) return;
    final xFraction = (position.dx / size.width).clamp(0.0, 1.0);
    final rawYFraction = (position.dy / size.height).clamp(0.0, 1.0);
    final yFraction = widget.invertY ? 1 - rawYFraction : rawYFraction;
    final xValue =
        widget.xMinimum +
        (xFraction * (widget.xMaximum - widget.xMinimum)).round();
    final yValue =
        widget.yMinimum +
        (yFraction * (widget.yMaximum - widget.yMinimum)).round();
    _setValues(xValue, yValue, changing: changing);
  }

  void _setValues(int xValue, int yValue, {required bool changing}) {
    final clampedX = xValue.clamp(widget.xMinimum, widget.xMaximum).toInt();
    final clampedY = yValue.clamp(widget.yMinimum, widget.yMaximum).toInt();
    final xChanged = clampedX != _xValue;
    final yChanged = clampedY != _yValue;
    if (!xChanged && !yChanged) return;
    setState(() {
      _xValue = clampedX;
      _yValue = clampedY;
    });
    if (xChanged) widget.onXChanged(clampedX, changing);
    if (yChanged) widget.onYChanged(clampedY, changing);
  }

  void _finishDrag() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onXChanged(_xValue, false);
    widget.onYChanged(_yValue, false);
  }

  void _nudgeX(int delta) {
    if (!widget.enabled) return;
    final next = (_xValue + delta)
        .clamp(widget.xMinimum, widget.xMaximum)
        .toInt();
    if (next == _xValue) return;
    setState(() => _xValue = next);
    widget.onXChanged(next, false);
  }

  void _nudgeY(int delta) {
    if (!widget.enabled) return;
    final next = (_yValue + delta)
        .clamp(widget.yMinimum, widget.yMaximum)
        .toInt();
    if (next == _yValue) return;
    setState(() => _yValue = next);
    widget.onYChanged(next, false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final xText = widget.formatX(_xValue);
    final yText = widget.formatY(_yValue);
    final nextX = (_xValue + _xStep)
        .clamp(widget.xMinimum, widget.xMaximum)
        .toInt();
    final previousX = (_xValue - _xStep)
        .clamp(widget.xMinimum, widget.xMaximum)
        .toInt();
    void resetToDefault() {
      _setValues(widget.xDefault, widget.yDefault, changing: false);
      SemanticsService.sendAnnouncement(
        View.of(context),
        '${widget.label} reset to default',
        Directionality.of(context),
      );
    }

    final customActions = widget.enabled
        ? <CustomSemanticsAction, VoidCallback>{
            CustomSemanticsAction(label: 'Decrease ${widget.xLabel}'): () =>
                _nudgeX(-_xStep),
            CustomSemanticsAction(label: 'Increase ${widget.xLabel}'): () =>
                _nudgeX(_xStep),
            CustomSemanticsAction(label: 'Decrease ${widget.yLabel}'): () =>
                _nudgeY(-_yStep),
            CustomSemanticsAction(label: 'Increase ${widget.yLabel}'): () =>
                _nudgeY(_yStep),
            CustomSemanticsAction(label: 'Reset ${widget.label} to default'):
                resetToDefault,
          }
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Text(
                '${widget.xLabel} $xText · ${widget.yLabel} $yText',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FocusableActionDetector(
          enabled: widget.enabled,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowLeft): _MoveXYLeftIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                _MoveXYRightIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): _MoveXYUpIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown): _MoveXYDownIntent(),
          },
          actions: {
            _MoveXYLeftIntent: CallbackAction<_MoveXYLeftIntent>(
              onInvoke: (_) {
                _nudgeX(-_xStep);
                return null;
              },
            ),
            _MoveXYRightIntent: CallbackAction<_MoveXYRightIntent>(
              onInvoke: (_) {
                _nudgeX(_xStep);
                return null;
              },
            ),
            _MoveXYUpIntent: CallbackAction<_MoveXYUpIntent>(
              onInvoke: (_) {
                _nudgeY(widget.invertY ? _yStep : -_yStep);
                return null;
              },
            ),
            _MoveXYDownIntent: CallbackAction<_MoveXYDownIntent>(
              onInvoke: (_) {
                _nudgeY(widget.invertY ? -_yStep : _yStep);
                return null;
              },
            ),
          },
          onShowFocusHighlight: (value) {
            if (_showFocusHighlight == value) return;
            setState(() => _showFocusHighlight = value);
          },
          child: Semantics(
            container: true,
            enabled: widget.enabled,
            label: widget.label,
            value: '${widget.xLabel} $xText, ${widget.yLabel} $yText',
            hint: widget.enabled
                ? 'Drag to position. Arrow keys change the two axes.'
                : null,
            increasedValue:
                '${widget.xLabel} ${widget.formatX(nextX)}, '
                '${widget.yLabel} $yText',
            decreasedValue:
                '${widget.xLabel} ${widget.formatX(previousX)}, '
                '${widget.yLabel} $yText',
            onIncrease: widget.enabled ? () => _nudgeX(_xStep) : null,
            onDecrease: widget.enabled ? () => _nudgeX(-_xStep) : null,
            customSemanticsActions: customActions,
            child: ExcludeSemantics(
              child: AspectRatio(
                aspectRatio: widget.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return MouseRegion(
                      cursor: widget.enabled
                          ? SystemMouseCursors.precise
                          : SystemMouseCursors.basic,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: widget.enabled
                            ? (_) => Focus.of(context).requestFocus()
                            : null,
                        onTapUp: widget.enabled
                            ? (details) => _setFromPosition(
                                details.localPosition,
                                size,
                                changing: false,
                              )
                            : null,
                        onDoubleTap: widget.enabled ? resetToDefault : null,
                        onPanStart: widget.enabled
                            ? (details) {
                                Focus.of(context).requestFocus();
                                setState(() => _dragging = true);
                                _setFromPosition(
                                  details.localPosition,
                                  size,
                                  changing: true,
                                );
                              }
                            : null,
                        onPanUpdate: widget.enabled
                            ? (details) => _setFromPosition(
                                details.localPosition,
                                size,
                                changing: true,
                              )
                            : null,
                        onPanEnd: widget.enabled ? (_) => _finishDrag() : null,
                        onPanCancel: widget.enabled ? _finishDrag : null,
                        child: DecoratedBox(
                          key: ValueKey(
                            'algorithm-controller-xy-pad:${widget.label}',
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _showFocusHighlight
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              width: _showFocusHighlight ? 3 : 1,
                            ),
                          ),
                          child: CustomPaint(
                            painter: _AlgorithmControllerXYPadPainter(
                              xValue: _xValue,
                              yValue: _yValue,
                              xMinimum: widget.xMinimum,
                              xMaximum: widget.xMaximum,
                              yMinimum: widget.yMinimum,
                              yMaximum: widget.yMaximum,
                              invertY: widget.invertY,
                              enabled: widget.enabled,
                              colorScheme: colorScheme,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _MoveXYLeftIntent extends Intent {
  const _MoveXYLeftIntent();
}

final class _MoveXYRightIntent extends Intent {
  const _MoveXYRightIntent();
}

final class _MoveXYUpIntent extends Intent {
  const _MoveXYUpIntent();
}

final class _MoveXYDownIntent extends Intent {
  const _MoveXYDownIntent();
}

final class _AlgorithmControllerXYPadPainter extends CustomPainter {
  const _AlgorithmControllerXYPadPainter({
    required this.xValue,
    required this.yValue,
    required this.xMinimum,
    required this.xMaximum,
    required this.yMinimum,
    required this.yMaximum,
    required this.invertY,
    required this.enabled,
    required this.colorScheme,
  });

  final int xValue;
  final int yValue;
  final int xMinimum;
  final int xMaximum;
  final int yMinimum;
  final int yMaximum;
  final bool invertY;
  final bool enabled;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final roundedRect = RRect.fromRectAndRadius(
      rect.deflate(1),
      const Radius.circular(11),
    );
    canvas
      ..clipRRect(roundedRect)
      ..drawRRect(
        roundedRect,
        Paint()
          ..color = colorScheme.surfaceContainerHighest
          ..style = PaintingStyle.fill,
      );

    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final fraction = index / 4;
      canvas
        ..drawLine(
          Offset(size.width * fraction, 0),
          Offset(size.width * fraction, size.height),
          gridPaint,
        )
        ..drawLine(
          Offset(0, size.height * fraction),
          Offset(size.width, size.height * fraction),
          gridPaint,
        );
    }

    final axisPaint = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1.5;
    canvas
      ..drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        axisPaint,
      )
      ..drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        axisPaint,
      );

    final xFraction = xMaximum == xMinimum
        ? 0.5
        : (xValue - xMinimum) / (xMaximum - xMinimum);
    final rawYFraction = yMaximum == yMinimum
        ? 0.5
        : (yValue - yMinimum) / (yMaximum - yMinimum);
    final yFraction = invertY ? 1 - rawYFraction : rawYFraction;
    final center = Offset(
      xFraction.clamp(0.0, 1.0) * size.width,
      yFraction.clamp(0.0, 1.0) * size.height,
    );
    final radius = math.min(size.width, size.height) * 0.045;
    canvas
      ..drawCircle(
        center,
        radius + 4,
        Paint()
          ..color = colorScheme.surface
          ..style = PaintingStyle.fill,
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..color = enabled ? colorScheme.primary : colorScheme.onSurfaceVariant
          ..style = PaintingStyle.fill,
      );
  }

  @override
  bool shouldRepaint(covariant _AlgorithmControllerXYPadPainter oldDelegate) {
    return oldDelegate.xValue != xValue ||
        oldDelegate.yValue != yValue ||
        oldDelegate.xMinimum != xMinimum ||
        oldDelegate.xMaximum != xMaximum ||
        oldDelegate.yMinimum != yMinimum ||
        oldDelegate.yMaximum != yMaximum ||
        oldDelegate.invertY != invertY ||
        oldDelegate.enabled != enabled ||
        oldDelegate.colorScheme != colorScheme;
  }
}

final class _AlgorithmControllerCanvasPainter extends CustomPainter {
  const _AlgorithmControllerCanvasPainter({
    required this.shapes,
    required this.colorScheme,
  });

  final List<AlgorithmControllerCanvasShape> shapes;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final scale = math.min(size.width, size.height);
    for (final shape in shapes) {
      switch (shape) {
        case AlgorithmControllerCircle shape:
          final center = Offset(shape.x * size.width, shape.y * size.height);
          final radius = shape.radius * scale;
          _paintFillAndStroke(
            canvas,
            Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
            fill: shape.fill,
            stroke: shape.stroke,
            strokeWidth: shape.strokeWidth,
          );
        case AlgorithmControllerLine shape:
          canvas.drawLine(
            Offset(shape.x1 * size.width, shape.y1 * size.height),
            Offset(shape.x2 * size.width, shape.y2 * size.height),
            Paint()
              ..color = _color(shape.stroke)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = shape.strokeWidth,
          );
        case AlgorithmControllerRectangle shape:
          final rect = Rect.fromLTWH(
            shape.x * size.width,
            shape.y * size.height,
            shape.width * size.width,
            shape.height * size.height,
          );
          _paintFillAndStroke(
            canvas,
            Path()..addRRect(
              RRect.fromRectAndRadius(
                rect,
                Radius.circular(shape.radius * scale),
              ),
            ),
            fill: shape.fill,
            stroke: shape.stroke,
            strokeWidth: shape.strokeWidth,
          );
      }
    }
  }

  void _paintFillAndStroke(
    Canvas canvas,
    Path path, {
    required String? fill,
    required String? stroke,
    required double strokeWidth,
  }) {
    if (fill != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(fill)
          ..style = PaintingStyle.fill,
      );
    }
    if (stroke != null && strokeWidth > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = _color(stroke)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
    }
  }

  Color _color(String token) {
    return switch (token) {
      'primary' => colorScheme.primary,
      'on_primary' => colorScheme.onPrimary,
      'secondary' => colorScheme.secondary,
      'tertiary' => colorScheme.tertiary,
      'surface' => colorScheme.surface,
      'surface_container' => colorScheme.surfaceContainer,
      'surface_container_highest' => colorScheme.surfaceContainerHighest,
      'on_surface' => colorScheme.onSurface,
      'on_surface_variant' => colorScheme.onSurfaceVariant,
      'outline' => colorScheme.outline,
      'error' => colorScheme.error,
      'transparent' => Colors.transparent,
      _ => _hexColor(token) ?? colorScheme.outline,
    };
  }

  Color? _hexColor(String value) {
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (hex.length != 6 && hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(hex.length == 6 ? 0xff000000 | parsed : parsed);
  }

  @override
  bool shouldRepaint(covariant _AlgorithmControllerCanvasPainter oldDelegate) {
    return oldDelegate.shapes != shapes ||
        oldDelegate.colorScheme != colorScheme;
  }
}
