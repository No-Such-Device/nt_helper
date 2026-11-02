import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/core/platform/platform_interaction_service.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/cubit/ntx_8cv_connection_cubit.dart';
import 'package:nt_helper/cubit/ntx_8cv_settings_cubit.dart';
import 'package:nt_helper/db/daos/metadata_dao.dart';
import 'package:nt_helper/db/daos/presets_dao.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/domain/i_disting_midi_manager.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_midi_connection.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_sysex.dart';
import 'package:nt_helper/models/firmware_version.dart';
import 'package:nt_helper/services/mcp_server_service.dart';
import 'package:nt_helper/ui/ntx_8cv/ntx_8cv_screen.dart';
import 'package:nt_helper/ui/synchronized_screen.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

import '../../fixtures/ntx_8cv_sysex_fixtures.dart';

class _MockDistingCubit extends Mock implements DistingCubit {}

class _MockDistingMidiManager extends Mock implements IDistingMidiManager {}

class _MockAppDatabase extends Mock implements AppDatabase {}

class _MockMetadataDao extends Mock implements MetadataDao {}

class _MockPresetsDao extends Mock implements PresetsDao {}

class _MockPlatformInteractionService extends Mock
    implements PlatformInteractionService {}

void main() {
  group('NTX-8CV entry page', () {
    testWidgets('uses a single connection-controls row on wide screens', (
      tester,
    ) async {
      await _setScreenSize(tester, const Size(1280, 900));
      await tester.pumpWidget(const MaterialApp(home: Ntx8cvScreen()));

      expect(
        find.byKey(const Key('ntx8cv-connection-controls-wide')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ntx8cv-connection-controls-narrow')),
        findsNothing,
      );
      expect(find.byKey(const Key('ntx8cv-midi-input')), findsOneWidget);
      expect(find.byKey(const Key('ntx8cv-midi-output')), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'SysEx device ID'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
      expect(find.text('Enable ES-5'), findsOneWidget);
      expect(find.text('Channel Group'), findsOneWidget);
      expect(find.text('USB Settings'), findsOneWidget);
      expect(find.text('disting NT Expander Settings'), findsOneWidget);
      expect(find.textContaining('Connect an NTX-8CV to read'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks connection controls on narrow screens', (tester) async {
      await _setScreenSize(tester, const Size(500, 900));
      await tester.pumpWidget(const MaterialApp(home: Ntx8cvScreen()));

      expect(
        find.byKey(const Key('ntx8cv-connection-controls-narrow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('ntx8cv-connection-controls-wide')),
        findsNothing,
      );
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('USB Settings'), findsOneWidget);
      expect(find.text('disting NT Expander Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'keeps endpoint names singular when the native connection mutates devices',
      (tester) async {
        await _setScreenSize(tester, const Size(1280, 900));
        final midiConnection = _FakeNtx8cvMidiConnection()
          ..devices = [_ntx8cvDevice(name: 'NTX-8CV')];
        final cubit = Ntx8cvConnectionCubit(
          midiConnection: midiConnection,
          store: _MemoryNtx8cvConnectionStore(),
          sessionTimeout: const Duration(milliseconds: 10),
        );
        addTearDown(() async {
          await cubit.close();
          await midiConnection.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(home: Ntx8cvScreen(connectionCubit: cubit)),
        );
        await tester.pumpAndSettle();
        await cubit.connect();
        await tester.pump();

        expect(midiConnection.nativeDeviceName, 'NTX-8CV NTX-8CV');
        for (final fieldKey in const [
          Key('ntx8cv-midi-input'),
          Key('ntx8cv-midi-output'),
        ]) {
          final field = find.byKey(fieldKey);
          expect(
            find.descendant(of: field, matching: find.text('NTX-8CV NTX-8CV')),
            findsNothing,
          );
          expect(
            find.descendant(of: field, matching: find.text('NTX-8CV')),
            findsOneWidget,
          );
        }
      },
    tags: ['regression']);

    testWidgets('uses one aggregate sync light that fades after confirmation', (
      tester,
    ) async {
      await _setScreenSize(tester, const Size(1280, 900));
      final midiConnection = _FakeNtx8cvMidiConnection()
        ..devices = [_ntx8cvDevice(name: 'NTX-8CV')];
      final cubit = Ntx8cvConnectionCubit(
        midiConnection: midiConnection,
        store: _MemoryNtx8cvConnectionStore(),
        sessionTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        await cubit.close();
        await midiConnection.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(home: Ntx8cvScreen(connectionCubit: cubit)),
      );
      await tester.pumpAndSettle();

      final indicator = find.byKey(const Key('ntx8cv-sync-indicator'));
      Color indicatorColor() {
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const Key('ntx8cv-sync-fill')),
                    )
                    .decoration
                as BoxDecoration;
        return decoration.color!;
      }

      final theme = Theme.of(tester.element(indicator));
      expect(find.byKey(const Key('ntx8cv-sync-indicator')), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(indicator).opacity, 1);
      expect(indicatorColor(), theme.appColors.warning.color);

      await cubit.connect();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (indicatorColor() == theme.appColors.info.color) break;
      }

      expect(indicatorColor(), theme.appColors.info.color);
      expect(tester.widget<AnimatedOpacity>(indicator).opacity, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<AnimatedOpacity>(indicator).opacity, 0);
      final outlineDecoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('ntx8cv-sync-outline')),
                  )
                  .decoration
              as BoxDecoration;
      expect(outlineDecoration.shape, BoxShape.circle);
      expect(outlineDecoration.border, isNotNull);
    });

    testWidgets('keeps the full control grid stable when connecting', (
      tester,
    ) async {
      await _setScreenSize(tester, const Size(1280, 900));
      final midiConnection = _FakeNtx8cvMidiConnection()
        ..devices = [_ntx8cvDevice(name: 'NTX-8CV')];
      final cubit = Ntx8cvConnectionCubit(
        midiConnection: midiConnection,
        store: _MemoryNtx8cvConnectionStore(),
        sessionTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        await cubit.close();
        await midiConnection.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(home: Ntx8cvScreen(connectionCubit: cubit)),
      );
      await tester.pumpAndSettle();
      final connectionCard = find.byType(Card).first;
      final usbSettingsCard = find.byKey(const Key('ntx8cv-usb-audio-card'));
      final expanderSettingsCard = find.ancestor(
        of: find.text('disting NT Expander Settings'),
        matching: find.byType(Card),
      );
      final disconnectedHeight = tester.getSize(connectionCard).height;
      final disconnectedUsbSettingsHeight = tester
          .getSize(usbSettingsCard)
          .height;
      final disconnectedExpanderSettingsHeight = tester
          .getSize(expanderSettingsCard)
          .height;
      final connectionStatus = find.byKey(
        const Key('ntx8cv-connection-status'),
      );
      final disconnectedStatusWidth = tester.getSize(connectionStatus).width;
      final connectButton = find.byKey(const Key('ntx8cv-connect-button'));
      final disconnectedButtonWidth = tester.getSize(connectButton).width;
      final disconnectedCardRect = tester.getRect(connectionCard);
      final disconnectedButtonRect = tester.getRect(connectButton);
      expect(
        disconnectedButtonRect.right,
        closeTo(disconnectedCardRect.right - 20, 0.01),
      );
      expect(
        disconnectedButtonRect.bottom,
        closeTo(disconnectedCardRect.bottom - 20, 0.01),
      );
      final disconnectedModeRect = tester.getRect(
        find.byType(DropdownButtonFormField<Ntx8cvExpansionMode>),
      );
      final disconnectedChannelGroupRect = tester.getRect(
        find.byType(DropdownButtonFormField<Ntx8cvChannelGroup>),
      );

      await cubit.connect();
      await tester.pumpAndSettle();

      expect(
        find.text('Device information verified from the selected MIDI input.'),
        findsNothing,
      );
      expect(tester.getSize(connectionStatus).width, disconnectedStatusWidth);
      expect(tester.getSize(connectionCard).height, disconnectedHeight);
      expect(
        tester.getSize(usbSettingsCard).height,
        disconnectedUsbSettingsHeight,
      );
      expect(
        tester.getSize(expanderSettingsCard).height,
        disconnectedExpanderSettingsHeight,
      );
      expect(tester.getSize(connectButton).width, disconnectedButtonWidth);
      expect(
        tester.getRect(
          find.byType(DropdownButtonFormField<Ntx8cvExpansionMode>),
        ),
        disconnectedModeRect,
      );
      expect(
        tester.getRect(
          find.byType(DropdownButtonFormField<Ntx8cvChannelGroup>),
        ),
        disconnectedChannelGroupRect,
      );
    }, tags: ['regression']);

    testWidgets('opens directly from the Expanders overflow item', (
      tester,
    ) async {
      final cubit = _MockDistingCubit();
      final midiManager = _MockDistingMidiManager();
      final platformService = _MockPlatformInteractionService();
      final database = _MockAppDatabase();
      final metadataDao = _MockMetadataDao();
      final presetsDao = _MockPresetsDao();
      final state = DistingStateSynchronized(
        disting: midiManager,
        distingVersion: '1.10.0',
        firmwareVersion: FirmwareVersion('1.10.0'),
        presetName: 'Test Preset',
        algorithms: const [],
        slots: const [],
        unitStrings: const [],
        offline: false,
      );

      when(() => cubit.checkpoints).thenReturn([]);
      when(() => cubit.cpuUsageStream).thenAnswer((_) => const Stream.empty());
      when(() => cubit.database).thenReturn(database);
      when(() => database.metadataDao).thenReturn(metadataDao);
      when(() => database.presetsDao).thenReturn(presetsDao);
      when(() => presetsDao.getTemplates()).thenAnswer((_) async => []);
      when(() => cubit.state).thenReturn(state);
      when(() => cubit.stream).thenAnswer((_) => Stream.value(state));
      when(() => platformService.isMobilePlatform()).thenReturn(false);
      McpServerService.initialize(distingCubit: cubit);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<DistingCubit>.value(
            value: cubit,
            child: SynchronizedScreen(
              distingVersion: '1.10.0',
              firmwareVersion: FirmwareVersion('1.10.0'),
              slots: const [],
              algorithms: const [],
              units: const [],
              presetName: 'Test Preset',
              screenshot: Uint8List(0),
              loading: false,
              platformService: platformService,
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Expanders'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);

      await tester.tap(find.text('Expanders'));
      await tester.pumpAndSettle();
      expect(find.byType(Ntx8cvScreen), findsOneWidget);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('USB Settings'), findsOneWidget);
      expect(find.text('disting NT Expander Settings'), findsOneWidget);
    });
  });
}

Ntx8cvMidiEndpoint _ntx8cvDevice({required String name}) => Ntx8cvMidiEndpoint(
  id: 'ntx8cv',
  name: name,
  hasInput: true,
  hasOutput: true,
);

class _MemoryNtx8cvConnectionStore implements Ntx8cvConnectionStore {
  Ntx8cvSavedConnection saved = const Ntx8cvSavedConnection();

  @override
  Future<Ntx8cvSavedConnection> load() async => saved;

  @override
  Future<void> save(Ntx8cvSavedConnection selection) async {
    saved = selection;
  }
}

class _FakeNtx8cvMidiConnection implements Ntx8cvMidiConnection {
  List<Ntx8cvMidiEndpoint> devices = [];
  final _setupChanges = StreamController<MidiSetupChange>.broadcast();
  final _FakeNtx8cvMidiTransport transport = _FakeNtx8cvMidiTransport();
  String nativeDeviceName = 'NTX-8CV';
  bool _mutatedNativeDeviceName = false;

  @override
  Stream<MidiSetupChange> get setupChanges => _setupChanges.stream;

  @override
  Future<List<Ntx8cvMidiEndpoint>> listDevices() async => List.of(devices);

  @override
  Future<Ntx8cvMidiTransport> open({
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    transport.beforeReceive = () {
      if (_mutatedNativeDeviceName) return;
      _mutatedNativeDeviceName = true;
      nativeDeviceName = '$nativeDeviceName $nativeDeviceName';
    };
    return transport;
  }

  @override
  Future<void> close({
    required Ntx8cvMidiTransport transport,
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {}

  Future<void> dispose() async {
    await transport.close();
    await _setupChanges.close();
  }
}

class _FakeNtx8cvMidiTransport implements Ntx8cvMidiTransport {
  final _received = StreamController<Uint8List>.broadcast(sync: true);
  void Function()? beforeReceive;
  bool _closed = false;

  @override
  Stream<Uint8List> get receivedPackets => _received.stream;

  @override
  Future<void> send(Uint8List packet) async {
    if (_closed) return;
    beforeReceive?.call();
    final response = switch ((packet[6], packet.length > 7 ? packet[7] : -1)) {
      (0x22, _) => Ntx8cvSysExFixtures.deviceInformationResponse,
      (0x31, 0x00) => Ntx8cvSysExFixtures.channelGroupResponse,
      (0x31, 0x01) => Ntx8cvSysExFixtures.es5DisabledResponse,
      (0x31, 0x1B) => Ntx8cvSysExFixtures.modeSettingResponse,
      (0x31, kNtx8cvUsbHostEnabledSettingId) => _settingResponse(
        kNtx8cvUsbHostEnabledSettingId,
        0,
      ),
      (0x31, final settingId)
          when settingId >= kNtx8cvFirstUsbAudioChannelSettingId &&
              settingId <
                  kNtx8cvFirstUsbAudioChannelSettingId +
                      kNtx8cvAudioChannelCount =>
        _settingResponse(settingId, 1),
      (0x31, final settingId)
          when settingId >= kNtx8cvFirstExpanderAudioChannelSettingId &&
              settingId <
                  kNtx8cvFirstExpanderAudioChannelSettingId +
                      kNtx8cvAudioChannelCount =>
        _settingResponse(settingId, 1),
      _ => null,
    };
    if (response != null) _received.add(response);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _received.close();
  }
}

Uint8List _settingResponse(int settingId, int value) => Uint8List.fromList([
  0xF0,
  0x00,
  0x21,
  0x27,
  0x6A,
  0x00,
  0x31,
  settingId,
  value,
  0xF7,
]);

Future<void> _setScreenSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
