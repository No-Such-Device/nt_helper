import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nt_helper/chat/cubit/chat_state.dart';
import 'package:nt_helper/chat/models/chat_message.dart';
import 'package:nt_helper/chat/models/chat_settings.dart';
import 'package:nt_helper/chat/models/llm_types.dart';
import 'package:nt_helper/chat/providers/anthropic_provider.dart';
import 'package:nt_helper/chat/providers/anthropic_subscription_provider.dart';
import 'package:nt_helper/chat/providers/llm_provider.dart';
import 'package:nt_helper/chat/providers/openai_provider.dart';
import 'package:nt_helper/chat/providers/openai_subscription_provider.dart';
import 'package:nt_helper/chat/services/chat_service.dart';
import 'package:nt_helper/chat/services/memory_service.dart';
import 'package:nt_helper/chat/services/system_prompt.dart';
import 'package:nt_helper/chat/services/tool_bridge_service.dart';
import 'package:nt_helper/mcp/tool_registry.dart';
import 'package:uuid/uuid.dart';

typedef LlmProviderFactory = LlmProvider Function(ChatSettings settings);

class ChatCubit extends Cubit<ChatState> {
  final ToolRegistry _toolRegistry;
  final MemoryService _memoryService;
  final LlmProviderFactory? _providerFactory;
  StreamSubscription<dynamic>? _loopSubscription;
  LlmProvider? _activeProvider;
  Future<void>? _summarizationFuture;
  bool _compacting = false;

  // Accumulated LLM message history for the agentic loop
  final List<LlmMessage> _llmHistory = [];

  // Length of _llmHistory before the current loop started, used to restore
  // clean state if the loop is cancelled mid-execution.
  int _historyLengthBeforeLoop = 0;

  // Memory state
  bool _bootstrapped = false;
  String? _memoryContent;
  String? _dailyLogs;
  String? _activeSystemPrompt;
  String _promptCacheKey = const Uuid().v4();
  int _currentContextWindowTokens = LlmProvider.defaultContextWindowTokens;
  int _lastContextInputTokens = 0;
  bool _needsCompaction = false;

  static const _compactionThresholdPercent = 85;

  ChatCubit({
    required ToolRegistry toolRegistry,
    required MemoryService memoryService,
    @visibleForTesting LlmProviderFactory? providerFactory,
  }) : _toolRegistry = toolRegistry,
       _memoryService = memoryService,
       _providerFactory = providerFactory,
       super(const ChatReady());

