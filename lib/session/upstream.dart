/// What `chord acp` tells its client from what its sessions hear, from the
/// original's `session/upstream.ts`: pure, beside the reducer. One surface
/// for every agent; what an agent lacks is absent, not differently shaped.
/// chord's `/new` is here, `/team` waits for CTUI-37; the agent's plan
/// asks, its own subagents and chord's long-lived children are here.
library;

import 'dart:convert';

import 'package:collection/collection.dart';

import '../acp/host_fold.dart' show FoldedSession;
import '../js_trim.dart';
import 'agent_state.dart';
import 'busy.dart';
import 'config.dart';
import 'enrich.dart' show filledKey;
import 'models.dart';
import 'modes.dart';
import 'session.dart' show PromptImage, PromptParts;
import 'transcript/subagents.dart' show taskMetaKey;
import 'transcript/types.dart'
    show
        PlanAgent,
        PlanAnswer,
        PlanAccepted,
        PlanCancelled,
        PlanKept,
        PlanLeft,
        PlanPhase,
        PlanTodo,
        PlanWait;

/// The `_meta` key on a turn's words that no client prompt began.
const fromKey = 'chord/from';

/// The `_meta` key on what chord says of a subagent beyond ACP's words.
const agentKey = 'chord/agent';

/// Whether a declared capability holds, as JavaScript's truthiness reads it.
bool _declared(Object? value) =>
    value != null && value != false && value != 0 && value != '';

/// The capability each gated kind needs the client to have declared.
final Map<String, bool Function(Map<String, Object?> capabilities)> _needs = {
  'subagent_update': (c) => _declared(c['subagents']),
  'session_message': (c) => _declared(c['subagents']),
  'session_message_chunk': (c) => _declared(c['subagents']),
  'plan_update': (c) => _declared(c['plan']),
  'plan_removed': (c) => _declared(c['plan']),
  'compaction_update': (c) => _declared(_session(c)?['compaction']),
  'compaction_summary_chunk': (c) => _declared(_session(c)?['compaction']),
  'notice': (c) => _declared(_session(c)?['notices']),
};

Map<String, Object?>? _session(Map<String, Object?> capabilities) =>
    switch (capabilities['session']) {
      final Map<String, Object?> session => session,
      _ => null,
    };

/// The v1 schema's kinds that need nothing declared.
const _open = {
  'user_message_chunk',
  'agent_message_chunk',
  'agent_thought_chunk',
  'tool_call',
  'tool_call_update',
  'plan',
  'available_commands_update',
  'config_option_update',
  'session_info_update',
  'usage_update',
};

/// Whether an update of [kind] may go to a client that declared
/// [capabilities]; [child] for a subagent's. The schema says an agent MUST
/// NOT send these kinds undeclared: the check only drops, the same live and
/// on a load, and the record keeps them.
bool reaches(
  Map<String, Object?> capabilities,
  String kind, {
  bool child = false,
}) {
  if (child && !_declared(capabilities['subagents'])) return false;
  final needs = _needs[kind];
  return needs == null ? _open.contains(kind) : needs(capabilities);
}

/// An id free of the sessions [live] here: an agent with per-process
/// counter ids answers a second `session/new` with one already taken.
/// Upstream only.
String aliasFor(Set<String> live, String id) {
  var alias = id;
  for (var count = 2; live.contains(alias); count++) {
    alias = '$id~$count';
  }
  return alias;
}

/// How one session's ids go up, and what it last told of its
/// configuration.
final class UpstreamSession {
  /// The session the agent calls [agentId] and the client [upstreamId].
  const UpstreamSession(
    this.agentId,
    this.upstreamId, {
    this.children = const {},
    this.configSent,
    this.nested = false,
    this.commandsSent = false,
  });

  /// A session the client knows by the agent's own id.
  const UpstreamSession.of(String agentId) : this(agentId, agentId);

  /// The agent's id for it.
  final String agentId;

  /// The client's.
  final String upstreamId;

