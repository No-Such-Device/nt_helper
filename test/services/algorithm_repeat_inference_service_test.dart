import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show Specification;
import 'package:nt_helper/models/algorithm_shape_snapshot.dart';
import 'package:nt_helper/services/algorithm_repeat_inference_service.dart';

void main() {
  final service = AlgorithmRepeatInferenceService();

  group('AlgorithmRepeatInferenceService', () {
    test('selects only supported count nouns and types', () {
      for (final name in const [
        'Channels',
        'Audio inputs',
        'Outputs',
        'Aux sends',
        'Stereo',
        'Voices',
      ]) {
        expect(
          AlgorithmRepeatInferenceService.isRepeatCandidate(
            _spec(name, min: 0, max: 8),
          ),
          isTrue,
          reason: name,
        );
      }
      expect(
        AlgorithmRepeatInferenceService.isRepeatCandidate(
          _spec('Channels', min: 1, max: 8, type: 2),
        ),
        isTrue,
      );
      for (final name in const [
        'Max delay time',
        'Record time',
        'Buffer size',
      ]) {
        expect(
          AlgorithmRepeatInferenceService.isRepeatCandidate(
            _spec(name, min: 0, max: 30),
          ),
          isFalse,
          reason: name,
        );
      }
      expect(
        AlgorithmRepeatInferenceService.isRepeatCandidate(
          _spec('Channels', min: 1, max: 8, type: 1),
        ),
        isFalse,
      );
    });

    test('probe plan uses min+1 and safe defaults without max sweeps', () {
      final specs = [
        _spec('Channels', min: 1, max: 12, defaultValue: 8),
        _spec('Sends', min: 0, max: 4),
        _spec('Max delay time', min: 1, max: 30, defaultValue: 30),
      ];

      final plan = service.buildInitialPlan(specs);

      expect(plan.canonical.values, [2, 1, 30]);
      expect(plan.lowerWitnessByAxis[0]!.values, [1, 1, 30]);
      expect(plan.lowerWitnessByAxis[1]!.values, [2, 0, 30]);
      expect(plan.lowerWitnessByAxis, isNot(contains(2)));
    });

    test('Quantizer 1/2 proves a grammar that expands at 4 and 12', () {
      final specs = [_spec('Channels', min: 1, max: 12)];
      final plan = service.buildInitialPlan(specs);
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _quantizer(2),
        plan.lowerWitnessByAxis[0]!: _quantizer(1),
      };

      final result = service.compile(
        analysis: service.analyzeInitial(
          specifications: specs,
          plan: plan,
          snapshots: snapshots,
        ),
        snapshots: snapshots,
      );

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final grammar = (result as ProvenAlgorithmRepeatGrammar).grammar;
      expect(grammar.expand(_quantizer(2), [4]).parameters.length, 5);
      expect(grammar.expand(_quantizer(2), [12]).parameters.last.name, 'Ch 12');
    });

    test('numbered rows with identical bus enum strings prove a grammar', () {
      // Mirrors the LFO hardware shape: "1:Output"/"2:Output" share the
      // same bus enum ("None", "Input 1", ... "Aux 44").
      final specs = [_spec('Channels', min: 1, max: 4)];
      final plan = service.buildInitialPlan(specs);
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _busOutputRows(2),
        plan.lowerWitnessByAxis[0]!: _busOutputRows(1),
      };

      final result = service.compile(
        analysis: service.analyzeInitial(
          specifications: specs,
          plan: plan,
          snapshots: snapshots,
        ),
        snapshots: snapshots,
      );

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final grammar = (result as ProvenAlgorithmRepeatGrammar).grammar;
      expect(grammar.expand(_busOutputRows(2), [4]), _busOutputRows(4));
    });

    test('Quantizer relationship streams follow repeated logical rows', () {
      final specs = [_spec('Channels', min: 1, max: 12)];
      final plan = service.buildInitialPlan(specs);
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _quantizerWithRelationships(2),
        plan.lowerWitnessByAxis[0]!: _quantizerWithRelationships(1),
      };

      final result = service.compile(
        analysis: service.analyzeInitial(
          specifications: specs,
          plan: plan,
          snapshots: snapshots,
        ),
        snapshots: snapshots,
      );

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final grammar = (result as ProvenAlgorithmRepeatGrammar).grammar;
      expect(
        grammar.expand(_quantizerWithRelationships(2), [4]),
        _quantizerWithRelationships(4),
      );
      expect(
        grammar.expand(_quantizerWithRelationships(2), [12]),
        _quantizerWithRelationships(12),
      );
    });

    test('one count axis can add two disjoint sections', () {
      final specs = [_spec('Inputs', min: 1, max: 8)];
      final plan = service.buildInitialPlan(specs);
      AlgorithmShapeSnapshot shape(int count) => _shape(
        [count],
        [
          for (var i = 1; i <= count; i++) _parameter('Input $i'),
          _parameter('Fixed'),
          for (var i = 1; i <= count; i++) _parameter('Output $i'),
        ],
      );
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: shape(2),
        plan.lowerWitnessByAxis[0]!: shape(1),
      };

      final result = service.compile(
        analysis: service.analyzeInitial(
          specifications: specs,
          plan: plan,
          snapshots: snapshots,
        ),
        snapshots: snapshots,
      );

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final expanded = (result as ProvenAlgorithmRepeatGrammar).grammar.expand(
        shape(2),
        [3],
      );
      expect(expanded.parameters.map((parameter) => parameter.name), [
        'Input 1',
        'Input 2',
        'Input 3',
        'Fixed',
        'Output 1',
        'Output 2',
        'Output 3',
      ]);
    });

    test('Mixer joint witness proves nested Channels and Sends', () {
      final specs = [
        _spec('Channels', min: 1, max: 8),
        _spec('Sends', min: 0, max: 4),
      ];
      final plan = service.buildInitialPlan(specs);
      final initial = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _mixer(2, 1),
        plan.lowerWitnessByAxis[0]!: _mixer(1, 1),
        plan.lowerWitnessByAxis[1]!: _mixer(2, 0),
      };
      final analysis = service.analyzeInitial(
        specifications: specs,
        plan: plan,
        snapshots: initial,
      );
      final interaction = service.interactionWitnesses(analysis).single;
      final snapshots = {...initial, interaction: _mixer(1, 0)};

      final result = service.compile(analysis: analysis, snapshots: snapshots);

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final expanded = (result as ProvenAlgorithmRepeatGrammar).grammar.expand(
        _mixer(2, 1),
        [4, 2],
      );
      expect(expanded.parameters.map((parameter) => parameter.name), [
        'Channel 1',
        'Channel 1 Send 1',
        'Channel 1 Send 2',
        'Channel 2',
        'Channel 2 Send 1',
        'Channel 2 Send 2',
        'Channel 3',
        'Channel 3 Send 1',
        'Channel 3 Send 2',
        'Channel 4',
        'Channel 4 Send 1',
        'Channel 4 Send 2',
      ]);
    });

    test('Mixer nests pages, memberships, and output usage with Sends', () {
      final specs = [
        _spec('Channels', min: 1, max: 8),
        _spec('Sends', min: 0, max: 4),
      ];
      final plan = service.buildInitialPlan(specs);
      final initial = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _mixerWithRelationships(2, 1),
        plan.lowerWitnessByAxis[0]!: _mixerWithRelationships(1, 1),
        plan.lowerWitnessByAxis[1]!: _mixerWithRelationships(2, 0),
      };
      final analysis = service.analyzeInitial(
        specifications: specs,
        plan: plan,
        snapshots: initial,
      );
      final interaction = service.interactionWitnesses(analysis).single;
      final snapshots = {
        ...initial,
        interaction: _mixerWithRelationships(1, 0),
      };

      final result = service.compile(analysis: analysis, snapshots: snapshots);

      expect(result, isA<ProvenAlgorithmRepeatGrammar>());
      final grammar = (result as ProvenAlgorithmRepeatGrammar).grammar;
      expect(
        grammar.expand(_mixerWithRelationships(2, 1), [4, 2]),
        _mixerWithRelationships(4, 2),
      );
    });

    test('scalar-only fixed-row change contributes no repeat section', () {
      final specs = [_spec('Channels', min: 1, max: 4)];
      final plan = service.buildInitialPlan(specs);
      final canonical = _shape([2], [_parameter('Gain', max: 10)]);
      final lower = _shape([1], [_parameter('Gain', max: 9)]);
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: canonical,
        plan.lowerWitnessByAxis[0]!: lower,
      };

      expect(
        service.compile(
          analysis: service.analyzeInitial(
            specifications: specs,
            plan: plan,
            snapshots: snapshots,
          ),
          snapshots: snapshots,
        ),
        isA<NoAlgorithmRepeats>(),
      );
    });

    test('tied alignment and missing interaction witness are unproven', () {
      final specs = [_spec('Channels', min: 1, max: 4)];
      final plan = service.buildInitialPlan(specs);
      final snapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        plan.canonical: _shape([2], [_parameter('Same'), _parameter('Same')]),
        plan.lowerWitnessByAxis[0]!: _shape([1], [_parameter('Same')]),
      };
      expect(
        service.compile(
          analysis: service.analyzeInitial(
            specifications: specs,
            plan: plan,
            snapshots: snapshots,
          ),
          snapshots: snapshots,
        ),
        isA<UnprovenAlgorithmRepeats>(),
      );

      final mixerSpecs = [
        _spec('Channels', min: 1, max: 8),
        _spec('Sends', min: 0, max: 4),
      ];
      final mixerPlan = service.buildInitialPlan(mixerSpecs);
      final mixerSnapshots = <SpecificationVector, AlgorithmShapeSnapshot>{
        mixerPlan.canonical: _mixer(2, 1),
        mixerPlan.lowerWitnessByAxis[0]!: _mixer(1, 1),
        mixerPlan.lowerWitnessByAxis[1]!: _mixer(2, 0),
      };
      expect(
        service.compile(
          analysis: service.analyzeInitial(
            specifications: mixerSpecs,
            plan: mixerPlan,
            snapshots: mixerSnapshots,
          ),
          snapshots: mixerSnapshots,
        ),
        isA<UnprovenAlgorithmRepeats>(),
      );
    });
  });
}

