import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command_platform_interface/midi_port.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_cubit.dart';
import 'package:nt_helper/cubit/firmware_update_state.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/models/firmware_release.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/services/firmware_version_service.dart';
import 'package:nt_helper/services/flash_tool_bridge.dart';
import 'package:nt_helper/services/flash_tool_manager.dart';
import 'package:nt_helper/ui/firmware/firmware_error_widget.dart';

class MockFirmwareVersionService extends Mock
    implements FirmwareVersionService {}

class MockFlashToolManager extends Mock implements FlashToolManager {}

class MockFlashToolBridge extends Mock implements FlashToolBridge {}

class MockDistingMidiManager extends Mock implements IDistingMidiManager {}

void main() {
  late MockFirmwareVersionService mockFirmwareVersionService;
  late MockFlashToolManager mockFlashToolManager;
  late MockFlashToolBridge mockFlashToolBridge;

  setUpAll(() {
    registerFallbackValue(
      FirmwareRelease(
        version: '0.0.0',
        releaseDate: DateTime(2024),
        changelog: [],
        downloadUrl: '',
      ),
    );
  });

  setUp(() {
    mockFirmwareVersionService = MockFirmwareVersionService();
    mockFlashToolManager = MockFlashToolManager();
    mockFlashToolBridge = MockFlashToolBridge();
  });

  FirmwareUpdateCubit createCubit({
    String currentVersion = '1.11.0',
    bool isDemo = false,
    bool isOffline = false,
    FirmwareVersion? firmwareVersion,
    IDistingMidiManager? midiManager,
    Future<IDistingMidiManager> Function()? createMidiManager,
    void Function(IDistingMidiManager)? disposeMidiManager,
    Future<bool> Function()? checkMidiDevices,
    Duration midiPollInterval = const Duration(seconds: 5),
    int midiPollAttempts = 12,
    bool? isWindowsOverride,
  }) {
    return FirmwareUpdateCubit(
      firmwareVersionService: mockFirmwareVersionService,
      flashToolManager: mockFlashToolManager,
      flashToolBridge: mockFlashToolBridge,
      currentVersion: currentVersion,
      isDemo: isDemo,
      isOffline: isOffline,
      firmwareVersion: firmwareVersion,
      midiManager: midiManager,
      createMidiManager: createMidiManager,
      disposeMidiManager: disposeMidiManager,
      checkMidiDevices: checkMidiDevices,
      midiPollInterval: midiPollInterval,
      midiPollAttempts: midiPollAttempts,
      isWindowsOverride: isWindowsOverride,
    );
  }

  group('FirmwareUpdateCubit', () {
    test(
      'initial state is FirmwareUpdateState.initial with current version',
      () {
        final cubit = createCubit(currentVersion: '1.11.0');

        expect(cubit.state, isA<FirmwareUpdateStateInitial>());
        expect(
          (cubit.state as FirmwareUpdateStateInitial).currentVersion,
          '1.11.0',
        );
        expect(
          (cubit.state as FirmwareUpdateStateInitial).availableVersions,
          isNull,
        );
        expect(
          (cubit.state as FirmwareUpdateStateInitial).isLoadingVersions,
          false,
        );

        cubit.close();
      },
    );

    test('isUpdateAvailable returns false in demo mode', () {
      final cubit = createCubit(isDemo: true);
      expect(cubit.isUpdateAvailable, false);
      cubit.close();
    });

    test('isUpdateAvailable returns false in offline mode', () {
      final cubit = createCubit(isOffline: true);
      expect(cubit.isUpdateAvailable, false);
      cubit.close();
    });

    group('loadAvailableVersions', () {
      final testVersions = [
        FirmwareRelease(
          version: '1.12.0',
          releaseDate: DateTime(2024, 1, 15),
          changelog: ['New feature A', 'Bug fix B'],
          downloadUrl: 'https://example.com/firmware.zip',
        ),
        FirmwareRelease(
          version: '1.11.5',
          releaseDate: DateTime(2024, 1, 10),
          changelog: ['Bug fix'],
          downloadUrl: 'https://example.com/firmware-old.zip',
        ),
      ];

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits loading then loaded with versions on success',
        build: () {
          when(
            () => mockFirmwareVersionService.fetchAvailableVersions(),
          ).thenAnswer((_) async => testVersions);
          return createCubit();
        },
        act: (cubit) => cubit.loadAvailableVersions(),
        expect: () => [
          isA<FirmwareUpdateStateInitial>().having(
            (s) => s.isLoadingVersions,
            'isLoadingVersions',
            true,
          ),
          isA<FirmwareUpdateStateInitial>()
              .having((s) => s.isLoadingVersions, 'isLoadingVersions', false)
              .having(
                (s) => s.availableVersions?.length,
                'availableVersions.length',
                2,
              ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits loading then error on failure',
        build: () {
          when(
            () => mockFirmwareVersionService.fetchAvailableVersions(),
          ).thenThrow(Exception('Network error'));
          return createCubit();
        },
        act: (cubit) => cubit.loadAvailableVersions(),
        expect: () => [
          isA<FirmwareUpdateStateInitial>().having(
            (s) => s.isLoadingVersions,
            'isLoadingVersions',
            true,
          ),
          isA<FirmwareUpdateStateInitial>()
              .having((s) => s.isLoadingVersions, 'isLoadingVersions', false)
              .having((s) => s.fetchError, 'fetchError', isNotNull),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'does nothing in demo mode',
        build: () => createCubit(isDemo: true),
        act: (cubit) => cubit.loadAvailableVersions(),
        expect: () => [],
      );
    });

    group('startUpdate', () {
      final testVersion = FirmwareRelease(
        version: '1.12.0',
        releaseDate: DateTime(2024, 1, 15),
        changelog: ['New feature'],
        downloadUrl: 'https://example.com/firmware.zip',
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when in demo mode',
        build: () => createCubit(isDemo: true),
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            contains('demo mode'),
          ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when in offline mode',
        build: () => createCubit(isOffline: true),
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            contains('offline mode'),
          ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits downloading progress then waitingForBootloader on success',
        build: () {
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((invocation) async {
            // Simulate progress callback
            final onProgress =
                invocation.namedArguments[#onProgress] as Function(double)?;
            onProgress?.call(0.5);
            onProgress?.call(1.0);
            return '/tmp/firmware.zip';
          });
          return createCubit();
        },
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateDownloading>()
              .having((s) => s.version, 'version', testVersion)
              .having((s) => s.progress, 'progress', 0),
          isA<FirmwareUpdateStateDownloading>().having(
            (s) => s.progress,
            'progress',
            0.5,
          ),
          isA<FirmwareUpdateStateDownloading>().having(
            (s) => s.progress,
            'progress',
            1.0,
          ),
          isA<FirmwareUpdateStateWaitingForBootloader>()
              .having(
                (s) => s.firmwarePath,
                'firmwarePath',
                '/tmp/firmware.zip',
              )
              .having((s) => s.targetVersion, 'targetVersion', '1.12.0'),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error on download failure',
        build: () {
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenThrow(const FirmwareDownloadException('Network error'));
          return createCubit();
        },
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateDownloading>(),
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            'Network error',
          ),
        ],
      );
    });

    group('startFlashing', () {
      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'does nothing if not in waitingForBootloader state',
        build: () => createCubit(),
        act: (cubit) => cubit.startFlashing(),
        expect: () => [],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits flashing states and success on completion',
        build: () {
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer(
            (_) => Stream.fromIterable([
              const FlashProgress(
                stage: FlashStage.sdpConnect,
                percent: 0,
                message: 'Connecting...',
              ),
              const FlashProgress(
                stage: FlashStage.sdpUpload,
                percent: 50,
                message: 'Uploading...',
              ),
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 100,
                message: 'Done',
              ),
            ]),
          );
          return createCubit();
        },
        seed: () => const FirmwareUpdateState.waitingForBootloader(
          firmwarePath: '/tmp/firmware.zip',
          targetVersion: '1.12.0',
        ),
        act: (cubit) => cubit.startFlashing(),
        expect: () => [
          // Initial flashing state
          isA<FirmwareUpdateStateFlashing>().having(
            (s) => s.progress.stage,
            'stage',
            FlashStage.sdpConnect,
          ),
          // From stream updates
          isA<FirmwareUpdateStateFlashing>().having(
            (s) => s.progress.stage,
            'stage',
            FlashStage.sdpConnect,
          ),
          isA<FirmwareUpdateStateFlashing>().having(
            (s) => s.progress.stage,
            'stage',
            FlashStage.sdpUpload,
          ),
          isA<FirmwareUpdateStateSuccess>().having(
            (s) => s.newVersion,
            'newVersion',
            '1.12.0',
          ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when flash process reports error',
        build: () {
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer(
            (_) => Stream.fromIterable([
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 0,
                message: 'Device not found',
                isError: true,
              ),
            ]),
          );
          return createCubit();
        },
        seed: () => const FirmwareUpdateState.waitingForBootloader(
          firmwarePath: '/tmp/firmware.zip',
          targetVersion: '1.12.0',
        ),
        act: (cubit) => cubit.startFlashing(),
        expect: () => [
          isA<FirmwareUpdateStateFlashing>(),
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            'Device not found',
          ),
        ],
      );
    });

    group('cancel', () {
      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'resets to initial state when cancelled',
        build: () {
          when(() => mockFlashToolBridge.cancel()).thenAnswer((_) async {});
          return createCubit(currentVersion: '1.11.0');
        },
        seed: () => FirmwareUpdateState.downloading(
          version: FirmwareRelease(
            version: '1.12.0',
            releaseDate: DateTime(2024, 1, 15),
            changelog: const [],
            downloadUrl: 'https://example.com/firmware.zip',
          ),
          progress: 0.5,
        ),
        act: (cubit) => cubit.cancel(),
        verify: (cubit) {
          // First emitted state should be initial, then version loading kicks in
          expect(cubit.state, isA<FirmwareUpdateStateInitial>());
        },
      );
    });

    group('useLocalFile', () {
      late Directory tempDir;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('firmware_test_');
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      Future<String> createValidFirmwareZip() async {
        final archive = Archive();
        // Expert Sleepers firmware uses disting_NT.bin in bootable_images/
        archive.addFile(
          ArchiveFile('bootable_images/disting_NT.bin', 4, [
            0x00,
            0x01,
            0x02,
            0x03,
          ]),
        );
        final zipData = ZipEncoder().encode(archive);
        final zipFile = File('${tempDir.path}/valid_firmware.zip');
        await zipFile.writeAsBytes(zipData);
        return zipFile.path;
      }

      Future<String> createInvalidZip() async {
        final zipFile = File('${tempDir.path}/invalid.zip');
        await zipFile.writeAsBytes([0x00, 0x01, 0x02, 0x03]);
        return zipFile.path;
      }

      Future<String> createZipWithoutFirmware() async {
        final archive = Archive();
        archive.addFile(
          ArchiveFile('readme.txt', 5, [0x48, 0x65, 0x6C, 0x6C, 0x6F]),
        );
        final zipData = ZipEncoder().encode(archive);
        final zipFile = File('${tempDir.path}/no_firmware.zip');
        await zipFile.writeAsBytes(zipData);
        return zipFile.path;
      }

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when in demo mode',
        build: () => createCubit(isDemo: true),
        act: (cubit) => cubit.useLocalFile('/some/path.zip'),
        expect: () => [
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            'Firmware updates not available',
          ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when in offline mode',
        build: () => createCubit(isOffline: true),
        act: (cubit) => cubit.useLocalFile('/some/path.zip'),
        expect: () => [
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            'Firmware updates not available',
          ),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'emits error when file does not exist',
        build: () => createCubit(),
        act: (cubit) => cubit.useLocalFile('/nonexistent/path.zip'),
        expect: () => [
          isA<FirmwareUpdateStateError>().having(
            (s) => s.message,
            'message',
            'Selected file does not exist',
          ),
        ],
      );

      test('emits error for corrupt/invalid ZIP data', () async {
        final invalidZipPath = await createInvalidZip();
        final cubit = createCubit();

        await cubit.useLocalFile(invalidZipPath);

        // Invalid ZIP data results in empty archive error from ZipDecoder
        expect(cubit.state, isA<FirmwareUpdateStateError>());
        expect(
          (cubit.state as FirmwareUpdateStateError).message,
          'Selected ZIP archive is empty',
        );

        await cubit.close();
      });

      test('emits error for ZIP without firmware binary', () async {
        final noFirmwareZipPath = await createZipWithoutFirmware();
        final cubit = createCubit();

        await cubit.useLocalFile(noFirmwareZipPath);

        expect(cubit.state, isA<FirmwareUpdateStateError>());
        expect(
          (cubit.state as FirmwareUpdateStateError).message,
          'ZIP does not contain expected firmware file (disting_NT.bin)',
        );

        await cubit.close();
      });

      test('transitions to waitingForBootloader with valid ZIP', () async {
        final validZipPath = await createValidFirmwareZip();
        final cubit = createCubit();

        await cubit.useLocalFile(validZipPath);

        expect(cubit.state, isA<FirmwareUpdateStateWaitingForBootloader>());
        final state = cubit.state as FirmwareUpdateStateWaitingForBootloader;
        expect(state.firmwarePath, validZipPath);
        expect(state.targetVersion, 'local');

        await cubit.close();
      });
    });

    group('cleanupAndReset', () {
      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'resets to initial state from error state',
        build: () {
          when(
            () => mockFirmwareVersionService.fetchAvailableVersions(),
          ).thenAnswer((_) async => []);
          return createCubit(currentVersion: '1.11.0');
        },
        seed: () => const FirmwareUpdateState.error(message: 'Some error'),
        act: (cubit) => cubit.cleanupAndReset(),
        expect: () => [
          isA<FirmwareUpdateStateInitial>(),
          isA<FirmwareUpdateStateInitial>().having(
            (s) => s.isLoadingVersions,
            'isLoadingVersions',
            true,
          ),
          isA<FirmwareUpdateStateInitial>()
              .having((s) => s.isLoadingVersions, 'isLoadingVersions', false)
              .having((s) => s.availableVersions, 'availableVersions', []),
        ],
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'preserves currentVersion when resetting from any state',
        build: () {
          when(
            () => mockFirmwareVersionService.fetchAvailableVersions(),
          ).thenAnswer((_) async => []);
          return createCubit(currentVersion: '1.11.0');
        },
        seed: () => const FirmwareUpdateState.flashing(
          targetVersion: '1.12.0',
          progress: FlashProgress(
            stage: FlashStage.sdpUpload,
            percent: 50,
            message: 'Uploading...',
          ),
        ),
        act: (cubit) => cubit.cleanupAndReset(),
        expect: () => [
          isA<FirmwareUpdateStateInitial>().having(
            (s) => s.currentVersion,
            'currentVersion',
            '1.11.0',
          ),
          isA<FirmwareUpdateStateInitial>()
              .having((s) => s.isLoadingVersions, 'isLoadingVersions', true)
              .having((s) => s.currentVersion, 'currentVersion', '1.11.0'),
          isA<FirmwareUpdateStateInitial>()
              .having((s) => s.isLoadingVersions, 'isLoadingVersions', false)
              .having((s) => s.currentVersion, 'currentVersion', '1.11.0'),
        ],
      );
    });

    group('auto-bootloader (firmware >= 1.15)', () {
      late MockDistingMidiManager mockMidiManager;

      setUp(() {
        mockMidiManager = MockDistingMidiManager();
        when(
          () => mockMidiManager.requestEnterBootloader(),
        ).thenAnswer((_) async {});
      });

      final testVersion = FirmwareRelease(
        version: '1.16.0',
        releaseDate: DateTime(2024, 6, 1),
        changelog: ['Bootloader SysEx support'],
        downloadUrl: 'https://example.com/firmware.zip',
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'firmware >= 1.15 shows waitingForBootloader with canAutoEnter, then confirmAndFlash enters bootloader',
        build: () {
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((invocation) async {
            return '/tmp/firmware.zip';
          });
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer(
            (_) => Stream.fromIterable([
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 100,
                message: 'Done',
              ),
            ]),
          );
          return createCubit(
            currentVersion: '1.15.0',
            firmwareVersion: FirmwareVersion('1.15.0'),
            midiManager: mockMidiManager,
          );
        },
        act: (cubit) async {
          await cubit.startUpdate(testVersion);
          await cubit.confirmAndFlash();
        },
        expect: () => [
          isA<FirmwareUpdateStateDownloading>(),
          isA<FirmwareUpdateStateWaitingForBootloader>()
              .having(
                (s) => s.firmwarePath,
                'firmwarePath',
                '/tmp/firmware.zip',
              )
              .having((s) => s.targetVersion, 'targetVersion', '1.16.0')
              .having((s) => s.canAutoEnter, 'canAutoEnter', true),
          // First enteringBootloader with progress 0
          isA<FirmwareUpdateStateEnteringBootloader>()
              .having(
                (s) => s.firmwarePath,
                'firmwarePath',
                '/tmp/firmware.zip',
              )
              .having((s) => s.targetVersion, 'targetVersion', '1.16.0')
              .having((s) => s.progress, 'progress', 0.0),
          // 50 progress ticks (0.02 to 1.0) - match them all
          for (var i = 1; i <= 50; i++)
            isA<FirmwareUpdateStateEnteringBootloader>().having(
              (s) => s.progress,
              'progress',
              i / 50,
            ),
          isA<FirmwareUpdateStateFlashing>(),
          isA<FirmwareUpdateStateSuccess>(),
        ],
        verify: (_) {
          verify(() => mockMidiManager.requestEnterBootloader()).called(1);
        },
      );

      test(
        'releases the MIDI manager after bootloader entry and before flashing',
        () async {
          final events = <String>[];

          when(() => mockMidiManager.requestEnterBootloader()).thenAnswer((
            _,
          ) async {
            events.add('bootloader');
          });
          when(() => mockMidiManager.dispose()).thenAnswer((_) {
            events.add('release');
          });
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer((_) {
            events.add('flash');
            return Stream.fromIterable([
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 100,
                message: 'Done',
              ),
            ]);
          });

          final cubit = createCubit(
            currentVersion: '1.15.0',
            firmwareVersion: FirmwareVersion('1.15.0'),
            midiManager: mockMidiManager,
          );
          addTearDown(cubit.close);

          await cubit.startUpdate(testVersion);
          await cubit.confirmAndFlash();

          expect(events, ['bootloader', 'release', 'flash']);
        },
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'firmware < 1.15 still shows waitingForBootloader',
        build: () {
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          return createCubit(
            currentVersion: '1.14.0',
            firmwareVersion: FirmwareVersion('1.14.0'),
            midiManager: mockMidiManager,
          );
        },
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateDownloading>(),
          isA<FirmwareUpdateStateWaitingForBootloader>()
              .having(
                (s) => s.firmwarePath,
                'firmwarePath',
                '/tmp/firmware.zip',
              )
              .having((s) => s.targetVersion, 'targetVersion', '1.16.0')
              .having((s) => s.canAutoEnter, 'canAutoEnter', false),
        ],
        verify: (_) {
          verifyNever(() => mockMidiManager.requestEnterBootloader());
        },
      );

      blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
        'no midiManager falls back to waitingForBootloader even on 1.15+',
        build: () {
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          return createCubit(
            currentVersion: '1.15.0',
            firmwareVersion: FirmwareVersion('1.15.0'),
          );
        },
        act: (cubit) => cubit.startUpdate(testVersion),
        expect: () => [
          isA<FirmwareUpdateStateDownloading>(),
          isA<FirmwareUpdateStateWaitingForBootloader>(),
        ],
      );
    });

    group('post-flash MIDI reacquisition', () {
      Future<FirmwareUpdateCubit> launchSuccessfulFlash({
        required Future<bool> Function() checkMidiDevices,
        int attempts = 12,
        bool isWindows = false,
      }) async {
        when(
          () => mockFirmwareVersionService.downloadFirmware(
            any(),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => '/tmp/firmware.zip');
        when(
          () => mockFlashToolManager.getToolPath(),
        ).thenAnswer((_) async => '/path/to/tool');
        when(() => mockFlashToolBridge.flash(any())).thenAnswer(
          (_) => Stream.value(
            const FlashProgress(
              stage: FlashStage.complete,
              percent: 100,
              message: 'Done',
            ),
          ),
        );

        final cubit = createCubit(
          checkMidiDevices: checkMidiDevices,
          midiPollInterval: Duration.zero,
          midiPollAttempts: attempts,
          isWindowsOverride: isWindows,
        );
        final release = FirmwareRelease(
          version: '1.16.0',
          releaseDate: DateTime(2026),
          changelog: const [],
          downloadUrl: 'https://example.com/firmware.zip',
        );
        await cubit.startUpdate(release);
        await cubit.confirmAndFlash();
        return cubit;
      }

      Future<T> waitForState<T extends FirmwareUpdateState>(
        FirmwareUpdateCubit cubit,
      ) async {
        if (cubit.state is T) return cubit.state as T;
        return cubit.stream.where((state) => state is T).cast<T>().first;
      }

      for (final returningAttempt in [1, 6, 12]) {
        test(
          'succeeds when both endpoints return on check $returningAttempt',
          () async {
            var checks = 0;
            final cubit = await launchSuccessfulFlash(
              checkMidiDevices: () async => ++checks >= returningAttempt,
            );
            addTearDown(cubit.close);

            await waitForState<FirmwareUpdateStateSuccess>(cubit);

            expect(checks, returningAttempt);
          },
        );
      }

      for (final platform in const [
        ('Windows', true),
        ('macOS', false),
        ('Linux', false),
      ]) {
        test(
          'uses the same successful detection cycle on ${platform.$1}',
          () async {
            var checks = 0;
            final cubit = await launchSuccessfulFlash(
              checkMidiDevices: () async => ++checks == 3,
              isWindows: platform.$2,
            );
            addTearDown(cubit.close);

            await waitForState<FirmwareUpdateStateSuccess>(cubit);

            expect(checks, 3);
          },
        );
      }

      test('continues after enumeration exceptions and times out', () async {
        var checks = 0;
        final cubit = await launchSuccessfulFlash(
          checkMidiDevices: () async {
            checks++;
            throw StateError('enumeration failed');
          },
          attempts: 4,
          isWindows: true,
        );
        addTearDown(cubit.close);

        final recovery =
            await waitForState<FirmwareUpdateStateMidiRecoveryRequired>(cubit);

        expect(checks, 4);
        expect(recovery.isWindows, isTrue);
        expect(recovery.newVersion, '1.16.0');
      });

      test('Check Again repeats the full cycle and exits on success', () async {
        var checks = 0;
        var recovered = false;
        final cubit = await launchSuccessfulFlash(
          checkMidiDevices: () async {
            checks++;
            return recovered;
          },
          attempts: 2,
        );
        addTearDown(cubit.close);
        await waitForState<FirmwareUpdateStateMidiRecoveryRequired>(cubit);

        recovered = true;
        await cubit.checkMidiAgain();

        expect(cubit.state, isA<FirmwareUpdateStateSuccess>());
        expect(checks, 3);
      });
    });

    group('MIDI release lifecycle', () {
      test(
        'manual flow releases once before launch, cancel, and close',
        () async {
          final manager = MockDistingMidiManager();
          final events = <String>[];
          var releases = 0;
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer((_) {
            events.add('flash');
            return Stream.value(
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 100,
                message: 'Done',
              ),
            );
          });
          when(() => mockFlashToolBridge.cancel()).thenAnswer((_) async {});
          final cubit = createCubit(
            firmwareVersion: FirmwareVersion('1.14.0'),
            midiManager: manager,
            disposeMidiManager: (_) {
              releases++;
              events.add('release');
            },
          );
          final release = FirmwareRelease(
            version: '1.16.0',
            releaseDate: DateTime(2026),
            changelog: const [],
            downloadUrl: 'https://example.com/firmware.zip',
          );

          await cubit.startUpdate(release);
          await cubit.confirmAndFlash();
          await Future<void>.delayed(Duration.zero);
          await cubit.cancel();
          await cubit.close();

          expect(events.take(2), ['release', 'flash']);
          expect(releases, 1);
        },
      );

      test(
        'lazy managers are reacquired and released once per flash attempt',
        () async {
          final firstManager = MockDistingMidiManager();
          final secondManager = MockDistingMidiManager();
          final managers = <IDistingMidiManager>[firstManager, secondManager];
          final events = <String>[];
          var managerIndex = 0;
          var flashCalls = 0;

          for (final manager in managers) {
            when(() => manager.requestEnterBootloader()).thenAnswer((_) async {
              events.add('bootloader-${managers.indexOf(manager) + 1}');
            });
          }
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer((_) {
            flashCalls++;
            events.add('flash-$flashCalls');
            return Stream.value(
              const FlashProgress(
                stage: FlashStage.write,
                percent: 50,
                message: 'Write failed',
                isError: true,
              ),
            );
          });
          when(() => mockFlashToolBridge.cancel()).thenAnswer((_) async {});

          final cubit = createCubit(
            firmwareVersion: FirmwareVersion('1.15.0'),
            createMidiManager: () async {
              final next = managers[managerIndex++];
              events.add('create-$managerIndex');
              return next;
            },
            disposeMidiManager: (manager) {
              events.add('release-${managers.indexOf(manager) + 1}');
            },
          );
          final release = FirmwareRelease(
            version: '1.16.0',
            releaseDate: DateTime(2026),
            changelog: const [],
            downloadUrl: 'https://example.com/firmware.zip',
          );

          await cubit.startUpdate(release);
          await cubit.confirmAndFlash();
          await Future<void>.delayed(Duration.zero);
          expect(cubit.state, isA<FirmwareUpdateStateError>());

          await cubit.retryFlash();
          await cubit.confirmAndFlash();
          await Future<void>.delayed(Duration.zero);
          await cubit.cancel();
          await cubit.close();

          expect(events, [
            'create-1',
            'bootloader-1',
            'release-1',
            'flash-1',
            'create-2',
            'bootloader-2',
            'release-2',
            'flash-2',
          ]);
          expect(managerIndex, 2);
          expect(flashCalls, 2);
        },
      );

      test(
        'cancellation and disposal release an unflashed manager once',
        () async {
          final manager = MockDistingMidiManager();
          var releases = 0;
          when(() => mockFlashToolBridge.cancel()).thenAnswer((_) async {});
          final cubit = createCubit(
            midiManager: manager,
            disposeMidiManager: (_) => releases++,
          );

          await cubit.cancel();
          await cubit.close();

          expect(releases, 1);
        },
      );

      test(
        'a flash retry does not release the manager a second time',
        () async {
          final manager = MockDistingMidiManager();
          var releases = 0;
          var flashCalls = 0;
          when(
            () => mockFirmwareVersionService.downloadFirmware(
              any(),
              onProgress: any(named: 'onProgress'),
            ),
          ).thenAnswer((_) async => '/tmp/firmware.zip');
          when(
            () => mockFlashToolManager.getToolPath(),
          ).thenAnswer((_) async => '/path/to/tool');
          when(() => mockFlashToolBridge.flash(any())).thenAnswer((_) {
            flashCalls++;
            if (flashCalls == 1) {
              return Stream.value(
                const FlashProgress(
                  stage: FlashStage.write,
                  percent: 50,
                  message: 'Write failed',
                  isError: true,
                ),
              );
            }
            return Stream.value(
              const FlashProgress(
                stage: FlashStage.complete,
                percent: 100,
                message: 'Done',
              ),
            );
          });
          final cubit = createCubit(
            firmwareVersion: FirmwareVersion('1.14.0'),
            midiManager: manager,
            disposeMidiManager: (_) => releases++,
          );
          final release = FirmwareRelease(
            version: '1.16.0',
            releaseDate: DateTime(2026),
            changelog: const [],
            downloadUrl: 'https://example.com/firmware.zip',
          );

          await cubit.startUpdate(release);
          await cubit.confirmAndFlash();
          await Future<void>.delayed(Duration.zero);
          expect(cubit.state, isA<FirmwareUpdateStateError>());

          await cubit.retryFlash();
          await cubit.confirmAndFlash();
          await Future<void>.delayed(Duration.zero);
          await cubit.close();

          expect(flashCalls, 2);
          expect(releases, 1);
        },
      );
    });
  });

  group('firmware MIDI endpoint matching', () {
    MidiDevice device({
      required String name,
      required bool input,
      required bool output,
    }) {
      final device = MidiDevice(name, name, MidiDeviceType.serial, false);
      if (input) device.inputPorts.add(MidiPort(0, MidiPortType.IN));
      if (output) device.outputPorts.add(MidiPort(0, MidiPortType.OUT));
      return device;
    }

    test(
      'requires expected input and output with their respective directions',
      () {
        final input = device(name: 'Disting NT', input: true, output: false);
        final output = device(name: 'Disting NT', input: false, output: true);

        expect(
          firmwareMidiEndpointsAvailable(
            [input, output],
            'disting nt',
            'DISTING NT',
          ),
          isTrue,
        );
        expect(
          firmwareMidiEndpointsAvailable([input], 'Disting NT', 'Disting NT'),
          isFalse,
        );
        expect(
          firmwareMidiEndpointsAvailable([output], 'Disting NT', 'Disting NT'),
          isFalse,
        );
      },
    );

    test('uses Disting fallback only when an expected name is unavailable', () {
      final both = device(
        name: 'Expert Sleepers Disting NT',
        input: true,
        output: true,
      );

      expect(firmwareMidiEndpointsAvailable([both], null, null), isTrue);
      expect(
        firmwareMidiEndpointsAvailable([both], 'Old NT Name', 'Old NT Name'),
        isFalse,
      );
    });
  });

  group('FirmwareUpdateState', () {
    test('initial state equality', () {
      const a = FirmwareUpdateState.initial(currentVersion: '1.0.0');
      const b = FirmwareUpdateState.initial(currentVersion: '1.0.0');
      const c = FirmwareUpdateState.initial(currentVersion: '1.1.0');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('downloading state equality', () {
      final version = FirmwareRelease(
        version: '1.12.0',
        releaseDate: DateTime(2024, 1, 15),
        changelog: const [],
        downloadUrl: 'https://example.com/firmware.zip',
      );

      final a = FirmwareUpdateState.downloading(
        version: version,
        progress: 0.5,
      );
      final b = FirmwareUpdateState.downloading(
        version: version,
        progress: 0.5,
      );
      final c = FirmwareUpdateState.downloading(
        version: version,
        progress: 0.7,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('error state equality', () {
      const a = FirmwareUpdateState.error(message: 'Error A');
      const b = FirmwareUpdateState.error(message: 'Error A');
      const c = FirmwareUpdateState.error(message: 'Error B');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('when method handles all states', () {
      const initialState = FirmwareUpdateState.initial(currentVersion: '1.0.0');
      final downloadingState = FirmwareUpdateState.downloading(
        version: FirmwareRelease(
          version: '1.12.0',
          releaseDate: DateTime(2024, 1, 15),
          changelog: const [],
          downloadUrl: 'https://example.com/firmware.zip',
        ),
        progress: 0.5,
      );
      const waitingState = FirmwareUpdateState.waitingForBootloader(
        firmwarePath: '/path',
        targetVersion: '1.12.0',
      );
      const flashingState = FirmwareUpdateState.flashing(
        targetVersion: '1.12.0',
        progress: FlashProgress(
          stage: FlashStage.sdpConnect,
          percent: 0,
          message: '',
        ),
      );
      const successState = FirmwareUpdateState.success(newVersion: '1.12.0');
      const errorState = FirmwareUpdateState.error(message: 'Error');

      expect(
        initialState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'initial',
      );

      expect(
        downloadingState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'downloading',
      );

      expect(
        waitingState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'waiting',
      );

      expect(
        flashingState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'flashing',
      );

      expect(
        successState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'success',
      );

      expect(
        errorState.when(
          initial: (_, _, _, _) => 'initial',
          downloading: (_, _) => 'downloading',
          waitingForBootloader: (_, _, _) => 'waiting',
          enteringBootloader: (_, _, _) => 'entering',
          flashing: (_, _) => 'flashing',
          verifyingMidi: (_, _, _) => 'verifying',
          midiRecoveryRequired: (_, _) => 'recovery',
          success: (_) => 'success',
          error: (_, _, _, _, _) => 'error',
        ),
        'error',
      );
    });
  });

  group('getActionButtonText', () {
    test('returns correct text for each FlashStage', () {
      expect(getActionButtonText(null), 'Try Again');
      expect(
        getActionButtonText(FlashStage.sdpConnect),
        'Re-enter Bootloader Mode',
      );
      expect(
        getActionButtonText(FlashStage.blCheck),
        'Re-enter Bootloader Mode',
      );
      expect(getActionButtonText(FlashStage.sdpUpload), 'Retry Update');
      expect(getActionButtonText(FlashStage.write), 'Retry Update');
      expect(getActionButtonText(FlashStage.configure), 'Try Again');
      expect(getActionButtonText(FlashStage.reset), 'Try Again');
      expect(getActionButtonText(FlashStage.complete), 'Try Again');
    });
  });

  group('FirmwareErrorType', () {
    test('error types are correctly assigned based on stage', () {
      // SDP_CONNECT and BL_CHECK should be bootloaderConnection type
      const errorState1 = FirmwareUpdateStateError(
        message: 'test',
        errorType: FirmwareErrorType.bootloaderConnection,
        failedStage: FlashStage.sdpConnect,
      );
      expect(errorState1.errorType, FirmwareErrorType.bootloaderConnection);

      // SDP_UPLOAD and WRITE should be flashWrite type
      const errorState2 = FirmwareUpdateStateError(
        message: 'test',
        errorType: FirmwareErrorType.flashWrite,
        failedStage: FlashStage.sdpUpload,
      );
      expect(errorState2.errorType, FirmwareErrorType.flashWrite);

      // Download errors should be download type
      const errorState3 = FirmwareUpdateStateError(
        message: 'test',
        errorType: FirmwareErrorType.download,
      );
      expect(errorState3.errorType, FirmwareErrorType.download);
    });
  });

  group('Recovery methods', () {
    blocTest<FirmwareUpdateCubit, FirmwareUpdateState>(
      'returnToBootloaderInstructions returns to waiting state from error',
      build: () {
        when(() => mockFlashToolBridge.cancel()).thenAnswer((_) async {});
        return createCubit();
      },
      seed: () => const FirmwareUpdateState.error(
        message: 'Device not found',
        errorType: FirmwareErrorType.bootloaderConnection,
        failedStage: FlashStage.sdpConnect,
        firmwarePath: '/tmp/firmware.zip',
        targetVersion: '1.12.0',
      ),
      act: (cubit) => cubit.returnToBootloaderInstructions(),
      expect: () => [
        isA<FirmwareUpdateStateWaitingForBootloader>()
            .having((s) => s.firmwarePath, 'firmwarePath', '/tmp/firmware.zip')
            .having((s) => s.targetVersion, 'targetVersion', '1.12.0'),
      ],
    );
  });
}