  /// Each subagent by the agent's id, under `<main>/<child>`.
  final Map<String, String> children;

  /// The configuration list the client last had, encoded.
  final String? configSent;

  /// A long-lived child's: all it says is a child's traffic to the client.
  final bool nested;

  /// Whether the client has chord's commands, with or without the agent's.
  final bool commandsSent;

  UpstreamSession _with({
    Map<String, String>? children,
    String? configSent,
    bool? commandsSent,
  }) => UpstreamSession(
    agentId,
    upstreamId,
    children: children ?? this.children,
    configSent: configSent ?? this.configSent,
    nested: nested,
    commandsSent: commandsSent ?? this.commandsSent,
  );
}

/// A long-lived child's session, the agent's [agentId] under the client's
/// [upstreamId] (`<parent>/<child id>`): what it says goes only to a client
/// that takes subagents.
UpstreamSession childSession(String agentId, String upstreamId) =>
    UpstreamSession(agentId, upstreamId, nested: true);

/// The agent's id for a subagent's composite id: looked up exactly, never
/// parsed, as a child's own id may hold a `/`.
String? childOf(UpstreamSession session, String upstreamId) {
  for (final MapEntry(:key, :value) in session.children.entries) {
    if (value == upstreamId) return key;
  }
  return null;
}

/// A session's id or a child's as the client knows it; unknown ones as
/// they are.
String upstreamIdOf(UpstreamSession session, String id) =>
    id == session.agentId ? session.upstreamId : (session.children[id] ?? id);

/// Whether an ask may name [id]: the session or a child it announced.
/// Anything else would reach the client as it is, where it could be
/// another live session.
bool asksIn(UpstreamSession session, String id) =>
    id == session.agentId || session.children.containsKey(id);

/// The adapters' draft state words, as ACP's.
const _endedAs = <String, Map<String, Object?>>{
  'completed': {'state': 'idle', 'stopReason': 'end_turn'},
  'failed': {'state': 'idle', 'stopReason': 'error'},
  'cancelled': {'state': 'idle', 'stopReason': 'cancelled'},
  'disconnected': {'state': 'unknown'},
};

Map<String, Object?> _acpStateWords(Map<String, Object?> update) {
  final word = switch (update['state']) {
    {'state': final String word} => word,
    _ => null,
  };
  final state = _endedAs[word];
  if (state == null) return update;
  final meta = update['_meta'];
  return {
    ...update,
    'state': state,
    '_meta': {
      if (meta is Map<String, Object?>) ...meta,
      agentKey: {'state': word},
    },
  };
}

/// A session's update going up: under the client's ids, or none.
typedef Mapped = ({
  UpstreamSession session,
  Map<String, Object?>? notification,
});

/// One [update] of [session] as it goes up, or none: under the client's
/// ids, whole, `_meta` included, read after the enrichers. The
/// configuration kinds go as one shape by [configChange], never as the
/// agent sent them. [subagentId] names the subagent it came from, if any.
Mapped mapUpdate(
  UpstreamSession session,
  Map<String, Object?> capabilities,
  Map<String, Object?> update, {
  String? subagentId,
}) {
  final kind = update['sessionUpdate'];
  if (kind is! String ||
      kind == 'config_option_update' ||
      kind == 'current_mode_update') {
    return (session: session, notification: null);
  }
  final parent = subagentId == null
      ? session.upstreamId
      : upstreamIdOf(session, subagentId);
  final child = update['sessionId'];
  final grown =
      kind == 'subagent_update' &&
          child is String &&
          !session.children.containsKey(child)
      ? session._with(children: {...session.children, child: '$parent/$child'})
      : session;
  if (!reaches(
    capabilities,
    kind,
    child: session.nested || subagentId != null,
  )) {
    return (session: grown, notification: null);
  }
  final sessionId = upstreamIdOf(grown, subagentId ?? grown.agentId);
  // Rewritten here, as the state and the record keep the agent's own list;
  // a child's is its own, and takes none of chord's.
  if (kind == 'available_commands_update' &&
      subagentId == null &&
      !session.nested) {
    final agents = update['availableCommands'];
    return (
      session: grown._with(commandsSent: true),
      notification: {
        'sessionId': sessionId,
        'update': {
          ...update,
          'availableCommands': _withChordCommands([
            if (agents is List) ...agents,
          ]),
        },
      },
    );
  }
  return (
    session: grown,
    notification: {
      'sessionId': sessionId,
      'update': _rewritten(grown, capabilities, update),
    },
  );
}

