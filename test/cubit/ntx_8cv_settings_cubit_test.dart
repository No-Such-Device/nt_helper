import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/cubit/ntx_8cv_connection_cubit.dart';
import 'package:nt_helper/cubit/ntx_8cv_settings_cubit.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_midi_connection.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_sysex.dart';

import '../fixtures/ntx_8cv_sysex_fixtures.dart';

void main() {
  group('Ntx8cvSettingsCubit', () {
    late _FakeNtx8cvMidiConnection midiConnection;
    late Ntx8cvConnectionCubit connectionCubit;
    late Ntx8cvSettingsCubit settingsCubit;

    setUp(() {
      midiConnection = _FakeNtx8cvMidiConnection();
      midiConnection.devices = [
        _midiDevice(id: 'ntx8cv', name: 'NTX-8CV', input: true, output: true),
      ];
      connectionCubit = Ntx8cvConnectionCubit(
        midiConnection: midiConnection,
        store: _MemoryNtx8cvConnectionStore(),
        sessionTimeout: const Duration(milliseconds: 10),
        rebootReconnectDelay: Duration.zero,
      );
      settingsCubit = Ntx8cvSettingsCubit(connectionCubit: connectionCubit);
    });

    tearDown(() async {
      await settingsCubit.close();
      await connectionCubit.close();
      await midiConnection.dispose();
    });

    test(
      'reads Channel Group, ES-5, and probes Mode after connecting',
      () async {
        midiConnection.transport.onSend = (packet) {
          _respondWithSettings(midiConnection.transport, packet);
        };
        await connectionCubit.initialize();
        final refreshStates = <Ntx8cvSettingsState>[];
        final refreshSubscription = settingsCubit.stream.listen(
          refreshStates.add,
        );
        addTearDown(refreshSubscription.cancel);
        await connectionCubit.connect();
        await _flushEvents();

        expect(
          refreshStates.where((state) => state.isRefreshing),
          hasLength(1),
        );
        expect(refreshStates.last.isRefreshing, isFalse);
        expect(settingsCubit.state.confirmedEs5Enabled, isFalse);
        expect(
          settingsCubit.state.confirmedMode,
          Ntx8cvExpansionMode.audio2x8_16bit,
        );
        expect(settingsCubit.state.modeCapabilityEvidenced, isTrue);
        expect(midiConnection.transport.sent, hasLength(21));
        expect(
          midiConnection.transport.sent[0],
          orderedEquals(Ntx8cvSysExFixtures.deviceInformationRequest),
        );
        expect(
          midiConnection.transport.sent[1],
          orderedEquals(Ntx8cvSysExFixtures.readEs5EnabledSetting),
        );
        expect(
          midiConnection.transport.sent[2],
          orderedEquals(Ntx8cvSysExFixtures.readModeSetting),
        );
        expect(
          midiConnection.transport.sent[3],
          orderedEquals(Ntx8cvSysExFixtures.readChannelGroupSetting),
        );
        expect(
          midiConnection.transport.sent[4],
          orderedEquals(_readSetting(kNtx8cvUsbHostEnabledSettingId)),
        );
        for (var index = 0; index < kNtx8cvAudioChannelCount; index++) {
          expect(
            midiConnection.transport.sent[5 + index],
            orderedEquals(
              _readSetting(kNtx8cvFirstUsbAudioChannelSettingId + index),
            ),
          );
          expect(
            midiConnection.transport.sent[13 + index],
            orderedEquals(
              _readSetting(kNtx8cvFirstExpanderAudioChannelSettingId + index),
            ),
          );
        }
        expect(
          settingsCubit.state.confirmedChannelGroup,
          Ntx8cvChannelGroup.channels1To8,
        );
        expect(settingsCubit.state.confirmedUsbHostEnabled, isFalse);
        expect([
          for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
            settingsCubit.state.confirmedUsbAudioChannelEnabled(index),
        ], everyElement(isTrue));
        expect([
          for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
            settingsCubit.state.confirmedExpanderAudioChannelEnabled(index),
        ], everyElement(isTrue));
      },
    );

    test(
      'changes USB host and both audio channel routes with confirmed readback',
      () async {
        var usbHostValue = 0;
        final usbAudioChannelValues = List<int>.filled(
          kNtx8cvAudioChannelCount,
          1,
        );
        final expanderAudioChannelValues = List<int>.filled(
          kNtx8cvAudioChannelCount,
          1,
        );
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x32 &&
              packet[7] == kNtx8cvUsbHostEnabledSettingId) {
            usbHostValue = packet[8];
          }
          if (packet[6] == 0x32 &&
              packet[7] >= kNtx8cvFirstUsbAudioChannelSettingId &&
              packet[7] <
                  kNtx8cvFirstUsbAudioChannelSettingId +
                      kNtx8cvAudioChannelCount) {
            usbAudioChannelValues[packet[7] -
                    kNtx8cvFirstUsbAudioChannelSettingId] =
                packet[8];
          }
          if (packet[6] == 0x32 &&
              packet[7] >= kNtx8cvFirstExpanderAudioChannelSettingId &&
              packet[7] <
                  kNtx8cvFirstExpanderAudioChannelSettingId +
                      kNtx8cvAudioChannelCount) {
            expanderAudioChannelValues[packet[7] -
                    kNtx8cvFirstExpanderAudioChannelSettingId] =
                packet[8];
          }
          _respondWithSettings(
            midiConnection.transport,
            packet,
            usbHostValue: usbHostValue,
            usbAudioChannelValues: usbAudioChannelValues,
            expanderAudioChannelValues: expanderAudioChannelValues,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setUsbHostEnabled(true);
        await settingsCubit.setUsbAudioChannelEnabled(3, false);
        await settingsCubit.setExpanderAudioChannelEnabled(4, false);

        expect(settingsCubit.state.confirmedUsbHostEnabled, isTrue);
        expect(settingsCubit.state.confirmedUsbAudioChannelEnabled(3), isFalse);
        expect(
          settingsCubit.state.confirmedExpanderAudioChannelEnabled(4),
          isFalse,
        );
        final writes = midiConnection.transport.sent.sublist(21);
        expect(writes, hasLength(6));
        expect(
          writes[0],
          orderedEquals(_writeSetting(kNtx8cvUsbHostEnabledSettingId, 1)),
        );
        expect(
          writes[1],
          orderedEquals(_readSetting(kNtx8cvUsbHostEnabledSettingId)),
        );
        expect(
          writes[2],
          orderedEquals(
            _writeSetting(kNtx8cvFirstUsbAudioChannelSettingId + 3, 0),
          ),
        );
        expect(
          writes[3],
          orderedEquals(_readSetting(kNtx8cvFirstUsbAudioChannelSettingId + 3)),
        );
        expect(
          writes[4],
          orderedEquals(
            _writeSetting(kNtx8cvFirstExpanderAudioChannelSettingId + 4, 0),
          ),
        );
        expect(
          writes[5],
          orderedEquals(
            _readSetting(kNtx8cvFirstExpanderAudioChannelSettingId + 4),
          ),
        );
      },
    );

    test(
      'a repeated audio-channel toggle retries uncertain readback',
      () async {
        var usbAudioChannel1Value = 1;
        var acceptWrite = false;
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x32 &&
              packet[7] == kNtx8cvFirstUsbAudioChannelSettingId &&
              acceptWrite) {
            usbAudioChannel1Value = packet[8];
          }
          final audioValues = <int>[usbAudioChannel1Value, 1, 1, 1, 1, 1, 1, 1];
          _respondWithSettings(
            midiConnection.transport,
            packet,
            usbAudioChannelValues: audioValues,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setUsbAudioChannelEnabled(0, false);
        expect(settingsCubit.state.hasPendingUsbAudioChannelChange(0), isTrue);
        expect(settingsCubit.state.confirmedUsbAudioChannelEnabled(0), isTrue);

        acceptWrite = true;
        await settingsCubit.setUsbAudioChannelEnabled(0, false);

        expect(settingsCubit.state.hasPendingUsbAudioChannelChange(0), isFalse);
        expect(settingsCubit.state.confirmedUsbAudioChannelEnabled(0), isFalse);
      },
    );

    test(
      'reboots only the selected NTX-8CV then revalidates and refreshes settings',
      () async {
        var channelGroupValue = Ntx8cvChannelGroup.channels1To8.value;
        var es5Value = 0;
        var modeValue = Ntx8cvExpansionMode.cv8x8.value;
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x32 && packet[7] == 0x1B) {
            modeValue = packet[8];
          }
          _respondWithSettings(
            midiConnection.transport,
            packet,
            channelGroupValue: channelGroupValue,
            es5Value: es5Value,
            modeValue: modeValue,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setExpansionMode(
          Ntx8cvExpansionMode.audio1x8_32bit,
        );
        expect(settingsCubit.state.modeRebootRequired, isTrue);

        channelGroupValue = Ntx8cvChannelGroup.channels57To64.value;
        es5Value = 1;
        final sendsBeforeReboot = midiConnection.transport.sent.length;

        await settingsCubit.reboot();

        expect(midiConnection.openCount, 2);
        expect(midiConnection.closeCount, 1);
        expect(
          midiConnection.transport.sent[sendsBeforeReboot],
          orderedEquals(Ntx8cvSysExFixtures.reboot),
        );
        expect(
          midiConnection.transport.sent[sendsBeforeReboot + 1],
          orderedEquals(Ntx8cvSysExFixtures.deviceInformationRequest),
        );
        expect(
          midiConnection.transport.sent[sendsBeforeReboot + 2],
          orderedEquals(Ntx8cvSysExFixtures.readEs5EnabledSetting),
        );
        expect(
          midiConnection.transport.sent[sendsBeforeReboot + 3],
          orderedEquals(Ntx8cvSysExFixtures.readModeSetting),
        );
        expect(
          midiConnection.transport.sent[sendsBeforeReboot + 4],
          orderedEquals(Ntx8cvSysExFixtures.readChannelGroupSetting),
        );
        expect(settingsCubit.state.confirmedEs5Enabled, isTrue);
        expect(
          settingsCubit.state.confirmedMode,
          Ntx8cvExpansionMode.audio1x8_32bit,
        );
        expect(
          settingsCubit.state.confirmedChannelGroup,
          Ntx8cvChannelGroup.channels57To64,
        );
        expect(settingsCubit.state.modeCapabilityEvidenced, isTrue);
        expect(settingsCubit.state.modeRebootRequired, isFalse);
        expect(settingsCubit.state.isRebooting, isFalse);
      },
    );

    test(
      'clears a failed reboot message after a later manual reconnect',
      () async {
        var failReboot = true;
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x7F && failReboot) {
            throw StateError('reboot send failed');
          }
          _respondWithSettings(midiConnection.transport, packet);
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.reboot();

        expect(settingsCubit.state.rebootMessage, isNotNull);
        failReboot = false;
        await connectionCubit.refreshEndpoints();
        await connectionCubit.connect();
        await _flushEvents();

        expect(connectionCubit.state.isConnected, isTrue);
        expect(settingsCubit.state.rebootMessage, isNull);
      },
    );

    test('changes ES-5 only after matching same-setting readback', () async {
      midiConnection.transport.onSend = (packet) {
        final hasWrittenEs5 = midiConnection.transport.sent.any(
          (sent) => sent[6] == 0x32 && sent[7] == 0x01,
        );
        _respondWithSettings(
          midiConnection.transport,
          packet,
          es5Value: hasWrittenEs5 ? 1 : 0,
        );
      };
      await connectionCubit.initialize();
      await connectionCubit.connect();
      await _flushEvents();

      await settingsCubit.setEs5Enabled(true);

      expect(settingsCubit.state.confirmedEs5Enabled, isTrue);
      expect(settingsCubit.state.hasPendingEs5Change, isFalse);
      expect(midiConnection.transport.sent, hasLength(23));
      expect(
        midiConnection.transport.sent[21],
        orderedEquals(Ntx8cvSysExFixtures.writeEs5EnabledSetting),
      );
      expect(
        midiConnection.transport.sent[22],
        orderedEquals(Ntx8cvSysExFixtures.readEs5EnabledSetting),
      );
    });

    test('serializes writes without blocking unrelated settings', () async {
      var es5WriteStarted = false;
      var modeValue = Ntx8cvExpansionMode.cv8x8.value;
      midiConnection.transport.onSend = (packet) {
        if (packet[6] == 0x32 && packet[7] == 0x01) {
          es5WriteStarted = true;
          return;
        }
        if (packet[6] == 0x31 && packet[7] == 0x01 && es5WriteStarted) {
          return;
        }
        if (packet[6] == 0x32 && packet[7] == 0x1B) {
          modeValue = packet[8];
        }
        _respondWithSettings(
          midiConnection.transport,
          packet,
          modeValue: modeValue,
        );
      };
      await connectionCubit.initialize();
      await connectionCubit.connect();
      await _flushEvents();

      final es5Write = settingsCubit.setEs5Enabled(true);
      await _flushEvents();
      expect(settingsCubit.state.isWritingEs5, isTrue);

      final modeWrite = settingsCubit.setExpansionMode(
        Ntx8cvExpansionMode.audio1x8_32bit,
      );
      await _flushEvents();
      expect(
        midiConnection.transport.sent.where(
          (packet) => packet[6] == 0x32 && packet[7] == 0x1B,
        ),
        isEmpty,
      );

      midiConnection.transport.receive(_settingResponse(0x01, 1));
      await es5Write;
      await modeWrite;

      expect(settingsCubit.state.confirmedEs5Enabled, isTrue);
      expect(
        settingsCubit.state.confirmedMode,
        Ntx8cvExpansionMode.audio1x8_32bit,
      );
      expect(
        midiConnection.transport.sent
            .where((packet) => packet[6] == 0x32)
            .map((packet) => packet[7]),
        orderedEquals([0x01, 0x1B]),
      );
    });

    test(
      'confirms a Channel Group only after matching readback and manual retry',
      () async {
        var reportedChannelGroup = Ntx8cvChannelGroup.channels1To8.value;
        midiConnection.transport.onSend = (packet) {
          _respondWithSettings(
            midiConnection.transport,
            packet,
            channelGroupValue: reportedChannelGroup,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setChannelGroup(Ntx8cvChannelGroup.channels57To64);

        expect(
          settingsCubit.state.confirmedChannelGroup,
          Ntx8cvChannelGroup.channels1To8,
        );
        expect(
          settingsCubit.state.attemptedChannelGroup,
          Ntx8cvChannelGroup.channels57To64,
        );
        expect(settingsCubit.state.hasPendingChannelGroupChange, isTrue);
        expect(settingsCubit.state.channelGroupMessage, contains('uncertain'));
        expect(
          midiConnection.transport.sent[21],
          orderedEquals(Ntx8cvSysExFixtures.writeChannelGroupSetting),
        );
        expect(
          midiConnection.transport.sent[22],
          orderedEquals(Ntx8cvSysExFixtures.readChannelGroupSetting),
        );

        reportedChannelGroup = Ntx8cvChannelGroup.channels57To64.value;
        await settingsCubit.retryChannelGroupChange();

        expect(
          settingsCubit.state.confirmedChannelGroup,
          Ntx8cvChannelGroup.channels57To64,
        );
        expect(settingsCubit.state.hasPendingChannelGroupChange, isFalse);
        expect(settingsCubit.state.modeRebootRequired, isFalse);
      },
    );

    test(
      'retains a mismatched ES-5 change across reconnect and retries only explicitly',
      () async {
        var returnEnabledValue = false;
        midiConnection.transport.onSend = (packet) {
          _respondWithSettings(
            midiConnection.transport,
            packet,
            es5Value: returnEnabledValue ? 1 : 0,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setEs5Enabled(true);

        expect(settingsCubit.state.confirmedEs5Enabled, isFalse);
        expect(settingsCubit.state.attemptedEs5Enabled, isTrue);
        expect(settingsCubit.state.hasPendingEs5Change, isTrue);
        expect(settingsCubit.state.es5Message, contains('not confirmed'));
        expect(settingsCubit.state.es5Message, contains('uncertain'));

        await connectionCubit.disconnect();
        await connectionCubit.setDeviceIdText('2');
        expect(settingsCubit.state.confirmedEs5Enabled, isNull);
        expect(settingsCubit.state.attemptedEs5Enabled, isTrue);
        expect(settingsCubit.state.es5Message, contains('target changed'));

        final sendsBeforeReconnect = midiConnection.transport.sent.length;
        await connectionCubit.connect();
        await _flushEvents();

        expect(settingsCubit.state.hasPendingEs5Change, isTrue);
        // Reconnect validates identity and refreshes every non-pending
        // setting, but never resends ES-5.
        expect(
          midiConnection.transport.sent,
          hasLength(sendsBeforeReconnect + 20),
        );
        expect(midiConnection.transport.sent[sendsBeforeReconnect][5], 2);
        expect(midiConnection.transport.sent[sendsBeforeReconnect][6], 0x22);
        expect(midiConnection.transport.sent[sendsBeforeReconnect + 1][5], 2);
        expect(
          midiConnection.transport.sent[sendsBeforeReconnect + 1][6],
          0x31,
        );
        expect(
          midiConnection.transport.sent[sendsBeforeReconnect + 1][7],
          0x1B,
        );
        expect(midiConnection.transport.sent.last[5], 2);
        expect(midiConnection.transport.sent.last[6], 0x31);
        expect(midiConnection.transport.sent.last[7], 0x23);

        returnEnabledValue = true;
        await settingsCubit.retryEs5Change();

        expect(settingsCubit.state.confirmedEs5Enabled, isTrue);
        expect(settingsCubit.state.hasPendingEs5Change, isFalse);
        expect(settingsCubit.state.modeRebootRequired, isFalse);
        expect(
          midiConnection.transport.sent,
          hasLength(sendsBeforeReconnect + 22),
        );
        expect(midiConnection.transport.sent[sendsBeforeReconnect + 20][5], 2);
        expect(
          midiConnection.transport.sent[sendsBeforeReconnect + 20][6],
          0x32,
        );
        expect(midiConnection.transport.sent[sendsBeforeReconnect + 21][5], 2);
        expect(
          midiConnection.transport.sent[sendsBeforeReconnect + 21][6],
          0x31,
        );
      },
    );

    test(
      'keeps a timed-out ES-5 write pending and labels it uncertain',
      () async {
        var hasStartedWrite = false;
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x32 && packet[7] == 0x01) {
            hasStartedWrite = true;
            return;
          }
          if (packet[6] == 0x31 && packet[7] == 0x01 && hasStartedWrite) {
            return;
          }
          _respondWithSettings(midiConnection.transport, packet);
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setEs5Enabled(true);

        expect(settingsCubit.state.confirmedEs5Enabled, isFalse);
        expect(settingsCubit.state.attemptedEs5Enabled, isTrue);
        expect(settingsCubit.state.isWritingEs5, isFalse);
        expect(settingsCubit.state.es5Message, contains('not confirmed'));
        expect(settingsCubit.state.es5Message, contains('uncertain'));
      },
    );

    test(
      'keeps an interrupted ES-5 write pending and labels it uncertain',
      () async {
        var hasStartedWrite = false;
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x32 && packet[7] == 0x01) {
            hasStartedWrite = true;
            return;
          }
          if (packet[6] == 0x31 && packet[7] == 0x01 && hasStartedWrite) {
            return;
          }
          _respondWithSettings(midiConnection.transport, packet);
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        final write = settingsCubit.setEs5Enabled(true);
        await _flushEvents();
        expect(settingsCubit.state.isWritingEs5, isTrue);
        expect(settingsCubit.state.attemptedEs5Enabled, isTrue);

        await connectionCubit.disconnect();
        await write;

        expect(settingsCubit.state.confirmedEs5Enabled, isFalse);
        expect(settingsCubit.state.attemptedEs5Enabled, isTrue);
        expect(settingsCubit.state.isWritingEs5, isFalse);
        expect(settingsCubit.state.es5Message, contains('disconnected'));
        expect(settingsCubit.state.es5Message, contains('uncertain'));
      },
    );

    test(
      'keeps Mode disabled when its capability probe is not evidenced',
      () async {
        midiConnection.transport.onSend = (packet) {
          _respondWithSettings(midiConnection.transport, packet, modeValue: 3);
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        expect(settingsCubit.state.modeCapabilityEvidenced, isFalse);
        expect(settingsCubit.state.confirmedMode, isNull);
        expect(settingsCubit.state.modeMessage, contains('not evidenced'));

        final sendsBeforeModeChange = midiConnection.transport.sent.length;
        await settingsCubit.setExpansionMode(Ntx8cvExpansionMode.cv8x8);
        expect(midiConnection.transport.sent, hasLength(sendsBeforeModeChange));
      },
    );

    test(
      'reports a timed-out Mode probe as capability not evidenced',
      () async {
        midiConnection.transport.onSend = (packet) {
          if (packet[6] == 0x31 && packet[7] == 0x1B) return;
          _respondWithSettings(midiConnection.transport, packet);
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        if (settingsCubit.state.isLoadingMode ||
            settingsCubit.state.modeMessage == null) {
          await settingsCubit.stream.firstWhere(
            (state) => !state.isLoadingMode && state.modeMessage != null,
          );
        }

        expect(settingsCubit.state.modeCapabilityEvidenced, isFalse);
        expect(settingsCubit.state.isLoadingMode, isFalse);
        expect(settingsCubit.state.modeMessage, contains('not evidenced'));
      },
    );

    test('confirms every supported Mode without changing ES-5', () async {
      var deviceMode = Ntx8cvExpansionMode.cv8x8.value;
      midiConnection.transport.onSend = (packet) {
        if (packet[6] == 0x32 && packet[7] == 0x1B) {
          deviceMode = packet[8];
        }
        _respondWithSettings(
          midiConnection.transport,
          packet,
          es5Value: 1,
          modeValue: deviceMode,
        );
      };
      await connectionCubit.initialize();
      await connectionCubit.connect();
      await _flushEvents();

      expect(
        Ntx8cvExpansionMode.values.map((mode) => mode.label),
        orderedEquals(['8x8 CV', '1x8 32bit Audio', '2x8 16bit Audio']),
      );
      expect(
        Ntx8cvExpansionMode.values.map((mode) => mode.value),
        orderedEquals([0, 1, 2]),
      );

      for (final mode in [
        Ntx8cvExpansionMode.audio1x8_32bit,
        Ntx8cvExpansionMode.audio2x8_16bit,
        Ntx8cvExpansionMode.cv8x8,
      ]) {
        await settingsCubit.setExpansionMode(mode);

        expect(settingsCubit.state.confirmedMode, mode);
        expect(settingsCubit.state.hasPendingModeChange, isFalse);
        expect(settingsCubit.state.modeRebootRequired, isTrue);
        expect(settingsCubit.state.confirmedEs5Enabled, isTrue);
        expect(settingsCubit.state.hasPendingEs5Change, isFalse);
      }

      final settingWrites = midiConnection.transport.sent
          .where((packet) => packet[6] == 0x32)
          .toList();
      expect(
        settingWrites.map((packet) => packet[7]),
        orderedEquals([0x1B, 0x1B, 0x1B]),
      );
      expect(
        settingWrites.map((packet) => packet[8]),
        orderedEquals([1, 2, 0]),
      );
    });

    test(
      'confirms a retried Mode change only after matching readback and requires reboot',
      () async {
        var returnedModeValue = 2;
        midiConnection.transport.onSend = (packet) {
          _respondWithSettings(
            midiConnection.transport,
            packet,
            modeValue: returnedModeValue,
          );
        };
        await connectionCubit.initialize();
        await connectionCubit.connect();
        await _flushEvents();

        await settingsCubit.setExpansionMode(Ntx8cvExpansionMode.cv8x8);

        expect(
          settingsCubit.state.confirmedMode,
          Ntx8cvExpansionMode.audio2x8_16bit,
        );
        expect(settingsCubit.state.attemptedMode, Ntx8cvExpansionMode.cv8x8);
        expect(settingsCubit.state.modeRebootRequired, isFalse);
        expect(settingsCubit.state.modeMessage, contains('not confirmed'));
        expect(settingsCubit.state.modeMessage, contains('uncertain'));

        await connectionCubit.disconnect();
        final sendsBeforeReconnect = midiConnection.transport.sent.length;
        await connectionCubit.connect();
        await _flushEvents();

        expect(settingsCubit.state.hasPendingModeChange, isTrue);
        // Reconnect reads every setting but does not write a pending Mode.
        expect(
          midiConnection.transport.sent,
          hasLength(sendsBeforeReconnect + 21),
        );
        expect(
          midiConnection.transport.sent.where((packet) => packet[6] == 0x32),
          hasLength(1),
        );

        returnedModeValue = 0;
        await settingsCubit.retryModeChange();

        expect(settingsCubit.state.confirmedMode, Ntx8cvExpansionMode.cv8x8);
        expect(settingsCubit.state.hasPendingModeChange, isFalse);
        expect(settingsCubit.state.modeRebootRequired, isTrue);
        expect(settingsCubit.state.confirmedEs5Enabled, isFalse);
        expect(
          midiConnection.transport.sent[midiConnection.transport.sent.length -
              2],
          orderedEquals(_writeSetting(0x1B, 0)),
        );
        expect(
          midiConnection.transport.sent.last,
          orderedEquals(Ntx8cvSysExFixtures.readModeSetting),
        );
      },
    );
  });
}

void _respondWithSettings(
  _FakeNtx8cvMidiTransport transport,
  Uint8List packet, {
  int channelGroupValue = 0,
  int es5Value = 0,
  int modeValue = 2,
  int usbHostValue = 0,
  List<int> usbAudioChannelValues = const [1, 1, 1, 1, 1, 1, 1, 1],
  List<int> expanderAudioChannelValues = const [1, 1, 1, 1, 1, 1, 1, 1],
}) {
  final deviceId = packet[5];
  if (packet[6] == 0x22) {
    transport.receive(
      _withDeviceId(Ntx8cvSysExFixtures.deviceInformationResponse, deviceId),
    );
  } else if (packet[6] == 0x31 && packet[7] == 0x00) {
    transport.receive(_settingResponse(0x00, channelGroupValue, deviceId));
  } else if (packet[6] == 0x31 && packet[7] == 0x01) {
    transport.receive(_settingResponse(0x01, es5Value, deviceId));
  } else if (packet[6] == 0x31 && packet[7] == 0x1B) {
    transport.receive(_settingResponse(0x1B, modeValue, deviceId));
  } else if (packet[6] == 0x31 && packet[7] == kNtx8cvUsbHostEnabledSettingId) {
    transport.receive(
      _settingResponse(kNtx8cvUsbHostEnabledSettingId, usbHostValue, deviceId),
    );
  } else if (packet[6] == 0x31 &&
      packet[7] >= kNtx8cvFirstUsbAudioChannelSettingId &&
      packet[7] <
          kNtx8cvFirstUsbAudioChannelSettingId + kNtx8cvAudioChannelCount) {
    final index = packet[7] - kNtx8cvFirstUsbAudioChannelSettingId;
    transport.receive(
      _settingResponse(packet[7], usbAudioChannelValues[index], deviceId),
    );
  } else if (packet[6] == 0x31 &&
      packet[7] >= kNtx8cvFirstExpanderAudioChannelSettingId &&
      packet[7] <
          kNtx8cvFirstExpanderAudioChannelSettingId +
              kNtx8cvAudioChannelCount) {
    final index = packet[7] - kNtx8cvFirstExpanderAudioChannelSettingId;
    transport.receive(
      _settingResponse(packet[7], expanderAudioChannelValues[index], deviceId),
    );
  }
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Uint8List _writeSetting(int settingId, int value, [int deviceId = 0]) =>
    Uint8List.fromList([
      0xF0,
      0x00,
      0x21,
      0x27,
      0x6A,
      deviceId,
      0x32,
      settingId,
      value,
      0xF7,
    ]);

Uint8List _readSetting(int settingId, [int deviceId = 0]) => Uint8List.fromList(
  [0xF0, 0x00, 0x21, 0x27, 0x6A, deviceId, 0x31, settingId, 0xF7],
);

Uint8List _settingResponse(int settingId, int value, [int deviceId = 0]) =>
    Uint8List.fromList([
      0xF0,
      0x00,
      0x21,
      0x27,
      0x6A,
      deviceId,
      0x31,
      settingId,
      value,
      0xF7,
    ]);

Uint8List _withDeviceId(Uint8List packet, int deviceId) {
  final copy = Uint8List.fromList(packet);
  copy[5] = deviceId;
  return copy;
}

Ntx8cvMidiEndpoint _midiDevice({
  required String id,
  required String name,
  bool input = false,
  bool output = false,
}) =>
    Ntx8cvMidiEndpoint(id: id, name: name, hasInput: input, hasOutput: output);

class _MemoryNtx8cvConnectionStore implements Ntx8cvConnectionStore {
  @override
  Future<Ntx8cvSavedConnection> load() async => const Ntx8cvSavedConnection();

  @override
  Future<void> save(Ntx8cvSavedConnection selection) async {}
}

class _FakeNtx8cvMidiConnection implements Ntx8cvMidiConnection {
  List<Ntx8cvMidiEndpoint> devices = [];
  final _FakeNtx8cvMidiTransport transport = _FakeNtx8cvMidiTransport();
  int openCount = 0;
  int closeCount = 0;

  @override
  Stream<MidiSetupChange>? get setupChanges => null;

  @override
  Future<List<Ntx8cvMidiEndpoint>> listDevices() async => List.of(devices);

  @override
  Future<Ntx8cvMidiTransport> open({
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    openCount += 1;
    return transport;
  }

  @override
  Future<void> close({
    required Ntx8cvMidiTransport transport,
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    closeCount += 1;
  }

  Future<void> dispose() => transport.close();
}

class _FakeNtx8cvMidiTransport implements Ntx8cvMidiTransport {
  final _received = StreamController<Uint8List>.broadcast(sync: true);
  final List<Uint8List> sent = [];
  void Function(Uint8List packet)? onSend;

  @override
  Stream<Uint8List> get receivedPackets => _received.stream;

  @override
  Future<void> send(Uint8List packet) async {
    sent.add(packet);
    onSend?.call(packet);
  }

  void receive(Uint8List packet) => _received.add(packet);

  Future<void> close() => _received.close();
}
