import 'dart:async';
import 'dart:math' show max, min;

import 'package:genkit/genkit.dart' as g;
// Genkit 1.0 agents are deliberately pinned behind this runtime boundary.
// ignore: experimental_member_use
import 'package:genkit/experimental.dart' as g;
import 'package:schemantic/schemantic.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart'
    show LlmApiException;
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/genkit_message_codec.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/chat/utils/image_result_detector.dart';

export 'chat_history.dart' show providerSafeToolHistory;
import 'chat_history.dart';

sealed class ChatLoopEvent {}

class ChatLoopThinking extends ChatLoopEvent {}

class ChatLoopTextDelta extends ChatLoopEvent {
  final String messageId;
  final String delta;
  ChatLoopTextDelta(this.messageId, this.delta);
}

class ChatLoopToolCall extends ChatLoopEvent {
  final LlmToolCall toolCall;
  ChatLoopToolCall(this.toolCall);
}

class ChatLoopToolResult extends ChatLoopEvent {
  final String toolCallId;
  final String toolName;
  final String result;
  final String? imageBase64;
  final String? imageMimeType;
  ChatLoopToolResult(
    this.toolCallId,
    this.toolName,
    this.result, {
    this.imageBase64,
    this.imageMimeType,
  });
}

class ChatLoopAssistantMessage extends ChatLoopEvent {
  final String content;
  final LlmUsage? usage;
  final bool isFinal;
  final List<LlmMessage>? finalHistory;
  final String? messageId;
  ChatLoopAssistantMessage(
    this.content, {
    this.usage,
    this.isFinal = false,
    this.finalHistory,
    this.messageId,
  });
}

class ChatLoopError extends ChatLoopEvent {
  final String message;
  final List<LlmMessage>? finalHistory;
  ChatLoopError(this.message, {this.finalHistory});
}

class ChatLoopRateLimited extends ChatLoopEvent {
  final int waitSeconds;
  final int attempt;
  final int maxAttempts;
  ChatLoopRateLimited({
    required this.waitSeconds,
    required this.attempt,
    required this.maxAttempts,
  });
}

/// Genkit owns generation, ordered tool rounds, and the in-flight transcript.
/// The finalized snapshot is handed back to the conversation owner between runs.
/// No coding tools, MCP client, reflection server, or remote backend is enabled.
class ChatService {
  final LlmProvider _provider;
  final ToolBridgeService _toolBridge;
  final String _systemPrompt;
  final _cancel = g.CancellationController();
  Future<void>? _work;
  Future<void>? _cleanup;
  List<LlmMessage>? lastGoodHistory;

  ChatService({
    required this._provider,
    required this._toolBridge,
    required this._systemPrompt,
  });

  Future<void> cancel() async {
    _cancel.cancel('Chat stopped');
    try {
      await _releaseControls();
    } catch (_) {
      /* Remote state retains uncertainty. */
    }
    await _work;
  }

  Future<void> _releaseControls() =>
      _cleanup ??= _toolBridge.cancelRemoteControl();

  Stream<ChatLoopEvent> runAgenticLoop(List<LlmMessage> messages) {
    late StreamController<ChatLoopEvent> events;
    events = StreamController<ChatLoopEvent>(
      onListen: () {
        _work =
            _run(List.of(messages), (event) {
              if (!_cancel.isCancelled && !events.isClosed) events.add(event);
            }).whenComplete(() {
              unawaited(events.close());
            });
      },
      onCancel: cancel,
    );
    return events.stream;
  }

