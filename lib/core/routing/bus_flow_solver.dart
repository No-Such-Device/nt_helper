import 'package:nt_helper/cubit/routing_editor_state.dart';
import 'package:nt_helper/models/device_io_profile.dart';

/// Minimal description of how one algorithm slot uses buses, for flow solving.
class SlotBusUsage {
  /// Stable algorithm id.
  final String id;

  /// Current slot index (evaluation order).
  final int index;

  /// Algorithm name (for diagnostics/messages).
  final String name;

  /// Bus numbers this slot reads (input ports).
  final Set<int> reads;

  /// Bus numbers this slot writes (output ports).
  final Set<int> writes;

  const SlotBusUsage({
    required this.id,
    required this.index,
    required this.name,
    required this.reads,
    required this.writes,
  });
}

/// A writer→reader dependency that the slot order cannot satisfy forward, so
/// the reader sees the writer's signal one frame late (feedback / backward edge).
class BusFlowEdge {
  final String fromId; // writer
  final String toId; // reader
  final int bus;

  const BusFlowEdge({
    required this.fromId,
    required this.toId,
    required this.bus,
  });

  @override
  bool operator ==(Object other) =>
      other is BusFlowEdge &&
      other.fromId == fromId &&
      other.toId == toId &&
      other.bus == bus;

  @override
  int get hashCode => Object.hash(fromId, toId, bus);

  @override
  String toString() => 'BusFlowEdge($fromId -> $toId on bus $bus)';
}

/// Result of solving the slot order from bus connections.
class BusFlowSolution {
  /// Target slot order (algorithm ids, slot 0..n-1).
  final List<String> order;

  /// True when [order] differs from the current slot order.
  final bool reorderNeeded;

  /// Dependencies that remain backward in [order] (unavoidable feedback).
  final List<BusFlowEdge> backwardEdges;

  const BusFlowSolution({
    required this.order,
    required this.reorderNeeded,
    required this.backwardEdges,
  });
}

/// Computes a valid slot order from bus connections.
///
/// The Disting NT evaluates slots top→bottom and signal only flows downward, so
/// a reader of a bus sees a writer's signal only when the writer is in an
/// earlier slot. This solver builds a precedence DAG (writer → reader for each
/// shared, order-relevant bus) and produces a topological order that keeps the
/// current order wherever the dependencies allow. Cycles (genuine feedback) are
/// not an error: they degrade to [BusFlowSolution.backwardEdges].
///
/// Physical input buses (1-12) are hardware-seeded, so reads of them are always
/// satisfied and create no ordering constraint. Bus identity is kept as integer
/// numbers (not bit masks), so the full extended range is supported.
class BusFlowSolver {
  /// Slots sorted by current index (ascending).
  final List<SlotBusUsage> _slots;
  final DeviceIoProfile deviceIoProfile;

  BusFlowSolver(
    List<SlotBusUsage> slots, {
    this.deviceIoProfile = DeviceIoProfile.distingExtended,
  }) : _slots = List<SlotBusUsage>.from(slots)
         ..sort((a, b) => a.index.compareTo(b.index));

  /// Builds a solver from routing-editor algorithm data.
  factory BusFlowSolver.fromAlgorithms(
    List<RoutingAlgorithm> algorithms, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) {
    final slots = algorithms.map((a) {
      final reads = <int>{};
      for (final p in a.inputPorts) {
        final b = p.busValue;
        if (b != null && b > 0) reads.add(b);
      }
      final writes = <int>{};
      for (final p in a.outputPorts) {
        final b = p.busValue;
        if (b != null && b > 0) writes.add(b);
      }
      return SlotBusUsage(
        id: a.id,
        index: a.index,
        name: a.algorithm.name,
        reads: reads,
        writes: writes,
      );
    }).toList();
    return BusFlowSolver(slots, deviceIoProfile: deviceIoProfile);
  }

  /// Whether reads of [bus] impose a slot-ordering constraint. Physical input
  /// buses (1-12) are hardware-seeded and never do.
  static bool busOrdersReads(
    int bus, {
    DeviceIoProfile deviceIoProfile = DeviceIoProfile.distingExtended,
  }) => deviceIoProfile.contains(bus) && !deviceIoProfile.isInput(bus);

  BusFlowSolution solve() {
    final currentOrder = _slots.map((s) => s.id).toList();
    final n = _slots.length;
    if (n <= 1) {
      return BusFlowSolution(
        order: currentOrder,
        reorderNeeded: false,
        backwardEdges: const [],
      );
    }

    // Index writers/readers by bus.
    final writersByBus = <int, List<String>>{};
    final readersByBus = <int, List<String>>{};
    for (final s in _slots) {
      for (final b in s.writes) {
        (writersByBus[b] ??= []).add(s.id);
      }
      for (final b in s.reads) {
        if (busOrdersReads(b, deviceIoProfile: deviceIoProfile)) {
          (readersByBus[b] ??= []).add(s.id);
        }
      }
    }

    // Build precedence edges writer → reader, tracking the buses behind each.
    final successors = {for (final s in _slots) s.id: <String>{}};
    final inDegree = {for (final s in _slots) s.id: 0};
    final edgeBuses = <String, Map<String, Set<int>>>{}; // from -> to -> buses

    void addEdge(String from, String to, int bus) {
      final isNew = successors[from]!.add(to);
      ((edgeBuses[from] ??= {})[to] ??= {}).add(bus);
      if (isNew) inDegree[to] = inDegree[to]! + 1;
    }

    readersByBus.forEach((bus, readers) {
      final writers = writersByBus[bus];
      if (writers == null) return; // undriven bus: no source to order against
      for (final w in writers) {
        for (final r in readers) {
          if (w != r) addEdge(w, r, bus);
        }
      }
    });

    // Stable Kahn topological sort: always take the available (in-degree 0)
    // node with the smallest current index, so the order stays as close to the
    // current order as the dependencies permit.
    final remaining = {for (final s in _slots) s.id};
    final inDeg = Map<String, int>.from(inDegree);
    final order = <String>[];

    while (remaining.isNotEmpty) {
      String? pick;
      for (final id in currentOrder) {
        if (remaining.contains(id) && inDeg[id] == 0) {
          pick = id;
          break;
        }
      }
      // Cycle: no node is free. Force the remaining node with the smallest
      // current index; its unmet incoming edges become backward edges.
      pick ??= currentOrder.firstWhere(remaining.contains);

      remaining.remove(pick);
      order.add(pick);
      for (final succ in successors[pick]!) {
        if (remaining.contains(succ)) inDeg[succ] = inDeg[succ]! - 1;
      }
    }

    // Any edge whose reader ends up before its writer is a backward edge.
    final pos = {for (var i = 0; i < order.length; i++) order[i]: i};
    final backward = <BusFlowEdge>[];
    edgeBuses.forEach((from, tos) {
      tos.forEach((to, buses) {
        if (pos[to]! < pos[from]!) {
          for (final b in buses) {
            backward.add(BusFlowEdge(fromId: from, toId: to, bus: b));
          }
        }
      });
    });
    backward.sort((a, b) {
      final c = a.fromId.compareTo(b.fromId);
      if (c != 0) return c;
      final d = a.toId.compareTo(b.toId);
      if (d != 0) return d;
      return a.bus.compareTo(b.bus);
    });

    return BusFlowSolution(
      order: order,
      reorderNeeded: !_listEquals(order, currentOrder),
      backwardEdges: backward,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
