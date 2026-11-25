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

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

// Domain classes
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/domain/disting_request_control.dart';
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

/// Whether a request may be sent again after a timeout/receive failure.
/// A write may already have executed even if its acknowledgement was lost.
enum RequestReplayPolicy { allow, never }

enum ResponseAttributionPolicy {
  bestEffort,
  failWhenAmbiguous,
  rejectAmbiguousResponse,
}

final class AmbiguousResponseAttributionException extends StateError {
  AmbiguousResponseAttributionException()
    : super(
        'Cannot establish response attribution because an earlier request may '
        'still respond.',
      );
}

/// Phase at which a request failed due to scheduler/transport termination.
enum RequestFailurePhase {
  /// Rejected before admission or while queued; bytes were never transmitted.
  beforeSend,

  /// Failed after transmission was attempted; device execution outcome is unknown.
  inFlight,
}

/// Why a scheduler stopped accepting or transmitting requests.
enum SchedulerTerminationReason {
  disposed,
  receiveStreamClosed,
  receiveStreamUnavailable,
  connectionLost,
}

/// Phase-aware terminal error raised when a scheduler is disposed or its
/// underlying receive/transport path is lost.
final class DistingSchedulerClosedException extends StateError {
  DistingSchedulerClosedException({
    required this.reason,
    required this.phase,
    String? message,
  }) : super(
         message ??
             switch ((reason, phase)) {
               (
                 SchedulerTerminationReason.disposed,
                 RequestFailurePhase.beforeSend,
               ) =>
                 'Scheduler disposed before request was sent.',
               (
                 SchedulerTerminationReason.disposed,
                 RequestFailurePhase.inFlight,
               ) =>
                 'Scheduler disposed while request was in flight; outcome is unknown.',
               (
                 SchedulerTerminationReason.receiveStreamClosed,
                 RequestFailurePhase.beforeSend,
               ) =>
                 'MIDI receive stream closed before request was sent.',
               (
                 SchedulerTerminationReason.receiveStreamClosed,
                 RequestFailurePhase.inFlight,
               ) =>
                 'MIDI receive stream closed while request was in flight; outcome is unknown.',
               (SchedulerTerminationReason.receiveStreamUnavailable, _) =>
                 'MIDI receive stream is unavailable; request was not sent.',
               (
                 SchedulerTerminationReason.connectionLost,
                 RequestFailurePhase.beforeSend,
               ) =>
                 'MIDI connection lost before request was sent.',
               (
                 SchedulerTerminationReason.connectionLost,
                 RequestFailurePhase.inFlight,
               ) =>
                 'MIDI connection lost while request was in flight; outcome is unknown.',
             },
       );

  final SchedulerTerminationReason reason;
  final RequestFailurePhase phase;

  bool get definitelyUnsent => phase == RequestFailurePhase.beforeSend;
  bool get outcomeUnknown => phase == RequestFailurePhase.inFlight;
}

// -----------------------------------------------------------------------------
// Scheduler state
// -----------------------------------------------------------------------------

typedef CcCallback = void Function(int channel, int cc, int value);

enum _SchedulerState { idle, sending, waitingForResponse, closed }

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
    required this.replayPolicy,
    this.rawResponseMatcher,
    this.preflight,
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
  final RequestReplayPolicy replayPolicy;
  final bool Function(Uint8List)? rawResponseMatcher;
  final void Function()? preflight;

  int attemptCount = 0;
  int transferErrorRecoveryCount = 0;
  int sentRequestCount = 0;
  int matchingResponseCount = 0;
  bool attributionStarted = false;
  Timer? timeoutTimer;
  void Function()? removeCancellationListener;

  /// Effective total attempt cap. Preserves existing total-attempt semantics
  /// where 0 or 1 means a single send attempt, and `never` replay always caps
  /// at 1 attempt.
  int get maxAttempts => replayPolicy == RequestReplayPolicy.never
      ? 1
      : (maxRetries < 1 ? 1 : maxRetries);

  /// Stopwatch to measure round-trip time from send to response
  final Stopwatch stopwatch = Stopwatch();

  void startTimeout(void Function() onTimeout) {
    timeoutTimer?.cancel();
    if (expectation != ResponseExpectation.none) {
      timeoutTimer = Timer(timeout, onTimeout);
    }
  }

  void dispose() {
    timeoutTimer?.cancel();
    removeCancellationListener?.call();
    removeCancellationListener = null;
  }
}

// -----------------------------------------------------------------------------
// Response Demultiplexer
// -----------------------------------------------------------------------------

class _ActiveHandler {
  _ActiveHandler({
    required this.key,
    required this.onMatch,
    required this.onAmbiguous,
  });

  final RequestKey key;
  final void Function(DistingNTParsedMessage) onMatch;
  final void Function() onAmbiguous;
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

final class _UncertainDomainKey {
  const _UncertainDomainKey({required this.sysExId, required this.messageType});

  final int sysExId;
  final DistingNTRespMessageType messageType;

