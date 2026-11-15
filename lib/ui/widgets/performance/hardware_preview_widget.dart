import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/performance_page_item.dart';

enum PerformanceLayoutMode { condensed, asIndexed }

typedef ParameterChangedCallback = void Function(
  int slotIndex,
  int parameterNumber,
  int value,
  bool userIsChanging,
);

class HardwarePreviewWidget extends StatelessWidget {
  const HardwarePreviewWidget({
    super.key,
    this.parameters = const [],
    this.layoutMode = PerformanceLayoutMode.asIndexed,
    this.perfPageItems,
    this.slots,
    this.onParameterChanged,
  });

  final List<MappedParameter> parameters;
  final PerformanceLayoutMode layoutMode;
  final List<PerformancePageItem>? perfPageItems;
  final List<Slot>? slots;
  final ParameterChangedCallback? onParameterChanged;

  @override
  Widget build(BuildContext context) {
    List<_PageData> pages;
    if (perfPageItems != null && perfPageItems!.isNotEmpty) {
      pages = _buildPerfItemPages();
    } else if (layoutMode == PerformanceLayoutMode.condensed) {
      pages = _buildCondensedPages();
    } else {
      pages = _buildAsIndexedPages();
    }

    if (pages.isEmpty) {
      return Center(
        child: Text(
          'No parameters assigned',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pages.length,
      itemBuilder: (context, index) {
        final page = pages[index];
        return _PageCard(
          pageNumber: page.pageNumber,
          knobs: page.knobs,
          onParameterChanged: onParameterChanged,
        );
      },
    );
  }

  List<_PageData> _buildPerfItemPages() {
    final items = perfPageItems!;
    final maxIndex = items
        .map((i) => i.itemIndex)
        .reduce((a, b) => a > b ? a : b);
    final totalPages = (maxIndex ~/ 3) + 1;

    final itemByIndex = <int, PerformancePageItem>{};
    for (final item in items) {
      itemByIndex[item.itemIndex] = item;
    }

    final pages = <_PageData>[];
    for (var page = 0; page < totalPages; page++) {
      final knobs = <_KnobData>[];
      for (var k = 0; k < 3; k++) {
        final index = page * 3 + k;
        final item = itemByIndex[index];
        if (item != null) {
          double? fillFraction;
          if (item.min != item.max && slots != null) {
            if (item.slotIndex < slots!.length) {
              final slot = slots![item.slotIndex];
              if (item.parameterNumber < slot.values.length) {
                final currentValue = slot.values[item.parameterNumber].value;
                fillFraction =
                    ((currentValue - item.min) / (item.max - item.min)).clamp(
                      0.0,
                      1.0,
                    );
              }
            }
          }
          knobs.add(
            _KnobData(
              label: item.upperLabel.isNotEmpty
                  ? item.upperLabel
                  : 'Item ${item.itemIndex + 1}',
              algorithmName: item.lowerLabel.isNotEmpty
                  ? item.lowerLabel
                  : 'Slot ${item.slotIndex + 1}, P${item.parameterNumber}',
              isEmpty: false,
              fillFraction: fillFraction,
              slotIndex: item.slotIndex,
              parameterNumber: item.parameterNumber,
              rangeMin: item.min,
              rangeMax: item.max,
            ),
          );
        } else {
          knobs.add(
            const _KnobData(label: '', algorithmName: '', isEmpty: true),
          );
        }
      }
      pages.add(_PageData(pageNumber: page + 1, knobs: knobs));
    }
    return pages;
  }

  List<_PageData> _buildCondensedPages() {
    if (parameters.isEmpty) return [];

    final pages = <_PageData>[];
    for (var i = 0; i < parameters.length; i += 3) {
      final pageNumber = (i ~/ 3) + 1;
      final knobs = <_KnobData>[];
      for (var k = 0; k < 3; k++) {
        if (i + k < parameters.length) {
          final p = parameters[i + k];
          double? fillFraction;
          if (slots != null) {
            if (p.parameter.algorithmIndex < slots!.length) {
              final slot = slots![p.parameter.algorithmIndex];
              if (p.parameter.parameterNumber < slot.values.length) {
                final currentValue =
                    slot.values[p.parameter.parameterNumber].value;
                final min = p.parameter.min;
                final max = p.parameter.max;
                if (min != max) {
                  fillFraction = ((currentValue - min) / (max - min)).clamp(
                    0.0,
                    1.0,
                  );
                }
              }
            }
          }
          knobs.add(
            _KnobData(
              label: p.parameter.name,
              algorithmName: p.algorithm.name,
              isEmpty: false,
              fillFraction: fillFraction,
              slotIndex: p.parameter.algorithmIndex,
              parameterNumber: p.parameter.parameterNumber,
              rangeMin: p.parameter.min,
              rangeMax: p.parameter.max,
            ),
          );
        } else {
          knobs.add(
            const _KnobData(label: '', algorithmName: '', isEmpty: true),
          );
        }
      }
      pages.add(_PageData(pageNumber: pageNumber, knobs: knobs));
    }
    return pages;
  }

  List<_PageData> _buildAsIndexedPages() {
    if (parameters.isEmpty) return [];

    final maxIndex = parameters
        .map((p) => p.mapping.packedMappingData.perfPageIndex)
        .reduce((a, b) => a > b ? a : b);

    final totalPages = ((maxIndex - 1) ~/ 3) + 1;
    final paramByIndex = <int, MappedParameter>{};
    for (final p in parameters) {
      paramByIndex[p.mapping.packedMappingData.perfPageIndex] = p;
    }

    final pages = <_PageData>[];
    for (var page = 0; page < totalPages; page++) {
      final knobs = <_KnobData>[];
      for (var k = 0; k < 3; k++) {
        final index = page * 3 + k + 1;
        final p = paramByIndex[index];
        if (p != null) {
          double? fillFraction;
          if (slots != null) {
            if (p.parameter.algorithmIndex < slots!.length) {
              final slot = slots![p.parameter.algorithmIndex];
              if (p.parameter.parameterNumber < slot.values.length) {
                final currentValue =
                    slot.values[p.parameter.parameterNumber].value;
                final min = p.parameter.min;
                final max = p.parameter.max;
                if (min != max) {
                  fillFraction = ((currentValue - min) / (max - min)).clamp(
                    0.0,
                    1.0,
                  );
                }
              }
            }
          }
          knobs.add(
            _KnobData(
              label: p.parameter.name,
              algorithmName: p.algorithm.name,
              isEmpty: false,
              fillFraction: fillFraction,
              slotIndex: p.parameter.algorithmIndex,
              parameterNumber: p.parameter.parameterNumber,
              rangeMin: p.parameter.min,
              rangeMax: p.parameter.max,
            ),
          );
        } else {
          knobs.add(
            const _KnobData(label: '', algorithmName: '', isEmpty: true),
          );
        }
      }
      pages.add(_PageData(pageNumber: page + 1, knobs: knobs));
    }
    return pages;
  }
}

class _PageData {
  const _PageData({required this.pageNumber, required this.knobs});
  final int pageNumber;
  final List<_KnobData> knobs;
}

class _KnobData {
  const _KnobData({
    required this.label,
    required this.algorithmName,
    required this.isEmpty,
    this.fillFraction,
    this.slotIndex,
    this.parameterNumber,
    this.rangeMin,
    this.rangeMax,
  });
  final String label;
  final String algorithmName;
  final bool isEmpty;
  final double? fillFraction;
  final int? slotIndex;
  final int? parameterNumber;
  final int? rangeMin;
  final int? rangeMax;

  bool get isInteractive =>
      !isEmpty &&
      slotIndex != null &&
      parameterNumber != null &&
      rangeMin != null &&
      rangeMax != null &&
      rangeMin != rangeMax;

  bool get isBoolean => rangeMin == 0 && rangeMax == 1;
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.pageNumber,
    required this.knobs,
    this.onParameterChanged,
  });

