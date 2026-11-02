import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_sample_apply_service.dart';
import 'package:nt_helper/poly_multisample/poly_sample_mapping_resolver.dart';

void main() {
  group('PolySampleApplyService', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'poly_sample_apply_service_test_',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('automatic root remains absent from target filename', () {
      final region = PolyMultisampleParser.parsePath('/tmp/Kick.wav');
      final resolution = const PolySampleMappingResolver().resolve([region]);

      expect(resolution.mappings.single.naturalMidi, 48);
      expect(
        const PolySampleApplyService().buildTargetFileName(region),
        'Kick.wav',
      );
    });

    test('explicit Low is serialized as SW', () {
      final region = PolyMultisampleParser.parsePath(
        '/tmp/Piano_C3.wav',
      ).copyWith(switchPoint: 55);

      expect(
        const PolySampleApplyService().buildTargetFileName(region),
        'Piano_C3_SW55.wav',
      );
    });

    test('out-of-range parsed SW round trips until explicitly edited', () {
      final region = PolyMultisampleParser.parsePath('/tmp/Piano_C3_SW999.wav');
      final resolution = const PolySampleMappingResolver().resolve([region]);

      expect(
        resolution.issues.map((issue) => issue.kind),
        contains(PolySampleMappingIssueKind.switchOutOfMidiRange),
      );
      expect(
        const PolySampleApplyService().buildTargetFileName(region),
        'Piano_C3_SW999.wav',
      );
    });

    test('builds target filenames while preserving source prefixes', () {
      final source = File('${tempRoot.path}/SoftPiano_C3_SW48_V1_RR1.wav')
        ..writeAsBytesSync([1, 2, 3]);
      final baseline = [
        PolyMultisampleParser.parseFile(source, basePath: tempRoot.path),
      ];
      final edited = [
        baseline.single.copyWith(
          rootMidi: 62,
          rootName: 'D3',
          switchPoint: 50,
          velocityLayer: 2,
          roundRobin: 1,
        ),
      ];

      final plan = PolySampleApplyService().buildPlan(
        baselineRegions: baseline,
        editedRegions: edited,
        targetFolder: tempRoot.path,
      );

      expect(plan.hasConflicts, isFalse);
      expect(plan.renames, hasLength(1));
      expect(plan.renames.single.fromPath, source.path);
      expect(
        plan.renames.single.toPath.replaceAll('\\', '/'),
        endsWith('/SoftPiano_D3_SW50_V2.wav'),
      );
    });

    test('detects local target conflicts before mutation', () {
      final source = File('${tempRoot.path}/SoftPiano_C3.wav')
        ..writeAsBytesSync([1]);
      final conflict = File('${tempRoot.path}/SoftPiano_D3.wav')
        ..writeAsBytesSync([2]);
      final baseline = [
        PolyMultisampleParser.parseFile(source, basePath: tempRoot.path),
      ];
      final edited = [baseline.single.copyWith(rootMidi: 62, rootName: 'D3')];

      final plan = PolySampleApplyService().buildPlan(
        baselineRegions: baseline,
        editedRegions: edited,
        targetFolder: tempRoot.path,
        existingPaths: {conflict.path},
      );

      expect(plan.conflicts, hasLength(1));
      expect(plan.conflicts.single.path, conflict.path);
      expect(source.existsSync(), isTrue);
      expect(conflict.readAsBytesSync(), [2]);
    });

    test(
      'applies local two-step renames without overwriting swapped targets',
      () async {
        final c3 = File('${tempRoot.path}/SoftPiano_C3.wav')
          ..writeAsBytesSync([3]);
        final d3 = File('${tempRoot.path}/SoftPiano_D3.wav')
          ..writeAsBytesSync([4]);
        final baseline = [
          PolyMultisampleParser.parseFile(c3, basePath: tempRoot.path),
          PolyMultisampleParser.parseFile(d3, basePath: tempRoot.path),
        ];
        final edited = [
          baseline[0].copyWith(rootMidi: 62, rootName: 'D3'),
          baseline[1].copyWith(rootMidi: 60, rootName: 'C3'),
        ];

        final plan = PolySampleApplyService().buildPlan(
          baselineRegions: baseline,
          editedRegions: edited,
          targetFolder: tempRoot.path,
        );

        expect(plan.hasConflicts, isFalse);

        await PolySampleApplyService().applyLocalPlan(plan);

        expect(File('${tempRoot.path}/SoftPiano_C3.wav').readAsBytesSync(), [
          4,
        ]);
        expect(File('${tempRoot.path}/SoftPiano_D3.wav').readAsBytesSync(), [
          3,
        ]);
      },
    , tags: ['regression']);

    test(
      'does not delete existing files when an addition source is missing',
      () async {
        final removed = File('${tempRoot.path}/SoftPiano_C3.wav')
          ..writeAsBytesSync([3]);
        final baseline = [
          PolyMultisampleParser.parseFile(removed, basePath: tempRoot.path),
        ];
        final missingSource = '${tempRoot.path}/imports/SoftPiano_D3.wav';
        final edited = [
          PolyMultisampleParser.parseFile(
            File(missingSource),
            basePath: tempRoot.path,
          ),
        ];

        final plan = PolySampleApplyService().buildPlan(
          baselineRegions: baseline,
          editedRegions: edited,
          targetFolder: tempRoot.path,
        );

        expect(plan.hasConflicts, isFalse);

        await expectLater(
          PolySampleApplyService().applyLocalPlan(plan),
          throwsA(isA<PolySampleApplyException>()),
        );
        expect(removed.existsSync(), isTrue);
        expect(removed.readAsBytesSync(), [3]);
      },
    , tags: ['regression']);

    test('does not rename files when an addition target exists', () async {
      final renamed = File('${tempRoot.path}/SoftPiano_C3.wav')
        ..writeAsBytesSync([3]);
      final blockingTarget = File('${tempRoot.path}/imports/SoftPiano_E3.wav')
        ..createSync(recursive: true)
        ..writeAsBytesSync([9]);
      final additionSource = File('${tempRoot.path}/outside/SoftPiano_E3.wav')
        ..createSync(recursive: true)
        ..writeAsBytesSync([5]);
      final baseline = [
        PolyMultisampleParser.parseFile(renamed, basePath: tempRoot.path),
      ];
      final edited = [
        baseline.single.copyWith(rootMidi: 62, rootName: 'D3'),
        PolyMultisampleParser.parseFile(
          additionSource,
          basePath: additionSource.parent.path,
        ),
      ];

      final plan = PolySampleApplyService().buildPlan(
        baselineRegions: baseline,
        editedRegions: edited,
        targetFolder: blockingTarget.parent.path,
      );

      expect(plan.hasConflicts, isFalse);

      await expectLater(
        PolySampleApplyService().applyLocalPlan(plan),
        throwsA(isA<PolySampleApplyException>()),
      );
      expect(renamed.existsSync(), isTrue);
      expect(renamed.readAsBytesSync(), [3]);
      expect(blockingTarget.readAsBytesSync(), [9]);
    });

    test('does not delete files when a rename target already exists', () async {
      final removed = File('${tempRoot.path}/SoftPiano_E3.wav')
        ..writeAsBytesSync([5]);
      final renamed = File('${tempRoot.path}/SoftPiano_C3.wav')
        ..writeAsBytesSync([3]);
      final blockingTarget = File('${tempRoot.path}/SoftPiano_D3.wav')
        ..writeAsBytesSync([9]);
      final baseline = [
        PolyMultisampleParser.parseFile(removed, basePath: tempRoot.path),
        PolyMultisampleParser.parseFile(renamed, basePath: tempRoot.path),
      ];
      final edited = [baseline[1].copyWith(rootMidi: 62, rootName: 'D3')];

      final plan = PolySampleApplyService().buildPlan(
        baselineRegions: baseline,
        editedRegions: edited,
        targetFolder: tempRoot.path,
      );

      expect(plan.hasConflicts, isFalse);

      await expectLater(
        PolySampleApplyService().applyLocalPlan(plan),
        throwsA(isA<PolySampleApplyException>()),
      );
      expect(removed.existsSync(), isTrue);
      expect(removed.readAsBytesSync(), [5]);
      expect(renamed.existsSync(), isTrue);
      expect(renamed.readAsBytesSync(), [3]);
      expect(blockingTarget.readAsBytesSync(), [9]);
    }, tags: ['regression']);

    test('does not delete files when a rename target is a directory', () async {
      final removed = File('${tempRoot.path}/SoftPiano_E3.wav')
        ..writeAsBytesSync([5]);
      final renamed = File('${tempRoot.path}/SoftPiano_C3.wav')
        ..writeAsBytesSync([3]);
      Directory('${tempRoot.path}/SoftPiano_D3.wav').createSync();
      final baseline = [
        PolyMultisampleParser.parseFile(removed, basePath: tempRoot.path),
        PolyMultisampleParser.parseFile(renamed, basePath: tempRoot.path),
      ];
      final edited = [baseline[1].copyWith(rootMidi: 62, rootName: 'D3')];

      final plan = PolySampleApplyService().buildPlan(
        baselineRegions: baseline,
        editedRegions: edited,
        targetFolder: tempRoot.path,
      );

      await expectLater(
        PolySampleApplyService().applyLocalPlan(plan),
        throwsA(isA<PolySampleApplyException>()),
      );
      expect(removed.existsSync(), isTrue);
      expect(renamed.existsSync(), isTrue);
    }, tags: ['regression']);

    test(
      'does not delete files when an addition target is a directory',
      () async {
        final removed = File('${tempRoot.path}/SoftPiano_C3.wav')
          ..writeAsBytesSync([3]);
        final additionSource = File('${tempRoot.path}/outside/SoftPiano_D3.wav')
          ..createSync(recursive: true)
          ..writeAsBytesSync([5]);
        Directory(
          '${tempRoot.path}/imports/SoftPiano_D3.wav',
        ).createSync(recursive: true);
        final baseline = [
          PolyMultisampleParser.parseFile(removed, basePath: tempRoot.path),
        ];
        final edited = [
          PolyMultisampleParser.parseFile(
            additionSource,
            basePath: additionSource.parent.path,
          ),
        ];

        final plan = PolySampleApplyService().buildPlan(
          baselineRegions: baseline,
          editedRegions: edited,
          targetFolder: '${tempRoot.path}/imports',
        );

        await expectLater(
          PolySampleApplyService().applyLocalPlan(plan),
          throwsA(isA<PolySampleApplyException>()),
        );
        expect(removed.existsSync(), isTrue);
      },
    );

    test(
      'does not treat a removed directory as a vacated rename target',
      () async {
        final vacatedDirectory = Directory('${tempRoot.path}/SoftPiano_D3.wav')
          ..createSync();
        final renamed = File('${tempRoot.path}/SoftPiano_C3.wav')
          ..writeAsBytesSync([3]);
        final baseline = [
          PolyMultisampleParser.parseFile(
            File(vacatedDirectory.path),
            basePath: tempRoot.path,
          ),
          PolyMultisampleParser.parseFile(renamed, basePath: tempRoot.path),
        ];
        final edited = [baseline[1].copyWith(rootMidi: 62, rootName: 'D3')];

        final plan = PolySampleApplyService().buildPlan(
          baselineRegions: baseline,
          editedRegions: edited,
          targetFolder: tempRoot.path,
        );

        await expectLater(
          PolySampleApplyService().applyLocalPlan(plan),
          throwsA(isA<PolySampleApplyException>()),
        );
        expect(vacatedDirectory.existsSync(), isTrue);
        expect(renamed.existsSync(), isTrue);
      },
    , tags: ['regression']);

    test(
      'does not treat a removed directory as a vacated addition target',
      () async {
        final vacatedDirectory = Directory('${tempRoot.path}/SoftPiano_D3.wav')
          ..createSync();
        final additionSource = File('${tempRoot.path}/outside/SoftPiano_D3.wav')
          ..createSync(recursive: true)
          ..writeAsBytesSync([5]);
        final baseline = [
          PolyMultisampleParser.parseFile(
            File(vacatedDirectory.path),
            basePath: tempRoot.path,
          ),
        ];
        final edited = [
          PolyMultisampleParser.parseFile(
            additionSource,
            basePath: additionSource.parent.path,
          ),
        ];

        final plan = PolySampleApplyService().buildPlan(
          baselineRegions: baseline,
          editedRegions: edited,
          targetFolder: tempRoot.path,
        );

        await expectLater(
          PolySampleApplyService().applyLocalPlan(plan),
          throwsA(isA<PolySampleApplyException>()),
        );
        expect(vacatedDirectory.existsSync(), isTrue);
      },
    , tags: ['regression']);
  });
}
