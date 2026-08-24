import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nt_helper/chat/cubit/chat_cubit.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/chat/ui/chat_panel.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:nt_helper/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockToolRegistry extends Mock implements ToolRegistry {}

class _MockMemoryService extends Mock implements MemoryService {}

class _MockChatCubit extends MockCubit<ChatState> implements ChatCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatCubit cubit;
  late _MockToolRegistry toolRegistry;
  late _MockMemoryService memoryService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService().init();
    toolRegistry = _MockToolRegistry();
    memoryService = _MockMemoryService();
    when(() => toolRegistry.entries).thenReturn(const []);
    when(
      () => memoryService.saveSessionSnapshot(any()),
    ).thenAnswer((_) async {});
    cubit = ChatCubit(toolRegistry: toolRegistry, memoryService: memoryService);
  });

  tearDown(() async {
    await cubit.close();
  });

  testWidgets('header uses context status arc instead of clear icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ChatCubit>.value(
            value: cubit,
            child: const ChatPanel(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byTooltip('Context status'), findsOneWidget);

    await tester.tap(find.byTooltip('Context status'));
    await tester.pumpAndSettle();

    expect(find.text('Context'), findsOneWidget);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.text('Compact context'), findsOneWidget);
    expect(find.text('Clear chat...'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('clear chat menu item requires confirmation before clearing', (
    tester,
  ) async {
    final mockCubit = _MockChatCubit();
    when(() => mockCubit.state).thenReturn(
      ChatReady(messages: [ChatMessage.user('keep me until confirmed')]),
    );
    when(
      () => mockCubit.contextSummary,
    ).thenReturn(const ChatContextSummary(messageCount: 1, userMessages: 1));
    when(() => mockCubit.clearChat()).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ChatCubit>.value(
            value: mockCubit,
            child: const ChatPanel(),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Context status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear chat...'));
    await tester.pumpAndSettle();

    expect(find.text('Clear chat?'), findsOneWidget);
    verifyNever(() => mockCubit.clearChat());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => mockCubit.clearChat());
  });

  testWidgets('tool use does not move a bottom-pinned transcript', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockCubit = _MockChatCubit();
    final messages = List.generate(
      8,
      (index) => ChatMessage.assistant(
        index == 7
            ? 'Stable transcript anchor'
            : 'Earlier response $index with enough text to fill the panel.',
      ),
    );
    final thinkingState = ChatReady(messages: messages, isProcessing: true);
    final states = StreamController<ChatState>();
    addTearDown(states.close);
    whenListen(mockCubit, states.stream, initialState: thinkingState);
    when(
      () => mockCubit.contextSummary,
    ).thenReturn(ChatContextSummary(messageCount: messages.length));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ChatCubit>.value(
            value: mockCubit,
            child: const ChatPanel(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    final listScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    listScroll.position.jumpTo(listScroll.position.maxScrollExtent);
    await tester.pump();

    final anchor = find.text('Stable transcript anchor');
    expect(anchor, findsOneWidget);
    final thinkingY = tester.getTopLeft(anchor).dy;

    states.add(
      ChatReady(
        messages: messages,
        isProcessing: true,
        currentToolName: 'show_preset',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Working...'), findsOneWidget);
    expect(find.bySemanticsLabel('Working...'), findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, closeTo(thinkingY, 0.1));

    states.add(thinkingState);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Working...'), findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, closeTo(thinkingY, 0.1));
  });
}
