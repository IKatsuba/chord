// Subagents in the draft form Codex's adapter sent before 2.4, and in ACP's
// own `subagent_update` as Claude's and Codex's 2.4 send it, as the
// original's scenarios/subagents.ts.
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../client.dart';
import '../options.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';

/// How long a subagent takes between steps of its work: 40 steps.
num get _subagentStepMs => stepMs * 40;

/// How long its last subagent outlives the turn: 400 steps.
num get _subagentAfterMs => stepMs * 400;

/// The subagents a turn has started and not ended, to cancel with it: each
/// by its session id, with its parent's turn.
typedef _Children = Map<String, Turn>;

/// How many subagents this process has started, numbered across every
/// session, as a subagent's session id names it across the connection.
var _subagentCount = 0;

/// This process's own mark in its subagents' ids, so a fake started on a
/// resumed session never takes the id of one an earlier process started.
final _run = const Uuid().v4();

/// A new subagent's session id, opaque as an adapter's.
String _subagentId() => 'agent-$_run-${++_subagentCount}';

/// [value] as a template literal writes it.
String _js(Object? value) => value == null ? 'undefined' : '$value';

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// Says subagents go only to a client that takes them.
Future<String> _untaken(Turn turn) async {
  await turn.say(['Subagents go only to a client that takes them.']);
  return 'end_turn';
}

/// Starts a subagent under [parent], as Codex's adapter before 2.4
/// announces one: a `subagent_spawned` on the parent's session, after which
/// the subagent's work goes out under a session id of its own.
Future<Turn> _spawn(
  Turn parent,
  _Children open,
  String name,
  String task,
) async {
  final child = Turn(parent.client, _subagentId(), parent.signal);
  await parent.send({
    'sessionUpdate': 'subagent_spawned',
    'subagentSessionId': child.sessionId,
    'name': name,
    'task': task,
    'capabilities': <String, Object?>{},
  });
  open[child.sessionId] = parent;
  return child;
}

/// Ends a subagent as the adapters do, with a `subagent_state_update` on
/// its parent's session; sent at once, as a cancelled turn's are.
Future<void> _finish(String childId, _Children open, String state) async {
  final parent = open.remove(childId);
  if (parent == null) return;
  await parent.client.notify('session/update', {
    'sessionId': parent.sessionId,
    'update': {
      'sessionUpdate': 'subagent_state_update',
      'subagentSessionId': childId,
      'state': state,
    },
  });
}

/// A tool call that runs and ends as [status], with [text] as its output.
Future<String> _call(
  Turn turn,
  String name,
  Map<String, Object?> call,
  String status, [
  String? text,
]) async {
  final toolCallId = turn.callId(name);
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    ...call,
    'status': 'in_progress',
  });
  if (status == 'in_progress') return toolCallId;
  await pause(turn.signal, _subagentStepMs);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': status,
    if (text != null) 'content': [_text(text)],
  });
  return toolCallId;
}

Update _plan(List<String> steps, int done) => {
  'sessionUpdate': 'plan',
  'entries': [
    for (final (index, content) in steps.indexed)
      {
        'content': content,
        'priority': 'medium',
        'status': index < done
            ? 'completed'
            : index == done
            ? 'in_progress'
            : 'pending',
      },
  ],
};

/// The plan the first subagent of `subagent` works through.
Update _childPlan(int done) => _plan(const [
  'Find the transport',
  'Find the listeners',
  'Write the answer',
], done);

Map<String, Object?> _read(String path) => {
  'title': 'Read $path',
  'kind': 'read',
  'locations': [
    {'path': path},
  ],
};

Map<String, Object?> _outcome(Map<String, Object?> answer) =>
    (answer['outcome'] as Map?)?.cast<String, Object?>() ?? const {};

/// The first subagent of `subagent`: a plan, calls, a subagent of its own,
/// and a write it asks permission for, the answer deciding how it ends.
Future<void> _findSessionLayer(Turn child, _Children open) async {
  await child.think(['Looking for where updates are routed.']);
  await child.send(_childPlan(0));
  await _call(
    child,
    'search',
    {'title': 'Search sessionUpdate in src', 'kind': 'search'},
    'completed',
    'Found 14 files',
  );
  await _call(child, 'read', _read('src/acp/connection.ts'), 'completed');

  final grandchild = await _spawn(
    child,
    open,
    'Read the transport tests',
    'Read tests/acp/connection_test.ts and say what the transport '
        'promises about sessions it did not open.',
  );
  await _call(
    grandchild,
    'read',
    _read('tests/acp/connection_test.ts'),
    'completed',
  );
  await _call(
    grandchild,
    'search',
    {
      'title': 'Search cancel in tests/acp/connection_test.ts',
      'kind': 'search',
    },
    'completed',
    '3 matches',
  );
  await grandchild.say(['Nothing it did not open is promised.']);
  await _finish(grandchild.sessionId, open, 'completed');
  await child.send(_childPlan(1));
  await _call(child, 'read', _read('src/session/session.ts'), 'completed');
  await pause(child.signal, _subagentStepMs);

  final write = child.callId('write');
  final toolCall = {
    'toolCallId': write,
    'title': 'Write notes/routing.md',
    'kind': 'edit',
    'status': 'pending',
    'locations': [
      {'path': 'notes/routing.md'},
    ],
  };
  await child.send({'sessionUpdate': 'tool_call', ...toolCall});
  final answer = _outcome(
    await child.client.request('session/request_permission', {
      'sessionId': child.sessionId,
      'toolCall': toolCall,
      'options': [
        {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        {'optionId': 'always', 'name': 'Always allow', 'kind': 'allow_always'},
        {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
      ],
    }),
  );

  // A request withdrawn is the turn being cancelled, whose cancel follows.
  if (answer['outcome'] == 'cancelled') {
    await pause(child.signal, _subagentAfterMs * 10);
  }

  final allowed =
      answer['outcome'] == 'selected' && answer['optionId'] != 'deny';
  await child.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': write,
    'status': allowed ? 'completed' : 'failed',
  });
  await child.send(_childPlan(3));
  await child.say([
    'The listeners are kept per sessionId in openAgent; ',
    'an id chord did not open is dropped there.',
  ]);
  await _finish(child.sessionId, open, 'completed');
}

