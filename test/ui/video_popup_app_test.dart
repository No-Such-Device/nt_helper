import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/domain/disting_nt_sysex.dart';
import 'package:nt_helper/ui/video_popup_app.dart';

void main() {
  testWidgets('pin button exposes semantics and toggles always on top', (
    tester,
  ) async {
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoPopupTopBar(
            alwaysOnTop: false,
            onToggleAlwaysOnTop: () => toggles++,
            onSetDisplayMode: (_) {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byTooltip('Keep video window on top'), findsOneWidget);

    await tester.tap(find.byTooltip('Keep video window on top'));
    expect(toggles, 1);
  });

  testWidgets('display mode buttons call back with selected mode', (
    tester,
  ) async {
    final selectedModes = <DisplayMode>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoPopupTopBar(
            alwaysOnTop: true,
            onToggleAlwaysOnTop: () {},
            onSetDisplayMode: selectedModes.add,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.push_pin), findsOneWidget);

    await tester.tap(find.byTooltip('Algorithm UI'));
    expect(selectedModes, [DisplayMode.algorithmUI]);
  });
}
