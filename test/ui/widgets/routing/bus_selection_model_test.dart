import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/ui/widgets/routing/bus_selection_model.dart';

void main() {
  final profile = DeviceIoProfile.tryCreate(
    inputBusCount: 4,
    outputBusCount: 3,
    auxBusCount: 5,
  )!;

  test('groups a non-Disting profile and intersects the parameter range', () {
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 6,
      minimum: 3,
      maximum: 10,
      allowNone: false,
    );

    expect(
      model.choicesFor(BusSelectionGroup.input).map((choice) => choice.value),
      [3, 4],
    );
    expect(
      model.choicesFor(BusSelectionGroup.output).map((choice) => choice.value),
      [5, 6, 7],
    );
    expect(
      model.choicesFor(BusSelectionGroup.aux).map((choice) => choice.value),
      [8, 9, 10],
    );
  });

  test('offers None only when both permitted and in range', () {
    final withNone = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 0,
      minimum: 0,
      maximum: 12,
      allowNone: true,
    );
    final withoutNone = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 0,
      minimum: 1,
      maximum: 12,
      allowNone: true,
    );

    expect(withNone.allowNone, isTrue);
    expect(withoutNone.allowNone, isFalse);
  });

  test('does not make an invalid current value selectable', () {
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: -1,
      minimum: 0,
      maximum: 127,
      allowNone: true,
    );

    expect(model.isSelectable(-1), isFalse);
    expect(model.labelFor(-1), '-1 (Unavailable)');
  });

  test('adds contextual ES-5 only when requested and in range', () {
    final hidden = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 1,
      minimum: 0,
      maximum: 14,
      allowNone: true,
    );
    final shown = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 1,
      minimum: 0,
      maximum: 14,
      allowNone: true,
      includeEs5: true,
    );

    expect(hidden.choicesFor(BusSelectionGroup.es5), isEmpty);
    expect(
      shown.choicesFor(BusSelectionGroup.es5).map((choice) => choice.value),
      [13, 14],
    );
  });

  test('omits zero-count groups', () {
    final sparseProfile = DeviceIoProfile.tryCreate(
      inputBusCount: 0,
      outputBusCount: 2,
      auxBusCount: 0,
    )!;
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: sparseProfile,
      currentValue: 1,
      minimum: 0,
      maximum: 2,
      allowNone: true,
    );

    expect(model.choicesFor(BusSelectionGroup.input), isEmpty);
    expect(
      model.choicesFor(BusSelectionGroup.output).map((choice) => choice.value),
      [1, 2],
    );
    expect(model.choicesFor(BusSelectionGroup.aux), isEmpty);
  });

  test('an inverted advertised range offers no values', () {
    final model = BusSelectionModel.fromProfile(
      deviceIoProfile: profile,
      currentValue: 6,
      minimum: 10,
      maximum: 3,
      allowNone: true,
    );

    expect(model.choices, isEmpty);
    expect(model.allowNone, isFalse);
    expect(model.isSelectable(6), isFalse);
  });
}