  @override
  bool operator ==(Object other) =>
      other is _UncertainDomainKey &&
      sysExId == other.sysExId &&
      messageType == other.messageType;

  @override
  int get hashCode => Object.hash(sysExId, messageType);
}

/// Counted response debt for one [RequestKey].
final class _CountedResponseDebt {
  _CountedResponseDebt(this.key);

  final RequestKey key;
  int strictCount = 0;
  int bestEffortCount = 0;
  int sessionLossCount = 0;

  int get totalCount => strictCount + bestEffortCount + sessionLossCount;
  bool get isEmpty => totalCount == 0;
}

/// Tracks response debt for requests whose wire protocol has no transaction ID.
///
/// The tracker is carried across manager replacement, `MidiCommand` client
/// replacement, and uncertain USB endpoint re-enumeration aliases so old
/// in-flight replies cannot be attributed to a replacement session. Debt
/// remains until matching packets drain it; elapsed time, a new local epoch, or
/// a fresh endpoint handle alone cannot prove old device replies impossible.
final class ResponseAttributionTracker {
  static const int _maxDistinctDebtKeys = 512;

  _ScheduledRequest? _activeRequest;
  final Map<RequestKey, _CountedResponseDebt> _debts = {};
  final Set<_UncertainDomainKey> _uncertainDomains = {};

  int get totalDebtCount {
    var total = 0;
    for (final debt in _debts.values) {
      total += debt.totalCount;
    }
    return total;
  }

  bool get hasUncertainDomains => _uncertainDomains.isNotEmpty;

  bool hasSessionLossDebt(RequestKey key) {
    if (_matchesUncertainDomain(key)) return true;
    for (final debt in _debts.values) {
      if (debt.sessionLossCount > 0 && debt.key.overlapsForQuarantine(key)) {
        return true;
      }
    }
    return false;
  }

  bool hasAnyOverlappingDebt(RequestKey key) {
    if (_matchesUncertainDomain(key)) return true;
    for (final debt in _debts.values) {
      if (debt.totalCount > 0 && debt.key.overlapsForQuarantine(key)) {
        return true;
      }
    }
    return false;
  }

  bool _begin(_ScheduledRequest request) {
    if (_activeRequest != null) {
      return false;
    }
    if (hasSessionLossDebt(request.key)) {
      return false;
    }
    final blocksBeforeSend =
        request.attributionPolicy ==
        ResponseAttributionPolicy.failWhenAmbiguous;
    if (blocksBeforeSend && hasAnyOverlappingDebt(request.key)) {
      return false;
    }
    _activeRequest = request;
    return true;
  }

  void _markSent(_ScheduledRequest request) {
    request.sentRequestCount++;
  }

  void _markResponse(_ScheduledRequest request) {
    request.matchingResponseCount++;
  }

  void _finish(_ScheduledRequest request, {bool sessionLost = false}) {
    final unresolved = request.sentRequestCount - request.matchingResponseCount;
    final canRecordKeyDebt =
        unresolved > 0 &&
        request.expectation != ResponseExpectation.none &&
        request.rawResponseMatcher == null &&
        request.key.messageType != null;

    if (canRecordKeyDebt) {
      if (sessionLost) {
        _addDebt(request.key, count: unresolved, sessionLoss: true);
      } else if (_tracksHealthyResponseDebt(request)) {
        _addDebt(
          request.key,
          count: unresolved,
          bestEffort:
              request.attributionPolicy == ResponseAttributionPolicy.bestEffort,
        );
      }
    }

    if (identical(_activeRequest, request)) {
      _activeRequest = null;
    }
  }

  bool consumeAmbiguousForActive(DistingNTParsedMessage parsed) {
    final activeRequest = _activeRequest;
    if (activeRequest == null) {
      return false;
    }

    // Session-loss quarantine applies conservatively to any active request whose
    // response class still has owed replies from a prior lost session.
    if (activeRequest.key.matches(parsed) && _consumeSessionLossDebt(parsed)) {
      return true;
    }

    if (activeRequest.attributionPolicy !=
            ResponseAttributionPolicy.rejectAmbiguousResponse ||
        !activeRequest.key.matchesStrict(parsed)) {
      return false;
    }

    if (_matchesUncertainDomainMessage(parsed)) {
      return true;
    }

    for (final entry in _debts.entries.toList()) {
      final debt = entry.value;
      if (!debt.key.matchesStrict(parsed)) continue;
      if (debt.sessionLossCount > 0) {
        debt.sessionLossCount--;
      } else if (debt.strictCount > 0) {
        debt.strictCount--;
      } else if (debt.bestEffortCount > 0) {
        debt.bestEffortCount--;
      } else {
        continue;
      }
      if (debt.isEmpty) {
        _debts.remove(entry.key);
      }
      return true;
    }
    return false;
  }

