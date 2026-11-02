import 'dart:async';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/services/startup_controller.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';

void main() {
  test('real lazy SQLite is not admitted until schema readiness', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var activations = 0;
    final controller = StartupController(
      open: ({bool selectLegacyDirectory = false}) async =>
          OpenedStartupLibrary(
            AppDatabase.withExecutor(
              LazyDatabase(() async => NativeDatabase.memory()),
              storageCheckpoint: (point) async {
                if (point == 'during:schema') {
                  entered.complete();
                  await release.future;
                }
              },
            ),
          ),
      activationSteps: [
        (_) async {
          activations++;
        },
      ],
    );
    final pending = controller.retry();
    await entered.future.timeout(const Duration(seconds: 5));
    expect(activations, 0);
    release.complete();
    await pending;
    expect(controller.failure, isNull);
    expect(activations, 1);
    await controller.close();
    controller.dispose();
  }, tags: ['regression']);

  test(
    'failed real schema open settles teardown before any Retry can reopen',
    () async {
      final closing = Completer<void>();
      final releaseClose = Completer<void>();
      var opens = 0;
      var activations = 0;
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async {
          opens++;
          return OpenedStartupLibrary(
            opens == 1
                ? _DelayedCloseDatabase(() async {
                    closing.complete();
                    await releaseClose.future;
                  })
                : AppDatabase.forTesting(NativeDatabase.memory()),
          );
        },
        activationSteps: [
          (_) async {
            activations++;
          },
        ],
      );
      final first = controller.retry();
      await closing.future;
      expect(controller.busy, isTrue);
      expect(identical(first, controller.retry()), isTrue);
      expect(opens, 1);
      expect(activations, 0);
      releaseClose.complete();
      await first;
      expect(controller.failure, isNotNull);
      await controller.retry();
      expect(controller.failure, isNull);
      expect(opens, 2);
      expect(activations, 1);
      await controller.close();
      controller.dispose();
    },
  , tags: ['regression']);

  test(
    'close wins over an opener returning a ready but stale real database',
    () async {
      final opened = Completer<void>();
      final release = Completer<void>();
      var activations = 0;
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async {
          final database = AppDatabase.forTesting(NativeDatabase.memory());
          await database.select(database.algorithms).get();
          opened.complete();
          await release.future;
          return OpenedStartupLibrary(database);
        },
        activationSteps: [
          (_) async {
            activations++;
          },
        ],
      );
      final pending = controller.retry();
      await opened.future;
      final closing = controller.close();
      release.complete();
      await pending;
      await closing;
      await controller.retry();
      expect(controller.ready, isFalse);
      expect(activations, 0);
      controller.dispose();
    },
  , tags: ['regression']);
}

class _DelayedCloseDatabase extends AppDatabase {
  _DelayedCloseDatabase(this.beforeClose)
    : super.withExecutor(
        NativeDatabase.memory(),
        storageCheckpoint: (point) async {
          if (point == 'before:schema-commit') {
            throw StateError('simulated schema failure');
          }
        },
      );
  final Future<void> Function() beforeClose;
  @override
  Future<void> close() async {
    await beforeClose();
    await super.close();
  }
}
