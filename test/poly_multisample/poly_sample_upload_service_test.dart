import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/sd_card_file_system.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_parser.dart';
import 'package:nt_helper/poly_multisample/poly_sample_upload_service.dart';

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

typedef ChunkUploadCall = ({
  String path,
  Uint8List data,
  int position,
  bool createAlways,
});

void main() {
  late Directory tempRoot;
  late PolySampleUploadService service;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync(
      'poly_sample_upload_service_test_',
    );
    service = const PolySampleUploadService();
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  test('automatic rootless upload preserves raw filename', () {
    final source = File('${tempRoot.path}/Kick.wav')..createSync();

    final files = service.buildUploadFiles(
      regions: [PolyMultisampleParser.parsePath(source.path)],
      targetFolder: '/multisamples/Drums',
    );

    expect(files.single.targetPath, '/multisamples/Drums/Kick.wav');
    expect(files.single.targetPath, isNot(contains('_C')));
  });

  test('buildUploadFiles rejects duplicate target names', () {
    final sourceA = File('${tempRoot.path}/a/Piano_C3.wav')
      ..createSync(recursive: true);
    final sourceB = File('${tempRoot.path}/b/Piano_C3.wav')
      ..createSync(recursive: true);

    expect(
      () => service.buildUploadFiles(
        regions: [
          PolySampleRegion(
            path: sourceA.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
          PolySampleRegion(
            path: sourceB.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        targetFolder: '${tempRoot.path}/dest',
      ),
      throwsA(
        isA<PolySampleUploadException>().having(
          (error) => error.message,
          'message',
          contains('Multiple samples target Piano_C3.wav'),
        ),
      ),
    );
  });

  test('adaptive ETA estimator waits for a usable rate sample', () {
    final estimator = AdaptiveTransferRateEstimator();

    expect(estimator.estimate(remainingBytes: 1000), isNull);
    estimator.record(
      completedBytes: 512,
      elapsed: const Duration(milliseconds: 100),
    );

    expect(estimator.sampleCount, 0);
    expect(estimator.estimate(remainingBytes: 1000), isNull);
  });

  test('adaptive ETA estimator adjusts when later transfer rate slows', () {
    final estimator = AdaptiveTransferRateEstimator(
      minSampleDuration: const Duration(seconds: 1),
      minSampleBytes: 1,
    );

    estimator.record(completedBytes: 1000, elapsed: const Duration(seconds: 1));
    final earlyEstimate = estimator.estimate(remainingBytes: 3000);

    estimator.record(completedBytes: 1250, elapsed: const Duration(seconds: 2));
    estimator.record(completedBytes: 1500, elapsed: const Duration(seconds: 3));
    final adjustedEstimate = estimator.estimate(remainingBytes: 3000);

    expect(earlyEstimate, isNotNull);
    expect(adjustedEstimate, isNotNull);
    expect(adjustedEstimate!, greaterThan(earlyEstimate!));
  });

  test('adaptive ETA estimator ignores timing gaps between files', () {
    final estimator = AdaptiveTransferRateEstimator(
      minSampleDuration: const Duration(seconds: 1),
      minSampleBytes: 1,
    );

    estimator.record(
      completedBytes: 1000,
      elapsed: const Duration(seconds: 1),
      segmentId: 1,
    );
    estimator.record(
      completedBytes: 2000,
      elapsed: const Duration(seconds: 2),
      segmentId: 1,
    );
    final beforeFileSwitch = estimator.estimate(remainingBytes: 1000);

    estimator.record(
      completedBytes: 2512,
      elapsed: const Duration(seconds: 10),
      segmentId: 2,
    );
    estimator.record(
      completedBytes: 3512,
      elapsed: const Duration(seconds: 11),
      segmentId: 2,
    );
    final afterFileSwitch = estimator.estimate(remainingBytes: 1000);

    expect(beforeFileSwitch, const Duration(seconds: 1));
    expect(afterFileSwitch, const Duration(seconds: 1));
    expect(estimator.sampleCount, 3);
  }, tags: ['regression']);

  test('adaptive ETA estimator excludes extreme outlier samples', () {
    final estimator = AdaptiveTransferRateEstimator(
      minSampleDuration: const Duration(seconds: 1),
      minSampleBytes: 1,
    );

    for (var second = 1; second <= 5; second++) {
      estimator.record(
        completedBytes: second * 1000,
        elapsed: Duration(seconds: second),
      );
    }
    estimator.record(
      completedBytes: 5001,
      elapsed: const Duration(seconds: 15),
    );
    estimator.record(
      completedBytes: 6001,
      elapsed: const Duration(seconds: 16),
    );

    expect(
      estimator.estimate(remainingBytes: 1000),
      lessThanOrEqualTo(const Duration(milliseconds: 1100)),
    );
  }, tags: ['regression']);

  test(
    'uploadMountedSd copies renamed files and preserves unrelated files',
    () async {
      final sourceDir = Directory('${tempRoot.path}/source')..createSync();
      final destinationDir = Directory('${tempRoot.path}/dest')..createSync();
      final source = File('${sourceDir.path}/Piano_C3.wav')
        ..writeAsBytesSync([1, 2, 3]);
      final target = File('${destinationDir.path}/Piano_C3.wav')
        ..writeAsBytesSync([9, 9, 9]);
      final unrelated = File('${destinationDir.path}/unrelated.txt')
        ..writeAsStringSync('keep');

      await service.uploadMountedSd(
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        destinationFolder: destinationDir.path,
      );

      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(unrelated.existsSync(), isTrue);
    },
  );

  test(
    'uploadMountedSd skips same source and target path without deleting',
    () async {
      final destinationDir = Directory('${tempRoot.path}/dest')..createSync();
      final source = File('${destinationDir.path}/Piano_C3.wav')
        ..writeAsBytesSync([1, 2, 3]);

      await service.uploadMountedSd(
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        destinationFolder: destinationDir.path,
      );

      expect(await source.readAsBytes(), [1, 2, 3]);
    },
  );

  test('uploadMountedSd keeps progress details on uploading lines', () async {
    final sourceDir = Directory('${tempRoot.path}/source')..createSync();
    final destinationDir = Directory('${tempRoot.path}/dest')..createSync();
    final progressMessages = <String>[];
    final first = File('${sourceDir.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final second = File('${sourceDir.path}/Piano_D3.wav')
      ..writeAsBytesSync([4, 5, 6]);

    await service.uploadMountedSd(
      regions: [
        PolySampleRegion(
          path: first.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
        PolySampleRegion(
          path: second.path,
          fileName: 'Piano_D3.wav',
          displayName: 'Piano_D3.wav',
          rootMidi: 50,
        ),
      ],
      destinationFolder: destinationDir.path,
      onProgress: progressMessages.add,
    );

    final uploadingMessages = progressMessages
        .where((message) => message.startsWith('Uploading '))
        .toList();
    expect(uploadingMessages, isNotEmpty);
    expect(uploadingMessages, everyElement(contains(' of 6 B, ')));
    expect(uploadingMessages, everyElement(endsWith(')')));
  });

  test(
    'uploadSysEx creates parents, uploads chunks, and checks names and sizes',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final source = File('${tempRoot.path}/Piano_C3.wav')
        ..writeAsBytesSync([1, 2, 3]);
      _stubDirectoryCreates(manager);
      _stubChunkUploads(manager, chunkCalls);
      when(
        () => manager.requestDirectoryListing('/multisamples/Piano/Nested'),
      ).thenAnswer(
        (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 3)]),
      );

      final result = await service.uploadSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        hardwareFolder: '/multisamples/Piano/Nested',
      );

      verify(
        () => manager.requestDirectoryCreate('/multisamples/Piano'),
      ).called(1);
      verify(
        () => manager.requestDirectoryCreate('/multisamples/Piano/Nested'),
      ).called(1);
      expect(chunkCalls, hasLength(1));
      expect(chunkCalls.single.path, '/multisamples/Piano/Nested/Piano_C3.wav');
      expect(chunkCalls.single.data, [1, 2, 3]);
      expect(chunkCalls.single.position, 0);
      expect(chunkCalls.single.createAlways, isTrue);
      verifyNever(() => manager.requestFileUpload(any(), any()));
      verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
      expect(result.correctedFiles, 0);
      expect(result.failedVerificationFiles, 0);
    },
  );

  test('uploadSysEx continues when hardware folder already exists', () async {
    final manager = MockDistingMidiManager();
    final chunkCalls = <ChunkUploadCall>[];
    final source = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    when(
      () => manager.requestDirectoryCreate('/multisamples/Piano'),
    ).thenAnswer(
      (_) async =>
          SdCardStatus(success: false, message: 'Unable to create folder'),
    );
    when(
      () => manager.requestDirectoryListing('/multisamples'),
    ).thenAnswer((_) async => DirectoryListing(entries: [_dir('Piano')]));
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 3)]),
    );
    _stubChunkUploads(manager, chunkCalls);

    final result = await service.uploadSysEx(
      manager: manager,
      regions: [
        PolySampleRegion(
          path: source.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
      ],
      hardwareFolder: '/multisamples/Piano',
    );

    expect(result.filesUploaded, 1);
    expect(chunkCalls.single.path, '/multisamples/Piano/Piano_C3.wav');
  }, tags: ['regression']);

  test('uploadSysEx keeps progress details on every uploading line', () async {
    final manager = MockDistingMidiManager();
    final chunkCalls = <ChunkUploadCall>[];
    final progressMessages = <String>[];
    final first = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    final second = File('${tempRoot.path}/Piano_D3.wav')
      ..writeAsBytesSync([4, 5, 6]);
    _stubDirectoryCreates(manager);
    _stubChunkUploads(manager, chunkCalls);
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(
        entries: [_file('Piano_C3.wav', 3), _file('Piano_D3.wav', 3)],
      ),
    );

    await service.uploadSysEx(
      manager: manager,
      regions: [
        PolySampleRegion(
          path: first.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
        PolySampleRegion(
          path: second.path,
          fileName: 'Piano_D3.wav',
          displayName: 'Piano_D3.wav',
          rootMidi: 50,
        ),
      ],
      hardwareFolder: '/multisamples/Piano',
      onProgress: progressMessages.add,
    );

    final uploadingMessages = progressMessages
        .where((message) => message.startsWith('Uploading '))
        .toList();
    expect(uploadingMessages, isNotEmpty);
    expect(uploadingMessages, everyElement(contains(' of 6 B, ')));
    expect(uploadingMessages, everyElement(endsWith(')')));
  });

  test('validateSysEx checks uploaded files with directory listing', () async {
    final manager = MockDistingMidiManager();
    final source = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 3)]),
    );

    final result = await service.validateSysEx(
      manager: manager,
      regions: [
        PolySampleRegion(
          path: source.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
      ],
      hardwareFolder: '/multisamples/Piano',
    );

    expect(result.filesChecked, 1);
    expect(result.bytesChecked, 3);
    expect(result.failedFiles, 0);
    verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
    verifyNever(
      () => manager.requestFileUploadChunk(
        any(),
        any(),
        any(),
        createAlways: any(named: 'createAlways'),
      ),
    );
  });

  test('validateSysEx rejects unsupported content validation', () async {
    final manager = MockDistingMidiManager();
    final source = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 3)]),
    );

    await expectLater(
      service.validateSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        hardwareFolder: '/multisamples/Piano',
        verifyContent: true,
      ),
      throwsA(
        isA<PolySampleUploadException>().having(
          (error) => error.message,
          'message',
          contains('whole files only'),
        ),
      ),
    );
    verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
  });

  test('validateSysEx reports size mismatches before downloading', () async {
    final manager = MockDistingMidiManager();
    final source = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 2)]),
    );

    final result = await service.validateSysEx(
      manager: manager,
      regions: [
        PolySampleRegion(
          path: source.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
      ],
      hardwareFolder: '/multisamples/Piano',
    );

    expect(result.filesChecked, 1);
    expect(result.failedFiles, 1);
    verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
  });

  test(
    'uploadSysEx writes semantic filenames into multisamples folder',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final c3Bytes = Uint8List.fromList([1, 2, 3]);
      final d3Bytes = Uint8List.fromList([4, 5, 6]);
      final c3 = File('${tempRoot.path}/Pno_C3.wav')..writeAsBytesSync(c3Bytes);
      final d3 = File('${tempRoot.path}/Pno_C3_take2.wav')
        ..writeAsBytesSync(d3Bytes);
      _stubDirectoryCreates(manager);
      _stubChunkUploads(manager, chunkCalls);
      when(
        () => manager.requestDirectoryListing('/multisamples/Piano'),
      ).thenAnswer(
        (_) async => DirectoryListing(
          entries: [
            _file('Pno_C3_SW48_V1_RR1.wav', c3Bytes.length),
            _file('Pno_take2_D3_SW60_V2_RR3.wav', d3Bytes.length),
          ],
        ),
      );

      await service.uploadSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: c3.path,
            fileName: 'Pno_C3.wav',
            displayName: 'Pno_C3.wav',
            rootMidi: 48,
            switchPoint: 48,
            velocityLayer: 1,
            roundRobin: 1,
          ),
          PolySampleRegion(
            path: d3.path,
            fileName: 'Pno_C3_take2.wav',
            displayName: 'Pno_C3_take2.wav',
            rootMidi: 50,
            switchPoint: 60,
            velocityLayer: 2,
            roundRobin: 3,
          ),
        ],
        hardwareFolder: '/multisamples/Piano',
      );

      expect(chunkCalls.map((call) => call.path), [
        '/multisamples/Piano/Pno_C3_SW48_V1_RR1.wav',
        '/multisamples/Piano/Pno_take2_D3_SW60_V2_RR3.wav',
      ]);
    },
  );

  test(
    'uploadSysEx splits large sample files into ordered 512-byte chunks',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final bytes = Uint8List.fromList(
        List<int>.generate(1200, (index) => index % 256),
      );
      final source = File('${tempRoot.path}/Piano_C3.wav')
        ..writeAsBytesSync(bytes);
      _stubDirectoryCreates(manager);
      _stubChunkUploads(manager, chunkCalls);
      when(
        () => manager.requestDirectoryListing('/multisamples/Piano'),
      ).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('Piano_C3.wav', bytes.length)]),
      );

      await service.uploadSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        hardwareFolder: '/multisamples/Piano',
      );

      expect(chunkCalls.map((call) => call.position), [0, 512, 1024]);
      expect(chunkCalls.map((call) => call.data.length), [512, 512, 176]);
      expect(chunkCalls.map((call) => call.createAlways), [true, false, false]);
      expect(chunkCalls[0].data, bytes.sublist(0, 512));
      expect(chunkCalls[1].data, bytes.sublist(512, 1024));
      expect(chunkCalls[2].data, bytes.sublist(1024));
      verifyNever(() => manager.requestFileUpload(any(), any()));
    },
  );

  test(
    'uploadSysEx verifies uploaded files by listing names and sizes',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final bytes = Uint8List.fromList(
        List<int>.generate(1025, (index) => (index * 7) % 256),
      );
      final source = File('${tempRoot.path}/Piano_C3.wav')
        ..writeAsBytesSync(bytes);
      _stubDirectoryCreates(manager);
      _stubChunkUploads(manager, chunkCalls);
      when(
        () => manager.requestDirectoryListing('/multisamples/Piano'),
      ).thenAnswer(
        (_) async =>
            DirectoryListing(entries: [_file('Piano_C3.wav', bytes.length)]),
      );

      final result = await service.uploadSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: source.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
        ],
        hardwareFolder: '/multisamples/Piano',
      );

      expect(chunkCalls.map((call) => call.position), [0, 512, 1024]);
      expect(chunkCalls.map((call) => call.createAlways), [true, false, false]);
      verifyNever(() => manager.requestFileUpload(any(), any()));
      verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
      expect(result.correctedFiles, 0);
      expect(result.failedVerificationFiles, 0);
    },
  );

  test('uploadSysEx reports listing check failures', () async {
    final manager = MockDistingMidiManager();
    final chunkCalls = <ChunkUploadCall>[];
    final source = File('${tempRoot.path}/Piano_C3.wav')
      ..writeAsBytesSync([1, 2, 3]);
    _stubDirectoryCreates(manager);
    _stubChunkUploads(manager, chunkCalls);
    when(
      () => manager.requestDirectoryListing('/multisamples/Piano'),
    ).thenAnswer(
      (_) async => DirectoryListing(entries: [_file('Piano_C3.wav', 2)]),
    );

    final result = await service.uploadSysEx(
      manager: manager,
      regions: [
        PolySampleRegion(
          path: source.path,
          fileName: 'Piano_C3.wav',
          displayName: 'Piano_C3.wav',
          rootMidi: 48,
        ),
      ],
      hardwareFolder: '/multisamples/Piano',
    );

    expect(chunkCalls, hasLength(1));
    expect(result.correctedFiles, 0);
    expect(result.failedVerificationFiles, 1);
  });

  test(
    'uploadSysEx uploads remaining files before listing check failures',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final first = File('${tempRoot.path}/Piano_C3.wav')
        ..writeAsBytesSync([1, 2, 3]);
      final second = File('${tempRoot.path}/Piano_D3.wav')
        ..writeAsBytesSync([4, 5, 6]);
      _stubDirectoryCreates(manager);
      _stubChunkUploads(manager, chunkCalls);
      when(
        () => manager.requestDirectoryListing('/multisamples/Piano'),
      ).thenAnswer(
        (_) async => DirectoryListing(entries: [_file('Piano_D3.wav', 3)]),
      );

      final result = await service.uploadSysEx(
        manager: manager,
        regions: [
          PolySampleRegion(
            path: first.path,
            fileName: 'Piano_C3.wav',
            displayName: 'Piano_C3.wav',
            rootMidi: 48,
          ),
          PolySampleRegion(
            path: second.path,
            fileName: 'Piano_D3.wav',
            displayName: 'Piano_D3.wav',
            rootMidi: 50,
          ),
        ],
        hardwareFolder: '/multisamples/Piano',
      );

      expect(
        chunkCalls.map((call) => call.path),
        containsAllInOrder([
          '/multisamples/Piano/Piano_C3.wav',
          '/multisamples/Piano/Piano_D3.wav',
        ]),
      );
      expect(result.filesUploaded, 2);
      expect(result.failedVerificationFiles, 1);
      verifyNever(() => manager.requestFileDownloadChunk(any(), any(), any()));
    },
  , tags: ['regression']);

  test(
    'uploadSysEx failed chunk upload surfaces PolySampleUploadException',
    () async {
      final manager = MockDistingMidiManager();
      final chunkCalls = <ChunkUploadCall>[];
      final source = File('${tempRoot.path}/Piano_C3.wav')
        ..writeAsBytesSync(List<int>.generate(600, (index) => index % 256));
      _stubDirectoryCreates(manager);
      _stubChunkUploads(
        manager,
        chunkCalls,
        statuses: [
          SdCardStatus(success: true, message: 'uploaded'),
          SdCardStatus(success: false, message: 'nope'),
        ],
      );

      await expectLater(
        service.uploadSysEx(
          manager: manager,
          regions: [
            PolySampleRegion(
              path: source.path,
              fileName: 'Piano_C3.wav',
              displayName: 'Piano_C3.wav',
              rootMidi: 48,
            ),
          ],
          hardwareFolder: '/multisamples/Piano',
        ),
        throwsA(
          isA<PolySampleUploadException>().having(
            (error) => error.message,
            'message',
            contains(
              'Hardware upload chunk at 512 for /multisamples/Piano/Piano_C3.wav failed: nope',
            ),
          ),
        ),
      );
      expect(chunkCalls.map((call) => call.position), [0, 512]);
      verifyNever(() => manager.requestFileUpload(any(), any()));
    },
  );
}

