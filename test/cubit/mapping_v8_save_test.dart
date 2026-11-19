import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/packed_mapping_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/mock_midi_command.dart';
import '../test_helpers/mapping_v8.dart';

class _Database extends Mock implements AppDatabase {}

class _Metadata extends Mock implements MetadataDao {}

class _Manager extends Mock implements IDistingMidiManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(PackedMappingData.filler()));

  test('v8 saves retain options and retry a mismatched bypass readback', () {
    SharedPreferences.setMockInitialValues({});
    final db = _Database();
    final metadata = _Metadata();
    final manager = _Manager();
    when(() => db.metadataDao).thenReturn(metadata);
    when(() => metadata.hasCachedAlgorithms()).thenAnswer((_) async => false);
    when(
      () => metadata.getAlgorithmInfoCache(
        any(),
        cacheFreshnessDays: any(named: 'cacheFreshnessDays'),
      ),
    ).thenAnswer((_) async => []);
    final cubit = DistingCubit(db, midiCommand: MockMidiCommand());
    addTearDown(cubit.close);
    fakeAsync((async) {
      final desired = PackedMappingData.fromBytes(8, mappingV8Fixture());
      final writes = <PackedMappingData>[];
      var reads = 0;
      when(() => manager.requestSetMapping(any(), any(), any()))
          .thenAnswer((invocation) async {
            writes.add(invocation.positionalArguments[2] as PackedMappingData);
          });
      when(() => manager.requestMappings(0, 0)).thenAnswer(
        (_) async => Mapping(
          algorithmIndex: 0,
          parameterNumber: 0,
          packedMappingData: ++reads == 1
              ? desired.copyWith(midiIgnoreWhenBypassed: false)
              : desired,
        ),
      );
      cubit.emit(
        DistingState.synchronized(
          disting: manager,
          distingVersion: '1.20beta',
          firmwareVersion: FirmwareVersion('1.20beta'),
          presetName: 'Test',
          algorithms: const [],
          slots: const [],
          unitStrings: const [],
        ),
      );
      var completed = false;
      cubit.saveMappingImmediately(0, 0, desired).then((_) => completed = true);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 400));
      async.flushMicrotasks();
      expect(completed, isTrue);
      expect(writes.length, 2);
      expect(
        writes.every((mapping) => mapping.version == 8 && mapping == desired),
        isTrue,
      );
    });
  });
}
