import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/ui/widgets/routing/bus_label_formatter.dart';

void main() {
  group('BusLabelFormatter', () {
    group('formatBusNumber', () {
      test('formats standard buses correctly', () {
        expect(BusLabelFormatter.formatBusNumber(1), 'I1');
        expect(BusLabelFormatter.formatBusNumber(12), 'I12');
        expect(BusLabelFormatter.formatBusNumber(13), 'O1');
        expect(BusLabelFormatter.formatBusNumber(20), 'O8');
        expect(BusLabelFormatter.formatBusNumber(21), 'A1');
        expect(BusLabelFormatter.formatBusNumber(28), 'A8');
      });

      test('formats legacy ES-5 buses (29-30)', () {
        expect(BusLabelFormatter.formatBusNumber(29), 'ES-5 L');
        expect(BusLabelFormatter.formatBusNumber(30), 'ES-5 R');
      });

      test('formats extended aux buses (31-64)', () {
        expect(
          BusLabelFormatter.formatBusNumber(31, hasExtendedAuxBuses: true),
          'A11',
        );
        expect(
          BusLabelFormatter.formatBusNumber(42, hasExtendedAuxBuses: true),
          'A22',
        );
        expect(
          BusLabelFormatter.formatBusNumber(64, hasExtendedAuxBuses: true),
          'A44',
        );
      });

      test('formats extended ES-5 buses (65-66)', () {
        expect(
          BusLabelFormatter.formatBusNumber(65, hasExtendedAuxBuses: true),
          'ES-5 L',
        );
        expect(
          BusLabelFormatter.formatBusNumber(66, hasExtendedAuxBuses: true),
          'ES-5 R',
        );
      });

      test('returns null for invalid bus numbers', () {
        expect(BusLabelFormatter.formatBusNumber(0), isNull);
        expect(BusLabelFormatter.formatBusNumber(67), isNull);
        expect(BusLabelFormatter.formatBusNumber(null), isNull);
      });
    });

    group('getBusType', () {
      test('classifies extended ES-5 buses as es5', () {
        expect(
          BusLabelFormatter.getBusType(65, hasExtendedAuxBuses: true),
          BusType.es5,
        );
        expect(
          BusLabelFormatter.getBusType(66, hasExtendedAuxBuses: true),
          BusType.es5,
        );
      });

      test('classifies legacy ES-5 buses as es5', () {
        expect(BusLabelFormatter.getBusType(29), BusType.es5);
        expect(BusLabelFormatter.getBusType(30), BusType.es5);
      });

      test('classifies aux buses correctly', () {
        expect(BusLabelFormatter.getBusType(21), BusType.auxiliary);
        expect(
          BusLabelFormatter.getBusType(31, hasExtendedAuxBuses: true),
          BusType.auxiliary,
        );
        expect(
          BusLabelFormatter.getBusType(64, hasExtendedAuxBuses: true),
          BusType.auxiliary,
        );
      });
    });

    group('getLocalBusNumber', () {
      test('returns correct local number for extended ES-5', () {
        expect(
          BusLabelFormatter.getLocalBusNumber(65, hasExtendedAuxBuses: true),
          1,
        );
        expect(
          BusLabelFormatter.getLocalBusNumber(66, hasExtendedAuxBuses: true),
          2,
        );
      });

      test('returns correct local number for legacy ES-5', () {
        expect(BusLabelFormatter.getLocalBusNumber(29), 1);
        expect(BusLabelFormatter.getLocalBusNumber(30), 2);
      });

      test('returns correct local number for extended aux', () {
        expect(
          BusLabelFormatter.getLocalBusNumber(
            31,
            hasExtendedAuxBuses: true,
          ),
          11,
        );
        expect(
          BusLabelFormatter.getLocalBusNumber(
            42,
            hasExtendedAuxBuses: true,
          ),
          22,
        );
        expect(
          BusLabelFormatter.getLocalBusNumber(
            64,
            hasExtendedAuxBuses: true,
          ),
          44,
        );
      });
    });

    group('firmware-aware formatting (1.15+)', () {
      test('buses 29-30 are aux on extended firmware', () {
        expect(
          BusLabelFormatter.formatBusNumber(29, hasExtendedAuxBuses: true),
          'A9',
        );
        expect(
          BusLabelFormatter.formatBusNumber(30, hasExtendedAuxBuses: true),
          'A10',
        );
      });

      test('buses 65-66 are ES-5 on extended firmware', () {
        expect(
          BusLabelFormatter.formatBusNumber(65, hasExtendedAuxBuses: true),
          'ES-5 L',
        );
        expect(
          BusLabelFormatter.formatBusNumber(66, hasExtendedAuxBuses: true),
          'ES-5 R',
        );
      });

      test('getBusType classifies 29-30 as auxiliary on extended firmware', () {
        expect(
          BusLabelFormatter.getBusType(29, hasExtendedAuxBuses: true),
          BusType.auxiliary,
        );
        expect(
          BusLabelFormatter.getBusType(30, hasExtendedAuxBuses: true),
          BusType.auxiliary,
        );
      });

      test(
        'getLocalBusNumber returns 9-10 for buses 29-30 on extended firmware',
        () {
          expect(
            BusLabelFormatter.getLocalBusNumber(29, hasExtendedAuxBuses: true),
            9,
          );
          expect(
            BusLabelFormatter.getLocalBusNumber(30, hasExtendedAuxBuses: true),
            10,
          );
        },
      );

      test('all 44 aux buses labeled A1-A44 on extended firmware', () {
        // Buses 21-64, all aux (no ES-5 gap at 29-30)
        for (int b = 21; b <= 64; b++) {
          final label = BusLabelFormatter.formatBusNumber(
            b,
            hasExtendedAuxBuses: true,
          );
          expect(label, startsWith('A'), reason: 'Bus $b should be aux');
        }
        expect(
          BusLabelFormatter.formatBusNumber(21, hasExtendedAuxBuses: true),
          'A1',
        );
        expect(
          BusLabelFormatter.formatBusNumber(64, hasExtendedAuxBuses: true),
          'A44',
        );
      });
    });

    group('isValidBusNumber', () {
      test('accepts extended range up to 66', () {
        expect(
          BusLabelFormatter.isValidBusNumber(
            64,
            hasExtendedAuxBuses: true,
          ),
          isTrue,
        );
        expect(
          BusLabelFormatter.isValidBusNumber(
            65,
            hasExtendedAuxBuses: true,
          ),
          isTrue,
        );
        expect(
          BusLabelFormatter.isValidBusNumber(
            66,
            hasExtendedAuxBuses: true,
          ),
          isTrue,
        );
        expect(
          BusLabelFormatter.isValidBusNumber(
            67,
            hasExtendedAuxBuses: true,
          ),
          isFalse,
        );
      });
    });
  });
}
