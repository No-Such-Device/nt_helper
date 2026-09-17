// disting_message_scheduler.dart - Simple Sequential Scheduler
// -----------------------------------------------------------------------------
// Redesigned for reliability and performance:
// • Simple state machine: idle → sending → waiting → idle
// • Sequential processing: one request at a time
// • Single timer approach: no complex timer chains
// • Immediate processing when idle
// • Retains device filtering and sysEx ID support
// • Auto-recovery from MIDI stream corruption
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

// Domain classes
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/request_key.dart';
import 'package:nt_helper/domain/sd_card_operation.dart';
import 'package:nt_helper/domain/sysex/response_factory.dart';
import 'package:nt_helper/domain/sysex/responses/parameter_pages_response.dart';
import 'package:nt_helper/domain/sysex/sysex_parser.dart';

// -----------------------------------------------------------------------------
// Response expectation enum
// -----------------------------------------------------------------------------

enum ResponseExpectation {
  required, // Must get a response or throw TimeoutException
  optional, // OK to get null (no response)
  none, // Fire-and-forget
}

enum ResponseAttributionPolicy { bestEffort, failWhenAmbiguous }

final class AmbiguousResponseAttributionException extends StateError {
  AmbiguousResponseAttributionException()
    : super(
        'Cannot establish response attribution because an earlier request may '
        'still respond.',
      );
}

// -----------------------------------------------------------------------------
// Scheduler state
// -----------------------------------------------------------------------------

typedef CcCallback = void Function(int channel, int cc, int value);

enum _SchedulerState { idle, sending, waitingForResponse }

// -----------------------------------------------------------------------------
// Internal request representation
// -----------------------------------------------------------------------------

class _ScheduledRequest {
  _ScheduledRequest({
    required this.id,
    required this.packet,
    required this.key,
    required this.expectation,
    required this.completer,
    required this.timeout,
    required this.maxRetries,
    required this.retryDelay,
    required this.attributionPolicy,
  });

  final int id;
  final Uint8List packet;
  final RequestKey key;
  final ResponseExpectation expectation;
  final Completer<dynamic> completer;
  final Duration timeout;
  final int maxRetries;
  final Duration retryDelay;
  final ResponseAttributionPolicy attributionPolicy;

  int attemptCount = 0;
  int transferErrorRecoveryCount = 0;
  int sentRequestCount = 0;
  int matchingResponseCount = 0;
  bool attributionStarted = false;
  Timer? timeoutTimer;

  /// Stopwatch to measure round-trip time from send to response
  final Stopwatch stopwatch = Stopwatch();

  void startTimeout(void Function() onTimeout) {
    timeoutTimer?.cancel();
    if (expectation != ResponseExpectation.none) {
      timeoutTimer = Timer(timeout, onTimeout);
    }
  }

  void dispose() => timeoutTimer?.cancel();
}

// -----------------------------------------------------------------------------
// Response Demultiplexer
// -----------------------------------------------------------------------------

class _ActiveHandler {
  _ActiveHandler({required this.key, required this.onMatch});

  final RequestKey key;
  final void Function(DistingNTParsedMessage) onMatch;
}

class _ExpiredHandler {
  _ExpiredHandler({required this.key, required this.expiredAt});

  final RequestKey key;
  final DateTime expiredAt;
}

final class _AttributionEndpointKey {
  const _AttributionEndpointKey({
    required this.inputDeviceId,
    required this.sysExId,
  });

  final String inputDeviceId;
  final int sysExId;

  @override
  bool operator ==(Object other) =>
      other is _AttributionEndpointKey &&
      inputDeviceId == other.inputDeviceId &&
      sysExId == other.sysExId;

  @override
  int get hashCode => Object.hash(inputDeviceId, sysExId);
}

final class _UnattributedResponse {
  const _UnattributedResponse({required this.key, required this.createdAt});

  final RequestKey key;
  final DateTime createdAt;
}

/// Tracks response debt for requests whose wire protocol has no transaction ID.
///
/// The tracker is shared by schedulers using the same MIDI command and endpoint,
/// so disposing and replacing a manager cannot make an old packet attributable
/// to the replacement. Only callers opting into strict attribution use it.
final class _StrictResponseAttribution {
  static const _responseDebtMaxAge = Duration(seconds: 30);

  _ScheduledRequest? _activeRequest;
  final List<_UnattributedResponse> _responseDebt = [];

  bool begin(_ScheduledRequest request) {
    _removeExpiredDebt();
    if (_activeRequest != null || _hasMatchingDebt(request.key)) {
      return false;
    }
    _activeRequest = request;
    return true;
  }

  void markSent(_ScheduledRequest request) {
    if (identical(_activeRequest, request)) {
      request.sentRequestCount++;
    }
  }

  void markResponse(_ScheduledRequest request) {
    if (identical(_activeRequest, request)) {
      request.matchingResponseCount++;
    }
  }

  void finish(_ScheduledRequest request) {
    if (!identical(_activeRequest, request)) return;

    final unresolved = request.sentRequestCount - request.matchingResponseCount;
    final now = DateTime.now();
    for (var i = 0; i < unresolved; i++) {
      _responseDebt.add(
        _UnattributedResponse(key: request.key, createdAt: now),
      );
    }
    _activeRequest = null;
  }

  bool consumeUnattributed(DistingNTParsedMessage parsed) {
    _removeExpiredDebt();
    if (_activeRequest != null) return false;

    final debtIndex = _responseDebt.indexWhere(
      (response) => response.key.matchesStrict(parsed),
    );
    if (debtIndex == -1) return false;

    _responseDebt.removeAt(debtIndex);
    return true;
  }

