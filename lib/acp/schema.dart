/// ACP's messages as M0 and M1 read and write them: typed views over the
/// decoded JSON maps, so unknown kinds, values and fields are kept as they
/// came. A view is read-only outside this library; a kind is dispatched on
/// its string, never by a type test, since the views are erased at run time,
/// and a field of the wrong type throws a [TypeError] where it is read; but
/// an agent's `initialize` answer, which the original reads raw through
/// optional chaining, reads a capability of the wrong type as absent.
///
/// The names and fields are `@agentclientprotocol/sdk` 2.6.0's schema
/// (`schema.unstable.json`), as the original pins it.
library;

Map<String, Object?>? _map(Object? value) => value as Map<String, Object?>?;

/// [value] when it is an object, else nothing: how the original's optional
/// chaining reads a raw `initialize` answer, a part of the wrong type
/// absent rather than an error, as the SDK parses no answer of an agent's.
Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// Whether [value] is truthy as JavaScript reads it, as the original tests
/// an agent's advertised capabilities: not null, false, 0, NaN or ''.
bool jsTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  final num number => number != 0 && !number.isNaN,
  _ => true,
};

List<T>? _list<T>(Object? value, T Function(Map<String, Object?> json) view) =>
    (value as List<Object?>?)
        ?.map((each) => view(each as Map<String, Object?>))
        .toList();

/// The protocol version chord speaks: ACP v1.
const protocolVersion = 1;

/// `initialize`'s request: what chord speaks and declares.
extension type const InitializeRequest._(Map<String, Object?> _json) {
  /// The request chord sends.
  InitializeRequest({
    required int protocolVersion,
    required ClientCapabilities clientCapabilities,
    Implementation? clientInfo,
  }) : _json = {
         'protocolVersion': protocolVersion,
         'clientCapabilities': clientCapabilities.toJson(),
         if (clientInfo != null) 'clientInfo': clientInfo.toJson(),
       };

  /// A view over a decoded request.
  InitializeRequest.fromJson(Map<String, Object?> json) : _json = json;

  int get protocolVersion => _json['protocolVersion'] as int;
  ClientCapabilities get clientCapabilities => ClientCapabilities.fromJson(
    _json['clientCapabilities'] as Map<String, Object?>,
  );
  Implementation? get clientInfo =>
      _map(_json['clientInfo']).let(Implementation.fromJson);
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// `initialize`'s answer: the version the agent picked, what it offers, how
/// it signs in, and who it is; `_meta` included.
extension type const InitializeResponse._(Map<String, Object?> _json) {
  /// A view over a decoded answer.
  InitializeResponse.fromJson(Map<String, Object?> json) : _json = json;

  /// The version the agent answered; kept, not acted on, as the original.
  int get protocolVersion => _json['protocolVersion'] as int;
  AgentCapabilities? get agentCapabilities =>
      _object(_json['agentCapabilities']).let(AgentCapabilities.fromJson);
  List<AuthMethod>? get authMethods =>
      _list(_json['authMethods'], AuthMethod.fromJson);
  Implementation? get agentInfo =>
      _object(_json['agentInfo']).let(Implementation.fromJson);
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// What chord tells an agent it can do; nothing in M0 and M1.
extension type const ClientCapabilities._(Map<String, Object?> _json) {
  /// Capabilities with nothing declared.
  ClientCapabilities() : _json = {};

  /// A view over decoded capabilities.
  ClientCapabilities.fromJson(Map<String, Object?> json) : _json = json;

  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// What an agent offers.
extension type const AgentCapabilities._(Map<String, Object?> _json) {
  /// A view over decoded capabilities.
  AgentCapabilities.fromJson(Map<String, Object?> json) : _json = json;

