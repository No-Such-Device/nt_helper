import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/performance/hardware_preview_widget.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key, required this.units});

  final List<String> units;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  bool _pollingEnabled = false;
  DistingCubit? _cubit;
  PerformanceLayoutMode _layoutMode = PerformanceLayoutMode.condensed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DistingCubit>().refreshPerfPageItems();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit = context.read<DistingCubit>();
  }

  @override
  void dispose() {
    _cubit?.stopPollingMappedParameters();
    super.dispose();
  }

  // --- Legacy (pre-v1.16) helpers ---

  Map<String, int> _buildParameterOrderMap(List<Slot> slots) {
    final orderMap = <String, int>{};
    var globalOrder = 0;
    for (final slot in slots) {
      for (final page in slot.pages.pages) {
        for (final paramNum in page.parameters) {
          final key = '${slot.algorithm.algorithmIndex}_$paramNum';
          orderMap[key] = globalOrder++;
        }
      }
    }
    return orderMap;
  }

  List<MappedParameter> _sortParameters(
    List<MappedParameter> mappedParameters,
    Map<String, int> orderMap,
  ) {
    final sorted = List<MappedParameter>.from(mappedParameters);
    sorted.sort((a, b) {
      final pageA = a.mapping.packedMappingData.perfPageIndex;
      final pageB = b.mapping.packedMappingData.perfPageIndex;
      if (pageA != pageB) return pageA.compareTo(pageB);

      final keyA =
          '${a.parameter.algorithmIndex}_${a.parameter.parameterNumber}';
      final keyB =
          '${b.parameter.algorithmIndex}_${b.parameter.parameterNumber}';
      final orderA = orderMap[keyA] ?? 999999;
      final orderB = orderMap[keyB] ?? 999999;
      return orderA.compareTo(orderB);
    });
    return sorted;
  }

  Color _getPageColor(int pageIndex) {
    return context.appColors.categoricalAt(pageIndex - 1).color;
  }

  Color _getPerfItemColor(int itemIndex) {
    final pageNum = (itemIndex ~/ 3);
    return context.appColors.categoricalAt(pageNum).color;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No performance parameters assigned',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Assign parameters in the property editor',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // --- Legacy (pre-v1.16) callbacks ---

  void _onReorder(
    List<MappedParameter> sortedParams,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final reordered = List<MappedParameter>.from(sortedParams);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    final assignments =
        <({int slotIndex, int parameterNumber, int perfPageIndex})>[];
    for (var i = 0; i < reordered.length; i++) {
      final p = reordered[i];
      final newPerfIndex = i + 1;
      if (p.mapping.packedMappingData.perfPageIndex != newPerfIndex) {
        assignments.add((
          slotIndex: p.parameter.algorithmIndex,
          parameterNumber: p.parameter.parameterNumber,
          perfPageIndex: newPerfIndex,
        ));
      }
    }

    if (assignments.isNotEmpty) {
      context.read<DistingCubit>().reorderPerformanceParameters(assignments);
    }
  }

  void _onRemoveParameter(MappedParameter param) {
    context.read<DistingCubit>().setPerformancePageMapping(
      param.parameter.algorithmIndex,
      param.parameter.parameterNumber,
      0,
    );
  }

  void _onIndexChanged(MappedParameter param, int newIndex) {
    context.read<DistingCubit>().setPerformancePageMapping(
      param.parameter.algorithmIndex,
      param.parameter.parameterNumber,
      newIndex,
    );
  }

  // --- v1.16+ callbacks ---

  void _onRemovePerfItem(PerformancePageItem item) {
    context.read<DistingCubit>().removePerfPageItem(item.itemIndex);
  }

  // --- Legacy (pre-v1.16) list builders ---

  Widget _buildCondensedList(List<MappedParameter> sortedParams) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      buildDefaultDragHandles: false,
      itemCount: sortedParams.length,
      onReorderItem: (oldIndex, newIndex) =>
          _onReorder(sortedParams, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final item = sortedParams[index];
        final perfIndex = item.mapping.packedMappingData.perfPageIndex;
        final pageNum = ((perfIndex - 1) ~/ 3) + 1;

        return ReorderableDragStartListener(
          key: ValueKey(
            'condensed_${item.parameter.algorithmIndex}_${item.parameter.parameterNumber}',
          ),
          index: index,
          child: _ParameterListItem(
            item: item,
            pageColor: _getPageColor(pageNum),
            indexLabel: '$perfIndex',
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              tooltip: 'Remove from performance',
              onPressed: () => _onRemoveParameter(item),
            ),
            leading: const Icon(Icons.drag_handle),
          ),
        );
      },
    );
  }

  Widget _buildAsIndexedList(List<MappedParameter> sortedParams) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sortedParams.length,
      itemBuilder: (context, index) {
        final item = sortedParams[index];
        final perfIndex = item.mapping.packedMappingData.perfPageIndex;
        final pageNum = ((perfIndex - 1) ~/ 3) + 1;

        return _ParameterListItem(
          key: ValueKey(
            'indexed_${item.parameter.algorithmIndex}_${item.parameter.parameterNumber}',
          ),
          item: item,
          pageColor: _getPageColor(pageNum),
          indexLabel: '$perfIndex',
          trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            tooltip: 'Remove from performance',
            onPressed: () => _onRemoveParameter(item),
          ),
          leading: SizedBox(
            width: 56,
            child: DropdownButton<int>(
              value: perfIndex,
              isDense: true,
              isExpanded: true,
              items: List.generate(30, (i) {
                return DropdownMenuItem(value: i + 1, child: Text('${i + 1}'));
              }),
              onChanged: (newValue) {
                if (newValue != null && newValue != perfIndex) {
                  _onIndexChanged(item, newValue);
                }
              },
            ),
          ),
        );
      },
    );
  }

  // --- v1.16+ list builder ---

  Widget _buildPerfItemList(
    List<PerformancePageItem> enabledItems,
    DistingStateSynchronized state,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: enabledItems.length,
      itemBuilder: (context, index) {
        final item = enabledItems[index];

        ParameterInfo? parameterInfo;
        String? unitString;
        if (item.slotIndex < state.slots.length) {
          final slot = state.slots[item.slotIndex];
          if (item.parameterNumber < slot.parameters.length) {
            parameterInfo = slot.parameters[item.parameterNumber];
            unitString = parameterInfo.getUnitString(state.unitStrings);
          }
        }

        return _PerfPageItemListTile(
          key: ValueKey('perf_${item.itemIndex}'),
          item: item,
          pageColor: _getPerfItemColor(item.itemIndex),
          onRemove: () => _onRemovePerfItem(item),
          parameterInfo: parameterInfo,
          unitString: unitString,
        );
      },
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<PerformanceLayoutMode>(
        segments: const [
          ButtonSegment(
            value: PerformanceLayoutMode.condensed,
            label: Text('Condensed'),
            icon: Icon(Icons.reorder),
          ),
          ButtonSegment(
            value: PerformanceLayoutMode.asIndexed,
            label: Text('As Indexed'),
            icon: Icon(Icons.grid_view),
          ),
        ],
        selected: {_layoutMode},
        onSelectionChanged: (selected) {
          setState(() {
            _layoutMode = selected.first;
          });
        },
      ),
    );
  }

  Widget _buildLegacyBody(DistingStateSynchronized state) {
    final mappedParameters = DistingCubit.buildMappedParameterList(state);

    if (mappedParameters.isEmpty) {
      return _buildEmptyState();
    }

    final orderMap = _buildParameterOrderMap(state.slots);
    final sortedParams = _sortParameters(mappedParameters, orderMap);

    final isWide = MediaQuery.of(context).size.width >= 720;

    return Column(
      children: [
        _buildModeToggle(),
        Expanded(
          child: isWide
              ? Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _layoutMode == PerformanceLayoutMode.condensed
                          ? _buildCondensedList(sortedParams)
                          : _buildAsIndexedList(sortedParams),
                    ),
                    const VerticalDivider(width: 1, thickness: 1),
                    Expanded(
                      flex: 2,
                      child: HardwarePreviewWidget(
                        parameters: sortedParams,
                        layoutMode: _layoutMode,
                        slots: state.slots,
                        onParameterChanged:
                            (
                              slotIndex,
                              parameterNumber,
                              value,
                              userIsChanging,
                            ) {
                              context.read<DistingCubit>().updateParameterValue(
                                algorithmIndex: slotIndex,
                                parameterNumber: parameterNumber,
                                value: value,
                                userIsChangingTheValue: userIsChanging,
                              );
                            },
                      ),
                    ),
                  ],
                )
              : _layoutMode == PerformanceLayoutMode.condensed
              ? _buildCondensedList(sortedParams)
              : _buildAsIndexedList(sortedParams),
        ),
      ],
    );
  }

  Widget _buildPerfItemsBody(DistingStateSynchronized state) {
    final enabledItems = state.perfPageItems.where((i) => i.enabled).toList();

    if (enabledItems.isEmpty) {
      return _buildEmptyState();
    }

    final isWide = MediaQuery.of(context).size.width >= 720;

    if (isWide) {
      return Row(
        children: [
          Expanded(flex: 3, child: _buildPerfItemList(enabledItems, state)),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            flex: 2,
            child: HardwarePreviewWidget(
              perfPageItems: enabledItems,
              slots: state.slots,
              onParameterChanged:
                  (slotIndex, parameterNumber, value, userIsChanging) {
                    context.read<DistingCubit>().updateParameterValue(
                      algorithmIndex: slotIndex,
                      parameterNumber: parameterNumber,
                      value: value,
                      userIsChangingTheValue: userIsChanging,
                    );
                  },
            ),
          ),
        ],
      );
    }

    return _buildPerfItemList(enabledItems, state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perform'),
        actions: [
          IconButton(
            icon: Icon(
              _pollingEnabled
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
              semanticLabel: _pollingEnabled ? 'Stop polling' : 'Start polling',
            ),
            tooltip: _pollingEnabled ? 'Stop polling' : 'Start polling',
            onPressed: () {
              setState(() {
                _pollingEnabled = !_pollingEnabled;
              });
              if (_pollingEnabled) {
                context.read<DistingCubit>().startPollingMappedParameters();
              } else {
                context.read<DistingCubit>().stopPollingMappedParameters();
              }
            },
          ),
        ],
      ),
      body: BlocBuilder<DistingCubit, DistingState>(
        builder: (context, state) {
          if (state is DistingStateSynchronized) {
            if (state.firmwareVersion.hasPerfPageItems) {
              return _buildPerfItemsBody(state);
            }
            return _buildLegacyBody(state);
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _ParameterListItem extends StatelessWidget {
  const _ParameterListItem({
    super.key,
    required this.item,
    required this.pageColor,
    required this.indexLabel,
    required this.trailing,
    required this.leading,
  });

  final MappedParameter item;
  final Color pageColor;
  final String indexLabel;
  final Widget trailing;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: pageColor,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                indexLabel,
                style: TextStyle(
                  color: Theme.of(context).appColors
                      .categoricalOnColor(pageColor),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        title: Text(item.parameter.name),
        subtitle: Text(
          item.algorithm.name,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        trailing: trailing,
      ),
    );
  }
}

class _PerfPageItemListTile extends StatefulWidget {
  const _PerfPageItemListTile({
    super.key,
    required this.item,
    required this.pageColor,
    required this.onRemove,
    this.parameterInfo,
    this.unitString,
  });

  final PerformancePageItem item;
  final Color pageColor;
  final VoidCallback onRemove;
  final ParameterInfo? parameterInfo;
  final String? unitString;

  @override
  State<_PerfPageItemListTile> createState() => _PerfPageItemListTileState();
}

class _PerfPageItemListTileState extends State<_PerfPageItemListTile> {
  bool _expanded = false;
  late PerformancePageItem _item;
  late TextEditingController _upperLabelController;
  late TextEditingController _lowerLabelController;

  Timer? _debounceTimer;
  bool _isDirty = false;
  DistingCubit? _cubit;

  DateTime? _lastPreviewSent;
  static const _previewThrottleDuration = Duration(milliseconds: 100);
  static const _debounceDuration = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _upperLabelController = TextEditingController(text: _item.upperLabel);
    _lowerLabelController = TextEditingController(text: _item.lowerLabel);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit = context.read<DistingCubit>();
  }

  @override
  void didUpdateWidget(covariant _PerfPageItemListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item != oldWidget.item && !_isDirty) {
      _item = widget.item;
      if (_upperLabelController.text != _item.upperLabel) {
        _upperLabelController.text = _item.upperLabel;
      }
      if (_lowerLabelController.text != _item.lowerLabel) {
        _lowerLabelController.text = _item.lowerLabel;
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (_isDirty) {
      _performSaveSync();
    }
    _upperLabelController.dispose();
    _lowerLabelController.dispose();
    super.dispose();
  }

  void _performSaveSync() {
    _item = _item.copyWith(
      upperLabel: _upperLabelController.text,
      lowerLabel: _lowerLabelController.text,
    );
    _cubit?.setPerfPageItem(_item);
  }

  void _previewParameterValue(int value) {
    final now = DateTime.now();
    if (_lastPreviewSent == null ||
        now.difference(_lastPreviewSent!) > _previewThrottleDuration) {
      _lastPreviewSent = now;
      _cubit?.updateParameterValue(
        algorithmIndex: _item.slotIndex,
        parameterNumber: _item.parameterNumber,
        value: value,
        userIsChangingTheValue: true,
      );
    }
  }

  void _restoreParameterValue() {
    final cubit = _cubit;
    if (cubit == null) return;
    final state = cubit.state;
    if (state is DistingStateSynchronized) {
      if (_item.slotIndex >= state.slots.length) return;
      final slot = state.slots[_item.slotIndex];
      if (_item.parameterNumber >= slot.values.length) return;
      final currentValue = slot.values[_item.parameterNumber].value;
      cubit.updateParameterValue(
        algorithmIndex: _item.slotIndex,
        parameterNumber: _item.parameterNumber,
        value: currentValue,
        userIsChangingTheValue: false,
      );
    }
  }

  void _onIndexChanged(int newIndex) {
    final cubit = _cubit;
    if (cubit == null) return;
    _debounceTimer?.cancel();
    if (_isDirty) {
      _item = _item.copyWith(
        upperLabel: _upperLabelController.text,
        lowerLabel: _lowerLabelController.text,
      );
      _isDirty = false;
    }
    final oldIndex = _item.itemIndex;
    final movedItem = _item.copyWith(itemIndex: newIndex);
    cubit.removePerfPageItem(oldIndex);
    cubit.setPerfPageItem(movedItem);
  }

  void _triggerOptimisticSave() {
    setState(() {
      _isDirty = true;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      _performSaveSync();
      if (mounted) {
        setState(() {
          _isDirty = false;
        });
      }
    });
  }

  String _formatDisplayValue(double displayValue) {
    final pi = widget.parameterInfo!;
    final decimalPlaces = pi.powerOfTen.abs();
    final formatted = displayValue.toStringAsFixed(decimalPlaces);
    final unit = widget.unitString?.trim();
    if (unit != null && unit.isNotEmpty) {
      return '$formatted $unit';
    }
    return formatted;
  }

  Widget _buildRangeSlider() {
    final pi = widget.parameterInfo!;
    final scale = pow(10, pi.powerOfTen).toDouble();
    var sliderMin = pi.min;
    var sliderMax = pi.max;
    if (sliderMin > sliderMax) {
      final tmp = sliderMin;
      sliderMin = sliderMax;
      sliderMax = tmp;
    }

    if (sliderMin == sliderMax) {
      final displayValue = sliderMin * scale;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'Range: ${_formatDisplayValue(displayValue)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final displayMin = sliderMin * scale;
    final displayMax = sliderMax * scale;

    var clampedMin = _item.min.clamp(sliderMin, sliderMax);
    var clampedMax = _item.max.clamp(sliderMin, sliderMax);
    if (clampedMin > clampedMax) {
      final tmp = clampedMin;
      clampedMin = clampedMax;
      clampedMax = tmp;
    }
    final displayStart = clampedMin * scale;
    final displayEnd = clampedMax * scale;

    final divisions = sliderMax - sliderMin;

    return Column(
      children: [
        RangeSlider(
          values: RangeValues(displayStart, displayEnd),
          min: displayMin,
          max: displayMax,
          divisions: divisions,
          labels: RangeLabels(
            _formatDisplayValue(displayStart),
            _formatDisplayValue(displayEnd),
          ),
          semanticFormatterCallback: (value) => _formatDisplayValue(value),
          onChanged: (RangeValues values) {
            final rawMin = (values.start / scale).round();
            final rawMax = (values.end / scale).round();
            final previousMin = _item.min;
            setState(() {
              _item = _item.copyWith(min: rawMin, max: rawMax);
            });
            _triggerOptimisticSave();

            final previewValue = (rawMin != previousMin) ? rawMin : rawMax;
            _previewParameterValue(previewValue);
          },
          onChangeEnd: (RangeValues values) {
            _restoreParameterValue();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Min: ${_formatDisplayValue(displayStart)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Max: ${_formatDisplayValue(displayEnd)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            onTap: widget.parameterInfo != null
                ? () => setState(() => _expanded = !_expanded)
                : null,
            leading: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.pageColor,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '${widget.item.itemIndex + 1}',
                style: TextStyle(
                  color: Theme.of(context).appColors
                      .categoricalOnColor(widget.pageColor),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              _item.upperLabel.isNotEmpty
                  ? _item.upperLabel
                  : 'Item ${_item.itemIndex + 1}',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_item.lowerLabel.isNotEmpty)
                  Text(
                    _item.lowerLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  'Slot ${_item.slotIndex + 1}, Param ${_item.parameterNumber}  '
                  'Range: ${_item.min}..${_item.max}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.parameterInfo != null)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  tooltip: 'Remove from performance',
                  onPressed: widget.onRemove,
                ),
              ],
            ),
          ),
          if (_expanded && widget.parameterInfo != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Index',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('perf_idx_${_item.itemIndex}'),
                          initialValue: _item.itemIndex + 1,
                          isDense: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          items: List.generate(30, (i) {
                            return DropdownMenuItem(
                              value: i + 1,
                              child: Text('${i + 1}'),
                            );
                          }),
                          onChanged: (newValue) {
                            if (newValue != null &&
                                newValue - 1 != _item.itemIndex) {
                              _onIndexChanged(newValue - 1);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Range', style: Theme.of(context).textTheme.labelLarge),
                  _buildRangeSlider(),
                  const SizedBox(height: 12),
                  DigitShortcutBlocker(
                    child: TextField(
                      controller: _upperLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Upper Label',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _triggerOptimisticSave(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DigitShortcutBlocker(
                    child: TextField(
                      controller: _lowerLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Lower Label',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _triggerOptimisticSave(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
