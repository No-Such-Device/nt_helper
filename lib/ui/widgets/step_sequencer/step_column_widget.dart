import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/scale_quantizer.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/bit_pattern_editor.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/pitch_bar_painter.dart';
import 'package:nt_helper/util/ui_helpers.dart';

/// Step parameter types for editing (GLOBAL mode, not per-step)
enum StepParameter {
  pitch,
  velocity,
  mod,
  division,
  pattern,
  ties,
  mute,
  skip,
  reset,
  repeat,
}

/// Individual step column widget showing parameter bar and step number
/// Uses global parameter mode selector (controlled by parent StepSequencerView)
class StepColumnWidget extends StatefulWidget {
  final int stepIndex; // 0-indexed
  final int pitchValue; // 0-127 MIDI note
  final int velocityValue; // 0-127
  final bool isActive;
  final int slotIndex;
  final Slot slot;
  final bool snapEnabled;
  final String selectedScale;
  final int rootNote;
  final StepParameter activeParameter; // GLOBAL parameter mode from parent
  final ValueChanged<int>? onParameterChanged; // Callback for parameter updates

  const StepColumnWidget({
    super.key,
    required this.stepIndex,
    required this.pitchValue,
    required this.velocityValue,
    required this.isActive,
    required this.slotIndex,
    required this.slot,
    required this.snapEnabled,
    required this.selectedScale,
    required this.rootNote,
    required this.activeParameter,
    this.onParameterChanged,
  });

  @override
  State<StepColumnWidget> createState() => _StepColumnWidgetState();
}

class _StepColumnWidgetState extends State<StepColumnWidget> {
  // OLD: Per-step parameter selection (_activeParam) - REMOVED
  // NEW: Global parameter mode is passed via widget.activeParameter

