// Task agents: a session that starts one on the fake runtime through
// chord's `spawn_task`, and the task's own turn, which messages its parent
// through `send_message` before its report, as the original's
// scenarios/tasks.ts.
import '../options.dart';
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'chord_tools.dart';

/// A task's pace: 20 steps, a tenth of a second by default.
num get _taskStepMs => stepMs * 20;

/// What `task` asks for: the fake runtime, its small model, `taskchild`.
const taskArgs = <String, Object?>{
  'agent': 'fake',
  'model': 'fake-small',
  'prompt': 'taskchild',
  'name': 'Fix the tokenizer',
};

/// What the task says to its parent while it works.
const taskMessage =
    'Found it: a string at the end of a line lost its closing quote. '
    'Fixing src/parse/tokenize.ts now.';

/// The task's report, its last message.
const taskReport =
    'The tokenizer dropped a closing quote when a string ended the line. '
    'Fixed in src/parse/tokenize.ts, with two cases added to '
    'tests/parse/tokenize_test.ts. bun dev test passes.';

/// Why the task fails when the person denies its write.
const taskFailure =
    'The edit to src/parse/tokenize.ts was denied, so the tokenizer is not '
    'fixed.';

/// A call of the task's own, done after a step.
Future<void> _work(Turn turn, String title, String kind, String output) async {
  final toolCallId = turn.callId(kind);
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': title,
    'kind': kind,
    'status': 'in_progress',
  });
  await pause(turn.signal, _taskStepMs);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': output},
      },
    ],
  });
}

/// What `tasklong` asks for: a task that works on, asking nothing.
const longTaskArgs = <String, Object?>{
  'agent': 'fake',
  'prompt': 'taskwait',
  'name': 'Watch the build',
};

/// A task name of about 600 characters, which wraps to more lines than
/// the background frame holds at 80x24 (CHD-430).
const tallTaskName =
    'Rewrite the tokenizer as a single pass over the source that reads every '
    'token, string and comment once, keeping the line and column of each one '
    'so the parser can point at the exact place a mistake starts, with the '
    'old lookahead buffer replaced by a small ring of the last three tokens, '
    'the escapes inside strings decoded where they are read rather than in a '
    'second walk, the numbers parsed with their radix and separators checked '
    'as they come, every error message reworded to say what was expected and '
    'what was found instead, with the positions kept for the error messages '
    'the parser prints, and the old two-pass reader removed together';

/// Says the session has no chord server and ends the turn.
Future<String> _noServer(Turn turn) async {
  await turn.say(['No chord server in this session.']);
  return 'end_turn';
}

/// Until [turn] is cancelled, or its client goes, as
/// `once(turn.signal, 'abort', {signal: lifetime.signal})` waits.
Future<void> _untilCancelled(Turn turn) async {
  turn.signal.throwIfAborted();
  await untilAborted(turn.signal, unless: lifetime.signal);
  turn.signal.throwIfAborted();
}

/// `taskstays`' play, its task started with [arguments].
Future<String> _taskStays(Turn turn, Map<String, Object?> arguments) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await turn.say(['I will send a task agent on fake for the fix.']);
    await callChord(turn, client, 'spawn_task', arguments);
    await turn.say(['It is running; I will check its report when it lands.']);
    await _untilCancelled(turn);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// What `tasktitled` asks for: a task whose agent names its own session,
/// which chord shows nowhere (CHD-445, Q200).
const titledTaskArgs = <String, Object?>{
  'agent': 'fake',
  'prompt': 'titledlong',
  'name': 'Name the session',
};

