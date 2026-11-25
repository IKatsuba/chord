// A fake ACP agent over stdio, for tests and for checking chord's screen by
// hand without spending anyone's account: the original's
// tests/fixtures/fake_agent/main.ts in Dart, the same on the wire. Its
// AGENTS.md there lists every scenario, flag and environment variable.
//
// The scenario comes from, in order: a prompt whose whole text is a
// scenario name, then `--scenario <name>`, then `CHORD_FAKE_SCENARIO`, then
// `text`. It imports nothing of the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../commands.dart';
import '../forms.dart';
import 'client.dart';
import 'context.dart';
import 'options.dart';
import 'rpc.dart';
import 'schema.dart';
import 'scenarios/accounts.dart';
import 'scenarios/agents.dart';
import 'scenarios/chord_tools.dart';
import 'scenarios/compaction.dart';
import 'scenarios/cycles.dart';
import 'scenarios/efforts.dart';
import 'scenarios/forms.dart';
import 'scenarios/fx.dart';
import 'scenarios/guardian.dart';
import 'scenarios/links.dart';
import 'scenarios/misbehaving.dart';
import 'scenarios/modes.dart';
import 'scenarios/monitors.dart';
import 'scenarios/notices.dart';
import 'scenarios/permissions.dart';
import 'scenarios/plans.dart';
import 'scenarios/resources.dart';
import 'scenarios/review_permissions.dart';
import 'scenarios/selected_teams.dart';
import 'scenarios/settings.dart';
import 'scenarios/shell.dart';
import 'scenarios/soak.dart';
import 'scenarios/subagents.dart';
import 'scenarios/tasks.dart';
import 'scenarios/teams.dart';
import 'scenarios/text.dart';
import 'scenarios/titles.dart';
import 'scenarios/tools.dart';
import 'sessions.dart';
import 'turn.dart';

/// Every scenario the original's fake has, ported or not: a prompt that
/// names one is a scenario's, not words to answer.
const scenarios = [
  'fxerror', 'resources', 'selectedteam', 'budgetawareteam', //
  'savedteamplain', 'selectedlate', 'selectedlead', 'selectedidle',
  'guardian', 'guardiangated', 'text', 'notice', 'noticeidle', 'noticelong',
  'titledlater', 'authchanged', 'subagentlinked', 'subagentgrandlinked',
  'subagentstranger', 'cloudrequest', 'texttillsteered',
  'texttillsteeredheld', 'readsheld', 'thought', 'tools', 'steps',
  'stepslater', 'calls', 'rawoutputs', 'longresults', 'overlap',
  'overlaptwo', 'overlapfail', 'overlapask', 'overlapasksteer',
  'subagentcall', 'unordered', 'edit', 'rewrite', 'headlines', 'heredoc',
  'longcommand', 'mcpnote', 'codexmcpnote', 'markdown', 'markdownwrap',
  'markdowncode', 'graphemes', 'permission', 'multidiffask', 'plan',
  'planshrink', 'planshrinkgated', 'proposal', 'cursorplan',
  'cursorplanearly', 'cursorplanbad', 'grokplan', 'grokplanempty',
  'planheard', 'grokplanwrong', 'cursorplanlate', 'planform', 'shell',
  'shellcut', 'bash', 'bashtwo', 'bashone', 'bashcut', 'bashask',
  'claudebetween', 'mainbetween', 'leftask', 'mainbetweentwice',
  'taskbetween', 'taskstays', 'tasktitled', 'taskstayshold',
  'tasktillsteered', 'teamtask', 'compact', 'codexcompact', 'compactfail',
  'idlecompact', 'idlecompactfail', 'idlecompactsays', 'status', 'error',
  'slow', 'titled', 'retitled', 'titledlook', 'titledfix', 'titledlong',
  'costwait', 'costwaitlate', 'long', 'longheld', 'todos', 'exitplan',
  'fullaccess', 'claudeexitplan', 'lock', 'mcp', 'opened', 'configsheard',
  'form', 'link', 'askclaude', 'askclaudeone', 'askcodex', 'askdroid',
  'askopencode', 'askdimcode', 'askcodexwait', 'askcodexasync', 'taskask',
  'taskaskstays', 'taskaskas', 'taskformas', 'mode', 'effort', 'late',
  'twins', 'permissionsteer', 'reviewpermission', 'reviewincomplete',
  'reviewfailed', 'mcpask', 'bigask', 'bigasktwice', 'unknown',
  'authstatus', 'turnfailed', 'cancels', 'flood', 'ignorescancel',
  'requestform', 'permissionmeta', 'strangerask', 'strangerform',
  'subagent', 'subagentupdate', 'codexsubagents', 'codexsubagentstop',
  'claudesubagents', 'claudelongprompt', 'claudecodeprompt',
  'claudepromptgrows', 'claudewrapprompt', 'claudesendrunning',
  'claudehandback', 'claudeunsetlaunch', 'claudenoanswer', 'claudefailed',
  'claudenested', 'claudebackground', 'claudeslowstop', 'claudemessage',
  'claudewaiting', 'claudenostop', 'subagentstates', 'subagentstatesstay',
  'chordtools', 'settingsread', 'settingsreadkey', 'settingsreadbad',
  'settingsreadlinked', 'settingstheme', 'settingsmodel', 'settingsremove',
  'settingsagent', 'settingslong', 'settingsvim', 'settingsoffered',
  'settingsoverlap', 'settingsrefused', 'settingswithdrawn', 'cutcalls',
  'cutcallsback', 'cutcallsunfinished', 'cutcallsunfinishedv2', 'task',
  'chordcalls', 'codexchordcalls', 'codexmodels', 'leftform',
  'leftformgated', 'bigaskleft', 'claudecycle', 'claudecyclebare',
  'claudecycleask', 'codebuddycycle', 'taskchild', 'taskchildhold',
  'tasklong', 'taskclose', 'taskcost', 'tasktallname', 'tasktwo',
  'taskwait', 'agents', 'agentother', 'agentsquiet', 'agentsheld',
  'agentsheldgated', 'agentchild', 'agentclose', 'agentclear', 'agentlate',
  'agentclearonly', 'latesay', 'agentcall', 'agentcalltwice',
  'agentcallgated', 'callchildgated', 'callchild', 'callchildtwo',
  'agentsend', 'codexagentsend', 'agentsendrefused', 'agentprose',
  'codexagentprose', 'prosechild', 'codexprosechild', 'agentlong',
  'agenttask', 'agentcost', 'agentexit', 'agentfail', 'agenttitled',
  'agentmentions', 'agentnames', 'agentstitled', 'taskeffort',
  'taskmaxeffort', 'agenteffort', 'agentmaxeffort', 'crash', 'monitor',
  'monitors', 'monitorexit', 'monitortimeout', 'monitorflood',
  'monitorchild', 'childmonitor', 'team', 'team2', 'teamlead',
  'teamtester', 'leadclear', 'teampartof', 'leadclearrace',
  'leadclearonly', 'teamcoder', 'teamreviewer', 'propose', 'proposeagain',
  'proposeefforts', 'proposeeffortsagain', 'soak', 'soaklead', 'soakturn',
];

