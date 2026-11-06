import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/ui/gallery/gallery_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/cubit/disting_cubit.dart';
import 'package:nt_helper/services/gallery_cache_storage.dart';
import 'package:nt_helper/services/gallery_service.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:nt_helper/services/startup_controller.dart';
import 'package:nt_helper/services/startup_storage_opener.dart';
import 'package:nt_helper/ui/plugin_gallery_screen.dart';
import 'package:nt_helper/ui/startup_recovery_app.dart';
import 'package:nt_helper/utils/app_directory.dart';
import 'package:path/path.dart' as p;

import '../support/storage_fixture.dart';
import '../support/gallery_cache_fixture.dart';

Future<T?> run<T>(WidgetTester tester, Future<T> Function() body) =>
    tester.runAsync(() => body().timeout(const Duration(seconds: 10)));

Future<void> settleIO(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() async {
      await pumpEventQueue();
    });
    await tester.pump();
  }
}

class _Settings extends Mock implements SettingsService {}

class _Disting extends Mock implements DistingCubit {}

void main() {
  if (!Platform.isMacOS) return;
  late Directory root;
  late Directory docs;
  late Directory support;
  late List<Object?> announcements;

  setUp(() {
    resetAppDirectoryForTest();
    root = Directory.systemTemp.createTempSync('nt-gallery-recovery-');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Support'))..createSync();
    announcements = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
          message,
        ) async {
          announcements.add(message);
          return null;
        });
  });
  tearDown(() {
    resetAppDirectoryForTest();
    root.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        );
  });

  for (final boundary in [
    'gallery:read',
    'gallery:during:write',
    'gallery:after:publish',
  ]) {
    testWidgets(
      'real ready database and on-demand gallery retry retain rows without a startup banner after simulated $boundary failure',
      (tester) async {
        final source = (await tester.runAsync(
          () => StorageFixture.create(docs),
        ))!;
        final expected = (await tester.runAsync(() => contents(source.app)))!;
        final original = File(p.join(docs.path, 'gallery_cache.json'))
          ..writeAsStringSync(cache('Retained plugin'));
        final originalBytes = original.readAsBytesSync();
        var fail = true;
        var hold = false;
        var databasePreparations = 0;
        var activations = 0;
        final entered = Completer<void>();
        final release = Completer<void>();
        final controller = StartupController(
          open:
              ({
                bool selectLegacyDirectory = false,
                File? importSource,
                bool startFresh = false,
              }) {
                databasePreparations++;
                return StartupStorageOpener(
                  isMacOS: true,
                  docsProvider: () async => docs,
                  supportProvider: () async => support,
                  galleryCheckpoint: (point) async {
                    if (point == 'gallery:inventory' && hold) {
                      entered.complete();
                      await release.future;
                    }
                    if (point == boundary && fail) {
                      throw const FileSystemException(
                        'simulated gallery transfer denial/interruption',
                        '',
                        OSError('denied', 13),
                      );
                    }
                  },
                ).open();
              },
          activationSteps: [
            (_) async {
              activations++;
            },
          ],
        );
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          StartupRecoveryApp(
            controller: controller,
            normalBuilder: (_) => MaterialApp(
              home: Scaffold(
                body: const Center(child: Text('Normal database use')),
              ),
            ),
          ),
        );
        await run(tester, controller.retry);
        await tester.pump();
        await settleIO(tester);
        expect(controller.ready, isTrue);
        expect(
          await tester.runAsync(() => contents(controller.database)),
          expected,
        );
        // Gallery preparation is now on demand, not driven by a startup notice.
        expect(galleryCacheStorage!.busy, isFalse);
        expect(galleryCacheStorage!.failure, isNull);
        await run(tester, () async {
          await expectLater(
            galleryCacheStorage!.prepare(),
            throwsA(isA<GalleryStorageUnavailable>()),
          );
        });
        expect(galleryCacheStorage!.failure, isA<GalleryStorageUnavailable>());
        expect(
          find.textContaining('Gallery temporarily unavailable'),
          findsNothing,
        );
        expect(find.textContaining(controller.location!), findsNothing);
        expect(find.textContaining('older releases'), findsNothing);
        expect(find.byTooltip('Dismiss library storage notice'), findsNothing);
        expect(tester.takeException(), isNull);
        final contentRect = tester.getRect(find.text('Normal database use'));
        await tester.runAsync(
          () => controller.database.customStatement(
            "INSERT INTO metadata_cache VALUES ('destination-only','gallery failure edit')",
          ),
        );
        final edited = await tester.runAsync(
          () => contents(controller.database),
        );
        final work = galleryCacheStorage!.directory
            .listSync()
            .whereType<File>()
            .where(
              (file) => p.basename(file.path).startsWith('.gallery-transfer-'),
            )
            .toList();
        final retained = {
          for (final file in work) file.path: file.readAsBytesSync(),
        };
        if (boundary == 'gallery:during:write') expect(retained, isNotEmpty);
        fail = false;
        hold = true;
        late Future<void> retry;
        await tester.runAsync(() async {
          retry = galleryCacheStorage!.prepare();
          await entered.future;
        });
        await tester.pump();
        expect(entered.isCompleted, isTrue);
        expect(galleryCacheStorage!.busy, isTrue);
        expect(tester.getRect(find.text('Normal database use')), contentRect);
        expect(
          await tester.runAsync(() => contents(controller.database)),
          edited,
        );
        release.complete();
        await tester.runAsync(() => retry);
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() async {
            await pumpEventQueue();
          });
          await tester.pump();
        }
        await tester.pump();
        expect(galleryCacheStorage!.ready, isTrue);
        expect(find.textContaining('Gallery cache available.'), findsNothing);
        expect(tester.getRect(find.text('Normal database use')), contentRect);
        expect(
          await tester.runAsync(() => contents(controller.database)),
          edited,
        );
        expect(databasePreparations, 1);
        expect(activations, 1);
        expect(original.readAsBytesSync(), originalBytes);
        for (final entry in retained.entries) {
          expect(File(entry.key).readAsBytesSync(), entry.value);
        }
        expect(announcements.toString(), isNot(contains('Gallery cache')));
        final settings = _Settings();
        when(
          () => settings.graphqlEndpoint,
        ).thenReturn('https://example.invalid/graphql');
        final service = GalleryService(
          settingsService: settings,
          database: controller.database,
        );
        final gallery = await tester.runAsync(() => service.fetchGallery());
        expect(gallery!.plugins.single.name, 'Retained plugin');
        service.dispose();
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        await tester.runAsync(() async {
          await controller.close();
          await source.close();
        });
        controller.dispose();
      },
      tags: ['regression'],
    );
  }

  for (final externalRetry in [false, true]) {
    testWidgets(
      'Plugin Manager announces migration unavailability, ${externalRetry ? 'shared' : 'keyboard'} Retry and recovered content without moving controls',
      (tester) async {
        final source = (await tester.runAsync(
          () => StorageFixture.create(docs),
        ))!;
        final original = File(p.join(docs.path, 'gallery_cache.json'))
          ..writeAsStringSync(
            cache('Retained plugin', stable: externalRetry ? '1.0.0' : null),
          );
        final bytes = original.readAsBytesSync();
        await tester.runAsync(
          () => getAppDirectory(
            isMacOS: true,
            docsProvider: () async => docs,
            supportProvider: () async => support,
          ),
        );
        final database = (await tester.runAsync(
          () async => (await StartupStorageOpener(
            isMacOS: true,
            docsProvider: () async => docs,
            supportProvider: () async => support,
          ).open()).database,
        ))!;
        var fail = true;
        late Completer<void> entered;
        late Completer<void> release;
        final storage = GalleryCacheStorage(
          directory: galleryCacheStorage!.directory,
          documentsProvider: () async => docs,
          checkpoint: (point) async {
            if (point == 'gallery:read') {
              if (fail) {
                throw const FileSystemException('simulated gallery denial');
              }
              entered.complete();
              await release.future;
            }
          },
        );
        final settings = _Settings();
        when(
          () => settings.graphqlEndpoint,
        ).thenReturn('https://example.invalid/graphql');
        final service = GalleryService(
          settingsService: settings,
          database: database,
          cacheStorage: storage,
        );
        final disting = _Disting();
        when(() => disting.state).thenReturn(const DistingState.initial());
        when(() => disting.stream).thenAnswer((_) => const Stream.empty());
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            home: PluginGalleryScreen(
              distingCubit: disting,
              database: database,
              galleryService: service,
            ),
          ),
        );
        final initialTitleRect = tester.getRect(
          find.text('Gallery temporarily unavailable'),
        );
        final initialRetryRect = tester.getRect(
          find.text('Retry gallery transfer'),
        );
        await settleIO(tester);
        expect(
          tester.getRect(find.text('Gallery temporarily unavailable')),
          initialTitleRect,
        );
        expect(
          tester.getRect(find.text('Retry gallery transfer')),
          initialRetryRect,
        );
        expect(find.text('Gallery temporarily unavailable'), findsOneWidget);
        expect(find.text('No plugins found'), findsNothing);
        expect(
          tester
              .getSemantics(find.text('Gallery temporarily unavailable'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        if (externalRetry) {
          final cubit = tester
              .element(find.text('Gallery temporarily unavailable'))
              .read<GalleryCubit>();
          await tester.runAsync(
            () => cubit.loadGallery(
              devicePluginGuids: {'TEST'},
              devicePluginPaths: {'TEST': '/programs/lua/fixture.lua'},
            ),
          );
          await tester.pump();
        }
        final titleRect = tester.getRect(
          find.text('Gallery temporarily unavailable'),
        );
        final retryRect = tester.getRect(find.text('Retry gallery transfer'));
        final installRect = tester.getRect(find.byTooltip('Install from File'));
        final cubit = tester
            .element(find.text('Gallery temporarily unavailable'))
            .read<GalleryCubit>();
        fail = false;
        Focus.of(
          tester.element(find.text('Retry gallery transfer')),
        ).requestFocus();
        await tester.pump();
        await tester.runAsync(() async {
          entered = Completer<void>();
          release = Completer<void>();
          if (externalRetry) {
            unawaited(storage.prepare());
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          }
          await entered.future.timeout(const Duration(seconds: 10));
        });
        await tester.pump(const Duration(milliseconds: 200));
        expect(entered.isCompleted, isTrue);
        await tester.pump();
        expect(find.text('Retrying gallery transfer…'), findsOneWidget);
        expect(
          tester.getRect(find.text('Gallery temporarily unavailable')),
          titleRect,
        );
        expect(tester.getRect(find.text('Retry gallery transfer')), retryRect);
        expect(
          tester.getRect(find.byTooltip('Install from File')),
          installRect,
        );
        await tester.runAsync(() async {
          // Background Drift connections add real isolate work. Await the
          // observable loaded state instead of guessing with repaint loops.
          final current = cubit.state;
          final loaded = current is GalleryLoaded && !current.isRefreshing
              ? Future<void>.value()
              : cubit.stream
                    .firstWhere(
                      (state) => state is GalleryLoaded && !state.isRefreshing,
                    )
                    .then((_) {});
          release.complete();
          await loaded.timeout(const Duration(seconds: 10));
        });
        await tester.pumpAndSettle();
        expect(find.text('Gallery temporarily unavailable'), findsNothing);
        expect(find.text('Retained plugin'), findsOneWidget);
        if (externalRetry) expect(find.byTooltip('Update'), findsOneWidget);
        expect(
          tester.getRect(find.byTooltip('Install from File')),
          installRect,
        );
        expect(original.readAsBytesSync(), bytes);
        expect(announcements.toString(), contains('Retrying gallery transfer'));
        expect(announcements.toString(), contains('Gallery available'));
        await tester.pumpWidget(const SizedBox());
        semantics.dispose();
        storage.dispose();
        await tester.runAsync(() async {
          await database.close();
          await source.close();
        });
      },
      tags: ['regression'],
    );
  }
}
