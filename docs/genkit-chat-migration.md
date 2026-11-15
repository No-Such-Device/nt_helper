# Genkit Dart migration assessment for nt_helper

2026-10-17. Initial assessment followed by implementation and hands-on testing
in the migration worktree, then integration into `main` for release 2.59.0.

## Implemented: `feat/genkit-chat-migration`

Worktree: `/Users/nealsanche/nosuch/nt_helper-worktrees/genkit-chat-migration`.
This worktree includes the earlier remote-control corrections and instructions.

- Genkit **1.0.0** now owns each chat run's model/tool loop and active transcript.
  `ChatService` is the compatibility/event boundary, not a second agent loop.
  Completed snapshots return to the Cubit for its existing memory/context UI.
- Custom Genkit model adapters retain all four existing provider/authentication
  contracts. No provider account, key, subscription token, endpoint, or model is
  silently replaced by a Google service or by a different model.
- Settings now also exposes Google Gemini, OpenRouter and local/OpenAI-compatible
  servers as explicit choices with independent profiles. These use the common
  compatible transport under Genkit, preserve scoped reasoning/signature metadata
  in history and never borrow subscription or other providers' credentials.
  See `chat-providers.md` for setup and remaining live-validation limits.
- All four transports support real text deltas and abortable HTTP requests,
  including Codex Responses Lite. The older buffered entry point remains for
  existing single-request/context operations, not for the main chat loop.
- Native registry callbacks preserve schemas, tool IDs/namespaces, large-result
  references and actual multipart images. No loopback HTTP is used in production
  chat; the external MCP server remains independent.
- Streaming updates one stable assistant bubble, with near-bottom scroll
  following. Old turn callbacks cannot write into a newer turn.
- Stop cancels the model token immediately; later sends wait for the preceding
  cleanup. Failed/cancelled turns retain facts from completed tool groups without
  automatically replaying writes. Remote gesture authority/deadlines are retained.
- Removed background model calls that silently summarized and replaced large
  tool results. Payload references and the explicit existing compaction/memory
  policy remain; compaction itself now also runs through Genkit.
- MCP/chat `show_screen` now uses the UI's `getHardwareScreenshot()` helper,
  which sends the dedicated SysEx **Wake** command before capture. The former MCP
  path bypassed Wake and could capture the black screensaver. It still does not
  switch display mode. The old optional `display_mode` argument was removed;
  explicit view changes use a separate `set_display_mode` tool, and menu
  navigation uses `remote_control` only.

### Validation

- `flutter analyze --no-pub`: no issues.
- Release full `flutter test --no-pub --concurrency=1`: **4,164 passed**,
  with two opt-in widget-capture tests skipped. The real provider/hardware smoke
  lives outside `test/`, so release-test discovery does not compile or run it.
- `flutter build macos --debug --no-pub`: succeeded. Existing native plugin and
  out-of-date local iOS simulator warnings remain; no iOS build was attempted.
- Additional opt-in live smoke passed with **real Codex subscription auth**, the
  migrated Genkit loop, and read-only MCP tools on the existing running app:
  `remote_state → show_preset → show_screen → streamed answer`. It observed Init
  with zero slots and correctly described a black screen. The running app was
  the older build, so this smoke did not exercise the new wake-before-capture
  handler; dedicated MCP/chat regression checks verify that handler awaits Wake
  before requesting the screenshot and does not set a display mode.
- Streaming/cancellation checks include an actual loopback HTTP server, not just
  buffered mock responses. Other provider authentication paths were covered by
  fixtures, not live account requests.

Opt-in smoke (spends provider quota, reads hardware, sends no gestures/settings):

```sh
flutter test --no-pub --dart-define=NT_GENKIT_LIVE=true \
  hardware_test/genkit_chat_live_smoke_test.dart
```