/// Starts a task on [arguments] and ends the turn, the task working on.
Future<String> _startTask(Turn turn, Map<String, Object?> arguments) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'spawn_task', arguments);
    await turn.say(['Started.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// How long `taskchildhold` stays at work if no cancel comes.
const _holdMs = 10000;

/// `taskchild`'s play: with [hold], at work after its message.
Future<String> _taskChild(Turn turn, bool hold) async {
  final client = await chordClient(turn);
  try {
    await _work(
      turn,
      'Search tokenize in src/parse',
      'search',
      'src/parse/tokenize.ts',
    );
    await _work(turn, 'Read src/parse/tokenize.ts', 'read', '120 lines');

    final toolCallId = turn.callId('edit');
    final toolCall = {
      'toolCallId': toolCallId,
      'title': 'Edit src/parse/tokenize.ts',
      'kind': 'edit',
      'status': 'pending',
      'locations': [
        {'path': 'src/parse/tokenize.ts'},
      ],
    };
    await turn.send({'sessionUpdate': 'tool_call', ...toolCall});

    final answer = await turn.client.request('session/request_permission', {
      'sessionId': turn.sessionId,
      'toolCall': toolCall,
      'options': [
        {'optionId': 'allow', 'name': 'Allow', 'kind': 'allow_once'},
        {'optionId': 'deny', 'name': 'Deny', 'kind': 'reject_once'},
      ],
    });
    final outcome = (answer['outcome'] as Map?) ?? const {};
    if (outcome['outcome'] == 'cancelled') return 'cancelled';

    final allowed = outcome['optionId'] == 'allow';
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': allowed ? 'completed' : 'failed',
    });
    if (!allowed) throw RequestError(-32603, taskFailure);

    if (client != null) {
      await callChord(turn, client, 'send_message', {'text': taskMessage});
    }
    if (hold) {
      // At work until the turn is cancelled, or for a while at most.
      await pause(turn.signal, _holdMs);
    }
    await _work(turn, '`bun dev test`', 'execute', '214 passed, 0 failed');
    await pause(turn.signal, _taskStepMs * 10);
    await turn.say([taskReport]);
  } finally {
    await client?.close();
  }
  return 'end_turn';
}

/// Starts a task that asks under its parent's session, by [word].
Play _taskPassingAsParent(String word) => (turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'spawn_task', {
      'agent': 'fake',
      'prompt': '$word ${turn.sessionId}',
      'name': 'Pass as the parent',
    });
  } finally {
    await client.close();
  }
  return 'end_turn';
};

/// A call of the parent's own titled as claude's question call, never
/// asked.
Future<void> _parentsOwnAsk(Turn turn) => turn.send({
  'sessionUpdate': 'tool_call',
  'toolCallId': turn.callId('ask'),
  'title': 'Asking for your input',
  'kind': 'other',
  'status': 'completed',
  'content': [
    {
      'type': 'content',
      'content': {'type': 'text', 'text': "The parent's own call."},
    },
  ],
});

