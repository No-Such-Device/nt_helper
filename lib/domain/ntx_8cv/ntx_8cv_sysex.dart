import 'dart:async';
import 'dart:typed_data';

/// The SysEx manufacturer ID assigned to Expert Sleepers.
const List<int> kNtx8cvManufacturerId = [0x00, 0x21, 0x27];

/// The product byte that identifies NTX-8CV SysEx, distinct from disting NT.
const int kNtx8cvProductByte = 0x6A;

/// The transient broadcast address. It must not be persisted as a device ID.
const int kNtx8cvAnyDeviceId = 0x7F;

const int _sysExStart = 0xF0;
const int _sysExEnd = 0xF7;
const int _deviceInformationRequest = 0x22;
const int _setting = 0x31;
const int _deviceInformationResponse = 0x32;
const int _reboot = 0x7F;

/// Encodes and decodes the NTX-8CV's product-specific SysEx frames.
///
/// This intentionally does not reuse the disting NT parser: an NTX-8CV frame
/// carries product byte [kNtx8cvProductByte], not the disting NT's `0x6D`.
/// Protocol framing was audited against `expertsleepersltd/NTX-8CV` main at
/// commit `6addf424c454aac20b26661d00384e6292401b18`.
class Ntx8cvSysExCodec {
  const Ntx8cvSysExCodec();

  Uint8List requestDeviceInformation({required int deviceId}) =>
      _frame(deviceId, _deviceInformationRequest);

  Uint8List readSetting({required int deviceId, required int settingId}) =>
      _frame(deviceId, _setting, [settingId]);

  Uint8List writeSetting({
    required int deviceId,
    required int settingId,
    required int value,
  }) => _frame(deviceId, _deviceInformationResponse, [settingId, value]);

  Uint8List reboot({required int deviceId}) => _frame(deviceId, _reboot);

  /// Decodes a complete, standalone NTX-8CV frame.
  ///
  /// `null` means the frame is malformed or belongs to another device family.
  /// Unknown but well-formed NTX-8CV commands are preserved as
  /// [Ntx8cvUnknownMessage] so callers can safely ignore them.
  Ntx8cvIncomingMessage? decode(Uint8List packet) {
    if (packet.length < 8 ||
        packet.first != _sysExStart ||
        packet.last != _sysExEnd) {
      return null;
    }
    if (packet[1] != kNtx8cvManufacturerId[0] ||
        packet[2] != kNtx8cvManufacturerId[1] ||
        packet[3] != kNtx8cvManufacturerId[2] ||
        packet[4] != kNtx8cvProductByte ||
        !_areDataBytes(packet, 1, packet.length - 1)) {
      return null;
    }

    final deviceId = packet[5];
    final command = packet[6];
    final payload = Uint8List.fromList(packet.sublist(7, packet.length - 1));
    final rawBytes = Uint8List.fromList(packet);

    switch (command) {
      case _setting:
        if (payload.length != 2) return null;
        return Ntx8cvSettingValue(
          deviceId: deviceId,
          settingId: payload[0],
          value: payload[1],
          rawBytes: rawBytes,
        );
      case _deviceInformationResponse:
        // The firmware version is an opaque NUL-terminated ASCII field. Keep
        // decoding multiple fields for forward compatibility without claiming
        // a grammar for any additional values.
        if (payload.isEmpty || payload.last != 0) return null;
        return Ntx8cvDeviceInformation(
          deviceId: deviceId,
          textFields: _decodeNulTerminatedFields(payload),
          rawBytes: rawBytes,
        );
      default:
        return Ntx8cvUnknownMessage(
          deviceId: deviceId,
          command: command,
          payload: payload,
          rawBytes: rawBytes,
        );
    }
  }

  Uint8List _frame(int deviceId, int command, [List<int> payload = const []]) {
    _validateDataByte(deviceId, 'deviceId');
    _validateDataByte(command, 'command');
    for (final value in payload) {
      _validateDataByte(value, 'payload value');
    }
    return Uint8List.fromList([
      _sysExStart,
      ...kNtx8cvManufacturerId,
      kNtx8cvProductByte,
      deviceId,
      command,
      ...payload,
      _sysExEnd,
    ]);
  }

  static bool _areDataBytes(Uint8List bytes, int start, int endExclusive) {
    for (var index = start; index < endExclusive; index++) {
      if (bytes[index] > kNtx8cvAnyDeviceId) return false;
    }
    return true;
  }

