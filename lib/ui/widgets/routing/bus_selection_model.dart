import 'dart:collection';

import 'package:nt_helper/models/device_io_profile.dart';

enum BusSelectionGroup { input, output, aux, es5 }

class BusSelectionChoice {
  final int value;
  final String label;
  final BusSelectionGroup group;

  const BusSelectionChoice({
    required this.value,
    required this.label,
    required this.group,
  });
}

/// Pre-classified choices for every bus-selection surface.
class BusSelectionModel {
  final DeviceIoProfile deviceIoProfile;
  final int currentValue;
  final bool allowNone;
  final int minimum;
  final int maximum;
  final List<BusSelectionChoice> choices;

  BusSelectionModel._({
    required this.deviceIoProfile,
    required this.currentValue,
    required this.allowNone,
    required this.minimum,
    required this.maximum,
    required List<BusSelectionChoice> choices,
  }) : choices = UnmodifiableListView(choices);

  factory BusSelectionModel.fromProfile({
    required DeviceIoProfile deviceIoProfile,
    required int currentValue,
    required int minimum,
    required int maximum,
    required bool allowNone,
    bool includeEs5 = false,
  }) {
    final low = minimum;
    final high = maximum;
    final choices = <BusSelectionChoice>[];

    void addProfileBuses(List<int> buses, BusSelectionGroup group) {
      for (final bus in buses) {
        if (bus < low || bus > high) continue;
        final local = deviceIoProfile.localNumber(bus);
        if (local == null) continue;
        final label = switch (group) {
          BusSelectionGroup.input => 'I$local',
          BusSelectionGroup.output => 'O$local',
          BusSelectionGroup.aux => 'A$local',
          BusSelectionGroup.es5 => throw StateError('ES-5 is added separately'),
        };
        choices.add(BusSelectionChoice(value: bus, label: label, group: group));
      }
    }

    addProfileBuses(deviceIoProfile.inputBuses, BusSelectionGroup.input);
    addProfileBuses(deviceIoProfile.outputBuses, BusSelectionGroup.output);
    addProfileBuses(deviceIoProfile.auxBuses, BusSelectionGroup.aux);

    if (includeEs5) {
      final es5 = deviceIoProfile.contextualEs5Buses;
      for (var index = 0; index < es5.length; index++) {
        final bus = es5[index];
        if (bus < low || bus > high) continue;
        choices.add(
          BusSelectionChoice(
            value: bus,
            label: index == 0 ? 'ES-5 L' : 'ES-5 R',
            group: BusSelectionGroup.es5,
          ),
        );
      }
    }

    return BusSelectionModel._(
      deviceIoProfile: deviceIoProfile,
      currentValue: currentValue,
      allowNone: allowNone && low <= 0 && high >= 0,
      minimum: low,
      maximum: high,
      choices: choices,
    );
  }

  List<BusSelectionChoice> choicesFor(BusSelectionGroup group) =>
      UnmodifiableListView(choices.where((choice) => choice.group == group));

  bool get hasSelectableValue => allowNone || choices.isNotEmpty;

  bool isSelectable(int value) =>
      (value == 0 && allowNone) ||
      choices.any((choice) => choice.value == value);

  String labelFor(int value) {
    if (value == 0 && allowNone) return 'None';
    for (final choice in choices) {
      if (choice.value == value) return choice.label;
    }
    return value < 0 ? '$value (Unavailable)' : 'Bus $value (Unavailable)';
  }
}