/// The second subagent of `subagent`, whose read fails, and it with it.
Future<void> _findToolDrawing(Turn child, _Children open) async {
  await _call(
    child,
    'search',
    {'title': 'Search function Tool in src/ui', 'kind': 'search'},
    'completed',
    'Found 1 file',
  );
  await pause(child.signal, _subagentStepMs);
  await _call(
    child,
    'read',
    _read('src/ui/App.tsx'),
    'failed',
    'File is too large to read whole.',
  );
  await child.say(['Could not read the component.']);
  await _finish(child.sessionId, open, 'failed');
}

/// The plan the parent of `subagentstates` works through.
Update _parentPlan(int done) => _plan(const [
  'Plan the change',
  'Read the session layer',
  'Write the design',
], done);

/// The lone subagent of `subagentstates`: a plan of its own, then five
/// calls, more than a running block shows, held on the last.
Future<void> _readSessionLayer(Turn child, _Children open) async {
  await child.send(_childPlan(0));
  for (final (name, title, path) in const <(String, String, String?)>[
    ('search', 'Search sessionUpdate in src', null),
    ('read', 'Read src/acp/connection.ts', 'src/acp/connection.ts'),
    ('read', 'Read src/session/session.ts', 'src/session/session.ts'),
    ('read', 'Read src/session/conversation.ts', 'src/session/conversation.ts'),
    ('read', 'Read src/session/enrichers.ts', 'src/session/enrichers.ts'),
  ]) {
    await _call(child, name, {
      'title': title,
      'kind': name,
      if (path != null)
        'locations': [
          {'path': path},
        ],
    }, 'completed');
  }
  await pause(child.signal, _subagentAfterMs);
  await child.say(['Routing lives in src/acp/connection.ts.']);
  await _finish(child.sessionId, open, 'completed');
}

/// One of the pair of `subagentstates`, whose calls all succeed.
Future<void> _readAll(Turn child, _Children open, List<String> paths) async {
  for (final path in paths) {
    await _call(child, 'read', _read(path), 'completed');
  }
  await child.say(['Read.']);
  await _finish(child.sessionId, open, 'completed');
}

/// Claude's subagents still at work, to end with a cancelled turn.
typedef _Working = Set<String>;

/// Claude's subagents at work, by session id, each with the stop a
/// `session/cancel` on its own id makes: its work stops, and it reports
/// itself idle and cancelled, its parent's turn going on.
final claudeChildren = <String, Future<void> Function()>{};

/// What `--stop-gate` writes each stop to, and waits on to let it go.
const stopGateStops = 'stops';
const stopGateRelease = 'stop-release';

/// With `--stop-gate`, writes the stop of subagent [id] under [parent] to
/// its session's gate, then waits until the test releases it.
Future<void> _stopGate(Turn parent, String id) async {
  if (!stopGate) return;
  final at = Directory(p.join(cwds[parent.sessionId] ?? '.', gate));
  await at.create(recursive: true);
  await File(
    p.join(at.path, stopGateStops),
  ).writeAsString('$id\n', mode: FileMode.append);
  while (!File(p.join(at.path, stopGateRelease)).existsSync()) {
    await pause(lifetime.signal, stepMs * 2);
  }
}

/// The subagents a stop of their own ended, whose work's abort is no
/// error.
final _stoppedAlone = <String>{};

/// Claude's subagents at work now: a stop of an idle one leaves its end as
/// it was, and one messaged again is at work again.
final _atWork = <String>{};

/// [work] of [child]'s, which its parent waits on: a stop of the child
/// alone ends it quietly, any other failure is the parent's.
Future<void> _alone(Turn child, Future<void> work) async {
  try {
    await work;
  } catch (_) {
    if (!_stoppedAlone.contains(child.sessionId)) rethrow;
  }
}

