import 'dart:async';
import 'dart:math' show max, min;

import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart'
    show LlmApiException;
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/chat/utils/image_result_detector.dart';

/// Events emitted during the agentic loop.
sealed class ChatLoopEvent {}

class ChatLoopThinking extends ChatLoopEvent {}

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

  /// When [isFinal] is true, contains the full updated LLM history including
  /// all tool calls/results and the final assistant message, ready to replace
  /// the cubit's [_llmHistory].
  final List<LlmMessage>? finalHistory;
  ChatLoopAssistantMessage(
    this.content, {
    this.usage,
    this.isFinal = false,
    this.finalHistory,
  });
}

class ChatLoopError extends ChatLoopEvent {
  final String message;
  ChatLoopError(this.message);
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

/// Orchestrates the agentic tool-use loop.
///
/// Sends messages to the LLM, executes tool calls, appends results, and loops
/// until the LLM produces a final text response. Yields [ChatLoopEvent]s so
/// the UI can update in real time.
class ChatService {
  final LlmProvider _provider;
  final ToolBridgeService _toolBridge;
  final String _systemPrompt;

  static const _maxIterations = 100;
  static const _maxRateLimitRetries = 4;
  static const _maxBackoffSeconds = 30;

  ChatService({
    required LlmProvider provider,
    required ToolBridgeService toolBridge,
    required String systemPrompt,
  }) : _provider = provider,
       _toolBridge = toolBridge,
       _systemPrompt = systemPrompt;

