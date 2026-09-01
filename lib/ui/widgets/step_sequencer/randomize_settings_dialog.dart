import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';

/// Dialog for configuring randomization settings for the Step Sequencer
///
/// Displays all 17 randomize parameters using existing parameter editor widgets.
/// Parameters update immediately via DistingCubit with automatic debouncing.
class RandomizeSettingsDialog extends StatefulWidget {
  final Slot slot;
  final int slotIndex;

  const RandomizeSettingsDialog({
    super.key,
    required this.slot,
    required this.slotIndex,
  });

  @override
  State<RandomizeSettingsDialog> createState() =>
      _RandomizeSettingsDialogState();
}

class _RandomizeSettingsDialogState extends State<RandomizeSettingsDialog> {
  late StepSequencerParams _params;

  @override
  void initState() {
    super.initState();
    _params = StepSequencerParams.fromSlot(widget.slot);
  }

  /// Gets enum strings for a parameter with fallback to numeric labels
  ///
  /// Returns firmware-provided enum strings if available, otherwise falls back
  /// to numeric labels based on parameter min/max values.
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return BlocBuilder<DistingCubit, DistingState>(
      builder: (context, state) {
        // Get current slot to refresh parameter values
        final currentSlot = state.maybeWhen(
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
                if (widget.slotIndex < slots.length) {
                  return slots[widget.slotIndex];
                }
                return widget.slot;
              },
          orElse: () => widget.slot,
        );

        // Rebuild params with current slot data
        _params = StepSequencerParams.fromSlot(currentSlot);

        final content = Scaffold(
          appBar: AppBar(
            title: const Text('Randomize Settings'),
            leading: IconButton(
              icon: const Icon(
                Icons.close,
                semanticLabel: 'Close randomize settings',
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _buildParameterList(currentSlot),
        );

        if (isMobile) {
          // Full-screen dialog on mobile
          return Dialog.fullscreen(child: content);
        } else {
          // Large centered dialog on desktop/tablet
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: content,
            ),
          );
        }
      },
    );
  }

  Widget _buildParameterList(Slot slot) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trigger Parameter Section
        _buildSectionHeader('Trigger'),
        _buildTriggerSwitch(slot),
        const SizedBox(height: 24),

        // What to Randomize Section
        _buildSectionHeader('What to Randomize'),
        _buildRandomiseWhatDropdown(slot),
        const SizedBox(height: 24),

        // Note Distribution Section
        _buildSectionHeader('Note Distribution'),
        _buildNoteDistributionDropdown(slot),
        const SizedBox(height: 16),

        // Pitch Range Section (conditional based on distribution)
        _buildPitchRangeParameters(slot),
        const SizedBox(height: 24),

        // Rhythm Section
        _buildSectionHeader('Rhythm'),
        _buildRhythmParameters(slot),
        const SizedBox(height: 24),

        // Probabilities Section
        _buildSectionHeader('Probabilities'),
        _buildProbabilityParameters(slot),
        const SizedBox(height: 24),

        // Velocity Section
        _buildSectionHeader('Velocity'),
        _buildVelocityParameter(slot),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildTriggerSwitch(Slot slot) {
    final paramNum = _params.randomise;
    if (paramNum == null) return const SizedBox.shrink();

    final value = slot.values[paramNum].value;
    final isEnabled = value == 1;

    return SwitchListTile(
      title: const Text('Randomise'),
      subtitle: const Text('Trigger randomization (0-1)'),
      value: isEnabled,
      onChanged: (newValue) {
        _updateParameter(paramNum, newValue ? 1 : 0);
      },
    );
  }

  Widget _buildRandomiseWhatDropdown(Slot slot) {
    final paramNum = _params.randomiseWhat;
    if (paramNum == null) return const SizedBox.shrink();

    final value = slot.values[paramNum].value;

    // Get enum strings from firmware
    final options = _getEnumStringsOrFallback(slot, paramNum);

    return ListTile(
      title: const Text('Randomise what'),
      subtitle: DropdownButton<int>(
        isExpanded: true,
        value: value.clamp(0, options.length - 1),
        items: List.generate(
          options.length,
          (index) =>
              DropdownMenuItem(value: index, child: Text(options[index])),
        ),
        onChanged: (newValue) {
          if (newValue != null) {
            _updateParameter(paramNum, newValue);
          }
        },
      ),
    );
  }

  Widget _buildNoteDistributionDropdown(Slot slot) {
    final paramNum = _params.noteDistribution;
    if (paramNum == null) return const SizedBox.shrink();

    final value = slot.values[paramNum].value;

    // Get enum strings from firmware
    final options = _getEnumStringsOrFallback(slot, paramNum);

    return ListTile(
      title: const Text('Note distribution'),
      subtitle: DropdownButton<int>(
        isExpanded: true,
        value: value.clamp(0, options.length - 1),
        items: List.generate(
          options.length,
          (index) =>
              DropdownMenuItem(value: index, child: Text(options[index])),
        ),
        onChanged: (newValue) {
          if (newValue != null) {
            _updateParameter(paramNum, newValue);
          }
        },
      ),
    );
  }

  Widget _buildPitchRangeParameters(Slot slot) {
    final distributionParam = _params.noteDistribution;
    if (distributionParam == null) return const SizedBox.shrink();

    final distribution = slot.values[distributionParam].value;
    final isUniform = distribution == 0;

    if (isUniform) {
      // Uniform distribution: Min/Max note
      return Column(
        children: [
          _buildSliderParameter(
            slot,
            'Min note',
            _params.minNote,
            0,
            127,
            showMidiNote: true,
          ),
          _buildSliderParameter(
            slot,
            'Max note',
            _params.maxNote,
            0,
            127,
            showMidiNote: true,
          ),
        ],
      );
    } else {
      // Normal distribution: Mean/Deviation
      return Column(
        children: [
          _buildSliderParameter(
            slot,
            'Mean note',
            _params.meanNote,
            0,
            127,
            showMidiNote: true,
          ),
          _buildSliderParameter(
            slot,
            'Note deviation',
            _params.noteDeviation,
            0,
            127,
          ),
        ],
      );
    }
  }

  Widget _buildRhythmParameters(Slot slot) {
    return Column(
      children: [
        _buildSliderParameter(slot, 'Min repeat', _params.minRepeat, 2, 8),
        _buildSliderParameter(slot, 'Max repeat', _params.maxRepeat, 2, 8),
        _buildSliderParameter(slot, 'Min ratchet', _params.minRatchet, 2, 8),
        _buildSliderParameter(slot, 'Max ratchet', _params.maxRatchet, 2, 8),
      ],
    );
  }

  Widget _buildProbabilityParameters(Slot slot) {
    return Column(
      children: [
        _buildProbabilitySlider(
          slot,
          'Note probability',
          _params.noteProbability,
        ),
        _buildProbabilitySlider(
          slot,
          'Tie probability',
          _params.tieProbability,
        ),
        _buildProbabilitySlider(
          slot,
          'Accent probability',
          _params.accentProbability,
        ),
        _buildProbabilitySlider(
          slot,
          'Repeat probability',
          _params.repeatProbability,
        ),
        _buildProbabilitySlider(
          slot,
          'Ratchet probability',
          _params.ratchetProbability,
        ),
      ],
    );
  }

  Widget _buildVelocityParameter(Slot slot) {
    return _buildSliderParameter(
      slot,
      'Unaccented velocity',
      _params.unaccentedVelocity,
      1,
      127,
    );
  }

  Widget _buildSliderParameter(
    Slot slot,
    String label,
    int? paramNum,
    int minValue,
    int maxValue, {
    bool showMidiNote = false,
  }) {
    if (paramNum == null) return const SizedBox.shrink();

    final value = slot.values[paramNum].value;

    return ListTile(
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Slider(
            value: value.toDouble(),
            min: minValue.toDouble(),
            max: maxValue.toDouble(),
            divisions: maxValue - minValue,
            label: showMidiNote ? _midiNoteToString(value) : '$value',
            semanticFormatterCallback: (v) =>
                showMidiNote ? _midiNoteToString(v.round()) : '${v.round()}',
            onChanged: (newValue) {
              _updateParameter(paramNum, newValue.toInt());
            },
          ),
          ExcludeSemantics(
            child: Text(
              showMidiNote ? _midiNoteToString(value) : '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProbabilitySlider(Slot slot, String label, int? paramNum) {
    if (paramNum == null) return const SizedBox.shrink();

    // Read current value from slot (0-127 firmware range)
    final rawValue = slot.values[paramNum].value;

    // Convert to UI range (0-100%)
    final percentage = (rawValue / 127 * 100).round();

    return ListTile(
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Slider(
            value: percentage.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$percentage%',
            semanticFormatterCallback: (v) => '${v.round()}%',
            onChanged: (value) {
              // Convert UI range (0-100%) back to firmware range (0-127)
              final firmwareValue = (value / 100 * 127).round();
              _updateParameter(paramNum, firmwareValue);
            },
          ),
          ExcludeSemantics(
            child: Text(
              '$percentage%',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _midiNoteToString(int midiNote) {
    const noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final octave = (midiNote ~/ 12) - 1;
    final noteName = noteNames[midiNote % 12];
    return '$noteName$octave ($midiNote)';
  }

  void _updateParameter(int paramNum, int value) {
    final cubit = context.read<DistingCubit>();
    cubit.updateParameterValue(
      algorithmIndex: widget.slotIndex,
      parameterNumber: paramNum,
      value: value,
      userIsChangingTheValue: true,
    );
  }
}