Map<String, Object?> _rewritten(
  UpstreamSession session,
  Map<String, Object?> capabilities,
  Map<String, Object?> update,
) {
  switch (update['sessionUpdate']) {
    case 'tool_call' || 'tool_call_update':
      return _withReferences(session, capabilities, update);
    case 'subagent_update':
      final child = update['sessionId'];
      final meta = update['_meta'];
      return _acpStateWords({
        ...update,
        if (child is String) 'sessionId': upstreamIdOf(session, child),
        // chord's own task: chord stops it, whatever its runtime offers.
        if (meta is Map && meta[taskMetaKey] != null)
          'capabilities': {'cancel': <String, Object?>{}},
      });
    case 'session_message':
      final sender = update['senderSessionId'];
      final recipient = update['recipientSessionId'];
      return {
        ...update,
        if (sender is String) 'senderSessionId': upstreamIdOf(session, sender),
        if (recipient is String)
          'recipientSessionId': upstreamIdOf(session, recipient),
      };
    default:
      return update;
  }
}

/// A call's references to subagents (`{type: "session"}`) under the
/// client's ids: one to a child the session announced goes by its alias;
/// one to any other id is dropped, never passed raw, as it could be another
/// session's alias; and for a client that takes no subagents, every one is
/// dropped. Content that was only references goes empty.
Map<String, Object?> _withReferences(
  UpstreamSession session,
  Map<String, Object?> capabilities,
  Map<String, Object?> update,
) {
  final content = update['content'];
  if (content is! List ||
      !content.any((item) => item is Map && item['type'] == 'session')) {
    return update;
  }
  final subagents = _declared(capabilities['subagents']);
  return {
    ...update,
    'content': [
      for (final item in content)
        if (item is! Map || item['type'] != 'session')
          item
        else if (subagents && session.children[item['sessionId']] != null)
          {...item, 'sessionId': session.children[item['sessionId']]},
    ],
  };
}

/// Modes, models and efforts as one list: the mode and the model, the
/// agent's own option or made from the older fields, then its other
/// selects. Booleans never appear, as the window shows none.
List<Map<String, Object?>> configOptionsOf(AgentState state) {
  final modes = modesFrom(state.configOptions, state.modes);
  final models = modelsFrom(state.configOptions, state.models);
  Map<String, Object?>? named(String id) {
    for (final option in state.configOptions) {
      if (option['id'] == id) return option;
    }
    return null;
  }

  final modeId = modeConfigId(state.configOptions) ?? 'mode';
  final modelId = modelConfigId(state.configOptions) ?? 'model';
  return [
    if (modes?.current case final current?)
      {
        'type': 'select',
        'id': modeId,
        'name': named(modeId)?['name'] ?? 'Mode',
        'category': 'mode',
        'currentValue': current,
        'options': [
          for (final mode in modes!.available)
            {'value': mode.id, 'name': mode.name},
        ],
      },
    if (models?.current case final current?)
      {
        'type': 'select',
        'id': modelId,
        'name': named(modelId)?['name'] ?? 'Model',
        'category': 'model',
        'currentValue': current,
        'options': [
          for (final model in models!.available)
            {'value': model.id, 'name': model.name},
        ],
      },
    for (final option in optionsFromConfigOptions(state.configOptions))
      {
        'type': 'select',
        'id': option.id,
        'name': option.name,
        'currentValue': option.current,
        'options': [
          for (final value in option.values)
            {'value': value.value, 'name': value.name},
        ],
      },
  ];
}