  bool consumeUnattributed(
    DistingNTParsedMessage parsed, {
    required bool allowBestEffortDebt,
  }) {
    // Drain owed replies from a prior lost session first, even before any
    // best-effort active handler or passive observer sees them.
    if (_consumeSessionLossDebt(parsed)) {
      return true;
    }

    final activeRequest = _activeRequest;
    if (activeRequest != null && activeRequest.key.matchesStrict(parsed)) {
      return false;
    }

    for (final entry in _debts.entries.toList()) {
      final debt = entry.value;
      if (!debt.key.matchesStrict(parsed)) continue;
      if (debt.strictCount > 0) {
        debt.strictCount--;
        if (debt.isEmpty) _debts.remove(entry.key);
        return true;
      }
      if (allowBestEffortDebt && debt.bestEffortCount > 0) {
        debt.bestEffortCount--;
        if (debt.isEmpty) _debts.remove(entry.key);
        return true;
      }
    }
    return false;
  }

  bool _consumeSessionLossDebt(DistingNTParsedMessage parsed) {
    if (_matchesUncertainDomainMessage(parsed)) {
      return true;
    }
    for (final entry in _debts.entries.toList()) {
      final debt = entry.value;
      if (debt.sessionLossCount <= 0) continue;
      if (!debt.key.matchesForQuarantineDrain(parsed)) continue;
      debt.sessionLossCount--;
      if (debt.isEmpty) {
        _debts.remove(entry.key);
      }
      return true;
    }
    return false;
  }

  void _addDebt(
    RequestKey key, {
    required int count,
    bool bestEffort = false,
    bool sessionLoss = false,
  }) {
    if (count <= 0) return;
    final messageType = key.messageType;
    if (messageType == null) return;
    final domain = _UncertainDomainKey(
      sysExId: key.sysExId,
      messageType: messageType,
    );
    if (_uncertainDomains.contains(domain)) {
      return;
    }

    var entry = _debts[key];
    if (entry == null) {
      if (_debts.length >= _maxDistinctDebtKeys) {
        // Keep memory bounded without dropping safety evidence: collapse this
        // response class into a conservative uncertain-domain marker.
        _uncertainDomains.add(domain);
        _debts.removeWhere(
          (existingKey, _) =>
              existingKey.sysExId == key.sysExId &&
              existingKey.messageType == messageType,
        );
        return;
      }
      entry = _CountedResponseDebt(key);
      _debts[key] = entry;
    }

    if (sessionLoss) {
      entry.sessionLossCount += count;
    } else if (bestEffort) {
      entry.bestEffortCount += count;
    } else {
      entry.strictCount += count;
    }
  }

  bool _matchesUncertainDomain(RequestKey key) {
    final messageType = key.messageType;
    if (messageType == null) return false;
    return _uncertainDomains.contains(
      _UncertainDomainKey(sysExId: key.sysExId, messageType: messageType),
    );
  }

  bool _matchesUncertainDomainMessage(DistingNTParsedMessage parsed) {
    return _uncertainDomains.contains(
      _UncertainDomainKey(
        sysExId: parsed.sysExId,
        messageType: parsed.messageType,
      ),
    );
  }

  bool _tracksHealthyResponseDebt(_ScheduledRequest request) =>
      request.expectation != ResponseExpectation.none &&
      (request.attributionPolicy != ResponseAttributionPolicy.bestEffort ||
          request.key.messageType == DistingNTRespMessageType.respAlgorithm);
}

final Expando<Map<_AttributionEndpointKey, ResponseAttributionTracker>>
_strictAttributionByMidi = Expando('Disting strict response attribution');

ResponseAttributionTracker _strictAttributionFor({
  required MidiCommand midi,
  required MidiDevice inputDevice,
  required int sysExId,
  ResponseAttributionTracker? overrideTracker,
}) {
  final endpointStates = _strictAttributionByMidi[midi] ??= {};
  final endpoint = _AttributionEndpointKey(
    inputDeviceId: inputDevice.id,
    sysExId: sysExId,
  );
  if (overrideTracker != null) {
    endpointStates[endpoint] = overrideTracker;
    return overrideTracker;
  }
  return endpointStates.putIfAbsent(endpoint, ResponseAttributionTracker.new);
}

class _ResponseDemux {
  _ResponseDemux(this._strictAttribution);

  final ResponseAttributionTracker _strictAttribution;
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
    void Function(DistingNTParsedMessage) onMatch, {
    required void Function() onAmbiguous,
  }) {
    _activeHandler = _ActiveHandler(
      key: key,
      onMatch: onMatch,
      onAmbiguous: onAmbiguous,
    );
  }

