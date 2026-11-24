import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/scale_quantizer.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_column_widget.dart';
import 'package:nt_helper/util/parameter_write_debouncer.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_sequencer_edit_scope.dart';

/// Grid view displaying all 16 steps of the step sequencer
///
/// Responsive layout:
/// - Desktop (> 768px): GridView showing all 16 steps
/// - Mobile (≤ 768px): Horizontal scrolling ListView
///
/// Supports drag-to-paint: drag across steps to paint values based on Y position
class StepGridView extends StatefulWidget {
  final Slot slot;
  final int slotIndex;
  final bool snapEnabled;
  final String selectedScale;
  final int rootNote;
  final StepParameter activeParameter; // Global parameter mode

  const StepGridView({
    super.key,
    required this.slot,
    required this.slotIndex,
    required this.snapEnabled,
    required this.selectedScale,
    required this.rootNote,
    required this.activeParameter,
  });

  @override
  State<StepGridView> createState() => _StepGridViewState();
}

class _StepGridViewState extends State<StepGridView> {
  bool _isDragging = false;
  int? _lastPaintedStep;
  final _debouncer = ParameterWriteDebouncer();
  final _rowKey = GlobalKey(); // Key to get Row's position
  late List<FocusNode> _stepFocusNodes;
  int _focusedStepIndex = -1;

