import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/core/routing/models/connection.dart';
import 'package:nt_helper/core/routing/models/routing_state.dart';
import 'package:nt_helper/core/routing/poly_algorithm_routing.dart';
import 'package:nt_helper/core/routing/multi_channel_algorithm_routing.dart';
import 'package:nt_helper/core/routing/connection_discovery_service.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';

void main() {
  group('Routing Implementations Direct Properties Tests', () {
    group('PolyAlgorithmRouting Direct Properties', () {
      test(
        'should create ports with direct properties for gate-driven poly',
        () {
          final config = PolyAlgorithmConfig(
            voiceCount: 4,
            requiresGateInputs: true,
            usesVirtualCvPorts: false,
            gateInputs: [1, 2, 0, 4], // Gates 1, 2, 4 connected
            gateCvCounts: [2, 1, 0, 3], // CV counts per gate
            algorithmProperties: {
              'algorithmUuid': 'test_poly_123',
              'algorithmGuid': 'py_test',
              'algorithmName': 'Test Poly',
            },
          );

          final routing = PolyAlgorithmRouting(config: config);
          final inputPorts = routing.generateInputPorts();

          // Verify gate ports have correct direct properties
          final gatePorts = inputPorts
              .where(
                (p) =>
                    p.type == PortType.cv &&
                    p.name.startsWith('Gate ') &&
                    !p.name.contains('CV'),
              )
              .toList();
          expect(gatePorts, hasLength(3)); // Gates 1, 2, 4

          final gate1 = gatePorts.firstWhere((p) => p.name == 'Gate 1');
          expect(gate1.isPolyVoice, isTrue);
          expect(gate1.voiceNumber, equals(1));
          expect(gate1.busValue, equals(1));

          final gate4 = gatePorts.firstWhere((p) => p.name == 'Gate 4');
          expect(gate4.isPolyVoice, isTrue);
          expect(gate4.voiceNumber, equals(4));
          expect(gate4.busValue, equals(4));

          // Verify CV ports have correct direct properties
          final cvPorts = inputPorts
              .where((p) => p.type == PortType.cv && p.name.contains('CV'))
              .toList();
          expect(cvPorts, hasLength(6)); // 2+1+3 CV inputs

          final gate1Cv1 = cvPorts.firstWhere((p) => p.name == 'Gate 1 CV1');
          expect(gate1Cv1.isPolyVoice, isTrue);
          expect(gate1Cv1.voiceNumber, equals(1));
          expect(gate1Cv1.busValue, equals(2)); // Gate bus + 1

          final gate4Cv3 = cvPorts.firstWhere((p) => p.name == 'Gate 4 CV3');
          expect(gate4Cv3.isPolyVoice, isTrue);
          expect(gate4Cv3.voiceNumber, equals(4));
          expect(gate4Cv3.busValue, equals(7)); // Gate bus + 3
        },
      );

      test('should create ports with direct properties for extra inputs', () {
        final config = PolyAlgorithmConfig(
          voiceCount: 2,
          algorithmProperties: {
            'extraInputs': [
              {
                'id': 'wave_input',
                'name': 'Wave Input',
                'type': 'cv',
                'busValue': 10,
                'busParam': 'wave_level',
                'parameterNumber': 5,
                'isVirtualCV': true,
              },
              {
                'id': 'audio_input',
                'name': 'Audio Input',
                'type': 'audio',
                'busValue': 11,
                'busParam': 'audio_level',
                'parameterNumber': 6,
              },
            ],
          },
        );

        final routing = PolyAlgorithmRouting(config: config);
        final inputPorts = routing.generateInputPorts();

        final wavePort = inputPorts.firstWhere((p) => p.id == 'wave_input');
        expect(wavePort.busValue, equals(10));
        expect(wavePort.busParam, equals('wave_level'));
        expect(wavePort.parameterNumber, equals(5));
        expect(wavePort.isVirtualCV, isTrue);

        final audioPort = inputPorts.firstWhere((p) => p.id == 'audio_input');
        expect(audioPort.busValue, equals(11));
        expect(audioPort.busParam, equals('audio_level'));
        expect(audioPort.parameterNumber, equals(6));
        expect(audioPort.isVirtualCV, isFalse);
      });

      test('should create output ports for output-only poly algorithms', () {
        final config = PolyAlgorithmConfig(
          voiceCount: 2,
          requiresGateInputs: false, // No gate inputs required
          algorithmProperties: {
            'algorithmGuid': 'pycv',
            'algorithmName': 'Poly CV',
            'algorithmUuid': 'test_pycv_123',
            'extraInputs': [], // No extra inputs
            'outputs': [
              // Gate outputs
              {
                'id': 'test_pycv_123_gate_out_0',
                'name': 'Gate Out 0',
                'type': 'gate',
                'busValue': 15,
                'busParam': 'Gate output 0',
                'parameterNumber': 0,
                'voiceNumber': 0,
              },
              {
                'id': 'test_pycv_123_gate_out_1',
                'name': 'Gate Out 1',
                'type': 'gate',
                'busValue': 18,
                'busParam': 'Gate output 1',
                'parameterNumber': 0,
                'voiceNumber': 1,
              },
              // Pitch outputs
              {
                'id': 'test_pycv_123_pitch_out_0',
                'name': 'Pitch Out 0',
                'type': 'cv',
                'busValue': 16,
                'busParam': 'Pitch output 0',
                'parameterNumber': 0,
                'voiceNumber': 0,
              },
              {
                'id': 'test_pycv_123_pitch_out_1',
                'name': 'Pitch Out 1',
                'type': 'cv',
                'busValue': 19,
                'busParam': 'Pitch output 1',
                'parameterNumber': 0,
                'voiceNumber': 1,
              },
            ],
          },
        );

        final routing = PolyAlgorithmRouting(config: config);
        final inputPorts = routing.generateInputPorts();
        final outputPorts = routing.generateOutputPorts();

        // Should have no input ports (output-only algorithm)
        expect(inputPorts, isEmpty);

        // Should have output ports based on the algorithm properties
        expect(outputPorts, hasLength(4)); // 2 gate + 2 pitch outputs

        // Verify gate outputs
        final gateOutputs = outputPorts
            .where((p) => p.type == PortType.cv && p.name.contains('Gate'))
            .toList();
        expect(gateOutputs, hasLength(2));

        final gate0 = gateOutputs.firstWhere((p) => p.name == 'Gate Out 0');
        expect(gate0.busValue, equals(15));
        expect(gate0.direction, equals(PortDirection.output));

        final gate1 = gateOutputs.firstWhere((p) => p.name == 'Gate Out 1');
        expect(gate1.busValue, equals(18));

        // Verify pitch outputs
        final pitchOutputs = outputPorts
            .where((p) => p.type == PortType.cv && p.name.contains('Pitch'))
            .toList();
        expect(pitchOutputs, hasLength(2));

        final pitch0 = pitchOutputs.firstWhere((p) => p.name == 'Pitch Out 0');
        expect(pitch0.busValue, equals(16));

        final pitch1 = pitchOutputs.firstWhere((p) => p.name == 'Pitch Out 1');
        expect(pitch1.busValue, equals(19));
      });

      test('should use direct properties in helper methods', () {
        final config = PolyAlgorithmConfig(voiceCount: 2);
        final routing = PolyAlgorithmRouting(config: config);

        // Create test ports with direct properties
        final polyPort = Port(
          id: 'poly_test',
          name: 'Poly Test',
          type: PortType.cv,
          direction: PortDirection.input,
          isPolyVoice: true,
          voiceNumber: 2,
          isVirtualCV: true,
        );

        final normalPort = Port(
          id: 'normal_test',
          name: 'Normal Test',
          type: PortType.audio,
          direction: PortDirection.input,
        );

        // Test private methods through public validation
        expect(routing.validateConnection(polyPort, normalPort), isTrue);
      });
    });

    group('MultiChannelAlgorithmRouting Direct Properties', () {
      test(
        'should create ports with direct properties for stereo channels',
        () {
          final config = MultiChannelAlgorithmConfig.widthBased(
            width: 2,
            supportsStereo: true,
          );

          final routing = MultiChannelAlgorithmRouting(config: config);
          final inputPorts = routing.generateInputPorts();

          // Find stereo audio ports
          final leftPorts = inputPorts
              .where((p) => p.type == PortType.audio && p.stereoSide == 'left')
              .toList();
          final rightPorts = inputPorts
              .where((p) => p.type == PortType.audio && p.stereoSide == 'right')
              .toList();

          expect(leftPorts, hasLength(2)); // 2 channels
          expect(rightPorts, hasLength(2)); // 2 channels

          // Verify direct properties on left channel 1
          final leftCh1 = leftPorts.firstWhere((p) => p.channelNumber == 1);
          expect(leftCh1.isMultiChannel, isTrue);
          expect(leftCh1.isStereoChannel, isTrue);
          expect(leftCh1.stereoSide, equals('left'));
          expect(leftCh1.channelNumber, equals(1));

          // Verify direct properties on right channel 2
          final rightCh2 = rightPorts.firstWhere((p) => p.channelNumber == 2);
          expect(rightCh2.isMultiChannel, isTrue);
          expect(rightCh2.isStereoChannel, isTrue);
          expect(rightCh2.stereoSide, equals('right'));
          expect(rightCh2.channelNumber, equals(2));
        },
      );

      test(
        'should create ports with direct properties for declared inputs',
        () {
          final config = MultiChannelAlgorithmConfig(
            algorithmProperties: {
              'inputs': [
                {
                  'id': 'main_input',
                  'name': 'Main Input',
                  'type': 'audio',
                  'busValue': 5,
                  'busParam': 'input_level',
                  'parameterNumber': 10,
                  'channelNumber': 1,
                },
              ],
            },
          );

          final routing = MultiChannelAlgorithmRouting(config: config);
          final inputPorts = routing.generateInputPorts();

          final mainInput = inputPorts.firstWhere((p) => p.id == 'main_input');
          expect(mainInput.busValue, equals(5));
          expect(mainInput.busParam, equals('input_level'));
          expect(mainInput.parameterNumber, equals(10));
          expect(mainInput.channelNumber, equals(1));
          expect(mainInput.isMultiChannel, isTrue);
        },
      );

      
    });

    group('ConnectionDiscoveryService Direct Properties', () {
      test('should use direct properties for bus discovery', () {
        // Create mock routing with ports using direct properties
        final mockRouting = _MockRouting([
          Port(
            id: 'input_1',
            name: 'Input 1',
            type: PortType.audio,
            direction: PortDirection.input,
            busValue: 1,
            busParam: 'audio_in',
            parameterNumber: 10,
          ),
          Port(
            id: 'output_1',
            name: 'Output 1',
            type: PortType.audio,
            direction: PortDirection.output,
            busValue: 13,
            busParam: 'audio_out',
            parameterNumber: 20,
          ),
        ]);

        final connections = ConnectionDiscoveryService.discoverConnections([
          mockRouting,
        ]);

        // Should discover hardware input and output connections
        expect(connections, hasLength(2));

        // Find connections by looking at port IDs and connection types
        final inputConnection = connections.firstWhere(
          (c) =>
              c.connectionType == ConnectionType.hardwareInput &&
              c.destinationPortId == 'input_1',
        );
        expect(inputConnection.destinationPortId, equals('input_1'));
        expect(inputConnection.busNumber, equals(1));

        final outputConnection = connections.firstWhere(
          (c) =>
              c.connectionType == ConnectionType.hardwareOutput &&
              c.sourcePortId == 'output_1',
        );
        expect(outputConnection.sourcePortId, equals('output_1'));
        expect(outputConnection.busNumber, equals(13));
      });

      test(
        'should discover connections via hw path on physical input bus using direct properties',
        () {
          final routing1 = _MockRouting([
            Port(
              id: 'algo1_out',
              name: 'Algorithm 1 Output',
              type: PortType.cv,
              direction: PortDirection.output,
              busValue: 5,
              busParam: 'cv_out',
              parameterNumber: 1,
            ),
          ]);

          final routing2 = _MockRouting([
            Port(
              id: 'algo2_in',
              name: 'Algorithm 2 Input',
              type: PortType.cv,
              direction: PortDirection.input,
              busValue: 5,
              busParam: 'cv_in',
              parameterNumber: 2,
            ),
          ]);

          final connections = ConnectionDiscoveryService.discoverConnections([
            routing1,
            routing2,
          ]);

          // On physical input bus 5, path goes through hw_in_5:
          // algo1_out → hw_in_5 (write) and hw_in_5 → algo2_in (read)
          final writeConnection = connections.firstWhere(
            (c) =>
                c.sourcePortId == 'algo1_out' &&
                c.destinationPortId == 'hw_in_5',
            orElse: () =>
                throw StateError('Hardware input write connection not found'),
          );
          expect(
            writeConnection.connectionType,
            equals(ConnectionType.hardwareOutput),
          );
          expect(writeConnection.busNumber, equals(5));

          final readConnection = connections.firstWhere(
            (c) =>
                c.sourcePortId == 'hw_in_5' &&
                c.destinationPortId == 'algo2_in',
            orElse: () =>
                throw StateError('Hardware input read connection not found'),
          );
          expect(
            readConnection.connectionType,
            equals(ConnectionType.hardwareInput),
          );
          expect(readConnection.busNumber, equals(5));
        },
      );
    });

    group('Direct Properties Integration Tests', () {
      test('should work correctly with direct properties only', () {
        // Test that direct properties work without metadata field
        final port = Port(
          id: 'test_port',
          name: 'Test Port',
          type: PortType.cv,
          direction: PortDirection.input,
          // Direct properties only (no metadata field)
          isPolyVoice: true,
          voiceNumber: 3,
          busValue: 7,
          busParam: 'test_param',
          parameterNumber: 15,
          isVirtualCV: true,
          isMultiChannel: true,
          channelNumber: 2,
          isStereoChannel: true,
          stereoSide: 'right',
          isMasterMix: false,
        );

        // Direct property access
        expect(port.isPolyVoice, isTrue);
        expect(port.voiceNumber, equals(3));
        expect(port.busValue, equals(7));
        expect(port.busParam, equals('test_param'));
        expect(port.parameterNumber, equals(15));
        expect(port.isVirtualCV, isTrue);
        expect(port.isMultiChannel, isTrue);
        expect(port.channelNumber, equals(2));
        expect(port.isStereoChannel, isTrue);
        expect(port.stereoSide, equals('right'));
        expect(port.isMasterMix, isFalse);
      });

      test('should serialize and deserialize direct properties correctly', () {
        final originalPort = Port(
          id: 'serialization_test',
          name: 'Serialization Test',
          type: PortType.cv,
          direction: PortDirection.output,
          isPolyVoice: true,
          voiceNumber: 4,
          busValue: 12,
          busParam: 'gate_out',
          parameterNumber: 25,
          isVirtualCV: false,
          isMultiChannel: true,
          channelNumber: 3,
          isStereoChannel: true,
          stereoSide: 'left',
          isMasterMix: true,
        );

        final json = originalPort.toJson();
        final deserializedPort = Port.fromJson(json);

        // Verify all direct properties are preserved
        expect(deserializedPort.isPolyVoice, equals(originalPort.isPolyVoice));
        expect(deserializedPort.voiceNumber, equals(originalPort.voiceNumber));
        expect(deserializedPort.busValue, equals(originalPort.busValue));
        expect(deserializedPort.busParam, equals(originalPort.busParam));
        expect(
          deserializedPort.parameterNumber,
          equals(originalPort.parameterNumber),
        );
        expect(deserializedPort.isVirtualCV, equals(originalPort.isVirtualCV));
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
      });
    });
  });
}

// Mock routing implementation for testing
class _MockRouting extends AlgorithmRouting {
  final List<Port> _ports;
  RoutingState _state = const RoutingState();

  _MockRouting(this._ports) : super();

  @override
  RoutingState get state => _state;

  @override
  List<Connection> get connections => _state.connections;

  @override
  List<Port> get inputPorts =>
      _ports.where((p) => p.direction == PortDirection.input).toList();

  @override
  List<Port> get outputPorts =>
      _ports.where((p) => p.direction == PortDirection.output).toList();

  @override
  List<Port> generateInputPorts() => inputPorts;

  @override
  List<Port> generateOutputPorts() => outputPorts;

  @override
  bool validateConnection(Port source, Port destination) => true;

  @override
  void updateState(RoutingState newState) {
    _state = newState;
  }
}