/// Every scenario ported so far, each family's from its module under
/// `scenarios/`.
final Map<String, Play> play = {
  ...text,
  ...tools,
  ...permissionPlays,
  ...reviewPermissions,
  ...plans,
  ...forms,
  ...guardian,
  ...links,
  ...modePlays,
  ...shell,
  ...compaction,
  ...idleCompaction,
  ...notices,
  ...titles,
  ...accounts,
  ...effortPlays,
  ...fx,
  ...resources,
  ...monitors,
  ...subagents,
  ...agentPlays,
  ...chordTools,
  ...settingsPlays,
  ...taskPlays,
  ...teamPlays,
  ...selectedTeams,
  ...cycles,
  ...misbehaving,
  ...soak,
};

/// The scenarios this fake plays, which the launcher routes to it until
/// every one is ported.
Set<String> get portedScenarios => play.keys.toSet();

/// The scenario a person's words stand for, as `--said` gives them.
String? _unsaid(String? text) {
  for (final MapEntry(:key, :value) in said.entries) {
    if (value == text) return key;
  }
  return text;
}

bool _isScenario(String? value) => value != null && scenarios.contains(value);

String _defaultScenario() {
  final flag = args.indexOf('--scenario');
  final chosen = flag >= 0
      ? (flag + 1 < args.length ? args[flag + 1] : null)
      : environment['CHORD_FAKE_SCENARIO'];
  if (chosen == null) return 'text';
  if (!_isScenario(chosen)) throw StateError('unknown scenario "$chosen"');
  return chosen;
}

/// An answer that never comes.
Future<Never> _never() => Completer<Never>().future;

/// The answer to a model switch: the new model's set, its effort kept where
/// it lists it, else `medium`; with `--resend-config`, also sent by
/// `config_option_update` on `low`, before or after the answer.
Future<Map<String, Object?>> _switchedModel(
  Client client,
  String sessionId,
) async {
  final model = models[sessionId] ?? firstModel;
  if (modes[sessionId] == 'auto') {
    modes[sessionId] = await _fallenBack(client, sessionId, 'auto');
  }
  if (!effortsOf(
    model,
  ).any((each) => each['value'] == (efforts[sessionId] ?? 'medium'))) {
    efforts[sessionId] = 'medium';
  }
  if (!hasFast(model)) fasts.remove(sessionId);

  final answer = {'configOptions': configOptions(sessionId)};
  Future<void> resend() {
    final said = efforts[sessionId];
    efforts[sessionId] = 'low';
    final update = configOptions(sessionId);
    if (resendConfig == 'before') {
      if (said == null) {
        efforts.remove(sessionId);
      } else {
        efforts[sessionId] = said;
      }
    }
    return client.notify('session/update', {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'config_option_update',
        'configOptions': update,
      },
    });
  }

  if (resendConfig == 'before') {
    await resend();
  } else if (resendConfig == 'after') {
    later(milliseconds(stepMs), () => resend().ignore());
  }
  return answer;
}

/// A line for each image and `resource_link` in a prompt, a turn's or a
/// steer's, so a capture shows what arrived.
List<String> _receivedLines(List<Object?> prompt) => [
  for (final block in prompt)
    if (block case {'type': 'image'})
      'Received an image: ${_js(block['mimeType'])}, '
          '${_atobLength(block['data'])} bytes\n\n'
    else if (block case {'type': 'resource_link'})
      'Received a link: ${_js(block['name'])}, ${_js(block['uri'])}\n\n'
    else if (block case {'type': 'resource'})
      'Received a resource: ${stringify(block)}\n\n',
];

/// [value] as a template literal writes it.
String _js(Object? value) => value == null ? 'undefined' : '$value';

