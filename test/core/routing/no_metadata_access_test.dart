import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/port.dart';

void main() {
  group('No Metadata Access Tests', () {
    group('Port Model Validation', () {
      

      test('should only use direct properties in JSON serialization', () {
        const port = Port(
          id: 'json_test',
          name: 'JSON Test',
          type: PortType.audio,
          direction: PortDirection.output,
          isPolyVoice: true,
          voiceNumber: 3,
          busValue: 8,
          busParam: 'json_param',
          parameterNumber: 15,
          isVirtualCV: false,
          isMultiChannel: true,
          channelNumber: 2,
          isStereoChannel: true,
          stereoSide: 'right',
          isMasterMix: true,
        );

        final json = port.toJson();

        // Verify metadata field is not in JSON
        expect(json.containsKey('metadata'), isFalse);

        // Verify all direct properties are in JSON
        expect(json['isPolyVoice'], isTrue);
        expect(json['voiceNumber'], equals(3));
        expect(json['busValue'], equals(8));
        expect(json['busParam'], equals('json_param'));
        expect(json['parameterNumber'], equals(15));
        expect(json['isVirtualCV'], isFalse);
        expect(json['isMultiChannel'], isTrue);
        expect(json['channelNumber'], equals(2));
        expect(json['isStereoChannel'], isTrue);
        expect(json['stereoSide'], equals('right'));
        expect(json['isMasterMix'], isTrue);
      });

      test('should deserialize from JSON without metadata', () {
        final json = {
          'id': 'deserialize_test',
          'name': 'Deserialize Test',
          'type': 'cv',
          'direction': 'bidirectional',
          'isActive': false,
          'isPolyVoice': true,
          'voiceNumber': 4,
          'busValue': 12,
          'busParam': 'deserialize_param',
          'parameterNumber': 20,
          'isVirtualCV': true,
          'isMultiChannel': true,
          'channelNumber': 3,
          'isStereoChannel': false,
          'stereoSide': null,
          'isMasterMix': false,
        };

        final port = Port.fromJson(json);

        // Verify all properties are correctly deserialized
        expect(port.id, equals('deserialize_test'));
        expect(port.name, equals('Deserialize Test'));
        expect(port.type, equals(PortType.cv));
        expect(port.direction, equals(PortDirection.bidirectional));
        expect(port.isActive, isFalse);
        expect(port.isPolyVoice, isTrue);
        expect(port.voiceNumber, equals(4));
        expect(port.busValue, equals(12));
        expect(port.busParam, equals('deserialize_param'));
        expect(port.parameterNumber, equals(20));
        expect(port.isVirtualCV, isTrue);
        expect(port.isMultiChannel, isTrue);
        expect(port.channelNumber, equals(3));
        expect(port.isStereoChannel, isFalse);
        expect(port.stereoSide, isNull);
        expect(port.isMasterMix, isFalse);
      });
    });

    group('Code Architecture Validation', () {
      test(
        'should demonstrate clean architecture without metadata coupling',
        () {
          // Create a port with all direct properties
          const inputPort = Port(
            id: 'clean_input',
            name: 'Clean Input Port',
            type: PortType.cv,
            direction: PortDirection.input,
            isPolyVoice: true,
            voiceNumber: 1,
            busValue: 3,
            busParam: 'input_level',
            parameterNumber: 5,
            isVirtualCV: false,
          );

          const outputPort = Port(
            id: 'clean_output',
            name: 'Clean Output Port',
            type: PortType.cv,
            direction: PortDirection.output,
            isMultiChannel: true,
            channelNumber: 2,
            isStereoChannel: true,
            stereoSide: 'left',
            isMasterMix: false,
            busValue: 15,
            busParam: 'output_level',
            parameterNumber: 25,
          );

          // Test that all common port operations work with direct properties
          expect(inputPort.canConnectTo(outputPort), isTrue);
          expect(inputPort.isCompatibleWith(outputPort), isTrue);

          // Test that serialization round-trip works
          final inputJson = inputPort.toJson();
          final outputJson = outputPort.toJson();

          final deserializedInput = Port.fromJson(inputJson);
          final deserializedOutput = Port.fromJson(outputJson);

          expect(deserializedInput, equals(inputPort));
          expect(deserializedOutput, equals(outputPort));

          // Verify specific direct properties after deserialization
          expect(deserializedInput.isPolyVoice, isTrue);
          expect(deserializedInput.voiceNumber, equals(1));
          expect(deserializedInput.busValue, equals(3));

          expect(deserializedOutput.isMultiChannel, isTrue);
          expect(deserializedOutput.channelNumber, equals(2));
          expect(deserializedOutput.stereoSide, equals('left'));
        },
      );

      test('should handle edge cases without metadata dependency', () {
        // Test with minimal properties
        const minimalPort = Port(
          id: 'minimal',
          name: 'Minimal Port',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(minimalPort.isPolyVoice, isFalse);
        expect(minimalPort.voiceNumber, isNull);
        expect(minimalPort.isMultiChannel, isFalse);
        expect(minimalPort.channelNumber, isNull);
        expect(minimalPort.busValue, isNull);

        // Test with all properties set
        const maximalPort = Port(
          id: 'maximal',
          name: 'Maximal Port',
          type: PortType.cv,
          direction: PortDirection.output,
          outputMode: OutputMode.replace,
          isPolyVoice: true,
          voiceNumber: 8,
          isVirtualCV: true,
          isMultiChannel: true,
          channelNumber: 7,
          isStereoChannel: true,
          stereoSide: 'right',
          isMasterMix: true,
          busValue: 20,
          busParam: 'max_param',
          parameterNumber: 99,
        );

        expect(maximalPort.isPolyVoice, isTrue);
        expect(maximalPort.voiceNumber, equals(8));
        expect(maximalPort.isVirtualCV, isTrue);
        expect(maximalPort.isMultiChannel, isTrue);
        expect(maximalPort.channelNumber, equals(7));
        expect(maximalPort.isStereoChannel, isTrue);
        expect(maximalPort.stereoSide, equals('right'));
        expect(maximalPort.isMasterMix, isTrue);
        expect(maximalPort.busValue, equals(20));
        expect(maximalPort.busParam, equals('max_param'));
        expect(maximalPort.parameterNumber, equals(99));

        // Verify serialization works for both
        final minimalJson = minimalPort.toJson();
        final maximalJson = maximalPort.toJson();

        expect(Port.fromJson(minimalJson), equals(minimalPort));
        expect(Port.fromJson(maximalJson), equals(maximalPort));
      });
    });

    group('Migration Validation', () {
      test('should handle legacy JSON gracefully', () {
        // Simulate JSON from before the refactoring (no direct properties)
        final legacyJson = {
          'id': 'legacy_port',
          'name': 'Legacy Port',
          'type': 'audio',
          'direction': 'input',
          'isActive': true,
          'description': 'A port from the old system',
        };

        final port = Port.fromJson(legacyJson);

        expect(port.id, equals('legacy_port'));
        expect(port.name, equals('Legacy Port'));
        expect(port.type, equals(PortType.audio));
        expect(port.direction, equals(PortDirection.input));
        expect(port.isActive, isTrue);
        expect(port.description, equals('A port from the old system'));

        // All direct properties should have default values
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
      });

      test('should maintain forward compatibility', () {
        // Create a port with current direct properties
        const modernPort = Port(
          id: 'modern_port',
          name: 'Modern Port',
          type: PortType.cv,
          direction: PortDirection.output,
          isPolyVoice: true,
          voiceNumber: 5,
          busValue: 10,
          busParam: 'modern_param',
          parameterNumber: 30,
          isMultiChannel: true,
          channelNumber: 4,
          isStereoChannel: true,
          stereoSide: 'left',
        );

        // Serialize and deserialize
        final json = modernPort.toJson();
        final deserializedPort = Port.fromJson(json);

        // Should be identical
        expect(deserializedPort, equals(modernPort));

        // Verify that adding a new field in the future would work
        // (this is testing the resilience of the fromJson method)
        final jsonWithExtraField = Map<String, dynamic>.from(json);
        jsonWithExtraField['futureField'] = 'some value';

        final portWithExtraField = Port.fromJson(jsonWithExtraField);
        // Should still deserialize correctly, ignoring the unknown field
        expect(portWithExtraField, equals(modernPort));
      });
    });

    group('Type Safety Validation', () {
      test('should enforce type safety for all direct properties', () {
        const port = Port(
          id: 'type_safety_test',
          name: 'Type Safety Test',
          type: PortType.cv,
          direction: PortDirection.bidirectional,
          isPolyVoice: true,
          voiceNumber: 6,
          isVirtualCV: false,
          isMultiChannel: true,
          channelNumber: 5,
          isStereoChannel: true,
          stereoSide: 'right',
          isMasterMix: true,
          busValue: 18,
          busParam: 'type_safe_param',
          parameterNumber: 42,
        );

        // Verify types are enforced at compile time
        expect(port.isPolyVoice, isA<bool>());
        expect(port.voiceNumber, isA<int?>());
        expect(port.isVirtualCV, isA<bool>());
        expect(port.isMultiChannel, isA<bool>());
        expect(port.channelNumber, isA<int?>());
        expect(port.isStereoChannel, isA<bool>());
        expect(port.stereoSide, isA<String?>());
        expect(port.isMasterMix, isA<bool>());
        expect(port.busValue, isA<int?>());
        expect(port.busParam, isA<String?>());
        expect(port.parameterNumber, isA<int?>());

        // Verify specific types and values
        expect(port.isPolyVoice, isTrue);
        expect(port.voiceNumber, equals(6));
        expect(port.isVirtualCV, isFalse);
        expect(port.isMultiChannel, isTrue);
        expect(port.channelNumber, equals(5));
        expect(port.isStereoChannel, isTrue);
        expect(port.stereoSide, equals('right'));
        expect(port.isMasterMix, isTrue);
        expect(port.busValue, equals(18));
        expect(port.busParam, equals('type_safe_param'));
        expect(port.parameterNumber, equals(42));
      });

      test('should handle null values correctly in type-safe manner', () {
        const port = Port(
          id: 'null_safety_test',
          name: 'Null Safety Test',
          type: PortType.audio,
          direction: PortDirection.input,
          // Leave optional values as null
          voiceNumber: null,
          channelNumber: null,
          stereoSide: null,
          busValue: null,
          busParam: null,
          parameterNumber: null,
        );

        // Verify null values are handled correctly
        expect(port.voiceNumber, isNull);
        expect(port.channelNumber, isNull);
        expect(port.stereoSide, isNull);
        expect(port.busValue, isNull);
        expect(port.busParam, isNull);
        expect(port.parameterNumber, isNull);

        // Verify boolean defaults are preserved
        expect(port.isPolyVoice, isFalse);
        expect(port.isVirtualCV, isFalse);
        expect(port.isMultiChannel, isFalse);
        expect(port.isStereoChannel, isFalse);
        expect(port.isMasterMix, isFalse);
      });
    });
  });
}