  bool _hasMatchingDebt(RequestKey key) {
    return _responseDebt.any((response) => response.key == key);
  }

  void _removeExpiredDebt() {
    final now = DateTime.now();
    _responseDebt.removeWhere(
      (response) => now.difference(response.createdAt) > _responseDebtMaxAge,
    );
  }
}

final Expando<Map<_AttributionEndpointKey, _StrictResponseAttribution>>
_strictAttributionByMidi = Expando('Disting strict response attribution');

_StrictResponseAttribution _strictAttributionFor({
  required MidiCommand midi,
  required MidiDevice inputDevice,
  required int sysExId,
}) {
  final endpointStates = _strictAttributionByMidi[midi] ??= {};
  final endpoint = _AttributionEndpointKey(
    inputDeviceId: inputDevice.id,
    sysExId: sysExId,
  );
  return endpointStates.putIfAbsent(endpoint, _StrictResponseAttribution.new);
}

class _ResponseDemux {
  _ResponseDemux(this._strictAttribution);

  final _StrictResponseAttribution _strictAttribution;
  _ActiveHandler? _activeHandler;
  final List<_ExpiredHandler> _expiredHandlers = [];
  final List<void Function(DistingNTParsedMessage)> _observers = [];

  int staleResponsesAbsorbed = 0;
  int unmatchedResponsesDiscarded = 0;

  int get expiredHandlerCount => _expiredHandlers.length;

  static const int _maxExpiredHandlers = 20;
  static const Duration _expiredHandlerMaxAge = Duration(seconds: 30);

  void registerActive(
    RequestKey key,
    void Function(DistingNTParsedMessage) onMatch,
  ) {
    _activeHandler = _ActiveHandler(key: key, onMatch: onMatch);
  }

  void expireActive() {
    final handler = _activeHandler;
    if (handler != null) {
      _activeHandler = null;
      _expiredHandlers.add(
        _ExpiredHandler(key: handler.key, expiredAt: DateTime.now()),
      );
    }
  }

  void discardActive() {
    _activeHandler = null;
  }

  void addObserver(void Function(DistingNTParsedMessage) observer) {
    _observers.add(observer);
  }

  void removeObserver(void Function(DistingNTParsedMessage) observer) {
    _observers.remove(observer);
  }

  void dispatch(DistingNTParsedMessage parsed) {
    // 1. Notify all passive observers before any matching
    for (final observer in _observers) {
      try {
        observer(parsed);
      } catch (_) {}
    }

    // 2. Strict requests carry response debt across scheduler replacement.
    if (_strictAttribution.consumeUnattributed(parsed)) {
      staleResponsesAbsorbed++;
      return;
    }

    // 3. Check active handler first — active request always takes priority
    if (_activeHandler != null && _activeHandler!.key.matches(parsed)) {
      final handler = _activeHandler!;
      _activeHandler = null;
      handler.onMatch(parsed);
      return;
    }

    // 4. Check expired handlers (oldest first) — absorb stale responses
    final expiredMatch = _expiredHandlers.indexWhere(
      (h) => h.key.matchesStrict(parsed),
    );
    if (expiredMatch != -1) {
      _expiredHandlers.removeAt(expiredMatch);
      staleResponsesAbsorbed++;
      return;
    }

    // 5. No match — discard cleanly
    unmatchedResponsesDiscarded++;

    // Lazy cleanup of old expired handlers
    _cleanupExpiredHandlers();
  }

  void _cleanupExpiredHandlers() {
    if (_expiredHandlers.isEmpty) return;

    final now = DateTime.now();
    _expiredHandlers.removeWhere(
      (h) => now.difference(h.expiredAt) > _expiredHandlerMaxAge,
    );

    // Cap the list size
    while (_expiredHandlers.length > _maxExpiredHandlers) {
      _expiredHandlers.removeAt(0);
    }
  }

  void clear() {
    _activeHandler = null;
    _expiredHandlers.clear();
  }
}

// -----------------------------------------------------------------------------
// RTT Statistics per message type
// -----------------------------------------------------------------------------

class _RttStats {
  int count = 0;
  int timeouts = 0;
  Duration total = Duration.zero;
  Duration min = const Duration(days: 1);
  Duration max = Duration.zero;
  Duration? last;

  void record(Duration rtt) {
    count++;
    total += rtt;
    last = rtt;
    if (rtt < min) min = rtt;
    if (rtt > max) max = rtt;
  }

  void recordTimeout() {
    timeouts++;
  }

  double get avgMs => count > 0 ? total.inMicroseconds / count / 1000 : 0;
  double get minMs => count > 0 ? min.inMicroseconds / 1000 : 0;
  double get maxMs => count > 0 ? max.inMicroseconds / 1000 : 0;
  double get lastMs => last != null ? last!.inMicroseconds / 1000 : 0;

  Map<String, dynamic> toJson() => {
    'count': count,
    'timeouts': timeouts,
    'avgMs': avgMs.toStringAsFixed(2),
    'minMs': minMs.toStringAsFixed(2),
    'maxMs': maxMs.toStringAsFixed(2),
    'lastMs': lastMs.toStringAsFixed(2),
  };
}

// -----------------------------------------------------------------------------
// Simple Sequential Message Scheduler
// -----------------------------------------------------------------------------

