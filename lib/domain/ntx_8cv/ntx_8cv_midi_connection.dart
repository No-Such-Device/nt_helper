import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:nt_helper/domain/midi_command_factory.dart';
import 'package:nt_helper/domain/ntx_8cv/ntx_8cv_sysex.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The persisted target selection for the independent NTX-8CV connection.
class Ntx8cvSavedConnection {
  const Ntx8cvSavedConnection({
    this.inputDeviceName,
    this.inputDeviceId,
    this.outputDeviceName,
    this.outputDeviceId,
    this.deviceId = 0,
  });

  final String? inputDeviceName;
  final String? inputDeviceId;
  final String? outputDeviceName;
  final String? outputDeviceId;
  final int deviceId;
}

/// Immutable endpoint data exposed by the NTX-8CV MIDI connection module.
///
/// The native MIDI package owns mutable [MidiDevice] instances and rewrites
/// them when packets arrive. Keeping those objects behind this module's
/// interface prevents out-of-band mutations from leaking into Cubit state.
class Ntx8cvMidiEndpoint {
  const Ntx8cvMidiEndpoint({
    required this.id,
    required this.name,
    required this.hasInput,
    required this.hasOutput,
  });

  final String id;
  final String name;
  final bool hasInput;
  final bool hasOutput;
}

/// Persists only the selected NTX-8CV endpoints and its SysEx device ID.
abstract interface class Ntx8cvConnectionStore {
  Future<Ntx8cvSavedConnection> load();

  Future<void> save(Ntx8cvSavedConnection selection);
}

/// Shared-preferences persistence for the NTX-8CV add-on's independent target.
class SharedPreferencesNtx8cvConnectionStore implements Ntx8cvConnectionStore {
  static const _inputDeviceNameKey = 'ntx8cvInputMidiDevice';
  static const _inputDeviceIdKey = 'ntx8cvInputMidiDeviceId';
  static const _outputDeviceNameKey = 'ntx8cvOutputMidiDevice';
  static const _outputDeviceIdKey = 'ntx8cvOutputMidiDeviceId';
  static const _deviceIdKey = 'ntx8cvSysExDeviceId';