  Future<void> sendMessage(
    String text,
    ChatSettings settings, {
    List<ChatImageAttachment> imageAttachments = const [],
    List<ChatFileAttachment> fileAttachments = const [],
  }) async {
    if (text.trim().isEmpty &&
        imageAttachments.isEmpty &&
        fileAttachments.isEmpty) {
      return;
    }

    final currentState = state;
    if (currentState is! ChatReady || currentState.isProcessing) return;

    // Handle /context command locally — no API call needed
    if (text.trim().toLowerCase() == '/context' &&
        imageAttachments.isEmpty &&
        fileAttachments.isEmpty) {
      _handleContextCommand(currentState);
      return;
    }

    if (!settings.hasApiKey) {
      emit(
        const ChatError(
          'No API key configured. Open chat settings to add one.',
        ),
      );
      return;
    }

    // Show processing state immediately
    final messageText = text.trim().isEmpty
        ? _defaultAttachmentMessage(imageAttachments, fileAttachments)
        : text.trim();
    final userMessage = ChatMessage.user(
      messageText,
      imageAttachments: imageAttachments,
      fileAttachments: fileAttachments,
    );
    final messages = [...currentState.messages, userMessage];
    emit(currentState.copyWith(messages: messages, isProcessing: true));

    try {
      final unsupportedFiles = _unsupportedFilesForProvider(
        settings.provider,
        fileAttachments,
      );
      if (unsupportedFiles.isNotEmpty) {
        emit(
          currentState.copyWith(
            messages: [
              ...messages,
              ChatMessage.assistant(
                _unsupportedAttachmentMessage(
                  settings.provider,
                  unsupportedFiles,
                ),
              ),
            ],
            isProcessing: false,
          ),
        );
        return;
      }

      // Bootstrap memory on first send
      if (!_bootstrapped) {
        _memoryContent = await _memoryService.readMemory();
        _dailyLogs = await _memoryService.readDailyLogs();
        _bootstrapped = true;
      }

      // Wait for any in-flight summarization before compaction/provider reset.
      if (_summarizationFuture != null) {
        await _summarizationFuture;
        _summarizationFuture = null;
      }

      await _resetActiveProvider(settings);
      _recomputeCompactionNeedForCurrentWindow();

      // Handle compaction if needed
      if (_needsCompaction) {
        await _performCompaction(settings);
      }

      // Add to LLM history
      _historyLengthBeforeLoop = _llmHistory.length;
      final llmImageAttachments = imageAttachments
          .map(
            (image) => LlmImageAttachment(
              data: image.data,
              mimeType: image.mimeType,
              name: image.name,
            ),
          )
          .toList();
      final llmFileAttachments = fileAttachments
          .map(
            (file) => LlmFileAttachment(
              name: file.name,
              data: file.data,
              mimeType: file.mimeType,
              sizeBytes: file.sizeBytes,
              textContent: file.textContent,
            ),
          )
          .toList();
      _llmHistory.add(
        LlmMessage.user(
          _messageWithFileAttachments(messageText, fileAttachments),
          imageAttachments: llmImageAttachments,
          fileAttachments: llmFileAttachments,
        ),
      );

      _activeProvider ??= _createProvider(settings);
      final toolBridge = ToolBridgeService(_toolRegistry);
      final chatService = ChatService(
        provider: _activeProvider!,
        toolBridge: toolBridge,
        systemPrompt: _systemPromptForSession,
      );

      // Run agentic loop
      await _loopSubscription?.cancel();
      _loopSubscription = chatService
          .runAgenticLoop(_llmHistory)
          .listen(
            _handleLoopEvent,
            onError: (Object error) {
              _truncateHistoryAfterCancellationPoint();
              final s = state;
              if (s is ChatReady) {
                emit(
                  s.copyWith(
                    messages: [
                      ...s.messages,
                      ChatMessage.assistant('Error: $error'),
                    ],
                    isProcessing: false,
                    clearToolName: true,
                  ),
                );
              }
            },
            onDone: () {
              final s = state;
              if (s is ChatReady && s.isProcessing) {
                _truncateHistoryAfterCancellationPoint();
                emit(s.copyWith(isProcessing: false, clearToolName: true));
              }
            },
          );
    } catch (e) {
      _truncateHistoryAfterCancellationPoint();
      final s = state;
      if (s is ChatReady) {
        emit(
          s.copyWith(
            messages: [...s.messages, ChatMessage.assistant('Error: $e')],
            isProcessing: false,
            clearToolName: true,
          ),
        );
      }
    }
  }

  String _defaultAttachmentMessage(
    List<ChatImageAttachment> imageAttachments,
    List<ChatFileAttachment> fileAttachments,
  ) {
    if (imageAttachments.isNotEmpty && fileAttachments.isNotEmpty) {
      return 'Attached images and files.';
    }
    if (imageAttachments.isNotEmpty) {
      return imageAttachments.length == 1
          ? 'Attached image.'
          : 'Attached images.';
    }
    return fileAttachments.length == 1 ? 'Attached file.' : 'Attached files.';
  }

  String _messageWithFileAttachments(
    String messageText,
    List<ChatFileAttachment> fileAttachments,
  ) {
    final buffer = StringBuffer(messageText);
    for (final file in fileAttachments) {
      if (file.textContent == null) continue;
      final content = _toolRegistry.storeReferenceIfLarge(
        toolName: 'attachment:${file.name}',
        result: file.textContent!,
      );
      buffer
        ..writeln()
        ..writeln()
        ..writeln(
          '--- Attached file: ${file.name} (${file.sizeBytes} bytes) ---',
        )
        ..writeln(content)
        ..writeln('--- End attached file: ${file.name} ---');
    }
    return buffer.toString();
  }

  List<ChatFileAttachment> _unsupportedFilesForProvider(
    LlmProviderType provider,
    List<ChatFileAttachment> fileAttachments,
  ) {
    return fileAttachments
        .where((file) => !_providerSupportsFileAttachment(provider, file))
        .toList();
  }