class DistingMessageScheduler {
  DistingMessageScheduler({
    required MidiCommand midiCommand,
    required MidiDevice inputDevice,
    required MidiDevice outputDevice,
    required int sysExId,
    Duration messageInterval = const Duration(milliseconds: 50),
    Duration defaultTimeout = const Duration(milliseconds: 1000),
    this.defaultMaxRetries = 5,
    Duration defaultRetryDelay = Duration.zero,
  }) : _midi = midiCommand,
       _inputDevice = inputDevice,
       _outputDevice = outputDevice,
       _sysExId = sysExId,
       messageInterval = _normalizeDuration(messageInterval),
       defaultTimeout = _normalizeDuration(defaultTimeout),
       defaultRetryDelay = _normalizeDuration(defaultRetryDelay) {
    _strictAttribution = _strictAttributionFor(
      midi: _midi,
      inputDevice: _inputDevice,
      sysExId: _sysExId,
    );
    _demux = _ResponseDemux(_strictAttribution);
    _subscription = _midi.onMidiPacketReceived?.listen(
      _handleIncomingPacket,
      onError: _handleSubscriptionError,
      onDone: _handleSubscriptionDone,
      cancelOnError: false,
    );
    if (_subscription == null) {
      _subscriptionActive = false;
    }
  }

  // MIDI and device configuration
  final MidiCommand _midi;
  final MidiDevice _inputDevice;
  final MidiDevice _outputDevice;
  final int _sysExId;

  static const bool _diagnosticsEnabled = true;
  static int _nextRequestId = 0;
  static const int _maxTransferErrorRecoveries = 1;

  // Timing configuration
  final Duration messageInterval;
  final Duration defaultTimeout;
  final int defaultMaxRetries;
  final Duration defaultRetryDelay;

  // State management
  _SchedulerState _state = _SchedulerState.idle;
  final Queue<_ScheduledRequest> _queue = Queue();
  _ScheduledRequest? _currentRequest;
  Timer? _nextProcessTimer;
  Timer? _retryTimer;
  StreamSubscription? _subscription;

  // Response demultiplexer
  late final _StrictResponseAttribution _strictAttribution;
  late final _ResponseDemux _demux;

  // CC callback for receiving MIDI CC messages from the device
  CcCallback? _ccCallback;

  void setCcCallback(CcCallback callback) {
    _ccCallback = callback;
  }

  void clearCcCallback() {
    _ccCallback = null;
  }

  // Diagnostic counters
  int _totalPacketsReceived = 0;
  int _sysexPacketsReceived = 0;
  int _nonSysexPacketsReceived = 0;
  int _ccMessagesDispatched = 0;
  int _packetsFromWrongDevice = 0;
  DateTime? _lastPacketTime;
  bool _subscriptionActive = true;
  String? _lastSubscriptionError;

  // RTT (Round-Trip Time) tracking - overall stats
  int _totalRequestsCompleted = 0;
  int _totalRequestsTimedOut = 0;
  Duration _totalRtt = Duration.zero;
  Duration _minRtt = const Duration(days: 1); // Start high
  Duration _maxRtt = Duration.zero;
  Duration? _lastRtt;

  // RTT tracking per message type
  final Map<DistingNTRespMessageType, _RttStats> _rttByMessageType = {};

  // Track slow Algorithm Info requests by algorithm index (for debugging)
  static const Duration _slowThreshold = Duration(milliseconds: 50);
  final Map<int, Duration> _slowAlgorithmInfoByIndex = {};

  // Consecutive timeout tracking for stream health detection
  int _consecutiveTimeouts = 0;
  static const int _maxConsecutiveTimeoutsBeforeRecovery = 3;

  // Track if device connection is suspected broken (to skip risky disconnect)
  bool _deviceConnectionSuspectedBroken = false;

  // SysEx buffering for handling split messages (common on Windows)
  final List<int> _sysExBuffer = [];
  bool _isBufferingSysEx = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  static Duration _normalizeDuration(Duration duration) {
    if (duration.isNegative) {
      return Duration.zero;
    }
    return duration;
  }

  /// Returns diagnostic information about the scheduler's MIDI stream health.
  Map<String, dynamic> getDiagnostics() {
    final now = DateTime.now();
    final timeSinceLastPacket = _lastPacketTime != null
        ? now.difference(_lastPacketTime!).inMilliseconds
        : -1;

    final avgRttMs = _totalRequestsCompleted > 0
        ? (_totalRtt.inMicroseconds / _totalRequestsCompleted / 1000)
              .toStringAsFixed(2)
        : 'N/A';

    return {
      'subscriptionActive': _subscriptionActive,
      'lastSubscriptionError': _lastSubscriptionError,
      'totalPacketsReceived': _totalPacketsReceived,
      'sysexPacketsReceived': _sysexPacketsReceived,
      'nonSysexPacketsReceived': _nonSysexPacketsReceived,
      'ccMessagesDispatched': _ccMessagesDispatched,
      'ccCallbackRegistered': _ccCallback != null,
      'packetsFromWrongDevice': _packetsFromWrongDevice,
      'timeSinceLastPacketMs': timeSinceLastPacket,
      'currentState': _state.name,
      'queueLength': _queue.length,
      'hasCurrentRequest': _currentRequest != null,
      'currentRequestCompleted':
          _currentRequest?.completer.isCompleted ?? false,
      // RTT statistics
      'rttRequestsCompleted': _totalRequestsCompleted,
      'rttRequestsTimedOut': _totalRequestsTimedOut,
      'rttLastMs': _lastRtt?.inMicroseconds != null
          ? (_lastRtt!.inMicroseconds / 1000).toStringAsFixed(2)
          : 'N/A',
      'rttAvgMs': avgRttMs,
      'rttMinMs': _totalRequestsCompleted > 0
          ? (_minRtt.inMicroseconds / 1000).toStringAsFixed(2)
          : 'N/A',
      'rttMaxMs': _totalRequestsCompleted > 0
          ? (_maxRtt.inMicroseconds / 1000).toStringAsFixed(2)
          : 'N/A',
      // Response demux diagnostics
      'staleResponsesAbsorbed': _demux.staleResponsesAbsorbed,
      'unmatchedResponsesDiscarded': _demux.unmatchedResponsesDiscarded,
      'expiredHandlerCount': _demux.expiredHandlerCount,
    };
  }