  @override
  void initState() {
    super.initState();
    _stepFocusNodes = List.generate(16, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(StepGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeParameter != widget.activeParameter) {
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Now editing ${widget.activeParameter.name} for all steps',
        TextDirection.ltr,
      );
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    for (final node in _stepFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 768;

    // Use BlocBuilder to rebuild when parameter values change
    return BlocBuilder<DistingCubit, DistingState>(
      buildWhen: (prev, curr) {
        // Only rebuild when this slot's parameter values change
        if (curr is! DistingStateSynchronized) return false;
        if (prev is! DistingStateSynchronized) return true;
        if (widget.slotIndex < 0 ||
            widget.slotIndex >= curr.slots.length ||
            widget.slotIndex >= prev.slots.length) {
          return true;
        }

        return prev.slots[widget.slotIndex].values !=
            curr.slots[widget.slotIndex].values;
      },
      builder: (context, state) {
        if (state is! DistingStateSynchronized) {
          return const Center(child: CircularProgressIndicator());
        }
        if (widget.slotIndex < 0 || widget.slotIndex >= state.slots.length) {
          return const SizedBox.shrink();
        }

        final currentSlot = state.slots[widget.slotIndex];
        final params = StepSequencerParams.fromSlot(currentSlot);

        return isMobile
            ? _buildHorizontalScrollGrid(context, currentSlot, params)
            : _buildFullGrid(context, currentSlot, params);
      },
    );
  }

  /// Build horizontal scrolling grid for mobile
  Widget _buildHorizontalScrollGrid(
    BuildContext context,
    Slot slot,
    StepSequencerParams params,
  ) {
    // Disable drag-to-paint for Pattern and Ties modes to allow direct bit clicking
    final isBitPatternMode =
        widget.activeParameter == StepParameter.pattern ||
        widget.activeParameter == StepParameter.ties;

    return FocusTraversalGroup(
      child: GestureDetector(
        onPanStart: isBitPatternMode
            ? null
            : (details) =>
                  _handleDragStart(details.globalPosition, slot, params),
        onPanUpdate: isBitPatternMode
            ? null
            : (details) =>
                  _handleDragUpdate(details.globalPosition, slot, params),
        onPanEnd: isBitPatternMode ? null : (details) => _handleDragEnd(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            key: _rowKey,
            children: List.generate(
              params.numSteps,
              (index) => SizedBox(
                width: 60,
                child: RepaintBoundary(
                  child: _buildStepColumn(context, slot, params, index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build full grid for desktop
  Widget _buildFullGrid(
    BuildContext context,
    Slot slot,
    StepSequencerParams params,
  ) {
    // Disable drag-to-paint for Pattern and Ties modes to allow direct bit clicking
    final isBitPatternMode =
        widget.activeParameter == StepParameter.pattern ||
        widget.activeParameter == StepParameter.ties;

    return FocusTraversalGroup(
      child: GestureDetector(
        onPanStart: isBitPatternMode
            ? null
            : (details) =>
                  _handleDragStart(details.globalPosition, slot, params),
        onPanUpdate: isBitPatternMode
            ? null
            : (details) =>
                  _handleDragUpdate(details.globalPosition, slot, params),
        onPanEnd: isBitPatternMode ? null : (details) => _handleDragEnd(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            key: _rowKey,
            children: List.generate(
              params.numSteps,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 60,
                  child: RepaintBoundary(
                    child: _buildStepColumn(context, slot, params, index),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleStepKeyEvent(
    int stepIndex,
    KeyEvent event,
    Slot slot,
    StepSequencerParams params,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    final isBitMode =
        widget.activeParameter == StepParameter.pattern ||
        widget.activeParameter == StepParameter.ties;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (stepIndex > 0) {
          _stepFocusNodes[stepIndex - 1].requestFocus();
        }
      case LogicalKeyboardKey.arrowRight:
        if (stepIndex < params.numSteps - 1) {
          _stepFocusNodes[stepIndex + 1].requestFocus();
        }
      case LogicalKeyboardKey.arrowUp:
        if (!isBitMode) {
          _adjustStepValue(stepIndex, 1, slot, params);
        }
      case LogicalKeyboardKey.arrowDown:
        if (!isBitMode) {
          _adjustStepValue(stepIndex, -1, slot, params);
        }
      case LogicalKeyboardKey.pageUp:
        if (!isBitMode) {
          final delta = widget.activeParameter == StepParameter.pitch ? 12 : 10;
          _adjustStepValue(stepIndex, delta, slot, params);
        }
      case LogicalKeyboardKey.pageDown:
        if (!isBitMode) {
          final delta = widget.activeParameter == StepParameter.pitch ? 12 : 10;
          _adjustStepValue(stepIndex, -delta, slot, params);
        }
      case LogicalKeyboardKey.home:
        if (!isBitMode) {
          _setStepToMin(stepIndex, slot, params);
        }
      case LogicalKeyboardKey.end:
        if (!isBitMode) {
          _setStepToMax(stepIndex, slot, params);
        }
      default:
        break;
    }
  }

  void _adjustStepValue(
    int stepIndex,
    int delta,
    Slot slot,
    StepSequencerParams params,
  ) {
    final paramIndex = _getParameterIndexForStep(stepIndex, params);
    if (paramIndex == null || paramIndex >= slot.parameters.length) return;

    final paramInfo = slot.parameters[paramIndex];
    final currentValue = paramIndex < slot.values.length
        ? slot.values[paramIndex].value
        : 0;
    final newValue = (currentValue + delta).clamp(paramInfo.min, paramInfo.max);

    if (newValue != currentValue) {
      _updateStepParameter(stepIndex, newValue, params);
    }
  }

  void _setStepToMin(int stepIndex, Slot slot, StepSequencerParams params) {
    final paramIndex = _getParameterIndexForStep(stepIndex, params);
    if (paramIndex == null || paramIndex >= slot.parameters.length) return;
    _updateStepParameter(stepIndex, slot.parameters[paramIndex].min, params);
  }

  void _setStepToMax(int stepIndex, Slot slot, StepSequencerParams params) {
    final paramIndex = _getParameterIndexForStep(stepIndex, params);
    if (paramIndex == null || paramIndex >= slot.parameters.length) return;
    _updateStepParameter(stepIndex, slot.parameters[paramIndex].max, params);
  }

  /// Build individual step column widget
  Widget _buildStepColumn(
    BuildContext context,
    Slot slot,
    StepSequencerParams params,
    int stepIndex,
  ) {
    // Get parameter indices for this step (1-indexed)
    final pitchParamIndex = params.getPitch(stepIndex + 1);
    final velocityParamIndex = params.getVelocity(stepIndex + 1);

    // Get current values (default to 0 if parameter not found)
    final pitchValue =
        pitchParamIndex != null && pitchParamIndex < slot.values.length
        ? slot.values[pitchParamIndex].value
        : 0;

    final velocityValue =
        velocityParamIndex != null && velocityParamIndex < slot.values.length
        ? slot.values[velocityParamIndex].value
        : 0;

    return Focus(
      focusNode: _stepFocusNodes[stepIndex],
      onFocusChange: (hasFocus) {
        setState(() {
          _focusedStepIndex = hasFocus ? stepIndex : -1;
        });
      },
      onKeyEvent: (node, event) {
        final isBitMode =
            widget.activeParameter == StepParameter.pattern ||
            widget.activeParameter == StepParameter.ties;

        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight ||
              (!isBitMode &&
                  (key == LogicalKeyboardKey.arrowUp ||
                      key == LogicalKeyboardKey.arrowDown ||
                      key == LogicalKeyboardKey.pageUp ||
                      key == LogicalKeyboardKey.pageDown ||
                      key == LogicalKeyboardKey.home ||
                      key == LogicalKeyboardKey.end))) {
            _handleStepKeyEvent(stepIndex, event, slot, params);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: _focusedStepIndex == stepIndex
            ? BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: StepColumnWidget(
          stepIndex: stepIndex,
          pitchValue: pitchValue,
          velocityValue: velocityValue,
          isActive: false,
          slotIndex: widget.slotIndex,
          slot: slot,
          snapEnabled: widget.snapEnabled,
          selectedScale: widget.selectedScale,
          rootNote: widget.rootNote,
          activeParameter: widget.activeParameter,
        ),
      ),
    );
  }

  /// Handle drag start - begin painting values
  void _handleDragStart(
    Offset globalPosition,
    Slot slot,
    StepSequencerParams params,
  ) {
    setState(() {
      _isDragging = true;
      _lastPaintedStep = null;
    });
    _paintValueAtPosition(globalPosition, slot, params);
  }

  /// Handle drag update - continue painting as drag moves
  void _handleDragUpdate(
    Offset globalPosition,
    Slot slot,
    StepSequencerParams params,
  ) {
    if (_isDragging) {
      _paintValueAtPosition(globalPosition, slot, params);
    }
  }

  /// Handle drag end - stop painting
  void _handleDragEnd() {
    setState(() {
      _isDragging = false;
      _lastPaintedStep = null;
    });
  }

  /// Paint value at the given position
  void _paintValueAtPosition(
    Offset globalPosition,
    Slot slot,
    StepSequencerParams params,
  ) {
    // Skip bit pattern modes (Pattern, Ties) - they need special editor
    if (widget.activeParameter == StepParameter.pattern ||
        widget.activeParameter == StepParameter.ties) {
      return;
    }

    // Convert global position to local position relative to the Row
    final RenderBox? rowBox =
        _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (rowBox == null) {
      return; // Row not yet rendered
    }

    final localPosition = rowBox.globalToLocal(globalPosition);

    // Calculate which step column is under the cursor
    final stepIndex = _calculateStepIndex(localPosition.dx, params.numSteps);
    if (stepIndex == null || stepIndex == _lastPaintedStep) {
      return; // Outside grid or same step as last update
    }

    _lastPaintedStep = stepIndex;

    // Calculate value from Y position
    final value = _calculateValueFromY(localPosition.dy, slot, params);
    if (value == null) {
      return;
    }

    // Update the parameter
    _updateStepParameter(stepIndex, value, params);
  }

  /// Calculate which step column is under the cursor based on X position
  int? _calculateStepIndex(double x, int numSteps) {
    // Each step is 60px wide + 8px padding (4px on each side) for desktop
    // Mobile has no padding, just 60px
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 768;

    final stepWidth = isMobile ? 60.0 : 68.0; // 60px + 8px padding
    final stepIndex = (x / stepWidth).floor();

    if (stepIndex < 0 || stepIndex >= numSteps) {
      return null; // Outside grid
    }

    return stepIndex;
  }

  /// Calculate parameter value from Y position within step column
  int? _calculateValueFromY(double y, Slot slot, StepSequencerParams params) {
    // Get parameter info for range
    final paramIndex = _getParameterIndexForStep(
      0,
      params,
    ); // Use step 0 as reference
    if (paramIndex == null || paramIndex >= slot.parameters.length) {
      return null;
    }

    final paramInfo = slot.parameters[paramIndex];
    final min = paramInfo.min;
    final max = paramInfo.max;

    // Step column structure from StepColumnWidget:
    // - Step number (Text): ~14px
    // - SizedBox(height: 4)
    // - Expanded (bar area)
    // - SizedBox(height: 4)
    // - ConstrainedBox(minHeight: 22, maxHeight: 22) - value text

    const stepNumberHeight = 14.0; // Text fontSize: 12, plus some padding
    const topSpacing = 4.0;
    const bottomSpacing = 4.0;
    const valueTextHeight = 22.0;

    const headerHeight = stepNumberHeight + topSpacing; // ~18px
    const footerHeight = bottomSpacing + valueTextHeight; // ~26px

    // The step column container has padding: 8px all around from Container
    const containerPadding = 8.0;

    // Adjust Y for container padding
    final yInContainer = y - containerPadding;

    // Calculate position relative to the bar area
    final barTop = headerHeight;
    final relativeY = yInContainer - barTop;

    // Bar height estimate (from 400px grid height - 44px padding - 44px header/footer)
    final barHeight =
        400.0 - (containerPadding * 2) - headerHeight - footerHeight;

    if (relativeY < 0 || relativeY > barHeight) {
      // Outside bar area - clamp to nearest edge
      final clampedY = relativeY.clamp(0.0, barHeight);
      final normalized = 1.0 - (clampedY / barHeight);
      int value = (min + (normalized * (max - min))).round().clamp(min, max);

      // Apply quantization for pitch if enabled
      if (widget.activeParameter == StepParameter.pitch && widget.snapEnabled) {
        value = ScaleQuantizer.quantize(
          value,
          widget.selectedScale,
          widget.rootNote,
        );
      }
      return value;
    }

    // Calculate normalized position (inverted: top = 1.0, bottom = 0.0)
    final normalized = 1.0 - (relativeY / barHeight).clamp(0.0, 1.0);

    // Map to parameter range
    int value = (min + (normalized * (max - min))).round().clamp(min, max);

    // Apply quantization for pitch if enabled
    if (widget.activeParameter == StepParameter.pitch && widget.snapEnabled) {
      value = ScaleQuantizer.quantize(
        value,
        widget.selectedScale,
        widget.rootNote,
      );
    }

    return value;
  }

  /// Get parameter index for a step based on active parameter mode
  int? _getParameterIndexForStep(int stepIndex, StepSequencerParams params) {
    final step1Based = stepIndex + 1; // Convert to 1-indexed for params

    switch (widget.activeParameter) {
      case StepParameter.pitch:
        return params.getPitch(step1Based);
      case StepParameter.velocity:
        return params.getVelocity(step1Based);
      case StepParameter.mod:
        return params.getMod(step1Based);
      case StepParameter.division:
        return params.getDivision(step1Based);
      case StepParameter.mute:
        return params.getMute(step1Based);
      case StepParameter.skip:
        return params.getSkip(step1Based);
      case StepParameter.reset:
        return params.getReset(step1Based);
      case StepParameter.repeat:
        return params.getRepeat(step1Based);
      default:
        return null;
    }
  }

  /// Update step parameter value with debouncing
  void _updateStepParameter(
    int stepIndex,
    int value,
    StepSequencerParams params,
  ) {
    final paramIndex = _getParameterIndexForStep(stepIndex, params);
    if (paramIndex == null) {
      return;
    }

    final scope = StepSequencerEditScope.capture(
      context.read<DistingCubit>(),
      widget.slotIndex,
      widget.slot,
    );
    if (scope == null) return;
    _debouncer.schedule('step_$stepIndex', () {
      if (mounted && scope.isCurrent) {
        scope.cubit.updateParameterValue(
          algorithmIndex: scope.slotIndex,
          parameterNumber: paramIndex,
          value: value,
          userIsChangingTheValue: true,
        );
      }
    }, const Duration(milliseconds: 50));
  }
}
