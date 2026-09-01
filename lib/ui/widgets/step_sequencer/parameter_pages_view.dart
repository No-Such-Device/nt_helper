import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/parameter_editor_view.dart';
import 'package:nt_helper/ui/widgets/parameter_value_edit_traversal_scope.dart';
import 'package:nt_helper/util/parameter_page_assigner.dart';

/// Parameter Pages view for Step Sequencer
///
/// Displays parameters not covered by the custom Step Sequencer UI,
/// organized into logical pages (MIDI, Routing, Modulation, Global).
///
/// Uses tab-based navigation and reusable parameter editor widgets.
class ParameterPagesView extends StatefulWidget {
  final Slot slot;
  final int slotIndex;

  const ParameterPagesView({
    super.key,
    required this.slot,
    required this.slotIndex,
  });

  @override
  State<ParameterPagesView> createState() => _ParameterPagesViewState();
}

class _ParameterPagesViewState extends State<ParameterPagesView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<ParameterPage> _availableFirmwarePages;

  @override
  void initState() {
    super.initState();
    _initializePages();
  }

  /// Initialize pages using firmware-provided page structure
  ///
  /// Filters out parameters that are handled by custom Step Sequencer UI
  void _initializePages() {
    // Get the firmware-provided pages
    final firmwarePages = widget.slot.pages.pages;

    // Build the set of custom UI parameters from all slot parameters
    ParameterPageAssigner.buildCustomUISet(widget.slot.parameters);

    // Parameters handled by custom Step Sequencer UI (to exclude)
    final customUIParameters =
        ParameterPageAssigner.getStepSequencerCustomUIParameters();

    // Filter firmware pages to only include parameters not in custom UI
    _availableFirmwarePages = firmwarePages
        .map((page) {
          final filteredParams = page.parameters
              .where((paramNum) => !customUIParameters.contains(paramNum))
              .toList();
          return ParameterPage(name: page.name, parameters: filteredParams);
        })
        .where((page) => page.parameters.isNotEmpty)
        .toList();

    // Initialize tab controller with number of available pages
    _tabController = TabController(
      length: _availableFirmwarePages.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    // Handle case where no parameters are available for pages
    if (_availableFirmwarePages.isEmpty) {
      return _buildEmptyState(context, isMobile);
    }

    // Build the parameter pages view
    return _buildParameterPagesView(context, isMobile);
  }

  /// Builds the main parameter pages view with tabs
  Widget _buildParameterPagesView(BuildContext context, bool isMobile) {
    if (isMobile) {
      // Mobile: Full-screen view
      return Scaffold(
        appBar: AppBar(
          title: const Text('Parameter Pages'),
          leading: IconButton(
            icon: const Icon(
              Icons.close,
              semanticLabel: 'Close parameter pages',
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _availableFirmwarePages.map((page) {
              return Tab(text: page.name);
            }).toList(),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: _availableFirmwarePages.map((page) {
            return _ParameterPageContent(
              parameterNumbers: page.parameters,
              slot: widget.slot,
              slotIndex: widget.slotIndex,
            );
          }).toList(),
        ),
      );
    } else {
      // Desktop: Large modal dialog
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Parameter Pages'),
              leading: IconButton(
                icon: const Icon(
                  Icons.close,
                  semanticLabel: 'Close parameter pages',
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              bottom: TabBar(
                controller: _tabController,
                isScrollable: false,
                tabs: _availableFirmwarePages.map((page) {
                  return Tab(text: page.name);
                }).toList(),
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: _availableFirmwarePages.map((page) {
                return _ParameterPageContent(
                  parameterNumbers: page.parameters,
                  slot: widget.slot,
                  slotIndex: widget.slotIndex,
                );
              }).toList(),
            ),
          ),
        ),
      );
    }
  }

  /// Builds the empty state when no parameters are available
  Widget _buildEmptyState(BuildContext context, bool isMobile) {
    final content = Scaffold(
      appBar: AppBar(
        title: const Text('Parameter Pages'),
        leading: IconButton(
          icon: const Icon(Icons.close, semanticLabel: 'Close parameter pages'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: context.appColors.success.color,
              ),
              const SizedBox(height: 16),
              const Text(
                'All parameters have custom UI',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'All Step Sequencer parameters are accessible through the custom interface.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Return to Step Sequencer'),
              ),
            ],
          ),
        ),
      ),
    );

    if (isMobile) {
      return content;
    } else {
      // Desktop: dialog wrapper
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
          child: content,
        ),
      );
    }
  }
}

/// Content widget for a single parameter page
///
/// Displays a scrollable list of familiar parameter editors for the given parameters.
class _ParameterPageContent extends StatelessWidget {
  final List<int> parameterNumbers;
  final Slot slot;
  final int slotIndex;

  const _ParameterPageContent({
    required this.parameterNumbers,
    required this.slot,
    required this.slotIndex,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DistingCubit, DistingState>(
      builder: (context, state) {
        // Get current slot and unit strings to refresh parameter values
        final data = state.maybeWhen(
          synchronized:
              (
                disting,
                distingVersion,
                firmwareVersion,
                deviceIoProfile,
                presetName,
                algorithms,
                slots,
                unitStrings,
                inputDevice,
                outputDevice,
                loading,
                offline,
                screenshot,
                demo,
                videoStream,
                availableFirmwareUpdate,
                perfPageItems,
                isDirty,
                renameConfirmationName,
              ) {
                final currentSlot = slotIndex < slots.length
                    ? slots[slotIndex]
                    : slot;
                return (currentSlot, unitStrings);
              },
          orElse: () => (slot, <String>[]),
        );

        final currentSlot = data.$1;
        final unitStrings = data.$2;

        // Use the familiar parameter editor UI
        return ParameterValueEditTraversalScope(
          child: ListView.builder(
            // ignore: deprecated_member_use
            cacheExtent: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            itemCount: parameterNumbers.length,
            itemBuilder: (context, index) {
              final paramNum = parameterNumbers[index];
              final parameter = currentSlot.parameters.elementAtOrNull(
                paramNum,
              );

              // Use safe access with bounds checking (like ParameterListView does)
              final value = currentSlot.values.elementAtOrNull(paramNum);
              final enumStrings = currentSlot.enums.elementAtOrNull(paramNum);
              final mapping = currentSlot.mappings.elementAtOrNull(paramNum);
              final valueString = currentSlot.valueStrings.elementAtOrNull(
                paramNum,
              );

              // Skip if we don't have essential data
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
              final unit = shouldShowUnit
                  ? parameter.getUnitString(unitStrings)
                  : null;

              // Use the familiar ParameterEditorView widget
              return ParameterEditorView(
                slot: currentSlot,
                parameterInfo: parameter,
                value: value,
                enumStrings: safeEnumStrings,
                mapping: mapping,
                valueString: safeValueString,
                unit: unit,
                parameterValueTraversalId:
                    'step-sequencer-$slotIndex-$paramNum',
                parameterValueTraversalOrder: index.toDouble(),
              );
            },
          ),
        );
      },
    );
  }
}