/// The length of `atob(data)`: its bytes once base64 is read.
int _atobLength(Object? data) => base64
    .decode(base64.normalize('$data'.replaceAll(RegExp(r'\s'), '')))
    .length;

String _promptText(List<Object?> prompt) => [
  for (final block in prompt)
    if (block case {'type': 'text', 'text': final String text}) text else '',
].join().trim();

final _fallback = _defaultScenario();
final _turns = <String, Aborter>{};

/// The turn each session is playing, which a steer goes into.
final _playing = <String, Turn>{};

/// Each session's `session/prompt` still unanswered.
final _prompted = <String, Future<Object?>>{};

/// The messages chord holds for a session's next prompt and sends ahead.
final _heldNotes = RegExp(
  r'^(?:<message from="[^"]*"(?: monitor="[^"]*")?>\n[\s\S]*?\n<\/message>\n\n)+',
);

/// chord's note that calls of its tools were cut off (CHD-417).
final _cutNote = RegExp(
  r'^<message from="chord">\n(Your \S+ (?:to @\S+ )?(?:call )?was cut off before it reached chord[\s\S]*?)\n<\/message>\n\n',
);

/// [text] as a JSON string with every C0, DEL and C1 character escaped.
String _quoted(String text) {
  final escaped = text.replaceAllMapped(
    RegExp('["\\\\\u0000-\u001f\u007f-\u009f]'),
    (match) {
      final found = match.group(0)!;
      return found == '"' || found == r'\'
          ? '\\$found'
          : '\\u${found.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}';
    },
  );
  return '"$escaped"';
}

/// A prompt that starts with one of the fake's commands, or `verbatim`,
/// `askas` or `formas`; null for any other.
Future<String?> _playCommand(Turn turn, String text) async {
  if (text
      .replaceFirst(_heldNotes, '')
      .startsWith('The person asks for a team of agents through /team new')) {
    return _playOf('propose')(turn);
  }

  final verbatim = RegExp(r'^verbatim (.*)$', dotAll: true).firstMatch(text);
  if (verbatim != null) {
    await turn.say([_quoted(verbatim.group(1)!)]);
    return 'end_turn';
  }

  final passing = RegExp(r'^(ask|form)as (\S+)$').firstMatch(text);
  if (passing?.group(1) == 'form') {
    return elicit(turn, {
      'sessionId': passing!.group(2),
      'mode': 'form',
      'message': 'Passing as another session',
      'requestedSchema': formSchema,
    });
  }
  if (passing?.group(1) == 'ask') {
    final answer = await turn.client.request('session/request_permission', {
      'sessionId': passing!.group(2),
      'toolCall': {'toolCallId': turn.callId('write')},
      'options': [
        {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
      ],
    });
    await turn.say(['Answered: ${_stringifyOrUndefined(answer['outcome'])}']);
    return 'end_turn';
  }

  final command = RegExp(r'^\/(\S+)\s*(.*)$', dotAll: true).firstMatch(text);
  switch (command?.group(1)) {
    case 'greet':
      await turn.say(['Hello', ' from the fake agent.']);
      return 'end_turn';
    case 'echo':
      final rest = command!.group(2) ?? '';
      await turn.say([rest.isEmpty ? '(nothing to echo)' : rest]);
      return 'end_turn';
    default:
      return null;
  }
}

String _stringifyOrUndefined(Object? value) =>
    value == null ? 'undefined' : stringify(value);

/// A message another agent sent through chord: answered with who it was
/// from, or with the whole prompt under `--echo-messages`.
Future<String> _playMessage(Turn turn, String from, String asked) async {
  await turn.say([
    echoMessages
        ? 'Received ${_quoted(asked)}'
        : 'Received the message from $from.',
  ]);
  return 'end_turn';
}

/// The play of [scenario], which must be ported.
Play _playOf(String scenario) =>
    play[scenario] ??
    (throw StateError('scenario "$scenario" is not ported to the Dart fake'));

/// Every session this process created, oldest first, for `session/list`.
final _created = <Map<String, Object?>>[];

/// Each model's context window.
const _windows = {'fake-large': 1000000, 'fake-small': 200000};

/// The tokens every turn reports.
const _turnUsage = {
  'inputTokens': 1000,
  'outputTokens': 200,
  'cachedReadTokens': 800,
  'totalTokens': 2000,
};

/// What each turn adds to the session's cost, in USD.
const _turnCost = 0.0125;

/// How long after its answer a late turn's cost comes.
const _lateCostMs = 100;

/// A turn's cost held for its session's next prompt.
final _heldCosts = <String, Update>{};

/// How many turns each session has reported usage for.
final _reported = <String, int>{};

/// The usage a turn that set none of its own reports as it ends.
Future<void> _reportUsage(Turn turn) async {
  final count = (_reported[turn.sessionId] ?? 0) + 1;
  _reported[turn.sessionId] = count;
  final times = sessionUsage ? count : 1;
  final usage = {
    for (final MapEntry(:key, :value) in _turnUsage.entries) key: value * times,
  };

  if (tokensOnly && !noCost) {
    turn.usage = usage;
    return;
  }

  final cost = (costs[turn.sessionId] ?? costFrom) + _turnCost;
  costs[turn.sessionId] = cost;
  final Update update = {
    'sessionUpdate': 'usage_update',
    'used': _turnUsage['totalTokens']! * count,
    'size': _windows[models[turn.sessionId] ?? firstModel] ?? 0,
    if (!noCost) 'cost': {'amount': cost, 'currency': 'USD'},
  };
  turn.usage = usage;

  if (costAtNext) {
    _heldCosts[turn.sessionId] = update;
    return;
  }
  if (!lateCost) {
    await turn.send(update);
    return;
  }
  () async {
    try {
      await pause(lifetime.signal, _lateCostMs);
      await turn.client.notify('session/update', {
        'sessionId': turn.sessionId,
        'update': update,
      });
    } catch (_) {
      // The client went first.
    }
  }();
}

/// What a loaded session says happened before.
const _history = <Update>[
  {
    'sessionUpdate': 'user_message_chunk',
    'content': {'type': 'text', 'text': 'tools'},
  },
  {
    'sessionUpdate': 'tool_call',
    'toolCallId': 'history-read-1',
    'title': 'Read README.md',
    'kind': 'read',
    'status': 'completed',
    'locations': [
      {'path': 'README.md'},
    ],
    'rawInput': {'path': 'README.md'},
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': '# chord'},
      },
    ],
    'rawOutput': '# chord',
  },
  {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': 'Read it.'},
  },
  {
    'sessionUpdate': 'user_message_chunk',
    'content': {'type': 'text', 'text': 'text'},
  },
  {
    'sessionUpdate': 'agent_message_chunk',
    'content': {
      'type': 'text',
      'text': 'Hello, world. This reply came in chunks.',
    },
  },
];

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The mode a session opens in: `auto` under `--auto-fallback`.
final _firstMode = autoFallback ? 'auto' : 'default';