  bool get loadSession => jsTruthy(_json['loadSession']);
  PromptCapabilities? get promptCapabilities =>
      _object(_json['promptCapabilities']).let(PromptCapabilities.fromJson);
  Map<String, Object?>? get mcpCapabilities =>
      _object(_json['mcpCapabilities']);
  Map<String, Object?>? get sessionCapabilities =>
      _object(_json['sessionCapabilities']);
  Map<String, Object?>? get meta => _object(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// The kinds of content a prompt may hold beyond text.
extension type const PromptCapabilities._(Map<String, Object?> _json) {
  /// A view over decoded capabilities.
  PromptCapabilities.fromJson(Map<String, Object?> json) : _json = json;

  bool get image => _json['image'] == true;
  bool get audio => _json['audio'] == true;
  bool get embeddedContext => _json['embeddedContext'] == true;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// A program's name and version, chord's or an agent's.
extension type const Implementation._(Map<String, Object?> _json) {
  /// [name] at [version], with a [title] to show.
  Implementation({required String name, required String version, String? title})
    : _json = {'name': name, 'version': version, 'title': ?title};

  /// A view over a decoded implementation.
  Implementation.fromJson(Map<String, Object?> json) : _json = json;

  String get name => _json['name'] as String;
  String get version => _json['version'] as String;
  String? get title => _json['title'] as String?;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// One way an agent lets a person sign in.
extension type const AuthMethod._(Map<String, Object?> _json) {
  /// A view over a decoded method.
  AuthMethod.fromJson(Map<String, Object?> json) : _json = json;

  String get id => _json['id'] as String;
  String get name => _json['name'] as String;
  String? get description => _json['description'] as String?;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// `session/new`'s request.
extension type const NewSessionRequest._(Map<String, Object?> _json) {
  /// A session in [cwd] with [mcpServers], opening on [configOptions]
  /// where the agent takes initial values.
  NewSessionRequest({
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
    List<Map<String, Object?>> configOptions = const [],
    Map<String, Object?>? meta,
  }) : _json = {
         'cwd': cwd,
         'mcpServers': mcpServers,
         if (configOptions.isNotEmpty) 'configOptions': configOptions,
         '_meta': ?meta,
       };

  /// A view over a decoded request.
  NewSessionRequest.fromJson(Map<String, Object?> json) : _json = json;

  String get cwd => _json['cwd'] as String;
  List<Object?> get mcpServers => _json['mcpServers'] as List<Object?>;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// Settings shared by new, load and resume answers; reopening returns no id.
extension type const SessionResponse._(Map<String, Object?> _json) {
  SessionResponse.fromJson(Map<String, Object?> json) : _json = json;
  Map<String, Object?>? get modes => _map(_json['modes']);
  List<Object?>? get configOptions => _json['configOptions'] as List<Object?>?;
  Map<String, Object?>? get meta => _map(_json['_meta']);
  Map<String, Object?> toJson() => _json;
}

/// Load and resume carry the requested literal id, cwd and current MCP policy.
extension type const ReopenSessionRequest._(Map<String, Object?> _json) {
  ReopenSessionRequest({
    required String sessionId,
    required String cwd,
    required List<Map<String, Object?>> mcpServers,
    Map<String, Object?>? meta,
  }) : _json = {
         'sessionId': sessionId,
         'cwd': cwd,
         'mcpServers': mcpServers,
         '_meta': ?meta,
       };
  ReopenSessionRequest.fromJson(Map<String, Object?> json) : _json = json;
  String get sessionId => _json['sessionId'] as String;
  String get cwd => _json['cwd'] as String;
  List<Object?> get mcpServers => _json['mcpServers'] as List<Object?>;
  Map<String, Object?> toJson() => _json;
}

/// `session/new` alone supplies a new id.
extension type const NewSessionResponse._(Map<String, Object?> _json)
    implements SessionResponse {
  /// A view over a decoded answer.
  NewSessionResponse.fromJson(Map<String, Object?> json) : _json = json;

  String get sessionId => _json['sessionId'] as String;
  Map<String, Object?>? get modes => _map(_json['modes']);
  List<Object?>? get configOptions => _json['configOptions'] as List<Object?>?;
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// `session/prompt`'s request: a turn's prompt.
extension type const PromptRequest._(Map<String, Object?> _json) {
  /// [prompt] for session [sessionId].
  PromptRequest({required String sessionId, required List<ContentBlock> prompt})
    : _json = {
        'sessionId': sessionId,
        'prompt': [for (final block in prompt) block.toJson()],
      };

  /// A view over a decoded request.
  PromptRequest.fromJson(Map<String, Object?> json) : _json = json;

  String get sessionId => _json['sessionId'] as String;
  List<ContentBlock> get prompt =>
      _list(_json['prompt'], ContentBlock.fromJson)!;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// The advertised steering extension's prompt for an existing running turn.
extension type const SteerRequest._(Map<String, Object?> _json) {
  SteerRequest({
    required String sessionId,
    required List<ContentBlock> prompt,
    Map<String, Object?>? meta,
  }) : _json = {
         'sessionId': sessionId,
         'prompt': [for (final block in prompt) block.toJson()],
         '_meta': ?meta,
       };
  SteerRequest.fromJson(Map<String, Object?> json) : _json = json;
  String get sessionId => _json['sessionId'] as String;
  List<ContentBlock> get prompt =>
      _list(_json['prompt'], ContentBlock.fromJson)!;
  Map<String, Object?>? get meta => _map(_json['_meta']);
  Map<String, Object?> toJson() => _json;
}

/// `session/prompt`'s answer: why the turn stopped.
extension type const PromptResponse._(Map<String, Object?> _json) {
  /// A view over a decoded answer.
  PromptResponse.fromJson(Map<String, Object?> json) : _json = json;

  /// One of [StopReason]'s, or a value chord does not know yet.
  String get stopReason => _json['stopReason'] as String;
  Map<String, Object?>? get usage => _map(_json['usage']);
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// The reasons a turn stops with.
abstract final class StopReason {
  static const endTurn = 'end_turn';
  static const maxTokens = 'max_tokens';
  static const maxTurnRequests = 'max_turn_requests';
  static const refusal = 'refusal';
  static const cancelled = 'cancelled';
}

/// A piece of content in a prompt, a message or a tool call: text, an
/// image, a resource, or a kind chord does not know yet.
extension type const ContentBlock._(Map<String, Object?> _json) {
  /// A text block.
  ContentBlock.text(String text) : _json = {'type': 'text', 'text': text};

  /// A view over a decoded block.
  ContentBlock.fromJson(Map<String, Object?> json) : _json = json;

  /// `text`, `image`, `audio`, `resource_link`, `resource`, or another.
  String get type => _json['type'] as String;

  /// A text block's text; null for any other kind.
  String? get text => type == 'text' ? _json['text'] as String : null;
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// `session/update`'s params: one update for one session.
extension type const SessionNotification._(Map<String, Object?> _json) {
  /// A view over decoded params.
  SessionNotification.fromJson(Map<String, Object?> json) : _json = json;

  String get sessionId => _json['sessionId'] as String;
  SessionUpdate get update =>
      SessionUpdate.fromJson(_json['update'] as Map<String, Object?>);
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// One `session/update`'s `update`, any kind. Once [kind] is known, it is
/// read through its own view with `as`, which costs nothing.
extension type const SessionUpdate._(Map<String, Object?> _json) {
  /// A view over a decoded update.
  SessionUpdate.fromJson(Map<String, Object?> json) : _json = json;

  /// One of [SessionUpdateKind]'s, or a kind chord does not know yet.
  String get kind => _json['sessionUpdate'] as String;
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// The update kinds M1 draws.
abstract final class SessionUpdateKind {
  static const userMessageChunk = 'user_message_chunk';
  static const agentMessageChunk = 'agent_message_chunk';
  static const agentThoughtChunk = 'agent_thought_chunk';
  static const toolCall = 'tool_call';
  static const toolCallUpdate = 'tool_call_update';
  static const plan = 'plan';
  static const planUpdate = 'plan_update';
  static const planRemoved = 'plan_removed';
  static const availableCommandsUpdate = 'available_commands_update';
  static const currentModeUpdate = 'current_mode_update';
  static const usageUpdate = 'usage_update';
  static const notice = 'notice';
  static const compactionUpdate = 'compaction_update';
  static const compactionSummaryChunk = 'compaction_summary_chunk';
}

/// A piece of a message, the person's, the agent's or its thought.
extension type const ContentChunk._(Map<String, Object?> _json)
    implements SessionUpdate {
  ContentBlock get content =>
      ContentBlock.fromJson(_json['content'] as Map<String, Object?>);
  String? get messageId => _json['messageId'] as String?;
}

/// A tool call the agent starts.
extension type const ToolCall._(Map<String, Object?> _json)
    implements SessionUpdate {
  String get toolCallId => _json['toolCallId'] as String;
  String get title => _json['title'] as String;

  /// One of [ToolKind]'s, or one chord does not know yet.
  String? get toolKind => _json['kind'] as String?;

  /// One of [ToolCallStatus]'s, or one chord does not know yet.
  String? get status => _json['status'] as String?;
  List<ToolCallContent>? get content =>
      _list(_json['content'], ToolCallContent.fromJson);
  List<ToolCallLocation>? get locations =>
      _list(_json['locations'], ToolCallLocation.fromJson);
  Object? get rawInput => _json['rawInput'];
  Object? get rawOutput => _json['rawOutput'];
}

/// What changed in a tool call: only its id is certain.
extension type const ToolCallUpdate._(Map<String, Object?> _json)
    implements SessionUpdate {
  /// A view over a decoded update, or a permission request's tool call.
  ToolCallUpdate.fromJson(Map<String, Object?> json) : _json = json;

  String get toolCallId => _json['toolCallId'] as String;
  String? get title => _json['title'] as String?;
  String? get toolKind => _json['kind'] as String?;
  String? get status => _json['status'] as String?;
  List<ToolCallContent>? get content =>
      _list(_json['content'], ToolCallContent.fromJson);
  List<ToolCallLocation>? get locations =>
      _list(_json['locations'], ToolCallLocation.fromJson);
  Object? get rawInput => _json['rawInput'];
  Object? get rawOutput => _json['rawOutput'];
}

/// The kinds of tool a call is.
abstract final class ToolKind {
  static const read = 'read';
  static const edit = 'edit';
  static const delete = 'delete';
  static const move = 'move';
  static const search = 'search';
  static const execute = 'execute';
  static const think = 'think';
  static const fetch = 'fetch';
  static const switchMode = 'switch_mode';
  static const other = 'other';
}

/// Where a tool call is.
abstract final class ToolCallStatus {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const failed = 'failed';
}

/// What a tool call produced: `content`, a `diff`, a `terminal`, or another.
extension type const ToolCallContent._(Map<String, Object?> _json) {
  /// A view over decoded content.
  ToolCallContent.fromJson(Map<String, Object?> json) : _json = json;

  String get type => _json['type'] as String;

  /// A `content` item's block.
  ContentBlock? get content => type == 'content'
      ? ContentBlock.fromJson(_json['content'] as Map<String, Object?>)
      : null;

  /// A `diff` item.
  Diff? get diff => type == 'diff' ? Diff.fromJson(_json) : null;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// A file's change: its text before, none for a new file, and after.
extension type const Diff._(Map<String, Object?> _json) {
  /// A view over a decoded diff.
  Diff.fromJson(Map<String, Object?> json) : _json = json;

  String get path => _json['path'] as String;
  String? get oldText => _json['oldText'] as String?;
  String get newText => _json['newText'] as String;
}

/// A file, and a line in it, a tool call touches.
extension type const ToolCallLocation._(Map<String, Object?> _json) {
  /// A view over a decoded location.
  ToolCallLocation.fromJson(Map<String, Object?> json) : _json = json;

  String get path => _json['path'] as String;
  num? get line => _json['line'] as num?;
}

/// The agent's plan, whole, each time it changes.
extension type const Plan._(Map<String, Object?> _json)
    implements SessionUpdate {
  List<PlanEntry> get entries => _list(_json['entries'], PlanEntry.fromJson)!;
}

/// One step of a plan.
extension type const PlanEntry._(Map<String, Object?> _json) {
  /// A view over a decoded entry.
  PlanEntry.fromJson(Map<String, Object?> json) : _json = json;

  String get content => _json['content'] as String;

  /// `high`, `medium`, `low`, or another.
  String get priority => _json['priority'] as String;

  /// `pending`, `in_progress`, `completed`, or another.
  String get status => _json['status'] as String;
}

/// The commands the agent offers, whole, each time they change.
extension type const AvailableCommandsUpdate._(Map<String, Object?> _json)
    implements SessionUpdate {
  List<AvailableCommand> get availableCommands =>
      _list(_json['availableCommands'], AvailableCommand.fromJson)!;
}

/// One command the agent offers.
extension type const AvailableCommand._(Map<String, Object?> _json) {
  /// A view over a decoded command.
  AvailableCommand.fromJson(Map<String, Object?> json) : _json = json;

  String get name => _json['name'] as String;
  String get description => _json['description'] as String;

  /// The hint for what follows the command, when it takes input.
  String? get hint => _map(_json['input'])?['hint'] as String?;
}

/// The session's mode, changed by the agent.
extension type const CurrentModeUpdate._(Map<String, Object?> _json)
    implements SessionUpdate {
  String get currentModeId => _json['currentModeId'] as String;
}

/// How much of its context the session uses, and what it cost; unstable in
/// ACP 2.6.
extension type const UsageUpdate._(Map<String, Object?> _json)
    implements SessionUpdate {
  num get used => _json['used'] as num;
  num get size => _json['size'] as num;
  num? get costAmount => _map(_json['cost'])?['amount'] as num?;
  String? get costCurrency => _map(_json['cost'])?['currency'] as String?;
}

/// `session/request_permission`'s params: a tool call the agent asks the
/// person about, and the answers it takes.
extension type const RequestPermissionRequest._(Map<String, Object?> _json) {
  /// A view over decoded params.
  RequestPermissionRequest.fromJson(Map<String, Object?> json) : _json = json;

  String get sessionId => _json['sessionId'] as String;
  ToolCallUpdate get toolCall =>
      ToolCallUpdate.fromJson(_json['toolCall'] as Map<String, Object?>);
  List<PermissionOption> get options =>
      _list(_json['options'], PermissionOption.fromJson)!;
  Map<String, Object?>? get meta => _map(_json['_meta']);

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// One answer a permission request takes.
extension type const PermissionOption._(Map<String, Object?> _json) {
  /// A view over a decoded option.
  PermissionOption.fromJson(Map<String, Object?> json) : _json = json;

  String get optionId => _json['optionId'] as String;
  String get name => _json['name'] as String;

  /// One of [PermissionOptionKind]'s, or another.
  String get kind => _json['kind'] as String;
}

/// The kinds of answer a permission option is.
abstract final class PermissionOptionKind {
  static const allowOnce = 'allow_once';
  static const allowAlways = 'allow_always';
  static const rejectOnce = 'reject_once';
  static const rejectAlways = 'reject_always';
}

/// The answer to a permission request: an option, or `cancelled`.
extension type const RequestPermissionResponse._(Map<String, Object?> _json) {
  /// The person chose [optionId].
  RequestPermissionResponse.selected(String optionId)
    : _json = {
        'outcome': {'outcome': 'selected', 'optionId': optionId},
      };

  /// Nobody answers it any more: the turn was cancelled, the agent withdrew
  /// it, or chord is closing.
  RequestPermissionResponse.cancelled()
    : _json = {
        'outcome': {'outcome': 'cancelled'},
      };

  /// A view over a decoded answer.
  RequestPermissionResponse.fromJson(Map<String, Object?> json) : _json = json;

  /// `selected` or `cancelled`.
  String get outcome =>
      (_json['outcome'] as Map<String, Object?>)['outcome'] as String;

  /// The option chosen, for a `selected` answer.
  String? get optionId => outcome == 'selected'
      ? (_json['outcome'] as Map<String, Object?>)['optionId'] as String
      : null;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

/// `session/cancel`'s params: stop that session's turn.
extension type const CancelNotification._(Map<String, Object?> _json) {
  /// A cancel for session [sessionId].
  CancelNotification({required String sessionId})
    : _json = {'sessionId': sessionId};

  /// A view over decoded params.
  CancelNotification.fromJson(Map<String, Object?> json) : _json = json;

  String get sessionId => _json['sessionId'] as String;

  /// The decoded map, the same one, for the wire.
  Map<String, Object?> toJson() => _json;
}

extension<T extends Object> on T? {
  R? let<R>(R Function(T value) f) {
    final value = this;
    return value == null ? null : f(value);
  }
}
