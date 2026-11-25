// Permissions: a write asked for, with three options or with two of one
// kind, and MCP calls asked for by their name and arguments alone, one of
// them a file too long for the box, as the original's
// scenarios/permissions.ts.
import 'dart:async';
import 'dart:math' as math;

import '../../release_notes.dart';
import '../options.dart';
import '../rpc.dart';
import '../turn.dart';

Map<String, Object?> _option(String id, String name, String kind) => {
  'optionId': id,
  'name': name,
  'kind': kind,
};

Map<String, Object?> _outcome(Map<String, Object?> answer) =>
    (answer['outcome'] as Map?)?.cast<String, Object?>() ?? const {};

String _js(Object? value) => value == null ? 'undefined' : '$value';

/// Asks for permission to call [server]'s [tool] with [rawInput], as
/// claude-agent-acp asks for an MCP tool, and says which option came back.
Future<String> _askMcp(
  Turn turn,
  String server,
  String tool,
  Map<String, Object?> rawInput,
) async {
  final id = turn.callId(tool);
  final toolCall = {
    'toolCallId': id,
    'title': 'mcp__${server}__$tool',
    'kind': 'other',
    'status': 'pending',
    'rawInput': rawInput,
  };
  await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

  final answer = await turn.client.request('session/request_permission', {
    'sessionId': turn.sessionId,
    'toolCall': toolCall,
    'options': [
      _option('allow', 'Yes', 'allow_once'),
      _option(
        'always',
        "Yes, and don't ask again for $server - $tool commands",
        'allow_always',
      ),
      _option(
        'deny',
        'No, and tell Claude what to do differently',
        'reject_once',
      ),
    ],
  });
  final outcome = _outcome(answer);
  if (outcome['outcome'] == 'cancelled') return 'cancelled';

  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    'status': outcome['optionId'] == 'deny' ? 'failed' : 'completed',
  });
  await turn.say(['Permission: ${_js(outcome['optionId'])}.']);
  return 'end_turn';
}

/// Asks for permission to write a file with [options], and says which
/// option came back, by its id.
Future<String> _askPermission(
  Turn turn,
  List<Map<String, Object?>> options, {
  bool untilSteered = false,
  bool multiple = false,
}) async {
  final id = turn.callId('write');
  final toolCall = {
    'toolCallId': id,
    'title': multiple ? 'Update files' : 'Write notes.txt',
    'kind': 'edit',
    'status': 'pending',
    'locations': multiple
        ? <Object?>[]
        : [
            {'path': 'notes.txt'},
          ],
  };
  await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

  // The request carries the diff and the arguments, as Claude Code's
  // adapter asks for a write.
  final answer = await turn.client.request('session/request_permission', {
    'sessionId': turn.sessionId,
    'toolCall': {
      ...toolCall,
      'content': multiple
          ? [
              {
                'type': 'diff',
                'path': 'src/first.ts',
                'oldText': 'old value\n',
                'newText': 'new value\n',
              },
              {
                'type': 'diff',
                'path': 'src/second.ts',
                'oldText': null,
                'newText': 'created value\n',
              },
            ]
          : [
              {'type': 'diff', 'path': 'notes.txt', 'newText': 'notes\n'},
            ],
      if (!multiple)
        'rawInput': {'file_path': 'notes.txt', 'content': 'notes\n'},
    },
    'options': options,
  });
  final outcome = _outcome(answer);
  if (outcome['outcome'] == 'cancelled') return 'cancelled';

  final allowed = outcome['optionId'] != 'deny';
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': id,
    'status': allowed ? 'completed' : 'failed',
  });

  // A model's next step comes only after the tool's result is in.
  while (untilSteered && !turn.steered) {
    await pause(turn.signal);
  }

  await turn.say(['Permission: ${_js(outcome['optionId'])}.']);
  return 'end_turn';
}

