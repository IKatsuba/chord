// Long-lived agents, as the original's scenarios/agents.ts: a session that
// opens two on the fake runtime through chord's `open_agent` and messages
// one of them twice, the child's first turn, which messages its parent
// twice, sessions that close, clear and message children, as Claude and
// Codex do, and the gate a test meets a session's turn at.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mcp_dart/mcp_dart.dart' as mcp;
import 'package:path/path.dart' as p;

import '../options.dart';
import '../sessions.dart';
import '../turn.dart';
import 'chord_tools.dart';

/// The directory, in a session's own, where a play meets a test.
const gate = '.fake-gate';
const gateOpen = 'open';
const gateRelease = 'release';

/// Until [file] is in the gate of [turn]'s session, or 10 s without it
/// (CHD-399).
Future<void> gateOpened(Turn turn, String file) async {
  final at = p.join(cwds[turn.sessionId] ?? '.', gate, file);
  final deadline = DateTime.now().millisecondsSinceEpoch + 10000;
  while (!File(at).existsSync() &&
      DateTime.now().millisecondsSinceEpoch < deadline) {
    await pause(turn.signal, stepMs * 2);
  }
}

/// The mark in a gate that its session has heard [text], told it in a
/// message.
String toldMark(String text) =>
    'told-${sha1.convert(utf8.encode(text.trim())).toString().substring(0, 12)}';

final _told = RegExp(
  r'<message from="[^"]*"(?: monitor="[^"]*")?>\n([\s\S]*?)\n<\/message>',
);

/// Marks in [sessionId]'s gate each message [text] tells it, as it hears
/// it, only where the gate is (CHD-501).
void heard(String sessionId, String text) {
  final at = p.join(cwds[sessionId] ?? '.', gate);
  if (!Directory(at).existsSync()) return;
  for (final match in _told.allMatches(text)) {
    File(p.join(at, toldMark(match.group(1)!))).writeAsStringSync('');
  }
}

/// Until [file] is in the gate of [turn]'s session, or the turn is stopped.
Future<void> _gated(Turn turn, String file) async {
  final at = p.join(cwds[turn.sessionId] ?? '.', gate, file);
  while (!File(at).existsSync() && !turn.signal.aborted) {
    await pause(turn.signal, stepMs * 2);
  }
}

/// A child's pace: 2 steps. Where an order is a gate's, the pace is only
/// how a turn's steps are spread (CHD-501).
num get _agentStepMs => stepMs * 2;

/// The pace before CHD-501, kept where a wait stands for something no gate
/// says yet.
num get _heldStepMs => stepMs * 20;

/// What `agents` opens first: the fake runtime's small model on
/// `agentchild`; on another runtime `--child-runtime` names, its own model.
final Map<String, Object?> parserArgs = {
  'agent': childRuntimeGiven ?? 'fake',
  if (childModel != null)
    'model': childModel
  else if ((childRuntimeGiven ?? 'fake') == 'fake')
    'model': 'fake-small',
  'prompt': said['agentchild'] ?? 'agentchild',
  'name': 'parser',
};

/// What it opens second, on the runtime's own model, which asks to write.
final Map<String, Object?> docsArgs = {
  'agent': childRuntimeGiven ?? 'fake',
  'model': ?childModel,
  'prompt': said['permission'] ?? 'permission',
  'name': 'docs',
};

/// What `agentother` opens: `other` on another runtime, [childRuntime].
final Map<String, Object?> otherArgs = {
  'agent': childRuntime,
  'prompt': 'text',
  'name': 'other',
};

/// The parent's two messages to `parser`.
const mainMessages = [
  'I changed how a string at the end of a line is read. Run the parser '
      'tests now and tell me only what fails.',
  'The printer is fixed too; run the whole parser suite once more.',
];

/// What `agenttitled` names the child it opens (CHD-471).
const longTitle =
    'Summarise the release notes for 0.56.0 from the commits since 0.55.2, '
    'grouped by area, with a line for each user-facing change and a note for '
    'each breaking one, then draft the announcement for the forum and the '
    'changelog entry, and list the open questions for the owner to settle '
    'before the tag.';

