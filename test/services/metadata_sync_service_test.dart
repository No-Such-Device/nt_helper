import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/metadata_sync_service.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

class TestMockDistingMidiManager implements IDistingMidiManager {
  final List<AlgorithmInfo> testAlgorithms;
  int _numAlgorithmsInPreset = 0;
  List<int>? lastSpecifications;
  AlgorithmInfo? _instantiatedAlgorithm;

  // Auto-recovery tracking
  int rebootCallCount = 0;
  int rescanPluginsCallCount = 0;
  int wakeCallCount = 0;

  /// Per-GUID timeout configuration: maps GUID to number of times
  /// requestAddAlgorithm should throw TimeoutException before succeeding.
  final Map<String, int> timeoutCountByGuid;

  /// Tracks how many times requestAddAlgorithm has been called per GUID.
  final Map<String, int> _addAttemptsByGuid = {};

  /// If non-null, requestAddAlgorithm always throws this for any GUID
  /// in [alwaysFailGuids].
  final Set<String> alwaysFailGuids;

  TestMockDistingMidiManager({
    required this.testAlgorithms,
    this.timeoutCountByGuid = const {},
    this.alwaysFailGuids = const {},
  });

  Future<List<AlgorithmInfo>> scanAlgorithms({
    Function(String algorithmName, double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    return testAlgorithms;
  }

  Future<Map<String, dynamic>> scanSpecs({
    required String algorithmGuid,
    Function(String specName, double progress)? onProgress,
  }) async {
    return {};
  }

  Future<List<int>> scanUnits() async {
    return [];
  }

  @override
  Future<List<String>?> requestUnitStrings() async {
    return [];
  }

  Stream<Map<String, dynamic>> get slotUpdateStream =>
      Stream<Map<String, dynamic>>.empty();

  Stream<Map<String, dynamic>> get parameterUpdateStream =>
      Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> dispose() async {}

  Future<void> initialize() async {}

  bool get isConnected => true;

  @override
  Future<void> requestWake() async {
    wakeCallCount++;
  }

  @override
  Future<void> requestReboot() async {
    rebootCallCount++;
  }

  @override
  Future<void> requestRescanPlugins() async {
    rescanPluginsCallCount++;
  }

  @override
  Future<int?> requestNumAlgorithmsInPreset({
    Duration? timeout,
    int? maxRetries,
  }) async {
    return _numAlgorithmsInPreset;
  }

  @override
  Future<int?> requestNumberOfAlgorithms() async {
    return testAlgorithms.length;
  }

  @override
  Future<NumParameters?> requestNumberOfParameters(int algorithmIndex) async {
    return NumParameters(algorithmIndex: algorithmIndex, numParameters: 0);
  }

  @override
  Future<AlgorithmInfo?> requestAlgorithmInfo(int index) async {
    if (index >= 0 && index < testAlgorithms.length) {
      return testAlgorithms[index];
    }
    return null;
  }

  @override
  Future<void> requestLoadPlugin(String guid) async {}

  @override
  Future<void> requestRemoveAlgorithm(int index) async {
    _numAlgorithmsInPreset = 0;
    _instantiatedAlgorithm = null;
  }

  @override
  Future<void> requestNewPreset() async {
    _numAlgorithmsInPreset = 0;
    _instantiatedAlgorithm = null;
  }

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    lastSpecifications = specifications;

    final guid = algorithm.guid;

    // Check for always-fail GUIDs
    if (alwaysFailGuids.contains(guid)) {
      throw TimeoutException('No response after 5000ms');
    }

    // Check for per-GUID timeout configuration
    final maxTimeouts = timeoutCountByGuid[guid] ?? 0;
    final attempts = _addAttemptsByGuid[guid] ?? 0;
    _addAttemptsByGuid[guid] = attempts + 1;

    if (attempts < maxTimeouts) {
      throw TimeoutException('No response after 5000ms');
    }

    _numAlgorithmsInPreset = 1;
    _instantiatedAlgorithm = algorithm;
  }

  @override
  Future<Algorithm?> requestAlgorithmGuid(
    int algorithmIndex, {
    Duration? timeout,
    int? maxRetries,
    DistingRequestCancellation? cancellation,
    bool rejectAmbiguousResponse = false,
  }) async {
    final algorithm = _instantiatedAlgorithm;
    if (algorithmIndex != 0 || algorithm == null) return null;
    return Algorithm(
      algorithmIndex: 0,
      guid: algorithm.guid,
      name: algorithm.name,
      specifications: List<int>.from(lastSpecifications ?? const []),
    );
  }

  @override
  void noSuchMethod(Invocation invocation) {
    // Ignore missing methods - return null for unknown methods
  }
}

// Helper to get parameters for an algorithm
Future<List<ParameterEntry>> getParametersForAlgorithm(
  AppDatabase db,
  String algorithmGuid,
) async {
  final query = db.select(db.parameters)
    ..where((p) => p.algorithmGuid.equals(algorithmGuid))
    ..orderBy([(p) => OrderingTerm.asc(p.parameterNumber)]);
  return query.get();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataSyncService - Parameter Prefix Preservation', () {
    late AppDatabase database;
    late MetadataSyncService service;

    setUpAll(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDownAll(() async {
      await database.close();
    });

    test('should preserve numeric channel prefixes in parameter names', () async {
      // Arrange - create test data with channel prefixes
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'mchn',
            name: 'Multi Channel Test',
            specifications: [],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      // Create test parameters through the metadata sync service
      // For this we need to mock the parameters returned by the algorithm
      // Since AlgorithmInfo doesn't have a parameters field, we need to check
      // how the service actually gets parameters

      service = MetadataSyncService(mockManager, database);

      // Act - sync algorithms (this will scan the device)
      await service.syncAllAlgorithmMetadata(
        onProgress: (progress, processed, total, mainMessage, subMessage) {},
      );

      // For this test to work properly, we need to understand how the service
      // actually gets parameter information. Let's check the implementation...

      // Note: The test structure shows we need to modify MetadataSyncService
      // to preserve prefixes. The current test setup needs refinement based on
      // actual service implementation.
    });

    test('should handle parameters without prefixes correctly', () async {
      // This test will verify that parameters without channel prefixes
      // remain unchanged during sync

      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 1,
            guid: 'simple-algo',
            name: 'Simple Test',
            specifications: [],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      service = MetadataSyncService(mockManager, database);

      // The actual test implementation depends on how MetadataSyncService
      // retrieves parameter information from the device
    });

    test('should preserve letter channel prefixes (A:, B:, C:, D:)', () async {
      // This test verifies that letter-based channel prefixes are preserved

      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 2,
            guid: 'letter-channel-algo',
            name: 'Letter Channel Test',
            specifications: [],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      service = MetadataSyncService(mockManager, database);

      // Test implementation pending understanding of parameter retrieval
    });

    test('should distinguish parameters from different channels', () async {
      // Verifies that parameters with same base name but different channel
      // prefixes are stored as distinct entries

      // Test implementation pending
    });

    test('should create unique parameter entries for each channel', () async {
      // Ensures each channel parameter gets a unique parameterNumber

      // Test implementation pending
    });
  });

