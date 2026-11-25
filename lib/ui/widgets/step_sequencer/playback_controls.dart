import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/util/parameter_write_debouncer.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_sequencer_edit_scope.dart';

/// Playback controls for Step Sequencer algorithm
///
/// Provides controls for global playback parameters:
/// - Direction (Forward, Reverse, Pendulum, Random, etc.)
/// - Permutation (None, Variation 1-3)
/// - Start Step (1-16)
/// - End Step (1-16)
/// - Gate Type (Gate, Trigger)
/// - Gate Length (1-99%)
/// - Trigger Length (1-100ms)
/// - Glide Time (0-1000ms)
///
/// Supports responsive layouts:
/// - Desktop/Tablet (width > 768px): horizontal wrap layout
/// - Mobile (width ≤ 768px): vertical column layout
class PlaybackControls extends StatefulWidget {
  final int slotIndex;
  final StepSequencerParams params;
  final Slot slot;
  final bool compact;
  final ParameterWriteDebouncer? pendingWrites;

  const PlaybackControls({
    super.key,
    required this.slotIndex,
    required this.params,
    required this.slot,
    this.compact = false,
    this.pendingWrites,
  });

  @override
  State<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<PlaybackControls> {
  final _ownWrites = ParameterWriteDebouncer();
  final _writeKeys = <String>{};
  ParameterWriteDebouncer get _debouncer => widget.pendingWrites ?? _ownWrites;
  final _startStepController = TextEditingController();
  final _endStepController = TextEditingController();

  // Track disabled state for dependent parameters
  bool _isGateLengthDisabled = false;
  bool _isTriggerLengthDisabled = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _refreshParameterStates();
  }