/// Which of the conversation's sets an option of [configOptionsOf] goes to.
enum ConfigSetter {
  /// The mode.
  mode,

  /// The model.
  model,

  /// Another select option.
  option,
}

/// The setter of option [id] in [state]; none for an id chord does not
/// list.
ConfigSetter? configSetter(AgentState state, String id) {
  for (final option in configOptionsOf(state)) {
    if (option['id'] != id) continue;
    return switch (option['category']) {
      'mode' => ConfigSetter.mode,
      'model' => ConfigSetter.model,
      _ => ConfigSetter.option,
    };
  }
  return null;
}

/// The whole update if the list differs from what the client last had. So
/// an agent that changes its config only in responses, one that answers
/// `set_mode` with nothing, and one that sends updates all look alike.
Mapped configChange(UpstreamSession session, AgentState state) {
  final configOptions = configOptionsOf(state);
  final encoded = jsonEncode(configOptions);
  if (encoded == session.configSent) {
    return (session: session, notification: null);
  }
  return (
    session: session._with(configSent: encoded),
    notification: {
      'sessionId': session.upstreamId,
      'update': {
        'sessionUpdate': 'config_option_update',
        'configOptions': configOptions,
        '_meta': {
          filledKey: ['configOptions'],
        },
      },
    },
  );
}

/// The list a session's answer carries, which [configChange] then goes on
/// from.
({UpstreamSession session, List<Map<String, Object?>> configOptions})
answeredConfig(UpstreamSession session, AgentState state) {
  final configOptions = configOptionsOf(state);
  return (
    session: session._with(configSent: jsonEncode(configOptions)),
    configOptions: configOptions,
  );
}

/// What a `chord acp` session declares toward its agent, as the original's
/// `clientCapabilities` does: forms and links, plans, compaction, notices
/// when the client declared them, subagents, and commands' output as
/// `_meta` on their tool calls, which reaches the client as the agent sent
/// it.
Map<String, Object?> acpCapabilities({required bool notices}) => {
  'elicitation': {'form': <String, Object?>{}, 'url': <String, Object?>{}},
  'subagents': <String, Object?>{},
  'plan': <String, Object?>{},
  'session': {
    'compaction': <String, Object?>{},
    if (notices) 'notices': <String, Object?>{},
  },
  '_meta': {'terminal_output_delta': true},
};

/// What chord says of a long-lived child, as no agent's update does.
final class AgentReport {
  /// A report of the child the client knows as [upstreamId], under
  /// [parent].
  const AgentReport({
    required this.parent,
    required this.upstreamId,
    required this.title,
    required this.state,
    required this.runtime,
    this.model,
    this.effort,
    this.mode,
    this.team,
    this.gone,
    this.failed,
    this.closed = false,
  });

  /// Its immediate parent's id: main's.
  final String parent;
  final String upstreamId;
  final String title;

  /// ACP's state words for it, as [agentStateOf] gives them.
  final Map<String, Object?> state;
  final String runtime;
  final String? model;
  final String? effort;

  /// The mode it is in, reported only: chord sets no policy on it.
  final String? mode;
  final String? team;

  /// Its process went on its own.
  final String? gone;

  /// Why it did not start.
  final String? failed;
  final bool closed;

  /// This report, the child closed.
  AgentReport get asClosed => AgentReport(
    parent: parent,
    upstreamId: upstreamId,
    title: title,
    state: state,
    runtime: runtime,
    model: model,
    effort: effort,
    mode: mode,
    team: team,
    gone: gone,
    failed: failed,
    closed: true,
  );
}

/// A child's state as ACP words it, from what is folded of it: an open
/// plan ask, permission or form wants the client; busy is `running`; else
/// `idle`, with the turn's [stopReason] once one ended.
Map<String, Object?> agentStateOf(FoldedSession fold, {String? stopReason}) {
  final transcript = fold.transcript;
  final asks = transcript.planAsks.any((ask) => ask.answer == null);
  final busy = busyOf(transcript, fold.queue);
  if (asks || busy is BusyPermission || busy is BusyInput) {
    return const {'state': 'requires_action'};
  }
  return busy != null
      ? const {'state': 'running'}
      : {'state': 'idle', 'stopReason': ?stopReason};
}

