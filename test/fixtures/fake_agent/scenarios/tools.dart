// Tool calls: a read, calls as a screen shows them, calls out of order,
// edits with their diffs, a turn of many calls, and headlines longer than a
// row, an MCP call's among them, as the original's scenarios/tools.ts.
import '../../edits.dart';
import '../../headlines.dart';
import '../options.dart';
import '../rpc.dart';
import '../turn.dart';
import 'chord_tools.dart';

/// Calls in a `steps` turn, each an entry of the transcript.
const _steps = 150;

Future<String> _stepsPlay(Turn turn) async {
  for (var step = 1; step <= _steps; step++) {
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': turn.callId('read'),
      'title': 'Read step-$step.ts',
      'kind': 'read',
      'status': 'completed',
    });
  }
  await turn.say(['$_steps steps read.']);
  return 'end_turn';
}

/// A heredoc command, a heading and a list in it, as Claude writes notes.
const _heredoc =
    "cat >> notes.md <<'EOF'\n"
    '## Decisions\n'
    '\n'
    'The headline shows the whole command:\n'
    '\n'
    '- every line of a heredoc\n'
    '- wrapped to the width\n'
    '- with no ctrl+o\n'
    '\n'
    '### Left\n'
    '\n'
    '1. a cap, if ever\n'
    'EOF';

/// A command of one line, over 200 characters.
const _oneLine =
    'cd apps/editor && grep -rn "headline" src/ui/transcript/tools/ '
    '--include="*.ts" --include="*.tsx" | grep -v "_test" | sort | uniq -c | '
    'sort -rn | head -20; git log --oneline -n 5 -- src/ui/transcript/tools/';

/// Lines of the `headlines` scenario's longest command.
const _longCommand = 300;

/// A heredoc of [_longCommand] lines: its opener, numbered lines, `EOF`.
final String _long = [
  "cat > lines.txt <<'EOF'",
  for (var line = 0; line < _longCommand - 2; line++)
    'line ${line + 1} of the long command',
  'EOF',
].join('\n');

/// A command Bash ran, as Claude's adapter titles it, that wrote [output].
Future<String> _ran(Turn turn, String command, String output) async {
  final toolCallId = turn.callId('bash');
  await turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': '`$command`',
    'kind': 'execute',
    'status': 'in_progress',
    'rawInput': {'command': command},
  });
  await turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
    'content': [_text(output)],
  });
  await turn.say(['Done.']);
  return 'end_turn';
}

Map<String, Object?> _text(String value) => {
  'type': 'content',
  'content': {'type': 'text', 'text': value},
};

/// An MCP call's result on one line of JSON.
final String longJson = stringify({
  'status': 'completed',
  'result':
      '# Long MCP result\n\nEvery note in the vault, exported with its tags, '
      'its links and the date it was last changed, so the agent can read '
      'them without opening each file.\n\nEnd of the long result.',
  'logs': <Object?>[],
});

/// A command's output with a line longer than any row.
const longStdout =
    'Building chord for darwin-arm64, linux-x64, linux-arm64, windows-x64 '
    'and darwin-x64 with bun build --compile, the native library embedded '
    'for each target, and the binaries laid out under dist/.\n'
    'Done.';

/// A file's one line before and after an edit that makes it long.
const longDiff = <String, Object?>{
  'path': 'src/greeting.ts',
  'oldText': "export const greeting = 'Hello';\n",
  'newText':
      "export const greeting = 'Hello, and welcome to chord, the terminal ' +\n"
      "  'client for coding agents that speak the Agent Client Protocol, ' + "
      "'run from source';\n",
};

/// A terminal's line longer than any row, as Codex's adapter streams it.
const longTerminal =
    'error: tests/parse/tokenize_test.ts:42 expected the closing quote of a '
    'string at the end of a line to be kept, but the token ended one '
    'character early and the quote was read as the start of the next one\n';