/// What a call in place of which the adapter sends a message said, as its
/// two views: the sender's on the sender's session, then the recipient's
/// on theirs, each naming the other.
Future<void> _linked(
  Client client,
  String messageId,
  String sender,
  String recipient,
  String text,
) async {
  final message = {
    'sessionUpdate': 'session_message',
    'messageId': messageId,
    'senderSessionId': sender,
    'recipientSessionId': recipient,
    'content': [
      {'type': 'text', 'text': text},
    ],
  };
  await client.notify('session/update', {
    'sessionId': sender,
    'update': {...message, 'recipientMessageId': messageId},
  });
  await client.notify('session/update', {
    'sessionId': recipient,
    'update': {...message, 'senderMessageId': messageId},
  });
}

/// The tool id each Claude subagent's launch went under, its reply's
/// prefix.
final _launches = <String, String>{};

/// A foreground subagent's answer, in its parent's transcript alone.
Future<void> _replied(Turn parent, String childId, String text) =>
    parent.client.notify('session/update', {
      'sessionId': parent.sessionId,
      'update': {
        'sessionUpdate': 'session_message',
        'messageId': '${_launches[childId] ?? childId}:reply',
        'senderSessionId': childId,
        'recipientSessionId': parent.sessionId,
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    });

/// Starts a subagent under [parent] as Claude's adapter announces one from
/// 0.95: a `subagent_update` titled, running and open to a cancel of its
/// own; then its whole task as both views of a `session_message`. [signal]
/// is the parent's unless the subagent outlives its turn.
Future<Turn> _announce(
  Turn parent,
  _Working? working,
  String? role,
  String title,
  String task, {
  Signal? signal,
  num stopAfterMs = 0,
}) async {
  final own = Aborter();
  final child = Turn(
    parent.client,
    _subagentId(),
    Signal.any([signal ?? parent.signal, own.signal]),
  );

  claudeChildren[child.sessionId] = () async {
    await _stopGate(parent, child.sessionId);
    await pause(lifetime.signal, stopAfterMs);
    if (!_atWork.contains(child.sessionId)) return;
    _stoppedAlone.add(child.sessionId);
    own.abort();
    await _report(parent, working, child.sessionId, _idleCancelled);
  };

  await parent.send({
    'sessionUpdate': 'subagent_update',
    'sessionId': child.sessionId,
    'title': title,
    // Its role goes only under Claude's name, which is what tells chord a
    // description is one.
    if (role != null && (adapter == 'claude' || steering == 'claude'))
      'description': role,
    'capabilities': {'cancel': <String, Object?>{}},
    'state': {'state': 'running'},
  });
  working?.add(child.sessionId);
  _atWork.add(child.sessionId);

  final launch = parent.callId('agent');
  _launches[child.sessionId] = launch;
  await _alone(child, () async {
    await pause(child.signal);
    await _linked(
      parent.client,
      launch,
      parent.sessionId,
      child.sessionId,
      task,
    );
  }());
  return child;
}

/// Reports where a Claude subagent stands, on its parent's session; sent
/// at once, as a cancelled turn's are.
Future<void> _report(
  Turn parent,
  _Working? working,
  String childId,
  Map<String, Object?> state,
) async {
  if (state['state'] == 'running' || state['state'] == 'requires_action') {
    _atWork.add(childId);
  } else {
    working?.remove(childId);
    _atWork.remove(childId);
  }
  await parent.client.notify('session/update', {
    'sessionId': parent.sessionId,
    'update': {
      'sessionUpdate': 'subagent_update',
      'sessionId': childId,
      'state': state,
    },
  });
}

const _idleEnd = {'state': 'idle', 'stopReason': 'end_turn'};
const _idleCancelled = {'state': 'idle', 'stopReason': 'cancelled'};

/// Reports each subagent still at work idle and cancelled, the last first.
Future<void> _cancelWorking(Turn turn, _Working working) async {
  for (final id in working.toList().reversed) {
    await _report(turn, working, id, _idleCancelled);
  }
}

/// The explorer of `claudesubagents`: calls, then a write it asks
/// permission for, waiting on the person meanwhile, and done.
Future<void> _explore(Turn parent, _Working working, Turn child) async {
  await _call(
    child,
    'search',
    {'title': 'Search sessionUpdate in src', 'kind': 'search'},
    'completed',
    'Found 14 files',
  );
  await _call(child, 'read', _read('src/acp/connection.ts'), 'completed');

  final write = child.callId('write');
  final toolCall = {
    'toolCallId': write,
    'title': 'Write notes/routing.md',
    'kind': 'edit',
    'status': 'pending',
    'locations': [
      {'path': 'notes/routing.md'},
    ],
  };
  await child.send({'sessionUpdate': 'tool_call', ...toolCall});
  await _report(parent, working, child.sessionId, {'state': 'requires_action'});

  final answer = _outcome(
    await child.client.request(
      'session/request_permission',
      {
        'sessionId': child.sessionId,
        'toolCall': toolCall,
        'options': [
          {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
          {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
        ],
      },
      // Withdrawn when it is stopped alone, as Claude Code withdraws it.
      cancellation: child.signal,
    ),
  );

  // A request withdrawn is the turn being cancelled, whose cancel follows.
  if (answer['outcome'] == 'cancelled') {
    await pause(child.signal, _subagentAfterMs * 10);
  }

  await _report(parent, working, child.sessionId, {'state': 'running'});
  final allowed =
      answer['outcome'] == 'selected' && answer['optionId'] != 'deny';
  await child.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': write,
    'status': allowed ? 'completed' : 'failed',
  });
  await child.say(['Routing lives in src/acp/connection.ts.']);
  await _report(parent, working, child.sessionId, _idleEnd);
}

/// The reviewer of `claudesubagents`, whose work fails.
Future<void> _review(Turn parent, _Working working, Turn child) async {
  await _call(
    child,
    'read',
    _read('src/session/transcript/reducer.ts'),
    'completed',
  );
  await pause(child.signal, _subagentStepMs);
  await _report(parent, working, child.sessionId, {
    'state': 'idle',
    'stopReason': 'error',
    'error': {'code': -32603, 'message': 'API Error: 529 Overloaded'},
  });
}

/// The tester of `claudesubagents`, stopped while its command runs.
Future<void> _stopped(Turn parent, _Working working, Turn child) async {
  final test = await _call(child, 'bash', {
    'title': '`bun test`',
    'kind': 'execute',
  }, 'in_progress');
  await pause(child.signal, _subagentStepMs * 2);
  await child.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': test,
    'status': 'failed',
    'content': [
      _text('The turn was cancelled before this tool call returned a result.'),
    ],
  });
  await _report(parent, working, child.sessionId, _idleCancelled);
}

