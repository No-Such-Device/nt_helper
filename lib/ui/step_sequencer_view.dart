import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/scale_quantizer.dart';
import 'package:nt_helper/services/step_sequencer_params.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/parameter_pages_view.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/playback_controls.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/quantize_controls.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/randomize_settings_dialog.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/sequence_selector.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_column_widget.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/step_grid_view.dart';
import 'package:nt_helper/ui/widgets/step_sequencer/sync_status_indicator.dart';
import 'package:nt_helper/util/parameter_write_debouncer.dart';

/// Custom widget view for Step Sequencer algorithm (GUID: 'spsq')
///
/// Displays a visual grid interface with 16 step columns with global parameter mode selector.
/// Users can edit all 16 steps for a single parameter at once (like a DAW automation lane).
/// Includes scale quantization controls for musical pitch mapping.
class StepSequencerView extends StatefulWidget {
  final Slot slot;
  final FirmwareVersion firmwareVersion;
  final int slotIndex;

  const StepSequencerView({
    super.key,
    required this.slot,
    required this.firmwareVersion,
    required this.slotIndex,
  });

  @override
  State<StepSequencerView> createState() => _StepSequencerViewState();
}

/// Undo history entry for parameter changes
class _UndoHistoryEntry {
  final List<_ParameterChange> changes;
  final DateTime timestamp;

  _UndoHistoryEntry(this.changes) : timestamp = DateTime.now();
}

/// Individual parameter change
class _ParameterChange {
  final int parameterNumber;
  final int oldValue;
  final int newValue;

  _ParameterChange({
    required this.parameterNumber,
    required this.oldValue,
    required this.newValue,
  });
}

class _StepSequencerViewState extends State<StepSequencerView> {
  // Global parameter mode state (affects all 16 steps)
  late StepParameter _activeParameter = StepParameter.pitch;

  // Local state for quantization settings (UI-only, not persisted)
  bool _snapEnabled = false;
  String _selectedScale = 'Major';
  int _rootNote = 0; // C

  // Undo history for quantization operations
  final List<_UndoHistoryEntry> _undoHistory = [];
  static const int _maxUndoHistory = 10;

  // Loading state for sequence selection
  bool _isLoadingSequence = false;

  // Sync status tracking
  final _debouncer = ParameterWriteDebouncer();
  SyncStatus _syncStatus = SyncStatus.synced;
  String? _lastError;