DirectoryEntry _dir(String name) =>
    DirectoryEntry(name: '$name/', attributes: 0x10, date: 0, time: 0, size: 0);

DirectoryEntry _file(String name, int size) =>
    DirectoryEntry(name: name, attributes: 0, date: 0, time: 0, size: size);

void _stubDirectoryCreates(MockDistingMidiManager manager) {
  when(
    () => manager.requestDirectoryCreate(any()),
  ).thenAnswer((_) async => SdCardStatus(success: true, message: 'created'));
}

void _stubChunkUploads(
  MockDistingMidiManager manager,
  List<ChunkUploadCall> calls, {
  List<SdCardStatus?>? statuses,
}) {
  var uploadCount = 0;
  when(
    () => manager.requestFileUploadChunk(
      any(),
      any(),
      any(),
      createAlways: any(named: 'createAlways'),
    ),
  ).thenAnswer((invocation) async {
    calls.add(_chunkUploadCallFromInvocation(invocation));
    final status = statuses != null && uploadCount < statuses.length
        ? statuses[uploadCount]
        : SdCardStatus(success: true, message: 'uploaded');
    uploadCount++;
    return status;
  });
}

ChunkUploadCall _chunkUploadCallFromInvocation(Invocation invocation) {
  final data = invocation.positionalArguments[1] as Uint8List;
  return (
    path: invocation.positionalArguments[0] as String,
    data: Uint8List.fromList(data),
    position: invocation.positionalArguments[2] as int,
    createAlways: invocation.namedArguments[#createAlways] as bool? ?? false,
  );
}