/// The watcher of `claudesubagents`, which the adapter loses sight of.
Future<void> _lost(Turn parent, _Working working, Turn child) async {
  await _call(child, 'read', _read('package.json'), 'completed');
  await pause(child.signal, _subagentStepMs * 3);
  await _report(parent, working, child.sessionId, {'state': 'unknown'});
}

/// The background tester of `claudebackground`: a command that runs past
/// its parent's turn, then done.
Future<void> _testInBackground(Turn parent, Turn child) async {
  try {
    final test = await _call(child, 'bash', {
      'title': '`bun test`',
      'kind': 'execute',
    }, 'in_progress');
    await pause(child.signal, _subagentAfterMs * 2);
    await child.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': test,
      'status': 'completed',
    });
    await child.say(['Every test passed.']);
    await _report(parent, null, child.sessionId, _idleEnd);
  } catch (_) {
    // The client went before the subagent ended.
  }
}

/// The background tester of `claudebetween`: once its parent's turn has
/// answered, it asks to write its report, then asks a form, with no turn of
/// the client's running (CHD-158); then it says what came back.
Future<void> _askAfterTurn(Turn parent, Turn child) async {
  try {
    await pause(child.signal, _subagentAfterMs);
    final write = child.callId('write');
    final toolCall = {
      'toolCallId': write,
      'title': 'Write notes/test-report.md',
      'kind': 'edit',
      'status': 'pending',
      'locations': [
        {'path': 'notes/test-report.md'},
      ],
    };
    await child.send({'sessionUpdate': 'tool_call', ...toolCall});
    await _report(parent, null, child.sessionId, {'state': 'requires_action'});

    final answer = _outcome(
      await child.client.request('session/request_permission', {
        'sessionId': child.sessionId,
        'toolCall': toolCall,
        'options': [
          {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
          {
            'optionId': 'always',
            'name': 'Always allow',
            'kind': 'allow_always',
          },
          {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
        ],
      }, cancellation: child.signal),
    );
    final allowed =
        answer['outcome'] == 'selected' && answer['optionId'] != 'deny';
    await child.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': write,
      'status': allowed ? 'completed' : 'failed',
    });

    final form = await child.client.request('elicitation/create', {
      'sessionId': child.sessionId,
      'mode': 'form',
      'message': 'Which suite should run next?',
      'requestedSchema': {
        'type': 'object',
        'properties': {
          'suite': {'type': 'string', 'title': 'Suite'},
        },
      },
    }, cancellation: child.signal);

    await _report(parent, null, child.sessionId, {'state': 'running'});
    await child.say([
      'Write ${allowed ? 'allowed' : 'denied'}; form ${_js(form['action'])}.',
    ]);
    await _report(parent, null, child.sessionId, _idleEnd);
  } catch (_) {
    // The client went before the subagent ended.
  }
}

/// A Claude subagent in the background beside one the turn waits on: the
/// first goes on past the turn's end, and past a cancel, which stops only
/// the second; each stopped alone after [stopAfterMs].
Future<String> _background(Turn turn, [num stopAfterMs = 0]) async {
  if (!clientTakesSubagents) return _untaken(turn);
  final _Working working = {};
  try {
    await turn.say(['The tests run in the background while I look.']);
    final tests = await _announce(
      turn,
      null,
      'general-purpose',
      'Run the test suite',
      'Run bun test in the background and report what fails.',
      signal: lifetime.signal,
      stopAfterMs: stopAfterMs,
    );

    // At once, so a cancel before the next announcement leaves it at work.
    _testInBackground(turn, tests).ignore();

    final looker = await _announce(
      turn,
      working,
      'Explore',
      'Find the cancel path',
      'Find where chord ends a turn on Esc.',
      signal: turn.signal,
      stopAfterMs: stopAfterMs,
    );
    await _alone(looker, () async {
      await _call(
        looker,
        'search',
        {'title': 'Search cancelled in src/session', 'kind': 'search'},
        'completed',
        'Found 3 files',
      );
      await pause(looker.signal, _subagentAfterMs);
      await looker.say([
        'Esc ends the turn in src/session/transcript/turn.ts.',
      ]);
      await _report(turn, working, looker.sessionId, _idleEnd);
    }());
    await turn.say(['The tests run on; I will say when they end.']);
    return 'end_turn';
  } catch (_) {
    await _cancelWorking(turn, working);
    rethrow;
  }
}

