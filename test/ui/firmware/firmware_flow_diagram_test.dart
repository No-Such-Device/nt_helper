import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/models/flash_progress.dart';
import 'package:nt_helper/models/flash_stage.dart';
import 'package:nt_helper/ui/firmware/firmware_flow_diagram.dart';

Future<void> _pump(
  WidgetTester tester, {
  required FlashProgress progress,
  bool reduceMotion = false,
  Brightness brightness = Brightness.light,
  double width = 600,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 150,
              child: FirmwareFlowDiagram(progress: progress),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('FirmwareFlowDiagram', () {
    testWidgets(
      'renders at the documented 600x150 size for every FlashStage without throwing',
      (tester) async {
        for (final stage in FlashStage.values) {
          await _pump(
            tester,
            progress: FlashProgress(stage: stage, percent: 50, message: ''),
          );

          expect(
            tester.takeException(),
            isNull,
            reason: 'should not throw for stage $stage',
          );

          final paintFinder = find.descendant(
            of: find.byType(FirmwareFlowDiagram),
            matching: find.byType(CustomPaint),
          );
          expect(
            paintFinder,
            findsWidgets,
            reason: 'CustomPaint should be present for stage $stage',
          );

          final svgFinder = find.descendant(
            of: find.byType(FirmwareFlowDiagram),
            matching: find.byType(SvgPicture),
          );
          expect(
            svgFinder,
            findsOneWidget,
            reason: 'SvgPicture should render disting NT icon for stage $stage',
          );

          final size = tester.getSize(find.byType(FirmwareFlowDiagram));
          expect(
            size,
            const Size(600, 150),
            reason: 'widget should fill its 600x150 container for stage $stage',
          );
        }
      },
    );

    testWidgets('renders the error variant without overflow', (tester) async {
      await _pump(
        tester,
        progress: FlashProgress(
          stage: FlashStage.write,
          percent: 75,
          message: 'flashing',
          isError: true,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FirmwareFlowDiagram)),
        const Size(600, 150),
      );
      expect(
        find.descendant(
          of: find.byType(FirmwareFlowDiagram),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders the reduced-motion (static) variant', (tester) async {
      await _pump(
        tester,
        progress: FlashProgress(
          stage: FlashStage.sdpUpload,
          percent: 25,
          message: '',
        ),
        reduceMotion: true,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FirmwareFlowDiagram)),
        const Size(600, 150),
      );
      expect(
        find.descendant(
          of: find.byType(FirmwareFlowDiagram),
          matching: find.byType(SvgPicture),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders under a dark theme without throwing', (tester) async {
      await _pump(
        tester,
        progress: FlashProgress(
          stage: FlashStage.write,
          percent: 50,
          message: '',
        ),
        brightness: Brightness.dark,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FirmwareFlowDiagram)),
        const Size(600, 150),
      );
    });

    testWidgets('renders at a narrower width without overflow', (tester) async {
      await _pump(
        tester,
        progress: FlashProgress(
          stage: FlashStage.complete,
          percent: 100,
          message: '',
        ),
        width: 300,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FirmwareFlowDiagram)),
        const Size(300, 150),
      );
    });
  });
}
