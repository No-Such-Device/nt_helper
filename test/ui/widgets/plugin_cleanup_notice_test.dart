import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/plugin_cleanup_outcome.dart';
import 'package:nt_helper/ui/widgets/plugin_cleanup_notice.dart';

const _rootPath = '/programs/plug-ins/seq.o';

Future<void> _show(WidgetTester tester, PluginCleanupOutcome outcome) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPluginCleanupNotice(
              ScaffoldMessenger.of(context),
              outcome,
              Theme.of(context).colorScheme,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void _expectLiveStatus(WidgetTester tester, String message) {
  expect(find.text(message), findsOneWidget);
  final status = tester.getSemantics(find.text(message));
  expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
  // Never promises the new plugin takes effect immediately.
  expect(message.toLowerCase(), isNot(contains('now')));
  expect(message.toLowerCase(), isNot(contains('effect')));
}

void main() {
  testWidgets('removed shows a live notice naming the root path', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _show(tester, const PluginCleanupRemoved(_rootPath));

    final message = pluginCleanupMessage(
      const PluginCleanupRemoved(_rootPath),
    )!;
    expect(message, contains(_rootPath));
    _expectLiveStatus(tester, message);
    semantics.dispose();
  });

  testWidgets('deletion failed shows a live warning and no success notice', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _show(tester, const PluginCleanupDeletionFailed(_rootPath));

    final message = pluginCleanupMessage(
      const PluginCleanupDeletionFailed(_rootPath),
    )!;
    expect(message, contains(_rootPath));
    _expectLiveStatus(tester, message);
    expect(find.textContaining('Removed'), findsNothing);
    semantics.dispose();
  });

  testWidgets('could not be verified shows a live warning naming the path', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _show(tester, const PluginCleanupCouldNotBeVerified(_rootPath));

    final message = pluginCleanupMessage(
      const PluginCleanupCouldNotBeVerified(_rootPath),
    )!;
    expect(message, contains(_rootPath));
    _expectLiveStatus(tester, message);
    expect(find.textContaining('Removed'), findsNothing);
    semantics.dispose();
  });

  testWidgets('skipped shows nothing', (tester) async {
    await _show(tester, const PluginCleanupSkipped());
    expect(find.byType(SnackBar), findsNothing);
  });
}