Specification _spec(
  String name, {
  required int min,
  required int max,
  int? defaultValue,
  int type = 0,
}) => Specification(
  name: name,
  min: min,
  max: max,
  defaultValue: defaultValue ?? min,
  type: type,
);

AlgorithmShapeSnapshot _quantizer(int channels) => _shape(
  [channels],
  [
    _parameter('Mode'),
    for (var channel = 1; channel <= channels; channel++)
      _parameter('Ch $channel'),
  ],
);

AlgorithmShapeSnapshot _quantizerWithRelationships(int channels) {
  final parameters = <ShapeParameterAtom>[_parameter('Mode')];
  final pages = <ShapePageAtom>[const ShapePageAtom(name: 'General')];
  final memberships = <ShapePageMembershipAtom>[
    const ShapePageMembershipAtom(pageIndex: 0, parameterNumber: 0),
  ];
  final outputUsage = <ShapeOutputUsageAtom>[];
  for (var channel = 1; channel <= channels; channel++) {
    final firstParameter = parameters.length;
    parameters.addAll([
      _parameter('Ch $channel Output mode'),
      _parameter('Ch $channel CV output'),
    ]);
    final pageIndex = pages.length;
    pages.add(ShapePageAtom(name: 'Channel $channel'));
    memberships.addAll([
      ShapePageMembershipAtom(
        pageIndex: pageIndex,
        parameterNumber: firstParameter,
      ),
      ShapePageMembershipAtom(
        pageIndex: pageIndex,
        parameterNumber: firstParameter + 1,
      ),
    ]);
    outputUsage.add(
      ShapeOutputUsageAtom(
        parameterNumber: firstParameter,
        affectedParameterNumber: firstParameter + 1,
      ),
    );
  }
  return AlgorithmShapeSnapshot(
    specificationValues: [channels],
    parameters: parameters,
    pages: pages,
    pageMemberships: memberships,
    outputUsage: outputUsage,
  );
}