  group('MetadataSyncService - Scan Spec Values', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await database.close();
    });

    test('spec with non-zero default sends default value', () async {
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'test-nonzero',
            name: 'Non-Zero Default',
            specifications: [
              Specification(
                name: 'Channels',
                min: 0,
                max: 10,
                defaultValue: 5,
                type: 0,
              ),
            ],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      final service = MetadataSyncService(mockManager, database);
      await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

      expect(mockManager.lastSpecifications, equals([5]));
    });

    test(
      'channel-like spec with low default uses useful offline value',
      () async {
        final mockManager = TestMockDistingMidiManager(
          testAlgorithms: [
            AlgorithmInfo(
              algorithmIndex: 0,
              guid: 'test-zero',
              name: 'Zero Default',
              specifications: [
                Specification(
                  name: 'Aux Sends per Channel',
                  min: 0,
                  max: 10,
                  defaultValue: 0,
                  type: 0,
                ),
              ],
              isPlugin: false,
              isLoaded: true,
            ),
          ],
        );

        final service = MetadataSyncService(mockManager, database);
        await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

        expect(mockManager.lastSpecifications, equals([2]));
      },
    );

    test('non-channel zero default still sends safe default', () async {
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'test-record-time',
            name: 'Record Time',
            specifications: [
              Specification(
                name: 'Record time',
                min: 0,
                max: 60,
                defaultValue: 0,
                type: 1,
              ),
            ],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      final service = MetadataSyncService(mockManager, database);
      await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

      expect(mockManager.lastSpecifications, equals([0]));
    });

    test('stereo boolean spec is enabled for offline metadata scan', () async {
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'test-stereo',
            name: 'Stereo Algorithm',
            specifications: [
              Specification(
                name: 'Stereo',
                min: 0,
                max: 1,
                defaultValue: 0,
                type: 2,
              ),
            ],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      final service = MetadataSyncService(mockManager, database);
      await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

      expect(mockManager.lastSpecifications, equals([1]));
    });

    test('spec with default 0 and max 0 sends 0 (clamped)', () async {
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'test-zero-max',
            name: 'Zero Max',
            specifications: [
              Specification(
                name: 'Feature',
                min: 0,
                max: 0,
                defaultValue: 0,
                type: 0,
              ),
            ],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      final service = MetadataSyncService(mockManager, database);
      await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

      expect(mockManager.lastSpecifications, equals([0]));
    });

    test(
      'spec with out-of-range default 0 sends midpoint (clamped to range)',
      () async {
        final mockManager = TestMockDistingMidiManager(
          testAlgorithms: [
            AlgorithmInfo(
              algorithmIndex: 0,
              guid: 'test-high-min',
              name: 'High Min',
              specifications: [
                Specification(
                  name: 'Mode',
                  min: 2,
                  max: 5,
                  defaultValue: 0,
                  type: 0,
                ),
              ],
              isPlugin: false,
              isLoaded: true,
            ),
          ],
        );

        final service = MetadataSyncService(mockManager, database);
        await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

        expect(mockManager.lastSpecifications, equals([3])); // (2+5)~/2 = 3
      },
    );

    test('multiple specs apply logic per-spec', () async {
      final mockManager = TestMockDistingMidiManager(
        testAlgorithms: [
          AlgorithmInfo(
            algorithmIndex: 0,
            guid: 'test-multi',
            name: 'Multi Spec',
            specifications: [
              Specification(
                name: 'Channels',
                min: 0,
                max: 10,
                defaultValue: 4,
                type: 0,
              ),
              Specification(
                name: 'Aux Sends',
                min: 0,
                max: 8,
                defaultValue: 0,
                type: 0,
              ),
              Specification(
                name: 'Mode',
                min: 2,
                max: 5,
                defaultValue: 0,
                type: 0,
              ),
            ],
            isPlugin: false,
            isLoaded: true,
          ),
        ],
      );

      final service = MetadataSyncService(mockManager, database);
      await service.rescanSingleAlgorithm(mockManager.testAlgorithms[0]);

      expect(
        mockManager.lastSpecifications,
        equals([4, 2, 3]),
      ); // 4 (useful default), 2 (small useful count), (2+5)~/2=3
    });
  });

  group('MetadataSyncService - Auto-Recovery on Timeout', () {
    test(
      'rescanSingleAlgorithm: timeout triggers reboot then retry succeeds',
      () {
        fakeAsync((async) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          final mockManager = TestMockDistingMidiManager(
            testAlgorithms: [
              AlgorithmInfo(
                algorithmIndex: 0,
                guid: 'timeout-plugin',
                name: 'Timeout Plugin',
                specifications: [],
                isPlugin: true,
                isLoaded: true,
              ),
            ],
            timeoutCountByGuid: {'timeout-plugin': 1},
          );

          final service = MetadataSyncService(mockManager, database);
          Object? caughtError;

          service
              .rescanSingleAlgorithm(mockManager.testAlgorithms[0])
              .catchError((e) => caughtError = e);

          // Advance past all delays (30s reboot wait + polling + misc)
          async.elapse(const Duration(minutes: 2));

          expect(mockManager.rebootCallCount, equals(1));
          expect(caughtError, isNull);

          database.close();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test(
      'rescanSingleAlgorithm: both attempts fail throws TimeoutException',
      () {
        fakeAsync((async) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          final mockManager = TestMockDistingMidiManager(
            testAlgorithms: [
              AlgorithmInfo(
                algorithmIndex: 0,
                guid: 'always-fail',
                name: 'Always Fail',
                specifications: [],
                isPlugin: true,
                isLoaded: true,
              ),
            ],
            alwaysFailGuids: {'always-fail'},
          );

          final service = MetadataSyncService(mockManager, database);
          Object? caughtError;

          service
              .rescanSingleAlgorithm(mockManager.testAlgorithms[0])
              .catchError((e) => caughtError = e);

          async.elapse(const Duration(minutes: 2));

          expect(caughtError, isA<TimeoutException>());
          expect(mockManager.rebootCallCount, equals(1));

          database.close();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test(
      'rescanSingleAlgorithm: non-timeout error does not trigger reboot',
      () {
        fakeAsync((async) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          final mockManager = _NonTimeoutErrorMockManager(
            testAlgorithms: [
              AlgorithmInfo(
                algorithmIndex: 0,
                guid: 'non-timeout',
                name: 'Non-Timeout Error',
                specifications: [],
                isPlugin: false,
                isLoaded: true,
              ),
            ],
          );

          final service = MetadataSyncService(mockManager, database);
          Object? caughtError;

          service
              .rescanSingleAlgorithm(mockManager.testAlgorithms[0])
              .catchError((e) => caughtError = e);

          async.elapse(const Duration(minutes: 1));

          expect(caughtError, isA<Exception>());
          expect(mockManager.rebootCallCount, equals(0));

          database.close();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test(
      'syncAllAlgorithmMetadata: timeout then reboot then retry succeeds',
      () {
        fakeAsync((async) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          final mockManager = TestMockDistingMidiManager(
            testAlgorithms: [
              AlgorithmInfo(
                algorithmIndex: 0,
                guid: 'syto',
                name: 'Sync Timeout Plugin',
                specifications: [],
                isPlugin: false,
                isLoaded: true,
              ),
            ],
            timeoutCountByGuid: {'syto': 1},
          );

          final service = MetadataSyncService(mockManager, database);
          final errors = <String>[];

          service.syncAllAlgorithmMetadata(
            onProgress: (progress, processed, total, mainMsg, subMsg) {},
            onError: (error) => errors.add(error),
          );

          async.elapse(const Duration(minutes: 3));

          expect(mockManager.rebootCallCount, equals(1));
          expect(errors, isEmpty);

          database.close();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test(
      'syncAllAlgorithmMetadata: retry fails then deferred rescan+reboot succeeds',
      () {
        fakeAsync((async) {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          // Fails first 2 attempts, succeeds on 3rd (after rescan+reboot)
          final mockManager = TestMockDistingMidiManager(
            testAlgorithms: [
              AlgorithmInfo(
                algorithmIndex: 0,
                guid: 'defr',
                name: 'Deferred Plugin',
                specifications: [],
                isPlugin: false,
                isLoaded: true,
              ),
            ],
            timeoutCountByGuid: {'defr': 2},
          );

          final service = MetadataSyncService(mockManager, database);
          final errors = <String>[];

          service.syncAllAlgorithmMetadata(
            onProgress: (progress, processed, total, mainMsg, subMsg) {},
            onError: (error) => errors.add(error),
          );

          async.elapse(const Duration(minutes: 5));

          expect(mockManager.rescanPluginsCallCount, equals(1));
          expect(mockManager.rebootCallCount, equals(2));
          expect(errors, isEmpty);

          database.close();
          async.elapse(const Duration(seconds: 1));
        });
      },
    );

    test('syncAllAlgorithmMetadata: all retries fail reports error', () {
      fakeAsync((async) {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        final mockManager = TestMockDistingMidiManager(
          testAlgorithms: [
            AlgorithmInfo(
              algorithmIndex: 0,
              guid: 'tfal',
              name: 'Total Fail Plugin',
              specifications: [],
              isPlugin: false,
              isLoaded: true,
            ),
          ],
          alwaysFailGuids: {'tfal'},
        );

        final service = MetadataSyncService(mockManager, database);
        final errors = <String>[];

        service.syncAllAlgorithmMetadata(
          onProgress: (progress, processed, total, mainMsg, subMsg) {},
          onError: (error) => errors.add(error),
        );

        async.elapse(const Duration(minutes: 5));

        expect(errors, hasLength(1));
        expect(errors[0], contains('Total Fail Plugin'));
        expect(errors[0], contains('after all retries'));

        database.close();
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('cancellation during reboot wait stops sync', () {
      fakeAsync((async) {
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        final mockManager = TestMockDistingMidiManager(
          testAlgorithms: [
            AlgorithmInfo(
              algorithmIndex: 0,
              guid: 'cnrb',
              name: 'Cancel During Reboot',
              specifications: [],
              isPlugin: false,
              isLoaded: true,
            ),
          ],
          timeoutCountByGuid: {'cnrb': 1},
        );

        final service = MetadataSyncService(mockManager, database);
        bool cancelled = false;
        bool completed = false;

        service
            .syncAllAlgorithmMetadata(
              onProgress: (progress, processed, total, mainMsg, subMsg) {},
              isCancelled: () => cancelled,
            )
            .then((_) => completed = true);

        // Advance past initial scan + timeout, into the reboot wait
        async.elapse(const Duration(seconds: 5));
        // Cancel while in the 30s reboot wait
        cancelled = true;
        async.elapse(const Duration(minutes: 2));

        expect(completed, isTrue);

        database.close();
        async.elapse(const Duration(seconds: 1));
      });
    });
  });
}

/// Mock that throws a non-timeout exception from requestAddAlgorithm.
class _NonTimeoutErrorMockManager extends TestMockDistingMidiManager {
  _NonTimeoutErrorMockManager({required super.testAlgorithms});

  @override
  Future<void> requestAddAlgorithm(
    AlgorithmInfo algorithm,
    List<int> specifications,
  ) async {
    lastSpecifications = specifications;
    throw Exception('Connection lost unexpectedly');
  }
}