  /// Returns RTT statistics broken down by message type.
  Map<String, Map<String, dynamic>> getRttStatsByMessageType() {
    final result = <String, Map<String, dynamic>>{};
    for (final entry in _rttByMessageType.entries) {
      result[entry.key.name] = entry.value.toJson();
    }
    return result;
  }

  /// Returns slow Algorithm Info requests by algorithm index.
  /// Only includes requests that exceeded the slow threshold (50ms).
  /// Returns map of algorithmIndex -> duration in milliseconds.
  Map<int, double> getSlowAlgorithmInfo() {
    return _slowAlgorithmInfoByIndex.map(
      (index, duration) => MapEntry(index, duration.inMicroseconds / 1000),
    );
  }

  /// Records an RTT measurement for both overall and per-message-type stats.
  void _recordRtt(
    Duration rtt,
    DistingNTRespMessageType messageType, {
    int? libraryIndex,
  }) {
    // Update overall stats
    _totalRequestsCompleted++;
    _totalRtt += rtt;
    _lastRtt = rtt;
    if (rtt < _minRtt) _minRtt = rtt;
    if (rtt > _maxRtt) _maxRtt = rtt;

    // Update per-message-type stats
    _rttByMessageType.putIfAbsent(messageType, () => _RttStats());
    _rttByMessageType[messageType]!.record(rtt);

    // Track slow Algorithm Info requests by library index
    if (messageType == DistingNTRespMessageType.respAlgorithmInfo &&
        libraryIndex != null &&
        rtt > _slowThreshold) {
      // Keep the slowest time for each library index
      final existing = _slowAlgorithmInfoByIndex[libraryIndex];
      if (existing == null || rtt > existing) {
        _slowAlgorithmInfoByIndex[libraryIndex] = rtt;
      }
    }
  }

  /// Records a timeout for stats tracking.
  void _recordTimeout(DistingNTRespMessageType? messageType) {
    _totalRequestsTimedOut++;
    // Track timeout per message type if known
    if (messageType != null) {
      _rttByMessageType.putIfAbsent(messageType, () => _RttStats());
      _rttByMessageType[messageType]!.recordTimeout();
    }
  }

  /// Attempts to re-establish the MIDI subscription if it's dead.
  void tryReconnectSubscription() {
    _subscription?.cancel();
    _subscriptionActive = false;

    _subscription = _midi.onMidiPacketReceived?.listen(
      _handleIncomingPacket,
      onError: _handleSubscriptionError,
      onDone: _handleSubscriptionDone,
      cancelOnError: false,
    );

    if (_subscription != null) {
      _subscriptionActive = true;
      _lastSubscriptionError = null;
    }
  }

  /// Resets internal MIDI state without full disconnect/reconnect.
  /// Clears buffers, resets counters, and re-subscribes to the stream.
  /// Does NOT affect the current request - caller is responsible for that.
  void _resetInternalState() {
    // Clear any partial SysEx data
    _sysExBuffer.clear();
    _isBufferingSysEx = false;

    // Reset consecutive timeout counter
    _consecutiveTimeouts = 0;

    // Re-establish subscription
    _subscription?.cancel();
    _subscriptionActive = false;

    _subscription = _midi.onMidiPacketReceived?.listen(
      _handleIncomingPacket,
      onError: _handleSubscriptionError,
      onDone: _handleSubscriptionDone,
      cancelOnError: false,
    );

    if (_subscription != null) {
      _subscriptionActive = true;
      _lastSubscriptionError = null;
      _totalPacketsReceived = 0;
      _sysexPacketsReceived = 0;
      _nonSysexPacketsReceived = 0;
      _ccMessagesDispatched = 0;
      _packetsFromWrongDevice = 0;
    }
  }