const _busEnum = ['None', 'Input 1', 'Input 2', 'Output 1', 'Aux 1'];

AlgorithmShapeSnapshot _busOutputRows(int channels) {
  final parameters = <ShapeParameterAtom>[_parameter('Bypass')];
  final pages = <ShapePageAtom>[const ShapePageAtom(name: 'Globals')];
  final memberships = <ShapePageMembershipAtom>[
    const ShapePageMembershipAtom(pageIndex: 0, parameterNumber: 0),
  ];
  final outputUsage = <ShapeOutputUsageAtom>[];
  for (var channel = 1; channel <= channels; channel++) {
    final firstParameter = parameters.length;
    parameters.addAll([
      _parameter(
        '$channel:Output',
        max: _busEnum.length - 1,
        enumStrings: _busEnum,
      ),
      _parameter('$channel:Output mode', enumStrings: const ['Add', 'Replace']),
    ]);
    final pageIndex = pages.length;
    pages.add(ShapePageAtom(name: 'Channel $channel'));
    memberships.addAll([
      ShapePageMembershipAtom(
        pageIndex: pageIndex,
        parameterNumber: firstParameter,
      ),
      ShapePageMembershipAtom(
        pageIndex: pageIndex,
        parameterNumber: firstParameter + 1,
      ),
    ]);
    outputUsage.add(
      ShapeOutputUsageAtom(
        parameterNumber: firstParameter + 1,
        affectedParameterNumber: firstParameter,
      ),
    );
  }
  return AlgorithmShapeSnapshot(
    specificationValues: [channels],
    parameters: parameters,
    pages: pages,
    pageMemberships: memberships,
    outputUsage: outputUsage,
  );
}

