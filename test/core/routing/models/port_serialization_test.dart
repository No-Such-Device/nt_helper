import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/port.dart';

void main() {
  group('Port Serialization Tests', () {
    group('Direct Properties Serialization', () {
      test(
        'should serialize and deserialize all direct properties correctly',
        () {
          final originalPort = Port(
            id: 'serialization_test_comprehensive',
            name: 'Comprehensive Serialization Test',
            type: PortType.cv,
            direction: PortDirection.output,
            description: 'Test port for serialization',
            isActive: false,
            outputMode: OutputMode.replace,
            // Direct properties
            isPolyVoice: true,
            voiceNumber: 5,
            isVirtualCV: true,
            isMultiChannel: true,
            channelNumber: 3,
            isStereoChannel: true,
            stereoSide: 'right',
            isMasterMix: false,
            busValue: 15,
            busParam: 'test_bus_param',
            parameterNumber: 42,
          );

          final json = originalPort.toJson();
          final deserializedPort = Port.fromJson(json);

          // Verify core properties
          expect(deserializedPort.id, equals(originalPort.id));
          expect(deserializedPort.name, equals(originalPort.name));
          expect(deserializedPort.type, equals(originalPort.type));
          expect(deserializedPort.direction, equals(originalPort.direction));
          expect(
            deserializedPort.description,
            equals(originalPort.description),
          );
          expect(deserializedPort.isActive, equals(originalPort.isActive));
          expect(deserializedPort.outputMode, equals(originalPort.outputMode));

          // Verify all direct properties
          expect(
            deserializedPort.isPolyVoice,
            equals(originalPort.isPolyVoice),
          );
          expect(
            deserializedPort.voiceNumber,
            equals(originalPort.voiceNumber),
          );
          expect(
            deserializedPort.isVirtualCV,
            equals(originalPort.isVirtualCV),
          );
          expect(
            deserializedPort.isMultiChannel,
            equals(originalPort.isMultiChannel),
          );
          expect(
            deserializedPort.channelNumber,
            equals(originalPort.channelNumber),
          );
          expect(
            deserializedPort.isStereoChannel,
            equals(originalPort.isStereoChannel),
          );
          expect(deserializedPort.stereoSide, equals(originalPort.stereoSide));
          expect(
            deserializedPort.isMasterMix,
            equals(originalPort.isMasterMix),
          );
          expect(deserializedPort.busValue, equals(originalPort.busValue));
          expect(deserializedPort.busParam, equals(originalPort.busParam));
          expect(
            deserializedPort.parameterNumber,
            equals(originalPort.parameterNumber),
          );

          // Verify complete object equality
          expect(deserializedPort, equals(originalPort));
        },
      );

      test(
        'should serialize and deserialize ports with null values correctly',
        () {
          final originalPort = Port(
            id: 'null_values_test',
            name: 'Null Values Test',
            type: PortType.audio,
            direction: PortDirection.input,
            // All optional direct properties left as defaults/null
          );

          final json = originalPort.toJson();
          final deserializedPort = Port.fromJson(json);

          // Verify default values are preserved
          expect(deserializedPort.isPolyVoice, isFalse);
          expect(deserializedPort.voiceNumber, isNull);
          expect(deserializedPort.isVirtualCV, isFalse);
          expect(deserializedPort.isMultiChannel, isFalse);
          expect(deserializedPort.channelNumber, isNull);
          expect(deserializedPort.isStereoChannel, isFalse);
          expect(deserializedPort.stereoSide, isNull);
          expect(deserializedPort.isMasterMix, isFalse);
          expect(deserializedPort.busValue, isNull);
          expect(deserializedPort.busParam, isNull);
          expect(deserializedPort.parameterNumber, isNull);

          expect(deserializedPort, equals(originalPort));
        },
      );

      test('should handle edge case values in serialization', () {
        final originalPort = Port(
          id: 'edge_case_test',
          name: 'Edge Case Test',
          type: PortType.cv,
          direction: PortDirection.bidirectional,
          // Edge case values
          voiceNumber: 0, // Zero voice number
          channelNumber: -1, // Negative channel number
          busValue: 1000, // Large bus value
          parameterNumber: 999999, // Large parameter number
          stereoSide: '', // Empty string
          busParam: '', // Empty bus param
        );

        final json = originalPort.toJson();
        final deserializedPort = Port.fromJson(json);

        expect(deserializedPort.voiceNumber, equals(0));
        expect(deserializedPort.channelNumber, equals(-1));
        expect(deserializedPort.busValue, equals(1000));
        expect(deserializedPort.parameterNumber, equals(999999));
        expect(deserializedPort.stereoSide, equals(''));
        expect(deserializedPort.busParam, equals(''));

        expect(deserializedPort, equals(originalPort));
      });
    });

    group('JSON Structure Tests', () {
      test('should include all direct properties in JSON output', () {
        final port = Port(
          id: 'json_structure_test',
          name: 'JSON Structure Test',
          type: PortType.cv,
          direction: PortDirection.input,
          isPolyVoice: true,
          voiceNumber: 2,
          isVirtualCV: true,
          isMultiChannel: true,
          channelNumber: 1,
          isStereoChannel: true,
          stereoSide: 'left',
          isMasterMix: false,
          busValue: 8,
          busParam: 'test_param',
          parameterNumber: 15,
        );

        final json = port.toJson();

        // Verify JSON contains all direct properties
        expect(json['isPolyVoice'], equals(true));
        expect(json['voiceNumber'], equals(2));
        expect(json['isVirtualCV'], equals(true));
        expect(json['isMultiChannel'], equals(true));
        expect(json['channelNumber'], equals(1));
        expect(json['isStereoChannel'], equals(true));
        expect(json['stereoSide'], equals('left'));
        expect(json['isMasterMix'], equals(false));
        expect(json['busValue'], equals(8));
        expect(json['busParam'], equals('test_param'));
        expect(json['parameterNumber'], equals(15));
      });

      test('should handle null values in JSON output correctly', () {
        final port = Port(
          id: 'null_handling_test',
          name: 'Null Handling Test',
          type: PortType.audio,
          direction: PortDirection.output,
          // Leave optional values as null
        );

        final json = port.toJson();

        // Null values may be present in JSON (depends on serialization config)
        // What's important is that deserialization handles them correctly
        final deserializedPort = Port.fromJson(json);

        expect(deserializedPort.voiceNumber, isNull);
        expect(deserializedPort.channelNumber, isNull);
        expect(deserializedPort.busValue, isNull);
        expect(deserializedPort.busParam, isNull);
        expect(deserializedPort.parameterNumber, isNull);
        expect(deserializedPort.stereoSide, isNull);

        // Boolean defaults should be preserved
        expect(deserializedPort.isPolyVoice, isFalse);
        expect(deserializedPort.isVirtualCV, isFalse);
        expect(deserializedPort.isMultiChannel, isFalse);
        expect(deserializedPort.isStereoChannel, isFalse);
        expect(deserializedPort.isMasterMix, isFalse);

        expect(deserializedPort, equals(port));
      });
    });

    group('Backward Compatibility Tests', () {
      test('should handle JSON without direct properties (legacy format)', () {
        // Simulate JSON from before direct properties were added
        final legacyJson = {
          'id': 'legacy_test',
          'name': 'Legacy Test Port',
          'type': 'cv',
          'direction': 'input',
          'isActive': true,
          // No direct properties in legacy JSON
        };

        final port = Port.fromJson(legacyJson);

        // Should create port with default values for direct properties
        expect(port.id, equals('legacy_test'));
        expect(port.name, equals('Legacy Test Port'));
        expect(port.type, equals(PortType.cv));
        expect(port.direction, equals(PortDirection.input));
        expect(port.isActive, isTrue);

        // Direct properties should have default values
        expect(port.isPolyVoice, isFalse);
        expect(port.voiceNumber, isNull);
        expect(port.isVirtualCV, isFalse);
        expect(port.isMultiChannel, isFalse);
        expect(port.channelNumber, isNull);
        expect(port.isStereoChannel, isFalse);
        expect(port.stereoSide, isNull);
        expect(port.isMasterMix, isFalse);
        expect(port.busValue, isNull);
        expect(port.busParam, isNull);
        expect(port.parameterNumber, isNull);
      }, tags: ['regression']);

      test('should handle mixed JSON with some direct properties', () {
        final mixedJson = {
          'id': 'mixed_test',
          'name': 'Mixed Test Port',
          'type': 'audio',
          'direction': 'output',
          'isActive': false,
          // Only some direct properties
          'isPolyVoice': true,
          'busValue': 10,
          'channelNumber': 2,
          // Missing: voiceNumber, isVirtualCV, etc.
        };

        final port = Port.fromJson(mixedJson);

        expect(port.isPolyVoice, isTrue);
        expect(port.busValue, equals(10));
        expect(port.channelNumber, equals(2));

        // Missing properties should have defaults
        expect(port.voiceNumber, isNull);
        expect(port.isVirtualCV, isFalse);
        expect(port.isStereoChannel, isFalse);
        expect(port.stereoSide, isNull);
        expect(port.isMasterMix, isFalse);
      });
    });

    group('Serialization Round-trip Tests', () {
      test(
        'should maintain data integrity through multiple serialization cycles',
        () {
          final originalPort = Port(
            id: 'round_trip_test',
            name: 'Round Trip Test',
            type: PortType.cv,
            direction: PortDirection.bidirectional,
            description: 'Testing round-trip serialization',
            outputMode: OutputMode.add,
            isPolyVoice: true,
            voiceNumber: 3,
            isVirtualCV: false,
            isMultiChannel: true,
            channelNumber: 4,
            isStereoChannel: true,
            stereoSide: 'right',
            isMasterMix: true,
            busValue: 12,
            busParam: 'round_trip_param',
            parameterNumber: 88,
          );

          // Multiple serialization/deserialization cycles
          Port currentPort = originalPort;
          for (int i = 0; i < 5; i++) {
            final json = currentPort.toJson();
            currentPort = Port.fromJson(json);
          }

          // Should still be identical after 5 cycles
          expect(currentPort, equals(originalPort));
          expect(currentPort.hashCode, equals(originalPort.hashCode));

          // Verify all properties individually
          expect(currentPort.id, equals(originalPort.id));
          expect(currentPort.name, equals(originalPort.name));
          expect(currentPort.type, equals(originalPort.type));
          expect(currentPort.direction, equals(originalPort.direction));
          expect(currentPort.description, equals(originalPort.description));
          expect(currentPort.outputMode, equals(originalPort.outputMode));
          expect(currentPort.isPolyVoice, equals(originalPort.isPolyVoice));
          expect(currentPort.voiceNumber, equals(originalPort.voiceNumber));
          expect(currentPort.isVirtualCV, equals(originalPort.isVirtualCV));
          expect(
            currentPort.isMultiChannel,
            equals(originalPort.isMultiChannel),
          );
          expect(currentPort.channelNumber, equals(originalPort.channelNumber));
          expect(
            currentPort.isStereoChannel,
            equals(originalPort.isStereoChannel),
          );
          expect(currentPort.stereoSide, equals(originalPort.stereoSide));
          expect(currentPort.isMasterMix, equals(originalPort.isMasterMix));
          expect(currentPort.busValue, equals(originalPort.busValue));
          expect(currentPort.busParam, equals(originalPort.busParam));
          expect(
            currentPort.parameterNumber,
            equals(originalPort.parameterNumber),
          );
        },
      );
    });

    group('Performance Tests', () {
      test('should handle large-scale serialization efficiently', () {
        final ports = <Port>[];

        // Create 1000 ports with various configurations
        for (int i = 0; i < 1000; i++) {
          ports.add(
            Port(
              id: 'perf_test_$i',
              name: 'Performance Test Port $i',
              type: PortType.values[i % PortType.values.length],
              direction: PortDirection.values[i % PortDirection.values.length],
              isPolyVoice: i % 2 == 0,
              voiceNumber: i % 2 == 0 ? i % 16 : null,
              busValue: i % 3 == 0 ? i % 20 + 1 : null,
              parameterNumber: i % 5 == 0 ? i : null,
              isMultiChannel: i % 4 == 0,
              channelNumber: i % 4 == 0 ? i % 8 : null,
            ),
          );
        }

        final stopwatch = Stopwatch()..start();

        // Serialize all ports
        final jsonList = ports.map((p) => p.toJson()).toList();

        // Deserialize all ports
        final deserializedPorts = jsonList
            .map((json) => Port.fromJson(json))
            .toList();

        stopwatch.stop();

        // Should complete within reasonable time (adjust as needed)
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
        ); // Less than 1 second

        // Verify data integrity
        expect(deserializedPorts.length, equals(ports.length));
        for (int i = 0; i < ports.length; i++) {
          expect(deserializedPorts[i], equals(ports[i]));
        }
      });
    });
  });
}