  /// Forces a full MIDI device disconnect/reconnect cycle.
  /// This is used to recover from corrupted MIDI state caused by rogue
  /// non-SysEx bytes that break CoreMIDI/flutter_midi_command.
  Future<void> forceDeviceReconnect() async {
    // Cancel current subscription first (safe operation)
    _subscription?.cancel();
    _subscriptionActive = false;

    // On Windows (and some other platforms), input and output are separate devices
    // and both need to be disconnected/reconnected.
    //
    // IMPORTANT: If we suspect the device connection is broken (e.g., device was
    // unplugged), we skip the disconnect call entirely. Calling disconnectDevice
    // on an invalid handle can crash the native MIDI library on Windows.

    if (!_deviceConnectionSuspectedBroken) {
      // Try to disconnect, but wrap in defensive try-catch.
      // On Windows, disconnecting an already-invalid handle can crash.
      try {
        _midi.disconnectDevice(_inputDevice);
      } catch (e) {
        // Disconnect failed - device likely already disconnected
        _deviceConnectionSuspectedBroken = true;
      }

      if (_outputDevice.id != _inputDevice.id) {
        try {
          _midi.disconnectDevice(_outputDevice);
        } catch (e) {
          // Disconnect failed - device likely already disconnected
          _deviceConnectionSuspectedBroken = true;
        }
      }
    }

    // Brief delay to let the system settle
    await Future.delayed(const Duration(milliseconds: 500));

    // Try to reconnect the devices
    try {
      _midi.connectToDevice(_inputDevice);
      if (_outputDevice.id != _inputDevice.id) {
        _midi.connectToDevice(_outputDevice);
      }
      // If reconnect succeeded, clear the broken flag
      _deviceConnectionSuspectedBroken = false;
    } catch (e) {
      // Reconnect failed - device may not be available
      _deviceConnectionSuspectedBroken = true;
      return; // Don't try to set up subscription if reconnect failed
    }

    // Re-establish subscription
    await Future.delayed(const Duration(milliseconds: 200));
    _subscription = _midi.onMidiPacketReceived?.listen(
      _handleIncomingPacket,
      onError: _handleSubscriptionError,
      onDone: _handleSubscriptionDone,
      cancelOnError: false,
    );

    if (_subscription != null) {
      _subscriptionActive = true;
      _lastSubscriptionError = null;
      // Reset diagnostic counters
      _totalPacketsReceived = 0;
      _sysexPacketsReceived = 0;
      _nonSysexPacketsReceived = 0;
      _ccMessagesDispatched = 0;
      _packetsFromWrongDevice = 0;
    }
  }

  void _handleSubscriptionError(Object error, StackTrace stackTrace) {
    _lastSubscriptionError = error.toString();

    // The listener uses cancelOnError: false, so a single stream error does
    // not end the subscription. If it interrupted a split SysEx response,
    // discard the unusable partial frame and replay the active request once.
    // This recovery is deliberately separate from the normal timeout budget:
    // SD requests retain their one-attempt timeout policy, while a confirmed
    // receive-side transfer failure can recover immediately.
    _subscriptionActive = _subscription != null;
    final request = _currentRequest;
    if (_state != _SchedulerState.waitingForResponse ||
        !_isBufferingSysEx ||
        request == null ||
        request.completer.isCompleted ||
        request.transferErrorRecoveryCount >= _maxTransferErrorRecoveries) {
      return;
    }

    _sysExBuffer.clear();
    _isBufferingSysEx = false;
    request.timeoutTimer?.cancel();
    request.stopwatch.stop();
    request.transferErrorRecoveryCount++;
    _state = _SchedulerState.sending;
    if (request.retryDelay == Duration.zero) {
      _sendCurrentRequest();
    } else {
      _retryTimer = Timer(request.retryDelay, _sendCurrentRequest);
    }
  }

  void _handleSubscriptionDone() {
    _subscriptionActive = false;
  }

  /// Adds a passive observer that receives ALL parsed Disting NT SysEx messages,
  /// regardless of whether they match a pending request.
  void addMessageObserver(void Function(DistingNTParsedMessage) observer) {
    _demux.addObserver(observer);
  }

  /// Removes a previously added message observer.
  void removeMessageObserver(void Function(DistingNTParsedMessage) observer) {
    _demux.removeObserver(observer);
  }

  Future<T?> sendRequest<T>(
    Uint8List packet,
    RequestKey key, {
    ResponseExpectation responseExpectation = ResponseExpectation.required,
    int? maxRetries,
    Duration? timeout,
    Duration? retryDelay,
    ResponseAttributionPolicy attributionPolicy =
        ResponseAttributionPolicy.bestEffort,
  }) {
    final completer = Completer<T?>();
    final request = _ScheduledRequest(
      id: ++_nextRequestId,
      packet: packet,
      key: key,
      expectation: responseExpectation,
      completer: completer,
      timeout: _normalizeDuration(timeout ?? defaultTimeout),
      maxRetries: maxRetries ?? defaultMaxRetries,
      retryDelay: _normalizeDuration(retryDelay ?? defaultRetryDelay),
      attributionPolicy: attributionPolicy,
    );

    _queue.add(request);
    _diag(
      'queued #${request.id} ${request.expectation.name} '
      'timeout=${request.timeout.inMilliseconds}ms '
      'maxRetries=${request.maxRetries} queue=${_queue.length} key=$key',
    );

    // Process immediately if idle
    if (_state == _SchedulerState.idle) {
      _processNext();
    }

    return completer.future;
  }

