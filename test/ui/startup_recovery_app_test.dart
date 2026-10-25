import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/db/database.dart';
import 'package:nt_helper/disting_app.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/services/macos_library_storage.dart';
import 'package:nt_helper/services/startup_controller.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/ui/startup_recovery_app.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;

import '../support/storage_fixture.dart';

void main() {
  late Directory root;
  late Directory docs;
  late Directory support;
  late Directory appDir;
  final fixtures = <StorageFixture>[];
  final controllers = <StartupController>[];
  late List<Object?> announcements;
  var activations = 0;
  Map<String, List<String>>? admitted;

  setUp(() {
    resetAppDirectoryForTest();
    root = Directory.systemTemp.createTempSync('nt-visible-startup-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Support'))..createSync();
    appDir = Directory(p.join(support.path, 'nt_helper'));
    activations = 0;
    admitted = null;
    announcements = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
          message,
        ) async {
          announcements.add(message);
          return null;
        });
  });
  tearDown(() async {
    for (final controller in controllers) {
      await controller.close();
      controller.dispose();
    }
    controllers.clear();
    for (final fixture in fixtures) {
      await fixture.close();
    }
    fixtures.clear();
    resetAppDirectoryForTest();
    root.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        );
  });

  Future<StorageFixture> fixture(Directory location) async {
    final value = await StorageFixture.create(
      location,
    ).timeout(const Duration(seconds: 10));
    fixtures.add(value);
    return value;
  }

  StartupStorageOpener opener({
    StorageCheckpoint? checkpoint,
    Future<Directory> Function()? documents,
    Future<bool> Function(String)? requestAccess,
    Future<void> Function()? releaseAccess,
  }) => StartupStorageOpener(
    isMacOS: true,
    docsProvider: documents ?? () async => docs,
    supportProvider: () async => support,
    checkpoint: checkpoint,
    requestAccess: requestAccess ?? (_) async => false,
    releaseAccess: releaseAccess ?? () async {},
  );
  StartupController controllerFor(StartupStorageOpener storage) {
    final controller = StartupController(
      open: storage.open,
      canSelectLegacyDirectory: () => storage.legacyAccessDirectory != null,
      activationSteps: [
        (database) async {
          admitted = await contents(database);
          activations++;
        },
      ],
    );
    controllers.add(controller);
    return controller;
  }

  Future<void> show(WidgetTester tester, StartupController controller) =>
      tester.pumpWidget(
        StartupRecoveryApp(
          key: ObjectKey(controller),
          controller: controller,
          normalBuilder: (_) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Expected library admitted ($activations)'),
              ),
            ),
          ),
        ),
      );
  Future<void> attempt(
    WidgetTester tester,
    StartupController controller,
  ) async {
    await tester.runAsync(
      () => controller.retry().timeout(const Duration(seconds: 10)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> clickRetry(
    WidgetTester tester,
    StartupController controller,
  ) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Retry'));
      await controller.retry(); // Coalesces with the button's attempt.
    });
    await tester.pumpAndSettle();
  }

  void blocked(StartupController controller) {
    expect(controller.ready, isFalse);
    expect(activations, 0);
    expect(find.text('Unable to open your library'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('Expected library admitted'), findsNothing);
  }

  for (final site in ['source', 'destination']) {
    testWidgets(
      'simulated $site denial clears through visible in-app Retry',
      (tester) async {
        final source = (await tester.runAsync(() => fixture(docs)))!;
        final expected = (await tester.runAsync(() => contents(source.app)))!;
        var denied = true;
        final storage = opener(
          checkpoint: (point) async {
            if (denied &&
                point ==
                    (site == 'source'
                        ? 'before:retain-0'
                        : 'before:directory')) {
              throw FileSystemException(
                'simulated $site denial',
                site == 'source' ? source.file.path : appDir.path,
                const OSError('denied', 13),
              );
            }
          },
        );
        final controller = controllerFor(storage);
        await show(tester, controller);
        await attempt(tester, controller);
        blocked(controller);
        expect(
          find.textContaining('could not access a library'),
          findsOneWidget,
        );
        final buttonPosition = tester.getRect(
          find.widgetWithText(FilledButton, 'Retry'),
        );
        final titlePosition = tester.getRect(
          find.text('Unable to open your library'),
        );
        final semantics = tester.ensureSemantics();
        expect(
          tester
              .getSemantics(find.text('Unable to open your library'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(
          tester.getSemantics(find.widgetWithText(FilledButton, 'Retry')).label,
          contains('Retry'),
        );
        Focus.of(tester.element(find.text('Retry'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (site == 'source') {
          expect(
            Focus.of(
              tester.element(find.text('Allow folder access…')),
            ).hasFocus,
            isTrue,
          );
          expect(
            tester
                .getSemantics(
                  find.widgetWithText(OutlinedButton, 'Allow folder access…'),
                )
                .label,
            contains('Allow folder access'),
          );
        } else {
          expect(FocusManager.instance.primaryFocus, isNotNull);
        }
        semantics.dispose();
        expect(
          tester.getRect(find.widgetWithText(FilledButton, 'Retry')),
          buttonPosition,
        );
        expect(
          tester.getRect(find.text('Unable to open your library')),
          titlePosition,
        );
        denied = false;
        await clickRetry(tester, controller);
        expect(admitted, expected);
        expect(activations, 1);
        expect(find.text('Expected library admitted (1)'), findsOneWidget);
        await controller.retry();
        expect(activations, 1);
        expect(announcements.toString(), contains('Library unavailable'));
        expect(announcements.toString(), contains('Library ready'));
      },
      skip: !Platform.isMacOS,
    );
  }

  for (final scenario in [
    'divergent',
    'subset',
    'empty A',
    'partial A',
    'orphan WAL',
    'malformed authority',
    'inaccessible competitor',
    'inconclusive inventory',
  ]) {
    testWidgets(
      'visible $scenario stays preserved and blocked, including Retry',
      (tester) async {
        await tester.runAsync(() => fixture(docs));
        final competitor = Directory(p.join(docs.path, 'nt_helper'));
        switch (scenario) {
          case 'divergent':
          case 'subset':
            final other = (await tester.runAsync(() => fixture(competitor)))!;
            other.raw.execute(
              scenario == 'subset'
                  ? "DELETE FROM metadata_cache WHERE cache_key='base'"
                  : "UPDATE presets SET name='Distinct divergent preset'",
            );
          case 'empty A':
          case 'partial A':
            appDir.createSync();
            File(p.join(appDir.path, libraryFileName)).writeAsStringSync(
              scenario == 'empty A' ? '' : 'unknown partial data',
            );
          case 'orphan WAL':
            appDir.createSync();
            File(
              p.join(appDir.path, '$libraryFileName-wal'),
            ).writeAsStringSync('unknown journal');
          case 'malformed authority':
            final control = Directory(p.join(appDir.path, '.storage-v1'))
              ..createSync(recursive: true);
            File(
              p.join(control.path, 'selected.json'),
            ).writeAsStringSync('{malformed');
          case 'inaccessible competitor':
            await tester.runAsync(() => fixture(competitor));
          case 'inconclusive inventory':
            appDir.createSync();
            Link(
              p.join(appDir.path, libraryFileName),
            ).createSync(p.join(docs.path, libraryFileName));
        }
        final originals = {
          for (final file
              in root
                  .listSync(recursive: true, followLinks: false)
                  .whereType<File>())
            if (!file.path.endsWith('-shm'))
              file.path: base64Encode(file.readAsBytesSync()),
        };
        final controller = controllerFor(
          opener(
            checkpoint: (point) async {
              if (scenario == 'inaccessible competitor' &&
                  point == 'before:retain-1') {
                throw FileSystemException(
                  'simulated competitor denial',
                  p.join(competitor.path, libraryFileName),
                  const OSError('denied', 13),
                );
              }
            },
          ),
        );
        await show(tester, controller);
        await attempt(tester, controller);
        blocked(controller);
        final reason = controller.failure.toString();
        expect(reason, isNot(contains('corruption')));
        expect(
          reason,
          anyOf(
            contains('equivalent'),
            contains('target'),
            contains('journal'),
            contains('authority'),
            contains('denial'),
            contains('Unsupported'),
          ),
        );
        await clickRetry(tester, controller);
        blocked(controller);
        final retainedBytes = root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((f) => base64Encode(f.readAsBytesSync()))
            .toSet();
        for (final entry in originals.entries) {
          expect(File(entry.key).existsSync(), isTrue);
          expect(retainedBytes, contains(entry.value), reason: entry.key);
        }
      },
      skip: !Platform.isMacOS,
    );
  }

  for (final legacy in ['absent', 'denied', 'older-version write']) {
    testWidgets(
      'postselection $legacy never gates destination-only edits after restart/interruption',
      (tester) async {
        final source = (await tester.runAsync(() => fixture(docs)))!;
        final initial = controllerFor(opener());
        await show(tester, initial);
        await attempt(tester, initial);
        await tester.runAsync(
          () => initial.database.customStatement(
            "INSERT INTO metadata_cache VALUES ('destination-only','new version edits')",
          ),
        );
        final expected = (await tester.runAsync(
          () => contents(initial.database),
        ))!;
        final selectedPath = selectedLibrary!.file.path;
        await tester.runAsync(initial.close);
        if (legacy == 'older-version write') {
          source.addLateCommit();
          source.raw.execute(
            'BEGIN IMMEDIATE',
          ); // No post-cutover source-lock prerequisite.
        }
        if (legacy == 'absent') docs.renameSync('${docs.path}-retained');
        resetAppDirectoryForTest();
        activations = 0;
        var legacyReads = 0;
        var interrupted = true;
        final next = controllerFor(
          opener(
            documents: () async {
              legacyReads++;
              throw const FileSystemException('simulated legacy unavailable');
            },
            checkpoint: (point) async {
              if (interrupted && point == 'after:open') {
                throw const FileSystemException(
                  'simulated postselection interruption',
                );
              }
            },
          ),
        );
        await show(tester, next);
        await attempt(tester, next);
        blocked(next);
        interrupted = false;
        await clickRetry(tester, next);
        expect(admitted, expected);
        expect(selectedLibrary!.file.path, selectedPath);
        expect(legacyReads, 0);
        expect(activations, 1);
      },
      skip: !Platform.isMacOS,
    );
  }

  for (final loss in ['missing', 'replaced', 'denied', 'recovery journal']) {
    testWidgets(
      'selected $loss tries SQLite without falling back to legacy data',
      (tester) async {
        await tester.runAsync(() => fixture(docs));
        final initial = controllerFor(opener());
        await show(tester, initial);
        await attempt(tester, initial);
        await tester.runAsync(
          () => initial.database.customStatement(
            "INSERT INTO metadata_cache VALUES ('destination-only','keep this')",
          ),
        );
        final expected = (await tester.runAsync(
          () => contents(initial.database),
        ))!;
        final selected = selectedLibrary!;
        await tester.runAsync(initial.close);
        resetAppDirectoryForTest();
        activations = 0;
        final affected = File(
          '${selected.file.path}${loss == 'recovery journal' ? '-journal' : ''}',
        );
        File? saved;
        if (loss != 'denied') {
          saved = affected.renameSync('${affected.path}.retained');
        }
        if (loss == 'replaced') {
          affected.writeAsStringSync('independent unknown store');
        }
        var denied = loss == 'denied';
        var legacyReads = 0;
        final next = controllerFor(
          opener(
            documents: () async {
              legacyReads++;
              return docs;
            },
            checkpoint: (point) async {
              if (denied && point == 'before:open') {
                throw FileSystemException(
                  'simulated selected destination denial',
                  selected.file.path,
                  const OSError('denied', 13),
                );
              }
            },
          ),
        );
        await show(tester, next);
        await attempt(tester, next);
        if (loss == 'recovery journal') {
          expect(next.ready, isTrue);
          expect(admitted, expected);
          expect(legacyReads, 0);
          expect(find.byType(Dialog), findsNothing);
          expect(saved!.existsSync(), isTrue);
          return;
        }
        blocked(next);
        expect(legacyReads, 0);
        if (loss == 'missing') {
          expect(affected.existsSync(), isFalse);
          expect(find.textContaining('SqliteException'), findsOneWidget);
          expect(
            find.textContaining('Observed identity: missing'),
            findsOneWidget,
          );
        }
        if (loss == 'replaced') affected.renameSync('${affected.path}.unknown');
        saved?.renameSync(affected.path);
        denied = false;
        await clickRetry(tester, next);
        expect(admitted, expected);
        expect(selectedLibrary!.identity, selected.identity);
        expect(legacyReads, 0);
      },
      skip: !Platform.isMacOS,
    );
  }

  testWidgets(
    'failed open report is visible, copyable and does not shift controls',
    (tester) async {
      const report = 'File: /saved/library.sqlite\nObserved identity: missing';
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async =>
            throw const StorageFailure(
              StorageFailureKind.access,
              'SQLite could not open the saved library',
              'SqliteException(14): unable to open database file',
              report,
            ),
        canSelectLegacyDirectory: () => false,
        activationSteps: const [],
      );
      controllers.add(controller);
      await show(tester, controller);
      await attempt(tester, controller);
      final semantics = tester.ensureSemantics();
      expect(find.textContaining(report), findsOneWidget);
      expect(find.textContaining('SqliteException(14)'), findsOneWidget);
      expect(find.textContaining('Architecture:'), findsOneWidget);
      final retryRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Retry'),
      );
      final titleRect = tester.getRect(
        find.text('Unable to open your library'),
      );
      final copy = find.widgetWithIcon(IconButton, Icons.copy);
      expect(tester.getSemantics(copy).label, contains('Copy error details'));
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(copy);
      await tester.pump();
      expect(copied, contains(report));
      expect(copied, contains('SqliteException(14)'));
      expect(copied, contains('OS:'));
      await tester.tap(find.text('Hide details'));
      await tester.pump();
      expect(find.textContaining(report), findsNothing);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Retry')),
        retryRect,
      );
      expect(
        tester.getRect(find.text('Unable to open your library')),
        titleRect,
      );
      await tester.tap(find.text('Show details'));
      await tester.pump();
      expect(find.textContaining(report), findsOneWidget);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Retry')),
        retryRect,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  for (final failure in ['native', 'I/O', 'access', 'busy']) {
    testWidgets(
      'actual opener $failure failure is not corruption and visible Retry recovers',
      (tester) async {
        final source = (await tester.runAsync(() => fixture(docs)))!;
        final expected = (await tester.runAsync(() => contents(source.app)))!;
        var failing = true;
        final controller = controllerFor(
          opener(
            checkpoint: (point) async {
              if (failing && point == 'before:open') {
                if (failure == 'native') {
                  throw ArgumentError(
                    "simulated couldn't resolve native function libsqlite3",
                  );
                }
                throw FileSystemException(
                  failure == 'busy' ? 'simulated busy' : 'simulated $failure',
                  appDir.path,
                  OSError(failure, failure == 'access' ? 13 : 5),
                );
              }
            },
          ),
        );
        await show(tester, controller);
        await attempt(tester, controller);
        blocked(controller);
        expect(
          (controller.failure as StorageFailure).kind,
          isNot(StorageFailureKind.damaged),
        );
        final authority = File(
          p.join(appDir.path, '.storage-v1', 'selected.json'),
        ).readAsBytesSync();
        failing = false;
        await clickRetry(tester, controller);
        expect(admitted, expected);
        expect(
          File(
            p.join(appDir.path, '.storage-v1', 'selected.json'),
          ).readAsBytesSync(),
          authority,
        );
      },
      skip: !Platform.isMacOS,
    );
  }

  testWidgets(
    'legacy selection cancellation is honest; successful temporary access is released before admission',
    (tester) async {
      final source = (await tester.runAsync(() => fixture(docs)))!;
      var denied = true;
      var cancel = true;
      var released = 0;
      final storage = opener(
        checkpoint: (point) async {
          if (denied && point == 'before:retain-0') {
            throw FileSystemException(
              'simulated source denial',
              source.file.path,
              const OSError('denied', 13),
            );
          }
        },
        requestAccess: (path) async {
          expect(path, docs.path);
          if (cancel) return false;
          denied = false;
          return true;
        },
        releaseAccess: () async {
          released++;
        },
      );
      final controller = controllerFor(storage);
      await show(tester, controller);
      await attempt(tester, controller);
      await tester.runAsync(() async {
        await tester.tap(find.text('Allow folder access…'));
        await controller.retry();
      });
      await tester.pump();
      blocked(controller);
      expect(controller.failure.toString(), contains('cancelled'));
      expect(released, 1);
      cancel = false;
      await tester.runAsync(() async {
        await tester.tap(find.text('Allow folder access…'));
        await controller.retry();
      });
      await tester.pump();
      expect(controller.ready, isTrue);
      expect(released, 2);
      expect(activations, 1);
    },
    skip: !Platform.isMacOS,
  );

  for (final closeWhilePending in [false, true]) {
    testWidgets(
      'delayed actual SQLite/schema opener coalesces callers and ${closeWhilePending ? 'close discards stale completion' : 'waits for readiness'}',
      (tester) async {
        late Completer<void> schemaEntered;
        late Completer<void> allowSchema;
        var opens = 0;
        final controller = StartupController(
          open: ({bool selectLegacyDirectory = false}) async {
            opens++;
            return OpenedStartupLibrary(
              AppDatabase.withExecutor(
                LazyDatabase(() async {
                  schemaEntered.complete();
                  await allowSchema.future;
                  return NativeDatabase(
                    File(p.join(root.path, libraryFileName)),
                  );
                }),
              ),
            );
          },
          activationSteps: [
            (_) async {
              activations++;
            },
          ],
        );
        controllers.add(controller);
        await show(tester, controller);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Retry'), findsNothing);
        late Future<void> first;
        await tester.runAsync(() async {
          schemaEntered = Completer<void>();
          allowSchema = Completer<void>();
          first = controller.retry();
          expect(identical(first, controller.retry()), isTrue);
          await Future.any([
            schemaEntered.future,
            first,
          ]).timeout(const Duration(seconds: 10));
          expect(controller.failure, isNull);
          expect(schemaEntered.isCompleted, isTrue);
        });
        await tester.pump();
        expect(controller.busy, isTrue);
        expect(opens, 1);
        expect(activations, 0);
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final closing = closeWhilePending ? controller.close() : null;
          allowSchema.complete();
          await first.timeout(const Duration(seconds: 10));
          await closing;
        });
        await tester.pump();
        expect(controller.ready, !closeWhilePending);
        expect(activations, closeWhilePending ? 0 : 1);
        await controller.retry();
        expect(opens, 1);
      },
    );
  }

  testWidgets(
    'failed actual schema transaction tears down before retry and preserves expected rows',
    (tester) async {
      final source = (await tester.runAsync(
        () => StorageFixture.create(root, oldSchema: true),
      ))!;
      final file = source.file;
      await tester.runAsync(source.close);
      var fail = true;
      var opens = 0;
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async {
          opens++;
          return OpenedStartupLibrary(
            AppDatabase.withExecutor(
              NativeDatabase(file),
              storageCheckpoint: (point) async {
                if (point == 'before:schema-commit' && fail) {
                  throw const FileSystemException(
                    'simulated schema I/O failure',
                  );
                }
              },
            ),
          );
        },
        activationSteps: [
          (database) async {
            await database.customStatement(
              "INSERT INTO metadata_cache VALUES ('expected','once')",
            );
            admitted = await contents(database);
            activations++;
          },
        ],
      );
      controllers.add(controller);
      await show(tester, controller);
      await attempt(tester, controller);
      blocked(controller);
      fail = false;
      await clickRetry(tester, controller);
      expect(opens, 2);
      expect(activations, 1);
      expect(admitted!['metadata_cache']!.join(), contains('expected'));
      expect(admitted!['metadata_cache']!.join(), contains('wal-only'));
      expect(admitted!['presets']!.join(), contains('Library preset'));
    },
  );

  testWidgets(
    'close between dependent services prevents later activation and normal admission',
    (tester) async {
      late Completer<void> entered;
      late Completer<void> release;
      var laterActivations = 0;
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async =>
            OpenedStartupLibrary(
              AppDatabase.forTesting(NativeDatabase.memory()),
            ),
        activationSteps: [
          (_) async {
            entered.complete();
            await release.future;
          },
          (_) async {
            laterActivations++;
          },
        ],
      );
      controllers.add(controller);
      await show(tester, controller);
      late Future<void> pending;
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<void>();
        pending = controller.retry();
        await entered.future;
      });
      await tester.runAsync(() async {
        final closing = controller.close();
        release.complete();
        await pending;
        await closing;
      });
      await tester.pump();
      expect(laterActivations, 0);
      expect(controller.ready, isFalse);
      expect(find.textContaining('Expected library admitted'), findsNothing);
    },
  );

  for (final repairable in [false, true]) {
    testWidgets(
      'real damage Retry retains ${repairable ? 'repair' : 'non-recovery'} outcome without a banner and preserves later edits on restart',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final original = (await tester.runAsync(() => fixture(docs)))!;
        final expected = (await tester.runAsync(() => contents(original.app)))!;
        await tester.runAsync(original.close);
        fixtures.remove(original);
        damageLibrary(original.file, repairable: repairable);
        final retained = storageBytes(original.file);
        var failInspection = true;
        final controller = controllerFor(
          opener(
            checkpoint: (point) async {
              if (failInspection && point == 'before:inspect-0') {
                throw const FileSystemException(
                  'simulated inspection denial',
                  '',
                  OSError('denied', 13),
                );
              }
            },
          ),
        );
        await show(tester, controller);
        await attempt(tester, controller);
        expect(controller.ready, isFalse);
        expect(activations, 0);
        expect(find.text('Retry'), findsOneWidget);
        failInspection = false;
        await clickRetry(tester, controller);
        await tester.pumpAndSettle();
        expect(controller.ready, isTrue);
        expect(activations, 1);
        if (repairable) {
          expect(admitted, expected);
          expect(announcements.toString(), contains('safely repaired'));
        } else {
          expect(admitted!.values.every((rows) => rows.isEmpty), isTrue);
          expect(
            announcements.toString(),
            contains('previous library was not recovered'),
          );
        }
        expect(
          controller.recovery,
          repairable
              ? LibraryRecovery.repaired
              : LibraryRecovery.freshAfterDamage,
        );
        expect(find.textContaining('Start fresh'), findsNothing);
        expect(find.text('Library repaired'), findsNothing);
        expect(find.text('Fresh library after database damage'), findsNothing);
        expect(find.byTooltip('Dismiss library storage notice'), findsNothing);
        expect(find.textContaining(controller.location!), findsNothing);
        expect(find.text('Expected library admitted (1)'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final entry in retained.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
        final identity = controller.location;
        await tester.runAsync(() async {
          await controller.database.customStatement(
            "INSERT INTO metadata_cache VALUES ('destination-only', 'later edit')",
          );
          await controller.retry(); // No second initialization after admission.
          await controller.close();
        });
        resetAppDirectoryForTest();
        final restarted = controllerFor(
          opener(documents: () async => throw StateError('No legacy access')),
        );
        await show(tester, restarted);
        await attempt(tester, restarted);
        expect(restarted.ready, isTrue);
        expect(restarted.location, identity);
        expect(
          find.text(
            repairable
                ? 'Library repaired'
                : 'Fresh library after database damage',
          ),
          findsNothing,
        );
        expect(
          restarted.recovery,
          repairable
              ? LibraryRecovery.repaired
              : LibraryRecovery.freshAfterDamage,
        );
        expect(
          admitted!['metadata_cache']!.where(
            (row) => row.contains('destination-only'),
          ),
          hasLength(1),
        );
        semantics.dispose();
      },
      skip: !Platform.isMacOS,
    );
  }

  for (final kind in [StorageFailureKind.access, StorageFailureKind.busy]) {
    testWidgets(
      'blocked $kind, busy and keyboard Retry preserve dialog geometry and announce results',
      (tester) async {
        late Completer<void> gate;
        var fail = true;
        late Future<void> pending;
        final controller = StartupController(
          open: ({bool selectLegacyDirectory = false}) async {
            await gate.future;
            if (fail) {
              throw StorageFailure(kind, 'Simulated required operation');
            }
            return OpenedStartupLibrary(
              AppDatabase.forTesting(NativeDatabase.memory()),
              location: '/resolved/Support/library.sqlite',
            );
          },
          canSelectLegacyDirectory: () => true,
          activationSteps: [
            (_) async {
              activations++;
            },
          ],
        );
        controllers.add(controller);
        final semantics = tester.ensureSemantics();
        await show(tester, controller);
        expect(find.byType(Dialog), findsNothing);
        await tester.runAsync(() async {
          gate = Completer<void>();
          pending = controller.retry();
        });
        await tester.pump();
        expect(find.text('Opening library…'), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        await tester.runAsync(() async {
          gate.complete();
          await pending;
        });
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            kind == StorageFailureKind.busy
                ? 'Another operation is using the library.'
                : 'could not access a library',
          ),
          findsOneWidget,
        );
        final button = find.widgetWithText(FilledButton, 'Retry');
        final buttonRect = tester.getRect(button);
        final titleRect = tester.getRect(
          find.text('Unable to open your library'),
        );
        final accessRect = tester.getRect(find.text('Allow folder access…'));
        expect(
          tester
              .getSemantics(find.text('Unable to open your library'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        Focus.of(tester.element(find.text('Retry'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          Focus.of(tester.element(find.text('Allow folder access…'))).hasFocus,
          isTrue,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(Focus.of(tester.element(find.text('Retry'))).hasFocus, isTrue);
        await tester.runAsync(() async {
          gate = Completer<void>();
          fail = false;
        });
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 200));
        expect(controller.busy, isTrue);
        expect(find.text('Opening library…'), findsOneWidget);
        expect(tester.getRect(button), buttonRect);
        expect(
          tester.getRect(find.text('Unable to open your library')),
          titleRect,
        );
        expect(tester.getRect(find.text('Allow folder access…')), accessRect);
        await tester.runAsync(() async {
          gate.complete();
        });
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(() async {
            await pumpEventQueue();
          });
          await tester.pump();
        }
        expect(controller.ready, isTrue);
        expect(activations, 1);
        expect(announcements.toString(), contains('Library unavailable'));
        expect(
          announcements.toString(),
          contains('Opening library. Please wait'),
        );
        expect(
          announcements.toString(),
          contains('Library ready at /resolved/Support/library.sqlite'),
        );
        final allText = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' ');
        expect(allText, isNot(contains('Full Disk Access')));
        expect(allText, isNot(contains('contact Neal')));
        semantics.dispose();
      },
    );
  }

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'recovery is modal in the normal $brightness shell with high contrast $highContrast and saved theme settings',
        (tester) async {
          final settings = SettingsService();
          final previousSeed = settings.themeSeedColorNotifier.value;
          final previousScale = settings.uiScaleNotifier.value;
          addTearDown(() {
            tester.platformDispatcher.clearPlatformBrightnessTestValue();
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
            settings.themeSeedColorNotifier.value = previousSeed;
            settings.uiScaleNotifier.value = previousScale;
          });
          const seed = Color(0xFFB34173);
          settings.themeSeedColorNotifier.value = seed;
          settings.uiScaleNotifier.value = 1.1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(highContrast: highContrast);
          final controller = StartupController(
            open: ({bool selectLegacyDirectory = false}) async =>
                throw const StorageFailure(
                  StorageFailureKind.access,
                  'Simulated storage denial',
                ),
          );
          controllers.add(controller);
          await show(tester, controller);
          expect(find.byType(DistingApp), findsOneWidget);
          expect(find.text('nt_helper'), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          await attempt(tester, controller);
          final context = tester.element(
            find.text('Unable to open your library'),
          );
          final expected = AppTheme.build(
            seedColor: seed,
            brightness: brightness,
            contrastLevel: highContrast ? 1 : 0,
          );
          expect(Theme.of(context).colorScheme, expected.colorScheme);
          expect(MediaQuery.textScalerOf(context).scale(10), 11);
          final route = ModalRoute.of(context)!;
          expect(route, isA<DialogRoute<void>>());
          expect(route.barrierDismissible, isFalse);
          expect(find.byType(Dialog), findsOneWidget);
          expect(find.byType(DistingApp), findsOneWidget);
          expect(controller.ready, isFalse);
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.tapAt(const Offset(8, 8));
          await tester.pumpAndSettle();
          expect(find.text('Unable to open your library'), findsOneWidget);
          settings.themeSeedColorNotifier.value = const Color(0xFF125C77);
          await tester.pumpAndSettle();
          expect(
            Theme.of(context).colorScheme.primary,
            AppTheme.build(
              seedColor: const Color(0xFF125C77),
              brightness: brightness,
              contrastLevel: highContrast ? 1 : 0,
            ).colorScheme.primary,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'successful startup stays silent and admits normal content without a storage overlay',
    (tester) async {
      final controller = StartupController(
        open: ({bool selectLegacyDirectory = false}) async =>
            OpenedStartupLibrary(
              AppDatabase.forTesting(NativeDatabase.memory()),
              location: '/resolved/Support/selected.sqlite',
            ),
      );
      controllers.add(controller);
      await show(tester, controller);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Unable to open your library'), findsNothing);
      expect(find.textContaining('Expected library admitted'), findsNothing);
      await attempt(tester, controller);
      await tester.pumpAndSettle();
      expect(controller.ready, isTrue);
      expect(find.text('Expected library admitted (0)'), findsOneWidget);
      expect(
        find.textContaining('/resolved/Support/selected.sqlite'),
        findsNothing,
      );
      expect(find.textContaining('older releases'), findsNothing);
      expect(find.byTooltip('Dismiss library storage notice'), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