/// The modes `session/new` and its kin answer with, the older way.
Map<String, Object?> _sessionModes([String sessionId = '']) => noModes
    ? {}
    : {
        'modes': {
          'currentModeId': modes[sessionId] ?? _firstMode,
          'availableModes': availableModes,
        },
      };

/// The mode [asked] comes to on [sessionId]'s model.
Future<String> _fallenBack(
  Client client,
  String sessionId,
  String asked,
) async {
  if (!autoFallback ||
      asked != 'auto' ||
      (models[sessionId] ?? firstModel) != 'fake-small') {
    return asked;
  }
  await client.notify('session/update', {
    'sessionId': sessionId,
    'update': noticeUpdate(autoOff),
  });
  return 'acceptEdits';
}

/// Sends the commands just after the reply, as Claude's adapter does.
void _advertiseCommands(Client client, String sessionId) {
  if (noCommands) return;
  later(
    0,
    () => client.notify('session/update', {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          ...fakeCommands,
          for (final name in alsoCommands)
            {'name': name, 'description': "The agent's own"},
        ],
      },
    }).ignore(),
  );
}

/// Names the session `--title` just after the reply, when given.
void _titleAtStart(Client client, String sessionId) {
  final title = titleAtStart;
  if (title == null) return;
  later(
    0,
    () => client.notify('session/update', {
      'sessionId': sessionId,
      'update': {'sessionUpdate': 'session_info_update', 'title': title},
    }).ignore(),
  );
}

final _ownPart = RegExp(
  r'^<team name="[^"]*" role="(?:lead|member)"(?: member="[^"]*")?>\n([\s\S]*?)\n<\/team>\n+(?!<message )',
);
final _teamPart = RegExp(
  r'^<team name="[^"]*" role="(lead|member)"(?: member="([^"]*)")?>\n([\s\S]*?)\n<\/team>\n',
);
final _wrappedMessage = RegExp(
  r'^<message from="([^"]*)"(?: monitor="[^"]*")?>\n([\s\S]*)\n<\/message>$',
);

/// Plays a prompt as a turn of the session's: the one `session/prompt`
/// asks for, or one a steer started with no turn running.
Future<Map<String, Object?>> _playPrompt(
  Client client,
  String sessionId,
  List<Object?> prompt, [
  Future<void>? answered,
]) async {
  if (hang == 'turn') await _never();

  heard(sessionId, _promptText(prompt));

  // An adapter that starts its own turn does not stop it for a prompt.
  final alongside = steering == 'codex' && _turns.containsKey(sessionId);
  _turns[sessionId]?.abort();
  final controller = Aborter();
  _turns[sessionId] = controller;

  final (:runs, text: whole) = splitContext(_promptText(prompt));
  final cutNote = _cutNote.firstMatch(whole.trimLeft());
  final text = cutNote == null
      ? whole
      : whole.trimLeft().substring(cutNote.group(0)!.length);
  final opened = text.trim();
  final ownPart = _ownPart.firstMatch(opened);
  final asked = ownPart == null
      ? opened
      : opened.substring(ownPart.group(0)!.length);
  if (ownPart != null) {
    teamParts[sessionId] = (from: 'the person', text: ownPart.group(1)!);
  }

  final named = _unsaid(asked);
  final scenario = _isScenario(named) ? named! : _fallback;
  final turn = Turn(client, sessionId, controller.signal);

  try {
    _playing[sessionId] = turn;
    await (answered ?? Future<void>.value());
    // Claude's adapter runs a prompt only after its own compaction.
    await afterIdleCompaction(sessionId, controller.signal);

    if (alongside) await turn.say(['Started alongside a turn still playing. ']);
    if (cutNote != null) {
      await turn.say([
        "Received chord's note: ${cutNote.group(1)!.split('\n').first}\n\n",
      ]);
    }
    for (final run in runs) {
      await turn.say([
        'Received `${run.command}`: ${run.stdout.split('\n').first}\n\n',
      ]);
    }
    for (final line in _receivedLines(prompt)) {
      await turn.say([line]);
    }

    final team = _teamPart.firstMatch(asked);
    final wrapped = team == null
        ? asked
        : asked.substring(team.group(0)!.length);
    final message = _wrappedMessage.firstMatch(wrapped);
    final said = _unsaid(message?.group(2)?.trim());
    final role = team == null ? null : 'team${team.group(2) ?? team.group(1)}';

    if (message != null) {
      senders[sessionId] = message.group(1)!.split(' · ').first;
    }
    if (team != null && message != null) {
      teamParts[sessionId] = (
        from: message.group(1)!.split(' · ').first,
        text: team.group(3)!,
      );
    }

    final String stopReason;
    if (message != null && _isScenario(said)) {
      stopReason = await _playOf(said!)(turn);
    } else if (message != null && _isScenario(role)) {
      stopReason = await _playOf(role!)(turn);
    } else if (message != null) {
      stopReason = await _playMessage(turn, message.group(1)!, asked);
    } else {
      stopReason =
          await _playCommand(turn, asked) ??
          await () {
            final again = proposing.remove(sessionId);
            return again != null && !_isScenario(asked)
                ? _playOf(again)(turn)
                : _playOf(scenario)(turn);
          }();
    }

    // A message steered in after the last step is read before the end.
    await turn.read();

    if (holdReply && message != null) await gateOpened(turn, gateRelease);

    if (turn.usage == null && stopReason == 'end_turn' && !noUsage) {
      await _reportUsage(turn);
    }

    return turn.usage == null
        ? {'stopReason': stopReason}
        : {'stopReason': stopReason, 'usage': turn.usage};
  } catch (error) {
    if (controller.signal.aborted) return {'stopReason': 'cancelled'};
    rethrow;
  } finally {
    turn.end();
    if (_turns[sessionId] == controller) {
      _turns.remove(sessionId);
      _playing.remove(sessionId);
    }
  }
}