  bool _providerSupportsFileAttachment(
    LlmProviderType provider,
    ChatFileAttachment file,
  ) {
    if (file.textContent != null) return true;
    return switch (provider) {
      LlmProviderType.anthropic || LlmProviderType.anthropicSubscription =>
        file.mimeType == 'application/pdf',
      LlmProviderType.openaiSubscription => file.mimeType == 'application/pdf',
      LlmProviderType.openai => false,
    };
  }

  String _unsupportedAttachmentMessage(
    LlmProviderType provider,
    List<ChatFileAttachment> unsupportedFiles,
  ) {
    final names = unsupportedFiles.map((file) => file.name).join(', ');
    final providerName = switch (provider) {
      LlmProviderType.anthropic => 'Anthropic API',
      LlmProviderType.anthropicSubscription => 'Anthropic subscription',
      LlmProviderType.openai => 'OpenAI API',
      LlmProviderType.openaiSubscription => 'OpenAI subscription',
    };
    return 'Unsupported attachment for $providerName: $names. '
        'Use images, UTF-8 text/JSON files, or switch to a provider that '
        'supports this file type.';
  }

  void _handleLoopEvent(ChatLoopEvent event) {
    final currentState = state;
    if (currentState is! ChatReady) return;

    switch (event) {
      case ChatLoopThinking():
        break;
      case ChatLoopToolCall(toolCall: final tc):
        final msg = ChatMessage.toolCall(
          toolName: tc.name,
          toolCallId: tc.id,
          arguments: tc.arguments,
        );
        emit(
          currentState.copyWith(
            messages: [...currentState.messages, msg],
            currentToolName: tc.name,
          ),
        );
      case ChatLoopToolResult(
        toolCallId: final id,
        toolName: final name,
        result: final result,
        imageBase64: final imageBase64,
        imageMimeType: final imageMimeType,
      ):
        final msg = ChatMessage.toolResult(
          toolName: name,
          toolCallId: id,
          result: result,
          imageBase64: imageBase64,
          imageMimeType: imageMimeType,
        );
        emit(
          currentState.copyWith(
            messages: [...currentState.messages, msg],
            clearToolName: true,
          ),
        );
      case ChatLoopAssistantMessage(
        content: final content,
        usage: final usage,
        isFinal: final isFinal,
        finalHistory: final finalHistory,
      ):
        final uiMessages = content.isNotEmpty
            ? [...currentState.messages, ChatMessage.assistant(content)]
            : currentState.messages;
        final totalInput =
            currentState.totalInputTokens + (usage?.inputTokens ?? 0);
        final totalOutput =
            currentState.totalOutputTokens + (usage?.outputTokens ?? 0);
        final contextInput = usage?.contextInputTokens ?? totalInput;

        if (isFinal) {
          final newHistory = finalHistory ?? [LlmMessage.assistant(content)];
          _llmHistory.clear();
          _llmHistory.addAll(newHistory);
          _historyLengthBeforeLoop = _llmHistory.length;
          _lastContextInputTokens = contextInput;

          // Summarize large tool results in background
          _summarizationFuture = _summarizeLargeToolResults();

          // Check if compaction is needed
          final compactAt =
              _currentContextWindowTokens * _compactionThresholdPercent ~/ 100;
          _needsCompaction = contextInput > compactAt;
        }

        emit(
          currentState.copyWith(
            messages: uiMessages,
            isProcessing: isFinal ? false : null,
            clearToolName: isFinal,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            contextInputTokens: isFinal ? contextInput : null,
            contextWindowTokens: _currentContextWindowTokens,
          ),
        );
      case ChatLoopRateLimited(
        waitSeconds: final wait,
        attempt: final attempt,
        maxAttempts: final max,
      ):
        final msg = ChatMessage.system(
          'Rate limited by the API (attempt $attempt of $max). '
          'This happens when too many requests are made in a short period. '
          'Retrying in $wait seconds...',
        );
        emit(currentState.copyWith(messages: [...currentState.messages, msg]));
      case ChatLoopError(message: final message):
        _truncateHistoryAfterCancellationPoint();
        final msg = ChatMessage.assistant('Error: $message');
        emit(
          currentState.copyWith(
            messages: [...currentState.messages, msg],
            isProcessing: false,
            clearToolName: true,
          ),
        );
    }
  }