  SharedPreferencesNtx8cvConnectionStore({
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  @override
  Future<Ntx8cvSavedConnection> load() async {
    final preferences = await _preferences;
    final savedDeviceId = preferences.getInt(_deviceIdKey);
    return Ntx8cvSavedConnection(
      inputDeviceName: preferences.getString(_inputDeviceNameKey),
      inputDeviceId: preferences.getString(_inputDeviceIdKey),
      outputDeviceName: preferences.getString(_outputDeviceNameKey),
      outputDeviceId: preferences.getString(_outputDeviceIdKey),
      deviceId:
          savedDeviceId != null && savedDeviceId >= 0 && savedDeviceId <= 126
          ? savedDeviceId
          : 0,
    );
  }

  @override
  Future<void> save(Ntx8cvSavedConnection selection) async {
    final preferences = await _preferences;
    if (selection.inputDeviceName == null) {
      await preferences.remove(_inputDeviceNameKey);
    } else {
      await preferences.setString(
        _inputDeviceNameKey,
        selection.inputDeviceName!,
      );
    }
    if (selection.inputDeviceId == null) {
      await preferences.remove(_inputDeviceIdKey);
    } else {
      await preferences.setString(_inputDeviceIdKey, selection.inputDeviceId!);
    }
    if (selection.outputDeviceName == null) {
      await preferences.remove(_outputDeviceNameKey);
    } else {
      await preferences.setString(
        _outputDeviceNameKey,
        selection.outputDeviceName!,
      );
    }
    if (selection.outputDeviceId == null) {
      await preferences.remove(_outputDeviceIdKey);
    } else {
      await preferences.setString(
        _outputDeviceIdKey,
        selection.outputDeviceId!,
      );
    }
    await preferences.setInt(_deviceIdKey, selection.deviceId);
  }
}

/// Opens and closes one independently selected NTX-8CV MIDI endpoint pair.
///
/// It intentionally has no dependency on [DistingCubit] or its connection.
abstract interface class Ntx8cvMidiConnection {
  Future<List<Ntx8cvMidiEndpoint>> listDevices();

  Stream<MidiSetupChange>? get setupChanges;

  Future<Ntx8cvMidiTransport> open({
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  });

  Future<void> close({
    required Ntx8cvMidiTransport transport,
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  });
}

/// The production MIDI connection used only by the NTX-8CV add-on.
class NativeNtx8cvMidiConnection implements Ntx8cvMidiConnection {
  NativeNtx8cvMidiConnection({MidiCommand? midiCommand})
    : _midiCommand = midiCommand ?? createNativeMidiCommand();

  final MidiCommand _midiCommand;
  final Map<String, MidiDevice> _nativeDevicesById = {};

  @override
  Stream<MidiSetupChange>? get setupChanges => _midiCommand.onMidiSetupChanged;

  @override
  Future<List<Ntx8cvMidiEndpoint>> listDevices() async {
    final devices = List<MidiDevice>.of(await _midiCommand.devices ?? const []);
    _nativeDevicesById
      ..clear()
      ..addEntries(devices.map((device) => MapEntry(device.id, device)));
    return List.unmodifiable(
      devices.map(
        (device) => Ntx8cvMidiEndpoint(
          id: device.id,
          name: device.name,
          hasInput: device.inputPorts.isNotEmpty,
          hasOutput: device.outputPorts.isNotEmpty,
        ),
      ),
    );
  }

  @override
  Future<Ntx8cvMidiTransport> open({
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    final nativeInputDevice = _nativeDevice(inputDevice);
    final nativeOutputDevice = _nativeDevice(outputDevice);
    final transport = _Ntx8cvMidiCommandTransport(
      midiCommand: _midiCommand,
      inputDevice: nativeInputDevice,
      outputDevice: nativeOutputDevice,
    );
    try {
      await transport.open();
      return transport;
    } catch (_) {
      await transport.close();
      _midiCommand.disconnectDevice(nativeInputDevice);
      if (nativeInputDevice.id != nativeOutputDevice.id) {
        _midiCommand.disconnectDevice(nativeOutputDevice);
      }
      rethrow;
    }
  }

  @override
  Future<void> close({
    required Ntx8cvMidiTransport transport,
    required Ntx8cvMidiEndpoint inputDevice,
    required Ntx8cvMidiEndpoint outputDevice,
  }) async {
    if (transport is _Ntx8cvMidiCommandTransport) {
      await transport.close();
      _midiCommand.disconnectDevice(transport._inputDevice);
      if (transport._inputDevice.id != transport._outputDevice.id) {
        _midiCommand.disconnectDevice(transport._outputDevice);
      }
    }
  }

  MidiDevice _nativeDevice(Ntx8cvMidiEndpoint endpoint) {
    final device = _nativeDevicesById[endpoint.id];
    if (device != null) return device;
    throw StateError('MIDI endpoint ${endpoint.name} is no longer available.');
  }
}

/// Bridges the selected native MIDI endpoints to an NTX-8CV SysEx session.
///
/// Incoming packets are filtered by the selected input device before complete
/// SysEx frames are exposed. Outgoing packets always name the selected output
/// device explicitly, so this transport cannot send to the disting NT target.
class _Ntx8cvMidiCommandTransport implements Ntx8cvMidiTransport {
  _Ntx8cvMidiCommandTransport({
    required this._midiCommand,
    required this._inputDevice,
    required this._outputDevice,
  });

  final MidiCommand _midiCommand;
  final MidiDevice _inputDevice;
  final MidiDevice _outputDevice;
  final StreamController<Uint8List> _receivedController =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<MidiPacket>? _subscription;
  final List<int> _sysExBuffer = [];
  bool _isOpen = false;
  bool _isClosed = false;

  @override
  Stream<Uint8List> get receivedPackets => _receivedController.stream;

  Future<void> open() async {
    final incoming = _midiCommand.onMidiPacketReceived;
    if (incoming == null) {
      throw UnsupportedError('MIDI input is unavailable on this platform.');
    }
    _subscription = incoming.listen(_handlePacket, onError: _handleError);
    try {
      await _midiCommand.connectToDevice(_inputDevice);
      if (_inputDevice.id != _outputDevice.id) {
        await _midiCommand.connectToDevice(_outputDevice);
      }
      _isOpen = true;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<void> send(Uint8List packet) async {
    if (!_isOpen || _isClosed) {
      throw StateError('The NTX-8CV MIDI transport is not open.');
    }
    _midiCommand.sendData(packet, deviceId: _outputDevice.id);
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _subscription?.cancel();
    await _receivedController.close();
  }

  void _handlePacket(MidiPacket packet) {
    if (_isClosed || packet.device.id != _inputDevice.id) return;
    for (final byte in packet.data) {
      if (byte == 0xF0) {
        _sysExBuffer
          ..clear()
          ..add(byte);
        continue;
      }
      if (_sysExBuffer.isEmpty) continue;
      _sysExBuffer.add(byte);
      if (byte == 0xF7) {
        _receivedController.add(Uint8List.fromList(_sysExBuffer));
        _sysExBuffer.clear();
      }
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (!_isClosed) {
      _receivedController.addError(error, stackTrace);
    }
  }
}