/// How long `subagentstatesstay`'s pair is at work if no cancel comes.
const _pairHoldMs = 10000;

/// `subagentstates`' play: with [holdPair], its pair stays at work until
/// the turn is cancelled.
Future<String> _subagentStates(Turn turn, bool holdPair) async {
  if (!clientTakesSubagents) return _untaken(turn);
  final _Children open = {};
  try {
    await turn.send(_parentPlan(1));
    await _readSessionLayer(
      await _spawn(
        turn,
        open,
        'Find the session layer',
        'Find where chord hands each session/update to its listeners.',
      ),
      open,
    );
    await turn.send(_parentPlan(2));
    await turn.say(['Routing is in src/acp/connection.ts. Now both sides.']);

    final explorer = await _spawn(
      turn,
      open,
      'explorer',
      'Find where chord routes session/update.',
    );
    final worker = await _spawn(
      turn,
      open,
      'worker',
      'Find where tool calls are drawn on screen.',
    );
    final wait = turn.callId('wait');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': wait,
      'title': 'Wait explorer, worker',
      'kind': 'other',
      'status': 'in_progress',
    });
    if (holdPair) {
      // At work until the turn is cancelled, or for a while at most.
      await pause(turn.signal, _pairHoldMs);
    }
    await Future.wait([
      _readAll(explorer, open, const [
        'src/acp/connection.ts',
        'src/session/session.ts',
        'src/session/conversation.ts',
      ]),
      _readAll(worker, open, const ['src/ui/transcript/tools/Tool.tsx']),
    ], eagerError: true);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': wait,
      'status': 'completed',
    });
    await turn.send(_parentPlan(3));
    await turn.say([
      'Both sides found: routing is in src/acp/connection.ts, ',
      'drawing is Tool in src/ui/transcript/tools/Tool.tsx.',
    ]);
    return 'end_turn';
  } catch (_) {
    for (final child in open.keys.toList().reversed) {
      await _finish(child, open, 'cancelled');
    }
    rethrow;
  }
}

/// A launch's prompt: [first], then eight steps, a blank line between.
String _grown(String first) => [
  first,
  for (var step = 0; step < 8; step++) 'Then step ${step + 1}.',
].join('\n\n');