  void expireActive() {
    final handler = _activeHandler;
    if (handler != null) {
      _activeHandler = null;
      _expiredHandlers.add(
        _ExpiredHandler(key: handler.key, expiredAt: clock.now()),
      );
      _cleanupExpiredHandlers();
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

  void clearObservers() {
    _observers.clear();
  }

  void dispatch(DistingNTParsedMessage parsed) {
    // 1. A strict verification request may be sent while an older response is
    // still owed. Reject an indistinguishable stale packet before it crosses
    // either the request or passive-observer boundary.
    if (_strictAttribution.consumeAmbiguousForActive(parsed)) {
      staleResponsesAbsorbed++;
      _removeExpiredMatch(parsed);
      final handler = _activeHandler;
      _activeHandler = null;
      handler?.onAmbiguous();
      return;
    }

    // 2. Drain unattributed session-loss and strict debt, plus ordinary 0x40
    // debt when doing so cannot change historical active-first behavior.
    final activeHandlerMatches = _activeHandler?.key.matches(parsed) ?? false;
    if (_strictAttribution.consumeUnattributed(
      parsed,
      allowBestEffortDebt: !activeHandlerMatches,
    )) {
      staleResponsesAbsorbed++;
      _removeExpiredMatch(parsed);
      return;
    }

    // 3. Notify passive observers only after stale response debt is excluded.
    for (final observer in List<void Function(DistingNTParsedMessage)>.of(
      _observers,
    )) {
      try {
        observer(parsed);
      } catch (_) {}
    }

    // 4. Check the active handler. Best-effort requests retain the historical
    // active-first behavior; strict verification requests reached here only
    // when no indistinguishable response debt exists.
    if (_activeHandler != null && _activeHandler!.key.matches(parsed)) {
      final handler = _activeHandler!;
      _activeHandler = null;
      handler.onMatch(parsed);
      return;
    }

    // 5. Check expired handlers (oldest first) — absorb stale responses
    final expiredMatch = _expiredHandlers.indexWhere(
      (h) => h.key.matchesStrict(parsed),
    );
    if (expiredMatch != -1) {
      _expiredHandlers.removeAt(expiredMatch);
      staleResponsesAbsorbed++;
      return;
    }

    // 6. No match — discard cleanly
    unmatchedResponsesDiscarded++;

    // Cleanup of old expired handlers
    _cleanupExpiredHandlers();
  }

  void _removeExpiredMatch(DistingNTParsedMessage parsed) {
    final expiredMatch = _expiredHandlers.indexWhere(
      (handler) => handler.key.matchesStrict(parsed),
    );
    if (expiredMatch != -1) {
      _expiredHandlers.removeAt(expiredMatch);
    }
  }

  void _cleanupExpiredHandlers() {
    if (_expiredHandlers.isEmpty) return;

    final now = clock.now();
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
    required this._inputDevice,
    required this._outputDevice,
    required this._sysExId,
    Duration messageInterval = const Duration(milliseconds: 50),
    Duration defaultTimeout = const Duration(milliseconds: 1000),
    this.defaultMaxRetries = 5,
    Duration defaultRetryDelay = Duration.zero,
    ResponseAttributionTracker? attributionTracker,
    this.onConnectionLost,
  }) : _midi = midiCommand,
       messageInterval = _normalizeDuration(messageInterval),
       defaultTimeout = _normalizeDuration(defaultTimeout),
       defaultRetryDelay = _normalizeDuration(defaultRetryDelay) {
    _strictAttribution = _strictAttributionFor(
      midi: _midi,
      inputDevice: _inputDevice,
      sysExId: _sysExId,
      overrideTracker: attributionTracker,
    );
    _demux = _ResponseDemux(_strictAttribution);
    _attachSubscription();
    if (_subscription == null) {
      _terminated = true;
      _terminationReason = SchedulerTerminationReason.receiveStreamUnavailable;
      _state = _SchedulerState.closed;
    }
  }

  // MIDI and device configuration
  final MidiCommand _midi;
  final MidiDevice _inputDevice;
  final MidiDevice _outputDevice;
  final int _sysExId;
  final VoidCallback? onConnectionLost;

  static const bool _diagnosticsEnabled = true;
  static int _nextRequestId = 0;
  static const int _maxTransferErrorRecoveries = 1;
  static const Duration _reconnectConnectTimeout = Duration(seconds: 3);

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
  DateTime? _nextAllowedSendAt;
  StreamSubscription? _subscription;
  bool _disposed = false;
  bool _terminated = false;
  SchedulerTerminationReason? _terminationReason;
  int _subscriptionEpoch = 0;
  int _reconnectOpEpoch = 0;

  // Response demultiplexer
  late final ResponseAttributionTracker _strictAttribution;
  late final _ResponseDemux _demux;

  bool get isDisposed => _disposed;
  bool get isUsable =>
      !_disposed &&
      !_terminated &&
      _subscriptionActive &&
      !_deviceConnectionSuspectedBroken;
  ResponseAttributionTracker get attributionTracker => _strictAttribution;

  // CC callback for receiving MIDI CC messages from the device
  CcCallback? _ccCallback;

  void setCcCallback(CcCallback callback) {
    if (_disposed || _terminated) return;
    _ccCallback = callback;
  }

  void clearCcCallback() {
    _ccCallback = null;
  }

  void _attachSubscription() {
    final subEpoch = ++_subscriptionEpoch;
    _subscription?.cancel();
    _subscription = null;
    _subscriptionActive = false;

    if (_disposed || _terminated) {
      return;
    }

    _subscription = _midi.onMidiPacketReceived?.listen(
      (packet) {
        if (_disposed || _terminated || subEpoch != _subscriptionEpoch) return;
        _handleIncomingPacket(packet);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed || _terminated || subEpoch != _subscriptionEpoch) return;
        _handleSubscriptionError(error, stackTrace);
      },
      onDone: () {
        if (_disposed || _terminated || subEpoch != _subscriptionEpoch) return;
        _handleSubscriptionDone();
      },
      cancelOnError: false,
    );

    if (_subscription != null) {
      _subscriptionActive = true;
      _lastSubscriptionError = null;
    }
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
    final now = clock.now();
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
    if (_disposed || _terminated) return;
    _attachSubscription();
    if (_subscription == null) {
      _terminate(
        SchedulerTerminationReason.receiveStreamUnavailable,
        notifyLoss: true,
      );
    }
  }