  /// Gets current sequence value from slot parameter
  int _getCurrentSequence(Slot slot) {
    final params = StepSequencerParams.fromSlot(slot);
    final sequenceParamNum = params.currentSequence;

    if (sequenceParamNum != null && sequenceParamNum < slot.values.length) {
      final sequenceValue = slot.values[sequenceParamNum].value;
      if (sequenceValue >= 0 && sequenceValue < 32) {
        return sequenceValue;
      }
    }
    return 0; // Default to sequence 0
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return BlocBuilder<DistingCubit, DistingState>(
        builder: (context, state) {
          // Determine if we're offline
          final isOffline = state.maybeWhen(
            connected:
                (
                  disting,
                  inputDevice,
                  outputDevice,
                  offline,
                  loading,
                  syncStatus,
                  syncProgress,
                ) => offline,
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
                ) => offline,
            orElse: () => false,
          );

          // Update sync status based on offline state
          final effectiveSyncStatus = isOffline
              ? SyncStatus.offline
              : _syncStatus;

          return Focus(
            onKeyEvent: _handleParameterModeShortcut,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Offline banner (if offline)
                    if (isOffline) _buildOfflineBanner(context),
                    if (isOffline) const SizedBox(height: 16),

                    // Compact header row: Title, Sync Status, Overflow Menu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Step Sequencer',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SyncStatusIndicator(
                              status: effectiveSyncStatus,
                              errorMessage: _lastError,
                              onRetry: _retryFailedWrites,
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert,
                                semanticLabel: 'More options',
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'randomize',
                                  child: ListTile(
                                    leading: Icon(Icons.shuffle),
                                    title: Text('Randomize'),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'settings',
                                  child: ListTile(
                                    leading: Icon(Icons.settings),
                                    title: Text('Randomize Settings...'),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'parameter_pages',
                                  child: ListTile(
                                    leading: Icon(Icons.view_list),
                                    title: Text('Parameter Pages...'),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'randomize') {
                                  _triggerRandomize();
                                } else if (value == 'settings') {
                                  _showRandomizeSettingsDialog();
                                } else if (value == 'parameter_pages') {
                                  _showParameterPages();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row with sequence and mode selector
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: _buildSequenceSelector(widget.slot),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _buildGlobalParameterModeSelector()),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Step grid (fixed height so it doesn't shrink)
                    SizedBox(
                      height: 400,
                      child: StepGridView(
                        slot: widget.slot,
                        slotIndex: widget.slotIndex,
                        snapEnabled: _snapEnabled,
                        selectedScale: _selectedScale,
                        rootNote: _rootNote,
                        activeParameter: _activeParameter,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quantize controls (only visible in Pitch mode)
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: _activeParameter == StepParameter.pitch
                          ? Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: QuantizeControls(
                                snapEnabled: _snapEnabled,
                                selectedScale: _selectedScale,
                                rootNote: _rootNote,
                                onToggleSnap: _toggleSnapToScale,
                                onScaleChanged: _setScale,
                                onRootNoteChanged: _setRootNote,
                                onQuantizeAll: _quantizeAllSteps,
                                onUndo: _undoLastChange,
                                canUndo: _undoHistory.isNotEmpty,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (_activeParameter == StepParameter.pitch)
                      const SizedBox(height: 12),

                    // Playback controls (fixed height)
                    SizedBox(
                      height: 180,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = MediaQuery.of(context).size.width;
                          final isMobile = width <= 768;
                          final params = StepSequencerParams.fromSlot(
                            widget.slot,
                          );

                          return PlaybackControls(
                            slotIndex: widget.slotIndex,
                            params: params,
                            slot: widget.slot,
                            compact: isMobile,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      // Fallback to error message if widget fails to render
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load Step Sequencer widget',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Error: $e',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  void _toggleSnapToScale() {
    setState(() {
      _snapEnabled = !_snapEnabled;
    });
  }

  void _setScale(String scale) {
    setState(() {
      _selectedScale = scale;
    });
  }

  void _setRootNote(int root) {
    setState(() {
      _rootNote = root;
    });
  }

  /// Handle sequence selection change
  ///
  /// Updates hardware parameter and triggers slot data refresh to load new sequence
  Future<void> _handleSequenceChange(int newSequence) async {
    if (_isLoadingSequence) return; // Prevent concurrent operations

    setState(() {
      _isLoadingSequence = true;
      _syncStatus = SyncStatus.syncing;
    });

    try {
      final params = StepSequencerParams.fromSlot(widget.slot);
      final sequenceParamNum = params.currentSequence;

      if (sequenceParamNum == null) {
        if (mounted) {
          setState(() {
            _syncStatus = SyncStatus.error;
            _lastError = 'Current Sequence parameter not found';
          });
        }
        return;
      }

      // Update hardware parameter (0-31 value)
      final cubit = context.read<DistingCubit>();
      await cubit.updateParameterValue(
        algorithmIndex: widget.slotIndex,
        parameterNumber: sequenceParamNum,
        value: newSequence,
        userIsChangingTheValue: true,
      );

      // Wait for hardware to process the change
      await Future.delayed(const Duration(milliseconds: 100));

      // Request fresh parameter values from hardware after sequence change
      // This ensures we get updated disabled states and parameter values
      cubit.scheduleParameterRefresh(widget.slotIndex);

      // Update sync status
      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.synced;
          _lastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.error;
          _lastError = 'Failed to switch sequence: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSequence = false;
        });
      }
    }
  }

  Future<void> _quantizeAllSteps() async {
    if (!mounted) return;

    try {
      final params = StepSequencerParams.fromSlot(widget.slot);

      // Store changes for undo
      final changes = <_ParameterChange>[];

      // Quantize all 16 steps
      final cubit = context.read<DistingCubit>();
      for (int step = 1; step <= 16; step++) {
        final pitchParamNum = params.getPitch(step);
        if (pitchParamNum != null) {
          // Get current pitch value
          final currentPitch =
              widget.slot.values.isNotEmpty &&
                  pitchParamNum < widget.slot.values.length
              ? widget.slot.values[pitchParamNum].value
              : 60; // Default to middle C if not available

          // Quantize to scale
          final quantized = ScaleQuantizer.quantize(
            currentPitch,
            _selectedScale,
            _rootNote,
          );

          // Only update if value changed
          if (quantized != currentPitch) {
            // Store change for undo
            changes.add(
              _ParameterChange(
                parameterNumber: pitchParamNum,
                oldValue: currentPitch,
                newValue: quantized,
              ),
            );

            // Update parameter (with debouncing built into cubit)
            cubit.updateParameterValue(
              algorithmIndex: widget.slotIndex,
              parameterNumber: pitchParamNum,
              value: quantized,
              userIsChangingTheValue: true,
            );

            // Small delay to avoid overwhelming MIDI scheduler
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
      }

      if (mounted) {
        setState(() {
          // Add to undo history if any changes were made
          if (changes.isNotEmpty) {
            _undoHistory.add(_UndoHistoryEntry(changes));

            // Limit history size
            if (_undoHistory.length > _maxUndoHistory) {
              _undoHistory.removeAt(0);
            }
          }

          _syncStatus = SyncStatus.synced;
          _lastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.error;
          _lastError = 'Error quantizing steps: $e';
        });
      }
    }
  }

  /// Undo the last quantization operation
  Future<void> _undoLastChange() async {
    if (_undoHistory.isEmpty || !mounted) return;

    try {
      // Get last history entry
      final entry = _undoHistory.removeLast();

      setState(() {
        _undoHistory.remove(entry);
      });

      // Restore old values
      final cubit = context.read<DistingCubit>();
      for (final change in entry.changes) {
        cubit.updateParameterValue(
          algorithmIndex: widget.slotIndex,
          parameterNumber: change.parameterNumber,
          value: change.oldValue,
          userIsChangingTheValue: true,
        );

        // Small delay to avoid overwhelming MIDI scheduler
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.synced;
          _lastError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.error;
          _lastError = 'Error undoing changes: $e';
        });
      }
    }
  }

  void _retryFailedWrites() {
    setState(() {
      _syncStatus = SyncStatus.synced;
      _lastError = null;
    });
  }

  void _switchParameterMode(StepParameter mode) {
    setState(() {
      _activeParameter = mode;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Switched to ${mode.name} mode',
      TextDirection.ltr,
    );
  }

  KeyEventResult _handleParameterModeShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Only handle when no modifier keys are pressed (except Shift for M)
    final isShiftOnly =
        HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed;
    final noModifiers =
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed;

    StepParameter? newMode;

    if (noModifiers) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyP:
          newMode = StepParameter.pitch;
        case LogicalKeyboardKey.keyV:
          newMode = StepParameter.velocity;
        case LogicalKeyboardKey.keyG:
          newMode = StepParameter.division;
        case LogicalKeyboardKey.keyT:
          newMode = StepParameter.ties;
        case LogicalKeyboardKey.keyB:
          newMode = StepParameter.pattern;
        default:
          break;
      }
    } else if (isShiftOnly && event.logicalKey == LogicalKeyboardKey.keyM) {
      newMode = StepParameter.mod;
    }

    if (newMode != null && newMode != _activeParameter) {
      _switchParameterMode(newMode);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Triggers randomization by setting Randomise parameter to 1, waiting 100ms, then resetting to 0
  Future<void> _triggerRandomize() async {
    final params = StepSequencerParams.fromSlot(widget.slot);
    final randomiseParam = params.randomise;

    if (randomiseParam == null) {
      // Randomise parameter not found
      return;
    }

    final cubit = context.read<DistingCubit>();

    try {
      // Set trigger to 1
      await cubit.updateParameterValue(
        algorithmIndex: widget.slotIndex,
        parameterNumber: randomiseParam,
        value: 1,
        userIsChangingTheValue: true,
      );

      // Wait 100ms (allow hardware to process)
      await Future.delayed(const Duration(milliseconds: 100));

      // Reset trigger to 0
      await cubit.updateParameterValue(
        algorithmIndex: widget.slotIndex,
        parameterNumber: randomiseParam,
        value: 0,
        userIsChangingTheValue: true,
      );
    } catch (e) {
      // Error triggering randomize - silently fail
    }
  }

  /// Shows the randomize settings dialog
  void _showRandomizeSettingsDialog() {
    final cubit = context.read<DistingCubit>();
    showDialog(
      context: context,
      builder: (context) => BlocProvider.value(
        value: cubit,
        child: RandomizeSettingsDialog(
          slot: widget.slot,
          slotIndex: widget.slotIndex,
        ),
      ),
    );
  }

  /// Shows the Parameter Pages view
  ///
  /// Opens a dialog (desktop) or full-screen view (mobile) displaying
  /// parameters not covered by the custom Step Sequencer UI.
  void _showParameterPages() {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final cubit = context.read<DistingCubit>();

    if (isMobile) {
      // Mobile: Full-screen navigation
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => BlocProvider.value(
            value: cubit,
            child: ParameterPagesView(
              slot: widget.slot,
              slotIndex: widget.slotIndex,
            ),
          ),
        ),
      );
    } else {
      // Desktop: Dialog
      showDialog(
        context: context,
        builder: (context) => BlocProvider.value(
          value: cubit,
          child: ParameterPagesView(
            slot: widget.slot,
            slotIndex: widget.slotIndex,
          ),
        ),
      );
    }
  }

  /// Build global parameter mode selector
  /// Shows 10 ChoiceChip buttons for switching between parameter modes
  /// Builds sequence selector with firmware-provided enum strings
  Widget _buildSequenceSelector(Slot slot) {
    final params = StepSequencerParams.fromSlot(slot);
    final sequenceParam = params.currentSequence;

    // Get enum strings and parameter info from firmware (if available)
    List<String>? enumStrings;
    int? minValue;
    int? maxValue;

    if (sequenceParam != null) {
      if (sequenceParam < slot.enums.length) {
        final enumData = slot.enums[sequenceParam];
        if (enumData.values.isNotEmpty) {
          enumStrings = enumData.values;
        }
      }

      if (sequenceParam < slot.parameters.length) {
        final paramInfo = slot.parameters[sequenceParam];
        minValue = paramInfo.min;
        maxValue = paramInfo.max;
      }
    }

    return SequenceSelector(
      currentSequence: _getCurrentSequence(slot),
      isLoading: _isLoadingSequence,
      onSequenceChanged: _handleSequenceChange,
      enumStrings: enumStrings,
      minValue: minValue,
      maxValue: maxValue,
    );
  }

  Widget _buildGlobalParameterModeSelector() {
    const modeDefinitions = [
      (StepParameter.pitch, 'Pitch'),
      (StepParameter.velocity, 'Velocity'),
      (StepParameter.mod, 'Mod'),
      (StepParameter.division, 'Division'),
      (StepParameter.pattern, 'Pattern'),
      (StepParameter.ties, 'Ties'),
      (StepParameter.mute, 'Mute'),
      (StepParameter.skip, 'Skip'),
      (StepParameter.reset, 'Reset'),
      (StepParameter.repeat, 'Repeat'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (mode, label) in modeDefinitions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: _buildModeButton(
                mode,
                label,
                context.appColors.sequencerAt(mode.index).color,
              ),
            ),
        ],
      ),
    );
  }

  /// Build individual mode button
  Widget _buildModeButton(StepParameter mode, String label, Color color) {
    final isActive = _activeParameter == mode;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isActive,
      selectedColor: color.withValues(alpha: 0.3),
      backgroundColor: Colors.transparent,
      side: BorderSide(color: color, width: isActive ? 2 : 1),
      onSelected: (_) {
        setState(() {
          _activeParameter = mode;
        });
      },
    );
  }

  /// Build offline banner widget
  Widget _buildOfflineBanner(BuildContext context) {
    final warning = context.appColors.warning;

    return Container(
      decoration: BoxDecoration(
        color: warning.container,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warning.color, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: warning.onContainer, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Offline - editing locally',
              style: TextStyle(
                color: warning.onContainer,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
