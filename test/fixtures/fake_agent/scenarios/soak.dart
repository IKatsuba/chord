// A team at work for as long as chord runs, for the long-run memory check,
// as the original's scenarios/soak.ts: `soak` hands team `bugfix` the job
// `soaklead`; the lead opens `tester` and `coder` on `soakturn` and sends
// main `soakturn`; and every `soakturn` streams a reply, a thought and a
// call, then sends `soakturn` back to whoever sent it.
import '../options.dart';
import '../turn.dart';
import 'chord_tools.dart';
import 'teams.dart';

/// Lines in each `soakturn`'s reply.
const _soakLines = 30;

/// Who sent each session's last message, by its session, as main read it.
final senders = <String, String>{};

/// Each session's turns so far, so no two replies say the same.
final _turns = <String, int>{};

/// A reply as an agent at work writes one: prose, a list and code.
Future<void> _stream(Turn turn, int n) async {
  await turn.think(['Turn $n: ', 'reading what changed ', 'since the last.']);
  for (var line = 1; line <= _soakLines; line++) {
    await pause(turn.signal, stepMs * 4);
    await turn.say([
      line == 1
          ? '## Turn $n\n\n'
          : line % 10 == 0
          ? '\n```ts\nconst turn${n}Line$line = ${n * line};\n```\n'
          : '\n- Turn $n, line $line: **checked** `src/parse/tokenize.ts`.',
    ]);
  }
}

/// A call that edits, its output naming the turn.
Future<void> _call(Turn turn, int n) async {
  final toolCallId = turn.callId('edit');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': 'Edit src/parse/tokenize.ts (turn $n)',
    'kind': 'edit',
    'status': 'in_progress',
  });
  await pause(turn.signal, stepMs * 10);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [
      {
        'type': 'content',
        'content': {'type': 'text', 'text': 'Wrote $n lines in turn $n.'},
      },
    ],
  });
}

final Map<String, Play> soak = {
  // Hands `bugfix` the job that starts the soak.
  'soak': (turn) => handOver(turn, 'soaklead'),

  // The lead's first turn: both members and main set going.
  'soaklead': (turn) async {
    final client = await chordClient(turn);
    if (client == null) {
      await turn.say(['No chord server in this session.']);
      return 'end_turn';
    }
    try {
      await callChord(turn, client, 'open_agent', {
        'member': 'tester',
        'prompt': 'soakturn',
      });
      await callChord(turn, client, 'open_agent', {
        'member': 'coder',
        'prompt': 'soakturn',
      });
      await callChord(turn, client, 'send_message', {
        'to': 'main',
        'text': 'soakturn',
      });
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A turn of work, then the next one asked of whoever sent this.
  'soakturn': (turn) async {
    final n = (_turns[turn.sessionId] ?? 0) + 1;
    final to = senders[turn.sessionId];
    _turns[turn.sessionId] = n;
    await _stream(turn, n);
    await _call(turn, n);
    final client = to == null ? null : await chordClient(turn);
    try {
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'to': to,
          'text': 'soakturn',
        });
      }
    } finally {
      await client?.close();
    }
    return 'end_turn';
  },
};