  String _getSemanticLabel() {
    final stepLabel = 'Step ${widget.stepIndex + 1}';
    final paramName = widget.activeParameter.name;
    final value = _getCurrentParameterValue();
    final formattedValue = _isBitPatternMode()
        ? '${_getValidBitCount()} substeps'
        : _formatStepValue(value);
    final activeLabel = widget.isActive ? ', active' : '';
    return '$stepLabel, $paramName: $formattedValue$activeLabel';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeStepColor = context.appColors.sequencerAt(0).color;
    final borderColor = widget.isActive
        ? activeStepColor
        : scheme.outlineVariant;
    final borderWidth = widget.isActive ? 2.0 : 1.0;

    final currentValue = _getCurrentParameterValue();
    final minVal = _getParameterMin();
    final maxVal = _getParameterMax();

    return Semantics(
      label: _getSemanticLabel(),
      value: _isBitPatternMode() ? null : _formatStepValue(currentValue),
      hint: 'Swipe up or down to adjust ${widget.activeParameter.name}',
      increasedValue: _isBitPatternMode()
          ? null
          : _formatStepValue((currentValue + 1).clamp(minVal, maxVal)),
      decreasedValue: _isBitPatternMode()
          ? null
          : _formatStepValue((currentValue - 1).clamp(minVal, maxVal)),
      onIncrease: _isBitPatternMode()
          ? null
          : () => _updateParameter((currentValue + 1).clamp(minVal, maxVal)),
      onDecrease: _isBitPatternMode()
          ? null
          : () => _updateParameter((currentValue - 1).clamp(minVal, maxVal)),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: widget.isActive
              ? activeStepColor.withValues(alpha: 0.2)
              : scheme.surfaceContainerLow,
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Step number (1-indexed for display)
            Text(
              '${widget.stepIndex + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),

            // Main parameter bar (tappable and draggable for editing current parameter)
            Expanded(
              child: _isBitPatternMode()
                  ? BitPatternEditor(
                      value: _getCurrentParameterValue(),
                      color: _getActiveParameterColor(),
                      validBitCount: _getValidBitCount(),
                      onChanged: _updateParameter,
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SizedBox(
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              _handleBarInteraction(
                                details.localPosition.dy,
                                constraints.maxHeight,
                              );
                            },
                            onVerticalDragUpdate: (details) {
                              _handleBarInteraction(
                                details.localPosition.dy,
                                constraints.maxHeight,
                              );
                            },
                            child: CustomPaint(
                              painter: PitchBarPainter(
                                pitchValue: _getCurrentParameterValue(),
                                barColor: _getActiveParameterColor(),
                                displayMode: _getDisplayMode(),
                                minValue: _getParameterMin(),
                                maxValue: _getParameterMax(),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 4),

            // Current parameter value text + warning (fixed height to prevent layout shift)
            // For Division mode, show subdivision label instead of division value
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 22, maxHeight: 22),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Show subdivision label for Division mode, otherwise show value
                  if (widget.activeParameter == StepParameter.division)
                    Positioned(
                      top: 0,
                      child: Text(
                        _getSubdivisionLabel(_getCurrentParameterValue()),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getActiveParameterColor(),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Positioned(
                      top: 0,
                      child: Text(
                        _formatStepValue(_getCurrentParameterValue()),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getActiveParameterColor(),
                        ),
                      ),
                    ),
                  // Warning indicator if Pattern = 0 (no substeps active)
                  if (_shouldShowPatternWarning())
                    Positioned(
                      bottom: 0,
                      child: Tooltip(
                        message: 'Pattern has no steps',
                        child: Icon(
                          Icons.warning_amber,
                          size: 10,
                          color: context.appColors.warning.color,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Check if current mode is bit pattern (Pattern or Ties)
  bool _isBitPatternMode() {
    return widget.activeParameter == StepParameter.pattern ||
        widget.activeParameter == StepParameter.ties;
  }

  /// Get the current step's division value
  int _getCurrentDivisionValue() {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final step = widget.stepIndex + 1;
    final divisionIndex = params.getDivision(step);

    if (divisionIndex != null && divisionIndex < widget.slot.values.length) {
      return widget.slot.values[divisionIndex].value;
    }
    return 7; // Default division (no subdivision)
  }

  /// Get the number of valid bits for Pattern/Ties based on current Division
  /// Returns 1-8 based on subdivision count
  int _getValidBitCount() {
    if (!_isBitPatternMode()) {
      return 8; // Not in bit pattern mode, return max
    }
    final divisionValue = _getCurrentDivisionValue();
    return _calculateSubdivisions(divisionValue);
  }

  /// Check if we should show the pattern warning (Pattern = 0 means no substeps active)
  bool _shouldShowPatternWarning() {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final step = widget.stepIndex + 1;
    final patternIndex = params.getPattern(step);

    if (patternIndex != null && patternIndex < widget.slot.values.length) {
      final patternValue = widget.slot.values[patternIndex].value;
      return patternValue == 0; // No substeps active
    }
    return false;
  }

  /// Get the appropriate display mode for the painter
  /// Note: Bit pattern modes use BitPatternEditor widget instead
  BarDisplayMode _getDisplayMode() {
    if (widget.activeParameter == StepParameter.division) {
      return BarDisplayMode.division;
    } else {
      return BarDisplayMode.continuous;
    }
  }

  /// Update parameter value via cubit
  void _updateParameter(int newValue) {
    final params = StepSequencerParams.fromSlot(widget.slot);
    int? paramIndex = _getParameterIndex(params, widget.activeParameter);

    if (paramIndex != null) {
      context.read<DistingCubit>().updateParameterValue(
        algorithmIndex: widget.slotIndex,
        parameterNumber: paramIndex,
        value: newValue,
        userIsChangingTheValue: true,
      );
    }
  }

  /// Handle tap or drag on pitch bar to edit active parameter
  void _handleBarInteraction(double localY, double barHeight) {
    // Get parameter's min/max range from metadata
    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    int min = 0;
    int max = 127;
    if (paramIndex != null && paramIndex < widget.slot.parameters.length) {
      final paramInfo = widget.slot.parameters[paramIndex];
      min = paramInfo.min;
      max = paramInfo.max;
    }

    // Calculate value based on position (inverted - top is high, bottom is low)
    // Map bar position (0.0-1.0) to parameter range (min-max)
    final normalizedPosition = 1.0 - (localY / barHeight);
    int newValue = (min + (normalizedPosition * (max - min))).round().clamp(
      min,
      max,
    );

    // For probability parameters, convert percentage back to firmware value
    if (_isProbabilityMode()) {
      newValue = _percentageToFirmware(newValue);
    } else if (widget.activeParameter == StepParameter.pitch &&
        widget.snapEnabled) {
      // Apply quantization if needed for pitch parameter
      newValue = ScaleQuantizer.quantize(
        newValue,
        widget.selectedScale,
        widget.rootNote,
      );
    }

    _updateParameter(newValue);
  }

  /// Get parameter index from parameter type using step sequencer params service
  int? _getParameterIndex(StepSequencerParams params, StepParameter param) {
    final step = widget.stepIndex + 1; // Convert 0-indexed to 1-indexed

    switch (param) {
      case StepParameter.pitch:
        return params.getPitch(step);
      case StepParameter.velocity:
        return params.getVelocity(step);
      case StepParameter.mod:
        return params.getMod(step);
      case StepParameter.division:
        return params.getDivision(step);
      case StepParameter.pattern:
        return params.getPattern(step);
      case StepParameter.ties:
        return params.getTies(step);
      case StepParameter.mute:
        return params.getMute(step);
      case StepParameter.skip:
        return params.getSkip(step);
      case StepParameter.reset:
        return params.getReset(step);
      case StepParameter.repeat:
        return params.getRepeat(step);
    }
  }

  /// Get the value of the currently selected parameter
  /// For probability parameters, returns percentage (0-100)
  /// For other parameters, returns firmware value (0-127 or relevant range)
  int _getCurrentParameterValue() {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    if (paramIndex != null && paramIndex < widget.slot.values.length) {
      final value = widget.slot.values[paramIndex].value;

      // Clamp to parameter's min/max range from metadata
      int clampedValue = value;
      if (paramIndex < widget.slot.parameters.length) {
        final paramInfo = widget.slot.parameters[paramIndex];
        clampedValue = value.clamp(paramInfo.min, paramInfo.max);
      }

      // For probability parameters, convert firmware value to percentage
      if (_isProbabilityMode()) {
        return _firmwareToPercentage(clampedValue);
      }

      return clampedValue;
    }
    return 0; // Default if parameter not found
  }

  /// Get the minimum value for the currently selected parameter
  /// For probability parameters, returns 0 (0%)
  /// For other parameters, returns firmware min value
  int _getParameterMin() {
    // Probability parameters always have min = 0 (0%)
    if (_isProbabilityMode()) {
      return 0;
    }

    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    if (paramIndex != null && paramIndex < widget.slot.parameters.length) {
      return widget.slot.parameters[paramIndex].min;
    }
    return 0; // Default
  }

  /// Get the maximum value for the currently selected parameter
  /// For probability parameters, returns 100 (100%)
  /// For other parameters, returns firmware max value
  int _getParameterMax() {
    // Probability parameters always have max = 100 (100%)
    if (_isProbabilityMode()) {
      return 100;
    }

    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    if (paramIndex != null && paramIndex < widget.slot.parameters.length) {
      return widget.slot.parameters[paramIndex].max;
    }
    return 127; // Default
  }

  /// Format step value based on parameter type
  String _formatStepValue(int value) {
    switch (widget.activeParameter) {
      case StepParameter.pitch:
        return midiNoteToNoteString(value); // e.g., "C4", "E4"

      case StepParameter.velocity:
        return value.toString(); // e.g., "64"

      case StepParameter.mod:
        return formatWithUnit(
          value,
          min: 0,
          max: 255,
          name: 'V',
          unit: 'V',
          powerOfTen: -1,
        ); // e.g., "2.0V"

      case StepParameter.division:
        // Division is 0-14 repeats/ratchets - show as-is for now
        return value.toString();

      case StepParameter.pattern:
      case StepParameter.ties:
        return ''; // Empty - bit pattern is visualized in the bar

      case StepParameter.mute:
      case StepParameter.skip:
      case StepParameter.reset:
      case StepParameter.repeat:
        return '$value%'; // e.g., "50%"
    }
  }

  /// Get the color of the currently selected parameter
  Color _getActiveParameterColor() {
    return context.appColors.sequencerAt(widget.activeParameter.index).color;
  }

  /// Convert firmware value to percentage (0-100)
  /// Used for displaying probability parameters
  /// Uses the parameter's actual max value instead of hardcoded 127
  int _firmwareToPercentage(int firmwareValue) {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    int paramMax = 100; // Default for probability parameters
    if (paramIndex != null && paramIndex < widget.slot.parameters.length) {
      paramMax = widget.slot.parameters[paramIndex].max;
    }

    return ((firmwareValue / paramMax.toDouble()) * 100).round().clamp(0, 100);
  }

  /// Convert percentage (0-100) to firmware value
  /// Used for writing probability parameters to hardware
  /// Uses the parameter's actual max value instead of hardcoded 127
  int _percentageToFirmware(int percentage) {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final paramIndex = _getParameterIndex(params, widget.activeParameter);

    int paramMax = 100; // Default for probability parameters
    if (paramIndex != null && paramIndex < widget.slot.parameters.length) {
      paramMax = widget.slot.parameters[paramIndex].max;
    }

    return ((percentage / 100.0) * paramMax).round().clamp(0, paramMax);
  }

  /// Check if current parameter is a probability type
  bool _isProbabilityMode() {
    return widget.activeParameter == StepParameter.mute ||
        widget.activeParameter == StepParameter.skip ||
        widget.activeParameter == StepParameter.reset ||
        widget.activeParameter == StepParameter.repeat;
  }

  /// Calculate number of subdivisions from Division parameter value
  /// Formula: subdivisions = |Division - 7| + 1
  /// - Division = 7 (default) → 1 subdivision (no ratchet/repeat)
  /// - Division < 7 → ratchets (fast subdivided notes)
  /// - Division > 7 → repeats (multiple sustained notes)
  int _calculateSubdivisions(int divisionValue) {
    // Clamp to valid range (0-14)
    final clampedDivision = divisionValue.clamp(0, 14);

    // Calculate distance from default (7)
    final distanceFromDefault = (clampedDivision - 7).abs();

    // Subdivisions = distance + 1
    return distanceFromDefault + 1;
  }

  /// Get subdivision label text based on Division parameter value
  /// - Division < 7: "X Ratchets" (e.g., "2 Ratchets")
  /// - Division > 7: "X Repeats" (e.g., "3 Repeats")
  /// - Division = 7: "1" (no subdivision)
  String _getSubdivisionLabel(int divisionValue) {
    final subdivisions = _calculateSubdivisions(divisionValue);

    if (divisionValue < 7) {
      return '$subdivisions RA'; // Ratchets abbreviated
    } else if (divisionValue > 7) {
      return '$subdivisions RE'; // Repeats abbreviated
    } else {
      return '1'; // Division = 7, no subdivision
    }
  }
}