/// How a session was opened, as `opened` says it (CHD-629).
Map<String, Object?> _opened(
  String method,
  Object? meta, [
  List<Object?>? initial,
]) => {
  'method': method,
  'meta': ?meta,
  'configOptions': ?initial,
  if (initialOptions != null) 'sessionOptions': _optionsAsked,
};

/// The sessions `--auth-required prompt` refused a prompt of already.
final _promptsRefused = <String>{};

/// How many `session/options` requests the fake has heard.
var _optionsAsked = 0;

/// `session/new`'s initial entries, as `--options` takes them.
Future<void> _applyInitial(
  Client client,
  String sessionId,
  List<Object?> entries,
) async {
  if (entries.isEmpty || initialOptions == null) return;
  final ids = {for (final entry in entries) (entry as Map)['configId']};
  if (ids.length != entries.length || initialOptions == 'reject') {
    throw RequestError.invalidParams(
      null,
      'The fake agent takes no such initial configOptions.',
    );
  }
  if (initialOptions == 'ignore') return;
  for (final entry in entries.cast<Map<String, Object?>>()) {
    try {
      await _setConfig(client, {
        'sessionId': sessionId,
        'configId': entry['configId'],
        'value': '${entry['value']}',
      });
    } catch (_) {}
  }
}

/// The ways in `--auth-required methods` offers at `initialize`.
const _authMethods = [
  {
    'id': 'fake-login',
    'name': 'Log in with the fake',
    'description': 'Run `fake login` in the terminal',
  },
  {'id': 'fake-sso', 'name': 'Log in with SSO'},
];

/// cursor-cloud's one way in, as `--auth-required cloud` offers it.
const cloudAuthMethods = [
  {
    'id': 'cursor-login',
    'name': 'Cursor login',
    'description':
        'Run `npx -y @chorded/cursor-cloud-acp@0.1.0 login` in a terminal, '
        'or set CURSOR_API_KEY',
  },
];

/// Refuses a session request under `--auth-required` (CHD-435).
Future<void> _refuseUnsigned(Client client, Object? requestId) async {
  switch (authRequired) {
    case 'methods':
      throw RequestError.authRequired(
        null,
        'run `fake login` from your terminal, or set FAKE_API_KEY',
      );
    case 'bare':
      throw RequestError.authRequired();
    case 'cloud':
      throw RequestError(-32000, 'Not signed in to Cursor.');
    case 'link' || 'linkother':
      final answer = await client.request('elicitation/create', {
        'requestId': requestId,
        'mode': 'url',
        'elicitationId': const Uuid().v4(),
        'message': 'Sign in to the fake to continue',
        'url': linkUrl,
      });
      if (answer['action'] != 'accept') {
        throw authRequired == 'link'
            ? RequestError.authRequired(
                null,
                'Sign-in was cancelled. Retry to sign in.',
              )
            : RequestError(-32603, 'The fake could not open its session.');
      }
  }
}

/// Refuses a session request as `--start-fails` says.
void _refuseSession(String method) {
  if (startFails == 'notacp') {
    throw RequestError(-32601, 'Method not found: $method');
  }
  if (startFails == 'alias' && method == 'session/new') {
    throw RequestError(
      -32602,
      'session/new requires `agentAlias` (alias of a configured '
      '[agents.<alias>] entry)',
    );
  }
}

