import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/parameter_editor_view.dart';
import 'package:nt_helper/ui/widgets/parameter_spreadsheet_view.dart';
import 'package:nt_helper/ui/widgets/parameter_value_edit_traversal_scope.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/ui/widgets/slot_bypass_control.dart';
import 'package:nt_helper/ui/widgets/slot_editor_action_bar.dart';

class SectionParameterListView extends StatefulWidget {
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final ParameterPages pages;
  final SectionParameterController? sectionController;
  final bool spreadsheetEditingMode;
  final Widget? editorModeSelector;
  final FocusNode? bypassFocusNode;

  const SectionParameterListView({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.pages,
    this.sectionController,
    this.spreadsheetEditingMode = false,
    this.editorModeSelector,
    this.bypassFocusNode,
  });

  @override
  State<SectionParameterListView> createState() =>
      _SectionParameterListViewState();
}

class _SectionParameterListViewState extends State<SectionParameterListView> {
  late List<ExpansibleController> _tileControllers;
  late bool _isCollapsed;
  // Track optimistic performance page assignments for immediate UI updates
  final Map<int, int> _optimisticPerfPageAssignments = {};
  StreamSubscription<({int slotIndex, int pageIndex})>? _sectionControllerSub;

  @override
  void initState() {
    super.initState();
    _tileControllers = List.generate(
      widget.pages.pages.length,
      (_) => ExpansibleController(),
    );
    _isCollapsed = SettingsService().startPagesCollapsed;
    _subscribeSectionController();
  }

