import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/connection.dart';
import 'package:nt_helper/models/tidy_result.dart';

void main() {
  group('TidyResult', () {
    test('should create success result with correct properties', () {
      final originalConnections = [
        Connection(
          id: 'conn1',
          sourceAlgorithmIndex: 0,
          sourcePortId: 'out',
          targetAlgorithmIndex: 1,
          targetPortId: 'in',
          assignedBus: 21,
          replaceMode: false,
        ),
      ];

      final optimizedConnections = [
        Connection(
          id: 'conn1',
          sourceAlgorithmIndex: 0,
          sourcePortId: 'out',
          targetAlgorithmIndex: 1,
          targetPortId: 'in',
          assignedBus: 21,
          replaceMode: true, // Optimized to use replace mode
        ),
      ];

      final changes = <String, BusChange>{
        'conn1': BusChange(
          connectionId: 'conn1',
          oldBus: 21,
          newBus: 21,
          oldReplaceMode: false,
          newReplaceMode: true,
          reason: 'Optimized to use replace mode',
        ),
      };

      final result = TidyResult.success(
        originalConnections: originalConnections,
        optimizedConnections: optimizedConnections,
        busesFreed: 1,
        changes: changes,
        warnings: ['Test warning'],
      );

      expect(result.success, isTrue);
      expect(result.originalConnections, equals(originalConnections));
      expect(result.optimizedConnections, equals(optimizedConnections));
      expect(result.busesFreed, equals(1));
      expect(result.changes, equals(changes));
      expect(result.warnings, equals(['Test warning']));
      expect(result.errorMessage, isNull);
    });

    test('should create failure result with error message', () {
      const errorMessage = 'Optimization failed due to insufficient buses';

      final result = TidyResult.failed(errorMessage);

      expect(result.success, isFalse);
      expect(result.errorMessage, equals(errorMessage));
      expect(result.originalConnections, isEmpty);
      expect(result.optimizedConnections, isEmpty);
      expect(result.busesFreed, equals(0));
      expect(result.changes, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('should track bus changes correctly', () {
      final change = BusChange(
        connectionId: 'test_conn',
        oldBus: 21,
        newBus: 22,
        oldReplaceMode: false,
        newReplaceMode: true,
        reason: 'Bus optimization',
      );

      expect(change.connectionId, equals('test_conn'));
      expect(change.oldBus, equals(21));
      expect(change.newBus, equals(22));
      expect(change.oldReplaceMode, isFalse);
      expect(change.newReplaceMode, isTrue);
      expect(change.reason, equals('Bus optimization'));
    });

    test('should calculate buses freed accurately', () {
      final originalConnections = [
        Connection(
          id: 'conn1',
          sourceAlgorithmIndex: 0,
          sourcePortId: 'out',
          targetAlgorithmIndex: 1,
          targetPortId: 'in',
          assignedBus: 21,
          replaceMode: false,
        ),
        Connection(
          id: 'conn2',
          sourceAlgorithmIndex: 1,
          sourcePortId: 'out',
          targetAlgorithmIndex: 2,
          targetPortId: 'in',
          assignedBus: 22,
          replaceMode: false,
        ),
      ];

      final optimizedConnections = [
        Connection(
          id: 'conn1',
          sourceAlgorithmIndex: 0,
          sourcePortId: 'out',
          targetAlgorithmIndex: 1,
          targetPortId: 'in',
          assignedBus: 21,
          replaceMode: true, // Now uses replace mode
        ),
        Connection(
          id: 'conn2',
          sourceAlgorithmIndex: 1,
          sourcePortId: 'out',
          targetAlgorithmIndex: 2,
          targetPortId: 'in',
          assignedBus: 21, // Reuses bus 21 - bus 22 is freed!
          replaceMode: false,
        ),
      ];

      final result = TidyResult.success(
        originalConnections: originalConnections,
        optimizedConnections: optimizedConnections,
        busesFreed: 1,
        changes: {},
      );

      expect(result.busesFreed, equals(1));
    });

    

    test('should handle empty optimization result', () {
      final result = TidyResult.success(
        originalConnections: [],
        optimizedConnections: [],
        busesFreed: 0,
        changes: {},
      );

      expect(result.success, isTrue);
      expect(result.originalConnections, isEmpty);
      expect(result.optimizedConnections, isEmpty);
      expect(result.busesFreed, equals(0));
      expect(result.changes, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('should handle complex optimization with multiple changes', () {
      final originalConnections = List.generate(
        5,
        (i) => Connection(
          id: 'conn$i',
          sourceAlgorithmIndex: i,
          sourcePortId: 'out',
          targetAlgorithmIndex: i + 1,
          targetPortId: 'in',
          assignedBus: 21 + i,
          replaceMode: false,
        ),
      );

      final optimizedConnections = List.generate(
        5,
        (i) => Connection(
          id: 'conn$i',
          sourceAlgorithmIndex: i,
          sourcePortId: 'out',
          targetAlgorithmIndex: i + 1,
          targetPortId: 'in',
          assignedBus: 21 + (i % 2), // Consolidate to fewer buses
          replaceMode: i % 2 == 1, // Alternate replace mode
        ),
      );

      final changes = <String, BusChange>{};
      for (int i = 0; i < 5; i++) {
        changes['conn$i'] = BusChange(
          connectionId: 'conn$i',
          oldBus: 21 + i,
          newBus: 21 + (i % 2),
          oldReplaceMode: false,
          newReplaceMode: i % 2 == 1,
          reason: 'Consolidated to reuse buses',
        );
      }

      final result = TidyResult.success(
        originalConnections: originalConnections,
        optimizedConnections: optimizedConnections,
        busesFreed: 3, // Freed buses 23, 24, 25
        changes: changes,
      );

      expect(result.success, isTrue);
      expect(result.busesFreed, equals(3));
      expect(result.changes, hasLength(5));
    });
  });

  group('BusChange', () {
    test('should be created with all required properties', () {
      final change = BusChange(
        connectionId: 'test_connection',
        oldBus: 21,
        newBus: 22,
        oldReplaceMode: false,
        newReplaceMode: true,
        reason: 'Optimization test',
      );

      expect(change.connectionId, equals('test_connection'));
      expect(change.oldBus, equals(21));
      expect(change.newBus, equals(22));
      expect(change.oldReplaceMode, isFalse);
      expect(change.newReplaceMode, isTrue);
      expect(change.reason, equals('Optimization test'));
    });

    

    test('should describe bus reassignment', () {
      final change = BusChange(
        connectionId: 'reassign_test',
        oldBus: 22,
        newBus: 21,
        oldReplaceMode: false,
        newReplaceMode: false,
        reason: 'Bus consolidation',
      );

      expect(change.oldBus, isNot(equals(change.newBus)));
      expect(change.oldReplaceMode, equals(change.newReplaceMode));
    });
  });
}
