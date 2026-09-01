import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/algorithm_routing.dart';
import 'package:nt_helper/core/routing/models/port.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';

ParameterInfo _parameter({
  required int number,
  required String name,
  required int max,
  int min = 0,
  int defaultValue = 0,
  int unit = 0,
  bool isInput = false,
}) => ParameterInfo(
  algorithmIndex: 0,
  parameterNumber: number,
  name: name,
  min: min,
  max: max,
  defaultValue: defaultValue,
  unit: unit,
  powerOfTen: 0,
  ioFlags: isInput ? 1 : 0,
);

Slot _slotWithPage({
  required String guid,
  required String name,
  required List<int> pageParameters,
  required List<ParameterInfo> parameters,
  required Map<int, int> values,
  String pageName = 'CV/Gate',
}) => Slot(
  algorithm: Algorithm(algorithmIndex: 0, guid: guid, name: name),
  routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
  pages: ParameterPages(
    algorithmIndex: 0,
    pages: [ParameterPage(name: pageName, parameters: pageParameters)],
  ),
  parameters: parameters,
  values: [
    for (final entry in values.entries)
      ParameterValue(
        algorithmIndex: 0,
        parameterNumber: entry.key,
        value: entry.value,
      ),
  ],
  enums: const [],
  mappings: const [],
  valueStrings: const [],
  outputModeMap: const {},
);

