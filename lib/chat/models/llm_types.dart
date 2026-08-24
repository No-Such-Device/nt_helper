// Types for LLM provider abstraction.
//
// These types are provider-neutral — both Anthropic and OpenAI providers
// convert to/from these types.

enum LlmRole { user, assistant, tool }

class LlmImageAttachment {
  final String data;
  final String mimeType;
  final String? name;

  const LlmImageAttachment({
    required this.data,
    required this.mimeType,
    this.name,
  });
}

class LlmFileAttachment {
  final String name;
  final String data;
  final String mimeType;
  final int sizeBytes;
  final String? textContent;

  const LlmFileAttachment({
    required this.name,
    required this.data,
    required this.mimeType,
    required this.sizeBytes,
    this.textContent,
  });
}

/// A message in the LLM conversation.
class LlmMessage {
  final LlmRole role;
  final String? content;
  final List<LlmToolCall>? toolCalls;
  final String? toolCallId;
  final String? toolName;
  final String? imageBase64;
  final String? imageMimeType;
  final List<LlmImageAttachment> imageAttachments;
  final List<LlmFileAttachment> fileAttachments;

  const LlmMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
    this.imageBase64,
    this.imageMimeType,
    this.imageAttachments = const [],
    this.fileAttachments = const [],
  });

  bool get hasImage => imageBase64 != null && imageMimeType != null;
  bool get hasImageAttachments => imageAttachments.isNotEmpty;
  bool get hasFileAttachments => fileAttachments.isNotEmpty;

  factory LlmMessage.user(
    String content, {
    List<LlmImageAttachment> imageAttachments = const [],
    List<LlmFileAttachment> fileAttachments = const [],
  }) => LlmMessage(
    role: LlmRole.user,
    content: content,
    imageAttachments: imageAttachments,
    fileAttachments: fileAttachments,
  );

  factory LlmMessage.assistant(String content) =>
      LlmMessage(role: LlmRole.assistant, content: content);

  factory LlmMessage.assistantWithToolCalls(
    List<LlmToolCall> toolCalls, {
    String? content,
  }) => LlmMessage(
    role: LlmRole.assistant,
    content: content,
    toolCalls: toolCalls,
  );

  factory LlmMessage.toolResult({
    required String toolCallId,
    required String toolName,
    required String content,
    String? imageBase64,
    String? imageMimeType,
  }) => LlmMessage(
    role: LlmRole.tool,
    content: content,
    toolCallId: toolCallId,
    toolName: toolName,
    imageBase64: imageBase64,
    imageMimeType: imageMimeType,
  );
}

/// A tool call requested by the LLM.
class LlmToolCall {
  final String id;
  final String name;
  final String? namespace;
  final Map<String, dynamic> arguments;

  const LlmToolCall({
    required this.id,
    required this.name,
    this.namespace,
    required this.arguments,
  });
}

/// A tool definition sent to the LLM.
class LlmToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const LlmToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

/// Response from an LLM provider.
class LlmResponse {
  final String? content;
  final List<LlmToolCall> toolCalls;
  final bool isComplete;
  final LlmUsage? usage;

  const LlmResponse({
    this.content,
    this.toolCalls = const [],
    required this.isComplete,
    this.usage,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Token usage information.
class LlmUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;
  final int? peakInputTokens;

  const LlmUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.peakInputTokens,
  });

  int get totalTokens => inputTokens + outputTokens;
  int get contextInputTokens =>
      peakInputTokens ??
      inputTokens + cacheCreationInputTokens + cacheReadInputTokens;
}
