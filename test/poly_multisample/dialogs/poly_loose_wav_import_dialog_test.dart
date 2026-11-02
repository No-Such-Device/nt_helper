import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/poly_multisample/poly_multisample_models.dart';
import 'package:nt_helper/poly_multisample/poly_sample_import_service.dart';
import 'package:nt_helper/ui/poly_multisample/dialogs/poly_loose_wav_import_dialog.dart';

void main() {
  testWidgets('lists files and mapping modes', (tester) async {
    await _pumpDialogButton(tester, paths: const ['/tmp/A.wav', '/tmp/B.wav']);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('A.wav'), findsOneWidget);
    expect(find.text('B.wav'), findsOneWidget);
    expect(find.text('Use note names from file names'), findsOneWidget);
    expect(find.text('Use Disting automatic notes from C3'), findsOneWidget);
    expect(find.text(['Leave', 'unmapped'].join(' ')), findsNothing);
    expect(find.text('Spread chromatically from start note'), findsOneWidget);
    expect(find.text('Stack as round robins on one note'), findsOneWidget);
    expect(find.text('Stack as velocity layers on one note'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    await tester.tap(find.text('Use Disting automatic notes from C3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Start note:'), findsNothing);
  });

  testWidgets('start note row appears for chromatic mode', (tester) async {
    await _pumpDialogButton(tester, paths: const ['/tmp/A.wav']);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spread chromatically from start note'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Start note: C4'), findsOneWidget);
  });

  testWidgets('cancel returns null', (tester) async {
    PolyStagedImport? result = const PolyStagedImport(
      name: 'sentinel',
      sourceLabel: 'sentinel',
      regions: [],
    );
    await _pumpDialogButton(
      tester,
      paths: const ['/tmp/A.wav'],
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('failure is announced as live status', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpDialogButton(
        tester,
        paths: const ['/tmp/A.wav'],
        importService: _FailingImportService(),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'Loose WAV import failed: .*')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('staging import cannot be dismissed', (tester) async {
    final service = _DelayedImportService();
    PolyStagedImport? result;
    await _pumpDialogButton(
      tester,
      paths: const ['/tmp/A.wav'],
      importService: service,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import'));
    await tester.pump();

    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);
    expect(find.bySemanticsLabel('Importing WAV files'), findsOneWidget);

    await (tester.state(find.byType(Navigator)) as NavigatorState).maybePop();
    await tester.pump();

    expect(find.text('Import WAV files'), findsOneWidget);
    expect(result, isNull);

    service.complete();
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(find.text('Import WAV files'), findsNothing);
  }, tags: ['regression']);
}

Future<void> _pumpDialogButton(
  WidgetTester tester, {
  required List<String> paths,
  PolySampleImportService? importService,
  ValueChanged<PolyStagedImport?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final result = await showPolyLooseWavImportDialog(
                  context,
                  paths: paths,
                  importService: importService,
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

class _FailingImportService extends PolySampleImportService {
  @override
  Future<PolyStagedImport> stageLooseFiles(
    List<String> paths,
    PolyLooseWavMappingOptions options,
  ) {
    throw Exception('Loose import failed.');
  }
}

class _DelayedImportService extends PolySampleImportService {
  final _completer = Completer<PolyStagedImport>();

  @override
  Future<PolyStagedImport> stageLooseFiles(
    List<String> paths,
    PolyLooseWavMappingOptions options,
  ) {
    return _completer.future;
  }

  void complete() {
    _completer.complete(
      const PolyStagedImport(
        name: 'Imported WAVs',
        sourceLabel: '/tmp',
        regions: [],
      ),
    );
  }
}
