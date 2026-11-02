import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/core/routing/aux_bus_consolidation.dart';

AuxBusPort src(int slot, int busParam, int mode,
        {bool isReplace = false, bool canReplace = true}) =>
    AuxBusPort(
      slot: slot,
      busParameterNumber: busParam,
      isSource: true,
      canReplace: canReplace,
      isReplace: isReplace,
      modeParameterNumber: canReplace ? mode : null,
    );

AuxBusPort read(int slot, int busParam) =>
    AuxBusPort(slot: slot, busParameterNumber: busParam, isSource: false);

void main() {
  group('planAuxBusConsolidation', () {
    test('packs disjoint sessions and preserves an in-session Add mix', () {
      // Bus 21: two sources Add-summing into one send (slots 0 and 1), read at
      // slot 2. Bus 22: a separate session entirely above it (source slot 5,
      // read slot 6).
      final buses = [
        AuxBusUsage(bus: 21, ports: [
          src(0, 10, 100),
          src(1, 11, 101), // mid-session Add — must NOT be touched
          read(2, 12),
        ]),
        AuxBusUsage(bus: 22, ports: [
          src(5, 20, 120),
          read(6, 21),
        ]),
      ];

      final merges = planAuxBusConsolidation(buses);

      expect(merges, hasLength(1));
      final m = merges.single;
      expect(m.keepBus, 21, reason: 'lower session keeps its bus');
      expect(m.freeBus, 22);

      // Bus 22's ports move onto 21.
      expect(
        m.moves.map((x) => x.slot).toSet(),
        {5, 6},
      );
      expect(m.moves.every((x) => x.toBus == 21 && x.fromBus == 22), isTrue);

      // Exactly one boundary Replace: bus 22's first source (slot 5).
      // The mid-session Add at slot 1 must never be flipped to Replace.
      expect(m.replaces.map((r) => r.slot).toList(), [5]);
      expect(m.replaces.any((r) => r.slot == 1 || r.slot == 0), isFalse);
    }, tags: ['regression']);

    test('leaves overlapping sessions untouched', () {
      final buses = [
        AuxBusUsage(bus: 21, ports: [src(0, 10, 100), read(5, 12)]), // [0,5]
        AuxBusUsage(bus: 22, ports: [src(2, 20, 120), read(6, 21)]), // [2,6]
      ];

      expect(planAuxBusConsolidation(buses), isEmpty);
    });

    test('excludes a bus that reads below its first write (feedback)', () {
      final buses = [
        // Read at slot 0 sits below the first write at slot 2 → ineligible.
        AuxBusUsage(bus: 21, ports: [read(0, 12), src(2, 10, 100), read(3, 13)]),
        AuxBusUsage(bus: 22, ports: [src(5, 20, 120), read(6, 21)]),
      ];

      expect(planAuxBusConsolidation(buses), isEmpty);
    });
  });
}
