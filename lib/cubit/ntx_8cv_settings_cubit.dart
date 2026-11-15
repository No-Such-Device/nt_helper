import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:nt_helper/cubit/ntx_8cv_connection_cubit.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_sysex.dart';

/// The released NTX-8CV setting that selects its eight-channel block.
const int kNtx8cvChannelGroupSettingId = 0x00;

/// The released NTX-8CV setting that enables its ES-5 output use.
const int kNtx8cvEs5EnabledSettingId = 0x01;

/// The first of eight per-channel USB audio enable settings.
const int kNtx8cvFirstUsbAudioChannelSettingId = 0x04;

/// The number of independently enabled channels in each audio route.
const int kNtx8cvAudioChannelCount = 8;

/// The released setting that lets the NTX-8CV act as a USB host.
const int kNtx8cvUsbHostEnabledSettingId = 0x17;

/// The upstream NT expansion-mode setting. It is probed before it is writable.
const int kNtx8cvExpansionModeSettingId = 0x1B;

/// The first of eight per-channel disting NT expander audio enable settings.
const int kNtx8cvFirstExpanderAudioChannelSettingId = 0x1C;

/// The three owner-supported NT expansion modes and their protocol values.
enum Ntx8cvExpansionMode {
  cv8x8(0, '8x8 CV'),
  audio1x8_32bit(1, '1x8 32bit Audio'),
  audio2x8_16bit(2, '2x8 16bit Audio');

  const Ntx8cvExpansionMode(this.value, this.label);

  final int value;
  final String label;

  static Ntx8cvExpansionMode? fromValue(int value) {
    for (final mode in values) {
      if (mode.value == value) return mode;
    }
    return null;
  }
}

/// The released Channel Group values, each selecting one eight-channel block.
enum Ntx8cvChannelGroup {
  channels1To8(0, '1–8'),
  channels9To16(1, '9–16'),
  channels17To24(2, '17–24'),
  channels25To32(3, '25–32'),
  channels33To40(4, '33–40'),
  channels41To48(5, '41–48'),
  channels49To56(6, '49–56'),
  channels57To64(7, '57–64');

  const Ntx8cvChannelGroup(this.value, this.label);

  final int value;
  final String label;

  static Ntx8cvChannelGroup? fromValue(int value) {
    for (final group in values) {
      if (group.value == value) return group;
    }
    return null;
  }
}

enum Ntx8cvSetting {
  channelGroup(kNtx8cvChannelGroupSettingId, 'Channel Group'),
  es5Enabled(kNtx8cvEs5EnabledSettingId, 'ES-5'),
  usbAudioChannel1(kNtx8cvFirstUsbAudioChannelSettingId, 'USB audio channel 1'),
  usbAudioChannel2(
    kNtx8cvFirstUsbAudioChannelSettingId + 1,
    'USB audio channel 2',
  ),
  usbAudioChannel3(
    kNtx8cvFirstUsbAudioChannelSettingId + 2,
    'USB audio channel 3',
  ),
  usbAudioChannel4(
    kNtx8cvFirstUsbAudioChannelSettingId + 3,
    'USB audio channel 4',
  ),
  usbAudioChannel5(
    kNtx8cvFirstUsbAudioChannelSettingId + 4,
    'USB audio channel 5',
  ),
  usbAudioChannel6(
    kNtx8cvFirstUsbAudioChannelSettingId + 5,
    'USB audio channel 6',
  ),
  usbAudioChannel7(
    kNtx8cvFirstUsbAudioChannelSettingId + 6,
    'USB audio channel 7',
  ),
  usbAudioChannel8(
    kNtx8cvFirstUsbAudioChannelSettingId + 7,
    'USB audio channel 8',
  ),
  usbHostEnabled(kNtx8cvUsbHostEnabledSettingId, 'USB host'),
  expansionMode(kNtx8cvExpansionModeSettingId, 'NT expansion mode'),
  expanderAudioChannel1(
    kNtx8cvFirstExpanderAudioChannelSettingId,
    'NT expander audio channel 1',
  ),
  expanderAudioChannel2(
    kNtx8cvFirstExpanderAudioChannelSettingId + 1,
    'NT expander audio channel 2',
  ),
  expanderAudioChannel3(
    kNtx8cvFirstExpanderAudioChannelSettingId + 2,
    'NT expander audio channel 3',
  ),
  expanderAudioChannel4(
    kNtx8cvFirstExpanderAudioChannelSettingId + 3,
    'NT expander audio channel 4',
  ),
  expanderAudioChannel5(
    kNtx8cvFirstExpanderAudioChannelSettingId + 4,
    'NT expander audio channel 5',
  ),
  expanderAudioChannel6(
    kNtx8cvFirstExpanderAudioChannelSettingId + 5,
    'NT expander audio channel 6',
  ),
  expanderAudioChannel7(
    kNtx8cvFirstExpanderAudioChannelSettingId + 6,
    'NT expander audio channel 7',
  ),
  expanderAudioChannel8(
    kNtx8cvFirstExpanderAudioChannelSettingId + 7,
    'NT expander audio channel 8',
  );

