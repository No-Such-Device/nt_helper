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

    test(
      'flush sends the latest accepted inputs once before another editor acts',
      () {
        fakeAsync((async) {
          final values = <int>[];
          debouncer.schedule(
            'pitch',
            () => values.add(1),
            const Duration(milliseconds: 50),
          );
          debouncer.schedule(
            'pitch',
            () => values.add(2),
            const Duration(milliseconds: 50),
          );
          debouncer.schedule(
            'glide',
            () => values.add(3),
            const Duration(milliseconds: 50),
          );
          debouncer.flush();
          expect(values, [2, 3]);
          expect(debouncer.pendingCount, 0);
          expect(async.pendingTimers, isEmpty);
          async.elapse(const Duration(milliseconds: 100));
          expect(values, [2, 3]);
        });
      },
    );

    test(
      'cancellation releases replaced and disposed work but not completed work',
      () {
        fakeAsync((async) {
          final cancelled = <String>[];
          debouncer.schedule(
            'pitch',
            () {},
            const Duration(milliseconds: 50),
            onCancel: () => cancelled.add('old'),
          );
          debouncer.schedule(
            'pitch',
            () {},
            const Duration(milliseconds: 50),
            onCancel: () => cancelled.add('new'),
          );
          expect(cancelled, ['old']);
          debouncer.flush();
          expect(cancelled, ['old']);
          debouncer.schedule(
            'glide',
            () {},
            const Duration(milliseconds: 50),
            onCancel: () => cancelled.add('disposed'),
          );
          debouncer.dispose();
          expect(cancelled, ['old', 'disposed']);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );

    test('cancelling one component leaves another component pending', () {
      fakeAsync((async) {
        final values = <int>[];
        debouncer.schedule(
          'step_0',
          () => values.add(1),
          const Duration(milliseconds: 50),
        );
        debouncer.schedule(
          'param_2',
          () => values.add(2),
          const Duration(milliseconds: 50),
        );
        debouncer.cancel('step_0');
        async.elapse(const Duration(milliseconds: 50));
        expect(values, [2]);
      });
    });

    test('failed flush leaves unsubmitted work cancellable, not orphaned', () {
      fakeAsync((async) {
        var cancelled = false;
        debouncer.schedule(
          'failing',
          () => throw StateError('send failed'),
          const Duration(milliseconds: 50),
        );
        debouncer.schedule(
          'pending',
          () {},
          const Duration(milliseconds: 50),
          onCancel: () => cancelled = true,
        );
        expect(debouncer.flush, throwsStateError);
        expect(debouncer.pendingCount, 1);
        debouncer.dispose();
        expect(cancelled, isTrue);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });
}
