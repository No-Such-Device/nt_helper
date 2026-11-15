import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/app_release.dart';
import 'package:nt_helper/ui/widgets/app_update_banner.dart';

void main() {
  final testRelease = AppRelease(
    version: '3.0.0',
    tagName: 'v3.0.0',
    body: 'Test release notes',
    publishedAt: DateTime(2026, 2, 1),
    platformAssets: {'macos': 'https://example.com/update.zip'},
  );

  Widget buildBanner({
    AppRelease? release,
    VoidCallback? onWhatsNew,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AppUpdateBanner(
          release: release,
          onWhatsNew: onWhatsNew ?? () {},
          onDismiss: onDismiss ?? () {},
        ),
      ),
    );
  }

  group('AppUpdateBanner', () {
    testWidgets('shows version when release is provided', (tester) async {
      await tester.pumpWidget(buildBanner(release: testRelease));
      await tester.pumpAndSettle();

      expect(find.text('NT Helper 3.0.0 available'), findsOneWidget);
    });

    testWidgets('has zero height when release is null', (tester) async {
      await tester.pumpWidget(buildBanner());
      await tester.pumpAndSettle();

      // The banner renders at zero height and zero opacity when no release
      final size = tester.getSize(find.byType(AppUpdateBanner));
      expect(size.height, 0);
    });

    testWidgets('calls onWhatsNew when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildBanner(release: testRelease, onWhatsNew: () => tapped = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text("What's New"));
      expect(tapped, isTrue);
    });

    testWidgets('calls onDismiss when close button tapped', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildBanner(release: testRelease, onDismiss: () => dismissed = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('has correct semantics', (tester) async {
      await tester.pumpWidget(buildBanner(release: testRelease));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(AppUpdateBanner));
      expect(semantics.label, contains('NT Helper 3.0.0 is available'));
    });

    testWidgets('shows update icon', (tester) async {
      await tester.pumpWidget(buildBanner(release: testRelease));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.system_update), findsOneWidget);
    });
  });
}