/// A long instruction with markdown in it, as a parent opens a child on.
const longInstruction =
    'Read AGENTS.md and docs/FEATURES.md before you start. Then:\n'
    '\n'
    '1. Fix the tokenizer so a string at the end of a line keeps its closing '
    'quote.\n'
    '2. Add two cases to `tests/parse/tokenize_test.ts`.\n'
    '3. Run `bun quality` in the foreground and **do not** hand back until '
    'it passes.\n'
    '\n'
    'Tell me only what failed, if anything.';

/// What `agentcall` tells `parser` while its call is open.
const heldMessage = 'Then the docs, once the tests pass.';

/// What `agentcalltwice` tells `parser` after [heldMessage].
const heldAgain = 'And the changelog after the docs.';

/// A short message to `parser`, sent before [longMessage].
const shortMessage = 'Start on the tokenizer; the printer can wait.';

/// A review sent as a message, longer than a message's six lines.
const longMessage =
    'CHD-1 unit 4: points 1 and 2 are good. Four things before I look again:\n'
    '\n'
    '1. The fold counts the blank line after the list; drop it, as '
    '`foldMessage` already does for a received message.\n'
    '2. `foldMessage` runs on every render; keep its lines in the same '
    '`useMemo` as the markdown.\n'
    '3. The hint names ctrl+o even when the person has rebound it; take the '
    'key from `useHintKey`.\n'
    '4. The refusal goes after the body, in the error colour, **never** '
    'folded.\n'
    '\n'
    'Commit each as its own fix, run the targeted tests, and tell me when '
    "the check passes and I'll look again.";

/// Two paragraphs of Cyrillic prose, each a few rows long at 120 columns.
const proseRu =
    'Это длинное тестовое сообщение для проверки передачи текста между '
    'агентами. В нём нет задания на изменение кода, запуск проверок или '
    'работу с файлами: оно предназначено только для проверки доставки и '
    'отображения большого объёма текста.\n'
    '\n'
    'Представим небольшую обсерваторию на вершине холма. Каждое утро '
    'смотритель открывает деревянные ставни, проверяет журнал наблюдений и '
    'ставит чайник на старую плиту. За окном медленно расходится туман, на '
    'дорожке появляются первые солнечные пятна, а в саду перекликаются '
    'птицы.';

/// A paragraph of ASCII prose a few rows long at 120 columns.
const proseEn =
    'The printer is fixed, and every case in tests/parse/printer_test.ts '
    'passes now. The tokenizer still drops a closing quote when a string '
    'ends the line, so I left a failing case for it beside the others and '
    'wrote down what I found in the notes, with the input that shows it and '
    'the line in src/parse/tokenize.ts where the quote is lost.';

/// What a child's last words are when its agent exits mid-turn.
const crashWords =
    'fatal: out of memory reading tests/parse/fixtures/huge.json';

/// The parent's message to `docs` while `docs` waits on its permission.
const docsMessage =
    'When the README section is done, add the new flag to docs/FEATURES.md.';

/// `parser`'s two messages to its parent.
const childMessages = [
  'Ran bun dev test tests/parse: 2 failures, both in '
      'tests/parse/printer_test.ts.',
  'All 214 parser tests pass now.',
];

Future<String> _noServer(Turn turn) async {
  await turn.say(['No chord server in this session.']);
  return 'end_turn';
}

/// Opens `parser` with [prompt] as its first turn, then waits on it.
Future<String> _openParserOn(Turn turn, String prompt, [String? name]) async {
  final named = name ?? parserArgs['name'] as String;
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', {
      ...parserArgs,
      'prompt': prompt,
      'name': named,
    });
    await turn.say([
      'Waiting on ${named == parserArgs['name'] ? named : 'it'}.',
    ]);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// Opens `parser` on [prompt], which answers, and sends it [texts], its