AlgorithmShapeSnapshot _mixer(int channels, int sends) => _shape(
  [channels, sends],
  [
    for (var channel = 1; channel <= channels; channel++) ...[
      _parameter('Channel $channel'),
      for (var send = 1; send <= sends; send++)
        _parameter('Channel $channel Send $send'),
    ],
  ],
);

AlgorithmShapeSnapshot _mixerWithRelationships(int channels, int sends) {
  final parameters = <ShapeParameterAtom>[];
  final pages = <ShapePageAtom>[];
  final memberships = <ShapePageMembershipAtom>[];
  final outputUsage = <ShapeOutputUsageAtom>[];
  for (var channel = 1; channel <= channels; channel++) {
    final channelParameter = parameters.length;
    parameters.add(_parameter('Channel $channel Level'));
    final pageIndex = pages.length;
    pages.add(ShapePageAtom(name: 'Channel $channel'));
    memberships.add(
      ShapePageMembershipAtom(
        pageIndex: pageIndex,
        parameterNumber: channelParameter,
      ),
    );
    for (var send = 1; send <= sends; send++) {
      final sendParameter = parameters.length;
      parameters.add(
        _parameter(
          'Channel $channel Send $send Gain',
          max: 100 + channel,
          enumStrings: ['Channel $channel Send $send'],
        ),
      );
      memberships.add(
        ShapePageMembershipAtom(
          pageIndex: pageIndex,
          parameterNumber: sendParameter,
        ),
      );
      outputUsage.add(
        ShapeOutputUsageAtom(
          parameterNumber: sendParameter,
          affectedParameterNumber: channelParameter,
        ),
      );
    }
  }
  return AlgorithmShapeSnapshot(
    specificationValues: [channels, sends],
    parameters: parameters,
    pages: pages,
    pageMemberships: memberships,
    outputUsage: outputUsage,
  );
}

AlgorithmShapeSnapshot _shape(
  List<int> specifications,
  List<ShapeParameterAtom> parameters,
) => AlgorithmShapeSnapshot(
  specificationValues: specifications,
  parameters: parameters,
  pages: const [],
  pageMemberships: const [],
  outputUsage: const [],
);

ShapeParameterAtom _parameter(
  String name, {
  int max = 1,
  List<String> enumStrings = const [],
}) => ShapeParameterAtom(
  name: name,
  min: 0,
  max: max,
  defaultValue: 0,
  rawUnitIndex: 0,
  powerOfTen: 0,
  ioFlags: 0,
  enumStrings: enumStrings,
);