  String get _systemPromptForSession {
    return _activeSystemPrompt ??= distingNtSystemPrompt(
      memoryContent: _memoryContent,
      dailyLogs: _dailyLogs,
    );
  }

  Future<void> _resetActiveProvider(ChatSettings settings) async {
    _activeProvider?.dispose();
    _activeProvider = _createProvider(settings);
    _currentContextWindowTokens = await _resolveContextWindow(_activeProvider!);
    final currentState = state;
    if (currentState is ChatReady) {
      emit(
        currentState.copyWith(contextWindowTokens: _currentContextWindowTokens),
      );
    }
  }

  void _recomputeCompactionNeedForCurrentWindow() {
    if (_llmHistory.isEmpty || _lastContextInputTokens <= 0) {
      _needsCompaction = false;
      return;
    }
    final compactAt =
        _currentContextWindowTokens * _compactionThresholdPercent ~/ 100;
    _needsCompaction = _lastContextInputTokens > compactAt;
  }

  Future<void> _summarizeLargeToolResults() async {
    final provider = _activeProvider;
    if (provider == null) return;
    // Snapshot current length — do not iterate beyond it if new messages arrive.
    final snapshotLength = _llmHistory.length;

    for (int i = 0; i < snapshotLength && i < _llmHistory.length; i++) {
      final msg = _llmHistory[i];
      if (msg.role != LlmRole.tool) continue;
      final content = msg.content;
      if (content == null || content.length <= 4096) continue;

      final toolName = msg.toolName ?? 'unknown';
      final toolCallId = msg.toolCallId;
      if (toolCallId == null) continue;
      try {
        final response = await provider.sendMessages(
          messages: [
            LlmMessage.user(
              'Condense this $toolName result to key facts '
              '(names, IDs, values, bus assignments, errors). '
              'Omit empty/default entries and verbose structure. '
              'One paragraph max.\n\n$content',
            ),
          ],
          tools: [],
        );

        final summary = response.content;
        if (summary != null &&
            summary.isNotEmpty &&
            i < _llmHistory.length &&
            identical(_llmHistory[i], msg)) {
          _llmHistory[i] = LlmMessage.toolResult(
            toolCallId: toolCallId,
            toolName: toolName,
            content: summary,
          );
        }
      } catch (_) {
        // Best-effort: keep original on failure
      }
    }
  }

