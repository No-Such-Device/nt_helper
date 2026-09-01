import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show DisplayMode;
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/bpm_editor_widget.dart';
import 'package:nt_helper/ui/parameter_editor_registry.dart';
import 'package:nt_helper/ui/widgets/mapping_edit_button.dart';
import 'package:nt_helper/ui/widgets/parameter_value_display.dart';
import 'package:nt_helper/ui/widgets/routing_parameter_value.dart';
import 'package:nt_helper/util/extensions.dart';
import 'package:nt_helper/util/ui_helpers.dart';

class ParameterViewRow extends StatefulWidget {
  final String name;
  final int min;
  final int max;
  final int defaultValue;
  final String?
  displayString; // For additional display string instead of dropdown
  final String? unit;
  final int powerOfTen;
  final List<String>? dropdownItems; // For enums as a dropdown
  final bool isOnOff; // Whether the parameter is an "on/off" type
  final int initialValue;
  final int algorithmIndex;
  final int parameterNumber;
  final PackedMappingData? mappingData;
  final Slot slot;
  final bool isDisabled;
  final int parameterUnit; // Integer unit type for registry-based detection
  final bool isRoutingParameter; // I/O parameter whose value is a bus number
  final Object? parameterValueTraversalId;
  final double? parameterValueTraversalOrder;
  final bool parameterValueEditingEnabled;

  const ParameterViewRow({
    super.key,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.parameterNumber,
    required this.algorithmIndex,
    this.unit,
    this.powerOfTen = 0,
    this.displayString,
    this.dropdownItems,
    this.isOnOff = false,
    this.mappingData,
    required this.initialValue,
    required this.slot,
    this.isDisabled = false,
    this.parameterUnit = 0,
    this.isRoutingParameter = false,
    this.parameterValueTraversalId,
    this.parameterValueTraversalOrder,
    this.parameterValueEditingEnabled = true,
  });

  @override
  State<ParameterViewRow> createState() => _ParameterViewRowState();
}

class _ParameterViewRowState extends State<ParameterViewRow> {
  late int currentValue;
  late bool isChecked;
  bool isChanging = false;
  bool _showAlternateEditor = false;

  @override
  void initState() {
    super.initState();
    // Guard against invalid min > max (can happen with malformed parameter data)
    currentValue = widget.min <= widget.max
        ? widget.initialValue.clamp(widget.min, widget.max)
        : widget.initialValue;
    isChecked = widget.isOnOff && currentValue == 1;
  }

  @override
  void didUpdateWidget(covariant ParameterViewRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update internal state when the widget is updated
    if (widget.initialValue != oldWidget.initialValue ||
        widget.min != oldWidget.min ||
        widget.max != oldWidget.max) {
      setState(() {
        // Guard against invalid min > max (can happen with malformed parameter data)
        currentValue = widget.min <= widget.max
            ? widget.initialValue.clamp(widget.min, widget.max)
            : widget.initialValue;
        isChecked = widget.isOnOff && currentValue == 1;
      });
    }
  }

  void _updateCubitValue(int value) {
    // Send updated value to the Cubit
    context.read<DistingCubit>().updateParameterValue(
      algorithmIndex: widget.algorithmIndex,
      parameterNumber: widget.parameterNumber,
      value: value,
      userIsChangingTheValue: widget.displayString?.isNotEmpty == true
          ? false
          : isChanging,
    );
  }

  void _scheduleParameterRefresh() {
    // Schedule a debounced refresh after parameter commit
    context.read<DistingCubit>().scheduleParameterRefresh(
      widget.algorithmIndex,
    );
  }

  String _getAccessibleValueString([int? value]) {
    final v = value ?? currentValue;
    if (widget.isOnOff) return v == 1 ? 'On' : 'Off';
    if (widget.dropdownItems != null &&
        v >= 0 &&
        v < widget.dropdownItems!.length) {
      return widget.dropdownItems![v];
    }
    if (widget.displayString != null) return widget.displayString!;
    if (widget.name.toLowerCase().contains("note") && widget.unit != "%") {
      return midiNoteToNoteString(v);
    }
    if (widget.name.toLowerCase().contains("midi channel")) {
      return v == 0 ? "None" : v.toString();
    }
    if (widget.unit != null) {
      return formatWithUnit(
        v,
        name: widget.name,
        min: widget.min,
        max: widget.max,
        unit: widget.unit,
        powerOfTen: widget.powerOfTen,
      );
    }
    return v.toString();
  }

  DateTime? _lastSent;
  final Duration throttleDuration = const Duration(milliseconds: 100);

