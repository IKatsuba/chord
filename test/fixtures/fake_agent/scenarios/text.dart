// Replies: plain, thought first, markdown, long and slow, and a few that say
// what reached the agent, as the original's scenarios/text.ts.
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../markdown.dart';
import '../options.dart';
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'agents.dart';

/// The title `titledlong` names its session (CHD-445).
const longSessionTitle =
    'Find out why the tokenizer drops the closing quote of a string at the '
    'end of a line, write a test in tests/parse/tokenize_test.ts that fails '
    'for that reason, fix src/parse/tokenize.ts and have the diff reviewed '
    'before anything else in the parser changes';

/// How many items the `long` scenario's list has.
const _longLines = 200;

String _longLine(int n) =>
    '${n == 1 ? '' : '\n'}$n. Line $n of $_longLines, streamed one at a time.';

/// How long `longheld` holds its turn for a cancel.
const _heldWithinMs = 10000;

/// Reports the session's cost so far, then works on until it is cancelled
/// (CHD-373).
Future<String> _costWait(Turn turn) async {
  await turn.send({
    'sessionUpdate': 'usage_update',
    'used': 1200,
    'size': 200000,
    'cost': {'amount': 0.01, 'currency': 'USD'},
  });
  await turn.say(['Working until stopped.']);
  turn.signal.throwIfAborted();
  await untilAborted(turn.signal, unless: lifetime.signal);
  turn.signal.throwIfAborted();
  return 'end_turn';
}

const _chunks = ['Hello', ', world', '. This reply', ' came in chunks.'];

