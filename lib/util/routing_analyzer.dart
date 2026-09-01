import 'dart:convert';

import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/routing_information.dart';

class RoutingAnalyzer {
  final List<RoutingInformation> _routing;
  final bool _showSignals;
  final bool _showMappings;
  final int _slotCount;
  final DeviceIoProfile deviceIoProfile;

  late List<List<int>> _processedSignals;
  late List<List<bool>> _processedUsageNeeded;

  RoutingAnalyzer({
    required List<RoutingInformation> routing,
    bool showSignals = true,
    bool showMappings = false,
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  }) : _routing = routing,
       _showSignals = showSignals,
       _showMappings = showMappings,
       _slotCount = routing.length {
    _initializeAnalysis();
  }

  void _initializeAnalysis() {
    _processedSignals = _buildForwardSignals();
    _applyStripSignals(_processedSignals);
    _processedUsageNeeded = _buildUsageNeeded();
  }

  // Public accessors for processed data for the widget
  List<List<int>> get signals => _processedSignals;
  List<List<bool>> get usageNeeded => _processedUsageNeeded;

  // Copied and adapted from RoutingTableWidget
  // Builds the initial signal propagation state based on outputs and replacements.
  List<List<int>> _buildForwardSignals() {
    // Initial signal state: index 0 unused, physical inputs have signal (1),
    // all others (outputs, aux, ES-5) start at 0.
    final initialSignals = List<int>.generate(
      DeviceIoProfile.maximumBusNumber + 1,
      (i) => deviceIoProfile.isInput(i) ? 1 : 0,
    );
    final List<List<int>> signalsList = [initialSignals];

    for (int s = 0; s < _slotCount; s++) {
      final info = _routing[s];
      final rowBefore = signalsList.last;
      final rowAfter = List<int>.from(rowBefore);

      final outMask = info.routingInfo[1];
      final replaceMask = info.routingInfo[2];

      for (int ch = 1; ch <= DeviceIoProfile.maximumBusNumber; ch++) {
        int v = rowBefore[ch];
        final hasOutput = (outMask & (1 << ch)) != 0;
        final replaced = (replaceMask & (1 << ch)) != 0;

        if (hasOutput) {
          if (replaced) {
            v = v + 1;
            if (v > 2) v = 1; // Signal level cycles 0 -> 1 -> 2 -> 1
          } else if (v == 0) {
            v = 1; // New signal introduced
          }
        }
        rowAfter[ch] = v;
      }
      signalsList.add(rowAfter);
    }
    return signalsList;
  }

  // Modifies the signals by removing signals that are not actually used by any subsequent input.
  // Works bottom-up.
  void _applyStripSignals(List<List<int>> signalsToModify) {
    for (int ch = 1; ch <= DeviceIoProfile.maximumBusNumber; ch++) {
      if (_showSignals && deviceIoProfile.isOutput(ch)) continue;

      bool hasInputBelow = false;
      for (int s = _slotCount; s >= 0; s--) {
        if (s < _slotCount) {
          final info = _routing[s];
          final inMaskForThisSlot = getNetInputMask(info);
          final replaceMaskForThisSlot = info.routingInfo[2];

          // If this slot replaces the channel, any input requirement from below is cut off here.
          if ((replaceMaskForThisSlot & (1 << ch)) != 0) {
            hasInputBelow = false;
          }
          // If this slot uses the channel as input, then it's needed.
          if ((inMaskForThisSlot & (1 << ch)) != 0) {
            hasInputBelow = true;
          }
        }
        // If no slot below (or this slot itself) requires this channel's signal at this point, strip it.
        if (!hasInputBelow) {
          signalsToModify[s][ch] = 0;
        }
      }
    }
  }

  // Builds a structure indicating, for each channel entering a slot, whether it's actually needed
  // by that slot or any subsequent slot.
  List<List<bool>> _buildUsageNeeded() {
    final List<List<bool>> usageList = List.generate(
      _slotCount + 1,
      (_) => List<bool>.filled(DeviceIoProfile.maximumBusNumber + 1, false),
    );
    for (int s = _slotCount - 1; s >= 0; s--) {
      final info = _routing[s];
      final inMaskForThisSlot = getNetInputMask(info);
      final replaceMaskForThisSlot = info.routingInfo[2];
      for (int ch = 1; ch <= DeviceIoProfile.maximumBusNumber; ch++) {
        final neededBySlotsBelow = usageList[s + 1][ch];
        final replacedByThisSlot = (replaceMaskForThisSlot & (1 << ch)) != 0;
        final thisSlotNeedsChannel = (inMaskForThisSlot & (1 << ch)) != 0;

        usageList[s][ch] =
            thisSlotNeedsChannel || (neededBySlotsBelow && !replacedByThisSlot);
      }
    }
    return usageList;
  }

  // Calculates the effective input mask for a slot, considering signal/mapping visibility.
  int getNetInputMask(RoutingInformation r) {
    final inputMask = r.routingInfo[0];
    final mappingMask = r.routingInfo[5];
    if (_showSignals && _showMappings) return inputMask | mappingMask;
    if (_showSignals) return inputMask;
    if (_showMappings) return mappingMask;
    return 0;
  }

  // Generates a JSON string representing input and output bus usage per slot.
  String generateSlotBusUsageJson() {
    final List<Map<String, dynamic>> slotDataList = [];
    for (int s = 0; s < _slotCount; s++) {
      final info = _routing[s];
      final List<int> inputBuses = [];
      final List<int> outputBuses = [];

      final currentNetInputMask = getNetInputMask(info);
      final currentOutMask = info.routingInfo[1]; // Direct output mask

      for (int ch = 1; ch <= DeviceIoProfile.maximumBusNumber; ch++) {
        if ((currentNetInputMask & (1 << ch)) != 0) {
          inputBuses.add(ch);
        }
        if ((currentOutMask & (1 << ch)) != 0) {
          outputBuses.add(ch);
        }
      }

      slotDataList.add({
        'slotIndex': s,
        'algorithmName': info.algorithmName,
        'inputBuses': inputBuses,
        'outputBuses': outputBuses,
      });
    }
    return jsonEncode(slotDataList);
  }
}