The hardware/provider smoke lives outside the release suite and requires an
explicit path plus `NT_GENKIT_LIVE=true`. No release workflow was expanded. The
small default regressions use scripted models/transports or a local HTTP socket;
they do not call provider APIs or hardware, launch an app, or run builds.

The smoke discovers an available account model unless `NT_GENKIT_MODEL` is set.
A real discovery during validation: the old hardcoded `gpt-5.4-mini` choice was
rejected by this ChatGPT account. Production preserves the user's configured
model; an unsupported-model response now explicitly directs them to select a
model from the current subscription list in Chat settings. It does not silently
substitute a model or rewrite settings.

### Local conversation history

- The synchronized screen injects `FileConversationStore` into its chat Cubit.
  Startup restores the active conversation passively, without creating a provider
  or calling tools. New chat archives the previous conversation; the header's
  history button opens the searchable, recent-first picker.
- Versioned local checkpoints include Genkit `SessionState` message JSON, UI
  message IDs/timestamps, attachments, tool IDs/namespaces, usage/cache metadata
  and the large-result reference payloads. System prompts are rebuilt using the
  current app instructions and semantic memory on the next explicit send.
- Storage: `<application support>/chat_conversations/`, with a conversation JSON
  file, small metadata sidecar and active pointer. Writes replace via temporary
  file/rename and are serialized, including overlapping store instances during
  screen teardown. Empty active drafts are retained but omitted from the picker.
- Checkpoints are written at submission, tool-result boundaries, completed turns,
  cancellation/cleanup and close—not for every streamed token. Pending restore
  cannot start a send after Stop/close. Old final saves do not reactivate a chat
  over a newly selected conversation.
- Interrupted runs restore idle with an explicit warning. Known receipts remain
  facts; unmatched visual tool cards report unknown delivery, never fake success.
  Extra recovered receipts are historical context, not tool requests to replay.
- Save/read failures are visible. Failed saves prevent New chat from silently
  discarding the visible conversation. Corrupt/unsupported records are kept;
  recovery requires choosing another chat or explicitly starting a new one.
- Content remains on this device as ordinary app-support JSON, not an encrypted
  vault. Attachments/references are retained until that saved conversation is
  deleted; there is no automatic expiry or storage cap. Credential/settings
  objects are not serialized, but anything pasted into chat is still chat content.
- Clear chat and confirmed picker deletion remove the saved conversation. Existing
  semantic memory, daily logs and separate Markdown snapshots are distinct and
  explicitly noted as retained in confirmation copy. There is no automatic import
  of old text snapshots as full sessions.

This is a client-managed checkpoint repository carrying Genkit's session schema,
not Genkit `FileSessionStore`/task adoption. There is **no** background generation,
process-restart task resume, automatic command replay, or durable hardware hold.

Persistence/picker validation: **54 focused checks passed across bounded runs**,
including the opt-in widget capture; analyzer clean. This covers file/attachment
round trips, references, conversation isolation, corruption, failed writes,
shutdown/restore races, keyboard search, error recovery, enlarged/RTL text,
keyboard insets and existing streaming/remote cleanup regressions. No further
full-suite, provider-account or hardware runs were added.

See `chat-conversation-picker-review.md` for the Impeccable audit and native-widget
render evidence. Live user validation and Claude subscription/API-key checks
remain deployment verification steps.

## Original assessment / design rationale

## Recommendation

Proceed with a staged **in-process Genkit Dart** backend. Keep the current
Flutter UI, ToolRegistry, MCP server, memory/file services and authentication
services initially. Replace the custom agent loop and duplicate transcript
ownership before redesigning the UI. Genkit is Google's framework but does not
require Gemini, Firebase, a Google account, a hosted backend, Node or its CLI to
run locally. Provider plugins/adapters determine the model connection.

Pin `genkit: 1.0.0` for an initial integration: the core is 1.0, but the agent APIs
are explicitly experimental and can change without a major version bump. Keep
those imports behind the chat runtime boundary rather than throughout widgets.