  /// Resets internal MIDI state without full disconnect/reconnect.
  /// Clears buffers, resets counters, and re-subscribes to the stream.
  /// Does NOT affect the current request - caller is responsible for that.
  void _resetInternalState() {
    if (_disposed || _terminated) return;

    // Clear any partial SysEx data
    _sysExBuffer.clear();
    _isBufferingSysEx = false;

    // Reset consecutive timeout counter
    _consecutiveTimeouts = 0;

    // Re-establish subscription
    _attachSubscription();

    if (_subscription != null) {
      _totalPacketsReceived = 0;
      _sysexPacketsReceived = 0;
      _nonSysexPacketsReceived = 0;
      _ccMessagesDispatched = 0;
      _packetsFromWrongDevice = 0;
    } else {
      _terminate(
        SchedulerTerminationReason.receiveStreamUnavailable,
        notifyLoss: true,
      );
    }
  }

  /// Forces a full MIDI device disconnect/reconnect cycle.
  /// Guarded by terminal disposal and local lifecycle epochs so a suspended
  /// reconnect can never revive listeners or alter state after disposal.
  Future<void> forceDeviceReconnect() async {
    if (_disposed || _terminated) return;
    final opEpoch = ++_reconnectOpEpoch;

    // Cancel current subscription first (safe operation)
    _subscriptionEpoch++;
    _subscription?.cancel();
    _subscription = null;
    _subscriptionActive = false;

    if (!_deviceConnectionSuspectedBroken) {
      try {
        _midi.disconnectDevice(_inputDevice);
      } catch (e) {
        _deviceConnectionSuspectedBroken = true;
      }

      if (_outputDevice.id != _inputDevice.id) {
        try {
          _midi.disconnectDevice(_outputDevice);
        } catch (e) {
          _deviceConnectionSuspectedBroken = true;
        }
      }
    }

    // Brief delay to let the system settle
    await Future.delayed(const Duration(milliseconds: 500));
    if (_disposed || _terminated || opEpoch != _reconnectOpEpoch) return;

    // Try to reconnect the devices (awaited with bounded timeout)
    try {
      await _midi
          .connectToDevice(_inputDevice)
          .timeout(_reconnectConnectTimeout);
      if (_disposed || _terminated || opEpoch != _reconnectOpEpoch) return;
      if (_outputDevice.id != _inputDevice.id) {
        await _midi
            .connectToDevice(_outputDevice)
            .timeout(_reconnectConnectTimeout);
        if (_disposed || _terminated || opEpoch != _reconnectOpEpoch) return;
      }
      _deviceConnectionSuspectedBroken = false;
    } catch (e) {
      if (!_disposed && !_terminated && opEpoch == _reconnectOpEpoch) {
        _deviceConnectionSuspectedBroken = true;
      }
      return;
    }

    // Re-establish subscription
    await Future.delayed(const Duration(milliseconds: 200));
    if (_disposed || _terminated || opEpoch != _reconnectOpEpoch) return;

    _attachSubscription();

    if (_subscription != null) {
      _totalPacketsReceived = 0;
      _sysexPacketsReceived = 0;
      _nonSysexPacketsReceived = 0;
      _ccMessagesDispatched = 0;
      _packetsFromWrongDevice = 0;
    }
  }

  void _handleSubscriptionError(Object error, StackTrace stackTrace) {
    if (_disposed || _terminated) return;
    _lastSubscriptionError = error.toString();

    // The listener uses cancelOnError: false, so a single stream error does
    // not end the subscription. If it interrupted a split SysEx response,
    // discard the unusable partial frame. Only replay explicitly eligible
    // requests within their configured total attempt budget; never-replay
    // requests fail closed immediately.
    _subscriptionActive = _subscription != null;
    final request = _currentRequest;
    if (_state != _SchedulerState.waitingForResponse ||
        !_isBufferingSysEx ||
        request == null ||
        request.rawResponseMatcher != null ||
        request.completer.isCompleted) {
      return;
    }

    _sysExBuffer.clear();
    _isBufferingSysEx = false;

    if (request.replayPolicy == RequestReplayPolicy.never) {
      request.timeoutTimer?.cancel();
      request.stopwatch.stop();
      _demux.discardActive();
      request.completer.completeError(
        StateError(
          'Receive interrupted; the request may already have executed. It was not replayed.',
        ),
      );
      _finishCurrentRequest();
      return;
    }

    if (request.transferErrorRecoveryCount >= _maxTransferErrorRecoveries ||
        request.attemptCount >= request.maxAttempts) {
      return;
    }

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
    _terminate(
      SchedulerTerminationReason.receiveStreamClosed,
      notifyLoss: true,
    );
  }