  Future<void> _performCompaction(ChatSettings settings) async {
    _compacting = true;

    // Save snapshot of current state
    await _memoryService.saveSessionSnapshot(_llmHistory);
    if (!_compacting) return;

    if (_activeProvider == null) {
      await _resetActiveProvider(settings);
    }

    final historyLengthBeforeCompaction = _llmHistory.length;

    // Inject compaction request
    _llmHistory.add(
      LlmMessage.user(
        '[SYSTEM: Context is large. Use memory_append_daily to save important '
        'session context before continuing.]',
      ),
    );

    // Run one agentic loop turn for the LLM to save context
    final toolBridge = ToolBridgeService(_toolRegistry);
    final chatService = ChatService(
      provider: _activeProvider!,
      toolBridge: toolBridge,
      systemPrompt: _systemPromptForSession,
    );

    final completer = Completer<void>();
    var completed = false;
    String? failure;
    final sub = chatService
        .runAgenticLoop(_llmHistory)
        .listen(
          (event) {
            if (event is ChatLoopAssistantMessage && event.isFinal) {
              completed = true;
              if (event.finalHistory != null) {
                _llmHistory.clear();
                _llmHistory.addAll(event.finalHistory!);
              }
            } else if (event is ChatLoopError) {
              failure = event.message;
            }
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          onError: (Object error) {
            failure = error.toString();
            if (!completer.isCompleted) completer.complete();
          },
        );

    await completer.future;
    await sub.cancel();
    if (!_compacting) return;

    if (!completed) {
      if (historyLengthBeforeCompaction <= _llmHistory.length) {
        _llmHistory.removeRange(
          historyLengthBeforeCompaction,
          _llmHistory.length,
        );
      }
      _needsCompaction = true;
      _compacting = false;
      throw StateError('Compaction failed: ${failure ?? 'no final response'}');
    }

    // Trim to ~last 10 messages, ensuring we start on a user message so that
    // tool/assistant ordering is valid for all providers.
    if (_llmHistory.length > 10) {
      var start = _llmHistory.length - 10;
      while (start < _llmHistory.length &&
          _llmHistory[start].role != LlmRole.user) {
        start++;
      }
      if (start < _llmHistory.length) {
        _llmHistory.removeRange(0, start);
      }
    }

    // Refresh daily logs since compaction may have appended
    _dailyLogs = await _memoryService.readDailyLogs();

    // Reset compaction state and token counters
    _needsCompaction = false;
    _compacting = false;
    _lastContextInputTokens = 0;

    // Add compaction notice to UI
    final currentState = state;
    if (currentState is ChatReady) {
      emit(
        currentState.copyWith(
          messages: [...currentState.messages, ChatMessage.compaction()],
          totalInputTokens: 0,
          totalOutputTokens: 0,
          contextInputTokens: 0,
          contextWindowTokens: _currentContextWindowTokens,
        ),
      );
    }
  }

  void _handleContextCommand(ChatReady currentState) {
    final contextDump = _serializeContext();
    final userMsg = ChatMessage.user('/context');
    final systemMsg = ChatMessage.system(contextDump);
    emit(
      currentState.copyWith(
        messages: [...currentState.messages, userMsg, systemMsg],
      ),
    );
  }

  String _serializeContext() {
    final buffer = StringBuffer();
    buffer.writeln('=== LLM Context (${_llmHistory.length} messages) ===');
    buffer.writeln();

    for (int i = 0; i < _llmHistory.length; i++) {
      final msg = _llmHistory[i];
      buffer.writeln(
        '--- Message ${i + 1}: ${msg.role.name.toUpperCase()} ---',
      );

      if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
        if (msg.content != null && msg.content!.isNotEmpty) {
          buffer.writeln('Text: ${msg.content}');
        }
        for (final tc in msg.toolCalls!) {
          buffer.writeln('Tool Call: ${tc.name} (id: ${tc.id})');
          buffer.writeln('Arguments: ${_prettyJson(tc.arguments)}');
        }
      } else if (msg.role == LlmRole.tool) {
        buffer.writeln('Tool: ${msg.toolName} (id: ${msg.toolCallId})');
        buffer.writeln('Result: ${_truncateToolResult(msg.content ?? '')}');
      } else {
        buffer.writeln(msg.content ?? '(empty)');
      }
      buffer.writeln();
    }

    buffer.writeln('=== End Context ===');
    return buffer.toString();
  }

