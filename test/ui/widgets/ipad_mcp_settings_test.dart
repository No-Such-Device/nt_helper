import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nt_helper/services/ipad_local_network.dart';
import 'package:nt_helper/ui/widgets/ipad_mcp_settings.dart';

void main() {
  // Existing desktop settings tests do not cover native loading, local endpoint
  // discovery, iPad opt-in semantics or geometry while that lookup completes.
  testWidgets(
    'iPad Settings opt-in is accessible and native lookup does not move controls',
    (tester) async {
      final native = Completer<Map<String, Object?>>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        IpadLocalNetwork.channel,
        (_) => native.future,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(IpadLocalNetwork.channel, null),
      );
      final semantics = tester.ensureSemantics();
      var enabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  IpadMcpSettings(
                    value: enabled,
                    onChanged: (value) => setState(() => enabled = value),
                  ),
                  const Text('Following settings', key: ValueKey('following')),
                ],
              ),
            ),
          ),
        ),
      );
      final following = find.byKey(const ValueKey('following'));
      final rect = tester.getRect(following);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      native.complete({
        'isIpad': true,
        'networks': [
          {
            'address': [192, 168, 2, 7],
            'netmask': [255, 255, 255, 0],
          },
        ],
      });
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(following), rect);
      expect(find.text('http://192.168.2.7:3847/mcp'), findsOneWidget);
      final toggle = find.byType(Switch);
      expect(tester.getSemantics(toggle).label, contains('Enable MCP on iPad'));
      await tester.tap(toggle);
      await tester.pump();
      expect(enabled, isTrue);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(
        tester
            .getSemantics(toggle)
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      // A label alone cannot prove that screen-reader activation works.
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          viewId: tester.view.viewId,
          nodeId: tester.getSemantics(toggle).id,
          type: SemanticsAction.tap,
        ),
      );
      await tester.pump();
      expect(enabled, isFalse);
      expect(
        tester
            .getSemantics(toggle)
            .getSemanticsData()
            .flagsCollection
            .isToggled,
        Tristate.isFalse,
      );
      expect(tester.getRect(following), rect);
      semantics.dispose();
    },
  );

  testWidgets(
    'network lookup failure explains unavailable iPad opt-in without layout movement',
    (tester) async {
      final native = Completer<Map<String, Object?>>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        IpadLocalNetwork.channel,
        (_) => native.future,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(IpadLocalNetwork.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                IpadMcpSettings(
                  value: false,
                  onChanged: (_) => fail('Unavailable toggle activated'),
                ),
                const Text('Following settings', key: ValueKey('following')),
              ],
            ),
          ),
        ),
      );
      final following = find.byKey(const ValueKey('following'));
      final rect = tester.getRect(following);
      native.completeError(StateError('Unavailable'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Local network information unavailable.'),
        findsOneWidget,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(tester.getRect(following), rect);
    },
  );
}