/// The session's own agent asking, with no turn running, to write [file],
/// and, silent for [saysAfterMs] after the answer, ending the call.
Future<String> _askBetween(
  Turn turn,
  String file, [
  num saysAfterMs = 0,
]) async {
  final client = turn.client;
  final sessionId = turn.sessionId;
  Future<void> update(Update update) => client.notify('session/update', {
    'sessionId': sessionId,
    'update': update,
  });
  final toolCall = {
    'toolCallId': turn.callId('write'),
    'title': 'Write $file',
    'kind': 'edit',
    'status': 'pending',
    'locations': [
      {'path': file},
    ],
  };
  await update({'sessionUpdate': 'tool_call', ...toolCall});

  final answer = await client.request('session/request_permission', {
    'sessionId': sessionId,
    'toolCall': toolCall,
    'options': [
      _option('allow', 'Allow', 'allow_once'),
      _option('deny', 'Deny', 'reject_once'),
    ],
  }, cancellation: lifetime.signal);
  final outcome = _outcome(answer);
  final chosen = outcome['outcome'] == 'selected'
      ? _js(outcome['optionId'])
      : 'cancelled';

  await pause(lifetime.signal, saysAfterMs);
  await update({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCall['toolCallId'],
    'status': chosen == 'allow' ? 'completed' : 'failed',
  });
  return chosen;
}

/// Text from the session's own agent with no turn running.
Future<void> _sayBetween(Turn turn, String text) =>
    turn.client.notify('session/update', {
      'sessionId': turn.sessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
      },
    });

final _allowDeny = [
  _option('allow', 'Allow', 'allow_once'),
  _option('deny', 'Deny', 'reject_once'),
];

final _allowAlwaysDeny = [
  _option('allow', 'Allow', 'allow_once'),
  _option('always', 'Always allow', 'allow_always'),
  _option('deny', 'Deny', 'reject_once'),
];

Future<String> _overlapAsk(Turn turn) async {
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': 'overlapask-a',
    'title': '`sleep 2`',
    'kind': 'execute',
    'status': 'in_progress',
  });
  await pause(turn.signal, stepMs * 20);
  final stop = await _askPermission(turn, _allowDeny);
  if (stop == 'cancelled') return stop;
  await pause(turn.signal, stepMs * 20);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': 'overlapask-a',
    'status': 'completed',
  });
  return 'end_turn';
}

Map<String, Object?> _bigWrite(String path, String mode) => {
  'path': path,
  'content': releaseNotes,
  'mode': mode,
};