final Map<String, Play> text = {
  // A request Cursor's agent waits on, said as cursor-cloud says it, then
  // the turn held until it is cancelled (CHD-622).
  'cloudrequest': (turn) async {
    await turn.send({
      'sessionUpdate': 'agent_message_chunk',
      'messageId': const Uuid().v4(),
      'content': {
        'type': 'text',
        'text':
            "Cursor's agent is waiting for input or approval (request r-81c2). "
            'This adapter cannot answer it; Esc stops the run.  \n'
            'https://cursor.com/agents/bc-5e1f0a7c-2d4b-4e8a-9c1f-7b2e6d3a9f10',
      },
    });
    turn.signal.throwIfAborted();
    await untilAborted(turn.signal, unless: lifetime.signal);
    turn.signal.throwIfAborted();
    return 'end_turn';
  },

  'text': (turn) async {
    await turn.say(_chunks);
    return 'end_turn';
  },

  // As `text`, its turn ending only once a message has been steered into
  // it, or after 10 s without one (CHD-399).
  'texttillsteered': (turn) async {
    final waiting = steeredInto(
      turn.sessionId,
      Signal.any([turn.signal, lifetime.signal, Signal.timeout(10000)]),
    );
    try {
      await turn.say(_chunks);
      await waiting.steered.catchError((Object _) {});
    } finally {
      waiting.stop();
    }
    return 'end_turn';
  },

  // As `texttillsteered`, then held until it is cancelled (CHD-526).
  'texttillsteeredheld': (turn) async {
    await turn.say(_chunks);
    await steeredIn(turn, 1);
    await turn.read();
    await pause(turn.signal, _heldWithinMs);
    return 'end_turn';
  },

  // Says `Working`, then reads each message steered in as it comes, until
  // it is cancelled, at most a minute (CHD-552).
  'readsheld': (turn) async {
    await turn.say(['Working']);
    for (final end = now() + 60000; now() < end;) {
      await pause(turn.signal);
      await turn.read();
    }
    return 'end_turn';
  },

  'thought': (turn) async {
    await turn.think(['Considering', ' the question.']);
    await turn.say(['Here is', ' the answer.']);
    return 'end_turn';
  },

  'todos': (turn) async {
    await turn.say([
      'todo tools: ${Platform.environment['CLAUDE_CODE_ENABLE_TODO_TOOLS'] ?? 'unset'}',
    ]);
    return 'end_turn';
  },

  'mcp': (turn) async {
    await turn.say([
      '```json\n${stringify(mcpServers[turn.sessionId] ?? [], 2)}\n```',
    ]);
    return 'end_turn';
  },

  'configsheard': (turn) async {
    await turn.say([
      '```json\n${stringify(configsHeard[turn.sessionId] ?? [], 2)}\n```',
    ]);
    return 'end_turn';
  },

  'opened': (turn) async {
    await turn.say([
      '```json\n${stringify(openedWith[turn.sessionId], 2)}\n```',
    ]);
    return 'end_turn';
  },

  // A reply in markdown, streamed a line at a time, that waits inside its
  // open code fences.
  'markdown': (turn) async {
    final chunks = [
      for (final (index, line) in markdownLines.indexed)
        index == 0 ? line : '\n$line',
    ];
    await turn.say(chunks.sublist(0, markdownOpenFence));
    await pause(turn.signal, stepMs * 300);
    await turn.say(chunks.sublist(markdownOpenFence, markdownOpenNestedFence));
    await pause(turn.signal, stepMs * 300);
    await turn.say(chunks.sublist(markdownOpenNestedFence));
    return 'end_turn';
  },

  // Paragraphs, items and a quote long enough to wrap (CHD-396).
  'markdownwrap': (turn) async {
    await turn.say([markdownWrap]);
    return 'end_turn';
  },

  // Code boxes a copy reads bare (CHD-396).
  'markdowncode': (turn) async {
    await turn.say([markdownCode]);
    return 'end_turn';
  },

  // Graphemes of several code points right before bold and code (CHD-319).
  'graphemes': (turn) async {
    await turn.say([
      [
        'A decomposed é **then bold** and `then code` after it.',
        '',
        '- 👩‍💻 **joined** then `code`',
        '- ⚠️ **warning** then `code`',
        '- 👍🏽 **toned** then `code`',
        '- plain **bold** then `code`',
      ].join('\n'),
    ]);
    return 'end_turn';
  },

  'costwait': _costWait,

  // As `costwait`, and once cancelled, a cost of 0.02 after its answer
  // (CHD-373 S3c).
  'costwaitlate': (turn) async {
    try {
      return await _costWait(turn);
    } finally {
      if (turn.signal.aborted) {
        later(0, () {
          turn.client
              .notify('session/update', {
                'sessionId': turn.sessionId,
                'update': {
                  'sessionUpdate': 'usage_update',
                  'used': 1200,
                  'size': 200000,
                  'cost': {'amount': 0.02, 'currency': 'USD'},
                },
              })
              // The client went first.
              .ignore();
        });
      }
    }
  },

  // Names its session with a `session_info_update` (CHD-491).
  'titled': (turn) async {
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': 'Fix the tokenizer',
    });
    await turn.say(['Named.']);
    return 'end_turn';
  },

  // Names its session, then names it again as the work moves on.
  'retitled': (turn) async {
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': 'Look at the parser',
    });
    await turn.say(['Looking.']);
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': 'Fix the parser',
    });
    await turn.say(['Renamed.']);
    return 'end_turn';
  },

  'titledlook': (turn) async {
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': 'Look at the parser',
    });
    await turn.say(['Looking.']);
    return 'end_turn';
  },

  'titledfix': (turn) async {
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': 'Fix the parser',
    });
    await turn.say(['Renamed.']);
    return 'end_turn';
  },

  'titledlong': (turn) async {
    await turn.send({
      'sessionUpdate': 'session_info_update',
      'title': longSessionTitle,
    });
    await turn.say(['Named at length.']);
    return 'end_turn';
  },

  'slow': (turn) async {
    await turn.say(['Working']);
    for (var i = 0; i < 1000; i++) {
      await turn.say(['.']);
    }
    return 'end_turn';
  },

  // A numbered reply taller than any window.
  'long': (turn) async {
    for (var n = 1; n <= _longLines; n++) {
      await pause(turn.signal, stepMs * 19);
      await turn.say([_longLine(n)]);
    }
    return 'end_turn';
  },

  // `long`'s first 20 lines, then line 21 once the gate is released, then
  // held until it is cancelled (CHD-397, CHD-399).
  'longheld': (turn) async {
    for (var n = 1; n <= 20; n++) {
      await pause(turn.signal, stepMs * 19);
      await turn.say([_longLine(n)]);
    }
    await gateOpened(turn, gateRelease);
    await turn.say([_longLine(21)]);
    await pause(turn.signal, _heldWithinMs);
    return 'end_turn';
  },
};
