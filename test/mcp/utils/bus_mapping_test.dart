import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart' show ParameterInfo;
import 'package:nt_helper/mcp/utils/bus_mapping.dart';

void main() {
  group('BusMapping', () {
    group('busToName', () {
      test('returns None for bus 0', () {
        expect(BusMapping.busToName(0, hasExtendedAuxBuses: false), 'None');
      });

      test('returns correct names for input buses 1-12', () {
        for (var i = 1; i <= 12; i++) {
          expect(
            BusMapping.busToName(i, hasExtendedAuxBuses: false),
            'Input $i',
          );
        }
      });

      test('returns correct names for output buses 13-20', () {
        for (var i = 1; i <= 8; i++) {
          expect(
            BusMapping.busToName(12 + i, hasExtendedAuxBuses: false),
            'Output $i',
          );
        }
      });

      test('returns correct names for aux buses 21-28 (pre-1.15)', () {
        for (var i = 1; i <= 8; i++) {
          expect(
            BusMapping.busToName(20 + i, hasExtendedAuxBuses: false),
            'Aux $i',
          );
        }
      });

      test('returns ES-5 L/R for buses 29-30 (pre-1.15)', () {
        expect(BusMapping.busToName(29, hasExtendedAuxBuses: false), 'ES-5 L');
        expect(BusMapping.busToName(30, hasExtendedAuxBuses: false), 'ES-5 R');
      });

      test('returns ES-5 L/R for buses 65-66 (extended firmware)', () {
        expect(BusMapping.busToName(65, hasExtendedAuxBuses: true), 'ES-5 L');
        expect(BusMapping.busToName(66, hasExtendedAuxBuses: true), 'ES-5 R');
      });

      test('treats 29-30 as Aux on extended firmware', () {
        expect(BusMapping.busToName(29, hasExtendedAuxBuses: true), 'Aux 9');
        expect(BusMapping.busToName(30, hasExtendedAuxBuses: true), 'Aux 10');
      });

      test('returns extended aux names on 1.15+', () {
        expect(BusMapping.busToName(44, hasExtendedAuxBuses: true), 'Aux 24');
        expect(BusMapping.busToName(64, hasExtendedAuxBuses: true), 'Aux 44');
      });

      test('returns Unknown for out-of-range', () {
        expect(
          BusMapping.busToName(-1, hasExtendedAuxBuses: false),
          'Unknown (-1)',
        );
        expect(
          BusMapping.busToName(100, hasExtendedAuxBuses: false),
          'Unknown (100)',
        );
      });
    });

    group('nameToBus', () {
      test('returns 0 for None', () {
        expect(BusMapping.nameToBus('None', hasExtendedAuxBuses: false), 0);
      });

      test('returns correct bus for Input names', () {
        expect(BusMapping.nameToBus('Input 1', hasExtendedAuxBuses: false), 1);
        expect(
          BusMapping.nameToBus('Input 12', hasExtendedAuxBuses: false),
          12,
        );
      });

      test('returns correct bus for Output names', () {
        expect(
          BusMapping.nameToBus('Output 1', hasExtendedAuxBuses: false),
          13,
        );
        expect(
          BusMapping.nameToBus('Output 8', hasExtendedAuxBuses: false),
          20,
        );
      });

      test('returns correct bus for Aux names', () {
        expect(BusMapping.nameToBus('Aux 1', hasExtendedAuxBuses: false), 21);
        expect(BusMapping.nameToBus('Aux 8', hasExtendedAuxBuses: false), 28);
      });

      test('returns correct bus for ES-5 names (pre-1.15)', () {
        expect(BusMapping.nameToBus('ES-5 L', hasExtendedAuxBuses: false), 29);
        expect(BusMapping.nameToBus('ES-5 R', hasExtendedAuxBuses: false), 30);
      });

      test('returns correct bus for ES-5 names (extended)', () {
        expect(BusMapping.nameToBus('ES-5 L', hasExtendedAuxBuses: true), 65);
        expect(BusMapping.nameToBus('ES-5 R', hasExtendedAuxBuses: true), 66);
      });

      test('is case-insensitive', () {
        expect(BusMapping.nameToBus('input 1', hasExtendedAuxBuses: false), 1);
        expect(BusMapping.nameToBus('INPUT 1', hasExtendedAuxBuses: false), 1);
        expect(BusMapping.nameToBus('none', hasExtendedAuxBuses: false), 0);
        expect(BusMapping.nameToBus('NONE', hasExtendedAuxBuses: false), 0);
        expect(BusMapping.nameToBus('es-5 l', hasExtendedAuxBuses: false), 29);
        expect(BusMapping.nameToBus('ES-5 R', hasExtendedAuxBuses: false), 30);
      });

      test('trims whitespace', () {
        expect(
          BusMapping.nameToBus('  Input 1  ', hasExtendedAuxBuses: false),
          1,
        );
        expect(BusMapping.nameToBus('  None  ', hasExtendedAuxBuses: false), 0);
      });

      test('returns null for unknown names', () {
        expect(
          BusMapping.nameToBus('Unknown', hasExtendedAuxBuses: false),
          isNull,
        );
        expect(BusMapping.nameToBus('', hasExtendedAuxBuses: false), isNull);
        expect(
          BusMapping.nameToBus('Input', hasExtendedAuxBuses: false),
          isNull,
        );
        expect(
          BusMapping.nameToBus('Bus 1', hasExtendedAuxBuses: false),
          isNull,
        );
      });

      test('returns null for out-of-range numbers', () {
        expect(
          BusMapping.nameToBus('Input 13', hasExtendedAuxBuses: false),
          isNull,
        );
        expect(
          BusMapping.nameToBus('Output 9', hasExtendedAuxBuses: false),
          isNull,
        );
        expect(
          BusMapping.nameToBus('Input 0', hasExtendedAuxBuses: false),
          isNull,
        );
      });

      test('rejects aux in ES-5 range on old firmware', () {
        // On pre-1.15, buses 29-30 are ES-5, not aux
        // Aux 9 would be bus 29 which is ES-5
        expect(
          BusMapping.nameToBus('Aux 9', hasExtendedAuxBuses: false),
          isNull,
        );
      });

      test('accepts extended aux on 1.15+', () {
        expect(BusMapping.nameToBus('Aux 9', hasExtendedAuxBuses: true), 29);
        expect(BusMapping.nameToBus('Aux 44', hasExtendedAuxBuses: true), 64);
      });
    });

    group('parseBus', () {
      test('parses valid int bus numbers', () {
        expect(BusMapping.parseBus(0, hasExtendedAuxBuses: false), 0);
        expect(BusMapping.parseBus(1, hasExtendedAuxBuses: false), 1);
        expect(BusMapping.parseBus(28, hasExtendedAuxBuses: false), 28);
      });

      test('returns null for invalid int bus numbers', () {
        expect(BusMapping.parseBus(-1, hasExtendedAuxBuses: false), isNull);
        expect(BusMapping.parseBus(100, hasExtendedAuxBuses: false), isNull);
      });

      test('parses numeric strings', () {
        expect(BusMapping.parseBus('0', hasExtendedAuxBuses: false), 0);
        expect(BusMapping.parseBus('1', hasExtendedAuxBuses: false), 1);
        expect(BusMapping.parseBus('28', hasExtendedAuxBuses: false), 28);
      });

      test('parses name strings', () {
        expect(BusMapping.parseBus('None', hasExtendedAuxBuses: false), 0);
        expect(BusMapping.parseBus('Input 1', hasExtendedAuxBuses: false), 1);
        expect(BusMapping.parseBus('Output 1', hasExtendedAuxBuses: false), 13);
        expect(BusMapping.parseBus('Aux 1', hasExtendedAuxBuses: false), 21);
        expect(BusMapping.parseBus('ES-5 L', hasExtendedAuxBuses: false), 29);
      });

      test('parses case-insensitively', () {
        expect(BusMapping.parseBus('none', hasExtendedAuxBuses: false), 0);
        expect(BusMapping.parseBus('input 1', hasExtendedAuxBuses: false), 1);
      });

      test('returns null for non-int non-string types', () {
        expect(BusMapping.parseBus(1.5, hasExtendedAuxBuses: false), isNull);
        expect(BusMapping.parseBus(true, hasExtendedAuxBuses: false), isNull);
        expect(BusMapping.parseBus(null, hasExtendedAuxBuses: false), isNull);
      });
    });

    group('isBusParameter', () {
      ParameterInfo makeParam({
        required int unit,
        required int min,
        required int max,
      }) {
        return ParameterInfo(
          algorithmIndex: 0,
          parameterNumber: 0,
          min: min,
          max: max,
          defaultValue: 0,
          unit: unit,
          name: 'test',
          powerOfTen: 0,
          ioFlags: 0,
        );
      }

      test('returns true for bus parameters', () {
        // unit=1, min=0, max=28 (pre-1.15 aux max)
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 0, max: 28)),
          isTrue,
        );
        // unit=1, min=0, max=30 (pre-1.15 with ES-5)
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 0, max: 30)),
          isTrue,
        );
        // unit=1, min=1, max=66 (extended)
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 1, max: 66)),
          isTrue,
        );
        // unit=1, min=0, max=64 (extended aux only)
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 0, max: 64)),
          isTrue,
        );
      });

      test('returns false for non-bus parameters', () {
        // Wrong unit
        expect(
          BusMapping.isBusParameter(makeParam(unit: 0, min: 0, max: 28)),
          isFalse,
        );
        // unit=1 but max too small (regular enum)
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 0, max: 5)),
          isFalse,
        );
        // unit=1 but min too high
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 5, max: 28)),
          isFalse,
        );
        // A broader advertised range is still intersected with the profile.
        expect(
          BusMapping.isBusParameter(makeParam(unit: 1, min: 0, max: 100)),
          isTrue,
        );
      });
    });

    group('round-trip consistency', () {
      test('busToName → nameToBus round-trips for all pre-1.15 buses', () {
        // 0 (None), 1-12 (Input), 13-20 (Output), 21-28 (Aux), 29-30 (ES-5)
        for (var i = 0; i <= 30; i++) {
          final name = BusMapping.busToName(i, hasExtendedAuxBuses: false);
          if (name.startsWith('Unknown')) continue;
          final back = BusMapping.nameToBus(name, hasExtendedAuxBuses: false);
          expect(back, i, reason: 'Round-trip failed for bus $i ($name)');
        }
      });

      test('busToName → nameToBus round-trips for extended firmware', () {
        for (var i = 0; i <= 66; i++) {
          final name = BusMapping.busToName(i, hasExtendedAuxBuses: true);
          if (name.startsWith('Unknown')) continue;
          final back = BusMapping.nameToBus(name, hasExtendedAuxBuses: true);
          expect(back, i, reason: 'Round-trip failed for bus $i ($name)');
        }
      });
    });
  });
}