/// Sets one of a session's config options.
Future<Map<String, Object?>> _setConfig(
  Client client,
  Map<String, Object?> params,
) async {
  final sessionId = params['sessionId'] as String;
  final askedId = params['configId'] as String;
  final configId = configNameOf(askedId) ?? '';

  if (hang == 'config' || (hang == 'effort' && configId == 'effort')) {
    await _never();
  }
  if (configDelayMs > 0) {
    await Future<void>.delayed(
      Duration(milliseconds: milliseconds(configDelayMs)),
    );
  }

  final value = '${params['value']}';
  final model = models[sessionId] ?? firstModel;
  final List<Map<String, Object?>> offered = configId == 'model'
      ? availableModels
      : configId == 'mode' && !noModes
      ? [
          for (final mode in availableModes) {'value': mode['id']},
        ]
      : configId == 'effort' && !noConfig
      ? effortsOf(model)
      : configId == 'fast' && hasFast(model)
      ? fastValues
      : configId == 'permission' && dimcodePermission != null
      ? dimcodePermissions
      : const [];

  if (!offered.any((entry) => entry['value'] == value)) {
    throw RequestError.invalidParams(null, '$askedId cannot be $value');
  }
  if (configId == 'effort' && refuseConfig) {
    throw RequestError(-32603, 'The fake agent holds its effort.');
  }
  if (configId == 'mode' && locked.contains(sessionId)) {
    throw RequestError(-32603, 'The fake agent holds its mode.');
  }

  final chosen = switch (configId) {
    'model' => models,
    'mode' => modes,
    'permission' => permissions,
    'fast' => fasts,
    _ => efforts,
  };
  chosen[sessionId] = configId == 'mode'
      ? await _fallenBack(client, sessionId, value)
      : value;

  if (configId == 'model') return _switchedModel(client, sessionId);
  // Codex's adapter says nothing of the mode it moved to.
  if (configId == 'mode' && silentSetMode) return {};
  return {'configOptions': configOptions(sessionId)};
}

Map<String, Object?> _initialize(Map<String, Object?> params, Client client) =>
    {
      'protocolVersion': 1,
      if (authRequired == 'methods') 'authMethods': _authMethods,
      if (authRequired == 'cloud') 'authMethods': cloudAuthMethods,
      'agentCapabilities': {
        if (authStatusMode != null) 'auth': {'status': <String, Object?>{}},
        'loadSession': !noLoad,
        'mcpCapabilities': mcpTransports,
        'promptCapabilities': {
          'image': !noImages,
          'embeddedContext': embeddedContext,
        },
        'sessionCapabilities': {
          'list': <String, Object?>{},
          if (resumeOnly) 'resume': <String, Object?>{},
          if (forks) 'fork': <String, Object?>{},
          if (initialOptions != null) 'options': <String, Object?>{},
          if (setTitleMode != null) 'title': <String, Object?>{},
        },
      },
      // Steering as Claude's adapter, it names itself as that adapter does.
      'agentInfo': {
        'name': steering == 'claude' || adapter == 'claude'
            ? '@agentclientprotocol/claude-agent-acp'
            : 'chord-fake-agent',
        'version': '0.0.0',
      },
      if (steering != null)
        '_meta': {
          'steering': {'supported': true},
        },
    };