  void onSliderChanged(int value) async {
    final now = DateTime.now();
    if (_lastSent == null || now.difference(_lastSent!) > throttleDuration) {
      // Enough time has passed -> proceed
      _lastSent = now;
      _updateCubitValue(value);
    }

    if (SettingsService().hapticsEnabled) {
      Haptics.vibrate(HapticsType.light);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Check if we are on a wide screen or a smaller screen
    bool widescreen = MediaQuery.of(context).size.width > 600;

    // Determine if the unit is BPM using registry-based detection
    // Modern firmware uses unit number, legacy uses unit string
    final bool isBpmUnit = ParameterEditorRegistry.isBpmUnit(
      widget.parameterUnit,
      unitString: widget.unit,
    );

    // Check if this parameter should use a specialized file editor
    final Widget? fileEditor =
        widget.slot.parameters.length > widget.parameterNumber
        ? ParameterEditorRegistry.findEditorFor(
            slot: widget.slot,
            parameterInfo: widget.slot.parameters[widget.parameterNumber],
            parameterNumber: widget.parameterNumber,
            currentValue: currentValue,
            onValueChanged: (newValue) {
              setState(() {
                currentValue = newValue;
              });
              _updateCubitValue(newValue);
              _scheduleParameterRefresh();
            },
          )
        : null;

    final paramName = cleanTitle(widget.name);

    // Routing (I/O) parameters use the routing bus picker instead of a slider
    // and a flat enum dropdown.
    final bool isRoutingParameter = widget.isRoutingParameter;
    final bool routingShowEs5 = widget.slot.algorithm.guid == 'usbf';
    final DeviceIoProfile routingDeviceIoProfile = isRoutingParameter
        ? () {
            final state = context.read<DistingCubit>().state;
            return state is DistingStateSynchronized
                ? state.deviceIoProfile
                : DeviceIoProfile.distingLegacy;
          }()
        : DeviceIoProfile.distingLegacy;

    final innerRow = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      child: Row(
        key: ValueKey(widescreen),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MappingEditButton(parameterViewRow: widget),
          // Name column with reduced width
          Expanded(
            flex: widescreen ? 2 : 3,
            child: Semantics(
              label: paramName,
              customSemanticsActions: {
                CustomSemanticsAction(label: 'Focus on hardware display'): () {
                  var cubit = context.read<DistingCubit>();
                  cubit.disting()?.let((manager) {
                    manager.requestSetFocus(
                      widget.algorithmIndex,
                      widget.parameterNumber,
                    );
                    manager.requestSetDisplayMode(DisplayMode.parameters);
                    if (SettingsService().hapticsEnabled) {
                      Haptics.vibrate(HapticsType.medium);
                    }
                  });
                },
              },
              child: GestureDetector(
                onDoubleTap: () async {
                  var cubit = context.read<DistingCubit>();
                  cubit.disting()?.let((manager) {
                    manager.requestSetFocus(
                      widget.algorithmIndex,
                      widget.parameterNumber,
                    );
                    manager.requestSetDisplayMode(DisplayMode.parameters);
                    if (SettingsService().hapticsEnabled) {
                      Haptics.vibrate(HapticsType.medium);
                    }
                  });
                },
                onLongPress: () {
                  final manager = context.read<DistingCubit>().requireDisting();
                  manager.requestSetFocus(
                    widget.algorithmIndex,
                    widget.parameterNumber,
                  );
                  if (SettingsService().hapticsEnabled) {
                    Haptics.vibrate(HapticsType.medium);
                  }
                },
                child: Text(
                  paramName,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                  softWrap: false,
                  textAlign: TextAlign.start,
                  style: widescreen
                      ? textTheme.titleMedium
                      : textTheme.labelMedium,
                ),
              ),
            ),
          ),

          // Slider column
          Expanded(
            flex: widescreen ? 8 : 6,
            child: GestureDetector(
              onDoubleTap: () =>
                  isBpmUnit || fileEditor != null || _showAlternateEditor
                  ? () {}
                  : setState(() {
                      currentValue = widget.defaultValue;
                      _updateCubitValue(currentValue);
                    }),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: SizedBox(
                  height: 45,
                  child: isBpmUnit
                      ? BpmEditorWidget(
                          initialValue: currentValue,
                          min: widget.min,
                          max: widget.max,
                          powerOfTen: widget.powerOfTen,
                          onChanged: (newBpm) {
                            setState(() {
                              currentValue = newBpm;
                            });
                            _updateCubitValue(newBpm);
                            _scheduleParameterRefresh();
                          },
                          onEditingStatusChanged: (isEditing) {
                            setState(() {
                              isChanging = isEditing;
                            });
                          },
                        )
                      : fileEditor ??
                            (_showAlternateEditor
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Semantics(
                                        button: true,
                                        label: 'Decrease $paramName',
                                        child: OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              currentValue = min(
                                                max(
                                                  currentValue - 1,
                                                  widget.min,
                                                ),
                                                widget.max,
                                              );
                                            });
                                            _updateCubitValue(currentValue);
                                            _scheduleParameterRefresh();
                                          },
                                          child: const Text("-"),
                                        ),
                                      ),
                                      Semantics(
                                        button: true,
                                        label: 'Increase $paramName',
                                        child: OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              currentValue = min(
                                                max(
                                                  currentValue + 1,
                                                  widget.min,
                                                ),
                                                widget.max,
                                              );
                                            });
                                            _updateCubitValue(currentValue);
                                            _scheduleParameterRefresh();
                                          },
                                          child: const Text("+"),
                                        ),
                                      ),
                                    ],
                                  )
                                : Semantics(
                                    label: paramName,
                                    value: _getAccessibleValueString(),
                                    increasedValue: currentValue < widget.max
                                        ? _getAccessibleValueString(
                                            currentValue + 1,
                                          )
                                        : null,
                                    decreasedValue: currentValue > widget.min
                                        ? _getAccessibleValueString(
                                            currentValue - 1,
                                          )
                                        : null,
                                    child: Slider(
                                      value: currentValue.toDouble(),
                                      min: widget.min.toDouble(),
                                      max: widget.max.toDouble(),
                                      divisions: (widget.max - widget.min > 0)
                                          ? widget.max - widget.min
                                          : null,
                                      semanticFormatterCallback: (value) =>
                                          _getAccessibleValueString(
                                            value.toInt(),
                                          ),
                                      onChangeStart: (value) {
                                        isChanging = true;
                                      },
                                      onChangeEnd: (value) {
                                        isChanging = false;
                                        setState(() {
                                          currentValue = value.toInt();
                                          if (widget.isOnOff) {
                                            isChecked = currentValue == 1;
                                          }
                                        });
                                        _updateCubitValue(currentValue);
                                        _scheduleParameterRefresh();
                                        SemanticsService.sendAnnouncement(
                                          View.of(context),
                                          '$paramName: ${_getAccessibleValueString()}',
                                          TextDirection.ltr,
                                        );
                                      },
                                      onChanged: (value) {
                                        setState(() {
                                          currentValue = value.toInt();
                                          if (widget.isOnOff) {
                                            isChecked = currentValue == 1;
                                          }
                                        });
                                        onSliderChanged(currentValue);
                                      },
                                    ),
                                  )),
                ),
              ),
            ),
          ),
          // Control column
          Expanded(
            flex: widescreen ? 4 : 5,
            child: Align(
              alignment: Alignment.centerLeft,
              child: isRoutingParameter
                  ? RoutingParameterValue(
                      portLabel: paramName,
                      currentBus: currentValue,
                      parameterMin: widget.min,
                      parameterMax: widget.max,
                      showEs5: routingShowEs5,
                      deviceIoProfile: routingDeviceIoProfile,
                      canDisconnect: widget.min <= 0 && widget.max >= 0,
                      enabled: widget.parameterValueEditingEnabled,
                      onValueChanged: (newValue) {
                        setState(() {
                          currentValue = newValue;
                        });
                        _updateCubitValue(newValue);
                        _scheduleParameterRefresh();
                      },
                    )
                  : ParameterValueDisplay(
                      currentValue: currentValue,
                      min: widget.min,
                      max: widget.max,
                      name: widget.name,
                      unit: widget.unit,
                      powerOfTen: widget.powerOfTen,
                      displayString: widget.displayString,
                      dropdownItems: widget.dropdownItems,
                      isOnOff: widget.isOnOff,
                      widescreen: widescreen,
                      isBpmUnit: isBpmUnit,
                      hasFileEditor: fileEditor != null,
                      showAlternateEditor: _showAlternateEditor,
                      enabled: widget.parameterValueEditingEnabled,
                      traversalId: widget.parameterValueTraversalId,
                      traversalOrder: widget.parameterValueTraversalOrder,
                      onValueChanged: (newValue) {
                        setState(() {
                          currentValue = newValue;
                          if (widget.isOnOff) {
                            isChecked = currentValue == 1;
                          }
                        });
                        _updateCubitValue(newValue);
                        _scheduleParameterRefresh();
                      },
                      onLongPress: () => setState(() {
                        if (!isBpmUnit && fileEditor == null) {
                          _showAlternateEditor = !_showAlternateEditor;
                        }
                      }),
                    ),
            ),
          ),
        ],
      ),
    );

    if (widget.isDisabled) {
      return Semantics(
        label: '$paramName, disabled',
        excludeSemantics: true,
        child: Opacity(
          opacity: 0.5,
          child: IgnorePointer(ignoring: true, child: innerRow),
        ),
      );
    }

    return innerRow;
  }
}