final Map<String, Play> subagents = {
  // One subagent whose call is the only one open.
  'subagentcall': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Children open = {};
    try {
      final child = await _spawn(turn, open, 'sleeper', 'Sleep a while');
      final id = await _call(child, 'sleep', {
        'title': '`sleep 2`',
        'kind': 'execute',
      }, 'in_progress');
      await pause(turn.signal, _subagentStepMs);
      await child.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': id,
        'status': 'completed',
      });
      await _finish(child.sessionId, open, 'completed');
      await turn.say(['The sleeper is done.']);
    } finally {
      for (final id in open.keys.toList()) {
        await _finish(id, open, 'cancelled');
      }
    }
    return 'end_turn';
  },

  // Subagents in the draft form Codex's adapter sends: two spawned back to
  // back, then, alone, a third that outlives the turn. A cancel ends each
  // one still open before the prompt is answered.
  'subagent': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Children open = {};
    try {
      await turn.say(['I will send two agents, one for each side.']);
      final first = await _spawn(
        turn,
        open,
        'Find the session layer',
        'Find where chord hands each session/update to its listeners and '
            'say which file owns the routing. Report paths and line numbers.',
      );
      final second = await _spawn(
        turn,
        open,
        'Find where tool calls are drawn on screen and how they fold',
        'Find the component that draws a tool call and the rule that folds '
            'its output.',
      );
      await Future.wait([
        _findSessionLayer(first, open),
        _findToolDrawing(second, open),
      ], eagerError: true);

      // Said between the spawns, so the last stands alone, not in a group.
      await turn.say(['Now the tests, in the background.']);
      final last = await _spawn(
        turn,
        open,
        'Run the whole test suite',
        'Run bun dev test and report what fails.',
      );
      // A moment before its first call, to see it starting.
      await pause(turn.signal, _subagentStepMs);
      final test = await _call(last, 'bash', {
        'title': 'bun dev test',
        'kind': 'execute',
      }, 'in_progress');
      await turn.say(['It is running; I will say when it ends.']);

      later(milliseconds(_subagentAfterMs), () async {
        try {
          // Where a test made the session's gate, the subagent works on
          // until its release, or 10 s (CHD-501).
          final at = p.join(cwds[turn.sessionId] ?? '.', gate);
          final deadline = now() + 10000;
          while (Directory(at).existsSync() &&
              !File(p.join(at, gateRelease)).existsSync() &&
              now() < deadline) {
            await Future<void>.delayed(
              Duration(milliseconds: milliseconds(stepMs * 2)),
            );
          }
          await last.client.notify('session/update', {
            'sessionId': last.sessionId,
            'update': {
              'sessionUpdate': 'tool_call_update',
              'toolCallId': test,
              'status': 'completed',
            },
          });
          await last.client.notify('session/update', {
            'sessionId': last.sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'Every test passed.'},
            },
          });
          await _finish(last.sessionId, open, 'completed');
        } catch (_) {
          // The client went before the subagent ended.
        }
      });
      return 'end_turn';
    } catch (_) {
      for (final child in open.keys.toList().reversed) {
        await _finish(child, open, 'cancelled');
      }
      rethrow;
    }
  },

  // The states `subagent` never reaches.
  'subagentstates': (turn) => _subagentStates(turn, false),

  // As `subagentstates`, its pair at work until cancelled (CHD-399).
  'subagentstatesstay': (turn) => _subagentStates(turn, true),

  // A subagent as ACP's own `subagent_update` says it: running, then idle.
  'subagentupdate': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final child = Turn(turn.client, _subagentId(), turn.signal);
    await turn.send({
      'sessionUpdate': 'subagent_update',
      'sessionId': child.sessionId,
      'title': 'Summarise the README',
      'description': 'Read README.md and say in one line what chord is.',
      'capabilities': <String, Object?>{},
      'state': {'state': 'running'},
    });
    await _call(child, 'read', _read('README.md'), 'completed', '# chord');
    await child.say(['chord is a terminal client for ACP agents.']);
    await turn.send({
      'sessionUpdate': 'subagent_update',
      'sessionId': child.sessionId,
      'state': {'state': 'idle'},
    });
    await turn.say(['It says chord is a terminal client for ACP agents.']);
    return 'end_turn';
  },

  // Subagents as Claude's adapter sends them, in ACP's own form: four
  // spawned back to back, ending each way it reports.
  'claudesubagents': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    try {
      await turn.say(['I will send four agents.']);
      final explorer = await _announce(
        turn,
        working,
        'Explore',
        'Find the session layer',
        'Find where chord hands each session/update to its listeners and '
            'say which file owns the routing.\n\nReport paths and line '
            'numbers, and write what you find to notes/routing.md.',
      );
      final reviewer = await _announce(
        turn,
        working,
        'general-purpose',
        'Review the transcript reducer',
        'Review src/session/transcript/reducer.ts for updates it drops.',
      );
      final tester = await _announce(
        turn,
        working,
        'general-purpose',
        'Run the tests',
        'Run bun test and report what fails.',
      );
      final watcher = await _announce(
        turn,
        working,
        null,
        'Watch the build',
        'Watch the build and say when it breaks.',
      );
      await Future.wait([
        _alone(explorer, _explore(turn, working, explorer)),
        _alone(reviewer, _review(turn, working, reviewer)),
        _alone(tester, _stopped(turn, working, tester)),
        _alone(watcher, _lost(turn, working, watcher)),
      ], eagerError: true);
      await turn.say(['Each agent has ended.']);
      return 'end_turn';
    } catch (_) {
      await _cancelWorking(turn, working);
      rethrow;
    }
  },

  'claudebackground': (turn) => _background(turn),

  // A Claude subagent in the background that asks a permission and then a
  // form once the turn has answered (CHD-158).
  'claudebetween': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final tests = await _announce(
      turn,
      null,
      'general-purpose',
      'Run the whole test suite',
      'Run bun test in the background and write a report of what fails.',
      signal: lifetime.signal,
    );
    _askAfterTurn(turn, tests).ignore();
    await turn.say(['It is running; I will say when it ends.']);
    return 'end_turn';
  },

  // As claudebackground, its subagents taking about 2 s to stop alone.
  'claudeslowstop': (turn) => _background(turn, _subagentAfterMs),

  // A Claude subagent its parent messages again once it is done.
  'claudemessage': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    try {
      final explorer = await _announce(
        turn,
        working,
        'Explore',
        'Find the session layer',
        'Find where chord hands each session/update to its listeners.\n\n'
            'Report the file that owns the routing, with line numbers.',
      );
      await _alone(explorer, () async {
        await _call(
          explorer,
          'read',
          _read('src/acp/connection.ts'),
          'completed',
        );
        await explorer.say(['Routing lives in src/acp/connection.ts.']);
        await _report(turn, working, explorer.sessionId, _idleEnd);
        await _replied(
          turn,
          explorer.sessionId,
          'Routing lives in src/acp/connection.ts.',
        );
      }());

      // One stopped alone is not messaged again.
      if (!_stoppedAlone.contains(explorer.sessionId)) {
        await turn.say(['I will ask it for the tests too. ']);
        await _linked(
          turn.client,
          turn.callId('send'),
          turn.sessionId,
          explorer.sessionId,
          'Now find the tests that cover it.',
        );
        await _report(turn, working, explorer.sessionId, {'state': 'running'});
        await _alone(explorer, () async {
          await _call(
            explorer,
            'search',
            {'title': 'Search connection in tests/acp', 'kind': 'search'},
            'completed',
            'Found 2 files',
          );
          await explorer.say(['tests/acp/connection_test.ts covers it.']);
          await _report(turn, working, explorer.sessionId, _idleEnd);
        }());
      }
      await turn.say(['Both found.']);
      return 'end_turn';
    } catch (_) {
      await _cancelWorking(turn, working);
      rethrow;
    }
  },

  // A Claude subagent its agent says waits on the person, with no request
  // of its reaching chord; held about 2 s, then done.
  'claudewaiting': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    try {
      final child = await _announce(
        turn,
        working,
        'general-purpose',
        'Run the test suite',
        'Run bun test and report what fails.',
      );
      await _alone(child, () async {
        await _report(turn, working, child.sessionId, {
          'state': 'requires_action',
        });
        await pause(child.signal, _subagentAfterMs);
        await _report(turn, working, child.sessionId, {'state': 'running'});
        await child.say(['Every test passed.']);
        await _report(turn, working, child.sessionId, _idleEnd);
      }());
      await turn.say(['The tests passed.']);
      return 'end_turn';
    } catch (_) {
      await _cancelWorking(turn, working);
      rethrow;
    }
  },

  // A Claude subagent that takes its own cancel back: held about 2 s with
  // no stop of its own, then done.
  'claudenostop': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'general-purpose',
      'Run the test suite',
      'Run bun test and report what fails.',
    );
    claudeChildren.remove(child.sessionId);
    await turn.send({
      'sessionUpdate': 'subagent_update',
      'sessionId': child.sessionId,
      'capabilities': null,
    });
    await pause(turn.signal, _subagentAfterMs);
    await _report(turn, working, child.sessionId, _idleEnd);
    await turn.say(['The tests passed.']);
    return 'end_turn';
  },

  // A launch's prompt over six rows, and a reply over two paragraphs.
  'claudelongprompt': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'Check the handover',
      [
        for (var step = 0; step < 9; step++)
          '${step + 1}. Check step ${step + 1} of the handover and report '
              'what it finds.',
      ].join('\n'),
    );
    await child.say(['Checked.']);
    await _report(turn, working, child.sessionId, _idleEnd);
    await _replied(
      turn,
      child.sessionId,
      'Every step holds.\n\nStep 9 was the slowest to check.',
    );
    await turn.say(['The handover holds.']);
    return 'end_turn';
  },

  // A launch's prompt with code above its fold and more below it.
  'claudecodeprompt': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'Check the build',
      _grown('Run this first.\n\n```sh\nbun test\n```'),
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    await turn.say(['The build holds.']);
    return 'end_turn';
  },

  // A launch's short prompt with code, lengthened under the same id past
  // the fold once the gate is released.
  'claudepromptgrows': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'Check the build',
      'Run this.\n\n```sh\nbun test\n```',
    );
    await turn.say(['Short so far. ']);
    await gateOpened(turn, gateRelease);
    await _linked(
      turn.client,
      _launches[child.sessionId] ?? child.sessionId,
      turn.sessionId,
      child.sessionId,
      _grown('Run this.\n\n```sh\nbun test\n```'),
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    await turn.say(['Long now.']);
    return 'end_turn';
  },

  // A launch's prompt that fits six rows wide and not narrow.
  'claudewrapprompt': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'Check the build',
      '${'Check every step of the handover and report it. ' * 3}\n\n'
          '```sh\nbun test\n```',
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    await turn.say(['Done wrapping.']);
    return 'end_turn';
  },

  // A SendMessage to a child still at work: the call comes after all.
  'claudesendrunning': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'Find the session layer',
      'Find the routing.',
    );
    await _call(
      turn,
      'send',
      {'title': 'SendMessage', 'kind': 'other'},
      'completed',
      'Message queued',
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    await _replied(turn, child.sessionId, 'It is the relay.');
    return 'end_turn';
  },

  // A child that hands its report back: both views, with no `:reply`, and
  // on its own session a one-option config update.
  'claudehandback': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'Explore',
      'explorer',
      'Find the routing and hand it back.',
    );
    await child.send({
      'sessionUpdate': 'config_option_update',
      'configOptions': [
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'child-model',
          'options': [
            {'value': 'child-model', 'name': 'Child model'},
          ],
        },
      ],
    });
    await _linked(
      turn.client,
      child.callId('handback'),
      child.sessionId,
      turn.sessionId,
      'The relay in connection.ts owns the routing.',
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    return 'end_turn';
  },

  // A lone failure that says why, with no answer.
  'claudefailed': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      null,
      'Run the test suite',
      'Run bun test and report what fails.',
    );
    await _report(turn, working, child.sessionId, {
      'state': 'idle',
      'stopReason': 'error',
      'error': {'code': -32603, 'message': 'The build still fails.'},
    });
    await turn.say(['It failed.']);
    return 'end_turn';
  },

  // A launch that leaves `run_in_background` unset, in the order Claude's
  // adapter 0.99.1 was seen sending it live.
  'claudeunsetlaunch': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'general-purpose',
      'Reply with ok',
      'Reply with ok.',
    );
    await _replied(
      turn,
      child.sessionId,
      'Async agent launched successfully. (This tool result is internal '
      'metadata.)\nagentId: ${child.sessionId}\noutput_file: /tmp/agent-output',
    );
    await _linked(
      turn.client,
      child.callId('handback'),
      child.sessionId,
      turn.sessionId,
      'ok',
    );
    await _report(turn, working, child.sessionId, _idleEnd);
    await turn.say(['It said ok.']);
    return 'end_turn';
  },

  // A failure that says nothing of why, and a stop: neither answers.
  'claudenoanswer': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final failing = await _announce(
      turn,
      working,
      null,
      'Run the test suite',
      'Run bun test and report what fails.',
    );
    await _report(turn, working, failing.sessionId, {
      'state': 'idle',
      'stopReason': 'error',
    });
    final told = await _announce(
      turn,
      working,
      null,
      'Watch the build',
      'Watch the build.',
    );
    await _report(turn, working, told.sessionId, _idleCancelled);
    await turn.say(['Neither answered.']);
    return 'end_turn';
  },

  // A child that launches one of its own, and has its reply, and then its
  // own answer to its parent.
  'claudenested': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final _Working working = {};
    final child = await _announce(
      turn,
      working,
      'general-purpose',
      'Review the layer',
      'Review the session layer.',
    );
    final inner = await _announce(
      child,
      working,
      'Explore',
      'Find the routing',
      'Find the routing.',
    );
    await inner.say(['The relay.']);
    await _report(child, working, inner.sessionId, _idleEnd);
    await _replied(child, inner.sessionId, 'It is the relay.');
    await child.say(['Reviewed.']);
    await _report(turn, working, child.sessionId, _idleEnd);
    await _replied(turn, child.sessionId, 'The layer holds.');
    return 'end_turn';
  },

  // Subagents as Codex's adapter sends them from 2.4: an announcement with
  // no state, then each thing as it changes, alone.
  'codexsubagents': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    Future<void> told(String sessionId, Map<String, Object?> fields) =>
        turn.send({
          'sessionUpdate': 'subagent_update',
          'sessionId': sessionId,
          ...fields,
        });
    final worker = Turn(turn.client, _subagentId(), turn.signal);
    await told(worker.sessionId, {'capabilities': <String, Object?>{}});
    await told(worker.sessionId, {'title': 'worker'});
    await worker.send({
      'sessionUpdate': 'session_info_update',
      'title': 'worker',
    });
    await worker.send({
      'sessionUpdate': 'config_option_update',
      'configOptions': <Object?>[],
    });
    await told(worker.sessionId, {
      'state': {'state': 'running'},
    });
    await told(worker.sessionId, {
      'capabilities': {'cancel': <String, Object?>{}},
    });
    await _call(worker, 'read', _read('README.md'), 'completed');
    await worker.say(['Read.']);
    await told(worker.sessionId, {'state': _idleEnd});
    await told(worker.sessionId, {
      'capabilities': {'cancel': null},
    });
    await told(worker.sessionId, {'title': 'worker renamed'});

    final failing = _subagentId();
    await told(failing, {
      'capabilities': <String, Object?>{},
      'title': 'failing',
      'description': 'Fail at once',
    });
    await told(failing, {
      'state': {'state': 'running'},
    });
    await told(failing, {
      'capabilities': {'cancel': <String, Object?>{}},
    });
    await told(failing, {
      'state': {
        'state': 'idle',
        'stopReason': 'error',
        'error': {'code': -32603, 'message': 'Subagent work failed'},
      },
    });
    await told(failing, {
      'capabilities': {'cancel': null},
    });
    await turn.say(['Both have ended.']);
    return 'end_turn';
  },

  // A subagent as Codex's 2.4 sends one, at work until a `session/cancel`
  // on its own id or on the turn.
  'codexsubagentstop': (turn) async {
    if (!clientTakesSubagents) return _untaken(turn);
    final id = _subagentId();
    Future<void> told(Map<String, Object?> fields) => turn.send({
      'sessionUpdate': 'subagent_update',
      'sessionId': id,
      ...fields,
    });
    final stopped = Completer<void>();

    // Sent at once, as a cancelled turn's are.
    Future<void> ended() async {
      for (final fields in const [
        {'state': _idleCancelled},
        {
          'capabilities': {'cancel': null},
        },
      ]) {
        await turn.client.notify('session/update', {
          'sessionId': turn.sessionId,
          'update': {
            'sessionUpdate': 'subagent_update',
            'sessionId': id,
            ...fields,
          },
        });
      }
    }

    // Its own, so a stop leaves no wait behind for the rest of the session.
    final waiting = Aborter();
    claudeChildren[id] = () async {
      if (!stopped.isCompleted) stopped.complete();
    };
    try {
      await told({'capabilities': <String, Object?>{}, 'title': 'watcher'});
      await told({
        'state': {'state': 'running'},
      });
      await told({
        'capabilities': {'cancel': <String, Object?>{}},
      });
      await Future.any([
        stopped.future,
        pause(Signal.any([turn.signal, waiting.signal]), 60000),
      ]);
    } catch (_) {
      await ended();
      rethrow;
    } finally {
      waiting.abort();
      claudeChildren.remove(id);
    }
    await ended();
    await turn.say(['It stopped, and the turn goes on.']);
    return 'end_turn';
  },
};