  @override
  void didUpdateWidget(PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot != widget.slot) {
      _initializeControllers(previous: oldWidget.slot);
      _refreshParameterStates();
    }
  }

  void _initializeControllers({Slot? previous}) {
    // Initialize start step controller
    final startStepParam = widget.params.startStep;
    if (startStepParam != null && startStepParam < widget.slot.values.length) {
      final startValue = widget.slot.values[startStepParam].value;
      if (previous?.values.elementAtOrNull(startStepParam)?.value !=
          startValue) {
        _startStepController.text = startValue.toString();
      }
    }

    // Initialize end step controller
    final endStepParam = widget.params.endStep;
    if (endStepParam != null && endStepParam < widget.slot.values.length) {
      final endValue = widget.slot.values[endStepParam].value;
      if (previous?.values.elementAtOrNull(endStepParam)?.value != endValue) {
        _endStepController.text = endValue.toString();
      }
    }
  }

  /// Refreshes parameter disabled states based on Gate Type dependency
  ///
  /// Gate Type controls which length parameter is active:
  /// - Gate Type = 0 (Gate): Gate Length enabled, Trigger Length disabled
  /// - Gate Type = 1 (Trigger): Trigger Length enabled, Gate Length disabled
  ///
  /// This method reads the disabled flag from parameter values (no SysEx requests)
  void _refreshParameterStates() {
    final slot = widget.slot;

    // Get Gate Length disabled state
    final gateLengthParam = widget.params.gateLength;
    if (gateLengthParam != null && gateLengthParam < slot.values.length) {
      final gateLengthValue = slot.values[gateLengthParam];
      setState(() {
        _isGateLengthDisabled = gateLengthValue.isDisabled;
      });
    }

    // Get Trigger Length disabled state
    final triggerLengthParam = widget.params.triggerLength;
    if (triggerLengthParam != null && triggerLengthParam < slot.values.length) {
      final triggerLengthValue = slot.values[triggerLengthParam];
      setState(() {
        _isTriggerLengthDisabled = triggerLengthValue.isDisabled;
      });
    }
  }

  @override
  void dispose() {
    for (final key in _writeKeys) {
      _debouncer.cancel(key);
    }
    _ownWrites.dispose();
    _startStepController.dispose();
    _endStepController.dispose();
    super.dispose();
  }

  /// Gets enum strings for a parameter with fallback to numeric labels
  ///
  /// Returns firmware-provided enum strings if available, otherwise falls back
  /// to numeric labels based on parameter min/max values.
  ///
  /// Examples:
  /// - With enum strings: ['Forward', 'Reverse', 'Pendulum', ...]
  /// - Without enum strings: ['0', '1', '2', '3', ...]
  List<String> _getEnumStringsOrFallback(Slot slot, int paramNumber) {
    // Try to get enum strings from slot
    final enumStrings = paramNumber < slot.enums.length
        ? slot.enums[paramNumber]
        : null;

    if (enumStrings != null && enumStrings.values.isNotEmpty) {
      // Use firmware-provided enum strings
      return enumStrings.values;
    }

    // Fallback to numeric labels based on parameter range
    if (paramNumber < slot.parameters.length) {
      final paramInfo = slot.parameters[paramNumber];
      final count = paramInfo.max - paramInfo.min + 1;
      return List.generate(count, (index) => '${paramInfo.min + index}');
    }

    // Last resort fallback
    return ['0'];
  }

  /// Builds dropdown menu items from enum strings for a parameter
  ///
  /// Uses firmware-provided enum strings if available, otherwise falls back
  /// to numeric labels. This ensures dropdowns work across firmware versions
  /// and adapt automatically to firmware changes.
  List<DropdownMenuItem<int>> _buildEnumDropdownItems(
    Slot slot,
    int paramNumber,
  ) {
    final options = _getEnumStringsOrFallback(slot, paramNumber);

    return List.generate(
      options.length,
      (index) => DropdownMenuItem(value: index, child: Text(options[index])),
    );
  }

  /// Updates a parameter with optional debouncing
  void _updateParameter(
    int? paramNumber,
    int value, {
    required Slot displayedSlot,
    bool debounce = false,
  }) {
    if (paramNumber == null || paramNumber >= widget.slot.values.length) {
      return;
    }

    final scope = StepSequencerEditScope.capture(
      context.read<DistingCubit>(),
      widget.slotIndex,
      displayedSlot,
    );
    if (scope == null) return;

    if (debounce) {
      final key = 'param_$paramNumber';
      _writeKeys.add(key);
      _debouncer.schedule(
        key,
        () {
          try {
            if (!mounted || !scope.isCurrent) return;
            scope.cubit.updateParameterValue(
              algorithmIndex: scope.slotIndex,
              parameterNumber: paramNumber,
              value: value,
              userIsChangingTheValue: true,
            );
          } finally {
            scope.dispose();
          }
        },
        const Duration(milliseconds: 50),
        onCancel: scope.dispose,
      );
    } else {
      try {
        scope.cubit.updateParameterValue(
          algorithmIndex: scope.slotIndex,
          parameterNumber: paramNumber,
          value: value,
          userIsChangingTheValue: true,
        );
      } finally {
        scope.dispose();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DistingCubit, DistingState>(
      buildWhen: (prev, curr) {
        // Only rebuild when playback parameters change
        if (curr is! DistingStateSynchronized) return false;
        if (prev is! DistingStateSynchronized) return true;
        if (widget.slotIndex < 0 ||
            widget.slotIndex >= curr.slots.length ||
            widget.slotIndex >= prev.slots.length) {
          return true;
        }

        // Check if any playback parameter changed
        final prevSlot = prev.slots[widget.slotIndex];
        final currSlot = curr.slots[widget.slotIndex];

        final playbackParamNumbers = [
          widget.params.currentSequence,
          widget.params.direction,
          widget.params.startStep,
          widget.params.endStep,
          widget.params.gateLength,
          widget.params.triggerLength,
          widget.params.glideTime,
          widget.params.permutation,
          widget.params.gateType,
        ].whereType<int>(); // Filter out nulls

        for (final paramNum in playbackParamNumbers) {
          if (paramNum < prevSlot.values.length &&
              paramNum < currSlot.values.length) {
            if (prevSlot.values[paramNum].value !=
                currSlot.values[paramNum].value) {
              return true;
            }
          }
        }

        return false;
      },
      builder: (context, state) {
        if (state is! DistingStateSynchronized) {
          return const SizedBox.shrink();
        }
        if (widget.slotIndex < 0 || widget.slotIndex >= state.slots.length) {
          return const SizedBox.shrink();
        }

        final slot = state.slots[widget.slotIndex];

        if (widget.compact) {
          return _buildCompactLayout(slot);
        } else {
          return _buildFullLayout(slot);
        }
      },
    );
  }

  Widget _buildFullLayout(Slot slot) {
    // Desktop/tablet: horizontal row layout (scrollable)
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.start,
          children: [
            SizedBox(width: 200, child: _buildDirectionDropdown(slot)),
            SizedBox(width: 180, child: _buildPermutationDropdown(slot)),
            SizedBox(width: 100, child: _buildStartStepInput(slot)),
            SizedBox(width: 100, child: _buildEndStepInput(slot)),
            SizedBox(width: 150, child: _buildGateTypeToggle(slot)),
            SizedBox(width: 250, child: _buildGateLengthSlider(slot)),
            SizedBox(width: 250, child: _buildTriggerLengthSlider(slot)),
            SizedBox(width: 250, child: _buildGlideTimeSlider(slot)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLayout(Slot slot) {
    // Mobile: vertical column, smaller controls (scrollable)
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _buildDirectionDropdown(slot)),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: _buildStartStepInput(slot)),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: _buildEndStepInput(slot)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _buildPermutationDropdown(slot),
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: _buildGateTypeToggle(slot)),
            const SizedBox(height: 12),
            _buildGateLengthSlider(slot),
            const SizedBox(height: 8),
            _buildTriggerLengthSlider(slot),
            const SizedBox(height: 8),
            _buildGlideTimeSlider(slot),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionDropdown(Slot slot) {
    final directionParam = widget.params.direction;
    if (directionParam == null || directionParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = directionParam < slot.values.length
        ? slot.values[directionParam].value
        : 0;

    // Build dropdown items from firmware enum strings
    final items = _buildEnumDropdownItems(slot, directionParam);

    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: currentValue.clamp(0, items.length - 1),
      decoration: const InputDecoration(
        labelText: 'Direction',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: (value) {
        if (value != null) {
          _updateParameter(directionParam, value, displayedSlot: slot);

          // Request fresh parameter values from hardware after Direction change
          context.read<DistingCubit>().scheduleParameterRefresh(
            widget.slotIndex,
          );
        }
      },
    );
  }

  Widget _buildStartStepInput(Slot slot) {
    final startStepParam = widget.params.startStep;
    if (startStepParam == null || startStepParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    return DigitShortcutBlocker(
      child: TextFormField(
        controller: _startStepController,
        decoration: const InputDecoration(
          labelText: 'Start',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onFieldSubmitted: (value) {
          final intValue = int.tryParse(value);
          if (intValue != null && intValue >= 1 && intValue <= 16) {
            _updateParameter(startStepParam, intValue, displayedSlot: slot);
          } else {
            final current = startStepParam < slot.values.length
                ? slot.values[startStepParam].value
                : 1;
            _startStepController.text = current.toString();
          }
        },
      ),
    );
  }

  Widget _buildEndStepInput(Slot slot) {
    final endStepParam = widget.params.endStep;
    if (endStepParam == null || endStepParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final startStepParam = widget.params.startStep;
    final startValue =
        startStepParam != null && startStepParam < slot.values.length
        ? slot.values[startStepParam].value
        : 1;

    return DigitShortcutBlocker(
      child: TextFormField(
        controller: _endStepController,
        decoration: const InputDecoration(
          labelText: 'End',
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onFieldSubmitted: (value) {
          final intValue = int.tryParse(value);
          if (intValue != null &&
              intValue >= 1 &&
              intValue <= 16 &&
              intValue >= startValue) {
            _updateParameter(endStepParam, intValue, displayedSlot: slot);
          } else {
            final current = endStepParam < slot.values.length
                ? slot.values[endStepParam].value
                : 16;
            _endStepController.text = current.toString();
          }
        },
      ),
    );
  }

  Widget _buildPermutationDropdown(Slot slot) {
    final permutationParam = widget.params.permutation;
    if (permutationParam == null ||
        permutationParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = permutationParam < slot.values.length
        ? slot.values[permutationParam].value
        : 0;

    // Build dropdown items from firmware enum strings
    final items = _buildEnumDropdownItems(slot, permutationParam);

    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: currentValue.clamp(0, items.length - 1),
      decoration: const InputDecoration(
        labelText: 'Permutation',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: (value) {
        if (value != null) {
          _updateParameter(permutationParam, value, displayedSlot: slot);
        }
      },
    );
  }

  Widget _buildGateTypeToggle(Slot slot) {
    final gateTypeParam = widget.params.gateType;
    if (gateTypeParam == null || gateTypeParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = gateTypeParam < slot.values.length
        ? slot.values[gateTypeParam].value
        : 0;

    // Build dropdown items from firmware enum strings
    final items = _buildEnumDropdownItems(slot, gateTypeParam);

    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: currentValue.clamp(0, items.length - 1),
      decoration: const InputDecoration(
        labelText: 'Gate Type',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: (value) {
        if (value != null) {
          _updateParameter(gateTypeParam, value, displayedSlot: slot);

          // Request fresh parameter values from hardware after Gate Type change
          // This ensures we get updated disabled states for dependent parameters
          context.read<DistingCubit>().scheduleParameterRefresh(
            widget.slotIndex,
          );
        }
      },
    );
  }

  Widget _buildGateLengthSlider(Slot slot) {
    final gateLengthParam = widget.params.gateLength;
    if (gateLengthParam == null || gateLengthParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = gateLengthParam < slot.values.length
        ? slot.values[gateLengthParam].value
        : 50;

    final isDisabled = _isGateLengthDisabled;

    return Semantics(
      label: 'Gate Length: $currentValue%',
      enabled: !isDisabled,
      hint: isDisabled ? 'Disabled when Gate Type is Trigger' : null,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Tooltip(
          message: isDisabled
              ? 'Disabled when Gate Type is Trigger'
              : 'Sets gate length as percentage of step duration',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  'Gate Length: $currentValue%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Slider(
                value: currentValue.toDouble().clamp(1, 99),
                min: 1,
                max: 99,
                divisions: 98,
                label: '$currentValue%',
                semanticFormatterCallback: (v) => '${v.round()}%',
                onChanged: isDisabled
                    ? null
                    : (value) {
                        _updateParameter(
                          gateLengthParam,
                          value.toInt(),
                          displayedSlot: slot,
                          debounce: true,
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTriggerLengthSlider(Slot slot) {
    final triggerLengthParam = widget.params.triggerLength;
    if (triggerLengthParam == null ||
        triggerLengthParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = triggerLengthParam < slot.values.length
        ? slot.values[triggerLengthParam].value
        : 10;

    final isDisabled = _isTriggerLengthDisabled;

    return Semantics(
      label: 'Trigger Length: ${currentValue}ms',
      enabled: !isDisabled,
      hint: isDisabled ? 'Disabled when Gate Type is Gate' : null,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: Tooltip(
          message: isDisabled
              ? 'Disabled when Gate Type is Gate'
              : 'Sets trigger length in milliseconds',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  'Trigger Length: ${currentValue}ms',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Slider(
                value: currentValue.toDouble().clamp(1, 100),
                min: 1,
                max: 100,
                divisions: 99,
                label: '${currentValue}ms',
                semanticFormatterCallback: (v) => '${v.round()} milliseconds',
                onChanged: isDisabled
                    ? null
                    : (value) {
                        _updateParameter(
                          triggerLengthParam,
                          value.toInt(),
                          displayedSlot: slot,
                          debounce: true,
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlideTimeSlider(Slot slot) {
    final glideTimeParam = widget.params.glideTime;
    if (glideTimeParam == null || glideTimeParam >= slot.parameters.length) {
      return const SizedBox.shrink();
    }

    final currentValue = glideTimeParam < slot.values.length
        ? slot.values[glideTimeParam].value
        : 0;

    return Semantics(
      label: 'Glide Time: ${currentValue}ms',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Text(
              'Glide Time: ${currentValue}ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Slider(
            value: currentValue.toDouble().clamp(0, 1000),
            min: 0,
            max: 1000,
            divisions: 100,
            label: '${currentValue}ms',
            semanticFormatterCallback: (v) => '${v.round()} milliseconds',
            onChanged: (value) {
              _updateParameter(
                glideTimeParam,
                value.toInt(),
                displayedSlot: slot,
                debounce: true,
              );
            },
          ),
        ],
      ),
    );
  }
}
