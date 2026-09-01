import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'algorithm_routing.dart';
import 'models/port.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Routing implementation for USB Audio (From Host) algorithm.
///
/// The USB Audio algorithm has a unique parameter structure where
/// it uses 8 'to' parameters (Ch1 to - Ch8 to) to define output
/// routing destinations, and 8 'mode' parameters (Ch1 mode - Ch8 mode)
/// to define Add/Replace modes for each channel.
///
/// This implementation:
/// - Has no input ports (USB audio comes from the host)
/// - Has 8 fixed output ports representing USB channels 1-8
/// - Supports extended bus values 0-30 (including ES-5 L/R at 29-30)
/// - Extracts mode information for each channel
class UsbFromAlgorithmRouting extends CachedAlgorithmRouting {
  /// Algorithm-specific properties, including pre-parsed ports
  final Map<String, dynamic> properties;

  /// Creates a new UsbFromAlgorithmRouting instance.
  ///
  /// Parameters:
  /// - [properties]: Pre-parsed algorithm properties, including output ports
  /// - [algorithmUuid]: Unique identifier for this algorithm instance
  /// - [validator]: Optional port compatibility validator
  /// - [initialState]: Optional initial routing state
  UsbFromAlgorithmRouting({
    required this.properties,
    required String algorithmUuid,
    super.validator,
    super.initialState,
  }) : super(algorithmUuid: algorithmUuid);

  @override
  List<Port> generateInputPorts() {
    // USB Audio (From Host) has no input ports
    return [];
  }

  @override
  List<Port> generateOutputPorts() {
    final ports = <Port>[];
    final declaredOutputs = properties['outputs'];

    if (declaredOutputs is List) {
      for (final item in declaredOutputs) {
        if (item is Map) {
          final port = buildPortFromDeclaration(
            item,
            direction: PortDirection.output,
            defaultId: 'out_${ports.length + 1}',
            defaultName: 'Output',
            defaultType: PortType.audio,
            defaultDescription: 'USB audio channel from host',
            includeOutputMode: true,
          ).copyWith(channelNumber: coerceInt(item['channelNumber']));

          ports.add(port);
        }
      }
    }

    return ports;
  }

  /// Determines if this routing implementation can handle the given slot.
  ///
  /// Returns true only for the USB Audio (From Host) algorithm with GUID 'usbf'.
  static bool canHandle(Slot slot) {
    return slot.algorithm.guid == 'usbf';
  }

  /// USB-specific extraction of IO parameters.
  ///
  /// Uses IO flags to find the 8 USB channel output parameters and returns a
  /// map of parameter name -> current value. Includes 0 values (None).
  static Map<String, int> extractIOParameters(Slot slot) {
    final result = <String, int>{};

    // Build helpers
    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    var toParams = _findUsbToParams(slot);

    // Build output map using actual parameter names
    for (final p in toParams) {
      final value = valueByParam[p.parameterNumber] ?? p.defaultValue;
      result[p.name] = value;
    }

    return result;
  }