  const Ntx8cvSetting(this.id, this.label);

  final int id;
  final String label;

  int? get usbAudioChannelIndex {
    final index = id - kNtx8cvFirstUsbAudioChannelSettingId;
    return index >= 0 && index < kNtx8cvAudioChannelCount ? index : null;
  }

  int? get expanderAudioChannelIndex {
    final index = id - kNtx8cvFirstExpanderAudioChannelSettingId;
    return index >= 0 && index < kNtx8cvAudioChannelCount ? index : null;
  }
}

const List<Ntx8cvSetting> _usbAudioChannelSettings = [
  Ntx8cvSetting.usbAudioChannel1,
  Ntx8cvSetting.usbAudioChannel2,
  Ntx8cvSetting.usbAudioChannel3,
  Ntx8cvSetting.usbAudioChannel4,
  Ntx8cvSetting.usbAudioChannel5,
  Ntx8cvSetting.usbAudioChannel6,
  Ntx8cvSetting.usbAudioChannel7,
  Ntx8cvSetting.usbAudioChannel8,
];

const List<Ntx8cvSetting> _expanderAudioChannelSettings = [
  Ntx8cvSetting.expanderAudioChannel1,
  Ntx8cvSetting.expanderAudioChannel2,
  Ntx8cvSetting.expanderAudioChannel3,
  Ntx8cvSetting.expanderAudioChannel4,
  Ntx8cvSetting.expanderAudioChannel5,
  Ntx8cvSetting.expanderAudioChannel6,
  Ntx8cvSetting.expanderAudioChannel7,
  Ntx8cvSetting.expanderAudioChannel8,
];

/// The confirmed and attempted state of one NTX-8CV setting.
///
/// An attempted value is deliberately not folded into [confirmedValue]: no
/// write acknowledgement exists, so only a matching readback can confirm it.
class Ntx8cvSettingChange {
  const Ntx8cvSettingChange({
    this.confirmedValue,
    this.attemptedValue,
    this.isLoading = false,
    this.isWriting = false,
    this.message,
  });

  final int? confirmedValue;
  final int? attemptedValue;
  final bool isLoading;
  final bool isWriting;
  final String? message;

  bool get hasPendingChange => attemptedValue != null;