/// A long-lived child's `subagent_update`, on its immediate parent, or none
/// for a client that takes no subagents. chord makes it, so no record holds
/// it; one closed has nothing left to cancel.
Map<String, Object?>? agentUpdate(
  Map<String, Object?> capabilities,
  AgentReport report,
) {
  if (!reaches(capabilities, 'subagent_update')) return null;
  return {
    'sessionId': report.parent,
    'update': {
      'sessionUpdate': 'subagent_update',
      'sessionId': report.upstreamId,
      'title': report.title,
      'state': report.state,
      if (!report.closed) 'capabilities': {'cancel': <String, Object?>{}},
      '_meta': {
        agentKey: {
          'runtime': report.runtime,
          'model': ?report.model,
          'effort': ?report.effort,
          'mode': ?report.mode,
          'team': ?report.team,
          'gone': ?report.gone,
          'failed': ?report.failed,
          if (report.closed) 'closed': true,
        },
      },
    },
  };
}

/// A message no client prompt began, as the client hears of it.
Map<String, Object?> messageChunk(
  String sessionId,
  String text, {
  Map<String, Object?>? from,
}) => {
  'sessionId': sessionId,
  'update': {
    'sessionUpdate': 'user_message_chunk',
    'content': {'type': 'text', 'text': text},
    if (from != null) '_meta': {fromKey: from},
  },
};

/// The client's answer to a permission, checked against the [options] it
/// was offered: the option chosen, or null for a refusal (a cancel, an
/// error, an id not offered).
String? permissionAnswerOf(
  List<Map<String, Object?>> options,
  Map<String, Object?>? response,
) {
  final outcome = response?['outcome'];
  if (outcome is! Map || outcome['outcome'] != 'selected') return null;
  final chosen = outcome['optionId'];
  return options.any((option) => option['optionId'] == chosen)
      ? chosen as String
      : null;
}

/// The client's answer to a form or a link, passed on as it came: an error
/// (none) or a word ACP does not have is `cancel`.
Map<String, Object?> elicitationReplyOf(Map<String, Object?>? response) =>
    switch (response?['action']) {
      'accept' || 'decline' || 'cancel' => response!,
      _ => const {'action': 'cancel'},
    };

/// A client's prompt as the conversation sends it: its text, and its
/// images, embedded resources and resource links, each block as the client
/// sent it.
typedef UpstreamPrompt = ({String text, PromptParts parts});

/// A prompt's [blocks] as [UpstreamPrompt], or why [agent]'s advertised
/// capabilities refuse it. Audio and unknown kinds stay unsupported.
({UpstreamPrompt? prompt, String? refused}) promptOf(
  List<Map<String, Object?>> blocks,
  String agent, {
  required bool takesImages,
  bool takesEmbeddedContext = false,
}) {
  final texts = <String>[];
  final images = <PromptImage>[];
  final resources = <Map<String, Object?>>[];
  final links = <Map<String, Object?>>[];
  for (final block in blocks) {
    switch (block['type']) {
      case 'text':
        texts.add(block['text'] as String);
      case 'image':
        if (!takesImages) {
          return (prompt: null, refused: '$agent does not take images');
        }
        images.add((
          mimeType: block['mimeType'] as String,
          data: block['data'] as String,
        ));
      case 'resource':
        if (!takesEmbeddedContext) {
          return (
            prompt: null,
            refused: '$agent does not take embedded resources',
          );
        }
        resources.add(block);
      case 'resource_link':
        links.add(block);
      case final type:
        return (prompt: null, refused: 'A prompt cannot carry a $type block.');
    }
  }
  return (
    prompt: (
      text: texts.join('\n'),
      parts: PromptParts(images: images, resources: resources, links: links),
    ),
    refused: null,
  );
}

