import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal MaterialApp that mirrors the production builder wiring: wraps its
/// child in a [MediaQuery] override driven by the [SettingsService.uiScaleNotifier].
Widget _buildScaledApp({required Widget child}) {
  return MaterialApp(
    builder: (context, appChild) {
      return ValueListenableBuilder<double>(
        valueListenable: SettingsService().uiScaleNotifier,
        builder: (context, scale, _) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(scale)),
            child: appChild ?? const SizedBox.shrink(),
          );
        },
      );
    },
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    await SettingsService().setUiScale(SettingsService.defaultUiScale);
  });

  testWidgets('default scale produces a linear(1.0) textScaler', (
    tester,
  ) async {
    late TextScaler capturedScaler;
    await tester.pumpWidget(
      _buildScaledApp(
        child: Builder(
          builder: (context) {
            capturedScaler = MediaQuery.textScalerOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    expect(capturedScaler.scale(14), 14);
  });

  testWidgets('increasing uiScale rebuilds with a larger textScaler', (
    tester,
  ) async {
    final captured = <double>[];

    await tester.pumpWidget(
      _buildScaledApp(
        child: Builder(
          builder: (context) {
            captured.add(MediaQuery.textScalerOf(context).scale(10));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    expect(captured.last, 10);

    await SettingsService().setUiScale(1.3);
    await tester.pump();

    expect(captured.last, closeTo(13, 0.0001));
  });

  testWidgets('decreasing uiScale shrinks the textScaler', (tester) async {
    final captured = <double>[];

    await tester.pumpWidget(
      _buildScaledApp(
        child: Builder(
          builder: (context) {
            captured.add(MediaQuery.textScalerOf(context).scale(10));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    await SettingsService().setUiScale(0.8);
    await tester.pump();

    expect(captured.last, closeTo(8, 0.0001));
  });
}
