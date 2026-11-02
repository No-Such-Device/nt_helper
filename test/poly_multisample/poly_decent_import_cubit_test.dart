import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/decent_sampler_converter.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_import_service.dart';
import 'package:nt_helper/ui/poly_multisample/poly_decent_import_cubit.dart';

void main() {
  group('PolyDecentImportCubit', () {
    test('blocks manual continuation when group ranges overlap', () async {
      final service = _FakeImportService(_overlappingAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.keyRanges);

      expect(cubit.state.status, PolyDecentImportStatus.ready);
      expect(cubit.state.canContinue, isFalse);
      expect(cubit.state.warnings.single, contains('overlap'));

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
      expect(cubit.state.error, contains('overlap'));
    }, tags: ['regression']);

    test('manual range edits do not auto-shift other rows', () async {
      final service = _FakeImportService(_overlappingAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.keyRanges);
      cubit.updateGroupRange(
        'group:1:Group 2',
        const DecentSamplerTagKeyRange(lowMidi: 62, rootMidi: 62, highMidi: 62),
      );

      expect(cubit.state.manualGroupRanges['group:0:Group 1']!.lowMidi, 60);
      expect(cubit.state.manualGroupRanges['group:0:Group 1']!.highMidi, 61);
      expect(cubit.state.canContinue, isTrue);

      await cubit.continueImport();

      expect(service.stageCallCount, 1);
      expect(service.lastOptions!.selectedGroupKeys, [
        'group:0:Group 1',
        'group:1:Group 2',
      ]);
      expect(cubit.state.status, PolyDecentImportStatus.completed);
    }, tags: ['regression']);

    test('analyzeSource seeds tag ranges and preset selection', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');

      expect(cubit.state.selectedPresetNames, {'Layered'});
      expect(
        cubit.state.tagKeyRanges.keys,
        containsAll(['tag:soft', 'tag:hard']),
      );
      expect(cubit.state.tagKeyRanges['tag:soft']!.lowMidi, 60);
      expect(cubit.state.tagKeyRanges['tag:soft']!.rootMidi, 60);
      expect(cubit.state.tagKeyRanges['tag:soft']!.highMidi, 61);
    });

    test(
      'blocks continuation when every visible preset is unchecked',
      () async {
        final service = _FakeImportService(_multiPresetAnalysis());
        final cubit = PolyDecentImportCubit(importService: service);
        addTearDown(cubit.close);

        await cubit.analyzeSource('/tmp/Layered.dspreset');
        cubit.togglePreset('Layer A');
        cubit.togglePreset('Layer B');

        expect(cubit.state.selectedPresetNames, isEmpty);
        expect(cubit.state.canContinue, isFalse);

        await cubit.continueImport();

        expect(service.stageCallCount, 0);
        expect(cubit.state.error, contains('not ready'));
      },
    );

    test('selectedGroup handling preselects the first group', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.selectedGroup);

      expect(cubit.state.selectedGroupKey, 'group:0:Group 1');
      expect(cubit.state.canContinue, isTrue);

      await cubit.continueImport();

      expect(service.lastOptions!.selectedGroupKey, 'group:0:Group 1');
    });

    test('selectedTags handling requires at least one selected tag', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.selectedTags);

      expect(cubit.state.canContinue, isFalse);

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
    });

    test('tagMapping handling requires at least one selected tag', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.tagMapping);

      expect(cubit.state.canContinue, isFalse);

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
      expect(cubit.state.error, contains('not ready'));
    });

    test('manual ranges must keep low, root, and high ordered', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.selectedTags);
      cubit.toggleTag('tag:soft');
      cubit.setTagRange(
        'tag:soft',
        const DecentSamplerTagKeyRange(lowMidi: 64, rootMidi: 60, highMidi: 63),
      );

      expect(cubit.state.canContinue, isFalse);
      expect(cubit.state.warnings.single, contains('invalid key range'));

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
    });

    test('key range handling requires at least one enabled group', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.keyRanges);
      for (final entry in cubit.state.manualGroupRanges.entries) {
        cubit.updateGroupRange(
          entry.key,
          DecentSamplerTagKeyRange(
            lowMidi: entry.value.lowMidi,
            rootMidi: entry.value.rootMidi,
            highMidi: entry.value.highMidi,
            enabled: false,
          ),
        );
      }

      expect(cubit.state.canContinue, isFalse);

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
    });

    test('velocity layer mode forwards only explicit velocity edits', () async {
      final service = _FakeImportService(_overlappingAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.velocityLayers);
      cubit.setGroupVelocity('group:0:Group 1', 2);

      await cubit.continueImport();

      expect(service.lastOptions!.groupVelocityLayers, {'group:0:Group 1': 2});
    });

    test(
      'velocity layer mode does not forward stale manual round robins',
      () async {
        final service = _FakeImportService(_overlappingAnalysis());
        final cubit = PolyDecentImportCubit(importService: service);
        addTearDown(cubit.close);

        await cubit.analyzeSource('/tmp/Layered.dspreset');
        cubit.setGroupHandling(DecentSamplerGroupHandling.keyRanges);
        cubit.setGroupRoundRobin('group:0:Group 1', 2);
        cubit.setGroupHandling(DecentSamplerGroupHandling.velocityLayers);

        await cubit.continueImport();

        expect(service.lastOptions!.groupRoundRobins, isEmpty);
      },
    , tags: ['regression']);

    test('group modes do not forward stale selected tag options', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.selectedTags);
      cubit.toggleTag('tag:soft');
      cubit.setTagVelocity('tag:soft', 2);
      cubit.setTagRoundRobin('tag:soft', 3);
      cubit.setGroupHandling(DecentSamplerGroupHandling.velocityLayers);

      await cubit.continueImport();

      final options = service.lastOptions!;
      expect(options.selectedTagKeys, isEmpty);
      expect(options.tagVelocityLayers, isEmpty);
      expect(options.tagKeyRanges, isEmpty);
      expect(options.tagRoundRobins, isEmpty);
    }, tags: ['regression']);

    test('tagMapping forwards selected tag options', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.tagMapping);
      cubit.toggleTag('tag:soft');
      cubit.setTagVelocity('tag:soft', 2);
      cubit.setTagRoundRobin('tag:soft', 3);

      await cubit.continueImport();

      final options = service.lastOptions!;
      expect(options.selectedTagKeys, ['tag:soft']);
      expect(options.tagVelocityLayers, {'tag:soft': 2});
      expect(options.tagRoundRobins, {'tag:soft': 3});
      expect(options.tagKeyRanges, isEmpty);
    });

    test('tagMapping allows velocity-only overlapping tags', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.tagMapping);
      cubit.toggleTag('tag:soft');
      cubit.toggleTag('tag:hard');
      cubit.setTagVelocity('tag:soft', 1);
      cubit.setTagVelocity('tag:hard', 2);

      expect(cubit.state.warnings, isEmpty);
      expect(cubit.state.canContinue, isTrue);

      await cubit.continueImport();

      final options = service.lastOptions!;
      expect(service.stageCallCount, 1);
      expect(options.tagVelocityLayers, {'tag:soft': 1, 'tag:hard': 2});
      expect(options.tagKeyRanges, isEmpty);
    });

    test('tagMapping validates selected tag ranges', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setGroupHandling(DecentSamplerGroupHandling.tagMapping);
      cubit.toggleTag('tag:soft');
      cubit.setTagRange(
        'tag:soft',
        const DecentSamplerTagKeyRange(lowMidi: 64, rootMidi: 60, highMidi: 63),
      );

      expect(cubit.state.canContinue, isFalse);
      expect(cubit.state.warnings.single, contains('invalid key range'));

      await cubit.continueImport();

      expect(service.stageCallCount, 0);
    });

    test(
      'setTagRange recomputes overlap warnings under selectedTags',
      () async {
        final service = _FakeImportService(_taggedAnalysis());
        final cubit = PolyDecentImportCubit(importService: service);
        addTearDown(cubit.close);

        await cubit.analyzeSource('/tmp/Layered.dspreset');
        cubit.toggleTag('tag:soft');
        cubit.toggleTag('tag:hard');

        expect(cubit.state.warnings, isNotEmpty);

        cubit.setTagRange(
          'tag:hard',
          const DecentSamplerTagKeyRange(
            lowMidi: 62,
            rootMidi: 62,
            highMidi: 63,
          ),
        );

        expect(cubit.state.warnings, isEmpty);
      },
    );

    test('continueImport forwards the full option set', () async {
      final service = _FakeImportService(_taggedAnalysis());
      final cubit = PolyDecentImportCubit(importService: service);
      addTearDown(cubit.close);

      await cubit.analyzeSource('/tmp/Layered.dspreset');
      cubit.setPreserveXmlMapping(true);
      cubit.setAddUnmapped(true);
      cubit.toggleTag('tag:soft');
      cubit.setTagRoundRobin('tag:soft', 2);

      await cubit.continueImport();

      final options = service.lastOptions!;
      expect(options.preserveXmlMapping, isTrue);
      expect(options.addUnmapped, isTrue);
      expect(options.selectedTagKeys, ['tag:soft']);
      expect(options.tagRoundRobins['tag:soft'], 2);
    });
  });
}