This is a moderate chat-backend refactor, not a one-dependency fix. It will not by
itself repair layout, accessibility, authentication or hardware safety.

## Verified feasibility

### Dependency compatibility

A temporary copy of nt_helper's complete pubspec and lockfile successfully ran
`flutter pub get` after adding `genkit: 1.0.0`. Eight dependency changes were
reported; no dependency edits were made in the real checkout. This check covered
the core package, not every provider plugin or all release targets.

Genkit 1.0.0 requires Dart ^3.12.0. This feasibility check used Dart 3.12.2
and Flutter 3.44.9; the project's old declared Dart floor (>=3.8.1) did not
reflect that requirement. The [current toolchain](flutter-3.50-upgrade.md) now
pins Flutter 3.50.0 / Dart 3.14.0 and declares matching SDK minimums.

### Native, local runtime probe

An isolated program in `/tmp/nt-genkit-investigation` used the actual published
Genkit 1.0.0, with `isDevEnv: false` and no prompt directory. It was run as Dart,
then AOT-compiled with `dart compile exe` and run as a standalone macOS ARM64
executable. Both runs completed:

1. Scripted model requested simulated `remote_state`.
2. Genkit executed it and returned the result to the model.
3. The model requested simulated `show_screen`.
4. Its multipart PNG payload reached the next model request.
5. The final answer arrived through the streaming interface.
6. A new chat handle loaded the saved session from InMemorySessionStore and
   retained both turns' message history.
7. Cancellation reached a deliberately blocked tool through `ctx.cancel`, and
   the turn finished as `aborted`.

The model and tools were synthetic. This proves the local agent loop, multipart
transport, streaming API, in-memory reattachment and cooperative cancellation,
**not** live provider vision, hardware control, file-store crash recovery,
Flutter release integration or subscription compatibility. The executable was
about 6.9 MiB; that is a whole small standalone Dart program, **not** a measured
size increase for nt_helper.

## Current architecture and migration seams

| Existing area | Current responsibility | Migration |
|---|---|---|
| `lib/chat/services/chat_service.dart` | 100-iteration model/tool loop, rate-limit retry, usage accumulation, provider-safe history repair | Replace loop with Genkit agent/generate machinery and a thin event adapter. Preserve explicit turn bounds and retry policy. |
| `lib/chat/cubit/chat_cubit.dart` | UI state plus `_llmHistory`, provider lifetime, cancellation, compaction, memory bootstrap | Reduce to UI projection and runtime commands. Genkit owns the authoritative conversation; avoid two independently mutable histories. |
| `lib/chat/services/tool_bridge_service.dart` | Registry-to-LLM tool definitions and dispatch | Adapt registry entries to Genkit Tools, forwarding exact schemas and callbacks. |
| `lib/mcp/tool_registry.dart` | Shared tool authority, references, permissions, per-caller gesture cleanup | Keep. Chat calls it in-process; external MCP remains unchanged. |
| `lib/chat/providers/*` | API transports and subscription-specific authentication/conversion | Use standard plugins for API-key paths where compatible; custom model actions for existing subscription paths. |
| `lib/chat/services/system_prompt.dart` | NT instructions and session memory | Keep as the agent system prompt, stable for the session. |
| `lib/chat/services/memory_service.dart` | Durable notes/logs and Markdown snapshots | Keep notes/logs; add a real Genkit SessionStore for conversation resume. Markdown snapshots currently save only recent text and are not a full tool transcript. |
| `lib/chat/ui/*`, chat message/state models | Rendering, attachments, settings, speech input, tool cards | Keep initially; feed deltas and explicit terminal outcomes from the new runtime. |

### A concrete weakness in the current backend

`LlmProvider.sendMessages` returns `Future<LlmResponse>`, not an event stream.
`ChatService` waits for that response before emitting assistant text. Even the
Codex provider parses an SSE response into one eventual result. Consequently,
the current architecture cannot expose live text deltas through that interface.