final Map<String, Play> taskPlays = {
  'taskaskas': _taskPassingAsParent('askas'),
  'taskformas': _taskPassingAsParent('formas'),

  // As tasklong, under a name taller than the background frame (CHD-430).
  'tasktallname': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', {
        ...longTaskArgs,
        'name': tallTaskName,
      });
      await turn.say(['The tokenizer is being rewritten.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Starts `taskwait` as a task agent and ends its turn at once.
  'tasklong': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', longTaskArgs);
      await turn.say(['The build is being watched.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Closes `tasklong`'s task by its name with close_agent (CHD-590).
  'taskclose': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'close_agent', {
        'to': longTaskArgs['name'],
      });
      await turn.say(['The build is no longer watched.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // As `tasklong`, its task on `costwait` (CHD-373).
  'taskcost': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', {
        'agent': 'fake',
        'prompt': 'costwait',
        'name': 'Count the cost',
      });
      await turn.say(['The cost is being counted.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Two `taskwait` tasks spawned one after the other.
  'tasktwo': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', longTaskArgs);
      await callChord(turn, client, 'spawn_task', {
        ...longTaskArgs,
        'name': 'Watch the deploy',
      });
      await turn.say(['The build and the deploy are being watched.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A task's job that takes a minute and asks nothing, until it is stopped.
  'taskwait': (turn) async {
    await turn.say(['Watching the build.']);
    await pause(turn.signal, 60000);
    return turn.signal.aborted ? 'cancelled' : 'end_turn';
  },

  // Starts `taskchild` as a task agent, says so, and works on a while.
  'task': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await turn.say(['I will send a task agent on fake for the fix.']);
      await callChord(turn, client, 'spawn_task', taskArgs);
      await turn.say(['It is running; I will check its report when it lands.']);
      await pause(turn.signal, _taskStepMs * 30);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // As `task`, its turn running on until it is cancelled.
  'taskstays': (turn) => _taskStays(turn, taskArgs),

  // A task whose agent titles its session (CHD-445, Q200).
  'tasktitled': (turn) => _startTask(turn, titledTaskArgs),

  // As `taskstays`, its task on `taskchildhold` (CHD-399).
  'taskstayshold': (turn) =>
      _taskStays(turn, {...taskArgs, 'prompt': 'taskchildhold'}),

  // As `task`, its turn running on until a message is steered into it
  // (CHD-470).
  'tasktillsteered': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    // Listening before the task starts, so its message is never missed.
    final waiting = steeredInto(
      turn.sessionId,
      Signal.any([turn.signal, lifetime.signal]),
    );
    try {
      await turn.say(['I will send a task agent on fake for the fix.']);
      await callChord(turn, client, 'spawn_task', taskArgs);
      await turn.say(['It is running; I will check its report when it lands.']);
      await waiting.steered;
    } finally {
      waiting.stop();
      await client.close();
    }
    return 'end_turn';
  },

  // Starts `taskchild` as `task` does, then ends its turn at once
  // (CHD-158).
  'taskbetween': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', taskArgs);
      await turn.say(['It is running; I will check its report when it lands.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A call of its own titled as claude's question call, then a task whose
  // job is `askclaude`.
  'taskask': (turn) async {
    await _parentsOwnAsk(turn);
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', {
        ...taskArgs,
        'prompt': 'askclaude',
        'name': 'Ask the person',
      });
      await turn.say(['It is asking; I will read its report when it lands.']);
      await pause(turn.signal, _taskStepMs * 30);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // As `taskask`, its turn running on until it is cancelled (CHD-467).
  'taskaskstays': (turn) async {
    await _parentsOwnAsk(turn);
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'spawn_task', {
        ...taskArgs,
        'prompt': 'askclaude',
        'name': 'Ask the person',
      });
      await turn.say(['It is asking; I will read its report when it lands.']);
      await _untilCancelled(turn);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // chord's tools as calls an agent makes, and a task on a runtime chord
  // does not know, which chord refuses.
  'chordcalls': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'list_agents', {});
      await callChord(turn, client, 'list_agents', {'agent': 'fake'});
      await callChord(turn, client, 'list_sessions', {});
      await callChord(turn, client, 'spawn_task', {
        ...taskArgs,
        'agent': 'fakx',
      });
      await turn.say(['chord knows no fakx.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // codex's models and modes, which chord reads for the directory the
  // asking session works in (CHD-466).
  'codexmodels': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      final answer = await callChord(turn, client, 'list_agents', {
        'agent': 'codex',
      });
      await turn.say(['Codex read: ${answer ?? 'failed'}']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // The same lists as codex-acp calls them (CHD-377), after a call of
  // another server's with the same arguments as the first.
  'codexchordcalls': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      final other = turn.callId('list_notes');
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': other,
        'status': 'completed',
        ...codexCall('notes', 'list_notes', {}),
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'no notes'},
          },
        ],
      });
      await callChord(turn, client, 'list_agents', {}, shape: 'codex');
      await callChord(turn, client, 'list_sessions', {}, shape: 'codex');
      await turn.say(['Listed as Codex.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A task's job: two calls, a write it asks the person for, a message to
  // its parent, a test run, then the report.
  'taskchild': (turn) => _taskChild(turn, false),

  // As `taskchild`, at work after its message until it is cancelled
  // (CHD-399).
  'taskchildhold': (turn) => _taskChild(turn, true),
};
