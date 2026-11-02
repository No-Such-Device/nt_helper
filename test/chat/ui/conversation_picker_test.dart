import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/stored_conversation.dart';
import 'package:nt_helper/chat/ui/conversation_picker.dart';
import 'package:nt_helper/ui/theme/app_theme.dart';

class _Cubit extends Mock implements ChatCubit {}

void main() {
  late _Cubit cubit;
  late List<ConversationSummary> conversations;
  String? selected;
  ConversationSummary summary(String id, String title, DateTime date) =>
      ConversationSummary(
        id: id,
        title: title,
        createdAt: date,
        updatedAt: date,
      );
  setUp(() {
    cubit = _Cubit();
    selected = null;
    conversations = [summary('first', 'Saved first', DateTime.now())];
    when(
      () => cubit.state,
    ).thenReturn(const ChatReady(conversationId: 'first'));
    when(
      () => cubit.listConversations(),
    ).thenAnswer((_) async => List.of(conversations));
  });
  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    double keyboard = 0,
    TextDirection direction = TextDirection.ltr,
    GlobalKey? boundary,
    bool fonts = false,
  }) async {
    var theme = AppTheme.build(
      seedColor: AppTheme.defaultSeedColor,
      brightness: brightness,
    );
    if (fonts) {
      theme = theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Evidence'),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: child!,
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await showDialog<String>(
                  context: context,
                  builder: (_) => ConversationPicker(cubit: cubit),
                );
              },
              child: const Text('Browse'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Browse'));
    await tester.pumpAndSettle();
  }

  Future<void> requestDelete(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Options for Saved first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation'));
    await tester.pumpAndSettle();
  }

  void narrow(WidgetTester tester, {Size size = const Size(320, 480)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('recent-first groups, current marker and selection are clear', (
    tester,
  ) async {
    conversations.add(summary('old', 'Older conversation', DateTime.utc(2025)));
    await open(tester);
    expect(find.text('Saved first'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.textContaining('Current chat'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await tester.tap(find.text('Saved first'));
    await tester.pumpAndSettle();
    expect(selected, 'first');
  });
  testWidgets('search filters locally and Enter opens the result', (
    tester,
  ) async {
    conversations.add(summary('routing', 'Filter routing', DateTime.utc(2025)));
    await open(tester);
    await tester.enterText(find.byType(TextField), 'ROUTING');
    await tester.pumpAndSettle();
    expect(find.text('Saved first'), findsNothing);
    expect(find.text('Filter routing'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selected, 'routing');
    verify(() => cubit.listConversations()).called(1);
  });
  testWidgets('no results can be cleared without losing the list', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'not present');
    await tester.pumpAndSettle();
    expect(find.text('No matching conversations'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Saved first'), findsOneWidget);
  });
  testWidgets('empty history and New chat work on a narrow screen', (
    tester,
  ) async {
    conversations.clear();
    narrow(tester);
    await open(tester);
    expect(find.text('No saved conversations yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byTooltip('New chat')).width,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.byTooltip('New chat'));
    await tester.pumpAndSettle();
    expect(selected, '');
  });
  testWidgets(
    'delete is secondary, confirmed, cancellable, and refreshes after success',
    (tester) async {
      when(() => cubit.deleteConversation('first')).thenAnswer((_) async {
        conversations.clear();
        return true;
      });
      await open(tester);
      await requestDelete(tester);
      expect(find.text('Delete conversation?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => cubit.deleteConversation('first'));
      await requestDelete(tester);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      verify(() => cubit.deleteConversation('first')).called(1);
      expect(find.text('No saved conversations yet'), findsOneWidget);
    },
  );
  testWidgets('delete failure keeps the record and gives a recovery message', (
    tester,
  ) async {
    when(
      () => cubit.deleteConversation('first'),
    ).thenAnswer((_) async => false);
    await open(tester);
    await requestDelete(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not delete the conversation'),
      findsOneWidget,
    );
    expect(find.text('Saved first'), findsOneWidget);
  });
  testWidgets(
    'read errors offer retry rather than pretending history is empty',
    (tester) async {
      var fail = true;
      when(() => cubit.listConversations()).thenAnswer((_) async {
        if (fail) throw StateError('fixture read error');
        return conversations;
      });
      await open(tester);
      expect(find.text('Couldn’t load conversations'), findsOneWidget);
      expect(find.text('No saved conversations yet'), findsNothing);
      fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Saved first'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  , tags: ['regression']);
  testWidgets('Escape cancels without selecting or deleting', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ConversationPicker), findsNothing);
    expect(selected, isNull);
    verifyNever(() => cubit.deleteConversation(any()));
  });
  testWidgets('enlarged text and long RTL titles fit the compact layout', (
    tester,
  ) async {
    narrow(tester);
    conversations = [
      summary(
        'first',
        'محادثة محفوظة — Filter routing and envelope configuration with a very long title 🎛️',
        DateTime.now(),
      ),
    ];
    await open(
      tester,
      scale: 2,
      direction: TextDirection.rtl,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ListView)).height, greaterThan(48));
    expect(find.textContaining('Current chat'), findsOneWidget);
    await tester.tap(find.byTooltip('Close conversations'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  }, tags: ['regression']);
  testWidgets('keyboard insets leave the search and results usable', (
    tester,
  ) async {
    narrow(tester);
    await open(tester, keyboard: 180);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ListView)).height, greaterThan(48));
    await tester.enterText(find.byType(TextField), 'Saved');
    await tester.pumpAndSettle();
    expect(find.text('Saved first'), findsOneWidget);
  }, tags: ['regression']);

  testWidgets(
    'capture native-widget evidence in both themes and compact sizes',
    (tester) async {
      for (final entry in {
        'Evidence': '/System/Library/Fonts/SFNS.ttf',
        'MaterialIcons':
            '/Users/nealsanche/fvm/default/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final file = File(entry.value);
        if (file.existsSync()) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            );
          await loader.load();
        }
      }
      final now = DateTime.now();
      conversations = [
        summary('first', 'Explore the NT settings menu', now),
        summary(
          'routing',
          'Check the Wavetable oscillator routing',
          now.subtract(const Duration(hours: 1)),
        ),
        summary(
          'filter',
          'Find an envelope for the filter',
          now.subtract(const Duration(days: 1)),
        ),
        summary(
          'midi',
          'Set up MIDI and CV routing',
          now.subtract(const Duration(days: 8)),
        ),
      ];
      for (final capture in [
        ('desktop-light', const Size(920, 760), Brightness.light, 1.0),
        ('desktop-dark', const Size(920, 760), Brightness.dark, 1.0),
        ('compact-dark', const Size(320, 480), Brightness.dark, 1.0),
        ('compact-large-type', const Size(320, 480), Brightness.light, 2.0),
      ]) {
        narrow(tester, size: capture.$2);
        final boundary = GlobalKey();
        await open(
          tester,
          brightness: capture.$3,
          scale: capture.$4,
          boundary: boundary,
          fonts: true,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'docs/evidence/chat-conversations/${capture.$1}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
    skip: Platform.environment['CAPTURE_CHAT_PICKER'] != '1',
  );
}
