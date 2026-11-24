import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/mcp/tools/disting_tools.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/disting_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/cv_routing_fixture.dart';
import '../test_helpers/mock_midi_command.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Manager extends Mock implements IDistingMidiManager {}

class _Controller extends Mock implements DistingController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DistingCubit cubit;
  late _Manager manager;
  late DistingStateSynchronized original;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final db = _Database();
    final metadata = _Metadata();
    manager = _Manager();
    when(() => db.metadataDao).thenReturn(metadata);
    cubit = DistingCubit(db, midiCommand: MockMidiCommand());
    original = DistingState.synchronized(
      disting: manager,
      distingVersion: '1.20beta',
      firmwareVersion: FirmwareVersion('1.20beta'),
      presetName: 'CV fixture',
      algorithms: const [],
      slots: [
        cvSlot(0, outputs: [32]),
        cvSlot(1, cvBuses: [32], source: 2),
      ],
      unitStrings: const [],
    ) as DistingStateSynchronized;
    cubit.emit(original);
  });
  tearDown(() => cubit.close());

  test(
    'shared up/down entry points reject before optimistic mutation or MIDI',
    () async {
      await expectLater(cubit.moveAlgorithmUp(1), throwsStateError);
      await expectLater(cubit.moveAlgorithmDown(0), throwsStateError);
      expect(cubit.state, same(original));
      verifyZeroInteractions(manager);
    },
  );

  test(
    'notes insertion composite fails before adding, editing or moving anything',
    () async {
      final controller = _Controller();
      final result = jsonDecode(
        await DistingTools(controller, cubit).setNotes({'text': 'Notes'}),
      ) as Map;
      expect(result['success'], false);
      expect(result['error'].toString(), contains('CV mapping'));
      expect(cubit.state, same(original));
      verifyZeroInteractions(controller);
      verifyZeroInteractions(manager);
    },
  );
}