/// Regression coverage for poly algorithms' generated pitch inputs.
///
/// Commit 7e7efa84 switched `extractIOParameters()` from pattern matching to
/// ioFlags-only detection. `Gate $i CV count` is a numeric knob (unit=0,
/// min=0, max=11) with no ioFlags, so it was no longer extracted into
/// `ioParameters`. As a result `PolyAlgorithmRouting.createFromSlot()` always
/// read `cvCount = 0`, and no CV input ports were generated after connected
/// gates — breaking the "virtual pitch inputs" visualization for Poly
/// Multisample and all other poly algorithms.
///
/// The routing implementation reads count values directly from the slot. It
/// also recognizes the gate/count structure from parameter numbers in a
/// parameter page, allowing plug-ins with non-factory GUIDs and non-sequential
/// parameter numbers to use the same generated routing.
void main() {
  group('Poly gate CV count regression', () {
    test(
      'unknown plugin with ordered gate/count page exposes consecutive pitch inputs',
      () {
        final parameters = <ParameterInfo>[
          _parameter(
            number: 41,
            name: 'Gate input 1',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(number: 7, name: 'Gate 1 CV count', max: 4),
          _parameter(number: 55, name: 'Gate 1 sample & hold', max: 1, unit: 1),
          _parameter(
            number: 12,
            name: 'Gate input 2',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(number: 90, name: 'Gate 2 CV count', max: 4),
          _parameter(number: 3, name: 'Gate 2 sample & hold', max: 1, unit: 1),
        ];
        final slot = _slotWithPage(
          guid: 'ThIb',
          name: 'Icy Beauty',
          pageParameters: [41, 7, 55, 12, 90, 3],
          parameters: [
            parameters[4],
            parameters[0],
            parameters[5],
            parameters[1],
            parameters[3],
            parameters[2],
          ],
          values: {41: 9, 7: 2, 12: 14, 90: 1},
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'icy_beauty_test',
        );

        expect(
          routing.inputPorts.map((port) => (port.name, port.busValue)),
          containsAll(<(String, int?)>[
            ('Gate 1', 9),
            ('Gate 1 CV1', 10),
            ('Gate 1 CV2', 11),
            ('Gate 2', 14),
            ('Gate 2 CV1', 15),
          ]),
        );
      },
    );

    test('known poly GUID pairs gate and count blocks by page position', () {
      final slot = _slotWithPage(
        guid: 'pymu',
        name: 'Poly Multisample',
        pageName: 'Controllers',
        pageParameters: [42, 5, 99, 18],
        parameters: [
          _parameter(
            number: 42,
            name: 'Trigger A',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(
            number: 5,
            name: 'Trigger B',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(number: 99, name: 'Pitch lanes A', max: 11),
          _parameter(number: 18, name: 'Pitch lanes B', max: 11),
        ],
        values: {42: 3, 5: 7, 99: 1, 18: 2},
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'factory_poly_test',
      );

      expect(
        routing.inputPorts.map((port) => (port.name, port.busValue)),
        containsAll(<(String, int?)>[
          ('Gate 1', 3),
          ('Gate 1 CV1', 4),
          ('Gate 2', 7),
          ('Gate 2 CV1', 8),
          ('Gate 2 CV2', 9),
        ]),
      );
    });

    test(
      'unknown algorithm with an unconfirmed input/count shape stays non-poly',
      () {
        final slot = _slotWithPage(
          guid: 'misc',
          name: 'Unrelated Algorithm',
          pageName: 'Controls',
          pageParameters: [8, 9],
          parameters: [
            _parameter(
              number: 8,
              name: 'Control source',
              max: 28,
              unit: 1,
              isInput: true,
            ),
            _parameter(number: 9, name: 'Control count', max: 4),
          ],
          values: {8: 6, 9: 2},
        );

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'unrelated_test',
        );

        expect(
          routing.inputPorts.map((port) => (port.name, port.busValue)),
          contains(('Control source', 6)),
        );
        expect(
          routing.inputPorts.where((port) => port.name == 'Gate 1'),
          isEmpty,
        );
      },
    );

    test('matching names in the wrong page order stay non-poly', () {
      final slot = _slotWithPage(
        guid: 'misc',
        name: 'Unrelated Algorithm',
        pageName: 'Controls',
        pageParameters: [9, 8],
        parameters: [
          _parameter(
            number: 8,
            name: 'Gate input 1',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(number: 9, name: 'Gate 1 CV count', max: 4),
        ],
        values: {8: 6, 9: 2},
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'wrong_order_test',
      );

      expect(
        routing.inputPorts.map((port) => (port.name, port.busValue)),
        contains(('Gate input 1', 6)),
      );
      expect(
        routing.inputPorts.where((port) => port.name == 'Gate 1'),
        isEmpty,
      );
    });

    test('missing parameter info does not collapse a gap in page order', () {
      final slot = _slotWithPage(
        guid: 'misc',
        name: 'Incomplete Algorithm',
        pageParameters: [8, 404, 9],
        parameters: [
          _parameter(
            number: 8,
            name: 'Gate input 1',
            max: 28,
            unit: 1,
            isInput: true,
          ),
          _parameter(number: 9, name: 'Gate 1 CV count', max: 4),
        ],
        values: {8: 6, 9: 2},
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'incomplete_metadata_test',
      );

      expect(
        routing.inputPorts.map((port) => (port.name, port.busValue)),
        contains(('Gate input 1', 6)),
      );
      expect(
        routing.inputPorts.where((port) => port.name == 'Gate 1'),
        isEmpty,
      );
    });

    /// Builds a poly algorithm slot (guid `pymu`) with a single connected
    /// gate input and a configurable `Gate 1 CV count`.
    ///
    /// `Gate input 1` carries the `isInput` ioFlag (ioFlags=1) so it is picked
    /// up by `extractIOParameters()`. `Gate 1 CV count` deliberately has
    /// **no** ioFlags (ioFlags=0), mirroring the firmware metadata, so it is
    /// NOT picked up by `extractIOParameters()` — the conditions that caused
    /// the regression.
    Slot createPolyMultisampleSlot({
      required int gateInputBus,
      required int gateCvCount,
      int algorithmIndex = 0,
    }) {
      final parameters = <ParameterInfo>[];
      final values = <ParameterValue>[];

      // Gate input 1 — bus assignment, flagged as isInput (ioFlags=1).
      parameters.add(
        ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: 0,
          name: 'Gate input 1',
          min: 0,
          max: 28,
          defaultValue: 0,
          unit: 1,
          powerOfTen: 0,
          ioFlags: 1, // isInput
        ),
      );
      values.add(
        ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: 0,
          value: gateInputBus,
        ),
      );

      // Gate 1 CV count — numeric knob, NO ioFlags (the regression condition).
      parameters.add(
        ParameterInfo(
          algorithmIndex: algorithmIndex,
          parameterNumber: 1,
          name: 'Gate 1 CV count',
          min: 0,
          max: 11,
          defaultValue: 1,
          unit: 0, // numeric type — not a bus parameter
          powerOfTen: 0,
          ioFlags: 0, // deliberately no ioFlags
        ),
      );
      values.add(
        ParameterValue(
          algorithmIndex: algorithmIndex,
          parameterNumber: 1,
          value: gateCvCount,
        ),
      );

      return Slot(
        algorithm: Algorithm(
          algorithmIndex: algorithmIndex,
          guid: 'pymu',
          name: 'Poly Multisample',
        ),
        routing: RoutingInfo(
          algorithmIndex: algorithmIndex,
          routingInfo: List.filled(6, 0),
        ),
        // Empty pages → _visibleParameterNumbers falls back to all parameters,
        // matching offline/test fixture behaviour.
        pages: ParameterPages(algorithmIndex: algorithmIndex, pages: []),
        parameters: parameters,
        values: values,
        enums: [],
        mappings: [],
        valueStrings: [],
        outputModeMap: {},
      );
    }

    test(
      'connected gate with CV count=1 produces a CV input port on the next bus',
      () {
        final slot = createPolyMultisampleSlot(gateInputBus: 3, gateCvCount: 1);

        final routing = AlgorithmRouting.fromSlot(
          slot,
          deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
          algorithmUuid: 'pymu_test',
        );

        final inputPorts = routing.inputPorts;

        // Expect a Gate 1 port at bus 3.
        final gatePort = inputPorts.firstWhere((p) => p.name == 'Gate 1');
        expect(gatePort.direction, equals(PortDirection.input));
        expect(gatePort.busValue, equals(3));
        expect(gatePort.isPolyVoice, isTrue);
        expect(gatePort.voiceNumber, equals(1));

        // Expect a CV port (the "virtual pitch input") at bus 4 = gateBus + 1.
        final cvPort = inputPorts.firstWhere((p) => p.name == 'Gate 1 CV1');
        expect(cvPort.direction, equals(PortDirection.input));
        expect(cvPort.busValue, equals(4));
        expect(cvPort.isPolyVoice, isTrue);
        expect(cvPort.voiceNumber, equals(1));
      },
    );

    test('CV count=0 produces no CV input ports after the gate', () {
      final slot = createPolyMultisampleSlot(gateInputBus: 5, gateCvCount: 0);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'pymu_test',
      );

      final inputPorts = routing.inputPorts;

      // Gate 1 should still be present.
      final gatePort = inputPorts.firstWhere((p) => p.name == 'Gate 1');
      expect(gatePort.busValue, equals(5));

      // No CV ports should be generated.
      final cvPorts = inputPorts.where((p) => p.name.contains('CV'));
      expect(cvPorts, isEmpty);
    });

    test('CV count=2 produces two CV input ports on consecutive busses', () {
      final slot = createPolyMultisampleSlot(gateInputBus: 1, gateCvCount: 2);

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'pymu_test',
      );

      final inputPorts = routing.inputPorts;

      final cv1 = inputPorts.firstWhere((p) => p.name == 'Gate 1 CV1');
      expect(cv1.busValue, equals(2)); // gateBus(1) + 1

      final cv2 = inputPorts.firstWhere((p) => p.name == 'Gate 1 CV2');
      expect(cv2.busValue, equals(3)); // gateBus(1) + 2
    });

    test('page-prefixed Gate 1 CV count parameter is still read correctly', () {
      // Same slot, but parameter names carry a page prefix ("1:Gate 1 CV count"),
      // mirroring what the Disting NT firmware actually sends.
      final parameters = <ParameterInfo>[
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          name: '1:Gate input 1',
          min: 0,
          max: 28,
          defaultValue: 0,
          unit: 1,
          powerOfTen: 0,
          ioFlags: 1,
        ),
        ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 1,
          name: '1:Gate 1 CV count',
          min: 0,
          max: 11,
          defaultValue: 1,
          unit: 0,
          powerOfTen: 0,
          ioFlags: 0,
        ),
      ];
      final values = <ParameterValue>[
        ParameterValue(algorithmIndex: 0, parameterNumber: 0, value: 2),
        ParameterValue(algorithmIndex: 0, parameterNumber: 1, value: 1),
      ];

      final slot = Slot(
        algorithm: Algorithm(
          algorithmIndex: 0,
          guid: 'pymu',
          name: 'Poly Multisample',
        ),
        routing: RoutingInfo(algorithmIndex: 0, routingInfo: List.filled(6, 0)),
        pages: ParameterPages(algorithmIndex: 0, pages: []),
        parameters: parameters,
        values: values,
        enums: [],
        mappings: [],
        valueStrings: [],
        outputModeMap: {},
      );

      final routing = AlgorithmRouting.fromSlot(
        slot,
        deviceIoProfile: AlgorithmRouting.defaultDeviceIoProfile,
        algorithmUuid: 'pymu_test',
      );

      final cvPort = routing.inputPorts.firstWhere(
        (p) => p.name == 'Gate 1 CV1',
      );
      // gateBus=2, CV1 on bus 3.
      expect(cvPort.busValue, equals(3));
    });
  });
}
