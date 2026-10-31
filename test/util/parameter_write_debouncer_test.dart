import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/util/parameter_write_debouncer.dart';

void main() {
  group('ParameterWriteDebouncer Tests', () {
    late ParameterWriteDebouncer debouncer;

    setUp(() => debouncer = ParameterWriteDebouncer());
    tearDown(() => debouncer.dispose());

    test('schedules callback after delay', () {
      fakeAsync((async) {
        var callbackExecuted = false;
        debouncer.schedule('test', () {
          callbackExecuted = true;
        }, const Duration(milliseconds: 50));

        expect(callbackExecuted, isFalse);
        async.elapse(const Duration(milliseconds: 49));
        expect(callbackExecuted, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(callbackExecuted, isTrue);
      });
    });

    test('debounces rapid calls - only executes final callback', () {
      fakeAsync((async) {
        var callCount = 0;
        var lastValue = 0;
        for (var i = 0; i < 10; i++) {
          debouncer.schedule('test', () {
            callCount++;
            lastValue = i;
          }, const Duration(milliseconds: 50));
          async.elapse(const Duration(milliseconds: 5));
          expect(callCount, 0);
        }

        async.elapse(const Duration(milliseconds: 44));
        expect(callCount, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(callCount, 1);
        expect(lastValue, 9);
      });
    });

    test('handles multiple keys independently', () {
      fakeAsync((async) {
        var key1CallCount = 0;
        var key2CallCount = 0;
        debouncer.schedule('key1', () {
          key1CallCount++;
        }, const Duration(milliseconds: 50));
        debouncer.schedule('key2', () {
          key2CallCount++;
        }, const Duration(milliseconds: 50));

        async.elapse(const Duration(milliseconds: 50));
        expect(key1CallCount, 1);
        expect(key2CallCount, 1);
      });
    });

    test('dispose cancels all pending timers', () {
      fakeAsync((async) {
        var callbackExecuted = false;
        debouncer.schedule('test', () {
          callbackExecuted = true;
        }, const Duration(milliseconds: 50));
        debouncer.dispose();
        async.elapse(const Duration(milliseconds: 100));
        expect(callbackExecuted, isFalse);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('pendingCount tracks active timers', () {
      fakeAsync((async) {
        expect(debouncer.pendingCount, 0);
        debouncer.schedule('key1', () {}, const Duration(milliseconds: 100));
        expect(debouncer.pendingCount, 1);
        debouncer.schedule('key2', () {}, const Duration(milliseconds: 100));
        expect(debouncer.pendingCount, 2);
        debouncer.schedule('key1', () {}, const Duration(milliseconds: 100));
        expect(debouncer.pendingCount, 2);
        debouncer.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('clears pending count after execution', () {
      fakeAsync((async) {
        debouncer.schedule('test', () {}, const Duration(milliseconds: 50));
        expect(debouncer.pendingCount, 1);
        async.elapse(const Duration(milliseconds: 50));
        expect(debouncer.pendingCount, 0);
      });
    });
  });
}
