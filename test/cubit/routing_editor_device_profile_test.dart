import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_cubit.dart';
import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  test(
    'profile changes rebuild routing even when slots are identical',
    () async {
      SharedPreferences.setMockInitialValues({});
      final stream = StreamController<DistingState>();
      final distingCubit = _MockDistingCubit();
      final manager = _MockMidiManager();
      const slots = <Slot>[];
      final firstProfile = DeviceIoProfile.tryCreate(
        inputBusCount: 4,
        outputBusCount: 3,
        auxBusCount: 5,
      )!;
      final secondProfile = DeviceIoProfile.tryCreate(
        inputBusCount: 2,
        outputBusCount: 1,
        auxBusCount: 0,
      )!;

      DistingState currentState = _state(
        manager,
        slots: slots,
        profile: firstProfile,
      );
      when(() => distingCubit.stream).thenAnswer((_) => stream.stream);
      when(() => distingCubit.state).thenAnswer((_) => currentState);

      final routingCubit = RoutingEditorCubit(distingCubit);
      addTearDown(() async {
        await routingCubit.close();
        await stream.close();
      });

      var loaded = routingCubit.state as RoutingEditorStateLoaded;
      expect(loaded.deviceIoProfile, firstProfile);
      expect(loaded.physicalInputs, hasLength(4));
      expect(loaded.physicalOutputs, hasLength(3));

      currentState = _state(manager, slots: slots, profile: secondProfile);
      stream.add(currentState);
      await Future<void>.delayed(Duration.zero);

      loaded = routingCubit.state as RoutingEditorStateLoaded;
      expect(loaded.deviceIoProfile, secondProfile);
      expect(loaded.physicalInputs, hasLength(2));
      expect(loaded.physicalOutputs, hasLength(1));
    },
  );
}

DistingState _state(
  IDistingMidiManager manager, {
  required List<Slot> slots,
  required DeviceIoProfile profile,
}) => DistingState.synchronized(
  disting: manager,
  distingVersion: 'Test firmware',
  firmwareVersion: FirmwareVersion('1.15'),
  deviceIoProfile: profile,
  presetName: 'Test',
  algorithms: const [],
  slots: slots,
  unitStrings: const [],
);
