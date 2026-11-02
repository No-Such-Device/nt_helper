import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/ntx_8cv_settings_cubit.dart';
import 'package:nt_helper/ui/ntx_8cv/ntx_8cv_screen.dart';

void main() {
  testWidgets(
    'USB Settings toggles host and eight audio channels without layout shifts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool? requestedUsbHost;
      (int, bool)? requestedUsbAudioChannel;

      Widget buildSection({
        required bool isConnected,
        required Ntx8cvSettingsState state,
      }) => MaterialApp(
        home: Scaffold(
          body: Ntx8cvUsbAudioSection(
            isConnected: isConnected,
            state: state,
            onUsbHostChanged: (enabled) async {
              requestedUsbHost = enabled;
            },
            onUsbAudioChannelChanged: (index, enabled) async {
              requestedUsbAudioChannel = (index, enabled);
            },
          ),
        ),
      );

      Map<String, Rect> geometry() => {
        'card': tester.getRect(find.byKey(const Key('ntx8cv-usb-audio-card'))),
        'host': tester.getRect(find.byKey(const Key('ntx8cv-usb-host'))),
        for (var channel = 1; channel <= kNtx8cvAudioChannelCount; channel++)
          'channel$channel': tester.getRect(
            find.byKey(Key('ntx8cv-usb-audio-channel-$channel')),
          ),
      };

      await tester.pumpWidget(
        buildSection(isConnected: true, state: _confirmedUsbAudioState),
      );
      final confirmedGeometry = geometry();
      expect(find.text('USB Settings'), findsOneWidget);
      expect(find.text('USB host'), findsOneWidget);
      expect(find.text('Enable audio channel'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(8));
      for (var channel = 1; channel <= kNtx8cvAudioChannelCount; channel++) {
        expect(find.text('$channel'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('USB audio channel 4'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('ntx8cv-usb-host')))
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('ntx8cv-usb-host')));
      await tester.tap(find.byKey(const Key('ntx8cv-usb-audio-channel-4')));
      expect(requestedUsbHost, isTrue);
      expect(requestedUsbAudioChannel, (3, false));

      await tester.pumpWidget(
        buildSection(
          isConnected: true,
          state: _confirmedUsbAudioState.copyWith(
            usbHost: const Ntx8cvSettingChange(
              confirmedValue: 0,
              attemptedValue: 1,
              isWriting: true,
            ),
            usbAudioChannels: const [
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(
                confirmedValue: 1,
                attemptedValue: 0,
                isWriting: true,
              ),
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(confirmedValue: 1),
              Ntx8cvSettingChange(confirmedValue: 1),
            ],
          ),
        ),
      );
      expect(geometry(), confirmedGeometry);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('ntx8cv-usb-host')))
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const Key('ntx8cv-usb-audio-channel-4')),
            )
            .value,
        isFalse,
      );
      expect(find.textContaining('Saving'), findsNothing);
      expect(find.textContaining('pending'), findsNothing);

      await tester.pumpWidget(
        buildSection(isConnected: false, state: _confirmedUsbAudioState),
      );
      expect(geometry(), confirmedGeometry);
      semantics.dispose();
    },
  tags: ['regression']);

  testWidgets(
    'disting NT Expander Settings toggles its independent audio channel row',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      (int, bool)? requestedExpanderAudioChannel;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Ntx8cvSettingsSection(
              isConnected: true,
              state: const Ntx8cvSettingsState(
                channelGroup: Ntx8cvSettingChange(confirmedValue: 0),
                es5: Ntx8cvSettingChange(confirmedValue: 0),
                mode: Ntx8cvSettingChange(confirmedValue: 0),
                modeCapabilityEvidenced: true,
                expanderAudioChannels: [
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                  Ntx8cvSettingChange(confirmedValue: 1),
                ],
              ),
              onChannelGroupChanged: (_) async {},
              onRetryChannelGroupChange: () async {},
              onEs5Changed: (_) async {},
              onRetryEs5Change: () async {},
              onModeChanged: (_) async {},
              onRetryModeChange: () async {},
              onExpanderAudioChannelChanged: (index, enabled) async {
                requestedExpanderAudioChannel = (index, enabled);
              },
              onReboot: () async {},
            ),
          ),
        ),
      );

      expect(find.text('disting NT Expander Settings'), findsOneWidget);
      expect(find.text('Enable audio channel'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(8));
      expect(
        find.bySemanticsLabel('NT expander audio channel 5'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('ntx8cv-expander-audio-channel-5')),
      );
      expect(requestedExpanderAudioChannel, (4, false));
      semantics.dispose();
    },
  );

  testWidgets(
    'keeps Retry send unavailable while disconnected and enables it after reconnect',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retryCount = 0;
      final pendingState = Ntx8cvSettingsState(
        es5: const Ntx8cvSettingChange(
          confirmedValue: 0,
          attemptedValue: 1,
          message:
              'The ES-5 change was not confirmed by device readback. The '
              'actual device state is uncertain.',
        ),
      );

      Widget buildSection({required bool isConnected}) => MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: isConnected,
            state: pendingState,
            onChannelGroupChanged: (_) async {},
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {
              retryCount += 1;
            },
            onModeChanged: (_) async {},
            onRetryModeChange: () async {},
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      );

      await tester.pumpWidget(buildSection(isConnected: false));

      final retry = find.byKey(const Key('ntx8cv-retry-es5-change'));
      expect(retry, findsOneWidget);
      expect(find.bySemanticsLabel('Retry send'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);
      expect(find.text('ES-5 change not confirmed.'), findsOneWidget);
      expect(find.textContaining('Attempted ES-5 value'), findsNothing);

      await tester.pumpWidget(buildSection(isConnected: true));
      expect(tester.widget<OutlinedButton>(retry).onPressed, isNotNull);

      await tester.tap(retry);
      expect(retryCount, 1);
    },
  );

  testWidgets('keeps confirmed settings copy concise', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: true,
            state: const Ntx8cvSettingsState(
              channelGroup: Ntx8cvSettingChange(confirmedValue: 0),
              es5: Ntx8cvSettingChange(confirmedValue: 1),
              mode: Ntx8cvSettingChange(confirmedValue: 1),
              modeCapabilityEvidenced: true,
            ),
            onChannelGroupChanged: (_) async {},
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {},
            onModeChanged: (_) async {},
            onRetryModeChange: () async {},
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Takes effect after reboot.'), findsNothing);
    final modePicker = tester
        .widget<DropdownButtonFormField<Ntx8cvExpansionMode>>(
          find.byType(DropdownButtonFormField<Ntx8cvExpansionMode>),
        );
    final channelGroupPicker = tester
        .widget<DropdownButtonFormField<Ntx8cvChannelGroup>>(
          find.byType(DropdownButtonFormField<Ntx8cvChannelGroup>),
        );
    expect(modePicker.decoration.border, isA<OutlineInputBorder>());
    expect(channelGroupPicker.decoration.border, isA<OutlineInputBorder>());
    expect(find.textContaining('device-confirmed'), findsNothing);
    expect(find.textContaining('Changes are sent immediately'), findsNothing);
    expect(find.textContaining('does not replace the disting'), findsNothing);
    expect(
      find.textContaining('Connect an NTX-8CV to read and configure'),
      findsNothing,
    );
  });

  testWidgets('keeps every settings row active while ES-5 is writing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: true,
            state: const Ntx8cvSettingsState(
              channelGroup: Ntx8cvSettingChange(confirmedValue: 0),
              es5: Ntx8cvSettingChange(
                confirmedValue: 0,
                attemptedValue: 1,
                isWriting: true,
              ),
              mode: Ntx8cvSettingChange(confirmedValue: 0),
              modeCapabilityEvidenced: true,
            ),
            onChannelGroupChanged: (_) async {},
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {},
            onModeChanged: (_) async {},
            onRetryModeChange: () async {},
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      ),
    );

    final modePicker = tester
        .widget<DropdownButtonFormField<Ntx8cvExpansionMode>>(
          find.byType(DropdownButtonFormField<Ntx8cvExpansionMode>),
        );
    final channelGroupPicker = tester
        .widget<DropdownButtonFormField<Ntx8cvChannelGroup>>(
          find.byType(DropdownButtonFormField<Ntx8cvChannelGroup>),
        );
    final es5Switch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Enable ES-5'),
    );

    expect(es5Switch.value, isTrue);
    expect(es5Switch.onChanged, isNotNull);
    expect(modePicker.onChanged, isNotNull);
    expect(channelGroupPicker.onChanged, isNotNull);
    expect(find.textContaining('pending'), findsNothing);
    expect(find.textContaining('Saving'), findsNothing);
  });

  testWidgets(
    'keeps settings geometry stable across connected, pending, and disconnected states',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const confirmedState = Ntx8cvSettingsState(
        channelGroup: Ntx8cvSettingChange(confirmedValue: 0),
        es5: Ntx8cvSettingChange(confirmedValue: 1),
        mode: Ntx8cvSettingChange(confirmedValue: 1),
        modeCapabilityEvidenced: true,
      );
      const pendingState = Ntx8cvSettingsState(
        channelGroup: Ntx8cvSettingChange(
          confirmedValue: 0,
          attemptedValue: 1,
          message: 'Channel Group change not confirmed.',
        ),
        es5: Ntx8cvSettingChange(
          confirmedValue: 1,
          attemptedValue: 0,
          message: 'ES-5 change not confirmed.',
        ),
        mode: Ntx8cvSettingChange(
          confirmedValue: 1,
          attemptedValue: 2,
          message: 'Expansion mode change not confirmed.',
        ),
        modeCapabilityEvidenced: true,
        rebootMessage:
            'NTX-8CV did not return after reboot. Check its MIDI connection.',
      );
      const activeState = Ntx8cvSettingsState(
        channelGroup: Ntx8cvSettingChange(confirmedValue: 0, isLoading: true),
        es5: Ntx8cvSettingChange(
          confirmedValue: 1,
          attemptedValue: 0,
          isWriting: true,
        ),
        mode: Ntx8cvSettingChange(confirmedValue: 1, isLoading: true),
        modeCapabilityEvidenced: true,
      );

      Widget buildSection({
        required bool isConnected,
        required Ntx8cvSettingsState state,
      }) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Ntx8cvSettingsSection(
              isConnected: isConnected,
              state: state,
              onChannelGroupChanged: (_) async {},
              onRetryChannelGroupChange: () async {},
              onEs5Changed: (_) async {},
              onRetryEs5Change: () async {},
              onModeChanged: (_) async {},
              onRetryModeChange: () async {},
              onExpanderAudioChannelChanged: (_, _) async {},
              onReboot: () async {},
            ),
          ),
        ),
      );

      Map<String, Rect> geometry() => {
        'card': tester.getRect(find.byType(Card)),
        'reboot': tester.getRect(find.byKey(const Key('ntx8cv-reboot'))),
        'es5': tester.getRect(
          find.widgetWithText(SwitchListTile, 'Enable ES-5'),
        ),
        'mode': tester.getRect(
          find.byType(DropdownButtonFormField<Ntx8cvExpansionMode>),
        ),
        'channelGroup': tester.getRect(
          find.byType(DropdownButtonFormField<Ntx8cvChannelGroup>),
        ),
      };
      await tester.pumpWidget(
        buildSection(isConnected: true, state: confirmedState),
      );
      final confirmedGeometry = geometry();
      expect(
        confirmedGeometry['reboot']!.right,
        closeTo(confirmedGeometry['card']!.right - 20, 0.01),
      );
      expect(
        confirmedGeometry['reboot']!.bottom,
        closeTo(confirmedGeometry['card']!.bottom - 20, 0.01),
      );

      await tester.pumpWidget(
        buildSection(
          isConnected: true,
          state: confirmedState.copyWith(isRebooting: true),
        ),
      );
      expect(geometry(), confirmedGeometry);
      expect(find.text('Reboot NTX-8CV'), findsOneWidget);

      await tester.pumpWidget(
        buildSection(
          isConnected: true,
          state: const Ntx8cvSettingsState(isRefreshing: true),
        ),
      );
      expect(geometry(), confirmedGeometry);
      expect(find.textContaining('unavailable'), findsNothing);

      await tester.pumpWidget(
        buildSection(isConnected: true, state: activeState),
      );
      expect(geometry(), confirmedGeometry);
      expect(find.textContaining('Reading'), findsNothing);
      expect(find.textContaining('Saving'), findsNothing);
      expect(find.text('Reboot NTX-8CV'), findsOneWidget);

      await tester.pumpWidget(
        buildSection(isConnected: true, state: pendingState),
      );
      expect(geometry(), confirmedGeometry);
      expect(
        find.text(
          'NTX-8CV did not return after reboot. Check its MIDI connection.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ntx8cv-retry-es5-change')), findsOneWidget);

      await tester.pumpWidget(
        buildSection(isConnected: false, state: confirmedState),
      );
      expect(geometry(), confirmedGeometry);
    },
  tags: ['regression']);

  testWidgets(
    'offers exactly three Mode choices while ES-5 remains available in each',
    (tester) async {
      Widget buildSection(Ntx8cvExpansionMode mode) => MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: true,
            state: Ntx8cvSettingsState(
              es5: const Ntx8cvSettingChange(confirmedValue: 1),
              mode: Ntx8cvSettingChange(confirmedValue: mode.value),
              modeCapabilityEvidenced: true,
            ),
            onChannelGroupChanged: (_) async {},
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {},
            onModeChanged: (_) async {},
            onRetryModeChange: () async {},
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      );

      for (final mode in Ntx8cvExpansionMode.values) {
        await tester.pumpWidget(buildSection(mode));

        final modePickerFinder = find.byType(
          DropdownButtonFormField<Ntx8cvExpansionMode>,
        );
        final modePicker = tester
            .widget<DropdownButtonFormField<Ntx8cvExpansionMode>>(
              modePickerFinder,
            );
        expect(modePicker.onChanged, isNotNull);
        await tester.tap(modePickerFinder);
        await tester.pumpAndSettle();
        for (final label in ['8x8 CV', '1x8 32bit Audio', '2x8 16bit Audio']) {
          expect(find.text(label), findsWidgets);
        }
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        final es5Switch = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Enable ES-5'),
        );
        expect(es5Switch.value, isTrue);
        expect(es5Switch.onChanged, isNotNull);
      }
    },
  );

  testWidgets('offers released Channel Group blocks without long helper copy', (
    tester,
  ) async {
    Ntx8cvChannelGroup? selectedGroup;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: true,
            state: const Ntx8cvSettingsState(
              channelGroup: Ntx8cvSettingChange(confirmedValue: 0),
            ),
            onChannelGroupChanged: (group) async {
              selectedGroup = group;
            },
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {},
            onModeChanged: (_) async {},
            onRetryModeChange: () async {},
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      ),
    );

    final pickerFinder = find.byType(
      DropdownButtonFormField<Ntx8cvChannelGroup>,
    );
    final picker = tester.widget<DropdownButtonFormField<Ntx8cvChannelGroup>>(
      pickerFinder,
    );
    expect(find.text('Channel Group'), findsOneWidget);
    expect(
      find.textContaining('does not replace the disting NT’s granular'),
      findsNothing,
    );
    expect(picker.onChanged, isNotNull);
    await tester.tap(pickerFinder);
    await tester.pumpAndSettle();
    for (final label in [
      '1–8',
      '9–16',
      '17–24',
      '25–32',
      '33–40',
      '41–48',
      '49–56',
      '57–64',
    ]) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('57–64').last);
    await tester.pumpAndSettle();
    expect(selectedGroup, Ntx8cvChannelGroup.channels57To64);
  });

  testWidgets(
    'shows a pending Mode separately from its confirmed value and reboot state',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retryCount = 0;
      Widget buildSection(Ntx8cvSettingsState state) => MaterialApp(
        home: Scaffold(
          body: Ntx8cvSettingsSection(
            isConnected: true,
            state: state,
            onChannelGroupChanged: (_) async {},
            onRetryChannelGroupChange: () async {},
            onEs5Changed: (_) async {},
            onRetryEs5Change: () async {},
            onModeChanged: (_) async {},
            onRetryModeChange: () async {
              retryCount += 1;
            },
            onExpanderAudioChannelChanged: (_, _) async {},
            onReboot: () async {},
          ),
        ),
      );
      final pendingMode = Ntx8cvSettingsState(
        modeCapabilityEvidenced: true,
        mode: const Ntx8cvSettingChange(
          confirmedValue: 2,
          attemptedValue: 0,
          message:
              'The Mode change was not confirmed by device readback. The '
              'actual device state is uncertain.',
        ),
      );

      await tester.pumpWidget(buildSection(pendingMode));

      final retry = find.byKey(const Key('ntx8cv-retry-mode-change'));
      expect(retry, findsOneWidget);
      expect(tester.widget<OutlinedButton>(retry).onPressed, isNotNull);
      expect(find.text('Expansion mode change not confirmed.'), findsOneWidget);
      expect(find.textContaining('Attempted NT expansion mode'), findsNothing);
      await tester.tap(retry);
      expect(retryCount, 1);

      await tester.pumpWidget(
        buildSection(
          const Ntx8cvSettingsState(
            modeCapabilityEvidenced: true,
            modeRebootRequired: true,
            mode: Ntx8cvSettingChange(confirmedValue: 0),
          ),
        ),
      );
      expect(find.text('Reboot to apply.'), findsOneWidget);
    },
  );

  testWidgets(
    'reboots the selected NTX-8CV with one activation and no dialog',
    (tester) async {
      var rebootCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Ntx8cvSettingsSection(
              isConnected: true,
              state: const Ntx8cvSettingsState(
                modeRebootRequired: true,
                modeCapabilityEvidenced: true,
                mode: Ntx8cvSettingChange(confirmedValue: 0),
              ),
              onChannelGroupChanged: (_) async {},
              onRetryChannelGroupChange: () async {},
              onEs5Changed: (_) async {},
              onRetryEs5Change: () async {},
              onModeChanged: (_) async {},
              onRetryModeChange: () async {},
              onExpanderAudioChannelChanged: (_, _) async {},
              onReboot: () async {
                rebootCount += 1;
              },
            ),
          ),
        ),
      );

      final reboot = find.byKey(const Key('ntx8cv-reboot'));
      expect(reboot, findsOneWidget);
      expect(find.text('Reboot NTX-8CV'), findsOneWidget);
      expect(tester.widget<FilledButton>(reboot).onPressed, isNotNull);

      await tester.tap(reboot);
      expect(rebootCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}

const _confirmedUsbAudioState = Ntx8cvSettingsState(
  usbHost: Ntx8cvSettingChange(confirmedValue: 0),
  usbAudioChannels: [
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
    Ntx8cvSettingChange(confirmedValue: 1),
  ],
);