  Future<void> _run(
    List<LlmMessage> messages,
    void Function(ChatLoopEvent) emit,
  ) async {
    final ai = g.Genkit(isDevEnv: false, promptDir: null);
    var input = 0;
    var output = 0;
    var cacheCreated = 0;
    var cacheRead = 0;
    var peakInput = 0;
    var turnNumber = 0;
    var currentMessageId = '';
    Object? failure;
    g.AgentChat<dynamic>? activeChat;
    try {
      final definitions = _toolBridge.toolDefinitions;
      final tools = [
        for (final definition in definitions)
          ai.defineTool<Map<String, dynamic>, dynamic>(
            name: definition.name,
            description: definition.description,
            inputSchema: SchemanticType.from(
              jsonSchema: {'type': 'object', ...definition.inputSchema},
              parse: (value) => Map<String, dynamic>.from(value as Map),
            ),
            fn: (args, context) async {
              _cancel.token.throwIfCancelled();
              final id =
                  context.toolRequest?.toolRequest.ref ?? definition.name;
              emit(
                ChatLoopToolCall(
                  LlmToolCall(id: id, name: definition.name, arguments: args),
                ),
              );
              final result = await _toolBridge.executeTool(
                definition.name,
                args,
              );
              _cancel.token.throwIfCancelled();
              final image = tryParseImageResult(result);
              emit(
                ChatLoopToolResult(
                  id,
                  definition.name,
                  result,
                  imageBase64: image?.data,
                  imageMimeType: image?.mimeType,
                ),
              );
              return g.ToolResult.response(
                image == null
                    ? result
                    : {'type': image.mimeType, 'size': 'image data'},
                parts: image == null
                    ? null
                    : [
                        g.MediaPart(
                          media: g.Media(
                            url: 'data:${image.mimeType};base64,${image.data}',
                            contentType: image.mimeType,
                          ),
                        ),
                      ],
              );
            },
          ),
      ];
      ai.defineModel(
        name: 'nt-provider',
        fn: (request, context) async {
          currentMessageId = 'genkit-turn-${turnNumber++}';
          final messageId = currentMessageId;
          emit(ChatLoopThinking());
          final providerMessages = fromGenkitMessages(request.messages);
          // Keep the exact last Genkit request as a recovery checkpoint. A
          // failed client-managed turn can roll its public chat state back.
          lastGoodHistory = List.unmodifiable(
            providerSafeToolHistory(providerMessages),
          );
          String? system;
          for (final message in request.messages) {
            if (message.role == g.Role.system) system = message.text;
          }
          LlmResponse? response;
          var streamed = false;
          for (var retry = 0; retry <= 4; retry++) {
            _cancel.token.throwIfCancelled();
            try {
              final provider = _provider;
              if (provider is StreamingLlmProvider) {
                response = await provider.sendMessagesStreaming(
                  messages: providerMessages,
                  tools: definitions,
                  systemPrompt: system ?? _systemPrompt,
                  cancel: _cancel.token,
                  onTextDelta: (delta) {
                    _cancel.token.throwIfCancelled();
                    streamed = true;
                    emit(ChatLoopTextDelta(messageId, delta));
                    context.sendChunk(
                      g.ModelResponseChunk(content: [g.TextPart(text: delta)]),
                    );
                  },
                );
              } else {
                response = await Future.any([
                  provider.sendMessages(
                    messages: providerMessages,
                    tools: definitions,
                    systemPrompt: system ?? _systemPrompt,
                  ),
                  _cancel.token.whenCancelled.then<LlmResponse>(
                    (_) => throw g.CancelledException(),
                  ),
                ]);
              }
              break;
            } on LlmApiException catch (error) {
              if (!error.isRateLimited || streamed) rethrow;
              if (retry == 4) {
                throw LlmApiException(
                  'Rate limited by the API after 4 retries. Please try again later.',
                  statusCode: error.statusCode,
                );
              }
              final wait = min(error.retryAfterSeconds ?? (1 << retry), 30);
              emit(
                ChatLoopRateLimited(
                  waitSeconds: wait,
                  attempt: retry + 1,
                  maxAttempts: 4,
                ),
              );
              await Future.any([
                Future<void>.delayed(Duration(seconds: wait)),
                _cancel.token.whenCancelled,
              ]);
            }
          }
          _cancel.token.throwIfCancelled();
          final value = response!;
          final usage = value.usage;
          if (usage != null) {
            input += usage.inputTokens;
            output += usage.outputTokens;
            cacheCreated += usage.cacheCreationInputTokens;
            cacheRead += usage.cacheReadInputTokens;
            peakInput = max(peakInput, usage.contextInputTokens);
          }
          if (value.hasToolCalls && (value.content?.isNotEmpty ?? false)) {
            emit(
              ChatLoopAssistantMessage(value.content!, messageId: messageId),
            );
          }
          return g.ModelResponse(
            finishReason: g.FinishReason.stop,
            message: toGenkitMessage(
              LlmMessage.assistantWithToolCalls(
                value.toolCalls,
                content: value.content,
                providerMetadata: value.providerMetadata,
              ),
            ),
          );
        },
      );
      final safe = providerSafeToolHistory(messages);
      if (safe.isEmpty || safe.last.role != LlmRole.user) {
        throw StateError('A chat turn must end with a user message.');
      }
      final history = toGenkitMessages(safe);
      final user = history.removeLast();
      final agent = ai.defineAgent(
        name: 'nt-assistant',
        model: g.modelRef('nt-provider'),
        system: _systemPrompt,
        tools: tools,
        maxTurns: 100,
      );
      final chat = agent.chat(
        state: g.SessionState(messages: history, artifacts: []),
      );
      activeChat = chat;
      final turn = chat.sendStream(message: user, cancel: _cancel.token);
      // Consume the stream even though provider/tool hooks project richer UI
      // events. The agent stream applies authoritative session-state updates.
      await turn.stream.drain<void>();
      final response = await turn.response;
      _cancel.token.throwIfCancelled();
      if (response.finishReason != g.AgentFinishReason.stop) {
        throw StateError(
          'Agent stopped without an answer (${response.finishReason.value}).',
        );
      }
      await _releaseControls();
      emit(
        ChatLoopAssistantMessage(
          response.text,
          messageId: currentMessageId,
          isFinal: true,
          finalHistory: List.unmodifiable(fromGenkitMessages(chat.messages)),
          usage: LlmUsage(
            inputTokens: input,
            outputTokens: output,
            cacheCreationInputTokens: cacheCreated,
            cacheReadInputTokens: cacheRead,
            peakInputTokens: peakInput,
          ),
        ),
      );
    } catch (error) {
      failure = error;
    } finally {
      try {
        await _releaseControls();
      } catch (error) {
        failure ??= error;
      }
      if (activeChat != null) {
        final snapshot = providerSafeToolHistory(
          fromGenkitMessages(activeChat.messages),
        );
        if (snapshot.length >= (lastGoodHistory?.length ?? 0)) {
          lastGoodHistory = List.unmodifiable(snapshot);
        }
      }
      await ai.shutdown();
      // A terminal UI error must not make a new send possible before the
      // preceding run has finished its hardware cleanup.
      if (failure != null && !_cancel.isCancelled) {
        emit(ChatLoopError(failure.toString(), finalHistory: lastGoodHistory));
      }
    }
  }
}
