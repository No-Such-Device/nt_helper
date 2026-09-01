import '../../../core/routing/models/port.dart';
import '../../../core/routing/bus_spec.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Enum representing the type of bus
enum BusType {
  /// Physical input buses (1-12)
  input,

  /// Physical output buses (13-20)
  output,

  /// Auxiliary buses (21-64, excluding ES-5)
  auxiliary,

  /// ES-5 output buses (29-30 on legacy firmware, 65-66 on 1.15+)
  es5,
}

/// Utility class for formatting bus numbers into readable labels
///
/// Converts bus numbers to their corresponding display format:
/// - Buses 1-12: "I1" through "I12" (physical inputs)
/// - Buses 13-20: "O1" through "O8" (physical outputs)
/// - Buses 21-64: "A1" through "A44" (auxiliary buses, excluding ES-5)
class BusLabelFormatter {
  /// Private constructor to prevent instantiation
  BusLabelFormatter._();

  /// Minimum valid bus number
  static const int minBusNumber = BusSpec.min;

  /// Maximum valid bus number (includes extended aux and ES-5)
  static const int maxBusNumber = BusSpec.extendedMax;

  /// Formats a bus value (alias for formatBusNumber)
  ///
  /// This is provided for convenience and compatibility.
  static String formatBusValue(
    int busValue, {
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    return formatBusNumber(
          busValue,
          hasExtendedAuxBuses: hasExtendedAuxBuses,
          deviceIoProfile: deviceIoProfile,
        ) ??
        'Bus$busValue';
  }

  /// Formats a bus number into its display label
  ///
  /// Returns:
  /// - "I1" through "I12" for buses 1-12
  /// - "O1" through "O8" for buses 13-20
  /// - "A1" through "A44" for aux buses 21-64 (excluding ES-5 at 29-30)
  /// - "ES-5 L" for bus 29
  /// - "ES-5 R" for bus 30
  /// - null for invalid bus numbers
  static String? formatBusNumber(
    int? busNumber, {
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    if (busNumber == null ||
        !isValidBusNumber(busNumber, deviceIoProfile: profile)) {
      return null;
    }

    final localNumber = getLocalBusNumber(
      busNumber,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: profile,
    );
    if (localNumber == null) return null;

    final busType = getBusType(
      busNumber,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: profile,
    );
    switch (busType) {
      case BusType.input:
        return 'I$localNumber';
      case BusType.output:
        return 'O$localNumber';
      case BusType.auxiliary:
        return 'A$localNumber';
      case BusType.es5:
        return (localNumber == 1) ? 'ES-5 L' : 'ES-5 R';
      case null:
        return null;
    }
  }

  /// Formats a bus number into its display label with optional output mode suffix
  ///
  /// Adds " R" suffix when [outputMode] is [OutputMode.replace] for
  /// both hardware output buses (13-20, "O#") and auxiliary buses
  /// (21-28, "A#"). Input buses (1-12, "I#") ignore the mode.
  ///
  /// Returns:
  /// - "I1" through "I12" for input buses (mode ignored)
  /// - "O1" through "O8" for output buses in add mode or null mode
  /// - "O1 R" through "O8 R" for output buses in replace mode
  /// - "A1" through "A44" for auxiliary buses (mode ignored)
  /// - "ES-5 L" or "ES-5 R" for ES-5 buses (mode ignored)
  /// - null for invalid bus numbers
  static String? formatBusLabelWithMode(
    int? busNumber,
    OutputMode? outputMode, {
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    if (busNumber == null ||
        !isValidBusNumber(busNumber, deviceIoProfile: profile)) {
      return null;
    }

    final localNumber = getLocalBusNumber(
      busNumber,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: profile,
    );
    if (localNumber == null) return null;

    final busType = getBusType(
      busNumber,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: profile,
    );
    switch (busType) {
      case BusType.input:
        return 'I$localNumber';
      case BusType.output:
        final baseLabel = 'O$localNumber';
        return outputMode == OutputMode.replace ? '$baseLabel R' : baseLabel;
      case BusType.auxiliary:
        final baseLabel = 'A$localNumber';
        return outputMode == OutputMode.replace ? '$baseLabel R' : baseLabel;
      case BusType.es5:
        return (localNumber == 1) ? 'ES-5 L' : 'ES-5 R';
      case null:
        return null;
    }
  }

  /// Determines the type of bus from its number
  ///
  /// Returns the [BusType] for valid bus numbers, null otherwise
  static BusType? getBusType(
    int? busNumber, {
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    if (busNumber == null) return null;
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    if (profile.isInput(busNumber)) {
      return BusType.input;
    } else if (profile.isOutput(busNumber)) {
      return BusType.output;
    } else if (profile.isAux(busNumber)) {
      return BusType.auxiliary;
    } else if (profile.contextualEs5Buses.contains(busNumber)) {
      return BusType.es5;
    }

    return null;
  }

  /// Checks if a bus number is valid
  ///
  /// Valid bus numbers are 1-30 inclusive (includes ES-5)
  static bool isValidBusNumber(
    int? busNumber, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
  }) {
    if (busNumber == null) return false;
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    return profile.contains(busNumber) ||
        profile.contextualEs5Buses.contains(busNumber);
  }

  /// Gets the range of bus numbers for a specific bus type
  ///
  /// Returns a list with [min, max] bus numbers for the type
  static List<int> getBusRange(
    BusType busType, {
    DeviceIoProfile? deviceIoProfile,
    bool hasExtendedAuxBuses = false,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    switch (busType) {
      case BusType.input:
        return [profile.inputStart, profile.outputStart - 1];
      case BusType.output:
        return [profile.outputStart, profile.auxStart - 1];
      case BusType.auxiliary:
        return [profile.auxStart, profile.maxBus];
      case BusType.es5:
        final es5 = profile.contextualEs5Buses;
        return es5.isEmpty ? const [] : [es5.first, es5.last];
    }
  }

  /// Converts a global bus number to its local number within its type
  ///
  /// For example:
  /// - Bus 1-12 returns 1-12 (unchanged for inputs)
  /// - Bus 13-20 returns 1-8 (outputs start at 1)
  /// - Bus 21-64 returns 1-44 (aux buses start at 1, excluding ES-5)
  /// - Bus 29-30 returns 1-2 (ES-5 L/R)
  static int? getLocalBusNumber(
    int? busNumber, {
    bool hasExtendedAuxBuses = false,
    DeviceIoProfile? deviceIoProfile,
  }) {
    final profile = _profile(deviceIoProfile, hasExtendedAuxBuses);
    if (busNumber == null ||
        !isValidBusNumber(busNumber, deviceIoProfile: profile)) {
      return null;
    }

    final busType = getBusType(
      busNumber,
      hasExtendedAuxBuses: hasExtendedAuxBuses,
      deviceIoProfile: profile,
    );
    switch (busType) {
      case BusType.input:
        return profile.localNumber(busNumber);
      case BusType.output:
        return profile.localNumber(busNumber);
      case BusType.auxiliary:
        return profile.localNumber(busNumber);
      case BusType.es5:
        return profile.contextualEs5Buses.indexOf(busNumber) + 1;
      case null:
        return null;
    }
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