  Ntx8cvSettingChange copyWith({
    int? confirmedValue,
    bool clearConfirmedValue = false,
    int? attemptedValue,
    bool clearAttemptedValue = false,
    bool? isLoading,
    bool? isWriting,
    String? message,
    bool clearMessage = false,
  }) {
    return Ntx8cvSettingChange(
      confirmedValue: clearConfirmedValue
          ? null
          : confirmedValue ?? this.confirmedValue,
      attemptedValue: clearAttemptedValue
          ? null
          : attemptedValue ?? this.attemptedValue,
      isLoading: isLoading ?? this.isLoading,
      isWriting: isWriting ?? this.isWriting,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

/// Presentation state for the device-confirmed NTX-8CV settings.
class Ntx8cvSettingsState {
  const Ntx8cvSettingsState({
    this.channelGroup = const Ntx8cvSettingChange(),
    this.es5 = const Ntx8cvSettingChange(),
    this.usbHost = const Ntx8cvSettingChange(),
    this.usbAudioChannels = const [
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
    ],
    this.expanderAudioChannels = const [
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
      Ntx8cvSettingChange(),
    ],
    this.mode = const Ntx8cvSettingChange(),
    this.modeCapabilityEvidenced = false,
    this.modeRebootRequired = false,
    this.isRebooting = false,
    this.isRefreshing = false,
    this.rebootMessage,
  });

  final Ntx8cvSettingChange channelGroup;
  final Ntx8cvSettingChange es5;
  final Ntx8cvSettingChange usbHost;
  final List<Ntx8cvSettingChange> usbAudioChannels;
  final List<Ntx8cvSettingChange> expanderAudioChannels;
  final Ntx8cvSettingChange mode;

  /// True only after the current session read setting `0x1B` with a value in
  /// `0..2`. A timeout is absence of evidence, not proof of unsupported
  /// firmware.
  final bool modeCapabilityEvidenced;

  /// A confirmed mode change is stored but needs a reboot to take effect.
  final bool modeRebootRequired;

  /// True while the selected device is being rebooted and revalidated.
  final bool isRebooting;

  /// True while the current session's complete settings snapshot is read.
  final bool isRefreshing;

  /// A failed reboot or post-reboot refresh explanation for the user.
  final String? rebootMessage;

  Ntx8cvChannelGroup? get confirmedChannelGroup =>
      channelGroup.confirmedValue == null
      ? null
      : Ntx8cvChannelGroup.fromValue(channelGroup.confirmedValue!);

  Ntx8cvChannelGroup? get attemptedChannelGroup =>
      channelGroup.attemptedValue == null
      ? null
      : Ntx8cvChannelGroup.fromValue(channelGroup.attemptedValue!);

  bool get isLoadingChannelGroup => channelGroup.isLoading;
  bool get isWritingChannelGroup => channelGroup.isWriting;
  String? get channelGroupMessage => channelGroup.message;
  bool get hasPendingChannelGroupChange => channelGroup.hasPendingChange;

  bool? get confirmedEs5Enabled => switch (es5.confirmedValue) {
    0 => false,
    1 => true,
    _ => null,
  };

  bool? get attemptedEs5Enabled => switch (es5.attemptedValue) {
    0 => false,
    1 => true,
    _ => null,
  };

  bool get isLoadingEs5 => es5.isLoading;
  bool get isWritingEs5 => es5.isWriting;
  String? get es5Message => es5.message;
  bool get hasPendingEs5Change => es5.hasPendingChange;

  bool? get confirmedUsbHostEnabled => _boolValue(usbHost.confirmedValue);
  bool? get attemptedUsbHostEnabled => _boolValue(usbHost.attemptedValue);
  bool get isLoadingUsbHost => usbHost.isLoading;
  bool get isWritingUsbHost => usbHost.isWriting;
  String? get usbHostMessage => usbHost.message;
  bool get hasPendingUsbHostChange => usbHost.hasPendingChange;

  bool? confirmedUsbAudioChannelEnabled(int index) =>
      _boolValue(usbAudioChannels[index].confirmedValue);

  bool? attemptedUsbAudioChannelEnabled(int index) =>
      _boolValue(usbAudioChannels[index].attemptedValue);

  bool isLoadingUsbAudioChannel(int index) => usbAudioChannels[index].isLoading;
  bool isWritingUsbAudioChannel(int index) => usbAudioChannels[index].isWriting;
  String? usbAudioChannelMessage(int index) => usbAudioChannels[index].message;
  bool hasPendingUsbAudioChannelChange(int index) =>
      usbAudioChannels[index].hasPendingChange;

  bool? confirmedExpanderAudioChannelEnabled(int index) =>
      _boolValue(expanderAudioChannels[index].confirmedValue);

  bool? attemptedExpanderAudioChannelEnabled(int index) =>
      _boolValue(expanderAudioChannels[index].attemptedValue);

  bool isLoadingExpanderAudioChannel(int index) =>
      expanderAudioChannels[index].isLoading;
  bool isWritingExpanderAudioChannel(int index) =>
      expanderAudioChannels[index].isWriting;
  String? expanderAudioChannelMessage(int index) =>
      expanderAudioChannels[index].message;
  bool hasPendingExpanderAudioChannelChange(int index) =>
      expanderAudioChannels[index].hasPendingChange;

  bool get hasPendingUsbSettingsChange =>
      hasPendingUsbHostChange ||
      usbAudioChannels.any((change) => change.hasPendingChange);

  bool get hasPendingExpanderAudioChange =>
      expanderAudioChannels.any((change) => change.hasPendingChange);

  bool get hasUsbSettingsError =>
      usbHost.message != null ||
      usbAudioChannels.any((change) => change.message != null);

  bool get hasExpanderAudioError =>
      expanderAudioChannels.any((change) => change.message != null);

  bool get hasConfirmedUsbSettingsSnapshot =>
      confirmedUsbHostEnabled != null &&
      usbAudioChannels.every(
        (change) => _boolValue(change.confirmedValue) != null,
      );

  bool get hasConfirmedExpanderAudioSnapshot => expanderAudioChannels.every(
    (change) => _boolValue(change.confirmedValue) != null,
  );

  Ntx8cvExpansionMode? get confirmedMode => mode.confirmedValue == null
      ? null
      : Ntx8cvExpansionMode.fromValue(mode.confirmedValue!);

  Ntx8cvExpansionMode? get attemptedMode => mode.attemptedValue == null
      ? null
      : Ntx8cvExpansionMode.fromValue(mode.attemptedValue!);

  bool get isLoadingMode => mode.isLoading;
  bool get isWritingMode => mode.isWriting;
  String? get modeMessage => mode.message;
  bool get hasPendingModeChange => mode.hasPendingChange;

  bool get isBusy =>
      isRebooting ||
      isRefreshing ||
      channelGroup.isLoading ||
      channelGroup.isWriting ||
      es5.isLoading ||
      es5.isWriting ||
      usbHost.isLoading ||
      usbHost.isWriting ||
      usbAudioChannels.any((change) => change.isLoading || change.isWriting) ||
      expanderAudioChannels.any(
        (change) => change.isLoading || change.isWriting,
      ) ||
      mode.isLoading ||
      mode.isWriting;

  bool get hasSettingOperationInProgress =>
      isRefreshing ||
      channelGroup.isLoading ||
      channelGroup.isWriting ||
      es5.isLoading ||
      es5.isWriting ||
      usbHost.isLoading ||
      usbHost.isWriting ||
      usbAudioChannels.any((change) => change.isLoading || change.isWriting) ||
      expanderAudioChannels.any(
        (change) => change.isLoading || change.isWriting,
      ) ||
      mode.isLoading ||
      mode.isWriting;

  Ntx8cvSettingsState copyWith({
    Ntx8cvSettingChange? channelGroup,
    Ntx8cvSettingChange? es5,
    Ntx8cvSettingChange? usbHost,
    List<Ntx8cvSettingChange>? usbAudioChannels,
    List<Ntx8cvSettingChange>? expanderAudioChannels,
    Ntx8cvSettingChange? mode,
    bool? modeCapabilityEvidenced,
    bool? modeRebootRequired,
    bool? isRebooting,
    bool? isRefreshing,
    String? rebootMessage,
    bool clearRebootMessage = false,
  }) {
    return Ntx8cvSettingsState(
      channelGroup: channelGroup ?? this.channelGroup,
      es5: es5 ?? this.es5,
      usbHost: usbHost ?? this.usbHost,
      usbAudioChannels: usbAudioChannels ?? this.usbAudioChannels,
      expanderAudioChannels:
          expanderAudioChannels ?? this.expanderAudioChannels,
      mode: mode ?? this.mode,
      modeCapabilityEvidenced:
          modeCapabilityEvidenced ?? this.modeCapabilityEvidenced,
      modeRebootRequired: modeRebootRequired ?? this.modeRebootRequired,
      isRebooting: isRebooting ?? this.isRebooting,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      rebootMessage: clearRebootMessage
          ? null
          : rebootMessage ?? this.rebootMessage,
    );
  }

  Ntx8cvSettingChange changeFor(Ntx8cvSetting setting) {
    final usbAudioChannelIndex = setting.usbAudioChannelIndex;
    if (usbAudioChannelIndex != null) {
      return usbAudioChannels[usbAudioChannelIndex];
    }
    final expanderAudioChannelIndex = setting.expanderAudioChannelIndex;
    if (expanderAudioChannelIndex != null) {
      return expanderAudioChannels[expanderAudioChannelIndex];
    }
    return switch (setting) {
      Ntx8cvSetting.channelGroup => channelGroup,
      Ntx8cvSetting.es5Enabled => es5,
      Ntx8cvSetting.usbHostEnabled => usbHost,
      Ntx8cvSetting.expansionMode => mode,
      _ => throw StateError('Unhandled NTX-8CV setting ${setting.name}.'),
    };
  }

  Ntx8cvSettingsState withChange(
    Ntx8cvSetting setting,
    Ntx8cvSettingChange change, {
    bool? modeCapabilityEvidenced,
    bool? modeRebootRequired,
  }) {
    final usbAudioChannelIndex = setting.usbAudioChannelIndex;
    if (usbAudioChannelIndex != null) {
      final updatedChannels = List<Ntx8cvSettingChange>.of(usbAudioChannels);
      updatedChannels[usbAudioChannelIndex] = change;
      return copyWith(
        usbAudioChannels: List.unmodifiable(updatedChannels),
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      );
    }
    final expanderAudioChannelIndex = setting.expanderAudioChannelIndex;
    if (expanderAudioChannelIndex != null) {
      final updatedChannels = List<Ntx8cvSettingChange>.of(
        expanderAudioChannels,
      );
      updatedChannels[expanderAudioChannelIndex] = change;
      return copyWith(
        expanderAudioChannels: List.unmodifiable(updatedChannels),
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      );
    }
    return switch (setting) {
      Ntx8cvSetting.channelGroup => copyWith(
        channelGroup: change,
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      ),
      Ntx8cvSetting.es5Enabled => copyWith(
        es5: change,
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      ),
      Ntx8cvSetting.usbHostEnabled => copyWith(
        usbHost: change,
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      ),
      Ntx8cvSetting.expansionMode => copyWith(
        mode: change,
        modeCapabilityEvidenced: modeCapabilityEvidenced,
        modeRebootRequired: modeRebootRequired,
      ),
      _ => throw StateError('Unhandled NTX-8CV setting ${setting.name}.'),
    };
  }

  static bool? _boolValue(int? value) => switch (value) {
    0 => false,
    1 => true,
    _ => null,
  };
}

/// Loads and changes settings for the currently identity-validated NTX-8CV.
///
/// This cubit owns device-confirmed setting state, not MIDI endpoints. It
/// listens to [Ntx8cvConnectionCubit] so it can only issue setting requests
/// through the session that is currently scoped to the selected device.
class Ntx8cvSettingsCubit extends Cubit<Ntx8cvSettingsState> {
  Ntx8cvSettingsCubit({required this._connectionCubit})
    : super(const Ntx8cvSettingsState()) {
    _connectionSubscription = _connectionCubit.stream.listen(
      _handleConnectionState,
    );
    _handleConnectionState(_connectionCubit.state);
  }

  final Ntx8cvConnectionCubit _connectionCubit;
  late final StreamSubscription<Ntx8cvConnectionState> _connectionSubscription;
  Ntx8cvSession? _activeSession;
  Ntx8cvSession? _refreshSession;
  Future<void>? _refreshFuture;
  Future<void> _settingWriteQueue = Future<void>.value();
  String? _targetKey;

  /// Changes Channel Group immediately, but commits it to presentation state
  /// only after a same-setting read returns the attempted value.
  Future<void> setChannelGroup(Ntx8cvChannelGroup group) =>
      _setSetting(Ntx8cvSetting.channelGroup, group.value);

  /// Changes ES-5 use immediately, but commits it to presentation state only
  /// after a same-setting read returns the attempted value.
  Future<void> setEs5Enabled(bool enabled) =>
      _setSetting(Ntx8cvSetting.es5Enabled, enabled ? 1 : 0);

  /// Enables or disables the NTX-8CV's USB host role.
  Future<void> setUsbHostEnabled(bool enabled) =>
      _setSetting(Ntx8cvSetting.usbHostEnabled, enabled ? 1 : 0);

  /// Enables or disables one of the eight USB audio channels.
  Future<void> setUsbAudioChannelEnabled(int index, bool enabled) {
    if (index < 0 || index >= kNtx8cvAudioChannelCount) {
      throw RangeError.range(index, 0, kNtx8cvAudioChannelCount - 1, 'index');
    }
    return _setSetting(_usbAudioChannelSettings[index], enabled ? 1 : 0);
  }

  /// Enables or disables one of the eight disting NT expander audio channels.
  Future<void> setExpanderAudioChannelEnabled(int index, bool enabled) {
    if (index < 0 || index >= kNtx8cvAudioChannelCount) {
      throw RangeError.range(index, 0, kNtx8cvAudioChannelCount - 1, 'index');
    }
    return _setSetting(_expanderAudioChannelSettings[index], enabled ? 1 : 0);
  }

  /// Changes the NT expansion mode immediately after a successful capability
  /// probe. The three [Ntx8cvExpansionMode] values map to protocol `0..2`.
  Future<void> setExpansionMode(Ntx8cvExpansionMode mode) =>
      _setSetting(Ntx8cvSetting.expansionMode, mode.value);

  /// Explicitly resends the retained, unconfirmed Channel Group change to the
  /// current identity-validated NTX-8CV. It never reconnects or retries on
  /// its own.
  Future<void> retryChannelGroupChange() =>
      _retrySetting(Ntx8cvSetting.channelGroup);

  /// Explicitly resends the retained, unconfirmed ES-5 change to the current
  /// identity-validated NTX-8CV. It never reconnects or retries on its own.
  Future<void> retryEs5Change() => _retrySetting(Ntx8cvSetting.es5Enabled);

  /// Explicitly resends the retained, unconfirmed Mode change to the current
  /// identity-validated NTX-8CV. Matching readback is still required.
  Future<void> retryModeChange() => _retrySetting(Ntx8cvSetting.expansionMode);

  /// Reboots the currently connected NTX-8CV once, then waits for its selected
  /// endpoint pair to be revalidated and all non-pending settings to refresh.
  /// No confirmation dialog or automatic resend is involved.
  Future<void> reboot() async {
    if (_currentSession == null || state.isBusy) return;

    emit(state.copyWith(isRebooting: true, clearRebootMessage: true));
    final reconnected = await _connectionCubit.rebootAndReconnect();
    if (isClosed) return;

    if (!reconnected) {
      emit(
        state.copyWith(
          isRebooting: false,
          rebootMessage: 'Reboot did not complete. Reconnect the NTX-8CV.',
        ),
      );
      return;
    }

    final session = await _waitForCurrentSession();
    if (session == null) {
      emit(
        state.copyWith(
          isRebooting: false,
          rebootMessage:
              'Settings refresh stopped after reboot. Reconnect the NTX-8CV.',
        ),
      );
      return;
    }

    await _refreshFor(session);
    if (!_isActiveSession(session)) return;
    emit(
      state.copyWith(
        isRebooting: false,
        modeRebootRequired: false,
        clearRebootMessage: true,
      ),
    );
  }

  Future<void> _setSetting(Ntx8cvSetting setting, int value) {
    return _enqueueSettingWrite(() async {
      final change = state.changeFor(setting);
      if (change.confirmedValue == null ||
          change.confirmedValue == value ||
          change.isLoading ||
          change.isWriting ||
          state.isRebooting ||
          state.isRefreshing ||
          (setting == Ntx8cvSetting.expansionMode &&
              !state.modeCapabilityEvidenced)) {
        return;
      }
      if (change.hasPendingChange && change.attemptedValue != value) return;
      await _writeSetting(setting, value);
    });
  }

  Future<void> _retrySetting(Ntx8cvSetting setting) {
    return _enqueueSettingWrite(() async {
      final change = state.changeFor(setting);
      final attemptedValue = change.attemptedValue;
      if (attemptedValue == null ||
          change.isLoading ||
          change.isWriting ||
          state.isRebooting ||
          state.isRefreshing ||
          (setting == Ntx8cvSetting.expansionMode &&
              !state.modeCapabilityEvidenced)) {
        return;
      }
      await _writeSetting(setting, attemptedValue);
    });
  }

  Future<void> _enqueueSettingWrite(Future<void> Function() operation) {
    final queued = _settingWriteQueue.then((_) async {
      if (isClosed) return;
      await operation();
    });
    _settingWriteQueue = queued;
    return queued;
  }

  Future<void> _writeSetting(Ntx8cvSetting setting, int value) async {
    final session = _currentSession;
    if (session == null) return;

    emit(
      state.withChange(
        setting,
        state
            .changeFor(setting)
            .copyWith(
              attemptedValue: value,
              isWriting: true,
              clearMessage: true,
            ),
      ),
    );
    try {
      await session.writeAndConfirmSetting(settingId: setting.id, value: value);
      if (!_isActiveSession(session)) return;
      emit(
        state.withChange(
          setting,
          state
              .changeFor(setting)
              .copyWith(
                confirmedValue: value,
                clearAttemptedValue: true,
                isWriting: false,
                clearMessage: true,
              ),
          modeRebootRequired: setting == Ntx8cvSetting.expansionMode
              ? true
              : null,
        ),
      );
    } catch (_) {
      if (!_isActiveSession(session)) return;
      emit(
        state.withChange(
          setting,
          state
              .changeFor(setting)
              .copyWith(
                isWriting: false,
                message:
                    'The ${setting.label} change was not confirmed by device '
                    'readback. The actual device state is uncertain.',
              ),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    await _connectionSubscription.cancel();
    return super.close();
  }

  void _handleConnectionState(Ntx8cvConnectionState connectionState) {
    final targetKey = _connectionTargetKey(connectionState);
    if (targetKey != null && targetKey != _targetKey) {
      final hasPreviousTarget = _targetKey != null;
      _targetKey = targetKey;
      _activeSession = null;
      if (!isClosed) {
        emit(
          hasPreviousTarget
              ? _stateForChangedTarget()
              : const Ntx8cvSettingsState(),
        );
      }
    }

    final session = _connectionCubit.session;
    if (session == null) {
      _activeSession = null;
      if (!isClosed && state.hasSettingOperationInProgress) {
        emit(_stateForInterruptedConnection());
      }
      return;
    }
    if (identical(session, _activeSession)) return;

    _activeSession = session;
    unawaited(_refreshFor(session));
  }

  /// Clears confirmations that belong to a changed target while retaining an
  /// explicit attempted value for a user-directed retry on the new target.
  Ntx8cvSettingsState _stateForChangedTarget() {
    Ntx8cvSettingChange retainedChange(
      Ntx8cvSettingChange change,
      String label,
    ) {
      if (!change.hasPendingChange) return const Ntx8cvSettingChange();
      return Ntx8cvSettingChange(
        attemptedValue: change.attemptedValue,
        message:
            'The NTX-8CV target changed before the $label change could be '
            'confirmed. The actual device state is uncertain. Retry send will '
            'use the current selected connection and device ID.',
      );
    }

    return Ntx8cvSettingsState(
      channelGroup: retainedChange(state.channelGroup, 'Channel Group'),
      es5: retainedChange(state.es5, 'ES-5'),
      usbHost: retainedChange(state.usbHost, 'USB host'),
      usbAudioChannels: List.unmodifiable([
        for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
          retainedChange(
            state.usbAudioChannels[index],
            'USB audio channel ${index + 1}',
          ),
      ]),
      expanderAudioChannels: List.unmodifiable([
        for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
          retainedChange(
            state.expanderAudioChannels[index],
            'NT expander audio channel ${index + 1}',
          ),
      ]),
      mode: retainedChange(state.mode, 'Mode'),
    );
  }

  Ntx8cvSettingsState _stateForInterruptedConnection() {
    Ntx8cvSettingChange interruptedChange(
      Ntx8cvSettingChange change,
      String label,
    ) {
      if (!change.isWriting && !change.isLoading) return change;
      final wasWriting = change.isWriting;
      return change.copyWith(
        isLoading: false,
        isWriting: false,
        message: wasWriting
            ? 'The NTX-8CV disconnected before the $label change could be '
                  'confirmed. The actual device state is uncertain.'
            : 'The NTX-8CV disconnected before the device-confirmed $label '
                  'value could be read.',
      );
    }

    return Ntx8cvSettingsState(
      channelGroup: interruptedChange(state.channelGroup, 'Channel Group'),
      es5: interruptedChange(state.es5, 'ES-5'),
      usbHost: interruptedChange(state.usbHost, 'USB host'),
      usbAudioChannels: List.unmodifiable([
        for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
          interruptedChange(
            state.usbAudioChannels[index],
            'USB audio channel ${index + 1}',
          ),
      ]),
      expanderAudioChannels: List.unmodifiable([
        for (var index = 0; index < kNtx8cvAudioChannelCount; index++)
          interruptedChange(
            state.expanderAudioChannels[index],
            'NT expander audio channel ${index + 1}',
          ),
      ]),
      mode: interruptedChange(state.mode, 'NT expansion mode'),
      modeRebootRequired: state.modeRebootRequired,
      isRebooting: state.isRebooting,
      rebootMessage: state.rebootMessage,
    );
  }

  Future<Ntx8cvSession?> _waitForCurrentSession() async {
    // Cubit stream listeners receive the revalidated connection state
    // asynchronously. Give that listener two event turns to bind the new
    // session and begin its shared refresh rather than starting a duplicate.
    for (var attempt = 0; attempt < 2; attempt++) {
      final session = _currentSession;
      if (session != null) return session;
      await Future<void>.delayed(Duration.zero);
    }
    return _currentSession;
  }

  Future<void> _refreshFor(Ntx8cvSession session) {
    if (identical(_refreshSession, session) && _refreshFuture != null) {
      return _refreshFuture!;
    }
    _refreshSession = session;
    final refresh = _refreshSettings(session);
    _refreshFuture = refresh;
    return refresh;
  }

  Future<void> _refreshSettings(Ntx8cvSession session) async {
    // Do not read a setting whose attempted value is pending: leaving that
    // value untouched makes reconnect a recovery step, never an implicit
    // confirmation or resend. A Mode probe is always safe and is required to
    // enable a Mode retry for this newly validated session.
    emit(
      state.copyWith(
        isRefreshing: true,
        modeCapabilityEvidenced: false,
        clearRebootMessage: true,
      ),
    );

    var es5 = state.es5;
    var usbHost = state.usbHost;
    final usbAudioChannels = List<Ntx8cvSettingChange>.of(
      state.usbAudioChannels,
    );
    final expanderAudioChannels = List<Ntx8cvSettingChange>.of(
      state.expanderAudioChannels,
    );
    var mode = state.mode;
    var channelGroup = state.channelGroup;

    if (!es5.hasPendingChange) {
      es5 = await _readSettingResult(session, Ntx8cvSetting.es5Enabled, es5);
    }
    if (!_isActiveSession(session)) return;

    mode = await _readSettingResult(session, Ntx8cvSetting.expansionMode, mode);
    if (!_isActiveSession(session)) return;

    if (!channelGroup.hasPendingChange) {
      channelGroup = await _readSettingResult(
        session,
        Ntx8cvSetting.channelGroup,
        channelGroup,
      );
    }
    if (!_isActiveSession(session)) return;

    if (!usbHost.hasPendingChange) {
      usbHost = await _readSettingResult(
        session,
        Ntx8cvSetting.usbHostEnabled,
        usbHost,
      );
    }
    if (!_isActiveSession(session)) return;

    for (var index = 0; index < kNtx8cvAudioChannelCount; index++) {
      final current = usbAudioChannels[index];
      if (!current.hasPendingChange) {
        usbAudioChannels[index] = await _readSettingResult(
          session,
          _usbAudioChannelSettings[index],
          current,
        );
      }
      if (!_isActiveSession(session)) return;
    }

    for (var index = 0; index < kNtx8cvAudioChannelCount; index++) {
      final current = expanderAudioChannels[index];
      if (!current.hasPendingChange) {
        expanderAudioChannels[index] = await _readSettingResult(
          session,
          _expanderAudioChannelSettings[index],
          current,
        );
      }
      if (!_isActiveSession(session)) return;
    }

    emit(
      Ntx8cvSettingsState(
        channelGroup: channelGroup,
        es5: es5,
        usbHost: usbHost,
        usbAudioChannels: List.unmodifiable(usbAudioChannels),
        expanderAudioChannels: List.unmodifiable(expanderAudioChannels),
        mode: mode,
        modeCapabilityEvidenced:
            mode.confirmedValue != null &&
            _isValidValue(Ntx8cvSetting.expansionMode, mode.confirmedValue!) &&
            mode.message == null,
        modeRebootRequired: state.modeRebootRequired,
        isRebooting: state.isRebooting,
        rebootMessage: state.rebootMessage,
      ),
    );
  }

  Future<Ntx8cvSettingChange> _readSettingResult(
    Ntx8cvSession session,
    Ntx8cvSetting setting,
    Ntx8cvSettingChange current,
  ) async {
    try {
      final response = await session.readSetting(settingId: setting.id);
      if (!_isActiveSession(session)) return current;
      if (!_isValidValue(setting, response.value)) {
        throw StateError(
          '${setting.label} setting has invalid value ${response.value}.',
        );
      }
      return current.copyWith(
        confirmedValue: response.value,
        isLoading: false,
        clearMessage: true,
      );
    } catch (_) {
      if (!_isActiveSession(session)) return current;
      return current.copyWith(
        isLoading: false,
        message: switch (setting) {
          Ntx8cvSetting.expansionMode =>
            'Mode capability was not evidenced. The NTX-8CV did not '
                'return a valid Mode setting value.',
          Ntx8cvSetting.channelGroup =>
            'Could not read the device-confirmed Channel Group setting. '
                'Check the NTX-8CV connection and reconnect to try again.',
          Ntx8cvSetting.es5Enabled =>
            'Could not read the device-confirmed ES-5 setting. Check '
                'the NTX-8CV connection and reconnect to try again.',
          Ntx8cvSetting.usbHostEnabled =>
            'Could not read the device-confirmed USB host setting.',
          _
              when setting.usbAudioChannelIndex != null ||
                  setting.expanderAudioChannelIndex != null =>
            'Could not read the device-confirmed ${setting.label} setting.',
          _ => 'Could not read the device-confirmed setting.',
        },
      );
    }
  }

  bool _isValidValue(Ntx8cvSetting setting, int value) => switch (setting) {
    Ntx8cvSetting.channelGroup => Ntx8cvChannelGroup.fromValue(value) != null,
    Ntx8cvSetting.es5Enabled => value == 0 || value == 1,
    Ntx8cvSetting.usbHostEnabled => value == 0 || value == 1,
    Ntx8cvSetting.expansionMode => Ntx8cvExpansionMode.fromValue(value) != null,
    _
        when setting.usbAudioChannelIndex != null ||
            setting.expanderAudioChannelIndex != null =>
      value == 0 || value == 1,
    _ => false,
  };

  Ntx8cvSession? get _currentSession {
    final session = _connectionCubit.session;
    return identical(session, _activeSession) ? session : null;
  }

  bool _isActiveSession(Ntx8cvSession session) =>
      !isClosed &&
      identical(session, _activeSession) &&
      identical(session, _connectionCubit.session);

  static String? _connectionTargetKey(Ntx8cvConnectionState state) {
    final inputId = state.selectedInputDevice?.id;
    final outputId = state.selectedOutputDevice?.id;
    if (inputId == null || outputId == null) return null;
    return '$inputId:$outputId:${state.deviceId}';
  }
}