Genkit's `sendStream()` can carry live deltas, but wrapping this existing Future
API as a custom Genkit model would still buffer. That wrapper is a useful
compatibility phase, not a finished streaming migration. Existing symptoms have
not all been diagnosed; this is a source-confirmed architectural limitation, not
proof of the cause of every reported chat failure.

## Design details that matter

### Tool adapter

Use existing entry names, descriptions and JSON schemas. `SchemanticType.from`
accepts a raw schema plus parse/serialize functions, so migrating the registry
need not mean hand-rewriting every schema. Verify constraints such as oneOf and
additionalProperties survive provider conversion and are enforced at execution.

Ordinary JSON/text results become `ToolResult.response(...)`. Decode existing
image results using `tryParseImageResult` and return image `MediaPart`s alongside
structured metadata. A JSON string containing base64 is not a substitute for
model-visible image content. Preserve large-result references and chat-only file
root/memory behavior; do not route chat through its own HTTP MCP endpoint.

Genkit 1.0.0 executes requested tools sequentially in the inspected core loop.
Still serialize chat submissions and enforce the existing remote-session
ownership. Sequential calls within one turn do not prevent competing turns or
another MCP client from acting.

### Recoverable errors versus failed turns

The current registry generally returns `{success:false,error:...}`. Genkit can
pass that through as an ordinary tool response, allowing the model to correct its
arguments. By contrast, an uncaught tool exception fails the Genkit turn rather
than automatically returning the error to the model. Decide this boundary
explicitly: preserve expected tool validation errors as results, surface genuine
runtime/transport failures clearly, and propagate cancellation as cancellation.

### Cancellation and hardware

Genkit cancellation is cooperative. Connect the turn token to provider request
cancellation and ToolRegistry remote cleanup; wait for cleanup on stop/close.
Invalidate callbacks for the old turn before accepting a replacement. Cancelling
a UI stream alone does not establish that an HTTP request or device command
stopped. Genkit cannot cancel an already executed physical action.

Continue using the existing remote delegate's bounded gesture and release logic.
No automatic retry/restart of uncertain hardware gestures. An interrupted run
should inspect live state/screen, then ask or replan. An unknown release remains
unknown, regardless of the agent's terminal state.

### Authentication is the largest compatibility item

Current modes are Anthropic API key, Claude subscription token, OpenAI-compatible
API key/custom base URL, and Codex subscription.

- Standard `genkit_openai` / `genkit_anthropic` plugins are candidates for API-key
  modes. Verify custom base URLs, model metadata and image results.
- Claude subscription currently uses bearer authentication, beta headers and
  endpoint-specific prompt behavior. It is not just an Anthropic API key.
- Codex subscription uses `CodexAuthService`, optional token refresh, client
  version/model metadata, account headers, Responses/Responses Lite shapes,
  prompt-cache identity and custom SSE handling. Preserve these requirements in
  a custom `defineModel` action; selecting a standard OpenAI plugin does not
  establish compatibility.
- Keep credentials on the local device and out of session snapshots, traces and
  model-visible context. Respect the supported authentication conditions of each
  provider; migration does not make a private/subscription API a public contract.

A transitional custom model may call the current providers, but the final model
adapter must expose deltas and cancellation instead of permanently retaining the
buffered Future interface.

### Sessions, memory and context budget

Use one Genkit AgentChat as the transcript authority. Project its messages and
streamed deltas into ChatCubit; include tool IDs, image content and usage.
`AgentTurn.response`/finish reason is the completion boundary, not stream closure
alone. Always settle processing/error/cancel UI state explicitly.

InMemorySessionStore is sufficient for initial adoption. For real restart/resume,
use FileSessionStore in app support storage or a SessionStore backed by the
existing database. Never put credentials in persisted messages. Add an explicit
retention policy for screen captures and attachments. Avoid enabling background
work or resuming hardware actions implicitly.

