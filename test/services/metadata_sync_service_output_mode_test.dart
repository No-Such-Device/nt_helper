import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/metadata_sync_service.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:drift/native.dart';

// Mock DistingMidiManager
class MockDistingMidiManager implements IDistingMidiManager {
  final AlgorithmInfo algorithmInfo;
  final ParameterInfo parameterInfo;
  final OutputModeUsage? outputModeUsage;

  int _numAlgorithmsInPreset = 0;
  List<int> _instantiatedSpecifications = const [];

  MockDistingMidiManager({
    required this.algorithmInfo,
    required this.parameterInfo,
    this.outputModeUsage,
  });

  @override
  Future<void> requestWake() async {}

  @override
  Future<void> requestNewPreset() async {
    _numAlgorithmsInPreset = 0;
    _instantiatedSpecifications = const [];
  }

  @override
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  }) async => _numAlgorithmsInPreset;

  @override
  Future<List<String>?> requestUnitStrings() async => [];

  @override
  Future<int?> requestNumberOfAlgorithms() async => 1;

  @override
  Future<AlgorithmInfo?> requestAlgorithmInfo(int index) async => algorithmInfo;

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    _numAlgorithmsInPreset = 1;
    _instantiatedSpecifications = List.unmodifiable(specifications);
  }

  @override
  Future<Algorithm?> requestAlgorithmGuid(
    int algorithmIndex, {
    Duration? timeout,
    int? maxRetries,
  }) async {
    if (algorithmIndex != 0 || _numAlgorithmsInPreset == 0) return null;
    return Algorithm(
      algorithmIndex: 0,
      guid: algorithmInfo.guid,
      name: algorithmInfo.name,
      specifications: _instantiatedSpecifications,
    );
  }

  @override
  Future<void> requestRemoveAlgorithm(int algorithmIndex) async {
    _numAlgorithmsInPreset = 0;
    _instantiatedSpecifications = const [];
  }

  @override
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex) async {
    return NumParameters(algorithmIndex: algorithmIndex, numParameters: 1);
  }

  @override
  Future<ParameterPages?> requestParameterPages(int algorithmIndex) async {
    return ParameterPages(algorithmIndex: algorithmIndex, pages: []);
  }

  @override
  Future<ParameterInfo?> requestParameterInfo(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    if (parameterNumber == parameterInfo.parameterNumber) {
      return parameterInfo;
    }
    return null;
  }

  @override
  Future<ParameterEnumStrings?> requestParameterEnumStrings(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    return null;
  }

  @override
  Future<OutputModeUsage?> requestOutputModeUsage(
    int algorithmIndex,
    int parameterNumber,
  ) async {
    if (parameterNumber == parameterInfo.parameterNumber) {
      return outputModeUsage;
    }
    return null;
  }

  @override
  Future<void> requestLoadPlugin(String guid) async {}

  @override
  void noSuchMethod(Invocation invocation) {
    // Allow other methods to be called without error, returning null or void
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataSyncService - Output Mode Usage', () {
    late AppDatabase database;
    late MetadataSyncService service;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test(
      'should persist output mode usage when parameter has isOutputMode flag',
      () async {
        // Arrange
        const algoGuid = 'tag1';
        const paramNum =
            0; // Must be 0 because requestNumberOfParameters returns 1, so loop queries index 0
        final affectedOutputs = [0];

        final algoInfo = AlgorithmInfo(
          algorithmIndex: 0,
          guid: algoGuid,
          name: 'Test Algo',
          specifications: [],
          isPlugin: false,
        );

        final paramInfo = ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          min: 0,
          max: 10,
          defaultValue: 0,
          unit: 0,
          name: 'Output Mode',
          powerOfTen: 0,
          ioFlags: 8, // Bit 3 set -> isOutputMode = true
        );

        final outputModeUsage = OutputModeUsage(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          affectedParameterNumbers: affectedOutputs,
        );

        final mockManager = MockDistingMidiManager(
          algorithmInfo: algoInfo,
          parameterInfo: paramInfo,
          outputModeUsage: outputModeUsage,
        );

        service = MetadataSyncService(mockManager, database);

        // Act
        await service.syncAllAlgorithmMetadata();

        // Assert
        final entries = await database.metadataDao.getAllOutputModeUsage();
        expect(entries, isNotEmpty);
        expect(entries.length, equals(1));
        expect(entries.first.algorithmGuid, equals(algoGuid));
        expect(entries.first.parameterNumber, equals(paramNum));
        expect(entries.first.affectedOutputNumbers, equals(affectedOutputs));
      },
    );

    test(
      'should NOT persist output mode usage when parameter does NOT have isOutputMode flag',
      () async {
        // Arrange
        const algoGuid = 'tag2';
        const paramNum = 0;

        final algoInfo = AlgorithmInfo(
          algorithmIndex: 0,
          guid: algoGuid,
          name: 'Test Algo 2',
          specifications: [],
          isPlugin: false,
        );

        final paramInfo = ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: paramNum,
          min: 0,
          max: 10,
          defaultValue: 0,
          unit: 0,
          name: 'Normal Param',
          powerOfTen: 0,
          ioFlags: 0, // isOutputMode = false
        );

        final mockManager = MockDistingMidiManager(
          algorithmInfo: algoInfo,
          parameterInfo: paramInfo,
          outputModeUsage: null, // Should not be called anyway
        );

        service = MetadataSyncService(mockManager, database);

        // Act
        await service.syncAllAlgorithmMetadata();

        // Assert
        final entries = await database.metadataDao.getAllOutputModeUsage();
        expect(entries, isEmpty);
      },
    );
  });
}