  void dispose() {
    _subscription?.cancel();
    _nextProcessTimer?.cancel();
    _retryTimer?.cancel();
    _demux.clear();
    final current = _currentRequest;
    _finishStrictAttribution(current);
    if (current != null && !current.completer.isCompleted) {
      current.completer.completeError(StateError('Scheduler disposed'));
    }
    current?.dispose();
    _currentRequest = null;
    _state = _SchedulerState.idle;

    // Fail all pending requests
    for (final request in _queue) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(StateError('Scheduler disposed'));
      }
    }
    _queue.clear();
  }

  // ---------------------------------------------------------------------------
  // Core processing logic
  // ---------------------------------------------------------------------------

  void _processNext() {
    // Cancel any pending timer
    _nextProcessTimer?.cancel();
    _nextProcessTimer = null;

    if (_state != _SchedulerState.idle || _queue.isEmpty) {
      return;
    }

    _currentRequest = _queue.removeFirst();
    _state = _SchedulerState.sending;
    _sendCurrentRequest();
  }

  void _sendCurrentRequest() {
    _retryTimer?.cancel();
    _retryTimer = null;

    final request = _currentRequest;
    if (request == null || request.completer.isCompleted) {
      _finishCurrentRequest();
      return;
    }

    if (request.attributionPolicy ==
            ResponseAttributionPolicy.failWhenAmbiguous &&
        !request.attributionStarted) {
      if (!_strictAttribution.begin(request)) {
        request.completer.completeError(
          AmbiguousResponseAttributionException(),
        );
        _finishCurrentRequest();
        return;
      }
      request.attributionStarted = true;
    }

    // If device is suspected broken, fail immediately instead of trying to send.
    // This prevents flooding the native layer with failed send attempts.
    if (_deviceConnectionSuspectedBroken) {
      _handleSendFailure(
        request,
        StateError('Device connection is broken - cannot send'),
      );
      return;
    }

    request.attemptCount++;
    _diag(
      'send #${request.id} attempt=${request.attemptCount}/'
      '${request.maxRetries} packetBytes=${request.packet.length} '
      'queue=${_queue.length} key=${request.key}',
    );

    // Start/restart stopwatch for RTT measurement
    request.stopwatch.reset();
    request.stopwatch.start();

    // Register handler with demux BEFORE sending (first attempt only).
    // Handler persists across retries — only moved to expired on final timeout.
    if (request.expectation != ResponseExpectation.none) {
      _demux.registerActive(request.key, (parsed) {
        _onResponseMatched(request, parsed);
      });
    }

    // Send the message
    try {
      _midi.sendData(request.packet, deviceId: _outputDevice.id);
      if (request.attributionStarted) {
        _strictAttribution.markSent(request);
      }
    } catch (e) {
      request.stopwatch.stop();
      _handleSendFailure(request, e);
      return;
    }

    if (request.expectation == ResponseExpectation.none) {
      // Fire-and-forget: complete immediately and schedule next
      _diag('complete #${request.id} fire-and-forget key=${request.key}');
      request.completer.complete(null);
      _finishCurrentRequest();
    } else {
      // Wait for response
      _state = _SchedulerState.waitingForResponse;
      request.startTimeout(() => _onTimeout());
    }
  }

  /// Called by the demux when a response matches the active handler.
  void _onResponseMatched(
    _ScheduledRequest request,
    DistingNTParsedMessage parsed,
  ) {
    // Guard against race conditions
    if (request.completer.isCompleted) {
      _finishCurrentRequest();
      return;
    }

    if (request.attributionStarted) {
      _strictAttribution.markResponse(request);
    }

    // Cancel timeout timer since we got a response
    request.timeoutTimer?.cancel();

    // Reset consecutive timeout counter
    _consecutiveTimeouts = 0;

    // Record RTT measurement
    request.stopwatch.stop();
    final rtt = request.stopwatch.elapsed;
    _recordRtt(rtt, parsed.messageType, libraryIndex: request.key.libraryIndex);
    _diag(
      'response #${request.id} rtt=${rtt.inMicroseconds / 1000}ms '
      'messageType=${parsed.messageType.name} key=${request.key}',
    );

    final sdCardOperation = request.key.sdCardOperation;
    final isSdCardError =
        sdCardOperation != null &&
        parsed.messageType == DistingNTRespMessageType.respDirectoryListing &&
        parsed.payload.isNotEmpty &&
        parsed.payload[0] != 0;
    if (isSdCardError) {
      request.completer.completeError(
        SdCardOperationException.fromPayload(
          operation: sdCardOperation,
          payload: parsed.payload,
        ),
      );
      _finishCurrentRequest();
      return;
    }

    // Parse and complete the response
    final response = ResponseFactory.fromMessageType(
      parsed.messageType,
      parsed.payload,
    );

    if (response != null) {
      try {
        final parsedResponse = response.parse();
        request.completer.complete(parsedResponse);
      } catch (e) {
        if (request.expectation == ResponseExpectation.optional) {
          _diag('parse-null #${request.id} optional key=${request.key}');
          request.completer.complete(null);
        } else {
          _diag(
            'parse-error #${request.id} key=${request.key} '
            'payloadLength=${parsed.payload.length} '
            'payloadHex=${_hex(parsed.payload)} error=$e',
          );
          final shouldRetryParseError = e is! TruncatedParameterPagesException;
          if (shouldRetryParseError &&
              request.attemptCount < request.maxRetries) {
            _state = _SchedulerState.sending;
            if (request.retryDelay == Duration.zero) {
              _sendCurrentRequest();
            } else {
              _retryTimer = Timer(request.retryDelay, _sendCurrentRequest);
            }
            return;
          }
          request.completer.completeError(
            StateError(
              'Failed to parse response: ${response.runtimeType} - $e',
            ),
          );
        }
      }
    } else {
      if (request.expectation == ResponseExpectation.optional) {
        _diag('unhandled-null #${request.id} optional key=${request.key}');
        request.completer.complete(null);
      } else {
        _diag(
          'unhandled-error #${request.id} messageType=${parsed.messageType.name} '
          'key=${request.key}',
        );
        request.completer.completeError(
          StateError('Unhandled response type: ${parsed.messageType}'),
        );
      }
    }

    _finishCurrentRequest();
  }

  void _onTimeout() {
    final request = _currentRequest;

    // Clear any partial SysEx buffer on timeout to prevent stale data
    if (_isBufferingSysEx) {
      _sysExBuffer.clear();
      _isBufferingSysEx = false;
    }

    // Guard against race conditions where response arrived just before timeout
    if (request == null || request.completer.isCompleted) {
      _consecutiveTimeouts = 0;
      _finishCurrentRequest();
      return;
    }

    if (request.attemptCount >= request.maxRetries) {
      // Out of retries — strict attribution tracks every sent attempt across
      // manager replacement; ordinary requests retain the local stale handler.
      if (request.attributionStarted) {
        _demux.discardActive();
      } else {
        _demux.expireActive();
      }

      // Record timeout for stats
      request.stopwatch.stop();
      _recordTimeout(request.key.messageType);
      _consecutiveTimeouts++;

      // Auto-recovery: after consecutive timeouts, reset MIDI state (buffers, subscription)
      // This is lighter than full disconnect/reconnect and handles most buffer corruption.
      if (_consecutiveTimeouts >= _maxConsecutiveTimeoutsBeforeRecovery) {
        _resetInternalState();
      }

      if (request.expectation == ResponseExpectation.required) {
        _diag(
          'timeout-final #${request.id} attempts=${request.attemptCount} '
          'timeout=${request.timeout.inMilliseconds}ms '
          'consecutiveTimeouts=$_consecutiveTimeouts key=${request.key}',
        );
        request.completer.completeError(
          TimeoutException(
            'No response after ${request.attemptCount} attempts',
            request.timeout,
          ),
        );
      } else {
        _diag(
          'timeout-final #${request.id} optional attempts=${request.attemptCount} '
          'timeout=${request.timeout.inMilliseconds}ms key=${request.key}',
        );
        request.completer.complete(null);
      }
      _finishCurrentRequest();
    } else {
      // Retry after delay — handler persists across retries
      _state = _SchedulerState.sending;
      _diag(
        'timeout-retry #${request.id} attempt=${request.attemptCount} '
        'nextAttempt=${request.attemptCount + 1} retryDelay='
        '${request.retryDelay.inMilliseconds}ms key=${request.key}',
      );

      if (request.retryDelay == Duration.zero) {
        _sendCurrentRequest();
      } else {
        _retryTimer = Timer(request.retryDelay, _sendCurrentRequest);
      }
    }
  }

  void _handleSendFailure(_ScheduledRequest request, Object error) {
    if (request.completer.isCompleted) {
      _finishCurrentRequest();
      return;
    }

    if (request.attemptCount >= request.maxRetries) {
      if (request.attributionStarted) {
        _demux.discardActive();
      } else {
        _demux.expireActive();
      }
      _diag(
        'send-failed-final #${request.id} attempts=${request.attemptCount} '
        'key=${request.key} error=$error',
      );
      request.completer.completeError(
        StateError(
          'Failed to send request after ${request.attemptCount} attempts: $error',
        ),
      );
      _finishCurrentRequest();
      return;
    }

    _state = _SchedulerState.sending;
    _diag(
      'send-failed-retry #${request.id} attempt=${request.attemptCount} '
      'retryDelay=${request.retryDelay.inMilliseconds}ms '
      'key=${request.key} error=$error',
    );
    if (request.retryDelay == Duration.zero) {
      _sendCurrentRequest();
    } else {
      _retryTimer = Timer(request.retryDelay, _sendCurrentRequest);
    }
  }

  void _diag(String message) {
    if (!_diagnosticsEnabled) return;
    final important =
        (message.startsWith('timeout-final #') &&
            !message.contains(' optional ')) ||
        message.startsWith('send-failed') ||
        message.startsWith('parse-error') ||
        message.startsWith('parameter-pages-raw') ||
        message.startsWith('unhandled-error');
    if (!important) return;
    debugPrint(
      '[NT_DIAG scheduler ${DateTime.now().toIso8601String()}] $message',
    );
  }

  String _hex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  void _finishCurrentRequest() {
    _finishStrictAttribution(_currentRequest);
    _currentRequest?.dispose();
    _currentRequest = null;
    _state = _SchedulerState.idle;
    _retryTimer?.cancel();
    _retryTimer = null;

    // Schedule next request after message interval
    if (_queue.isNotEmpty) {
      _nextProcessTimer?.cancel();
      _nextProcessTimer = Timer(messageInterval, _processNext);
    }
  }

  void _finishStrictAttribution(_ScheduledRequest? request) {
    if (request == null || !request.attributionStarted) return;
    _strictAttribution.finish(request);
    request.attributionStarted = false;
  }

  // ---------------------------------------------------------------------------
  // Incoming message handling
  // ---------------------------------------------------------------------------

  /// Extracts SysEx messages (F0...F7) from a raw MIDI packet.
  /// Returns an empty list if no valid SysEx is found.
  /// This handles cases where rogue MIDI messages (Program Change, Pitchwheel)
  /// are prepended to or mixed with SysEx data by the MIDI library.
  List<Uint8List> _extractSysExMessages(Uint8List raw) {
    final messages = <Uint8List>[];
    int searchStart = 0;

    while (searchStart < raw.length) {
      final startIndex = raw.indexOf(0xF0, searchStart);
      if (startIndex == -1) break;

      final endIndex = raw.indexOf(0xF7, startIndex);
      if (endIndex == -1) break;

      // Per MIDI spec, a new F0 cancels any in-progress SysEx.
      int actualStart = startIndex;
      for (int i = startIndex + 1; i < endIndex; i++) {
        if (raw[i] == 0xF0) actualStart = i;
      }

      messages.add(raw.sublist(actualStart, endIndex + 1));
      searchStart = endIndex + 1;
    }

    return messages;
  }

  void _handleIncomingPacket(dynamic packet) {
    _totalPacketsReceived++;
    _lastPacketTime = DateTime.now();

    if (packet is MidiPacket) {
      if (packet.device.id != _inputDevice.id) {
        _packetsFromWrongDevice++;
        return;
      }
      _handleIncoming(packet.data);
    } else if (packet is Uint8List) {
      _handleIncoming(packet);
    }
  }

  void _handleIncoming(Uint8List raw) {
    // Handle SysEx buffering for split messages (common on Windows with large SysEx)
    final hasF0 = raw.contains(0xF0);
    final hasF7 = raw.contains(0xF7);

    // If we're currently buffering a SysEx message
    if (_isBufferingSysEx) {
      if (hasF0 && (!hasF7 || raw.indexOf(0xF0) < raw.indexOf(0xF7))) {
        // New F0 arrives before any F7 — interrupts our buffered SysEx.
        // Discard buffer and fall through to process this packet normally.
        _sysExBuffer.clear();
        _isBufferingSysEx = false;
      } else if (raw.isNotEmpty && raw[0] >= 0x80 && raw[0] != 0xF7 && !hasF0) {
        // Non-SysEx status byte (CC, Note, etc.) — dispatch CCs, skip rest
        _dispatchCcMessages(raw);
        _nonSysexPacketsReceived++;
        return;
      } else {
        // SysEx continuation data (data bytes < 0x80, or F7 terminator)
        _sysExBuffer.addAll(raw);
        if (hasF7) {
          _isBufferingSysEx = false;
          final completeMessage = Uint8List.fromList(_sysExBuffer);
          _sysExBuffer.clear();
          _sysexPacketsReceived++;
          _processExtractedSysEx(_extractSysExMessages(completeMessage));

          // Check for a trailing F0 (start of next split SysEx)
          final lastF7 = completeMessage.lastIndexOf(0xF7);
          if (lastF7 < completeMessage.length - 1) {
            final trailing = completeMessage.sublist(lastF7 + 1);
            if (trailing.contains(0xF0)) {
              final trailingF0 = trailing.indexOf(0xF0);
              _sysExBuffer.addAll(trailing.sublist(trailingF0));
              _isBufferingSysEx = true;
            }
          }
          return;
        }
        return;
      }
    }

    // Check if this starts a new SysEx that might be split
    if (hasF0 && !hasF7) {
      // Dispatch any CC messages that precede the SysEx start
      final f0Index = raw.indexOf(0xF0);
      if (f0Index > 0) {
        _dispatchCcMessages(Uint8List.sublistView(raw, 0, f0Index));
      }
      // Start of a split SysEx message
      _isBufferingSysEx = true;
      _sysExBuffer.clear();
      _sysExBuffer.addAll(raw.sublist(f0Index));
      return;
    }

    // Extract SysEx messages from packet, filtering out any rogue MIDI bytes.
    // Some plugins/algorithms send Program Change or Pitchwheel messages that
    // may be combined with SysEx responses by the MIDI library.
    final sysexMessages = _extractSysExMessages(raw);
    if (sysexMessages.isEmpty) {
      _dispatchCcMessages(raw);
      _nonSysexPacketsReceived++;
      return;
    }

    _sysexPacketsReceived++;

    // Dispatch CC messages from any non-SysEx bytes in the packet.
    // CC bytes may precede or follow the SysEx data.
    _dispatchCcMessages(raw);

    // Check for trailing split SysEx start after the last complete message
    final lastMsgEnd = raw.lastIndexOf(0xF7);
    if (lastMsgEnd < raw.length - 1) {
      final trailing = raw.sublist(lastMsgEnd + 1);
      if (trailing.contains(0xF0)) {
        final trailingF0 = trailing.indexOf(0xF0);
        _isBufferingSysEx = true;
        _sysExBuffer.clear();
        _sysExBuffer.addAll(trailing.sublist(trailingF0));
      }
    }

    _processExtractedSysEx(sysexMessages);
  }

  void _dispatchCcMessages(Uint8List raw) {
    final callback = _ccCallback;
    if (callback == null) return;
    for (int i = 0; i < raw.length; i++) {
      final byte = raw[i];
      if (byte & 0xF0 == 0xB0 && i + 2 < raw.length) {
        final data1 = raw[i + 1];
        final data2 = raw[i + 2];
        if (data1 < 0x80 && data2 < 0x80) {
          callback(byte & 0x0F, data1, data2);
          _ccMessagesDispatched++;
          i += 2;
        }
      }
    }
  }

  void _processExtractedSysEx(List<Uint8List> sysexMessages) {
    for (final sysex in sysexMessages) {
      _dispatchSysEx(sysex);
    }
  }

  void _dispatchSysEx(Uint8List sysex) {
    try {
      final parsed = decodeDistingNTSysEx(sysex);
      if (parsed == null) return;
      if (parsed.sysExId != _sysExId) return;

      if (parsed.messageType == DistingNTRespMessageType.respParameterPages) {
        _diag(
          'parameter-pages-raw rawLength=${sysex.length} '
          'payloadLength=${parsed.payload.length} '
          'payloadHex=${_hex(parsed.payload)} rawHex=${_hex(sysex)}',
        );
      }

      _demux.dispatch(parsed);
    } catch (e) {
      // Catch any unexpected exceptions to prevent scheduler from getting stuck.
    }
  }
}