  /// Creates a UsbFromAlgorithmRouting instance from a slot.
  ///
  /// This factory method is called by AlgorithmRouting.fromSlot() when
  /// the algorithm GUID is 'usbf'. It parses the 8 channel parameters
  /// and their corresponding modes.
  ///
  /// Channel enumeration and mode alignment:
  /// - Output ports are enumerated by ascending parameterNumber of the eight
  ///   USB channel 'to' parameters, producing 'USB Channel 1..8'. This holds even
  ///   if names are generic (e.g., all 'to'/'mode').
  /// - OutputMode for each channel is aligned by index with the sorted mode
  ///   parameters: 0 = Add, 1 = Replace. Missing mode defaults to Add.
  /// - busValue drives connection discovery (e.g., 13–20 => hardware outs O1–O8,
  ///   29–30 => ES-5 L/R). A value of 0 means 'None'.
  ///
  /// Parameters:
  /// - [slot]: The slot containing algorithm and parameter information
  /// - [ioParameters]: Pre-extracted routing parameters (bus assignments)
  /// - [modeParametersWithNumbers]: Mode parameters with their parameter numbers
  /// - [algorithmUuid]: Optional UUID for the algorithm instance
  static UsbFromAlgorithmRouting createFromSlot(
    Slot slot, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
    required Map<String, int> ioParameters,
    Map<String, ({int parameterNumber, int value})>? modeParametersWithNumbers,
    String? algorithmUuid,
  }) {
    final algUuid =
        algorithmUuid ?? 'algo_usbf_${DateTime.now().millisecondsSinceEpoch}';

    final outputPorts = <Map<String, Object?>>[];

    // Build parameter lookup for getting parameter numbers
    final paramsByName = <String, ParameterInfo>{
      for (final p in slot.parameters) p.name: p,
    };

    // Pre-build a value lookup for direct fallback access
    final valueByParam = <int, int>{
      for (final v in slot.values) v.parameterNumber: v.value,
    };

    // Collect candidate 'to' and 'mode' parameters robustly
    var toParams = _findUsbToParams(slot);
    var modeParams = _findUsbModeParams(slot);

    // If we still have fewer than 8 'to' params, try name-based lookup as a last resort
    if (toParams.length < 8) {
      String? findParamName(int channel, String suffix) {
        final candidates = <String>[
          'Ch$channel $suffix',
          'Ch $channel $suffix',
          'Channel $channel $suffix',
          if (suffix == 'to' || suffix == 'mode') 'Ch$channel $suffix',
        ];
        for (final name in candidates) {
          final info = paramsByName[name];
          if (info != null) return name;
        }
        return null;
      }

      final recovered = <ParameterInfo>[];
      for (int i = 1; i <= 8; i++) {
        final name = findParamName(i, 'to');
        if (name != null) {
          final info = paramsByName[name];
          if (info != null) recovered.add(info);
        }
      }
      if (recovered.isNotEmpty) {
        recovered.sort(
          (a, b) => a.parameterNumber.compareTo(b.parameterNumber),
        );
        toParams = recovered;
      }
    }

    // Build ports based on discovered params
    for (int i = 0; i < toParams.length && i < 8; i++) {
      final channel = i + 1;
      final toParam = toParams[i];
      final busValue =
          valueByParam[toParam.parameterNumber] ?? toParam.defaultValue;

      // Mode per index if available
      ({int parameterNumber, int value})? modeInfo;
      if (i < modeParams.length) {
        final modeParam = modeParams[i];
        final value =
            valueByParam[modeParam.parameterNumber] ?? modeParam.defaultValue;
        modeInfo = (parameterNumber: modeParam.parameterNumber, value: value);
      }

      outputPorts.add({
        'id': '${algUuid}_usb_ch$channel',
        'name': 'USB Channel $channel',
        'type': 'audio',
        'busParam': toParam.name,
        'busValue': busValue,
        'parameterNumber': toParam.parameterNumber,
        'channelNumber': channel,
        'outputMode': (modeInfo?.value == 1) ? 'replace' : 'add',
        'modeParameterNumber': modeInfo?.parameterNumber,
      });
    }

    final properties = {
      'algorithmGuid': slot.algorithm.guid,
      'algorithmName': slot.algorithm.name,
      'algorithmUuid': algUuid,
      'outputs': outputPorts,
    };

    final routing = UsbFromAlgorithmRouting(
      properties: properties,
      algorithmUuid: algUuid,
    );
    routing.deviceIoProfile = deviceIoProfile;
    return routing;
  }

  static List<ParameterInfo> _findUsbToParams(Slot slot) {
    // Only consider parameters that appear in at least one firmware-provided
    // page — hidden parameters should not leak into the routing views.
    // When pages are empty (test mocks, offline fixtures), fall back to all.
    final visible = _visibleParameterNumbers(slot);

    // Use IO flags to find output parameters
    var toParams = [
      for (final p in slot.parameters)
        if (visible.contains(p.parameterNumber) && p.isOutput) p,
    ];

    // Sort stably by parameter number and keep the first 8
    toParams.sort((a, b) => a.parameterNumber.compareTo(b.parameterNumber));
    if (toParams.length > 8) {
      toParams = toParams.sublist(0, 8);
    }

    return toParams;
  }

  static List<ParameterInfo> _findUsbModeParams(Slot slot) {
    // Only consider parameters that appear in at least one firmware-provided
    // page — hidden parameters should not leak into the routing views.
    // When pages are empty (test mocks, offline fixtures), fall back to all.
    final visible = _visibleParameterNumbers(slot);

    // Use IO flags to find output mode parameters
    var modeParams = [
      for (final p in slot.parameters)
        if (visible.contains(p.parameterNumber) && p.isOutputMode) p,
    ];

    // Sort by parameter number to keep channel order stable
    modeParams.sort((a, b) => a.parameterNumber.compareTo(b.parameterNumber));

    // Keep only first 8 (USB has 8 channels)
    if (modeParams.length > 8) {
      modeParams = modeParams.sublist(0, 8);
    }

    return modeParams;
  }

  /// Compute visible parameter numbers: page membership when available,
  /// or all parameters as fallback for test mocks / offline fixtures.
  static Set<int> _visibleParameterNumbers(Slot slot) {
    final pageParams = slot.pages.pages.expand((p) => p.parameters).toSet();
    if (pageParams.isNotEmpty) return pageParams;
    return slot.parameters.map((p) => p.parameterNumber).toSet();
  }
}
