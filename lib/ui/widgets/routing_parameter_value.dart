import 'package:flutter/material.dart';

import 'package:nt_helper/core/routing/bus_spec.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_field.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

/// Routing-parameter adapter for the shared bus-selection field.
class RoutingParameterValue extends StatelessWidget {
  final String portLabel;
  final int currentBus;
  final int parameterMin;
  final int parameterMax;
  final bool showEs5;
  final DeviceIoProfile deviceIoProfile;
  final bool canDisconnect;
  final bool enabled;
  final ValueChanged<int> onValueChanged;

  const RoutingParameterValue({
    super.key,
    required this.portLabel,
    required this.currentBus,
    this.parameterMin = BusSpec.min,
    this.parameterMax = BusSpec.max,
    required this.showEs5,
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
    this.canDisconnect = false,
    this.enabled = true,
    required this.onValueChanged,
  }) : deviceIoProfile =
           deviceIoProfile ??
           (hasExtendedAuxBuses
               ? DeviceIoProfile.distingExtended
               : DeviceIoProfile.distingLegacy);

  @override
  Widget build(BuildContext context) {
    return BusSelectionField(
      label: portLabel,
      model: BusSelectionModel.fromProfile(
        deviceIoProfile: deviceIoProfile,
        currentValue: currentBus,
        minimum: parameterMin,
        maximum: parameterMax,
        allowNone: canDisconnect,
        includeEs5: showEs5,
      ),
      enabled: enabled,
      onChanged: onValueChanged,
    );
  }
}
