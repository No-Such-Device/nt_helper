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
import 'package:nt_helper/services/library_storage.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/startup_controller.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/ui/startup_recovery_app.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final controllers = <StartupController>[];
  late List<Object?> announcements;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const picker = MethodChannel('miguelruivo.flutter.plugins.filepicker');
  setUp(() {
    resetAppDirectoryForTest();
    root = Directory.systemTemp.createTempSync('nt-visible-startup-');
    PackageInfo.setMockInitialValues(
      appName: 'nt_helper',
      packageName: 'nt_helper',
      version: '2.61.0',
      buildNumber: '349',
      buildSignature: '',
    );
    announcements = [];
    messenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        announcements.add(message);
        return null;
      },
    );
  });
  tearDown(() async {
    for (final controller in controllers) {
      await controller.close();
      controller.dispose();
    }
    controllers.clear();
    resetAppDirectoryForTest();
    root.deleteSync(recursive: true);
    messenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(picker, null);
  });
  StartupController keep(StartupController controller) {
    controllers.add(controller);
    return controller;
  }

  Future<void> show(WidgetTester tester, StartupController controller) =>
      tester.pumpWidget(
        StartupRecoveryApp(
          key: ObjectKey(controller),
          controller: controller,
          normalBuilder: (_) =>
              const MaterialApp(home: Scaffold(body: Text('Normal library'))),
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

  AppDatabase memory() => AppDatabase.forTesting(NativeDatabase.memory());

  testWidgets(
    'Adam missing-main report offers confirmed fresh creation without deleting recovery files',
    (tester) async {
      const id = '11111111-1111-1111-1111-111111111111';
      final support = Directory(p.join(root.path, 'Support'))..createSync();
      final docs = Directory(p.join(root.path, 'Documents'))..createSync();
      final work = Directory(
        p.join(support.path, 'nt_helper', '.storage-v1', 'work-$id'),
      )..createSync(recursive: true);
      final record = File(p.join(work.parent.path, 'selected.json'))
        ..writeAsStringSync(
          jsonEncode({
            'body': jsonEncode({
              'attempt': id,
              'file': 'work-$id/nt_helper_db.sqlite',
            }),
          }),
        );
      final journal = File(p.join(work.path, 'nt_helper_db.sqlite-journal'))
        ..writeAsStringSync('remaining journal');
      final opener = StartupStorageOpener(
        isMacOS: true,
        docsProvider: () async => docs,
        supportProvider: () async => support,
      );
      final controller = keep(
        StartupController(
          open: opener.open,
          libraryLocation: () => opener.location,
        ),
      );
      await show(tester, controller);
      await attempt(tester, controller);
      expect(controller.failure, isA<LibraryImportException>());
      expect(find.text('Choose library…'), findsOneWidget);
      expect(find.text('Start fresh…'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Start fresh…')).label,
        contains('Start fresh'),
      );
      expect(
        tester
            .getSemantics(find.text('Unable to open your library'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      final retry = tester.getRect(find.widgetWithText(FilledButton, 'Retry'));
      await tester.tap(find.text('Start fresh…'));
      await tester.pumpAndSettle();
      expect(find.text('Start with an empty library?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.ready, isFalse);
      expect(File(opener.location!).existsSync(), isFalse);
      expect(tester.getRect(find.widgetWithText(FilledButton, 'Retry')), retry);
      await tester.tap(find.text('Start fresh…'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Start fresh'));
        await controller.retry(startFresh: true);
      });
      await tester.pumpAndSettle();
      expect(controller.ready, isTrue);
      expect(
        await tester.runAsync(
          () => controller.database.select(controller.database.presets).get(),
        ),
        isEmpty,
      );
      expect(journal.readAsStringSync(), 'remaining journal');
      expect(record.existsSync(), isTrue);
      expect(find.text('Normal library'), findsOneWidget);
      semantics.dispose();
    },
    tags: ['regression'],
  );

  testWidgets(
    'library chooser cancellation preserves failure and choosing a file uses the existing retry lifecycle',
    (tester) async {
      final failure = const LibraryImportException('Choose a saved library');
      File? imported;
      var opens = 0;
      final controller = keep(
        StartupController(
          open:
              ({
                bool selectLegacyDirectory = false,
                File? importSource,
                bool startFresh = false,
              }) async {
                opens++;
                if (importSource == null) throw failure;
                imported = importSource;
                return OpenedStartupLibrary(memory());
              },
        ),
      );
      await show(tester, controller);
      await attempt(tester, controller);
      messenger.setMockMethodCallHandler(picker, (_) async => null);
      await tester.tap(find.text('Choose library…'));
      await tester.pumpAndSettle();
      expect(controller.failure, same(failure));
      expect(opens, 1);
      final source = File(p.join(root.path, 'chosen.sqlite'))
        ..writeAsStringSync('picker fixture');
      messenger.setMockMethodCallHandler(
        picker,
        (_) async => [
          {
            'path': source.path,
            'name': 'chosen.sqlite',
            'size': source.lengthSync(),
          },
        ],
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Choose library…'));
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      expect(controller.ready, isTrue);
      expect(imported?.path, source.path);
      expect(opens, 2);
    },
  );

  for (final failure in <Object>[
    ArgumentError('could not load sqlite native library'),
    const FileSystemException(
      'access denied',
      '/saved/library.sqlite',
      OSError('denied', 13),
    ),
    const FileSystemException('busy', '/saved/library.sqlite'),
    SqliteException(
      extendedResultCode: 11,
      message: 'database disk image is malformed',
    ),
  ]) {
    testWidgets(
      'open failure $failure is preserved, copyable and never enables implicit replacement',
      (tester) async {
        final controller = keep(
          StartupController(
            open:
                ({
                  bool selectLegacyDirectory = false,
                  File? importSource,
                  bool startFresh = false,
                }) async => throw failure,
            libraryLocation: () => '/saved/library.sqlite',
          ),
        );
        await show(tester, controller);
        await attempt(tester, controller);
        expect(controller.failure, same(failure));
        expect(controller.canImport, isFalse);
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  'Start fresh…',
                  skipOffstage: false,
                ),
              )
              .onPressed,
          isNull,
        );
        expect(find.textContaining(failure.toString()), findsOneWidget);
        expect(find.textContaining('App: 2.61.0+349'), findsOneWidget);
        final buttonRect = tester.getRect(
          find.widgetWithText(FilledButton, 'Retry'),
        );
        final titleRect = tester.getRect(
          find.text('Unable to open your library'),
        );
        String? copied;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        final semantics = tester.ensureSemantics();
        final copy = find.widgetWithIcon(IconButton, Icons.copy);
        expect(tester.getSemantics(copy).label, contains('Copy error details'));
        await tester.tap(copy);
        await tester.pump();
        expect(copied, contains(failure.toString()));
        expect(copied, contains('Library: /saved/library.sqlite'));
        expect(copied, contains('Architecture:'));
        await tester.tap(find.text('Hide details'));
        await tester.pump();
        expect(find.textContaining(failure.toString()), findsNothing);
        expect(
          tester.getRect(find.widgetWithText(FilledButton, 'Retry')),
          buttonRect,
        );
        expect(
          tester.getRect(find.text('Unable to open your library')),
          titleRect,
        );
        await tester.tap(find.text('Show details'));
        await tester.pump();
        expect(find.textContaining(failure.toString()), findsOneWidget);
        semantics.dispose();
      },
      tags: ['regression'],
    );
  }

  testWidgets(
    'busy keyboard Retry keeps recovery controls fixed and announces completion',
    (tester) async {
      var fail = true;
      var activations = 0;
      final entered = Completer<void>();
      final release = Completer<void>();
      final controller = keep(
        StartupController(
          open:
              ({
                bool selectLegacyDirectory = false,
                File? importSource,
                bool startFresh = false,
              }) async {
                if (fail) throw const LibraryImportException('Choose or retry');
                entered.complete();
                await release.future;
                return OpenedStartupLibrary(
                  memory(),
                  location: '/Support/library.sqlite',
                );
              },
          canSelectLegacyDirectory: () => true,
          activationSteps: [
            (_) async {
              activations++;
            },
          ],
        ),
      );
      await show(tester, controller);
      await attempt(tester, controller);
      final button = find.widgetWithText(FilledButton, 'Retry');
      final buttonRect = tester.getRect(button);
      final titleRect = tester.getRect(
        find.text('Unable to open your library'),
      );
      final chooseRect = tester.getRect(find.text('Choose library…'));
      final accessRect = tester.getRect(find.text('Allow folder access…'));
      Focus.of(tester.element(find.text('Retry'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.text('Allow folder access…'))).hasFocus,
        isTrue,
      );
      Focus.of(tester.element(find.text('Retry'))).requestFocus();
      fail = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.runAsync(() => entered.future);
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.busy, isTrue);
      expect(tester.getRect(button), buttonRect);
      expect(
        tester.getRect(find.text('Unable to open your library')),
        titleRect,
      );
      expect(tester.getRect(find.text('Allow folder access…')), accessRect);
      expect(
        tester.getRect(find.text('Choose library…', skipOffstage: false)),
        chooseRect,
      );
      expect(find.text('Opening library…'), findsOneWidget);
      await tester.runAsync(() async {
        release.complete();
        await controller.retry();
      });
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(announcements.toString(), contains('Library unavailable'));
      expect(
        announcements.toString(),
        contains('Opening library. Please wait'),
      );
      expect(
        announcements.toString(),
        contains('Library ready at /Support/library.sqlite'),
      );
    },
    tags: ['regression'],
  );

  for (final closeWhilePending in [false, true]) {
    testWidgets(
      'delayed real SQLite open coalesces callers and ${closeWhilePending ? 'close rejects stale completion' : 'waits for readiness'}',
      (tester) async {
        late Completer<void> entered;
        late Completer<void> release;
        var activations = 0;
        var opens = 0;
        final controller = keep(
          StartupController(
            open:
                ({
                  bool selectLegacyDirectory = false,
                  File? importSource,
                  bool startFresh = false,
                }) async {
                  opens++;
                  return OpenedStartupLibrary(
                    AppDatabase.withExecutor(
                      LazyDatabase(() async {
                        entered.complete();
                        await release.future;
                        return NativeDatabase(
                          File(p.join(root.path, 'lazy.sqlite')),
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
          ),
        );
        await show(tester, controller);
        late Future<void> pending;
        await tester.runAsync(() async {
          entered = Completer<void>();
          release = Completer<void>();
          pending = controller.retry();
          expect(identical(pending, controller.retry()), isTrue);
          await entered.future.timeout(const Duration(seconds: 10));
        });
        await tester.pump();
        expect(activations, 0);
        expect(find.byType(Dialog), findsNothing);
        await tester.runAsync(() async {
          final closing = closeWhilePending ? controller.close() : null;
          release.complete();
          await pending.timeout(const Duration(seconds: 10));
          await closing;
        });
        await tester.pump();
        expect(controller.ready, !closeWhilePending);
        expect(activations, closeWhilePending ? 0 : 1);
        await controller.retry();
        expect(opens, 1);
      },
      tags: ['regression'],
    );
  }

  testWidgets('close between dependent services prevents later activation', (
    tester,
  ) async {
    late Completer<void> entered;
    late Completer<void> release;
    var later = 0;
    final controller = keep(
      StartupController(
        open:
            ({
              bool selectLegacyDirectory = false,
              File? importSource,
              bool startFresh = false,
            }) async => OpenedStartupLibrary(memory()),
        activationSteps: [
          (_) async {
            entered.complete();
            await release.future;
          },
          (_) async {
            later++;
          },
        ],
      ),
    );
    await show(tester, controller);
    await tester.runAsync(() async {
      entered = Completer<void>();
      release = Completer<void>();
      final pending = controller.retry();
      await entered.future;
      final closing = controller.close();
      release.complete();
      await pending;
      await closing;
    });
    await tester.pump();
    expect(later, 0);
    expect(controller.ready, isFalse);
  }, tags: ['regression']);

  for (final brightness in Brightness.values) {
    for (final highContrast in [false, true]) {
      testWidgets(
        'recovery keeps the normal $brightness shell, contrast $highContrast and saved theme settings',
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
          final controller = keep(
            StartupController(
              open:
                  ({
                    bool selectLegacyDirectory = false,
                    File? importSource,
                    bool startFresh = false,
                  }) async => throw const FileSystemException('denied'),
            ),
          );
          await show(tester, controller);
          expect(find.byType(DistingApp), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          await attempt(tester, controller);
          final context = tester.element(
            find.text('Unable to open your library'),
          );
          expect(
            Theme.of(context).colorScheme,
            AppTheme.build(
              seedColor: seed,
              brightness: brightness,
              contrastLevel: highContrast ? 1 : 0,
            ).colorScheme,
          );
          expect(MediaQuery.textScalerOf(context).scale(10), 11);
          expect(ModalRoute.of(context), isA<DialogRoute<void>>());
          expect(ModalRoute.of(context)!.barrierDismissible, isFalse);
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
        tags: ['regression'],
      );
    }
  }

  testWidgets('successful startup stays silent without a storage overlay', (
    tester,
  ) async {
    final controller = keep(
      StartupController(
        open:
            ({
              bool selectLegacyDirectory = false,
              File? importSource,
              bool startFresh = false,
            }) async => OpenedStartupLibrary(
              memory(),
              location: '/Support/library.sqlite',
            ),
      ),
    );
    await show(tester, controller);
    expect(find.byType(Dialog), findsNothing);
    await attempt(tester, controller);
    expect(controller.ready, isTrue);
    expect(find.text('Normal library'), findsOneWidget);
    expect(find.textContaining('/Support/library.sqlite'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });
}