  void _subscribeSectionController() {
    _sectionControllerSub?.cancel();
    _sectionControllerSub = widget.sectionController?.stream.listen((event) {
      if (event.slotIndex != widget.slotIndex) return;
      final pageIndex = event.pageIndex;
      if (isBypassOnlyPage(widget.slot, pageIndex)) return;
      if (pageIndex >= 0 && pageIndex < _tileControllers.length) {
        for (int i = 0; i < _tileControllers.length; i++) {
          if (i == pageIndex) {
            _tileControllers[i].expand();
          } else {
            _tileControllers[i].collapse();
          }
        }
        setState(() {
          _isCollapsed = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sectionControllerSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(SectionParameterListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear optimistic assignments when slot changes (state has been updated)
    if (oldWidget.slot != widget.slot) {
      _optimisticPerfPageAssignments.clear();
    }

    if (oldWidget.sectionController != widget.sectionController) {
      _subscribeSectionController();
    }

    // Rebuild tile controllers if page count changed (e.g., Lua script program change)
    if (oldWidget.pages.pages.length != widget.pages.pages.length) {
      // Dispose old controllers
      for (var controller in _tileControllers) {
        controller.dispose();
      }
      // Create new controllers matching new page count and current collapse state
      _tileControllers = List.generate(widget.pages.pages.length, (_) {
        final controller = ExpansibleController();
        // Match current collapse state
        if (_isCollapsed) {
          controller.collapse();
        } else {
          controller.expand();
        }
        return controller;
      });
    }
  }

  void _collapseAllTiles() {
    for (var element in _tileControllers) {
      _isCollapsed ? element.expand() : element.collapse();
    }
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  bool get _usePerfPageItems {
    final state = context.read<DistingCubit>().state;
    if (state is! DistingStateSynchronized) return false;
    return state.firmwareVersion.hasPerfPageItems;
  }

  int _findPerfItemDisplayIndex(
    List<PerformancePageItem> items,
    int slotIndex,
    int paramNumber,
  ) {
    for (final item in items) {
      if (item.enabled &&
          item.slotIndex == slotIndex &&
          item.parameterNumber == paramNumber) {
        return item.itemIndex + 1;
      }
    }
    return 0;
  }

  PerformancePageItem? _findPerfItem(
    List<PerformancePageItem> items,
    int slotIndex,
    int paramNumber,
  ) {
    for (final item in items) {
      if (item.enabled &&
          item.slotIndex == slotIndex &&
          item.parameterNumber == paramNumber) {
        return item;
      }
    }
    return null;
  }

  // Get list of parameter indices that have performance page assignments
  List<int> _getPerformanceParameterIndices() {
    final state = context.read<DistingCubit>().state;
    if (state is! DistingStateSynchronized) return [];

    if (state.firmwareVersion.hasPerfPageItems) {
      final perfParams = <int>[];
      for (final item in state.perfPageItems) {
        if (item.enabled && item.slotIndex == widget.slotIndex) {
          perfParams.add(item.parameterNumber);
        }
      }
      perfParams.sort((a, b) {
        final itemA = _findPerfItem(state.perfPageItems, widget.slotIndex, a);
        final itemB = _findPerfItem(state.perfPageItems, widget.slotIndex, b);
        final indexCompare = (itemA?.itemIndex ?? 0).compareTo(
          itemB?.itemIndex ?? 0,
        );
        if (indexCompare != 0) return indexCompare;
        return a.compareTo(b);
      });
      return perfParams;
    }

    final perfParams = <int>[];
    for (int i = 0; i < widget.slot.mappings.length; i++) {
      final mapping = widget.slot.mappings[i];
      if (mapping.packedMappingData.perfPageIndex > 0) {
        perfParams.add(i);
      }
    }
    perfParams.sort((a, b) {
      final mappingA = widget.slot.mappings[a];
      final mappingB = widget.slot.mappings[b];
      final pageCompare = mappingA.packedMappingData.perfPageIndex.compareTo(
        mappingB.packedMappingData.perfPageIndex,
      );
      if (pageCompare != 0) return pageCompare;
      return a.compareTo(b);
    });
    return perfParams;
  }

  Widget _buildPageBadge(int pageIndex) {
    final colors = context.appColors.categoricalAt(pageIndex - 1);

    return Semantics(
      label: 'Performance page $pageIndex',
      child: Chip(
        label: Text('P$pageIndex'),
        backgroundColor: colors.color,
        labelStyle: TextStyle(
          color: colors.onColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // Build performance parameter row
  Widget _buildPerformanceParameterRow(
    int parameterNumber, {
    PerformancePageItem? perfItem,
    required double traversalOrder,
  }) {
    final value = widget.slot.values.elementAtOrNull(parameterNumber);
    final enumStrings = widget.slot.enums.elementAtOrNull(parameterNumber);
    final mapping = widget.slot.mappings.elementAtOrNull(parameterNumber);
    final valueString = widget.slot.valueStrings.elementAtOrNull(
      parameterNumber,
    );
    final parameterInfo = widget.slot.parameters.elementAtOrNull(
      parameterNumber,
    );

    // Skip if missing essential data
    if (value == null || parameterInfo == null || mapping == null) {
      return const SizedBox.shrink();
    }

    final safeEnumStrings = enumStrings ?? ParameterEnumStrings.filler();
    final safeValueString = valueString ?? ParameterValueString.filler();
    final shouldShowUnit = !ParameterEditorRegistry.isStringTypeUnit(
      parameterInfo.unit,
    );
    final unit = shouldShowUnit
        ? parameterInfo.getUnitString(widget.units)
        : null;

    final int badgeIndex;
    if (perfItem != null) {
      badgeIndex = perfItem.itemIndex + 1;
    } else {
      badgeIndex = mapping.packedMappingData.perfPageIndex;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          _buildPageBadge(badgeIndex),
          const SizedBox(width: 12),
          Expanded(
            child: ParameterEditorView(
              slot: widget.slot,
              parameterInfo: parameterInfo,
              value: value,
              enumStrings: safeEnumStrings,
              mapping: mapping,
              valueString: safeValueString,
              unit: unit,
              parameterValueTraversalId:
                  'performance-${widget.slotIndex}-$parameterNumber',
              parameterValueTraversalOrder: traversalOrder,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              semanticLabel: 'Remove from performance page',
            ),
            tooltip: 'Remove from performance page',
            onPressed: () => _removeFromPerformancePage(parameterNumber),
          ),
        ],
      ),
    );
  }

  // Remove parameter from performance page
  Future<void> _removeFromPerformancePage(int parameterNumber) async {
    final cubit = context.read<DistingCubit>();
    try {
      if (_usePerfPageItems) {
        final state = cubit.state;
        if (state is! DistingStateSynchronized) return;
        final item = _findPerfItem(
          state.perfPageItems,
          widget.slotIndex,
          parameterNumber,
        );
        if (item != null) {
          await cubit.removePerfPageItem(item.itemIndex);
        }
      } else {
        await cubit.setPerformancePageMapping(
          widget.slot.algorithm.algorithmIndex,
          parameterNumber,
          0,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from performance page'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Intentionally empty
    }
  }

  // Assign parameter to performance page
  Future<void> _assignToPerformancePage(
    int parameterNumber,
    int pageIndex,
  ) async {
    final cubit = context.read<DistingCubit>();

    if (_usePerfPageItems) {
      final state = cubit.state;
      if (state is! DistingStateSynchronized) return;

      final oldItem = _findPerfItem(
        state.perfPageItems,
        widget.slotIndex,
        parameterNumber,
      );

      if (pageIndex == 0) {
        if (oldItem != null) {
          cubit.removePerfPageItem(oldItem.itemIndex);
        }
      } else {
        if (oldItem != null) {
          cubit.removePerfPageItem(oldItem.itemIndex);
        }
        final paramInfo = widget.slot.parameters[parameterNumber];
        cubit.setPerfPageItem(
          PerformancePageItem(
            itemIndex: pageIndex - 1,
            enabled: true,
            slotIndex: widget.slotIndex,
            parameterNumber: parameterNumber,
            min: paramInfo.min,
            max: paramInfo.max,
            upperLabel: widget.slot.algorithm.name,
            lowerLabel: paramInfo.name,
          ),
        );
      }
      return;
    }

    // Legacy path
    setState(() {
      _optimisticPerfPageAssignments[parameterNumber] = pageIndex;
    });

    try {
      await cubit.setPerformancePageMapping(
        widget.slot.algorithm.algorithmIndex,
        parameterNumber,
        pageIndex,
      );
      if (mounted) {
        final manager = cubit.disting();
        final isConnectedMode = manager is DistingMidiManager;
        if (isConnectedMode) {
          final message = pageIndex > 0
              ? 'Assigned to Page $pageIndex'
              : 'Removed from performance pages';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticPerfPageAssignments.remove(parameterNumber);
        });
      }
    }
  }

  // Build parameter row with performance page selector
  Widget _buildParameterRowWithPageSelector({
    required int parameterNumber,
    required ParameterInfo parameterInfo,
    required ParameterValue value,
    required ParameterEnumStrings enumStrings,
    required Mapping? mapping,
    required ParameterValueString valueString,
    required String? unit,
  }) {
    final int perfPageIndex;
    if (_usePerfPageItems) {
      final state = context.read<DistingCubit>().state;
      if (state is DistingStateSynchronized) {
        perfPageIndex = _findPerfItemDisplayIndex(
          state.perfPageItems,
          widget.slotIndex,
          parameterNumber,
        );
      } else {
        perfPageIndex = 0;
      }
    } else {
      final actualPerfPageIndex = mapping?.packedMappingData.perfPageIndex ?? 0;
      perfPageIndex =
          _optimisticPerfPageAssignments[parameterNumber] ??
          actualPerfPageIndex;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ParameterEditorView(
              slot: widget.slot,
              parameterInfo: parameterInfo,
              value: value,
              enumStrings: enumStrings,
              mapping: mapping,
              valueString: valueString,
              unit: unit,
              parameterValueTraversalId:
                  'parameter-${widget.slotIndex}-$parameterNumber',
              parameterValueTraversalOrder: _parameterTraversalOrder(
                parameterNumber,
              ),
            ),
          ),
          if (MediaQuery.of(context).size.width >= 600) ...[
            const SizedBox(width: 8),
            Semantics(
              label: _usePerfPageItems
                  ? 'Assign to performance index'
                  : 'Assign to performance page',
              child: DropdownButton<int>(
                value: perfPageIndex,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 11),
                hint: Text(_usePerfPageItems ? 'Index' : 'Page'),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onChanged: (newValue) {
                  if (newValue != null) {
                    _assignToPerformancePage(parameterNumber, newValue);
                  }
                },
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Not Assigned')),
                  ...List.generate(30, (i) {
                    return DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        _usePerfPageItems ? 'Index ${i + 1}' : 'Page ${i + 1}',
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Build performance parameters section
  Widget _buildPerformanceParametersSection() {
    final perfParams = _getPerformanceParameterIndices();
    final isEmpty = perfParams.isEmpty;

    final state = context.read<DistingCubit>().state;
    final syncState =
        state is DistingStateSynchronized &&
            state.firmwareVersion.hasPerfPageItems
        ? state
        : null;

    return _HeaderShadedExpansionTile(
      initiallyExpanded: !isEmpty,
      title: Text(
        'Performance Parameters (${perfParams.length})',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      children: isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No parameters assigned to performance pages',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ]
          : [
              for (int i = 0; i < perfParams.length; i++)
                _buildPerformanceParameterRow(
                  perfParams[i],
                  perfItem: syncState != null
                      ? _findPerfItem(
                          syncState.perfPageItems,
                          widget.slotIndex,
                          perfParams[i],
                        )
                      : null,
                  traversalOrder: i.toDouble(),
                ),
            ],
    );
  }

  double _parameterTraversalOrder(int parameterNumber) {
    for (
      int pageIndex = 0;
      pageIndex < widget.pages.pages.length;
      pageIndex++
    ) {
      final parameters = widget.pages.pages[pageIndex].parameters;
      final parameterIndex = parameters.indexOf(parameterNumber);
      if (parameterIndex >= 0) {
        return 10000 + pageIndex * 1000 + parameterIndex.toDouble();
      }
    }
    return 10000 + parameterNumber.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return ParameterValueEditTraversalScope(
      child: ListTileTheme(
        data: ListTileThemeData(
          titleTextStyle: Theme.of(context).textTheme.titleLarge,
        ),
        child: ExpansionTileTheme(
          data: const ExpansionTileThemeData(
            shape: RoundedRectangleBorder(side: BorderSide.none),
          ),
          child: Column(
            children: [
              _buildActionRow(),
              Expanded(
                child: widget.spreadsheetEditingMode
                    ? ParameterSpreadsheetView(
                        slot: widget.slot,
                        slotIndex: widget.slotIndex,
                        units: widget.units,
                        pages: widget.pages,
                      )
                    : _buildParameterSectionList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return SlotEditorActionBar(
      slot: widget.slot,
      editorModeSelector: widget.editorModeSelector,
      sectionsCollapsed: _isCollapsed,
      onToggleSections: widget.spreadsheetEditingMode
          ? null
          : _collapseAllTiles,
      bypassFocusNode: widget.bypassFocusNode,
    );
  }

  Widget _buildParameterSectionList() {
    return ListView(
      children: [
        // Performance Parameters Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: _buildPerformanceParametersSection(),
        ),
        // Regular parameter pages
        ...widget.pages.pages.indexed
            .map((entry) => _buildRegularParameterPage(entry.$1, entry.$2))
            .whereType<Widget>(),
        const SizedBox(height: 24), // Bottom padding
      ],
    );
  }

  Widget? _buildRegularParameterPage(int index, ParameterPage page) {
    final parameterNumbers = page.parameters
        .where(
          (parameterNumber) =>
              !isUniversalBypassParameter(widget.slot, parameterNumber),
        )
        .toList();
    if (parameterNumbers.isEmpty) return null;

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: _HeaderShadedExpansionTile(
        initiallyExpanded: !_isCollapsed,
        controller: _tileControllers.elementAt(index),
        title: Text(page.name),
        children: parameterNumbers.map((parameterNumber) {
          // Use safe access with bounds checking
          final value = widget.slot.values.elementAtOrNull(parameterNumber);
          final enumStrings = widget.slot.enums.elementAtOrNull(
            parameterNumber,
          );
          final mapping = widget.slot.mappings.elementAtOrNull(parameterNumber);
          final valueString = widget.slot.valueStrings.elementAtOrNull(
            parameterNumber,
          );
          var parameterInfo = widget.slot.parameters.elementAtOrNull(
            parameterNumber,
          );

          // Skip this parameter if we don't have essential data
          // Note: valueString and enumStrings can be empty/filler for many parameters
          if (value == null || parameterInfo == null) {
            return const SizedBox.shrink();
          }

          // Use filler/empty data if not available
          final safeEnumStrings = enumStrings ?? ParameterEnumStrings.filler();
          final safeValueString = valueString ?? ParameterValueString.filler();

          // For string-type parameters, don't show unit
          final shouldShowUnit = !ParameterEditorRegistry.isStringTypeUnit(
            parameterInfo.unit,
          );
          final unit = shouldShowUnit
              ? parameterInfo.getUnitString(widget.units)
              : null;

          return _buildParameterRowWithPageSelector(
            parameterNumber: parameterNumber,
            parameterInfo: parameterInfo,
            value: value,
            enumStrings: safeEnumStrings,
            mapping: mapping,
            valueString: safeValueString,
            unit: unit,
          );
        }).toList(),
      ),
    );
  }
}

/// Paints only the [ExpansionTile] header while preserving the inherited
/// [ListTileTheme] for every body child.
///
/// Flutter renders an ExpansionTile header as a ListTile, while the tile's
/// backgroundColor is painted behind both its header and expanded body. A
/// locally merged ListTile tileColor therefore provides the header-only paint.
class _HeaderShadedExpansionTile extends StatelessWidget {
  const _HeaderShadedExpansionTile({
    required this.title,
    required this.children,
    required this.initiallyExpanded,
    this.controller,
  });

  final Widget title;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ExpansibleController? controller;

  @override
  Widget build(BuildContext context) {
    final inheritedListTileTheme = ListTileTheme.of(context);
    final headerListTileTheme = inheritedListTileTheme.copyWith(
      tileColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.10),
    );

    return ListTileTheme(
      data: headerListTileTheme,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        controller: controller,
        title: title,
        children: [
          for (final child in children)
            ListTileTheme(data: inheritedListTileTheme, child: child),
        ],
      ),
    );
  }
}
