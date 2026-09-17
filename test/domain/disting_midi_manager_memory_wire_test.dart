import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/domain/disting_message_scheduler.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/memory_wire_harness.dart';

const int _sysExId = memoryWireSysExId;
typedef _MemoryWireHarness = MemoryWireHarness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'request_timeout_ms': 10,
      'inter_message_delay_ms': 0,
    });
    await SettingsService().init();
  });

  test('sends the exact request and returns only total/current/free', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final future = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);

    final request = harness.memoryRequests.single;
    expect(request, hasLength(21));
    expect(request, [
      0xF0,
      0x00,
      0x21,
      0x27,
      0x6D,
      _sysExId,
      0x39,
      0x6E,
      0x6F,
      0x74,
      0x65,
      0x03,
      0x7F,
      0x7C,
      0x00,
      0x24,
      0x34,
      0x00,
      0x00,
      0x00,
      0xF7,
    ]);

    harness.injectMemory(
      values: const [
        1000,
        2000,
        3000,
        4000,
        100,
        2500,
        0,
        4000,
        91,
        92,
        93,
        94,
      ],
    );
    final result = await future;

    expect(result, isNotNull);
    expect(result!.sram.total, 1000);
    expect(result.sram.current, 100);
    expect(result.sram.free, 900);
    expect(result.dram.total, 2000);
    expect(result.dram.current, 2500);
    expect(result.dram.free, -500);
    expect(result.dtc.total, 3000);
    expect(result.dtc.current, 0);
    expect(result.dtc.free, 3000);
    expect(result.itc.total, 4000);
    expect(result.itc.current, 4000);
    expect(result.itc.free, 0);
  });

  test('ignores wrong-device and wrong-command frames', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final future = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);

    harness.injectMemory(sysExId: _sysExId + 1);
    harness.injectMemory(command: 0x38);
    await Future<void>.delayed(Duration.zero);
    expect(harness.memoryRequests, hasLength(1));

    harness.injectMemory();
    expect(await future, isNotNull);
  });

  test(
    'malformed status fails explicitly instead of returning zeros',
    () async {
      final harness = _MemoryWireHarness(autoMemoryStatus: 2);
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      await expectLater(
        harness.manager.requestMemoryUsage(input),
        throwsA(isA<StateError>()),
      );
      expect(harness.memoryRequests, hasLength(5));
    },
  );

  test('serializes concurrent memory requests through the scheduler', () async {
    final harness = _MemoryWireHarness();
    addTearDown(harness.close);
    final input = await harness.catalogueInput();

    final first = harness.manager.requestMemoryUsage(input);
    final second = harness.manager.requestMemoryUsage(input);
    await Future<void>.delayed(Duration.zero);
    expect(harness.memoryRequests, hasLength(1));

    harness.injectMemory();
    expect(await first, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(harness.memoryRequests, hasLength(2));

    harness.injectMemory();
    expect(await second, isNotNull);
  });

  test(
    'a delayed timed-out response cannot complete the next memory query',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      final timedOut = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(5);
      await expectLater(timedOut, throwsA(isA<TimeoutException>()));

      final fresh = harness.manager.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 91, 92, 93, 94, 1, 2, 3, 4],
      );

      await freshFailure;
      expect(harness.memoryRequests, hasLength(5));
    },
  );

  test(
    'extra retry responses make a newer memory query fail explicitly',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();

      final retried = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(2);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );
      final retriedResult = await retried;
      expect(retriedResult?.sram.current, 10);

      final fresh = harness.manager.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );

      await freshFailure;
      await Future<void>.delayed(Duration.zero);
      expect(harness.memoryRequests, hasLength(2));

      final recovered = harness.manager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(3);
      harness.injectMemory(
        values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
      );
      final recoveredResult = await recovered;
      expect(recoveredResult?.sram.current, 50);
    },
  );

  test(
    'connection replacement rejects a response from the disposed manager',
    () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();
      final oldManager = harness.manager;

      final oldQuery = oldManager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(1);
      oldManager.dispose();
      await expectLater(oldQuery, throwsA(isA<StateError>()));

      final replacement = harness.replaceManager();
      final fresh = replacement.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 10, 20, 30, 40, 1, 2, 3, 4],
      );

      await freshFailure;
      await Future<void>.delayed(Duration.zero);
      expect(harness.memoryRequests, hasLength(1));

      final recovered = replacement.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(2);
      harness.injectMemory(
        values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
      );
      final recoveredResult = await recovered;
      expect(recoveredResult?.sram.current, 50);
    },
  );

  test(
    'timed-out response debt stays ambiguous beyond the former expiry',
    () async {
      var currentTime = DateTime.utc(2026);
      await withClock(Clock(() => currentTime), () async {
        final harness = _MemoryWireHarness();
        addTearDown(harness.close);
        final input = await harness.catalogueInput();

        final timedOut = harness.manager.requestMemoryUsage(input);
        await harness.waitForMemoryRequests(5);
        await expectLater(timedOut, throwsA(isA<TimeoutException>()));

        currentTime = currentTime.add(const Duration(seconds: 31));
        final fresh = harness.manager.requestMemoryUsage(input);
        final freshFailure = expectLater(fresh, _throwsAttributionFailure);
        await Future<void>.delayed(Duration.zero);
        harness.injectMemory(
          values: const [100, 200, 300, 400, 91, 92, 93, 94, 1, 2, 3, 4],
        );

        await freshFailure;
        await Future<void>.delayed(Duration.zero);
        expect(harness.memoryRequests, hasLength(5));

        for (var i = 1; i < 5; i++) {
          harness.injectMemory();
        }
        await Future<void>.delayed(Duration.zero);

        final recovered = harness.manager.requestMemoryUsage(input);
        await harness.waitForMemoryRequests(6);
        harness.injectMemory(
          values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
        );
        final recoveredResult = await recovered;
        expect(recoveredResult?.sram.current, 50);
      });
    },
  );

  test('replacement debt stays ambiguous beyond the former expiry', () async {
    var currentTime = DateTime.utc(2026);
    await withClock(Clock(() => currentTime), () async {
      final harness = _MemoryWireHarness();
      addTearDown(harness.close);
      final input = await harness.catalogueInput();
      final oldManager = harness.manager;

      final oldQuery = oldManager.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(1);
      oldManager.dispose();
      await expectLater(oldQuery, throwsA(isA<StateError>()));

      currentTime = currentTime.add(const Duration(seconds: 31));
      final replacement = harness.replaceManager();
      final fresh = replacement.requestMemoryUsage(input);
      final freshFailure = expectLater(fresh, _throwsAttributionFailure);
      await Future<void>.delayed(Duration.zero);
      harness.injectMemory(
        values: const [100, 200, 300, 400, 91, 92, 93, 94, 1, 2, 3, 4],
      );

      await freshFailure;
      await Future<void>.delayed(Duration.zero);
      expect(harness.memoryRequests, hasLength(1));

      final recovered = replacement.requestMemoryUsage(input);
      await harness.waitForMemoryRequests(2);
      harness.injectMemory(
        values: const [500, 600, 700, 800, 50, 60, 70, 80, 5, 6, 7, 8],
      );
      final recoveredResult = await recovered;
      expect(recoveredResult?.sram.current, 50);
    });
  });
}

final Matcher _throwsAttributionFailure = throwsA(
  isA<AmbiguousResponseAttributionException>(),
);