/// The fake's handlers, by method.
Map<String, RequestSpec> _requests() => {
  'initialize': RequestSpec(parse: parseInitialize, (context) async {
    readCapabilities(context.params);
    if (authPush) pushStatus(context.client);
    if (authPushEarly) {
      await context.client.notify('auth/status_update', apiKey);
    }
    if (hang == 'start') await _never();
    return _initialize(context.params, context.client);
  }),
  'authenticate': RequestSpec(parse: parseAuthenticate, empty: true, (_) => {}),
  'session/new': RequestSpec(parse: parseNewSession, (context) async {
    final params = context.params;
    final client = context.client;
    _refuseSession('session/new');
    await _refuseUnsigned(client, context.requestId);

    final sessionId = sessionIdFlag ?? const Uuid().v4();
    final cwd = params['cwd'] as String;
    modes[sessionId] = _firstMode;
    mcpServers[sessionId] = params['mcpServers'] as List<Object?>;
    openedWith[sessionId] = _opened(
      'session/new',
      params['_meta'],
      params['configOptions'] as List<Object?>?,
    );
    cwds[sessionId] = cwd;
    _created.add({'sessionId': sessionId, 'cwd': cwd});
    await _applyInitial(
      client,
      sessionId,
      params['configOptions'] as List<Object?>? ?? const [],
    );

    final first = firstMessage;
    if (first != null) {
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': {
          'sessionUpdate': 'agent_message_chunk',
          'messageId': const Uuid().v4(),
          'content': {'type': 'text', 'text': first},
        },
      });
    }
    final notice = startNotice;
    if (notice != null) {
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': noticeUpdate({'severity': 'warning', 'title': notice}),
      });
    }

    _advertiseCommands(client, sessionId);
    _titleAtStart(client, sessionId);
    return {
      'sessionId': sessionId,
      ..._sessionModes(sessionId),
      'configOptions': configOptions(sessionId),
    };
  }),
  'auth/status': RequestSpec(
    parse: parseMetaOnly,
    (context) => authStatus(context.client),
  ),
  'session/set_title': RequestSpec(
    parse: parseSetTitle,
    (context) => setTitle(context.client, context.params),
  ),
  // Counted, for a test that chord never asks it (CHD-629).
  'session/options': RequestSpec(parse: parseSessionOptions, (_) {
    _optionsAsked += 1;
    return {..._sessionModes(), 'configOptions': configOptions('')};
  }),
  'session/list': RequestSpec(parse: parseListSessions, (context) {
    final cwd = context.params['cwd'];
    return {
      'sessions': [
        for (final session in _created.reversed)
          if (cwd == null || cwd == '' || session['cwd'] == cwd) session,
      ],
    };
  }),
  'session/load': RequestSpec(parse: parseLoadSession, empty: true, (
    context,
  ) async {
    final params = context.params;
    final client = context.client;
    final sessionId = params['sessionId'] as String;
    _refuseSession('session/load');
    await _refuseUnsigned(client, context.requestId);
    if (environment['CHORD_FAKE_REFUSE_LOAD'] == '1' ||
        !_uuid.hasMatch(sessionId)) {
      throw RequestError.resourceNotFound(sessionId);
    }
    modes[sessionId] = _firstMode;
    mcpServers[sessionId] = params['mcpServers'] as List<Object?>;
    openedWith[sessionId] = _opened('session/load', params['_meta']);
    cwds[sessionId] = params['cwd'] as String;
    loadMarks[sessionId] = const Uuid().v4().substring(0, 8);
    // The whole past goes out before the reply.
    for (final update in _history) {
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': update,
      });
    }
    _advertiseCommands(client, sessionId);
    _titleAtStart(client, sessionId);
    return {
      ..._sessionModes(sessionId),
      'configOptions': configOptions(sessionId),
    };
  }),
  'session/fork': RequestSpec(parse: parseForkSession, (context) async {
    final params = context.params;
    final client = context.client;
    final from = params['sessionId'] as String;
    _refuseSession('session/fork');
    await _refuseUnsigned(client, context.requestId);
    if (environment['CHORD_FAKE_HANG_FORK'] == '1') await _never();
    if (!forks ||
        environment['CHORD_FAKE_REFUSE_FORK'] == '1' ||
        !_uuid.hasMatch(from)) {
      throw RequestError.resourceNotFound(from);
    }
    final sessionId = const Uuid().v4();
    final model = forkModel;
    if (model != null) models[sessionId] = model;
    modes[sessionId] = _firstMode;
    mcpServers[sessionId] = params['mcpServers'] as List<Object?>? ?? [];
    openedWith[sessionId] = {
      ..._opened('session/fork', params['_meta']),
      'from': from,
    };
    final cwd = params['cwd'] as String;
    cwds[sessionId] = cwd;
    _created.add({'sessionId': sessionId, 'cwd': cwd});
    _advertiseCommands(client, sessionId);
    _titleAtStart(client, sessionId);
    return {
      'sessionId': sessionId,
      ..._sessionModes(sessionId),
      'configOptions': configOptions(sessionId),
    };
  }),
  'session/resume': RequestSpec(parse: parseResumeSession, (context) async {
    final params = context.params;
    final client = context.client;
    final sessionId = params['sessionId'] as String;
    _refuseSession('session/resume');
    await _refuseUnsigned(client, context.requestId);
    if (!resumeOnly ||
        environment['CHORD_FAKE_REFUSE_LOAD'] == '1' ||
        !_uuid.hasMatch(sessionId)) {
      throw RequestError.resourceNotFound(sessionId);
    }
    modes[sessionId] = _firstMode;
    mcpServers[sessionId] = params['mcpServers'] as List<Object?>? ?? [];
    openedWith[sessionId] = _opened('session/resume', params['_meta']);
    cwds[sessionId] = params['cwd'] as String;
    loadMarks[sessionId] = const Uuid().v4().substring(0, 8);
    _advertiseCommands(client, sessionId);
    _titleAtStart(client, sessionId);
    if (cycleOnResume) runCycle(client, sessionId);
    return {
      ..._sessionModes(sessionId),
      'configOptions': configOptions(sessionId),
    };
  }),
  // Answered as Claude's adapter answers it: the new mode goes out in the
  // config options before the reply.
  'session/set_mode': RequestSpec(parse: parseSetMode, empty: true, (
    context,
  ) async {
    final params = context.params;
    final sessionId = params['sessionId'] as String;
    final modeId = params['modeId'] as String;
    if (hang == 'config') await _never();
    if (noModes) throw RequestError.methodNotFound('session/set_mode');
    if (!availableModes.any((mode) => mode['id'] == modeId)) {
      throw RequestError.invalidParams(
        null,
        'Mode $modeId is not available in this session',
      );
    }
    if (locked.contains(sessionId)) {
      throw RequestError(-32603, 'The fake agent holds its mode.');
    }
    modes[sessionId] = await _fallenBack(context.client, sessionId, modeId);
    if (silentSetMode || configInResponses) return {};
    await context.client.notify('session/update', {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'config_option_update',
        'configOptions': configOptions(sessionId),
      },
    });
    return {};
  }),
  'session/set_config_option': RequestSpec(parse: parseSetConfigOption, (
    context,
  ) {
    final sessionId = context.params['sessionId'] as String;
    configsHeard[sessionId] = [...?configsHeard[sessionId], context.params];
    return _setConfig(context.client, context.params);
  }),
  // The older way to pick a model, which Claude's adapter still answers.
  'session/set_model': RequestSpec((context) async {
    final params = context.params;
    if (hang == 'config') await _never();
    final modelId = params['modelId'];
    if (!availableModels.any((model) => model['value'] == modelId)) {
      throw RequestError.invalidParams(
        null,
        'Model ${_js(modelId)} is not available',
      );
    }
    models['${params['sessionId']}'] = '$modelId';
    return {};
  }),
  'session/prompt': RequestSpec(parse: parsePrompt, (context) async {
    final params = context.params;
    final client = context.client;
    final sessionId = params['sessionId'] as String;
    final prompt = params['prompt'] as List<Object?>;
    // Signed out, the first prompt is refused.
    if (authRequired == 'prompt' && _promptsRefused.add(sessionId)) {
      throw RequestError.authRequired();
    }

    final gateDir = p.join(cwds[sessionId] ?? '.', '.fake-gate');
    final capture = File(p.join(gateDir, 'capture-prompt'));
    if (capture.existsSync()) {
      capture.deleteSync();
      File(p.join(gateDir, 'prompt.json')).writeAsStringSync(stringify(prompt));
    }

    final held = _heldCosts.remove(sessionId);
    if (held != null) {
      await client.notify('session/update', {
        'sessionId': sessionId,
        'update': held,
      });
    }

    final answered = _playPrompt(client, sessionId, prompt);
    _prompted[sessionId] = answered;
    try {
      return await answered;
    } finally {
      if (identical(_prompted[sessionId], answered)) {
        _prompted.remove(sessionId);
      }
    }
  }),
  // Steering as `--steering` names the adapter.
  '_session/steering': RequestSpec((context) async {
    final params = context.params;
    final client = context.client;
    if (steering == null) {
      throw RequestError.methodNotFound('_session/steering');
    }
    final sessionId = '${params['sessionId']}';
    final prompt = params['prompt'] is List
        ? params['prompt'] as List<Object?>
        : const <Object?>[];
    emitSteer(sessionId);
    if (steerRefuse) {
      return {'outcome': 'promptRequired', 'reason': 'noRunningTurn'};
    }
    final late = steerLate ? _prompted[sessionId] : null;
    if (late != null) {
      try {
        await late;
      } catch (_) {}
    }
    final turn = _playing[sessionId];
    if (turn != null) {
      heard(sessionId, _promptText(prompt));
      turn.steer(_promptText(prompt), _receivedLines(prompt));
      return {'outcome': 'injected'};
    }
    final meta = params['_meta'];
    final idleBehavior = meta is Map && meta['steering'] is Map
        ? (meta['steering'] as Map)['idleBehavior']
        : null;
    if (steering == 'opencode' ||
        (steering != 'codex' && idleBehavior == 'promptRequired')) {
      return {'outcome': 'promptRequired', 'reason': 'noRunningTurn'};
    }
    // Answered once the turn it started is running, before it says
    // anything.
    final answering = late == null
        ? Future<void>.value()
        : Future<void>.delayed(
            Duration(milliseconds: milliseconds(stepMs * 20)),
          );
    _playPrompt(client, sessionId, prompt, answering).ignore();
    await answering;
    return {'outcome': 'startedNewTurn'};
  }),
};