  static void _validateDataByte(int value, String name) {
    if (value < 0 || value > kNtx8cvAnyDeviceId) {
      throw ArgumentError.value(value, name, 'must be a MIDI 7-bit value');
    }
  }

  static List<String> _decodeNulTerminatedFields(Uint8List payload) {
    if (payload.isEmpty) return const [];

    final fields = <String>[];
    var fieldStart = 0;
    for (var index = 0; index < payload.length; index++) {
      if (payload[index] == 0) {
        fields.add(String.fromCharCodes(payload.sublist(fieldStart, index)));
        fieldStart = index + 1;
      }
    }
    return List.unmodifiable(fields);
  }
}

/// A complete NTX-8CV message received from the selected MIDI input.
sealed class Ntx8cvIncomingMessage {
  const Ntx8cvIncomingMessage({required this.deviceId, required this.rawBytes});

  final int deviceId;
  final Uint8List rawBytes;
}

/// Device information returned in response to command `0x22` using `0x32`.
class Ntx8cvDeviceInformation extends Ntx8cvIncomingMessage {
  const Ntx8cvDeviceInformation({
    required super.deviceId,
    required this.textFields,
    required super.rawBytes,
  });

  /// Opaque NUL-terminated text fields reported by the device.
  final List<String> textFields;

  String? get firmwareText => textFields.isEmpty ? null : textFields.first;
  String? get serialText => textFields.length < 2 ? null : textFields[1];
}

/// A response to a setting read (`0x31 <setting-id> <value>`).
class Ntx8cvSettingValue extends Ntx8cvIncomingMessage {
  const Ntx8cvSettingValue({
    required super.deviceId,
    required this.settingId,
    required this.value,
    required super.rawBytes,
  });

  final int settingId;
  final int value;
}

/// A well-formed NTX-8CV message whose command is not yet modeled.
class Ntx8cvUnknownMessage extends Ntx8cvIncomingMessage {
  const Ntx8cvUnknownMessage({
    required super.deviceId,
    required this.command,
    required this.payload,
    required super.rawBytes,
  });

  final int command;
  final Uint8List payload;
}

/// The independent MIDI transport used by an NTX-8CV session.
///
/// Feature-layer code supplies a transport bound to its chosen NTX-8CV input
/// and output endpoints; it never shares the disting NT transport.
abstract interface class Ntx8cvMidiTransport {
  Stream<Uint8List> get receivedPackets;

  Future<void> send(Uint8List packet);
}

/// Reports that a requested NTX-8CV response did not arrive in time.
class Ntx8cvTimeoutException implements Exception {
  const Ntx8cvTimeoutException({
    required this.operation,
    required this.timeout,
  });

  final String operation;
  final Duration timeout;

  @override
  String toString() =>
      'Ntx8cvTimeoutException($operation after ${timeout.inMilliseconds}ms)';
}

/// Reports a receive-stream failure while waiting for an NTX-8CV response.
class Ntx8cvTransportException implements Exception {
  const Ntx8cvTransportException(this.cause);

  final Object cause;

  @override
  String toString() => 'Ntx8cvTransportException($cause)';
}

/// Serializes NTX-8CV requests and matches responses for one selected device.
///
/// The session makes no implicit retries. A setting is only confirmed by
/// [writeAndConfirmSetting], which reads the setting after the write and waits
/// for a matching value.
class Ntx8cvSession {
  Ntx8cvSession({
    required this._transport,
    required this.deviceId,
    this._codec = const Ntx8cvSysExCodec(),
    this.timeout = const Duration(seconds: 1),
  }) {
    _validateDeviceId(deviceId);
    if (timeout < Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must not be negative');
    }
    _subscription = _transport.receivedPackets.listen(
      _handlePacket,
      onError: _handleStreamError,
    );
  }

  final Ntx8cvMidiTransport _transport;
  final Ntx8cvSysExCodec _codec;
  final int deviceId;
  final Duration timeout;
  late final StreamSubscription<Uint8List> _subscription;
  _PendingNtx8cvRequest? _pending;
  bool _isClosed = false;

  Future<Ntx8cvDeviceInformation> requestDeviceInformation() async {
    final response = await _sendAndAwait(
      packet: _codec.requestDeviceInformation(deviceId: deviceId),
      operation: 'device information',
      matches: (message) => message is Ntx8cvDeviceInformation,
    );
    return response as Ntx8cvDeviceInformation;
  }