final Map<String, Play> permissionPlays = {
  // A write asked for while another call stays open.
  'overlapask': _overlapAsk,

  // Keep the turn open after its last call so a held steer can reach it.
  'overlapasksteer': (turn) async {
    final stop = await _overlapAsk(turn);
    if (stop != 'cancelled') await steeredIn(turn, 1);
    return stop;
  },

  'permission': (turn) => _askPermission(turn, _allowAlwaysDeny),

  'multidiffask': (turn) =>
      _askPermission(turn, _allowAlwaysDeny, multiple: true),

  // A request carrying metadata of its own and on its call.
  'permissionmeta': (turn) async {
    final answer = await turn.client.request('session/request_permission', {
      'sessionId': turn.sessionId,
      'toolCall': {
        'toolCallId': turn.callId('write'),
        '_meta': {'fake/call': 1},
      },
      'options': [_option('deny', 'Deny', 'reject_once')],
      '_meta': {'fake/asked': 1},
    });
    return _outcome(answer)['outcome'] == 'cancelled'
        ? 'cancelled'
        : 'end_turn';
  },

  // A request naming a session this agent never announced.
  'strangerask': (turn) async {
    final answer = await turn.client.request('session/request_permission', {
      'sessionId': 'stranger-session',
      'toolCall': {'toolCallId': turn.callId('write')},
      'options': _allowDeny,
    });
    final outcome = answer['outcome'];
    await turn.say([
      'Answered: ${outcome == null ? 'undefined' : stringify(outcome)}',
    ]);
    return 'end_turn';
  },

  // As `permission`, its next step waiting for a message steered in.
  'permissionsteer': (turn) =>
      _askPermission(turn, _allowDeny, untilSteered: true),

  // Two options of one kind, as Codex's adapter offers two ways to allow
  // once.
  'twins': (turn) => _askPermission(turn, [
    _option('allow', 'Allow once', 'allow_once'),
    _option('allow-here', 'Allow once in this folder', 'allow_once'),
    _option('deny', 'Deny', 'reject_once'),
  ]),

  // As claude-agent-acp asks for an MCP tool.
  'mcpask': (turn) => _askMcp(turn, 'chord', 'monitor', {
    'command': 'tail -f dev.log | grep --line-buffered -E "ERROR|WARN"',
    'description': 'dev server errors',
    'timeout_ms': 600000,
  }),

  // An MCP write whose file runs past any window (CHD-246).
  'bigask': (turn) => _askMcp(
    turn,
    'files',
    'write_file',
    _bigWrite('docs/release.md', 'overwrite'),
  ),

  // bigask's write, its turn ending with it still open (CHD-158 §8).
  'bigaskleft': (turn) async {
    final toolCall = {
      'toolCallId': turn.callId('write_file'),
      'title': 'mcp__files__write_file',
      'kind': 'other',
      'status': 'pending',
      'rawInput': _bigWrite('docs/release.md', 'overwrite'),
    };
    await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

    () async {
      try {
        final answer = await turn.client.request('session/request_permission', {
          'sessionId': turn.sessionId,
          'toolCall': toolCall,
          'options': [
            _option('allow', 'Yes', 'allow_once'),
            _option('deny', 'No', 'reject_once'),
          ],
        });
        final outcome = _outcome(answer);
        final chosen = outcome['outcome'] == 'selected'
            ? _js(outcome['optionId'])
            : 'cancelled';
        await _sayBetween(turn, 'Permission: $chosen.');
      } catch (_) {
        // The client went before it was answered.
      }
    }();

    await pause(turn.signal, stepMs * 100);
    await turn.say(['I asked; the turn ends with it open.']);
    return 'end_turn';
  },

  // Two such writes asked at once, told apart by their paths.
  'bigasktwice': (turn) async {
    final answers = await Future.wait([
      _askMcp(
        turn,
        'files',
        'write_file',
        _bigWrite('docs/release.md', 'overwrite'),
      ),
      _askMcp(
        turn,
        'files',
        'write_file',
        _bigWrite('docs/changes.md', 'append'),
      ),
    ]);
    return answers.contains('cancelled') ? 'cancelled' : 'end_turn';
  },

  // Asks in its turn, then ends the turn with the request still open
  // (CHD-158, the owner's Q44).
  'leftask': (turn) async {
    () async {
      try {
        final chosen = await _askBetween(turn, 'notes/left.md');
        await _sayBetween(turn, 'Permission: $chosen.');
      } catch (_) {
        // The client went before it was answered.
      }
    }();
    await pause(turn.signal, stepMs * 100);
    await turn.say(['I asked; the turn ends with it open.']);
    return 'end_turn';
  },

  // The session's own agent asks once its turn has answered (CHD-158).
  'mainbetween': (turn) async {
    () async {
      try {
        await pause(lifetime.signal, stepMs * 100);
        final chosen = await _askBetween(turn, 'notes/report.md');
        await _sayBetween(turn, 'Permission: $chosen.');
      } catch (_) {
        // The client went before it was answered.
      }
    }();
    await turn.say(['I will write the report once the build is done.']);
    return 'end_turn';
  },

  // As mainbetween, then a second request at once, silent half a second
  // after its answer.
  'mainbetweentwice': (turn) async {
    () async {
      try {
        await pause(lifetime.signal, stepMs * 100);
        await _askBetween(turn, 'notes/report.md');
        // Within chord's second of quiet at any pace.
        final chosen = await _askBetween(
          turn,
          'notes/summary.md',
          math.min(stepMs * 100, 500),
        );
        await _sayBetween(turn, 'Second: $chosen.');
      } catch (_) {
        // The client went before it was answered.
      }
    }();
    await turn.say(['I will write the report once the build is done.']);
    return 'end_turn';
  },
};