/// The two names that are chord's in `chord acp`; all else goes as typed.
const List<Map<String, Object?>> chordCommands = [
  {
    'name': 'team',
    'description': 'Show and run teams of agents',
    'input': {
      'hint':
          'list | run <name> <job> | show <name> | stop <run> | new <words>',
    },
  },
  {
    'name': 'new',
    'description': 'Open a new agent beside main',
    'input': {'hint': '[agent] [--name <name>]'},
  },
];

/// One of chord's commands: its name, the words after it, and whether the
/// prompt holds nothing else.
typedef ChordCommand = ({String name, String args, bool alone});

final _command = RegExp(r'^\/(\S+)(?:\s+([\s\S]*))?$');

/// The command a prompt's first text block is, if it is one of chord's.
ChordCommand? commandOf(List<Map<String, Object?>> blocks) {
  final first = blocks.firstWhereOrNull((block) => block['type'] == 'text');
  final text = first?['text'];
  if (text is! String) return null;
  final match = _command.firstMatch(jsTrim(text));
  final name = match?.group(1);
  if (name == null || !chordCommands.any((each) => each['name'] == name)) {
    return null;
  }
  return (name: name, args: match!.group(2) ?? '', alone: blocks.length == 1);
}

/// The agent's list with chord's ahead of it: a name both offer is chord's
/// alone, as chord's is the one that runs.
List<Object?> _withChordCommands(List<Object?> agents) {
  final ours = {for (final command in chordCommands) command['name']};
  return [
    ...chordCommands,
    for (final command in agents)
      if (command is! Map || !ours.contains(command['name'])) command,
  ];
}

/// chord's commands for an agent that has said none yet; once.
Mapped commandsIfNone(UpstreamSession session) => session.commandsSent
    ? (session: session, notification: null)
    : (
        session: session._with(commandsSent: true),
        notification: {
          'sessionId': session.upstreamId,
          'update': {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': _withChordCommands(const []),
          },
        },
      );

List<String> _todosMarkdown(List<PlanTodo>? todos) => [
  for (final todo in todos ?? const <PlanTodo>[])
    '- [${todo.status == 'completed' ? 'x' : ' '}] ${todo.content}',
];

String _planMarkdown(PlanWait plan) => [
  ?plan.overview,
  ?plan.plan,
  if (plan.todos case final todos? when todos.isNotEmpty)
    _todosMarkdown(todos).join('\n'),
  for (final phase in plan.phases ?? const <PlanPhase>[])
    ['## ${phase.name}', ..._todosMarkdown(phase.todos)].join('\n'),
].join('\n\n');

/// A plan ask as an ordinary permission for `chord acp`'s client, as the
/// original's `planPermission`: its call, its markdown, the agent's choices.
Map<String, Object?> planPermission(String sessionId, PlanWait plan) => {
  'sessionId': sessionId,
  'toolCall': {
    'toolCallId': plan.toolCallId,
    'title': plan.name ?? 'Plan',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': _planMarkdown(plan)},
      },
    ],
  },
  'options': [
    {
      'optionId': 'accepted',
      'name': 'Yes, accept the plan',
      'kind': 'allow_once',
    },
    {'optionId': 'kept', 'name': 'No, keep planning', 'kind': 'reject_once'},
    if (plan.agent == PlanAgent.grok)
      {
        'optionId': 'left',
        'name': 'No, and leave plan mode',
        'kind': 'reject_once',
      },
  ],
};

/// The client's answer to a plan ask: a cancel, an error (none) or an id it
/// was not offered is cancelled, never a yes.
PlanAnswer planAnswerOf(PlanWait plan, Map<String, Object?>? response) {
  final outcome = response?['outcome'];
  if (outcome is! Map || outcome['outcome'] != 'selected') {
    return const PlanCancelled();
  }
  return switch (outcome['optionId']) {
    'accepted' => const PlanAccepted(),
    'kept' => const PlanKept(),
    'left' when plan.agent == PlanAgent.grok => const PlanLeft(),
    _ => const PlanCancelled(),
  };
}