  /// Run the agentic loop as a stream of events.
  ///
  /// [messages] is the current conversation history (user + assistant messages).
  /// The stream yields events as the loop progresses and completes when the
  /// LLM produces a final response with no tool calls.
  Stream<ChatLoopEvent> runAgenticLoop(List<LlmMessage> messages) async* {
    // Work on a private copy so that cancellation or external mutation of the
    // caller's history list cannot corrupt the loop's in-flight state. Repair
    // incomplete tool groups at this provider boundary as well: strict
    // providers reject orphan results or calls without adjacent results.
    final currentMessages = providerSafeToolHistory(messages);
    final tools = _toolBridge.toolDefinitions;

    // Accumulate token usage across all API calls in the loop, not just the
    // final one.
    int totalInputTokens = 0;
    int totalOutputTokens = 0;
    int totalCacheCreationInputTokens = 0;
    int totalCacheReadInputTokens = 0;
    int peakInputTokens = 0;

    for (int i = 0; i < _maxIterations; i++) {
      yield ChatLoopThinking();

      LlmResponse? response;
      for (int retry = 0; retry <= _maxRateLimitRetries; retry++) {
        try {
          response = await _provider.sendMessages(
            messages: currentMessages,
            tools: tools,
            systemPrompt: _systemPrompt,
          );
          break;
        } on LlmApiException catch (e) {
          if (!e.isRateLimited || retry == _maxRateLimitRetries) {
            if (e.isRateLimited) {
              yield ChatLoopError(
                'Rate limited by the API after $_maxRateLimitRetries '
                'retries. Please wait a few minutes before trying again.',
              );
            } else {
              yield ChatLoopError(e.toString());
            }
            return;
          }
          final backoff = min(
            e.retryAfterSeconds ?? (1 << retry),
            _maxBackoffSeconds,
          );
          yield ChatLoopRateLimited(
            waitSeconds: backoff,
            attempt: retry + 1,
            maxAttempts: _maxRateLimitRetries,
          );
          await Future<void>.delayed(Duration(seconds: backoff));
        } catch (e) {
          yield ChatLoopError(e.toString());
          return;
        }
      }
      if (response == null) return;

      // Accumulate usage from every API call
      if (response.usage != null) {
        final usage = response.usage!;
        totalInputTokens += usage.inputTokens;
        totalOutputTokens += usage.outputTokens;
        totalCacheCreationInputTokens += usage.cacheCreationInputTokens;
        totalCacheReadInputTokens += usage.cacheReadInputTokens;
        peakInputTokens = max(peakInputTokens, usage.contextInputTokens);
      }

      if (response.hasToolCalls) {
        // Add assistant message with tool calls to history
        currentMessages.add(
          LlmMessage.assistantWithToolCalls(
            response.toolCalls,
            content: response.content,
          ),
        );

        if (response.content != null && response.content!.isNotEmpty) {
          yield ChatLoopAssistantMessage(response.content!);
        }

        // Execute each tool call
        for (final toolCall in response.toolCalls) {
          yield ChatLoopToolCall(toolCall);

          final result = await _toolBridge.executeTool(
            toolCall.name,
            toolCall.arguments,
          );

          final image = tryParseImageResult(result);
          final String llmContent;
          String? imageBase64;
          String? imageMimeType;
          if (image != null) {
            llmContent = '{"type":"${image.mimeType}","size":"image data"}';
            imageBase64 = image.data;
            imageMimeType = image.mimeType;
          } else {
            llmContent = result;
          }

          yield ChatLoopToolResult(
            toolCall.id,
            toolCall.name,
            result,
            imageBase64: imageBase64,
            imageMimeType: imageMimeType,
          );

          // Add tool result to history
          currentMessages.add(
            LlmMessage.toolResult(
              toolCallId: toolCall.id,
              toolName: toolCall.name,
              content: llmContent,
              imageBase64: imageBase64,
              imageMimeType: imageMimeType,
            ),
          );
        }

        // Loop continues — LLM needs to process tool results
        continue;
      }

      // No tool calls — final response
      final finalContent = response.content ?? '';
      currentMessages.add(LlmMessage.assistant(finalContent));
      yield ChatLoopAssistantMessage(
        finalContent,
        usage: LlmUsage(
          inputTokens: totalInputTokens,
          outputTokens: totalOutputTokens,
          cacheCreationInputTokens: totalCacheCreationInputTokens,
          cacheReadInputTokens: totalCacheReadInputTokens,
          peakInputTokens: peakInputTokens,
        ),
        isFinal: true,
        finalHistory: List.unmodifiable(currentMessages),
      );
      return;
    }

    yield ChatLoopError(
      'Reached maximum number of tool iterations ($_maxIterations). '
      'The assistant may need a simpler request.',
    );
  }
}

/// Returns a provider-safe copy containing only complete, adjacent tool groups.
///
/// A cancelled or partially restored conversation can contain a tool result
/// without its assistant call, or a call whose result was never recorded.
/// OpenAI-compatible providers reject orphan IDs, and retaining an incomplete
/// group is unsafe for Anthropic as well. Ordinary text remains intact while
/// unmatched calls/results are omitted from the request history.
List<LlmMessage> providerSafeToolHistory(List<LlmMessage> messages) {
  final safe = <LlmMessage>[];

  for (var index = 0; index < messages.length; index++) {
    final message = messages[index];
    if (message.role == LlmRole.tool) continue;

    final calls = message.role == LlmRole.assistant
        ? message.toolCalls ?? const <LlmToolCall>[]
        : const <LlmToolCall>[];
    if (calls.isEmpty) {
      safe.add(message);
      continue;
    }

    final callIds = calls.map((call) => call.id).toSet();
    final results = <LlmMessage>[];
    var nextIndex = index + 1;
    while (nextIndex < messages.length &&
        messages[nextIndex].role == LlmRole.tool) {
      results.add(messages[nextIndex]);
      nextIndex++;
    }

    final matchedIds = results
        .map((result) => result.toolCallId)
        .whereType<String>()
        .where(callIds.contains)
        .toSet();
    final matchedCalls = calls
        .where((call) => matchedIds.contains(call.id))
        .toList(growable: false);

    if (matchedCalls.isNotEmpty || (message.content?.isNotEmpty ?? false)) {
      safe.add(
        LlmMessage(
          role: LlmRole.assistant,
          content: message.content,
          toolCalls: matchedCalls.isEmpty ? null : matchedCalls,
        ),
      );
    }

    final emittedIds = <String>{};
    for (final result in results) {
      final id = result.toolCallId;
      if (id != null && matchedIds.contains(id) && emittedIds.add(id)) {
        safe.add(result);
      }
    }
    index = nextIndex - 1;
  }

  return safe;
}
