import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline mode retains the last connected device profile', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = _MockDistingMidiManager();
    final midiCommand = MockMidiCommand();
    final profile = DeviceIoProfile.tryCreate(
      inputBusCount: 2,
      outputBusCount: 1,
      auxBusCount: 1,
    )!;
    when(() => manager.dispose()).thenReturn(null);
    final cubit = DistingCubit(database, midiCommand: midiCommand);
    cubit.emit(
      DistingState.synchronized(
        disting: manager,
        distingVersion: 'Forever 1.0',
        firmwareVersion: FirmwareVersion('1.15'),
        deviceIoProfile: profile,
        presetName: 'Test',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
      ),
    );

    await cubit.goOffline();

    final state = cubit.state as DistingStateSynchronized;
    expect(state.offline, isTrue);
    expect(state.deviceIoProfile, profile);

    await cubit.close();
    await database.close();
  });
}