/// `overlap`'s two calls, then its last step once [untilTold] messages
/// were steered into the turn.
Future<String> _overlapping(Turn turn, int untilTold) async {
  Future<void> open(String toolCallId, String title) => turn.send({
    'sessionUpdate': 'tool_call',
    'toolCallId': toolCallId,
    'title': title,
    'kind': 'execute',
    'status': 'in_progress',
  });
  Future<void> end(String toolCallId) => turn.send({
    'sessionUpdate': 'tool_call_update',
    'toolCallId': toolCallId,
    'status': 'completed',
  });

  await open('overlap-a', '`sleep 1`');
  await pause(turn.signal, stepMs * 20);
  await open('overlap-b', '`sleep 2`');
  await pause(turn.signal, stepMs * 20);
  await end('overlap-a');
  await pause(turn.signal, stepMs * 20);
  await end('overlap-b');
  await steeredIn(turn, untilTold);
  await turn.say(['Both slept.']);
  return 'end_turn';
}

String _saved() =>
    'saved "${noteArguments['title']}" '
    '(${(noteArguments['body'] as String).length} chars)';

final Map<String, Play> tools = {
  'steps': _stepsPlay,

  // The same calls after a second's pause.
  'stepslater': (turn) async {
    await pause(turn.signal, stepMs * 200);
    return _stepsPlay(turn);
  },

  'tools': (turn) async {
    final read = turn.callId('read');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': read,
      'title': 'Read README.md',
      'kind': 'read',
      'status': 'pending',
      'locations': [
        {'path': 'README.md'},
      ],
      'rawInput': {'path': 'README.md'},
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': read,
      'status': 'in_progress',
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': read,
      'status': 'completed',
      'content': [_text('# chord')],
      'rawOutput': {'lines': 1},
    });
    await turn.say(['Read it.']);
    return 'end_turn';
  },

  // Results sent only as rawOutput, one call per shape the agents send
  // (CHD-440).
  'rawoutputs': (turn) async {
    const calls = <(String, Object?)>[
      ('Run date', 'Thu Oct 22 12:00:00 UTC 2026\n'),
      ('Run npm test', {'exitCode': 0, 'stdout': 'ok 1\nok 2\n', 'stderr': ''}),
      (
        'Run npm run lint',
        {'exitCode': 1, 'stdout': '', 'stderr': 'src/a.ts:3 unused x\n'},
      ),
      ('View src/a.ts', {'output': 'const x = 1;'}),
      ('Run make', {'result': 'built 3 targets'}),
      (
        'Search TODO',
        {
          'matches': 2,
          'files': ['a.ts', 'b.ts'],
        },
      ),
    ];
    for (final (title, rawOutput) in calls) {
      final id = turn.callId('raw');
      await turn.send({
        'sessionUpdate': 'tool_call',
        'toolCallId': id,
        'title': title,
        'kind': 'execute',
        'status': 'in_progress',
        'rawInput': {'command': title},
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': id,
        'status': 'completed',
        'rawOutput': rawOutput,
      });
    }
    await turn.say(['Ran them.']);
    return 'end_turn';
  },

  // Calls as a screen shows them: long output, a long command in progress
  // a while, and one that fails.
  'calls': (turn) async {
    final source = turn.callId('read');
    final test = turn.callId('bash');
    final missing = turn.callId('read');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': source,
      'title': 'Read src/main.tsx',
      'kind': 'read',
      'status': 'in_progress',
      'locations': [
        {'path': 'src/main.tsx'},
      ],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': source,
      'status': 'completed',
      'content': [
        _text(
          [
            "import { Command } from '@cliffy/command';",
            "import { render } from 'ink';",
            "import { App } from './ui/App.tsx';",
            '',
            'await new Command()',
            "  .name('chord')",
            '  .parse(Deno.args);',
          ].join('\n'),
        ),
      ],
    });
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': test,
      'title':
          '`deno test --allow-read --allow-write --allow-env --allow-run '
          '--allow-sys lint/ tests/ --filter "tool calls draw their status"`',
      'kind': 'execute',
      'status': 'in_progress',
    });
    await pause(turn.signal, stepMs * 300);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': test,
      'status': 'completed',
      'content': [_text('ok | 1 passed | 0 failed (12ms)')],
    });
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': missing,
      'title': 'Read src/missing.ts',
      'kind': 'read',
      'status': 'in_progress',
      'locations': [
        {'path': 'src/missing.ts'},
      ],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': missing,
      'status': 'failed',
      'content': [_text('File does not exist.')],
    });
    await turn.say(['Two calls worked, one failed.']);
    return 'end_turn';
  },

  // Results longer than a row, each to be read whole and wrapped.
  'longresults': (turn) async {
    Future<void> done(
      String toolCallId,
      Map<String, Object?> call,
      List<Object?> content,
    ) => turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'status': 'completed',
      ...call,
      'content': content,
    });

    await done(
      turn.callId('export'),
      {
        'title': 'mcp__notes__export_notes',
        'kind': 'other',
        'rawInput': <String, Object?>{},
      },
      [_text(longJson)],
    );
    await done(
      turn.callId('build'),
      {'title': '`bun dev compile --all`', 'kind': 'execute'},
      [_text(longStdout)],
    );
    await done(
      turn.callId('edit'),
      {'title': 'Edit src/greeting.ts', 'kind': 'edit'},
      [
        {'type': 'diff', ...longDiff},
      ],
    );

    final shell = turn.callId('shell');
    final terminalId = 'terminal-$shell';
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': shell,
      'title': 'Run bun dev test',
      'kind': 'execute',
      'status': 'in_progress',
      'content': [
        {'type': 'terminal', 'terminalId': terminalId},
      ],
      '_meta': {
        'terminal_info': {'terminal_id': terminalId},
      },
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': shell,
      'status': 'failed',
      '_meta': {
        'terminal_output_delta': {
          'terminal_id': terminalId,
          'data': longTerminal,
        },
        'terminal_exit': {
          'terminal_id': terminalId,
          'exit_code': 1,
          'signal': null,
        },
      },
    });
    await turn.say(['Four long results.']);
    return 'end_turn';
  },

  // As `overlap`, but `a` ends failed.
  'overlapfail': (turn) async {
    Future<void> open(String toolCallId, String title) => turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': title,
      'kind': 'execute',
      'status': 'in_progress',
    });
    await open('overlapfail-a', '`false`');
    await pause(turn.signal, stepMs * 20);
    await open('overlapfail-b', '`sleep 2`');
    await pause(turn.signal, stepMs * 20);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'overlapfail-a',
      'status': 'failed',
    });
    await pause(turn.signal, stepMs * 20);
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': 'overlapfail-b',
      'status': 'completed',
    });
    await turn.say(['One failed, one slept.']);
    return 'end_turn';
  },

  // Two calls that overlap.
  'overlap': (turn) => _overlapping(turn, 0),

  // As `overlap`, its next step waiting for two messages steered in
  // (CHD-399).
  'overlaptwo': (turn) => _overlapping(turn, 2),

  // What a client has to survive: an update before its call, the call sent
  // twice, and a stale status after the call finished.
  'unordered': (turn) async {
    final id = turn.callId('grep');
    final call = {
      'toolCallId': id,
      'title': 'Search for TODO',
      'kind': 'search',
      'status': 'pending',
    };
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': id,
      'status': 'in_progress',
    });
    await turn.send({'sessionUpdate': 'tool_call', ...call});
    await turn.send({'sessionUpdate': 'tool_call', ...call});
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': id,
      'status': 'completed',
      'content': [_text('src/main.tsx:1: TODO')],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': id,
      'status': 'in_progress',
    });
    await turn.say(['Searched.']);
    return 'end_turn';
  },

  'edit': (turn) async {
    final edit = turn.callId('edit');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': edit,
      'title': 'Edit src/greeting.ts',
      'kind': 'edit',
      'status': 'in_progress',
      'locations': [
        {'path': 'src/greeting.ts', 'line': 1},
      ],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': edit,
      'status': 'completed',
      'content': [
        {
          'type': 'diff',
          'path': 'src/greeting.ts',
          'oldText': editOld,
          'newText': editNew,
        },
      ],
    });
    await turn.say(['Edited.']);
    return 'end_turn';
  },

  'rewrite': (turn) async {
    final rewrite = turn.callId('rewrite');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': rewrite,
      'title': 'Edit src/table.ts',
      'kind': 'edit',
      'status': 'in_progress',
      'locations': [
        {'path': 'src/table.ts', 'line': 1},
      ],
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': rewrite,
      'status': 'completed',
      'content': [
        {
          'type': 'diff',
          'path': 'src/table.ts',
          'oldText': rewriteOld,
          'newText': rewriteNew,
        },
      ],
    });
    await turn.say(['Rewrote the table.']);
    return 'end_turn';
  },

  // Headlines longer than a row, each answered with a line.
  'headlines': (turn) async {
    final calls = <(Map<String, Object?>, String)>[
      (
        {
          'toolCallId': turn.callId('bash'),
          'title': '`$_heredoc`',
          'kind': 'execute',
          'rawInput': {'command': _heredoc},
        },
        '(no output)',
      ),
      (
        {
          'toolCallId': turn.callId('bash'),
          'title': '`$_oneLine`',
          'kind': 'execute',
          'rawInput': {'command': _oneLine},
        },
        '     12 src/ui/transcript/tools/tools.ts',
      ),
      (
        {
          'toolCallId': turn.callId('send'),
          'title': 'mcp__chord__send_message',
          'kind': 'other',
          'rawInput': {
            'to': 'reviewer',
            'text':
                'CHD-393 U1 is done: the headlines scenario plays a heredoc, '
                'a long one-line command, this call and a command of 300 '
                'lines; nothing of chord changes, so it goes to you directly.',
          },
        },
        'Delivered to reviewer.',
      ),
      (
        {
          'toolCallId': turn.callId('bash'),
          'title': '`$_long`',
          'kind': 'execute',
          'rawInput': {'command': _long},
        },
        '(no output)',
      ),
    ];
    for (final (call, output) in calls) {
      await turn.send({
        'sessionUpdate': 'tool_call',
        ...call,
        'status': 'in_progress',
      });
      await turn.send({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': call['toolCallId'],
        'status': 'completed',
        'content': [_text(output)],
      });
    }
    await turn.say(['Four calls with long headlines.']);
    return 'end_turn';
  },

  // The calls of the Claude Code capture in docs/design/CHD-393.md.
  'heredoc': (turn) => _ran(turn, notesCommand, '      10 notes.md'),
  'longcommand': (turn) => _ran(turn, weatherCommand, '309'),

  // The capture's MCP call as codex-acp sends one (CHD-419).
  'codexmcpnote': (turn) async {
    final toolCallId = turn.callId('save_note');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'status': 'in_progress',
      ...codexCall('notes', 'save_note', noteArguments),
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'completed',
      'content': [_text(_saved())],
    });
    await turn.say(['Done.']);
    return 'end_turn';
  },

  // The capture's MCP call, as claude-agent-acp sends one.
  'mcpnote': (turn) async {
    final toolCallId = turn.callId('save_note');
    await turn.send({
      'sessionUpdate': 'tool_call',
      'toolCallId': toolCallId,
      'title': 'mcp__notes__save_note',
      'kind': 'other',
      'status': 'pending',
      'rawInput': <String, Object?>{},
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'in_progress',
      'rawInput': noteArguments,
    });
    await turn.send({
      'sessionUpdate': 'tool_call_update',
      'toolCallId': toolCallId,
      'status': 'completed',
      'content': [_text(_saved())],
    });
    await turn.say(['Done.']);
    return 'end_turn';
  },
};