Session snapshots do not imply Pi Durable-style task checkpoints, nor do they
remove the need for context budgeting. Move the existing compaction policy out of
the Cubit into a runtime/middleware service and validate it against Genkit's full
messages/tool groups. Do not keep the old history-truncation code mutating the
Genkit transcript behind its back. Preserve stable prompt and provider cache
identity semantics.

### UI and observability

Use `AgentChunk.text`/reasoning and tool middleware to produce stable tool cards,
progress, results and explicit terminal state. Genkit does not supply a finished
Flutter chat interface. Keep existing semantics/focus handling and reserve layout
space for status changes. Retain useful diagnostics without logging keys, tokens,
full raw screenshots or private attachment content.

Disable development reflection (`isDevEnv: false`, no prompt discovery) in
production. Dev tooling is optional and separate from the native runtime. Review
trace export configuration before using real credentials/device content.

## Suggested delivery sequence

1. **Backend seam:** introduce a narrow ChatRuntime interface for send/stream,
   stop, clear, context inspection and close. Give a conversation one owner.
2. **Read-only vertical slice:** Genkit local agent, stable NT prompt, and direct
   ToolRegistry adapters for `remote_state`, `show_screen`, `show_preset` and
   references. Use a real supported provider and show actual streamed text and
   screenshot-informed answers in Flutter, without changing the preset.
3. **Provider parity:** API-key plugins plus Codex/Claude subscription model
   adapters. Preserve settings, model selection, custom endpoints, refresh and
   cache identity. Keep the legacy backend only as a temporary selectable
   fallback; do not silently switch between two histories mid-conversation.
4. **Cancellation and mutations:** wire tokens through providers/tools, await
   bounded cleanup, gate destructive actions, and ensure no uncertain replay.
5. **Sessions and context:** real persistence, attachments, memory, usage and
   compaction. Exercise failed/aborted turn recovery and model changes.
6. **Cutover:** switch the UI to the new backend once parity is observed; remove
   the old loop and obsolete conversion/history code rather than maintaining two
   complete harnesses. Validate release builds on all supported platforms.

Before starting production implementation, consult the official Genkit Dart
Agent Skill linked by the project README, and pin the API version used.

## Acceptance evidence before cutover

- Live read-only NT conversation completes a state → screen → answer chain;
  the response is actually grounded in the screenshot.
- Text streams while the provider is still responding; tool cards settle once.
- Cancellation during provider work, waits and held gestures returns to usable
  UI state, releases through the original transport where possible and sends no
  later queued mutation.
- Both subscription modes work through their real authentication paths; no API
  key is substituted and no secret is logged.
- Invalid arguments and provider failures produce useful recoverable feedback,
  not a permanent spinner or orphaned tool history.
- Session reattachment/restart retains valid message/tool associations without
  replaying hardware writes; large references and image attachments survive.
- Clear/close, context compaction, changing model/provider, and retry behavior
  have explicit transcript and cleanup ownership.

## Sources

- [Genkit Dart agents](https://genkit.dev/docs/dart/agents/overview/)
- [Agent run/stream lifecycle](https://genkit.dev/docs/dart/agents/run/)
- [Tool calling and failure semantics](https://genkit.dev/docs/dart/tool-calling/)
- [Genkit Dart repository and official skill pointer](https://github.com/genkit-ai/genkit-dart)
- [Published genkit 1.0.0](https://pub.dev/packages/genkit/versions/1.0.0)
- Published source inspected: `lib/src/experimental/agent_veneer.dart`,
  `lib/src/ai/agents/agent_core.dart`, `lib/src/ai/generate.dart`,
  `lib/src/ai/tool.dart`, `lib/src/core/cancellation.dart`, and upstream agent
  examples/tests. Experimental imports and multipart tool response support were
  verified in the released archive.
- nt_helper source paths above were inspected directly; Graphify was used for
  orientation, not treated as current implementation truth.
