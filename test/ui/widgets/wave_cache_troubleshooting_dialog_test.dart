import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/services/wave_cache_maintenance_service.dart';
import 'package:nt_helper/ui/widgets/wave_cache_troubleshooting_dialog.dart';

class _MockWaveCacheMaintenanceService extends Mock
    implements WaveCacheMaintenanceService {}

void main() {
  late _MockWaveCacheMaintenanceService service;

  setUp(() {
    service = _MockWaveCacheMaintenanceService();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => WaveCacheTroubleshootingDialog(service: service),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('requires a fragment and marks the dialog title as a header', (
    tester,
  ) async {
    await pumpDialog(tester);

    final findButton = tester.widget<FilledButton>(
      find.byKey(const Key('wave-cache-find-fragment')),
    );
    expect(findButton.onPressed, isNull);
    expect(
      tester
          .getSemantics(find.text('Wave cache troubleshooting'))
          .flagsCollection
          .isHeader,
      true,
    );

    await tester.enterText(
      find.byKey(const Key('wave-cache-fragment')),
      'FM1 - Track 44',
    );
    await tester.pump();

    final enabledFindButton = tester.widget<FilledButton>(
      find.byKey(const Key('wave-cache-find-fragment')),
    );
    expect(enabledFindButton.onPressed, isNotNull);
  });

  testWidgets('reviews a targeted match before deleting and remounting', (
    tester,
  ) async {
    const plan = WaveCacheCleanupPlan(
      sampleFragment: 'Track 44',
      matchedSamplePaths: ['/samples/Future Music CD1/FM1 - Track 44.wav'],
      cachePaths: ['/samples/Future Music CD1/distingNT.wavcache'],
      directoriesWithoutCache: [],
    );
    const result = WaveCacheCleanupResult(
      plan: plan,
      deletedCachePaths: ['/samples/Future Music CD1/distingNT.wavcache'],
      failedCachePaths: {},
      remountRequested: true,
    );
    when(
      () => service.findForSampleFragment('Track 44'),
    ).thenAnswer((_) async => plan);
    when(() => service.deleteAndRemount(plan)).thenAnswer((_) async => result);
    await pumpDialog(tester);

    await tester.enterText(
      find.byKey(const Key('wave-cache-fragment')),
      'Track 44',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('wave-cache-find-fragment')));
    await tester.pumpAndSettle();

    expect(find.text('Matching WAV files'), findsOneWidget);
    expect(
      find.text('/samples/Future Music CD1/FM1 - Track 44.wav'),
      findsOneWidget,
    );
    expect(
      find.text('/samples/Future Music CD1/distingNT.wavcache'),
      findsOneWidget,
    );
    verifyNever(() => service.deleteAndRemount(plan));

    await tester.tap(find.byKey(const Key('wave-cache-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Wave cache reset complete'), findsOneWidget);
    expect(
      find.textContaining('the SD card remount was requested'),
      findsOneWidget,
    );
    verify(() => service.deleteAndRemount(plan)).called(1);
  });

  testWidgets('offers a separate all-cache scan with the same review step', (
    tester,
  ) async {
    const plan = WaveCacheCleanupPlan(
      sampleFragment: null,
      matchedSamplePaths: [],
      cachePaths: [
        '/samples/Kit/distingNT.wavcache',
        '/wavetables/Bank/distingNT.wavcache',
      ],
      directoriesWithoutCache: [],
    );
    when(() => service.findAll()).thenAnswer((_) async => plan);
    await pumpDialog(tester);

    await tester.tap(find.byKey(const Key('wave-cache-find-all')));
    await tester.pumpAndSettle();

    expect(find.text('2 wave cache files were found.'), findsOneWidget);
    expect(find.text('Delete 2 caches and remount'), findsOneWidget);
    verify(() => service.findAll()).called(1);
    verifyNever(() => service.deleteAndRemount(plan));
  });
}
