import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_limits.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/performance_page_item.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/midi_listener/midi_detector_widget.dart';
import 'package:nt_helper/ui/midi_listener/midi_listener_cubit.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/ui/widgets/digit_shortcut_blocker.dart';
import 'package:nt_helper/ui/widgets/mapping_range_slider.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

class PackedMappingDataEditor extends StatefulWidget {
  final PackedMappingData initialData;
  final Future<void> Function(PackedMappingData) onSave;
  final Future<void> Function(PackedMappingData)? onSaveImmediately;
  final List<Slot> slots;
  final int algorithmIndex;
  final int parameterNumber;
  final int parameterMin;
  final int parameterMax;
  final int powerOfTen;
  final String? unitString;

  const PackedMappingDataEditor({
    super.key,
    required this.initialData,
    required this.onSave,
    this.onSaveImmediately,
    required this.slots,
    required this.algorithmIndex,
    required this.parameterNumber,
    required this.parameterMin,
    required this.parameterMax,
    required this.powerOfTen,
    this.unitString,
  });

  @override
  PackedMappingDataEditorState createState() => PackedMappingDataEditorState();
}

class PackedMappingDataEditorState extends State<PackedMappingDataEditor>
    with SingleTickerProviderStateMixin {
  static int? _lastTabIndex;

  late TabController _tabController;

  // We'll keep a local copy of the data that we can edit
  late PackedMappingData _data;

  // CV range state (replaces volts/delta text controllers)
  late int _cvRangeMin;
  late int _cvRangeMax;

  // MIDI
  late TextEditingController _midiCcController;
  late TextEditingController _midiMinController;
  late TextEditingController _midiMaxController;

  // I2C
  late TextEditingController _i2cCcController;
  late TextEditingController _i2cMinController;
  late TextEditingController _i2cMaxController;

  // The Cubit owns save debouncing. This timer only advances the visible
  // indicator from "changes pending" to "saving".
  Timer? _saveStatusTimer;
  static const _saveStatusDelay = Duration(seconds: 1);
  int _saveGeneration = 0;

  // Dirty state tracking
  bool _isDirty = false;
  bool _isSaving = false;

  // Parameter value preview during range slider drag
  DateTime? _lastPreviewSent;
  static const _previewThrottleDuration = Duration(milliseconds: 100);
  DateTime? _lastUnsupportedExpressiveMidiWarningAt;
  static const _unsupportedExpressiveMidiWarningDebounce = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();

    _data = widget.initialData;

    // Auto-default MIDI fields for new mappings
    final bool isNewMidiMapping =
        (_data.midiMin == 0 && _data.midiMax == 0 && !_data.isMidiEnabled) ||
        (_data.midiMin == -1 && _data.midiMax == -1);
    if (isNewMidiMapping && widget.parameterMin < widget.parameterMax) {
      _data = _data.copyWith(
        midiCC: _data.midiCC < 0 ? 0 : _data.midiCC,
        midiMin: widget.parameterMin,
        midiMax: widget.parameterMax,
      );
    } else if (_data.midiCC < 0) {
      _data = _data.copyWith(midiCC: 0);
    }

    // Auto-default I2C fields for new mappings
    final bool isNewI2cMapping =
        (_data.i2cMin == 0 && _data.i2cMax == 0 && !_data.isI2cEnabled) ||
        (_data.i2cMin == -1 && _data.i2cMax == -1);
    if (isNewI2cMapping && widget.parameterMin < widget.parameterMax) {
      _data = _data.copyWith(
        i2cCC: _data.i2cCC < 0 ? 0 : _data.i2cCC,
        i2cMin: widget.parameterMin,
        i2cMax: widget.parameterMax,
      );
    } else if (_data.i2cCC < 0) {
      _data = _data.copyWith(i2cCC: 0);
    }

    // Auto-default CV range for new mappings
    final bool isNewCvMapping =
        (_data.volts == -1) || (_data.volts == 0 && _data.delta == 0);
    if (isNewCvMapping && widget.parameterMin < widget.parameterMax) {
      _cvRangeMin = widget.parameterMin;
      _cvRangeMax = widget.parameterMax;
      final depth = widget.parameterMax - widget.parameterMin;
      _data = _data.copyWith(volts: 5, delta: depth);
    } else {
      // Derive range from existing volts/delta
      final depth = _data.isUnipolar ? _data.delta : _data.delta * 2;
      _cvRangeMin = widget.parameterMin;
      _cvRangeMax = (widget.parameterMin + depth).clamp(
        widget.parameterMin,
        widget.parameterMax,
      );
    }

    // Decide which tab should be displayed first.
    int initialIndex;
    if (_data.cvInput != 0) {
      // CV is in use
      initialIndex = 0;
    } else if (_data.isMidiEnabled) {
      // MIDI is in use
      initialIndex = 1;
    } else if (_data.isI2cEnabled) {
      // I2C is in use
      initialIndex = 2;
    } else if (_data.perfPageIndex > 0) {
      // Performance page is assigned
      initialIndex = 3;
    } else {
      // No mapping configured — use last selected tab if available
      initialIndex = _lastTabIndex ?? 0;
    }

    // Create the TabController with initialIndex set to the matching page.
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _lastTabIndex = _tabController.index;
      }
    });

    // Initialize controllers with the existing data
    _midiCcController = TextEditingController(text: _data.midiCC.toString());
    _midiMinController = TextEditingController(text: _data.midiMin.toString());
    _midiMaxController = TextEditingController(text: _data.midiMax.toString());
    _i2cCcController = TextEditingController(text: _data.i2cCC.toString());
    _i2cMinController = TextEditingController(text: _data.i2cMin.toString());
    _i2cMaxController = TextEditingController(text: _data.i2cMax.toString());
  }

  @override
  void dispose() {
    _saveStatusTimer?.cancel();
    _tabController.dispose();

    // Dispose controllers
    _midiCcController.dispose();
    _midiMinController.dispose();
    _midiMaxController.dispose();
    _i2cCcController.dispose();
    _i2cMinController.dispose();
    _i2cMaxController.dispose();

    super.dispose();
  }

  void _previewParameterValue(int value) {
    final now = DateTime.now();
    if (_lastPreviewSent == null ||
        now.difference(_lastPreviewSent!) > _previewThrottleDuration) {
      _lastPreviewSent = now;
      context.read<DistingCubit>().updateParameterValue(
        algorithmIndex: widget.algorithmIndex,
        parameterNumber: widget.parameterNumber,
        value: value,
        userIsChangingTheValue: true,
      );
    }
  }

  void _restoreParameterValue() {
    final state = context.read<DistingCubit>().state;
    if (state is DistingStateSynchronized) {
      final currentValue = state
          .slots[widget.algorithmIndex]
          .values[widget.parameterNumber]
          .value;
      context.read<DistingCubit>().updateParameterValue(
        algorithmIndex: widget.algorithmIndex,
        parameterNumber: widget.parameterNumber,
        value: currentValue,
        userIsChangingTheValue: false,
      );
    }
  }

  void _triggerOptimisticSave({bool force = false}) {
    _syncDataFromControllers();
    final generation = ++_saveGeneration;

    setState(() {
      _isDirty = true;
      _isSaving = force;
    });
    _saveStatusTimer?.cancel();
    if (force) {
      final save = widget.onSaveImmediately ?? widget.onSave;
      unawaited(_trackSave(Future.sync(() => save(_data)), generation));
    } else {
      _saveStatusTimer = Timer(_saveStatusDelay, () {
        if (!mounted || generation != _saveGeneration) return;
        setState(() {
          _isSaving = true;
        });
      });
      unawaited(
        _trackSave(Future.sync(() => widget.onSave(_data)), generation),
      );
    }
  }

  void _syncDataFromControllers() {
    final midiCC = (int.tryParse(_midiCcController.text) ?? _data.midiCC).clamp(
      0,
      _data.version >= 7 ? 127 : 128,
    );
    final midiMin = (int.tryParse(_midiMinController.text) ?? _data.midiMin)
        .clamp(-32768, 32767);
    final midiMax = (int.tryParse(_midiMaxController.text) ?? _data.midiMax)
        .clamp(-32768, 32767);
    final i2cCC = int.tryParse(_i2cCcController.text) ?? _data.i2cCC;
    final i2cMin = int.tryParse(_i2cMinController.text) ?? _data.i2cMin;
    final i2cMax = int.tryParse(_i2cMaxController.text) ?? _data.i2cMax;

    _data = _data.copyWith(
      midiCC: midiCC,
      midiMin: midiMin,
      midiMax: midiMax,
      i2cCC: i2cCC,
      i2cMin: i2cMin,
      i2cMax: i2cMax,
    );
  }

  Future<void> _trackSave(Future<void> save, int generation) async {
    try {
      await save;

      if (mounted && generation == _saveGeneration) {
        _saveStatusTimer?.cancel();
        setState(() {
          _isDirty = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _saveGeneration) {
        _saveStatusTimer?.cancel();
        setState(() {
          _isSaving = false;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Failed to save changes',
          TextDirection.ltr,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 450, // keep the bottom sheet from being too tall
      child: Column(
        children: [
          Stack(
            children: [
              TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).colorScheme.onSurface,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withAlpha(64),
                tabs: const [
                  Tab(text: 'CV'),
                  Tab(text: 'MIDI'),
                  Tab(text: 'I2C'),
                  Tab(text: 'Performance'),
                ],
              ),
              if (_isDirty || _isSaving)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: _isSaving ? 'Saving changes' : 'Unsaved changes',
                      child: Tooltip(
                        message: _isSaving ? 'Saving...' : 'Unsaved changes',
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isSaving
                                ? context.appColors.info.color
                                : context.appColors.warning.color,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCvEditor(),
                _buildMidiEditor(),
                _buildI2cEditor(),
                _buildPerformanceEditor(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ---------------------
  /// CV Editor
  /// ---------------------
  Widget _buildCvEditor() {
    final state = context.read<DistingCubit>().state;
    final deviceIoProfile = state is DistingStateSynchronized
        ? state.deviceIoProfile
        : DeviceIoProfile.distingLegacy;

    // Safely clamp the source value for the dropdown
    final maxSourceValue = DistingLimits.maxPresetSlots + 1;
    final sourceValue = (_data.source >= 0 && _data.source <= maxSourceValue)
        ? _data.source
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SafeArea(
        child: Column(
          children: [
            // Source Dropdown
            SizedBox(
              width: double.infinity,
              child: DropdownMenu<int>(
                initialSelection: sourceValue,
                requestFocusOnTap: false,
                label: const Text('Source'),
                onSelected: (newValue) {
                  if (newValue == null) return;
                  setState(() {
                    _data = _data.copyWith(source: newValue);
                  });
                  _triggerOptimisticSave();
                },
                dropdownMenuEntries: List.generate(
                  DistingLimits.maxPresetSlots + 2,
                  (index) {
                    if (index == 0) {
                      return const DropdownMenuEntry<int>(
                        value: 0,
                        label: 'Own inputs',
                      );
                    } else if (index == 1) {
                      return const DropdownMenuEntry<int>(
                        value: 1,
                        label: 'Module inputs',
                      );
                    } else {
                      // index 2..41 correspond to slots 1..40
                      final slotNumber = index - 1;
                      String label = 'Slot $slotNumber'; // Default label
                      // Check if a slot exists at this index (0-based)
                      if (slotNumber - 1 >= 0 &&
                          slotNumber - 1 < widget.slots.length) {
                        final slot = widget.slots[slotNumber - 1];
                        // Use algorithm name if available
                        label = 'Slot $slotNumber: ${slot.algorithm.name}';
                      }

                      return DropdownMenuEntry<int>(value: index, label: label);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Shared grouped bus picker for CV Input.
            SizedBox(
              width: double.infinity,
              child: BusSelectionField(
                label: 'CV Input',
                model: BusSelectionModel.fromProfile(
                  deviceIoProfile: deviceIoProfile,
                  currentValue: _data.cvInput,
                  minimum: 0,
                  maximum: deviceIoProfile.maxBus,
                  allowNone: true,
                ),
                onChanged: (newValue) {
                  setState(() {
                    _data = _data.copyWith(cvInput: newValue);
                  });
                  _triggerOptimisticSave();
                },
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Unipolar'),
              value: _data.isUnipolar,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() {
                  _data = _data.copyWith(isUnipolar: val);
                  final depth = val ? _data.delta : _data.delta * 2;
                  _cvRangeMin = widget.parameterMin;
                  _cvRangeMax = (widget.parameterMin + depth).clamp(
                    widget.parameterMin,
                    widget.parameterMax,
                  );
                });
                _triggerOptimisticSave();
              },
            ),
            SwitchListTile(
              title: const Text('Gate'),
              value: _data.isGate,
              dense: true,
              contentPadding: EdgeInsets.zero,
              onChanged: (val) {
                setState(() {
                  _data = _data.copyWith(isGate: val);
                });
                _triggerOptimisticSave();
              },
            ),
            Row(
              children: [
                const Text('CV Voltage'),
                Expanded(
                  child: Slider(
                    value: _data.volts.clamp(1, 10).toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${_data.volts.clamp(1, 10)}V',
                    onChanged: (val) {
                      setState(() {
                        _data = _data.copyWith(volts: val.round());
                      });
                      _triggerOptimisticSave();
                    },
                  ),
                ),
                Text('${_data.volts.clamp(1, 10)}V'),
              ],
            ),
            _buildRangeSlider(
              minValue: _cvRangeMin,
              maxValue: _cvRangeMax,
              onChanged: (rawMin, rawMax) {
                final previousMin = _cvRangeMin;
                setState(() {
                  _cvRangeMin = rawMin;
                  _cvRangeMax = rawMax;
                  final depth = rawMax - rawMin;
                  final delta = _data.isUnipolar ? depth : depth ~/ 2;
                  _data = _data.copyWith(delta: delta);
                });
                _triggerOptimisticSave();
                final previewValue = (rawMin != previousMin) ? rawMin : rawMax;
                _previewParameterValue(previewValue);
              },
              onChangeEnd: (_, _) {
                _restoreParameterValue();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// ---------------------
  /// MIDI Editor
  /// ---------------------
  Widget _buildMidiEditor() {
    final supportsExpressiveMidiMapping = _supportsExpressiveMidiMapping();
    final expressiveMappingSelected = _isExpressiveMidiType(
      _data.midiMappingType,
    );
    final showExpressiveMidiTypes =
        supportsExpressiveMidiMapping || expressiveMappingSelected;
    final midiTypeEntries = _midiTypeEntries(showExpressiveMidiTypes);

    // Safely clamp the current MIDI channel to 0..15
    final midiChannelValue = (_data.midiChannel >= 0 && _data.midiChannel <= 15)
        ? _data.midiChannel
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          // Material 3 DropdownMenu for MIDI Channel
          SizedBox(
            width: double.infinity,
            child: DropdownMenu<int>(
              initialSelection: midiChannelValue,
              requestFocusOnTap: false,
              label: Text("MIDI Channel"),
              onSelected: (newValue) {
                if (newValue == null) return;
                if (_warnIfUnsupportedExpressiveMidiControlEdit()) return;
                setState(() {
                  _data = _data.copyWith(midiChannel: newValue);
                });
                _triggerOptimisticSave();
              },
              dropdownMenuEntries: List.generate(16, (index) {
                // 0..15 = Ch 1..16
                return DropdownMenuEntry<int>(
                  value: index,
                  label: 'Ch ${index + 1}',
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          // MIDI Mapping Type Dropdown
          SizedBox(
            width: double.infinity,
            child: DropdownMenu<MidiMappingType>(
              initialSelection: _data.midiMappingType,
              requestFocusOnTap: false,
              label: const Text("MIDI Type"),
              onSelected: (newValue) {
                if (newValue == null) return;
                if (_isExpressiveMidiType(newValue) &&
                    !supportsExpressiveMidiMapping) {
                  _announceUnsupportedExpressiveMidiMapping();
                  return;
                }
                setState(() {
                  _data = _data.copyWith(
                    midiMappingType: newValue,
                    midiCC: _isExpressiveMidiType(newValue) ? 0 : _data.midiCC,
                    version: _mappingVersionForType(newValue),
                  );
                  // If type is not CC, disable relative
                  if (newValue != MidiMappingType.cc) {
                    _data = _data.copyWith(isMidiRelative: false);
                  }
                  _midiCcController.text = _data.midiCC.toString();
                });
                _triggerOptimisticSave();
              },
              dropdownMenuEntries: midiTypeEntries,
            ),
          ),
          const SizedBox(height: 12),
          _buildNumericField(
            label: expressiveMappingSelected
                ? 'MIDI CC / Note (ignored)'
                : _data.version >= 7
                ? 'MIDI CC / Note (0-127)'
                : 'MIDI CC / Note (0-128)',
            controller: _midiCcController,
            onSubmit: _updateMidiCcFromController,
            onChanged: expressiveMappingSelected
                ? null
                : _triggerOptimisticSave,
            enabled: !expressiveMappingSelected,
          ),
          SwitchListTile(
            title: const Text('MIDI Enabled'),
            value: _data.isMidiEnabled,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              if (_warnIfUnsupportedExpressiveMidiControlEdit()) return;
              setState(() {
                _data = _data.copyWith(isMidiEnabled: val);
              });
              _triggerOptimisticSave();
            },
          ),
          SwitchListTile(
            title: const Text('MIDI Symmetric'),
            value: _data.isMidiSymmetric,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              if (_warnIfUnsupportedExpressiveMidiControlEdit()) return;
              setState(() {
                _data = _data.copyWith(isMidiSymmetric: val);
              });
              _triggerOptimisticSave();
            },
          ),
          SwitchListTile(
            title: const Text('MIDI Relative'),
            value: _data.isMidiRelative,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: _data.midiMappingType == MidiMappingType.cc
                ? (val) {
                    setState(() {
                      _data = _data.copyWith(isMidiRelative: val);
                    });
                    _triggerOptimisticSave();
                  }
                : null,
          ),
          if (_data.midiMappingType != MidiMappingType.cc)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                '(N/A for notes, 14-bit CC, pitch bend, and channel pressure)',
                style: TextStyle(
                  color: Theme.of(context).disabledColor,
                  fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
                ),
              ),
            ),
          _buildRangeSlider(
            minValue: _data.midiMin,
            maxValue: _data.midiMax,
            onChanged: (rawMin, rawMax) {
              if (_warnIfUnsupportedExpressiveMidiControlEdit()) return;
              final previousMin = _data.midiMin;
              setState(() {
                _data = _data.copyWith(midiMin: rawMin, midiMax: rawMax);
                _midiMinController.text = rawMin.toString();
                _midiMaxController.text = rawMax.toString();
              });
              _triggerOptimisticSave();
              // Preview whichever thumb moved
              final previewValue = (rawMin != previousMin) ? rawMin : rawMax;
              _previewParameterValue(previewValue);
            },
            onChangeEnd: (_, _) {
              _restoreParameterValue();
            },
          ),
          // Add the MIDI Detector
          MidiDetectorWidget(
            onMidiEventFound:
                ({
                  required MidiEventType type,
                  required channel,
                  required number,
                }) {
                  // Determine the mapping type from the detected event type
                  MidiMappingType detectedMappingType = MidiMappingType.cc;
                  if (type == MidiEventType.noteOn ||
                      type == MidiEventType.noteOff) {
                    if (_data.midiMappingType !=
                            MidiMappingType.noteMomentary &&
                        _data.midiMappingType != MidiMappingType.noteToggle) {
                      detectedMappingType = MidiMappingType.noteMomentary;
                    } else {
                      detectedMappingType = _data.midiMappingType;
                    }
                  } else if (type == MidiEventType.cc14BitLowFirst) {
                    detectedMappingType = MidiMappingType.cc14BitLow;
                  } else if (type == MidiEventType.cc14BitHighFirst) {
                    detectedMappingType = MidiMappingType.cc14BitHigh;
                  } else if (type == MidiEventType.nrpn) {
                    // NRPN supplies the mapping address, while the selected
                    // CC type determines whether its value is 7- or 14-bit.
                    if (_data.midiMappingType == MidiMappingType.cc14BitLow ||
                        _data.midiMappingType == MidiMappingType.cc14BitHigh) {
                      detectedMappingType = _data.midiMappingType;
                    }
                  } else if (type == MidiEventType.pitchBend) {
                    if (!supportsExpressiveMidiMapping) {
                      _announceUnsupportedExpressiveMidiMapping();
                      return;
                    }
                    detectedMappingType = MidiMappingType.pitchBend;
                  } else if (type == MidiEventType.channelPressure) {
                    if (!supportsExpressiveMidiMapping) {
                      _announceUnsupportedExpressiveMidiMapping();
                      return;
                    }
                    detectedMappingType = MidiMappingType.channelPressure;
                  }

                  final detectedNumber =
                      _isExpressiveMidiType(detectedMappingType) ? 0 : number;

                  // Skip save if nothing actually changed
                  if (_data.midiMappingType == detectedMappingType &&
                      _data.midiCC == detectedNumber &&
                      _data.midiChannel == channel &&
                      _data.isMidiEnabled) {
                    return;
                  }

                  setState(() {
                    _data = _data.copyWith(
                      midiMappingType: detectedMappingType,
                      midiCC: detectedNumber,
                      midiChannel: channel,
                      isMidiEnabled: true,
                      isMidiRelative: detectedMappingType == MidiMappingType.cc
                          ? _data.isMidiRelative
                          : false,
                      version: _mappingVersionForType(detectedMappingType),
                    );
                  });
                  _midiCcController.text = detectedNumber.toString();
                  _triggerOptimisticSave(force: true);
                },
          ),
        ],
      ),
    );
  }

  bool _supportsExpressiveMidiMapping() {
    final state = context.read<DistingCubit>().state;
    return state is DistingStateSynchronized &&
        state.firmwareVersion.hasExpressiveMidiMapping;
  }

  bool _isExpressiveMidiType(MidiMappingType type) {
    return type == MidiMappingType.pitchBend ||
        type == MidiMappingType.channelPressure;
  }

  bool _warnIfUnsupportedExpressiveMidiControlEdit() {
    if (_isExpressiveMidiType(_data.midiMappingType) &&
        !_supportsExpressiveMidiMapping()) {
      _announceUnsupportedExpressiveMidiMapping();
      return true;
    }
    return false;
  }

  int _mappingVersionForType(MidiMappingType type) {
    if (_isExpressiveMidiType(type) && _supportsExpressiveMidiMapping()) {
      return 7;
    }
    return _data.version;
  }

  List<DropdownMenuEntry<MidiMappingType>> _midiTypeEntries(
    bool includeExpressiveTypes,
  ) {
    return [
      const DropdownMenuEntry<MidiMappingType>(
        value: MidiMappingType.cc,
        label: 'CC',
      ),
      const DropdownMenuEntry<MidiMappingType>(
        value: MidiMappingType.noteMomentary,
        label: 'Note - Momentary',
      ),
      const DropdownMenuEntry<MidiMappingType>(
        value: MidiMappingType.noteToggle,
        label: 'Note - Toggle',
      ),
      const DropdownMenuEntry<MidiMappingType>(
        value: MidiMappingType.cc14BitLow,
        label: '14 bit CC - low',
      ),
      const DropdownMenuEntry<MidiMappingType>(
        value: MidiMappingType.cc14BitHigh,
        label: '14 bit CC - high',
      ),
      if (includeExpressiveTypes) ...const [
        DropdownMenuEntry<MidiMappingType>(
          value: MidiMappingType.pitchBend,
          label: 'Pitch bend',
        ),
        DropdownMenuEntry<MidiMappingType>(
          value: MidiMappingType.channelPressure,
          label: 'Channel pressure',
        ),
      ],
    ];
  }

  void _announceUnsupportedExpressiveMidiMapping() {
    final now = DateTime.now();
    final lastWarning = _lastUnsupportedExpressiveMidiWarningAt;
    if (lastWarning != null &&
        now.difference(lastWarning) <
            _unsupportedExpressiveMidiWarningDebounce) {
      return;
    }
    _lastUnsupportedExpressiveMidiWarningAt = now;

    const message =
        'Pitch bend and channel pressure mappings require firmware 1.17 or newer.';
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(message)));
  }

  void _updateMidiCcFromController() {
    final parsed = int.tryParse(_midiCcController.text) ?? _data.midiCC;
    final clamped = parsed.clamp(0, _data.version >= 7 ? 127 : 128);
    setState(() {
      _data = _data.copyWith(midiCC: clamped);
    });
    if (_midiCcController.text != _data.midiCC.toString()) {
      _midiCcController.text = _data.midiCC.toString();
    }
  }

  /// ---------------------
  /// I2C Editor
  /// ---------------------
  Widget _buildI2cEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          _buildNumericField(
            label: 'I2C CC',
            controller: _i2cCcController,
            onSubmit: _updateI2cCcFromController,
            onChanged: _triggerOptimisticSave,
          ),
          SwitchListTile(
            title: const Text('I2C Enabled'),
            value: _data.isI2cEnabled,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                _data = _data.copyWith(isI2cEnabled: val);
              });
              _triggerOptimisticSave();
            },
          ),
          SwitchListTile(
            title: const Text('I2C Symmetric'),
            value: _data.isI2cSymmetric,
            dense: true,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() {
                _data = _data.copyWith(isI2cSymmetric: val);
              });
              _triggerOptimisticSave();
            },
          ),
          _buildRangeSlider(
            minValue: _data.i2cMin,
            maxValue: _data.i2cMax,
            onChanged: (rawMin, rawMax) {
              final previousMin = _data.i2cMin;
              setState(() {
                _data = _data.copyWith(i2cMin: rawMin, i2cMax: rawMax);
                _i2cMinController.text = rawMin.toString();
                _i2cMaxController.text = rawMax.toString();
              });
              _triggerOptimisticSave();
              // Preview whichever thumb moved
              final previewValue = (rawMin != previousMin) ? rawMin : rawMax;
              _previewParameterValue(previewValue);
            },
            onChangeEnd: (_, _) {
              _restoreParameterValue();
            },
          ),
        ],
      ),
    );
  }

  void _updateI2cCcFromController() {
    final parsed = int.tryParse(_i2cCcController.text) ?? _data.i2cCC;
    setState(() {
      _data = _data.copyWith(i2cCC: parsed);
    });
    if (_i2cCcController.text != _data.i2cCC.toString()) {
      _i2cCcController.text = _data.i2cCC.toString();
    }
  }

  /// ---------------------
  /// Performance Editor
  /// ---------------------
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

  Widget _buildPerformanceEditor() {
    return BlocBuilder<DistingCubit, DistingState>(
      builder: (context, state) {
        if (state is! DistingStateSynchronized) {
          return const Center(child: Text('Not synchronized'));
        }

        final usePerfPageItems = state.firmwareVersion.hasPerfPageItems;

        if (usePerfPageItems) {
          return _buildPerformanceEditorV116(context, state);
        } else {
          return _buildPerformanceEditorLegacy(context, state);
        }
      },
    );
  }

  Widget _buildPerformanceEditorLegacy(
    BuildContext context,
    DistingStateSynchronized state,
  ) {
    final slot = state.slots[widget.algorithmIndex];
    final currentPerfPageIndex =
        slot.mappings[widget.parameterNumber].packedMappingData.perfPageIndex;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign this parameter to a performance page for quick access.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DropdownMenu<int>(
            initialSelection: currentPerfPageIndex,
            label: const Text('Performance Page'),
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              const DropdownMenuEntry<int>(value: 0, label: 'None'),
              for (int i = 1; i <= 15; i++)
                DropdownMenuEntry<int>(
                  value: i,
                  label: 'P$i',
                  leadingIcon: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getPageColors(i).color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'P$i',
                      style: TextStyle(
                        color: _getPageColors(i).onColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
            onSelected: (newValue) {
              if (newValue == null) return;
              context.read<DistingCubit>().setPerformancePageMapping(
                widget.algorithmIndex,
                widget.parameterNumber,
                newValue,
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            currentPerfPageIndex == 0
                ? 'Not assigned to any performance page'
                : 'Assigned to Performance Page $currentPerfPageIndex',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceEditorV116(
    BuildContext context,
    DistingStateSynchronized state,
  ) {
    final currentDisplayIndex = _findPerfItemDisplayIndex(
      state.perfPageItems,
      widget.algorithmIndex,
      widget.parameterNumber,
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign this parameter to a performance index for quick access.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          DropdownMenu<int>(
            initialSelection: currentDisplayIndex,
            label: const Text('Performance Index'),
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              const DropdownMenuEntry<int>(value: 0, label: 'None'),
              for (int i = 1; i <= 30; i++)
                DropdownMenuEntry<int>(
                  value: i,
                  label: '$i',
                  leadingIcon: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getPageColors(i).color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '$i',
                      style: TextStyle(
                        color: _getPageColors(i).onColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
            onSelected: (newValue) {
              if (newValue == null) return;
              final cubit = context.read<DistingCubit>();
              final oldDisplayIndex = currentDisplayIndex;
              final slot = state.slots[widget.algorithmIndex];
              final paramName = slot.parameters[widget.parameterNumber].name;
              final algoName = slot.algorithm.name;

              if (oldDisplayIndex > 0 && newValue == 0) {
                cubit.removePerfPageItem(oldDisplayIndex - 1);
              } else if (oldDisplayIndex > 0 && newValue != oldDisplayIndex) {
                cubit.removePerfPageItem(oldDisplayIndex - 1);
                cubit.setPerfPageItem(
                  PerformancePageItem(
                    itemIndex: newValue - 1,
                    enabled: true,
                    slotIndex: widget.algorithmIndex,
                    parameterNumber: widget.parameterNumber,
                    min: widget.parameterMin,
                    max: widget.parameterMax,
                    upperLabel: algoName,
                    lowerLabel: paramName,
                  ),
                );
              } else if (oldDisplayIndex == 0 && newValue > 0) {
                cubit.setPerfPageItem(
                  PerformancePageItem(
                    itemIndex: newValue - 1,
                    enabled: true,
                    slotIndex: widget.algorithmIndex,
                    parameterNumber: widget.parameterNumber,
                    min: widget.parameterMin,
                    max: widget.parameterMax,
                    upperLabel: algoName,
                    lowerLabel: paramName,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 16),
          Text(
            currentDisplayIndex == 0
                ? 'Not assigned to any performance index'
                : 'Assigned to Performance Index $currentDisplayIndex',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get color for page badges (matches section_parameter_list_view.dart and performance_screen.dart)
  AppColorPair _getPageColors(int pageIndex) {
    return context.appColors.categoricalAt(pageIndex - 1);
  }

  /// ---------------------
  /// Range Slider
  /// ---------------------
  Widget _buildRangeSlider({
    required int minValue,
    required int maxValue,
    required void Function(int rawMin, int rawMax) onChanged,
    void Function(int rawMin, int rawMax)? onChangeEnd,
  }) {
    return MappingRangeSlider(
      minValue: minValue,
      maxValue: maxValue,
      parameterMin: widget.parameterMin,
      parameterMax: widget.parameterMax,
      powerOfTen: widget.powerOfTen,
      unitString: widget.unitString,
      onChanged: onChanged,
      onChangeEnd: onChangeEnd,
    );
  }

  /// ---------------------
  /// Helpers
  /// ---------------------
  /// Builds a labeled numeric TextField that calls [onSubmit]
  /// when the user presses the "done" button on the keyboard
  Widget _buildNumericField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onSubmit,
    VoidCallback? onChanged,
    bool signed = false,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: DigitShortcutBlocker(
        child: TextField(
          enabled: enabled,
          keyboardType: signed
              ? const TextInputType.numberWithOptions(signed: true)
              : TextInputType.number,
          textInputAction: TextInputAction.done,
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => onSubmit(),
          onChanged: onChanged != null ? (_) => onChanged() : null,
        ),
      ),
    );
  }
}