/// calls in [shape]'s adapter's.
Future<String> _sendParser(
  Turn turn,
  String shape, [
  String prompt = 'agentchild',
  List<String> texts = const [shortMessage, longMessage],
]) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', {
      ...parserArgs,
      'prompt': prompt,
    }, shape: shape);
    for (final text in texts) {
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': text,
      }, shape: shape);
      await pause(turn.signal, _agentStepMs * 10);
    }
    await turn.say(['Waiting on parser.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// [proseRu] and [proseEn] to the parent, in [shape]'s adapter's calls.
Future<String> _sendProse(Turn turn, String shape) async {
  final client = await chordClient(turn);
  try {
    for (final text in [proseRu, proseEn]) {
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'text': text,
        }, shape: shape);
      }
    }
    await turn.say(['Both sent back.']);
  } finally {
    await client?.close();
  }
  return 'end_turn';
}

/// Opens `parser` on [child] and, a moment into its call, or once a gated
/// child says it is open, tells it each of [texts] in turn.
Future<String> _tellParserDuringCall(
  Turn turn,
  List<String> texts, [
  String child = 'callchild',
]) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', {
      ...parserArgs,
      'prompt': child,
    });
    // The gated child says when its call is open; the other is given a
    // moment.
    if (child == 'callchildgated') {
      await _gated(turn, gateOpen);
    } else {
      await pause(turn.signal, _heldStepMs * 2);
    }
    for (final text in texts) {
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': text,
      });
    }
    await turn.say(['Waiting on parser.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// A call of the child's own, done after a step.
Future<void> _work(Turn turn, String title, String output) async {
  final toolCallId = turn.callId('execute');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': title,
    'kind': 'execute',
    'status': 'in_progress',
  });
  await pause(turn.signal, _agentStepMs * 10);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [_text(output)],
  });
}

/// One call for about three seconds, then a report that the tests pass;
/// its next step waits until [untilTold] messages were steered in.
Future<String> _callChild(Turn turn, [int untilTold = 0]) async {
  final toolCallId = turn.callId('execute');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': '`bun dev test`',
    'kind': 'execute',
    'status': 'in_progress',
  });
  await pause(turn.signal, _heldStepMs * 30);
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [_text('214 passed, 0 failed')],
  });
  await steeredIn(turn, untilTold);
  await turn.say(['The tests pass.']);
  return 'end_turn';
}

