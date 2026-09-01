import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/widgets/routing/routing_editor_widget.dart';

import 'main.dart' as app;

void main() {
  enableFlutterDriverExtension(handler: _handleDriverData);
  app.main(const []);
}

Future<String> _handleDriverData(String? message) async {
  if (message != 'routing_dump') {
    return jsonEncode({'error': 'unknown_message'});
  }

  final rootElement = WidgetsBinding.instance.rootElement;
  if (rootElement == null) {
    return jsonEncode({'error': 'no_root_element'});
  }

  final routingElement =
      _findElementByWidgetType(rootElement, RoutingEditorWidget) ?? rootElement;

  DistingCubit? distingCubit;
  RoutingEditorCubit? routingCubit;
  try {
    distingCubit = BlocProvider.of<DistingCubit>(routingElement, listen: false);
  } catch (_) {}
  try {
    routingCubit = BlocProvider.of<RoutingEditorCubit>(
      routingElement,
      listen: false,
    );
  } catch (_) {}

  final result = <String, Object?>{};
  if (distingCubit == null) {
    result['error'] = 'disting_cubit_not_found';
    return jsonEncode(result);
  }

  final state = distingCubit.state;
  if (state is! DistingStateSynchronized) {
    result['error'] = 'disting_not_synchronized';
    result['state'] = state.runtimeType.toString();
    return jsonEncode(result);
  }

  final slots = state.slots;
  result['slotCount'] = slots.length;
  result['slots'] = slots.map((slot) {
    final modeValues = <String, int>{};
    for (final entry in slot.outputModeMap.entries) {
      final modeParam = entry.key;
      final value = slot.values
          .firstWhere(
            (v) => v.parameterNumber == modeParam,
            orElse: () => ParameterValue(
              algorithmIndex: slot.algorithm.algorithmIndex,
              parameterNumber: modeParam,
              value: -999,
            ),
          )
          .value;
      modeValues[modeParam.toString()] = value;
    }

    return {
      'index': slot.algorithm.algorithmIndex,
      'guid': slot.algorithm.guid,
      'name': slot.algorithm.name,
      'outputModeMap': slot.outputModeMap.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'modeValues': modeValues,
      'valueCount': slot.values.length,
      'parameterCount': slot.parameters.length,
    };
  }).toList();

  if (slots.isNotEmpty) {
    final clockDividerSlot = slots.firstWhere(
      (slot) => slot.algorithm.guid == 'clkd',
      orElse: () => slots.first,
    );
    if (clockDividerSlot.algorithm.guid == 'clkd') {
      final routing = AlgorithmRouting.fromSlot(
        clockDividerSlot,
        deviceIoProfile: state.deviceIoProfile,
      );
      result['clockDividerOutputs'] = routing.outputPorts.map((port) {
        return {
          'name': port.name,
          'bus': port.busValue,
          'parameterNumber': port.parameterNumber,
          'modeParameterNumber': port.modeParameterNumber,
          'outputMode': port.outputMode?.name,
        };
      }).toList();
    }
  }

  if (routingCubit != null) {
    final routingState = routingCubit.state;
    result['routingState'] = routingState.runtimeType.toString();
    if (routingState is RoutingEditorStateLoaded) {
      result['connections'] = routingState.connections.map((conn) {
        return {
          'busNumber': conn.busNumber,
          'outputMode': conn.outputMode?.name,
          'sourcePortId': conn.sourcePortId,
          'destinationPortId': conn.destinationPortId,
          'connectionType': conn.connectionType.name,
        };
      }).toList();
    }
  }

  return jsonEncode(result);
}

Element? _findElementByWidgetType(Element root, Type widgetType) {
  if (root.widget.runtimeType == widgetType) {
    return root;
  }
  Element? found;
  root.visitChildElements((child) {
    found ??= _findElementByWidgetType(child, widgetType);
  });
  return found;
}
