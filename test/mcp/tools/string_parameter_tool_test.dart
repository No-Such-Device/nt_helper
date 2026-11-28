import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/models/device_io_profile.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/algorithm_metadata_service.dart';
import 'package:nt_helper/services/disting_controller_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers/mock_midi_command.dart';

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

const _stringParameterNumber = 2;
const _channelName = 'Bass';

/// A mixer-like slot whose third parameter is a text parameter, as the
/// firmware reports mixer channel names (unit 18, no numeric range).
void _emitSlotWithStringParameter(DistingCubit cubit) {
  cubit.emit(
    DistingState.synchronized(
      disting: MockDistingMidiManager(),
      distingVersion: '1.17.0-beta',
      firmwareVersion: FirmwareVersion('1.17.0-beta'),
      deviceIoProfile: DeviceIoProfile.distingExtended,
      presetName: 'Test',
      algorithms: [
        AlgorithmInfo(
          algorithmIndex: 0,
          guid: 'mix2',
          name: 'Mixer Stereo',
          specifications: const [],
        ),
      ],
      slots: [
        Slot(
          algorithm: Algorithm(
            algorithmIndex: 0,
            guid: 'mix2',
            name: 'Mixer Stereo',
          ),
          routing: RoutingInfo(algorithmIndex: 0, routingInfo: const []),
          pages: ParameterPages(algorithmIndex: 0, pages: const []),
          parameters: [
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 0,
              min: 0,
              max: 127,
              defaultValue: 0,
              unit: 0,
              name: '1:Gain',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: 1,
              min: 0,
              max: 1,
              defaultValue: 0,
              unit: 1,
              name: '1:Mute',
              powerOfTen: 0,
            ),
            ParameterInfo(
              algorithmIndex: 0,
              parameterNumber: _stringParameterNumber,
              min: 0,
              max: 0,
              defaultValue: 0,
              // Factory text input, which is what a mixer channel name uses.
              unit: 18,
              name: '1:Name',
              powerOfTen: 0,
            ),
          ],
          values: [
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: 0,
            ),
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: 1,
              value: 0,
            ),
            ParameterValue(
              algorithmIndex: 0,
              parameterNumber: _stringParameterNumber,
              value: 0,
            ),
          ],
          enums: [],
          mappings: [],
          valueStrings: [
            ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: 0,
              value: '',
            ),
            ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: 1,
              value: '',
            ),
            ParameterValueString(
              algorithmIndex: 0,
              parameterNumber: _stringParameterNumber,
              value: _channelName,
            ),
          ],
        ),
      ],
      unitStrings: const [],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DistingCubit cubit;
  late MockDistingMidiManager manager;
  late DistingTools tools;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await AlgorithmMetadataService().initialize(database);
  });

  tearDownAll(() async {
    await database.close();
  });

  setUp(() {
    cubit = DistingCubit(database, midiCommand: MockMidiCommand());
    final controller = DistingControllerImpl(cubit);
    tools = DistingTools(controller, cubit);

    _emitSlotWithStringParameter(cubit);
    final state = cubit.state as DistingStateSynchronized;
    manager = state.disting as MockDistingMidiManager;
    when(
      () => manager.setParameterString(any(), any(), any()),
    ).thenAnswer((_) async {});
    when(() => manager.requestParameterValue(any(), any())).thenAnswer(
      (invocation) async => ParameterValue(
        algorithmIndex: invocation.positionalArguments[0] as int,
        parameterNumber: invocation.positionalArguments[1] as int,
        value: 0,
      ),
    );
    when(() => manager.requestParameterValueString(any(), any())).thenAnswer(
      (_) async => ParameterValueString(
        algorithmIndex: 0,
        parameterNumber: _stringParameterNumber,
        value: _channelName,
      ),
    );
  });

  tearDown(() {
    cubit.close();
  });

  group('text parameters', () {
    test('edit_parameter writes a string value instead of rejecting it', () async {
      final result = await tools.editParameter({
        'slot_index': 0,
        'parameter_number': _stringParameterNumber,
        'value': _channelName,
      });

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['success'], isNot(false), reason: result);
      expect(decoded['value'], _channelName);
      expect(decoded['is_string'], isTrue);
      verify(
        () => manager.setParameterString(
          0,
          _stringParameterNumber,
          _channelName,
        ),
      ).called(1);
    });

    test('edit_parameter rejects a numeric value for a text parameter', () async {
      final result = await tools.editParameter({
        'slot_index': 0,
        'parameter_number': _stringParameterNumber,
        'value': 42,
      });

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['success'], isFalse);
      expect(decoded['error'], contains('requires a string value'));
      verifyNever(() => manager.setParameterString(any(), any(), any()));
    });

    test('edit_parameter rejects text longer than the hardware limit', () async {
      final result = await tools.editParameter({
        'slot_index': 0,
        'parameter_number': _stringParameterNumber,
        'value': 'x' * 32,
      });

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['success'], isFalse);
      expect(decoded['error'], contains('31'));
      verifyNever(() => manager.setParameterString(any(), any(), any()));
    });

    test('get_parameter_value reports the text value', () async {
      final result = await tools.getParameterValue({
        'slot_index': 0,
        'parameter_number': _stringParameterNumber,
      });

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['is_string'], isTrue);
      expect(decoded['value'], _channelName);
    });

    test('set_parameter writes a string value', () async {
      final result = await tools.setParameterValue({
        'slot_index': 0,
        'parameter_number': _stringParameterNumber,
        'value': 'Lead',
      });

      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['success'], isTrue, reason: result);
      verify(
        () => manager.setParameterString(0, _stringParameterNumber, 'Lead'),
      ).called(1);
    });
  });
}