/// Opens `docs` on `permission` and messages it: after a pause, or with
/// [gated] once the gate is released.
Future<String> _messageDocsAsking(Turn turn, bool gated) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', docsArgs);
    if (gated) {
      await gateOpened(turn, gateRelease);
    } else {
      await pause(turn.signal, _agentStepMs * 10);
    }
    await callChord(turn, client, 'send_message', {
      'to': 'docs',
      'text': docsMessage,
    });
    await turn.say(['Waiting on docs.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// Opens `parser` and `docs`, then sends `parser` each of [messages], the
/// next once parser has the one before.
Future<String> _openTeam(Turn turn, List<String> messages) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    Directory(
      p.join(cwds[turn.sessionId] ?? '.', gate),
    ).createSync(recursive: true);
    await turn.say(['I will open parser on the tests and docs on the README.']);
    await callChord(turn, client, 'open_agent', parserArgs);
    await callChord(turn, client, 'open_agent', docsArgs);
    await gateOpened(turn, toldMark(parserArgs['prompt'] as String));
    for (final text in messages) {
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': text,
      });
      await gateOpened(turn, toldMark(text));
    }
    await turn.say(['Waiting on parser.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// Opens `parser` and `docs`, each on a scenario that titles its session.
Future<String> _openTitled(Turn turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', {
      ...parserArgs,
      'prompt': 'titled',
    });
    await callChord(turn, client, 'open_agent', {
      ...docsArgs,
      'prompt': 'retitled',
    });
    await turn.say(['Waiting on parser and docs.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

/// Opens `other` on [childRuntime] and says so.
Future<String> _openOther(Turn turn) async {
  final client = await chordClient(turn);
  if (client == null) return _noServer(turn);
  try {
    await callChord(turn, client, 'open_agent', otherArgs);
    await turn.say(['Opened other on $childRuntime.']);
  } finally {
    await client.close();
  }
  return 'end_turn';
}

final Map<String, Play> agentPlays = {
  'agentmentions': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return 'end_turn';
    try {
      for (final name in ['parser', 'docs']) {
        await callChord(turn, client, 'open_agent', {
          'agent': 'fake',
          'name': name,
          'prompt': 'text',
        });
      }
      for (final prompt in [
        'First completion team.',
        'Second completion team.',
      ]) {
        await callChord(turn, client, 'run_team', {
          'team': 'bugfix',
          'job': prompt,
        });
      }
      await turn.say(['Agent completion sessions opened.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  'agentnames': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return 'end_turn';
    try {
      await callChord(turn, client, 'open_agent', {
        'agent': 'fake',
        'name': 'a "b @notes.md suffix',
        'prompt': 'text',
      });
      await callChord(turn, client, 'open_agent', {
        'agent': 'bad"runtime',
        'prompt': 'text',
      });
      for (final name in [
        'a\n@notes.md suffix',
        'a\rline',
        'a\ttab',
        'a\u0000nul',
        'a\u007Fdel',
      ]) {
        await callChord(turn, client, 'open_agent', {
          'agent': 'fake',
          'name': name,
          'prompt': 'text',
        });
      }
      await turn.say(['Quoted agent names refused.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A child on another runtime (CHD-493).
  'agentother': _openOther,

  // Each child names its own session, the second renames it (CHD-445).
  'agentstitled': _openTitled,

  // Opens `parser` and `docs`, then tells `parser` twice what changed.
  'agents': (turn) => _openTeam(turn, mainMessages),

  // As `agents`, telling `parser` nothing (CHD-507).
  'agentsquiet': (turn) => _openTeam(turn, const []),

  // Opens `docs`, which asks to write, and messages it while it waits.
  'agentsheld': (turn) => _messageDocsAsking(turn, false),

  // As `agentsheld`, the message sent once the gate is released (CHD-399).
  'agentsheldgated': (turn) => _messageDocsAsking(turn, true),

  // `parser`'s first turn: a test run, a message to its parent, another
  // run and a second message.
  'agentchild': (turn) async {
    final client = await chordClient(turn);
    try {
      await _work(turn, '`bun dev test tests/parse`', '2 failed, 212 passed');
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'text': childMessages[0],
        });
      }
      await _work(turn, '`bun dev test tests/parse`', '214 passed, 0 failed');
      if (client != null) {
        await callChord(turn, client, 'send_message', {
          'text': childMessages[1],
        });
      }
      await turn.say(['I will run the parser tests on each change.']);
    } finally {
      await client?.close();
    }
    return 'end_turn';
  },

  // Opens `parser` on `task`, so the child starts a task agent of its own.
  'agenttask': (turn) => _openParserOn(turn, 'task'),

  // Opens `parser` on `costwait` (CHD-373).
  'agentcost': (turn) => _openParserOn(turn, 'costwait'),

  // Opens `parser` on a long instruction.
  'agentlong': (turn) => _openParserOn(turn, longInstruction),

  // Opens `parser` on `crash`, whose agent exits in its first turn.
  'agentexit': (turn) => _openParserOn(turn, 'crash'),

  // Opens `parser` on `error`, whose first turn fails with its agent up.
  'agentfail': (turn) => _openParserOn(turn, 'error'),

  // Opens a child on `text` under [longTitle].
  'agenttitled': (turn) => _openParserOn(turn, 'text', longTitle),

  // A child's turn whose agent goes: a test run, its last words on stderr,
  // then the exit, with the turn never answered.
  'crash': (turn) async {
    await _work(turn, '`bun dev test tests/parse`', 'Killed');
    stderr.writeln(crashWords);
    // Long enough for the line to reach chord before the pipe closes.
    await pause(turn.signal, _heldStepMs);
    exit(1);
  },

  // Messages `parser`, clears it, messages it again, and asks to clear one
  // it never opened (CHD-476).
  'agentclear': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': 'Queued before the clear.',
      });
      await callChord(turn, client, 'clear_agent', {'to': 'parser'});
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': 'text',
      });
      await callChord(turn, client, 'clear_agent', {'to': 'nobody'});
      await turn.say(['parser was cleared.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Opens `parser` on `latesay` (CHD-476).
  'agentlate': (turn) => _openParserOn(turn, 'latesay'),

  // Clears `parser` and says so.
  'agentclearonly': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'clear_agent', {'to': 'parser'});
      await turn.say(['parser was cleared.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // A child's turn that works until it is stopped, then tries to message
  // its parent from the session that was let go.
  'latesay': (turn) async {
    final client = await chordClient(turn);
    try {
      await turn.say(['Working until stopped.']);
      try {
        await untilAborted(turn.signal, unless: lifetime.signal);
      } catch (_) {}
      try {
        await client?.callTool(
          const mcp.CallToolRequest(
            name: 'send_message',
            arguments: {'text': 'Late from the old session.'},
          ),
        );
      } catch (_) {}
    } finally {
      try {
        await client?.close();
      } catch (_) {}
    }
    return 'end_turn';
  },

  // Closes `parser`, then messages it, which chord refuses.
  'agentclose': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'close_agent', {'to': 'parser'});
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': 'Are you still there?',
      });
      await turn.say(['parser is closed, so I will run the tests myself.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },

  // Tells `parser` [heldMessage] while its call is open.
  'agentcall': (turn) => _tellParserDuringCall(turn, const [heldMessage]),

  // Gated for a test: both messages told once `parser`'s call is open.
  'agentcallgated': (turn) => _tellParserDuringCall(turn, const [
    heldMessage,
    heldAgain,
  ], 'callchildgated'),

  // One call open from the turn's start, [gateOpen] written once it is,
  // until the gate is released, then the answer.
  'callchildgated': (turn) async {
    final toolCallId = turn.callId('execute');
    final at = p.join(cwds[turn.sessionId] ?? '.', gate);
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': '`bun dev test`',
      'kind': 'execute',
      'status': 'in_progress',
    });
    Directory(at).createSync(recursive: true);
    File(p.join(at, gateOpen)).writeAsStringSync('');
    await _gated(turn, gateRelease);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'completed',
      'content': [_text('214 passed, 0 failed')],
    });
    await turn.say(['The tests pass.']);
    return 'end_turn';
  },

  // The same with [heldAgain] after it, both told during that one call.
  'agentcalltwice': (turn) =>
      _tellParserDuringCall(turn, const [heldMessage, heldAgain]),

  // One call open from the turn's start for about 3 s.
  'callchild': (turn) => _callChild(turn),

  // As callchild, waiting for two messages steered in after the call.
  'callchildtwo': (turn) => _callChild(turn, 2),

  // A short message and a long one to `parser`, as Claude and as Codex.
  'agentsend': (turn) => _sendParser(turn, 'claude'),
  'codexagentsend': (turn) => _sendParser(turn, 'codex'),

  // Long paragraphs to `parser`, which sends both back.
  'agentprose': (turn) =>
      _sendParser(turn, 'claude', 'prosechild', const [proseRu, proseEn]),
  'codexagentprose': (turn) =>
      _sendParser(turn, 'codex', 'codexprosechild', const [proseRu, proseEn]),
  'prosechild': (turn) => _sendProse(turn, 'claude'),
  'codexprosechild': (turn) => _sendProse(turn, 'codex'),

  // [longMessage] to `parser`, which was never opened: chord refuses it.
  'agentsendrefused': (turn) async {
    final client = await chordClient(turn);
    if (client == null) return _noServer(turn);
    try {
      await callChord(turn, client, 'send_message', {
        'to': 'parser',
        'text': longMessage,
      });
      await turn.say(['parser is not open, so I will review it myself.']);
    } finally {
      await client.close();
    }
    return 'end_turn';
  },
};
