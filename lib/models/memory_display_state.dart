import 'package:flutter/foundation.dart';
import 'package:nt_helper/models/memory_usage.dart';

/// The connection-local state shown by memory display consumers.
enum MemoryDisplayStatus { unavailable, refreshing, available, unfresh }

/// A display snapshot and its current freshness state.
///
/// A previous successful [sample] remains present while a refresh is running
/// and after a refresh fails. An unavailable state never fabricates a sample.
@immutable
final class MemoryDisplayState {
  const MemoryDisplayState._({required this.status, this.sample});

  const MemoryDisplayState.unavailable()
    : this._(status: MemoryDisplayStatus.unavailable);

  const MemoryDisplayState.refreshing({MemoryUsage? previousSample})
    : this._(status: MemoryDisplayStatus.refreshing, sample: previousSample);

  const MemoryDisplayState.available(MemoryUsage sample)
    : this._(status: MemoryDisplayStatus.available, sample: sample);

  const MemoryDisplayState.unfresh(MemoryUsage sample)
    : this._(status: MemoryDisplayStatus.unfresh, sample: sample);

  final MemoryDisplayStatus status;
  final MemoryUsage? sample;

  bool get isRefreshing => status == MemoryDisplayStatus.refreshing;
  bool get isUnfresh => status == MemoryDisplayStatus.unfresh;
  bool get isAvailable => status == MemoryDisplayStatus.available;
}