  Future<Ntx8cvSettingValue> readSetting({required int settingId}) async {
    _validateDataByte(settingId, 'settingId');
    final response = await _sendAndAwait(
      packet: _codec.readSetting(deviceId: deviceId, settingId: settingId),
      operation:
          'read setting 0x${settingId.toRadixString(16).padLeft(2, '0').toUpperCase()}',
      matches: (message) =>
          message is Ntx8cvSettingValue && message.settingId == settingId,
    );
    return response as Ntx8cvSettingValue;
  }

  /// Sends a setting write. The protocol has no write acknowledgement.
  Future<void> writeSetting({
    required int settingId,
    required int value,
  }) async {
    _ensureOpen();
    _validateDataByte(settingId, 'settingId');
    _validateDataByte(value, 'value');
    await _transport.send(
      _codec.writeSetting(
        deviceId: deviceId,
        settingId: settingId,
        value: value,
      ),
    );
  }

  /// Writes [value] then confirms it only with a matching setting readback.
  Future<Ntx8cvSettingValue> writeAndConfirmSetting({
    required int settingId,
    required int value,
  }) async {
    await writeSetting(settingId: settingId, value: value);
    final readback = await readSetting(settingId: settingId);
    if (readback.value != value) {
      throw StateError(
        'NTX-8CV readback for setting 0x${settingId.toRadixString(16)} '
        'was ${readback.value}, expected $value.',
      );
    }
    return readback;
  }

  Future<void> reboot() async {
    _ensureOpen();
    await _transport.send(_codec.reboot(deviceId: deviceId));
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    final pending = _pending;
    _pending = null;
    pending?.cancelTimeout();
    if (pending != null && !pending.isComplete) {
      pending.completeError(StateError('The NTX-8CV session was closed.'));
    }
    await _subscription.cancel();
  }

  Future<Ntx8cvIncomingMessage> _sendAndAwait({
    required Uint8List packet,
    required String operation,
    required bool Function(Ntx8cvIncomingMessage message) matches,
  }) async {
    _ensureOpen();
    if (_pending != null) {
      throw StateError('An NTX-8CV request is already waiting for a response.');
    }

    final pending = _PendingNtx8cvRequest(
      operation: operation,
      matches: matches,
    );
    _pending = pending;
    try {
      await _transport.send(packet);
    } catch (_) {
      if (identical(_pending, pending)) {
        _pending = null;
      }
      pending.cancelTimeout();
      rethrow;
    }

    if (!pending.isComplete) {
      pending.startTimeout(timeout, () {
        if (!identical(_pending, pending)) return;
        _pending = null;
        pending.completeError(
          Ntx8cvTimeoutException(operation: operation, timeout: timeout),
        );
      });
    }
    return pending.future;
  }

  void _handlePacket(Uint8List packet) {
    final pending = _pending;
    final message = _codec.decode(packet);
    if (pending == null || message == null || message.deviceId != deviceId) {
      return;
    }
    if (!pending.matches(message)) return;

    _pending = null;
    pending.cancelTimeout();
    pending.complete(message);
  }

  void _handleStreamError(Object error, StackTrace stackTrace) {
    final pending = _pending;
    if (pending == null) return;

    _pending = null;
    pending.cancelTimeout();
    pending.completeError(Ntx8cvTransportException(error), stackTrace);
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('The NTX-8CV session is closed.');
    }
  }

  static void _validateDeviceId(int value) =>
      _validateDataByte(value, 'deviceId');

  static void _validateDataByte(int value, String name) {
    if (value < 0 || value > kNtx8cvAnyDeviceId) {
      throw ArgumentError.value(value, name, 'must be a MIDI 7-bit value');
    }
  }
}

class _PendingNtx8cvRequest {
  _PendingNtx8cvRequest({required this.operation, required this.matches});

  final String operation;
  final bool Function(Ntx8cvIncomingMessage message) matches;
  final Completer<Ntx8cvIncomingMessage> _completer = Completer();
  Timer? _timer;

  bool get isComplete => _completer.isCompleted;
  Future<Ntx8cvIncomingMessage> get future => _completer.future;

  void startTimeout(Duration timeout, void Function() onTimeout) {
    _timer = Timer(timeout, onTimeout);
  }

  void cancelTimeout() => _timer?.cancel();

  void complete(Ntx8cvIncomingMessage message) {
    if (!_completer.isCompleted) _completer.complete(message);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}
