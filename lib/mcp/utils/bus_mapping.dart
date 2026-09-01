import 'package:nt_helper/domain/disting_nt_sysex.dart' show ParameterInfo;
import 'package:nt_helper/models/device_io_profile.dart';

/// Dynamic bus mapping utilities for MCP tools.
/// Maps between bus numbers and human-friendly names using a device profile.
class BusMapping {
  /// Convert bus number to human-friendly name.
  /// Returns "None" for 0, "Input 1"-"Input 12", "Output 1"-"Output 8",
  /// "Aux 1"-"Aux N", "ES-5 L"/"ES-5 R", or "Unknown (N)" for unrecognized.
  static String busToName(
    int busNumber, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
    bool includeEs5 = true,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    if (busNumber == 0) return 'None';
    final es5Index = profile.contextualEs5Buses.indexOf(busNumber);
    if (includeEs5 && es5Index >= 0) {
      final local = es5Index + 1;
      return local == 1 ? 'ES-5 L' : 'ES-5 R';
    }
    return profile.labelForBus(busNumber) ?? 'Unknown ($busNumber)';
  }

  static final _namePattern = RegExp(
    r'^(input|output|aux|es-5|none)\s*(\d+|l|r)?$',
    caseSensitive: false,
  );

  /// Convert human-friendly name to bus number.
  /// Case-insensitive. Returns null for unrecognized names.
  static int? nameToBus(
    String name, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
    bool includeEs5 = true,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final match = _namePattern.firstMatch(trimmed);
    if (match == null) return null;

    final category = match.group(1)!.toLowerCase();
    final suffix = match.group(2)?.toLowerCase();

    switch (category) {
      case 'none':
        return 0;
      case 'input':
        if (suffix == null) return null;
        final n = int.tryParse(suffix);
        if (n == null) return null;
        return profile.busForLocalNumber(DeviceBusGroup.input, n);
      case 'output':
        if (suffix == null) return null;
        final n = int.tryParse(suffix);
        if (n == null) return null;
        return profile.busForLocalNumber(DeviceBusGroup.output, n);
      case 'aux':
        if (suffix == null) return null;
        final n = int.tryParse(suffix);
        if (n == null) return null;
        return profile.busForLocalNumber(DeviceBusGroup.aux, n);
      case 'es-5':
        if (!includeEs5 || suffix == null) return null;
        final int local;
        if (suffix == 'l') {
          local = 1;
        } else if (suffix == 'r') {
          local = 2;
        } else {
          return null;
        }
        final buses = profile.contextualEs5Buses;
        return buses.length == 2 ? buses[local - 1] : null;
      default:
        return null;
    }
  }

  /// Parse bus from either a name string or raw integer.
  /// Accepts "Aux 1", "Input 5", "None", or integer bus numbers.
  static int? parseBus(
    dynamic value, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
    bool includeEs5 = true,
    bool allowNone = true,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    bool isAccepted(int bus) =>
        (allowNone && bus == 0) ||
        profile.contains(bus) ||
        (includeEs5 && profile.contextualEs5Buses.contains(bus));

    if (value is int) {
      return isAccepted(value) ? value : null;
    }
    if (value is String) {
      // Try as integer first
      final asInt = int.tryParse(value);
      if (asInt != null) {
        return isAccepted(asInt) ? asInt : null;
      }
      final bus = nameToBus(
        value,
        deviceIoProfile: profile,
        includeEs5: includeEs5,
      );
      return bus != null && isAccepted(bus) ? bus : null;
    }
    return null;
  }

  /// Detect whether a parameter is a bus assignment parameter.
  /// I/O flags identify algorithm bus inputs and outputs. The advertised
  /// range limits the choices later; it does not define the device topology.
  static bool isBusParameter(ParameterInfo param) {
    return param.unit == 1 &&
        (param.isInput || param.isOutput) &&
        param.min <= param.max &&
        param.max >= 0;
  }

  static DeviceIoProfile _profile(
    DeviceIoProfile? profile,
    bool hasExtendedAuxBuses,
  ) =>
      profile ??
      (hasExtendedAuxBuses
          ? DeviceIoProfile.distingExtended
          : DeviceIoProfile.distingLegacy);
}