class _FakeImportService extends PolySampleImportService {
  _FakeImportService(this.analysis);

  final DecentSamplerImportAnalysis analysis;
  int stageCallCount = 0;
  DecentSamplerConvertOptions? lastOptions;

  @override
  Future<DecentSamplerImportAnalysis> analyzeDecentSource(String path) async {
    return analysis;
  }

  @override
  Future<PolyStagedImport> stageDecentSource(
    String path, {
    DecentSamplerConvertOptions options = const DecentSamplerConvertOptions(),
    String? outputParentPath,
  }) async {
    stageCallCount++;
    lastOptions = options;
    return const PolyStagedImport(
      name: 'Layered',
      sourceLabel: '/tmp/Layered.dspreset',
      regions: [],
    );
  }
}

DecentSamplerImportAnalysis _overlappingAnalysis() {
  return const DecentSamplerImportAnalysis(
    presetName: 'Layered',
    presets: [
      DecentSamplerPresetInfo(
        name: 'Layered',
        groupCount: 2,
        sampleCount: 4,
        tagCount: 0,
      ),
    ],
    groups: [
      DecentSamplerGroupInfo(
        key: 'group:0:Group 1',
        name: 'Group 1',
        xmlSummary: 'Group 1',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['soft_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
      DecentSamplerGroupInfo(
        key: 'group:1:Group 2',
        name: 'Group 2',
        xmlSummary: 'Group 2',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['hard_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
    ],
    tags: [],
    hasAmbiguousOverlaps: true,
    structureSummary: '2 overlapping groups',
    recommendedGroupHandling: DecentSamplerGroupHandling.keyRanges,
  );
}

DecentSamplerImportAnalysis _taggedAnalysis() {
  return const DecentSamplerImportAnalysis(
    presetName: 'Layered',
    presets: [
      DecentSamplerPresetInfo(
        name: 'Layered',
        groupCount: 2,
        sampleCount: 4,
        tagCount: 2,
      ),
    ],
    groups: [
      DecentSamplerGroupInfo(
        key: 'group:0:Group 1',
        name: 'Group 1',
        xmlSummary: 'Group 1',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['soft_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
      DecentSamplerGroupInfo(
        key: 'group:1:Group 2',
        name: 'Group 2',
        xmlSummary: 'Group 2',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['hard_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
    ],
    tags: [
      DecentSamplerTag(
        key: 'tag:soft',
        label: 'soft',
        groupKeys: ['group:0:Group 1'],
        sampleCount: 2,
        confidence: 1.0,
        evidence: '',
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
      DecentSamplerTag(
        key: 'tag:hard',
        label: 'hard',
        groupKeys: ['group:1:Group 2'],
        sampleCount: 2,
        confidence: 1.0,
        evidence: '',
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
    ],
    hasAmbiguousOverlaps: true,
    structureSummary: '2 overlapping tags',
    recommendedGroupHandling: DecentSamplerGroupHandling.selectedTags,
  );
}

DecentSamplerImportAnalysis _multiPresetAnalysis() {
  return const DecentSamplerImportAnalysis(
    presetName: 'Layered',
    presets: [
      DecentSamplerPresetInfo(
        name: 'Layer A',
        groupCount: 1,
        sampleCount: 2,
        tagCount: 0,
      ),
      DecentSamplerPresetInfo(
        name: 'Layer B',
        groupCount: 1,
        sampleCount: 2,
        tagCount: 0,
      ),
    ],
    groups: [
      DecentSamplerGroupInfo(
        key: 'group:0:Group 1',
        name: 'Group 1',
        xmlSummary: 'Group 1',
        sampleCount: 2,
        rootCount: 2,
        structureSummary: 'C4-D4',
        noteRange: 'C4 - D4',
        velocitySummary: '1-127',
        roundRobinSummary: 'No seqPosition',
        examples: ['soft_c4.wav'],
        defaultLowMidi: 60,
        defaultRootMidi: 60,
        defaultHighMidi: 61,
        defaultVelocityLayer: 1,
      ),
    ],
    tags: [],
    hasAmbiguousOverlaps: false,
    structureSummary: '2 presets',
    recommendedGroupHandling: DecentSamplerGroupHandling.auto,
  );
}
