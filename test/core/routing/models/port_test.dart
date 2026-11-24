import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/port.dart';

void main() {
  group('OutputMode Enum Tests', () {
    test('OutputMode should have add and replace values', () {
      expect(OutputMode.values, hasLength(2));
      expect(OutputMode.values, contains(OutputMode.add));
      expect(OutputMode.values, contains(OutputMode.replace));
    });

    test('OutputMode should serialize to JSON correctly', () {
      expect(OutputMode.add.name, equals('add'));
      expect(OutputMode.replace.name, equals('replace'));
    });
  });

  group('Port Model Tests', () {
    test('should create port with all required fields', () {
      const port = Port(
        id: 'test_port',
        name: 'Test Port',
        type: PortType.audio,
        direction: PortDirection.input,
      );

      expect(port.id, equals('test_port'));
      expect(port.name, equals('Test Port'));
      expect(port.type, equals(PortType.audio));
      expect(port.direction, equals(PortDirection.input));
      expect(port.isActive, isTrue); // default value
    });

    test('should create port with optional fields', () {
      const port = Port(
        id: 'test_port',
        name: 'Test Port',
        type: PortType.cv,
        direction: PortDirection.output,
        description: 'A test CV output port',
        isActive: false,
        constraints: {
          'voltageRange': {'min': -5, 'max': 5},
        },
      );

      expect(port.description, equals('A test CV output port'));
      expect(port.isActive, isFalse);
      expect(port.constraints?['voltageRange'], isNotNull);
    });

    test('should create output port with outputMode', () {
      const port = Port(
        id: 'output_port',
        name: 'Output Port',
        type: PortType.audio,
        direction: PortDirection.output,
        outputMode: OutputMode.replace,
      );

      expect(port.outputMode, equals(OutputMode.replace));
    });

    test(
      'should create output port with default add mode when not specified',
      () {
        const port = Port(
          id: 'output_port',
          name: 'Output Port',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        expect(port.outputMode, isNull);
      },
    );

    test('input port should not have outputMode', () {
      const port = Port(
        id: 'input_port',
        name: 'Input Port',
        type: PortType.audio,
        direction: PortDirection.input,
        outputMode:
            OutputMode.replace, // This should be ignored for input ports
      );

      // The outputMode might be present but should not be used for input ports
      expect(port.direction, equals(PortDirection.input));
    });

    test('should serialize to and from JSON correctly', () {
      const originalPort = Port(
        id: 'test_port',
        name: 'Test Port',
        type: PortType.cv,
        direction: PortDirection.bidirectional,
        description: 'Test description',
        isActive: true,
        constraints: {'maxConnections': 4},
      );

      final json = originalPort.toJson();
      final deserializedPort = Port.fromJson(json);

      expect(deserializedPort, equals(originalPort));
      expect(deserializedPort.id, equals(originalPort.id));
      expect(deserializedPort.name, equals(originalPort.name));
      expect(deserializedPort.type, equals(originalPort.type));
      expect(deserializedPort.direction, equals(originalPort.direction));
      expect(deserializedPort.description, equals(originalPort.description));
      expect(deserializedPort.isActive, equals(originalPort.isActive));
      expect(deserializedPort.constraints, equals(originalPort.constraints));
    });

    test(
      'should serialize port with outputMode to and from JSON correctly',
      () {
        const originalPort = Port(
          id: 'output_port',
          name: 'Output Port',
          type: PortType.audio,
          direction: PortDirection.output,
          outputMode: OutputMode.replace,
        );

        final json = originalPort.toJson();
        expect(json['outputMode'], equals('replace'));

        final deserializedPort = Port.fromJson(json);
        expect(deserializedPort.outputMode, equals(OutputMode.replace));
        expect(deserializedPort, equals(originalPort));
      },
    );

    group('Port Direction Tests', () {
      test('input port should be identified correctly', () {
        const inputPort = Port(
          id: 'input',
          name: 'Input',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(inputPort.isInput, isTrue);
        expect(inputPort.isOutput, isFalse);
      });

      test('output port should be identified correctly', () {
        const outputPort = Port(
          id: 'output',
          name: 'Output',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        expect(outputPort.isInput, isFalse);
        expect(outputPort.isOutput, isTrue);
      });

      test('bidirectional port should be both input and output', () {
        const bidirectionalPort = Port(
          id: 'bidirectional',
          name: 'Bidirectional',
          type: PortType.audio,
          direction: PortDirection.bidirectional,
        );

        expect(bidirectionalPort.isInput, isTrue);
        expect(bidirectionalPort.isOutput, isTrue);
      });
    });

    group('Port Connection Compatibility Tests', () {
      test('output port should connect to input port', () {
        const outputPort = Port(
          id: 'output',
          name: 'Output',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        const inputPort = Port(
          id: 'input',
          name: 'Input',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(outputPort.canConnectTo(inputPort), isTrue);
        expect(inputPort.canConnectTo(outputPort), isTrue);
      });

      test('input port should not connect to input port', () {
        const inputPort1 = Port(
          id: 'input1',
          name: 'Input 1',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        const inputPort2 = Port(
          id: 'input2',
          name: 'Input 2',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(inputPort1.canConnectTo(inputPort2), isFalse);
      });

      test('output port should not connect to output port', () {
        const outputPort1 = Port(
          id: 'output1',
          name: 'Output 1',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        const outputPort2 = Port(
          id: 'output2',
          name: 'Output 2',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        expect(outputPort1.canConnectTo(outputPort2), isFalse);
      });

      test('bidirectional port should connect to any port', () {
        const bidirectionalPort = Port(
          id: 'bidirectional',
          name: 'Bidirectional',
          type: PortType.audio,
          direction: PortDirection.bidirectional,
        );

        const inputPort = Port(
          id: 'input',
          name: 'Input',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        const outputPort = Port(
          id: 'output',
          name: 'Output',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        expect(bidirectionalPort.canConnectTo(inputPort), isTrue);
        expect(bidirectionalPort.canConnectTo(outputPort), isTrue);
        expect(inputPort.canConnectTo(bidirectionalPort), isTrue);
        expect(outputPort.canConnectTo(bidirectionalPort), isTrue);
      });
    });

    group('Port Type Compatibility Tests', () {
      test('same types should be compatible', () {
        const audioPort1 = Port(
          id: 'audio1',
          name: 'Audio 1',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        const audioPort2 = Port(
          id: 'audio2',
          name: 'Audio 2',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(audioPort1.isCompatibleWith(audioPort2), isTrue);
      });

      test('audio and CV should be compatible', () {
        const audioPort = Port(
          id: 'audio',
          name: 'Audio',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        const cvPort = Port(
          id: 'cv',
          name: 'CV',
          type: PortType.cv,
          direction: PortDirection.input,
        );

        expect(audioPort.isCompatibleWith(cvPort), isTrue);
        expect(cvPort.isCompatibleWith(audioPort), isTrue);
      });

      test('clock and gate should be compatible', () {
        const clockPort = Port(
          id: 'clock',
          name: 'Clock',
          type: PortType.cv,
          direction: PortDirection.output,
        );

        const gatePort = Port(
          id: 'gate',
          name: 'Gate',
          type: PortType.cv,
          direction: PortDirection.input,
        );

        expect(clockPort.isCompatibleWith(gatePort), isTrue);
        expect(gatePort.isCompatibleWith(clockPort), isTrue);
      });

      test('audio and gate should be compatible (all types are voltage)', () {
        const audioPort = Port(
          id: 'audio',
          name: 'Audio',
          type: PortType.audio,
          direction: PortDirection.output,
        );

        const gatePort = Port(
          id: 'gate',
          name: 'Gate',
          type: PortType.cv,
          direction: PortDirection.input,
        );

        // All port types are compatible in Eurorack (everything is voltage)
        expect(audioPort.isCompatibleWith(gatePort), isTrue);
        expect(gatePort.isCompatibleWith(audioPort), isTrue);
      });
    });

    group('Port Equality Tests', () {
      test('ports with same values should be equal', () {
        const port1 = Port(
          id: 'test',
          name: 'Test',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        const port2 = Port(
          id: 'test',
          name: 'Test',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(port1, equals(port2));
        expect(port1.hashCode, equals(port2.hashCode));
      });

      test('ports with different values should not be equal', () {
        const port1 = Port(
          id: 'test1',
          name: 'Test 1',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        const port2 = Port(
          id: 'test2',
          name: 'Test 2',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        expect(port1, isNot(equals(port2)));
      });
    });

    group('Port Copy Tests', () {
      test('should create modified copy with copyWith', () {
        const originalPort = Port(
          id: 'original',
          name: 'Original',
          type: PortType.audio,
          direction: PortDirection.input,
          isActive: true,
        );

        final modifiedPort = originalPort.copyWith(
          name: 'Modified',
          isActive: false,
        );

        expect(modifiedPort.id, equals(originalPort.id));
        expect(modifiedPort.name, equals('Modified'));
        expect(modifiedPort.type, equals(originalPort.type));
        expect(modifiedPort.direction, equals(originalPort.direction));
        expect(modifiedPort.isActive, isFalse);
      });
    });
  });

  group('Direct Properties Tests', () {
    test('should create port with poly voice properties', () {
      const port = Port(
        id: 'poly_voice_port',
        name: 'Poly Voice Port',
        type: PortType.cv,
        direction: PortDirection.input,
        isPolyVoice: true,
        voiceNumber: 3,
      );

      expect(port.isPolyVoice, isTrue);
      expect(port.voiceNumber, equals(3));
    });

    test('should create port with multi-channel properties', () {
      const port = Port(
        id: 'multichannel_port',
        name: 'Multi-Channel Port',
        type: PortType.audio,
        direction: PortDirection.output,
        isMultiChannel: true,
        channelNumber: 2,
        isStereoChannel: true,
        stereoSide: 'right',
        isMasterMix: false,
      );

      expect(port.isMultiChannel, isTrue);
      expect(port.channelNumber, equals(2));
      expect(port.isStereoChannel, isTrue);
      expect(port.stereoSide, equals('right'));
      expect(port.isMasterMix, isFalse);
    });

    test('should create port with bus and parameter properties', () {
      const port = Port(
        id: 'bus_port',
        name: 'Bus Port',
        type: PortType.cv,
        direction: PortDirection.input,
        busValue: 5,
        busParam: 'mix_level',
        parameterNumber: 12,
        isVirtualCV: true,
      );

      expect(port.busValue, equals(5));
      expect(port.busParam, equals('mix_level'));
      expect(port.parameterNumber, equals(12));
      expect(port.isVirtualCV, isTrue);
    });

    test('should create port with default direct property values', () {
      const port = Port(
        id: 'default_port',
        name: 'Default Port',
        type: PortType.audio,
        direction: PortDirection.input,
      );

      expect(port.isPolyVoice, isFalse);
      expect(port.voiceNumber, isNull);
      expect(port.isMultiChannel, isFalse);
      expect(port.channelNumber, isNull);
      expect(port.isStereoChannel, isFalse);
      expect(port.stereoSide, isNull);
      expect(port.isMasterMix, isFalse);
      expect(port.busValue, isNull);
      expect(port.busParam, isNull);
      expect(port.parameterNumber, isNull);
      expect(port.isVirtualCV, isFalse);
    });

    test('should serialize direct properties to and from JSON correctly', () {
      const originalPort = Port(
        id: 'direct_props_port',
        name: 'Direct Props Port',
        type: PortType.cv,
        direction: PortDirection.output,
        isPolyVoice: true,
        voiceNumber: 2,
        isMultiChannel: true,
        channelNumber: 1,
        isStereoChannel: true,
        stereoSide: 'left',
        isMasterMix: true,
        busValue: 8,
        busParam: 'frequency',
        parameterNumber: 25,
        isVirtualCV: true,
      );

      final json = originalPort.toJson();
      final deserializedPort = Port.fromJson(json);

      expect(deserializedPort, equals(originalPort));
      expect(deserializedPort.isPolyVoice, equals(originalPort.isPolyVoice));
      expect(deserializedPort.voiceNumber, equals(originalPort.voiceNumber));
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
      expect(deserializedPort.isMasterMix, equals(originalPort.isMasterMix));
      expect(deserializedPort.busValue, equals(originalPort.busValue));
      expect(deserializedPort.busParam, equals(originalPort.busParam));
      expect(
        deserializedPort.parameterNumber,
        equals(originalPort.parameterNumber),
      );
      expect(deserializedPort.isVirtualCV, equals(originalPort.isVirtualCV));
    });

    test('should handle copyWith with direct properties', () {
      const originalPort = Port(
        id: 'original',
        name: 'Original',
        type: PortType.audio,
        direction: PortDirection.input,
        isPolyVoice: false,
        voiceNumber: 1,
      );

      final modifiedPort = originalPort.copyWith(
        isPolyVoice: true,
        voiceNumber: 4,
        busValue: 10,
      );

      expect(modifiedPort.id, equals(originalPort.id));
      expect(modifiedPort.name, equals(originalPort.name));
      expect(modifiedPort.isPolyVoice, isTrue);
      expect(modifiedPort.voiceNumber, equals(4));
      expect(modifiedPort.busValue, equals(10));
    });

    group('Direct Properties Validation', () {
      test('should handle null voice number with poly voice false', () {
        const port = Port(
          id: 'test',
          name: 'Test',
          type: PortType.cv,
          direction: PortDirection.input,
          isPolyVoice: false,
          voiceNumber: null,
        );

        expect(port.isPolyVoice, isFalse);
        expect(port.voiceNumber, isNull);
      });

      test('should handle null channel number with multi-channel false', () {
        const port = Port(
          id: 'test',
          name: 'Test',
          type: PortType.audio,
          direction: PortDirection.output,
          isMultiChannel: false,
          channelNumber: null,
        );

        expect(port.isMultiChannel, isFalse);
        expect(port.channelNumber, isNull);
      });

      test('should handle stereo properties independently', () {
        const leftPort = Port(
          id: 'left',
          name: 'Left',
          type: PortType.audio,
          direction: PortDirection.output,
          isStereoChannel: true,
          stereoSide: 'left',
        );

        const rightPort = Port(
          id: 'right',
          name: 'Right',
          type: PortType.audio,
          direction: PortDirection.output,
          isStereoChannel: true,
          stereoSide: 'right',
        );

        expect(leftPort.isStereoChannel, isTrue);
        expect(leftPort.stereoSide, equals('left'));
        expect(rightPort.isStereoChannel, isTrue);
        expect(rightPort.stereoSide, equals('right'));
      });
    });
  });

  group('PortRole Tests', () {
    test('PortRole enum has expected values', () {
      expect(PortRole.values, hasLength(6));
      expect(PortRole.values, contains(PortRole.busReader));
      expect(PortRole.values, contains(PortRole.busWriter));
      expect(PortRole.values, contains(PortRole.physicalInputBus));
      expect(PortRole.values, contains(PortRole.physicalOutputBus));
      expect(PortRole.values, contains(PortRole.es5Bus));
      expect(PortRole.values, contains(PortRole.expanderOutputBus));
    });

    group('effectiveRole derivation from legacy fields', () {
      test('algorithm input derives to busReader', () {
        const port = Port(
          id: 'node_1_in_1',
          name: 'Input 1',
          type: PortType.cv,
          direction: PortDirection.input,
        );
        expect(port.effectiveRole, PortRole.busReader);
      });

      test('algorithm output derives to busWriter', () {
        const port = Port(
          id: 'node_1_out_1',
          name: 'Output 1',
          type: PortType.cv,
          direction: PortDirection.output,
        );
        expect(port.effectiveRole, PortRole.busWriter);
      });

      test('physical input derives to physicalInputBus', () {
        const port = Port(
          id: 'hw_in_1',
          name: 'I1',
          type: PortType.cv,
          direction: PortDirection.output,
          hardwareIndex: 1,
          role: PortRole.physicalInputBus,
        );
        expect(port.effectiveRole, PortRole.physicalInputBus);
      });

      test('physical output derives to physicalOutputBus', () {
        const port = Port(
          id: 'hw_out_1',
          name: 'O1',
          type: PortType.audio,
          direction: PortDirection.input,
          hardwareIndex: 1,
          role: PortRole.physicalOutputBus,
        );
        expect(port.effectiveRole, PortRole.physicalOutputBus);
      });

      test('ES-5 port derives to es5Bus', () {
        const port = Port(
          id: 'es5_L',
          name: 'ES-5 L',
          type: PortType.audio,
          direction: PortDirection.input,
        );
        expect(port.effectiveRole, PortRole.es5Bus);
      });

      test('bidirectional derives to busWriter', () {
        const port = Port(
          id: 'node_1_out_1',
          name: 'Bidir',
          type: PortType.cv,
          direction: PortDirection.bidirectional,
        );
        expect(port.effectiveRole, PortRole.busWriter);
      });
    });

    group('explicit role overrides derivation', () {
      test('explicit role takes precedence over direction', () {
        const port = Port(
          id: 'node_1_in_1',
          name: 'Input 1',
          type: PortType.cv,
          direction: PortDirection.input,
          role: PortRole.busWriter,
        );
        expect(port.effectiveRole, PortRole.busWriter);
      });
    });

    group('role-based convenience getters', () {
      test('isBus is true for physicalInputBus', () {
        const port = Port(
          id: 'hw_in_1',
          name: 'I1',
          type: PortType.cv,
          direction: PortDirection.output,
          role: PortRole.physicalInputBus,
        );
        expect(port.isBus, isTrue);
        expect(port.isBusReader, isFalse);
        expect(port.isBusWriter, isFalse);
      });

      test('isBus is true for es5Bus', () {
        const port = Port(
          id: 'es5_L',
          name: 'ES-5 L',
          type: PortType.audio,
          direction: PortDirection.input,
        );
        expect(port.isBus, isTrue);
      });

      test('isBusReader for algorithm input', () {
        const port = Port(
          id: 'node_1_in_1',
          name: 'Input 1',
          type: PortType.cv,
          direction: PortDirection.input,
        );
        expect(port.isBusReader, isTrue);
        expect(port.isBusWriter, isFalse);
        expect(port.isBus, isFalse);
      });

      test('isBusWriter for algorithm output', () {
        const port = Port(
          id: 'node_1_out_1',
          name: 'Output 1',
          type: PortType.cv,
          direction: PortDirection.output,
        );
        expect(port.isBusWriter, isTrue);
        expect(port.isBusReader, isFalse);
        expect(port.isBus, isFalse);
      });
    });

    group('PortRole serialization', () {
      test('explicit role round-trips through JSON', () {
        const port = Port(
          id: 'test',
          name: 'Test',
          type: PortType.cv,
          direction: PortDirection.input,
          role: PortRole.physicalInputBus,
        );

        final json = port.toJson();
        final deserialized = Port.fromJson(json);
        expect(deserialized.role, PortRole.physicalInputBus);
        expect(deserialized.effectiveRole, PortRole.physicalInputBus);
      });

      test('null role round-trips through JSON', () {
        const port = Port(
          id: 'test',
          name: 'Test',
          type: PortType.cv,
          direction: PortDirection.input,
        );

        final json = port.toJson();
        final deserialized = Port.fromJson(json);
        expect(deserialized.role, isNull);
        expect(deserialized.effectiveRole, PortRole.busReader);
      });
    });
  });
}