  static String _prettyJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(json);
    } catch (_) {
      return json.toString();
    }
  }

  static String _truncateToolResult(String result) {
    if (result.length <= 2000) return result;
    return '${result.substring(0, 2000)}\n... (${result.length} chars total, truncated for display)';
  }

  Future<void> clearChat() async {
    await _loopSubscription?.cancel();
    _loopSubscription = null;
    _compacting = false;
    if (_summarizationFuture != null) {
      await _summarizationFuture;
      _summarizationFuture = null;
    }
    if (_llmHistory.isNotEmpty) {
      await _memoryService.saveSessionSnapshot(_llmHistory.toList());
    }
    _llmHistory.clear();
    _bootstrapped = false;
    _activeSystemPrompt = null;
    _promptCacheKey = const Uuid().v4();
    _needsCompaction = false;
    _lastContextInputTokens = 0;
    emit(const ChatReady());
  }

  Future<void> compactContext(ChatSettings settings) async {
    final currentState = state;
    if (currentState is! ChatReady ||
        currentState.isProcessing ||
        _llmHistory.isEmpty) {
      return;
    }

    if (!settings.hasApiKey) {
      emit(
        currentState.copyWith(
          messages: [
            ...currentState.messages,
            ChatMessage.system(
              'Configure a chat provider before compacting context.',
            ),
          ],
        ),
      );
      return;
    }

    emit(currentState.copyWith(isProcessing: true, clearToolName: true));
    try {
      if (!_bootstrapped) {
        _memoryContent = await _memoryService.readMemory();
        _dailyLogs = await _memoryService.readDailyLogs();
        _bootstrapped = true;
      }
      if (_summarizationFuture != null) {
        await _summarizationFuture;
        _summarizationFuture = null;
      }
      await _resetActiveProvider(settings);
      await _performCompaction(settings);
      final doneState = state;
      if (doneState is ChatReady) {
        emit(doneState.copyWith(isProcessing: false, clearToolName: true));
      }
    } catch (e) {
      _compacting = false;
      final errorState = state;
      if (errorState is ChatReady) {
        emit(
          errorState.copyWith(
            messages: [
              ...errorState.messages,
              ChatMessage.assistant('Error compacting context: $e'),
            ],
            isProcessing: false,
            clearToolName: true,
          ),
        );
      }
    }
  }

  void cancelProcessing() {
    _compacting = false;
    _loopSubscription?.cancel();
    _truncateHistoryAfterCancellationPoint();
    final currentState = state;
    if (currentState is ChatReady) {
      emit(currentState.copyWith(isProcessing: false, clearToolName: true));
    }
  }

  void dismissError() {
    _llmHistory.clear();
    _bootstrapped = false;
    _activeSystemPrompt = null;
    _promptCacheKey = const Uuid().v4();
    _needsCompaction = false;
    _lastContextInputTokens = 0;
    emit(const ChatReady());
  }

  ChatContextSummary get contextSummary {
    var userMessages = 0;
    var assistantMessages = 0;
    var toolCalls = 0;
    var toolResults = 0;
    var imageAttachments = 0;
    var fileAttachments = 0;
    var approxCharacters = 0;

    for (final message in _llmHistory) {
      approxCharacters += message.content?.length ?? 0;
      imageAttachments += message.imageAttachments.length;
      fileAttachments += message.fileAttachments.length;
      if (message.hasImage) imageAttachments++;
      switch (message.role) {
        case LlmRole.user:
          userMessages++;
        case LlmRole.assistant:
          assistantMessages++;
          toolCalls += message.toolCalls?.length ?? 0;
        case LlmRole.tool:
          toolResults++;
      }
    }

    return ChatContextSummary(
      messageCount: _llmHistory.length,
      userMessages: userMessages,
      assistantMessages: assistantMessages,
      toolCalls: toolCalls,
      toolResults: toolResults,
      imageAttachments: imageAttachments,
      fileAttachments: fileAttachments,
      approxCharacters: approxCharacters,
    );
  }

  LlmProvider _createProvider(ChatSettings settings) {
    if (_providerFactory != null) return _providerFactory(settings);
    switch (settings.provider) {
      case LlmProviderType.anthropic:
        return AnthropicProvider(
          apiKey: settings.anthropicApiKey!,
          model: settings.anthropicModel,
        );
      case LlmProviderType.anthropicSubscription:
        return AnthropicSubscriptionProvider(
          token: settings.anthropicApiKey!,
          model: settings.anthropicModel,
        );
      case LlmProviderType.openai:
        return OpenAIProvider(
          apiKey: settings.openaiApiKey!,
          model: settings.openaiModel,
          baseUrl: settings.openaiBaseUrl,
          promptCacheKey: _promptCacheKey,
        );
      case LlmProviderType.openaiSubscription:
        return OpenAISubscriptionProvider(
          model: settings.openaiSubscriptionModel,
          allowAuthRefresh: settings.allowCodexAuthRefresh,
          promptCacheKey: _promptCacheKey,
        );
    }
  }

  Future<int> _resolveContextWindow(LlmProvider provider) async {
    try {
      final resolved = await provider.resolveContextWindowTokens();
      if (resolved != null && resolved > 0) return resolved;
    } on Object {
      // Context-window metadata is advisory. Keep chat usable if metadata
      // lookup fails or a test double does not implement it.
    }
    return LlmProvider.defaultContextWindowTokens;
  }

  @override
  Future<void> close() async {
    await _loopSubscription?.cancel();
    _compacting = false;
    if (_summarizationFuture != null) {
      await _summarizationFuture;
      _summarizationFuture = null;
    }
    if (_llmHistory.isNotEmpty) {
      await _memoryService.saveSessionSnapshot(_llmHistory.toList());
    }
    _activeProvider?.dispose();
    return super.close();
  }

  void _truncateHistoryAfterCancellationPoint() {
    if (_historyLengthBeforeLoop <= _llmHistory.length) {
      _llmHistory.removeRange(_historyLengthBeforeLoop, _llmHistory.length);
      return;
    }
    _llmHistory.clear();
  }
}