  /// Synchronously terminates admission and settles all in-flight and queued
  /// requests with phase-aware errors without waiting for native teardown.
  void markConnectionLost({
    SchedulerTerminationReason reason =
        SchedulerTerminationReason.connectionLost,
  }) {
    _terminate(reason, notifyLoss: false);
  }

  /// Adds a passive observer that receives attributable parsed Disting NT SysEx
  /// messages, regardless of whether they match a pending request. Packets owed
  /// to an earlier request are excluded.
  void addMessageObserver(void Function(DistingNTParsedMessage) observer) {
    if (_disposed || _terminated) return;
    _demux.addObserver(observer);
  }

  /// Removes a previously added message observer.
  void removeMessageObserver(void Function(DistingNTParsedMessage) observer) {
    _demux.removeObserver(observer);
  }

  /// Plug-in traffic shares the normal queue and selected-device receive path.
  /// Responses must carry their own transaction identity. Never replay writes.
  Future<Uint8List> sendPluginRequest(
    Uint8List packet,
    bool Function(Uint8List) matches,
  ) async {
    if (packet.length > 1024 ||
        packet.length < 2 ||
        packet.first != 0xf0 ||
        packet.last != 0xf7) {
      throw ArgumentError('Expected a SysEx frame of at most 1024 bytes');
    }
    final result = await sendRequest<Uint8List>(
      packet,
      RequestKey(sysExId: _sysExId),
      maxRetries: 1,
      replayPolicy: RequestReplayPolicy.never,
      rawResponseMatcher: matches,
    );
    return result!;
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
    DistingRequestCancellation? cancellation,
    RequestReplayPolicy replayPolicy = RequestReplayPolicy.allow,
    void Function()? preflight,
    bool Function(Uint8List)? rawResponseMatcher,
  }) {
    if (_disposed || _terminated || !_subscriptionActive) {
      final reason =
          _terminationReason ??
          (_disposed
              ? SchedulerTerminationReason.disposed
              : SchedulerTerminationReason.receiveStreamUnavailable);
      return Future<T?>.error(
        DistingSchedulerClosedException(
          reason: reason,
          phase: RequestFailurePhase.beforeSend,
        ),
      );
    }

    final completer = Completer<T?>();
    final effectiveMaxRetries = replayPolicy == RequestReplayPolicy.never
        ? 1
        : (maxRetries ?? defaultMaxRetries);
    final request = _ScheduledRequest(
      id: ++_nextRequestId,
      packet: packet,
      key: key,
      expectation: responseExpectation,
      completer: completer,
      timeout: _normalizeDuration(timeout ?? defaultTimeout),
      maxRetries: effectiveMaxRetries,
      retryDelay: _normalizeDuration(retryDelay ?? defaultRetryDelay),
      attributionPolicy: attributionPolicy,
      replayPolicy: replayPolicy,
      preflight: preflight,
      rawResponseMatcher: rawResponseMatcher,
    );

    _queue.add(request);
    request.removeCancellationListener = cancellation?.addListener(
      () => _cancelRequest(request),
    );
    _diag(
      'queued #${request.id} ${request.expectation.name} '
      'timeout=${request.timeout.inMilliseconds}ms '
      'maxRetries=${request.maxRetries} queue=${_queue.length} key=$key',
    );

    // Schedule processing while honoring inter-message pacing cooldown.
    if (_state == _SchedulerState.idle) {
      _scheduleNextProcess(allowImmediateIfIdle: true);
    }

    return completer.future;
  }

  void dispose() {
    _disposed = true;
    _terminate(SchedulerTerminationReason.disposed, notifyLoss: false);
  }

  void _terminate(
    SchedulerTerminationReason reason, {
    required bool notifyLoss,
  }) {
    _subscriptionEpoch++;
    _reconnectOpEpoch++;
    _subscription?.cancel();
    _subscription = null;
    _subscriptionActive = false;
    _nextProcessTimer?.cancel();
    _nextProcessTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _sysExBuffer.clear();
    _isBufferingSysEx = false;
    _ccCallback = null;

    if (_terminated) {
      _state = _SchedulerState.closed;
      return;
    }

    _terminated = true;
    _terminationReason = reason;
    _state = _SchedulerState.closed;

    _demux.clear();
    _demux.clearObservers();

    final current = _currentRequest;
    _currentRequest = null;
    final queued = _queue.toList(growable: false);
    _queue.clear();

    if (current != null) {
      final inFlight = current.sentRequestCount > 0 || current.attemptCount > 0;
      _finishResponseAttribution(current, sessionLost: inFlight);
      if (!current.completer.isCompleted) {
        current.completer.completeError(
          DistingSchedulerClosedException(
            reason: reason,
            phase: inFlight
                ? RequestFailurePhase.inFlight
                : RequestFailurePhase.beforeSend,
          ),
        );
      }
      current.dispose();
    }

    // Fail all queued (definitely unsent) requests once with beforeSend phase.
    for (final request in queued) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(
          DistingSchedulerClosedException(
            reason: reason,
            phase: RequestFailurePhase.beforeSend,
          ),
        );
      }
      request.dispose();
    }

    if (notifyLoss) {
      try {
        onConnectionLost?.call();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Core processing logic
  // ---------------------------------------------------------------------------

  void _scheduleNextProcess({required bool allowImmediateIfIdle}) {
    if (_disposed ||
        _terminated ||
        _state != _SchedulerState.idle ||
        _queue.isEmpty) {
      return;
    }
    if (_nextProcessTimer != null) {
      return;
    }

    final now = clock.now();
    final nextAllowed = _nextAllowedSendAt;
    if (nextAllowed != null && nextAllowed.isAfter(now)) {
      _nextProcessTimer = Timer(nextAllowed.difference(now), _processNext);
      return;
    }

    if (allowImmediateIfIdle) {
      _processNext();
    } else {
      _nextProcessTimer = Timer(Duration.zero, _processNext);
    }
  }

  void _processNext() {
    // Clear the timer reference since we are now executing
    _nextProcessTimer?.cancel();
    _nextProcessTimer = null;

    if (_disposed ||
        _terminated ||
        _state != _SchedulerState.idle ||
        _queue.isEmpty) {
      return;
    }

    final now = clock.now();
    final nextAllowed = _nextAllowedSendAt;
    if (nextAllowed != null && nextAllowed.isAfter(now)) {
      _nextProcessTimer = Timer(nextAllowed.difference(now), _processNext);
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

    if (_disposed || _terminated || !_subscriptionActive) {
      final reason =
          _terminationReason ??
          (_disposed
              ? SchedulerTerminationReason.disposed
              : SchedulerTerminationReason.receiveStreamUnavailable);
      final inFlight = request.sentRequestCount > 0 || request.attemptCount > 0;
      _demux.discardActive();
      request.completer.completeError(
        DistingSchedulerClosedException(
          reason: reason,
          phase: inFlight
              ? RequestFailurePhase.inFlight
              : RequestFailurePhase.beforeSend,
        ),
      );
      _finishCurrentRequest();
      return;
    }

    try {
      request.preflight?.call();
    } catch (error, stack) {
      request.completer.completeError(error, stack);
      _finishCurrentRequest();
      return;
    }

    if (request.attributionPolicy != ResponseAttributionPolicy.bestEffort &&
        !request.attributionStarted) {
      if (!_strictAttribution._begin(request)) {
        request.completer.completeError(
          AmbiguousResponseAttributionException(),
        );
        _finishCurrentRequest();
        return;
      }
      request.attributionStarted = true;
    } else if (request.attributionPolicy ==
            ResponseAttributionPolicy.bestEffort &&
        request.expectation != ResponseExpectation.none &&
        request.rawResponseMatcher == null &&
        _strictAttribution.hasSessionLossDebt(request.key)) {
      request.completer.completeError(AmbiguousResponseAttributionException());
      _finishCurrentRequest();
      return;
    }

    // If device is suspected broken, settle immediately as terminal without
    // retrying an uncounted attempt.
    if (_deviceConnectionSuspectedBroken) {
      _demux.discardActive();
      request.completer.completeError(
        DistingSchedulerClosedException(
          reason: SchedulerTerminationReason.connectionLost,
          phase: request.attemptCount == 0
              ? RequestFailurePhase.beforeSend
              : RequestFailurePhase.inFlight,
          message: 'Device connection is broken - cannot send',
        ),
      );
      _finishCurrentRequest();
      return;
    }

    request.attemptCount++;
    _diag(
      'send #${request.id} attempt=${request.attemptCount}/'
      '${request.maxAttempts} packetBytes=${request.packet.length} '
      'queue=${_queue.length} key=${request.key}',
    );

    // Start/restart stopwatch for RTT measurement
    request.stopwatch.reset();
    request.stopwatch.start();

    // Register handler with demux BEFORE sending (first attempt only).
    // Handler persists across retries — only moved to expired on final timeout.
    if (request.expectation != ResponseExpectation.none &&
        request.rawResponseMatcher == null) {
      _demux.registerActive(
        request.key,
        (parsed) {
          _onResponseMatched(request, parsed);
        },
        onAmbiguous: () {
          _onResponseAttributionAmbiguous(request);
        },
      );
    }

    // Send the message
    try {
      // Sending can throw after bytes reached the device. Conservatively retain
      // attribution debt even when transmission itself reports failure.
      _strictAttribution._markSent(request);
      _midi.sendData(request.packet, deviceId: _outputDevice.id);
    } catch (e) {
      request.stopwatch.stop();
      if (_disposed || _terminated) return;
      _handleSendFailure(request, e);
      return;
    }

    if (_disposed || _terminated || !identical(_currentRequest, request)) {
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

  void _cancelRequest(_ScheduledRequest request) {
    if (request.completer.isCompleted) return;

    if (identical(_currentRequest, request)) {
      request.timeoutTimer?.cancel();
      _retryTimer?.cancel();
      _retryTimer = null;
      request.stopwatch.stop();
      if (_isBufferingSysEx) {
        _sysExBuffer.clear();
        _isBufferingSysEx = false;
      }
      if (request.attributionStarted) {
        _demux.discardActive();
      } else {
        _demux.expireActive();
      }
      request.completer.completeError(const DistingRequestCancelledException());
      _finishCurrentRequest();
      return;
    }

    if (_queue.remove(request)) {
      request.completer.completeError(const DistingRequestCancelledException());
      request.dispose();
      if (_queue.isEmpty) {
        _nextProcessTimer?.cancel();
        _nextProcessTimer = null;
      }
    }
  }

  void _onResponseAttributionAmbiguous(_ScheduledRequest request) {
    if (_disposed ||
        _terminated ||
        !identical(_currentRequest, request) ||
        request.completer.isCompleted) {
      return;
    }

    request.timeoutTimer?.cancel();
    request.stopwatch.stop();
    request.completer.completeError(AmbiguousResponseAttributionException());
    _finishCurrentRequest();
  }

  /// Called by the demux when a response matches the active handler.
  void _onResponseMatched(
    _ScheduledRequest request,
    DistingNTParsedMessage parsed,
  ) {
    if (_disposed || _terminated) return;
    // Guard against race conditions
    if (request.completer.isCompleted) {
      _finishCurrentRequest();
      return;
    }

    _strictAttribution._markResponse(request);

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
          final shouldRetryParseError =
              e is! TruncatedParameterPagesException &&
              request.replayPolicy == RequestReplayPolicy.allow;
          if (shouldRetryParseError &&
              request.attemptCount < request.maxAttempts) {
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
    if (_disposed || _terminated) return;
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

    if (request.replayPolicy == RequestReplayPolicy.never ||
        request.attemptCount >= request.maxAttempts) {
      // Out of retries — strict requests use shared response debt across
      // manager replacement. Ordinary requests retain the local stale handler;
      // indistinguishable 0x40 attempts are also retained as shared debt.
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
        if (!request.completer.isCompleted) {
          request.completer.completeError(
            TimeoutException(
              'No response after ${request.attemptCount} attempts',
              request.timeout,
            ),
          );
        }
      } else {
        _diag(
          'timeout-final #${request.id} optional attempts=${request.attemptCount} '
          'timeout=${request.timeout.inMilliseconds}ms key=${request.key}',
        );
        if (!request.completer.isCompleted) {
          request.completer.complete(null);
        }
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
    if (_disposed || _terminated) return;
    if (request.completer.isCompleted) {
      _finishCurrentRequest();
      return;
    }

    if (request.replayPolicy == RequestReplayPolicy.never ||
        request.attemptCount >= request.maxAttempts) {
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
    debugPrint('[NT_DIAG scheduler ${clock.now().toIso8601String()}] $message');
  }

  String _hex(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  void _finishCurrentRequest() {
    final finished = _currentRequest;
    _finishResponseAttribution(finished);
    finished?.dispose();
    _currentRequest = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    if (_disposed || _terminated) {
      _state = _SchedulerState.closed;
      return;
    }

    _state = _SchedulerState.idle;
    if (finished != null &&
        finished.attemptCount > 0 &&
        messageInterval > Duration.zero) {
      _nextAllowedSendAt = clock.now().add(messageInterval);
    }

    // Schedule next request after message interval
    if (_queue.isNotEmpty) {
      _scheduleNextProcess(allowImmediateIfIdle: false);
    }
  }

  void _finishResponseAttribution(
    _ScheduledRequest? request, {
    bool sessionLost = false,
  }) {
    if (request == null) return;
    _strictAttribution._finish(request, sessionLost: sessionLost);
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
    if (_disposed || _terminated) return;
    _totalPacketsReceived++;
    _lastPacketTime = clock.now();

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
      final request = _currentRequest;
      if (request != null &&
          !request.completer.isCompleted &&
          request.rawResponseMatcher?.call(sysex) == true) {
        request.timeoutTimer?.cancel();
        request.stopwatch.stop();
        _consecutiveTimeouts = 0;
        request.completer.complete(sysex);
        _finishCurrentRequest();
        return;
      }
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
