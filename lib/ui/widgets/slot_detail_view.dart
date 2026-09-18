import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:nt_helper/algorithm_controller/algorithm_controller.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/ui/algorithm_registry.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/algorithm_controller_section_controller.dart';
import 'package:nt_helper/ui/widgets/algorithm_controller/lua_algorithm_controller_view.dart';
import 'package:nt_helper/ui/widgets/section_parameter_controller.dart';
import 'package:nt_helper/ui/widgets/section_parameter_list_view.dart';
import 'package:nt_helper/ui/widgets/slot_bypass_control.dart';
import 'package:nt_helper/ui/widgets/slot_editor_action_bar.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode.dart';
import 'package:nt_helper/ui/widgets/slot_editor_mode_selector.dart';

/// Presents the current slot snapshot supplied by [DistingStateSynchronized].
///
/// In particular, a post-respecification rebuild renders the returned
/// parameters, mappings, and routing as supplied. This view does not merge
/// them with the pre-respecification slot or infer parameter identity from an
/// old index.
class SlotDetailView extends StatefulWidget {
  final Slot slot;
  final int slotIndex;
  final List<String> units;
  final FirmwareVersion firmwareVersion;
  final SectionParameterController? sectionController;
  final AlgorithmControllerSectionController algorithmControllerSections;
  final SlotEditorMode editorMode;
  final ValueChanged<SlotEditorMode> onEditorModeChanged;
  final bool editorModeEnabled;

  const SlotDetailView({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.units,
    required this.firmwareVersion,
    required this.algorithmControllerSections,
    required this.editorMode,
    required this.onEditorModeChanged,
    this.sectionController,
    this.editorModeEnabled = true,
  });

  @override
  State<SlotDetailView> createState() => _SlotDetailViewState();
}

class _SlotDetailViewState extends State<SlotDetailView>
    with AutomaticKeepAliveClientMixin {
  StreamSubscription<({int slotIndex, int pageIndex})>? _sectionControllerSub;
  late final FocusNode _bypassFocusNode = FocusNode(
    debugLabel: 'SlotDetailView.bypass',
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.algorithmControllerSections.addListener(
      _handleControllerSectionsChanged,
    );
    _subscribeSectionController();
  }

  @override
  void didUpdateWidget(covariant SlotDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.algorithmControllerSections !=
        widget.algorithmControllerSections) {
      oldWidget.algorithmControllerSections.removeListener(
        _handleControllerSectionsChanged,
      );
      widget.algorithmControllerSections.addListener(
        _handleControllerSectionsChanged,
      );
    }
    if (oldWidget.sectionController != widget.sectionController) {
      _subscribeSectionController();
    }
  }

  @override
  void dispose() {
    _sectionControllerSub?.cancel();
    _bypassFocusNode.dispose();
    widget.algorithmControllerSections.removeListener(
      _handleControllerSectionsChanged,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final definition = AlgorithmControllerRegistry.bundled.findForGuid(
      widget.slot.algorithm.guid,
    );
    final mode =
        widget.editorMode == SlotEditorMode.controller && definition == null
        ? SlotEditorMode.standard
        : widget.editorMode;
    final modeSelector = SlotEditorModeSelector(
      mode: mode,
      controllerName: definition?.name,
      enabled: widget.editorModeEnabled,
      onSelected: (selectedMode) => _selectMode(selectedMode, definition),
    );

    if (mode == SlotEditorMode.controller && definition != null) {
      return SafeArea(
        child: Column(
          children: [
            SlotEditorActionBar(
              slot: widget.slot,
              editorModeSelector: modeSelector,
              sectionsCollapsed:
                  widget.algorithmControllerSections.sectionsCollapsed,
              onToggleSections: _toggleControllerSections,
              bypassFocusNode: _bypassFocusNode,
            ),
            Expanded(
              child: LuaAlgorithmControllerView(
                definition: definition,
                slot: widget.slot,
                slotIndex: widget.slotIndex,
                units: widget.units,
                sectionController: widget.algorithmControllerSections,
                onError: _handleControllerError,
              ),
            ),
          ],
        ),
      );
    }

    if (mode == SlotEditorMode.standard) {
      final view = AlgorithmViewRegistry.findViewFor(
        widget.slot,
        widget.slotIndex,
        widget.firmwareVersion,
      );
      if (view != null) {
        return SafeArea(
          child: Column(
            children: [
              SlotEditorActionBar(
                slot: widget.slot,
                editorModeSelector: modeSelector,
                sectionsCollapsed: false,
                bypassFocusNode: _bypassFocusNode,
              ),
              Expanded(child: view),
            ],
          ),
        );
      }
    }

    // Create a set of list sections for the parameters of the
    // algorithm initially based off Os' organization on the module firmware.

    return SafeArea(
      child: SectionParameterListView(
        slot: widget.slot,
        slotIndex: widget.slotIndex,
        units: widget.units,
        pages: widget.slot.pages,
        sectionController: widget.sectionController,
        spreadsheetEditingMode: mode == SlotEditorMode.spreadsheet,
        editorModeSelector: modeSelector,
        bypassFocusNode: _bypassFocusNode,
      ),
    );
  }

  void _toggleControllerSections() {
    widget.algorithmControllerSections.toggleAll();
    SemanticsService.sendAnnouncement(
      View.of(context),
      widget.algorithmControllerSections.sectionsCollapsed
          ? 'All controller sections collapsed'
          : 'All controller sections expanded',
      TextDirection.ltr,
    );
  }

  void _subscribeSectionController() {
    _sectionControllerSub?.cancel();
    _sectionControllerSub = widget.sectionController?.stream.listen((event) {
      if (!mounted || event.slotIndex != widget.slotIndex) {
        return;
      }
      if (widget.editorMode == SlotEditorMode.controller &&
          AlgorithmControllerRegistry.bundled.findForGuid(
                widget.slot.algorithm.guid,
              ) !=
              null) {
        final title = widget.algorithmControllerSections.showOnlySection(
          event.pageIndex,
        );
        if (title == null) return;
        SemanticsService.sendAnnouncement(
          View.of(context),
          '$title controller section expanded',
          Directionality.of(context),
        );
        return;
      }

      if (isBypassOnlyPage(widget.slot, event.pageIndex)) {
        _bypassFocusNode.requestFocus();
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Bypass control focused',
          Directionality.of(context),
        );
        return;
      }
    });
  }

  void _handleControllerSectionsChanged() {
    if (mounted) setState(() {});
  }

  void _selectMode(
    SlotEditorMode mode,
    AlgorithmControllerDefinition? definition,
  ) {
    if (!widget.editorModeEnabled ||
        mode == widget.editorMode ||
        mode == SlotEditorMode.controller && definition == null) {
      return;
    }
    widget.onEditorModeChanged(mode);
  }

  void _handleControllerError(String message) {
    if (!mounted || widget.editorMode != SlotEditorMode.controller) return;
    widget.onEditorModeChanged(SlotEditorMode.standard);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message. Returned to the standard editor.')),
    );
  }
}