  final int pageNumber;
  final List<_KnobData> knobs;
  final ParameterChangedCallback? onParameterChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Page $pageNumber',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(3, (i) {
                const potLabels = ['L', 'C', 'R'];
                final knob = i < knobs.length ? knobs[i] : null;
                return Expanded(
                  child: _KnobSlot(
                    potLabel: potLabels[i],
                    knob: knob,
                    onParameterChanged: onParameterChanged,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _KnobSlot extends StatefulWidget {
  const _KnobSlot({required this.potLabel, this.knob, this.onParameterChanged});

  final String potLabel;
  final _KnobData? knob;
  final ParameterChangedCallback? onParameterChanged;

  @override
  State<_KnobSlot> createState() => _KnobSlotState();
}

class _KnobSlotState extends State<_KnobSlot> {
  bool _isDragging = false;
  double? _dragStartFill;
  double? _localFillFraction;
  DateTime? _lastPreviewSent;
  static const _previewThrottleDuration = Duration(milliseconds: 100);

  @override
  void didUpdateWidget(covariant _KnobSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKnob = oldWidget.knob;
    final newKnob = widget.knob;
    if (oldKnob?.slotIndex != newKnob?.slotIndex ||
        oldKnob?.parameterNumber != newKnob?.parameterNumber) {
      _isDragging = false;
      _localFillFraction = null;
    } else if (!_isDragging) {
      _localFillFraction = null;
    }
  }

  void _onTap() {
    final knob = widget.knob;
    if (knob == null ||
        !knob.isInteractive ||
        !knob.isBoolean ||
        widget.onParameterChanged == null) {
      return;
    }
    final currentFill = _localFillFraction ?? knob.fillFraction ?? 0.0;
    final newValue = currentFill >= 0.5 ? 0 : 1;
    setState(() {
      _localFillFraction = newValue.toDouble();
    });
    widget.onParameterChanged!(
      knob.slotIndex!,
      knob.parameterNumber!,
      newValue,
      false,
    );
  }

  void _onDragStart(DragStartDetails details) {
    final knob = widget.knob;
    if (knob == null ||
        !knob.isInteractive ||
        widget.onParameterChanged == null) {
      return;
    }
    setState(() {
      _isDragging = true;
      _dragStartFill = _localFillFraction ?? knob.fillFraction ?? 0.0;
      _localFillFraction = _dragStartFill;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final knob = widget.knob;
    if (!_isDragging ||
        knob == null ||
        !knob.isInteractive ||
        widget.onParameterChanged == null) {
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final width = renderBox.size.width;
    if (width <= 0) return;

    final delta = details.delta.dx / width;
    final newFill = (_localFillFraction! + delta).clamp(0.0, 1.0);
    final range = knob.rangeMax! - knob.rangeMin!;
    final value = (knob.rangeMin! + (newFill * range)).round();

    setState(() {
      _localFillFraction = newFill;
    });

    final now = DateTime.now();
    if (_lastPreviewSent == null ||
        now.difference(_lastPreviewSent!) > _previewThrottleDuration) {
      _lastPreviewSent = now;
      widget.onParameterChanged!(
        knob.slotIndex!,
        knob.parameterNumber!,
        value,
        true,
      );
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final knob = widget.knob;
    if (!_isDragging ||
        knob == null ||
        !knob.isInteractive ||
        widget.onParameterChanged == null) {
      return;
    }

    final fill = _localFillFraction ?? 0.0;
    final range = knob.rangeMax! - knob.rangeMin!;
    final value = (knob.rangeMin! + (fill * range)).round();
    final snappedFill = (value - knob.rangeMin!) / range;

    widget.onParameterChanged!(
      knob.slotIndex!,
      knob.parameterNumber!,
      value,
      false,
    );

    setState(() {
      _isDragging = false;
      _localFillFraction = snappedFill;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final knob = widget.knob;
    final isEmpty = knob == null || knob.isEmpty;

    final displayFill = _localFillFraction ?? knob?.fillFraction;

    final isInteractive =
        knob != null && knob.isInteractive && widget.onParameterChanged != null;

    Widget container = Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isEmpty
              ? colorScheme.outlineVariant.withAlpha(80)
              : colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isEmpty ? null : colorScheme.surfaceContainerLow,
        gradient: (!isEmpty && displayFill != null)
            ? LinearGradient(
                colors: [
                  colorScheme.secondary.withAlpha(60),
                  colorScheme.secondary.withAlpha(60),
                  colorScheme.surfaceContainerLow,
                  colorScheme.surfaceContainerLow,
                ],
                stops: [0.0, displayFill, displayFill, 1.0],
              )
            : null,
      ),
      child: Column(
        children: [
          Text(
            'Pot ${widget.potLabel}',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            isEmpty ? '---' : knob.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isEmpty
                  ? colorScheme.onSurfaceVariant.withAlpha(100)
                  : colorScheme.onSurface,
              fontWeight: isEmpty ? null : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (!isEmpty) ...[
            const SizedBox(height: 2),
            Text(
              knob.algorithmName,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant, fontSize: 9),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (knob.isBoolean) ...[
              const SizedBox(height: 2),
              Text(
                (displayFill ?? 0.0) >= 0.5 ? 'On' : 'Off',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: (displayFill ?? 0.0) >= 0.5
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );

    if (isInteractive) {
      final isBoolean = knob.isBoolean;
      container = GestureDetector(
        onTap: isBoolean ? _onTap : null,
        onHorizontalDragStart: isBoolean ? null : _onDragStart,
        onHorizontalDragUpdate: isBoolean ? null : _onDragUpdate,
        onHorizontalDragEnd: isBoolean ? null : _onDragEnd,
        child: container,
      );
    }

    return container;
  }
}