Map<String, NotificationSpec> _notifications() => {
  'session/cancel': NotificationSpec(parse: parseSessionId, (params, client) {
    final sessionId = params['sessionId'] as String;
    // A Claude subagent's own id stops that one alone.
    claudeChildren[sessionId]?.call().ignore();
    final turn = _turns[sessionId];
    if (turn == null && !claudeChildren.containsKey(sessionId)) {
      strayCancels[sessionId] = (strayCancels[sessionId] ?? 0) + 1;
      if (sayCancels) {
        client.notify('session/update', {
          'sessionId': sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': 'Cancel heard with no turn.'},
          },
        }).ignore();
      }
    }
    turn?.abort();
  }),
};

/// A wedged agent ignores SIGTERM and goes only with SIGKILL or its parent.
void _wedge() {
  ProcessSignal.sigterm.watch().listen((_) {});
  final parent = _parentOf(pid);
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    final now = _parentOf(pid);
    if (parent == 1 || (now != null && now != parent)) exit(1);
  });
}

/// The parent of process [id], as `ps` says; null when it cannot tell.
int? _parentOf(int id) {
  try {
    final result = Process.runSync('ps', ['-o', 'ppid=', '-p', '$id']);
    return int.tryParse('${result.stdout}'.trim());
  } on ProcessException {
    return null;
  }
}

Future<void> main(List<String> arguments) async {
  args = arguments;
  try {
    readOptions();
    _fallback;
  } on StateError catch (error) {
    stderr.writeln('error: ${error.message}');
    await stderr.flush();
    exit(1);
  }

  if (hang != null) _wedge();

  // An agent that cannot start goes before it reads a line (CHD-454).
  if (startFails == 'traceback') {
    stderr.write(
      [
        'Traceback (most recent call last):',
        for (var n = 0; n < 60; n++) ...[
          '  File "/opt/agent/lib/python3.12/site-packages/agent/module_$n.py", '
              'line ${n + 10}, in <module>',
          '    from .module_${n + 1} import run',
        ],
        tracebackError,
        '',
      ].join('\n'),
    );
    await stderr.flush();
    exit(1);
  }
  if (startFails == 'stdout') {
    stdout.write(
      'fake-agent is no longer maintained. Please use its successor.\n',
    );
    await stdout.flush();
    exit(0);
  }

  final connection = Connection.serve(
    stdin,
    stdout.add,
    stdout.flush,
    requests: _requests(),
    notifications: _notifications(),
  );

  // The client closing stdin is how an ACP agent is told to go.
  await connection.closed;
  for (final turn in _turns.values) {
    turn.abort();
  }
  lifetime.abort();
  cancelTimeouts();
}
