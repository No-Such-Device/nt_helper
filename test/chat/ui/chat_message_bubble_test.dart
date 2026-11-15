import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/ui/chat_message_bubble.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'assistant Markdown stays readable selectable and announced with $brightness Material',
      (tester) async {
        // Transcript layout tests do not exercise the renderer's Material
        // integration, selectable rich content, or live reply semantics.
        final semantics = tester.ensureSemantics();
        try {
          const content =
              '# Routing\n\nConnect **input** to `bus 13`.\n\n'
              '| Bus | Destination |\n| --- | --- |\n| 13 | Output |\n\n'
              '```json\n{"slot":1}\n```\n\n> Keep this preset.';
          final theme = ThemeData(brightness: brightness);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ChatMessageBubble(
                    message: ChatMessage(
                      id: 'renderer-migration',
                      role: ChatMessageRole.assistant,
                      content: content,
                      timestamp: DateTime(2026),
                    ),
                    isNew: true,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(SelectionArea), findsOneWidget);
          expect(
            find.textContaining('Connect', findRichText: true),
            findsWidgets,
          );
          expect(
            find.textContaining('Output', findRichText: true),
            findsWidgets,
          );
          expect(find.textContaining('slot', findRichText: true), findsWidgets);
          final reply = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          );
          expect(reply, findsOneWidget);
          expect(
            tester.getSemantics(reply).label,
            contains('Assistant: $content'),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
