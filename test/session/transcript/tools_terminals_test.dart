// The terminal cases of the original's transcript/tools_test.ts: a tool
// call's terminals folded from its `_meta`. Left for later: a session
// resumed from the agent's replay or chord's record, which M1 does not
// open; each such case keeps its live half here.
import 'dart:convert';

import 'package:chord/session/terminal_text.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

/// A tool call update for call `c1`, carrying [meta] and [fields].
UpdateAction _terminalUpdate(
  Map<String, Object?> meta, [
  Map<String, Object?> fields = const {},
]) => update('t1', {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': 'c1',
  ...fields,
  '_meta': meta,
});

/// The terminals of the one tool call in [transcript], as plain values.
List<Map<String, Object?>>? _terminalsOf(Transcript transcript) => transcript
    .entries
    .whereType<ToolEntry>()
    .single
    .call
    .terminals
    ?.map(describedTerminal)
    .toList();

/// The one terminal [pieces] write, each a delta of its own.
Map<String, Object?> _cutOutput(List<String> pieces) => _terminalsOf(
  fold([
    const PromptAction('t1', 'shell', 0),
    for (final data in pieces)
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'x', 'data': data},
      }),
  ]),
)!.single;

void main() {
  test("a terminal's output grows by deltas and ends with the exit that "
      'carries the last of it', () {
    final actions = <TranscriptAction>[
      const PromptAction('t1', 'shell', 0),
      update('t1', {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'c1',
        'title': 'Run make',
        'kind': 'execute',
        'status': 'in_progress',
        'content': [
          {'type': 'terminal', 'terminalId': 'x'},
        ],
        '_meta': {
          'terminal_info': {'terminal_id': 'x', 'cwd': '/work'},
        },
      }),
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'x', 'data': 'a\n'},
      }),
      // An escape cut in two by the pieces it came in.
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'x', 'data': '\x1b[3'},
      }),
      _terminalUpdate(
        {
          'terminal_output_delta': {'terminal_id': 'x', 'data': '1mb\x1b[0m\n'},
          'terminal_exit': {'terminal_id': 'x', 'exit_code': 2, 'signal': null},
        },
        {'status': 'failed'},
      ),
    ];
    final seen = states(actions);

    expect(_terminalsOf(seen[1]), [
      {'id': 'x', 'output': '', 'cwd': '/work', 'exited': false},
    ]);
    expect(_terminalsOf(seen[2]), [
      {'id': 'x', 'output': 'a\n', 'cwd': '/work', 'exited': false},
    ]);
    expect(_terminalsOf(seen[3]), [
      {
        'id': 'x',
        'output': 'a\n',
        'escape': {'kind': 'csi', 'params': '3'},
        'cwd': '/work',
        'exited': false,
      },
    ]);
    expect(_terminalsOf(fold(actions)), [
      {
        'id': 'x',
        'output': 'a\nb\n',
        'cwd': '/work',
        'exited': true,
        'exitCode': 2,
      },
    ]);
  });

  test(
    "a terminal's whole output replaces what it had, and a signal ends it",
    () {
      final big = '${'x' * outputLimit}\n';

      expect(
        _terminalsOf(
          fold([
            const PromptAction('t1', 'bash', 0),
            _terminalUpdate({
              'terminal_info': {'terminal_id': 'x'},
            }),
            _terminalUpdate({
              'terminal_output_delta': {'terminal_id': 'x', 'data': big},
            }),
            _terminalUpdate({
              'terminal_output': {'terminal_id': 'x', 'data': 'all\n'},
            }),
            _terminalUpdate({
              'terminal_exit': {
                'terminal_id': 'x',
                'exit_code': null,
                'signal': 'SIGINT',
              },
            }),
          ]),
        ),
        [
          {'id': 'x', 'output': 'all\n', 'exited': true, 'signal': 'SIGINT'},
        ],
      );
    },
  );

  test('a terminal keeps the last of its output past the limit, from a line '
      'start', () {
    final head = '${'h' * 10}\n';
    final tail = '${'t' * (outputLimit - 5)}\n';

    expect(_cutOutput([head, tail, 'z']), {
      'id': 'x',
      'output': '${tail}z',
      'exited': false,
      'truncated': true,
    });
  });

  test('a terminal cut past the limit starts at a line, and an escape before '
      'it no longer counts', () {
    final lines = [
      for (var index = 0; index < 4; index++)
        '${'$index' * (outputLimit ~/ 3)}\n',
    ];
    final cut = _cutOutput(lines);

    expect(cut['output'], lines.skip(2).join());
    expect(cut['truncated'], isTrue);

    // A line whose link's escape began before the bound is kept whole,
    // since the escape is gone before the bound is counted.
    final link = _cutOutput([
      'head\n\x1b]8;;https://${'u' * 5000}\x07',
      '${'x' * (outputLimit - 10)}\x1b]8;;\x07',
    ]);

    expect(link['output'], 'head\n${'x' * (outputLimit - 10)}');
    expect(link.containsKey('truncated'), isFalse);
  });

  test(
    'a terminal sent a cursor move of any length stays within the bound',
    () {
      final far = '\x1b[${'9' * 15}C';
      final moved = _cutOutput([far, 'X', '\n${far}Y' * 100, far]);
      final output = moved['output'] as String;

      expect(output.length, lessThanOrEqualTo(outputLimit));
      expect(moved['truncated'], isTrue);
      expect(output.endsWith('${' ' * columnLimit}Y'), isTrue);
    },
  );

  // Escapes no delta ends, whatever their length: an OSC's body, an
  // introducer's intermediates, the bytes a terminal ignores inside one, and
  // a CSI's parameters, each twice the bound and fed in pieces.
  for (final (name, opener, filler, end) in [
    ('an OSC', '\x1b]8;;https://', 'u', '\x07visible'),
    ('an introducer', '\x1b', ' ', '0visible'),
    ('ignored bytes', '\x1b', '\x00', ']u\x07visible'),
    ('a CSI', '\x1b[', '1;', 'mvisible'),
    ('a C1 string', 'gone\n\x9d8;;', 'u', '\x9cvisible'),
  ]) {
    test('a terminal holds $name no delta ends within a constant, and shows '
        'what follows its end', () {
      final body = filler * (outputLimit * 2);
      final pieces = [opener, body, body.substring(0, outputLimit), end];

      for (var count = 1; count < pieces.length; count++) {
        final open = _cutOutput(pieces.sublist(0, count));

        expect(
          (open['output'] as String).length,
          lessThanOrEqualTo(outputLimit),
        );
        expect(open['escape'], isNotNull, reason: 'still open');
        expect(
          jsonEncode(open['escape']).length,
          lessThanOrEqualTo(64),
          reason: 'held within bounds',
        );
      }

      final ended = _cutOutput(pieces);

      expect((ended['output'] as String).endsWith('visible'), isTrue);
      expect(ended['escape'], isNull);
    });
  }

  for (final (name, pieces) in [
    ('an OSC', ['\x1b]8;;https://${'u' * outputLimit}', '\x07visible']),
    (
      'an oversized introducer',
      ['\x1b${' ' * (outputLimit * 2)}', ' ' * outputLimit, '0visible'],
    ),
    (
      'an introducer full of ignored bytes',
      ['\x1b${'\x00' * (outputLimit * 2)}]u', 'u' * outputLimit, '\x07visible'],
    ),
    // An OSC an `ESC` breaks off, then a sequence of its own.
    ('an OSC broken off by an escape', ['\x1b]8;;https://a\x1b', 'bvisible']),
    // An `ESC` with an intermediate, ended by its final byte.
    ('an escape with an intermediate', ['\x1b', ' 0visible']),
  ]) {
    test(
      'a terminal inside $name that a later piece ends shows what follows',
      () {
        expect(_cutOutput(pieces)['output'], 'visible');
      },
    );
  }

  test("a terminal's signal is kept as plain as its output", () {
    expect(
      _terminalsOf(
        fold([
          const PromptAction('t1', 'shell', 0),
          _terminalUpdate({
            'terminal_exit': {
              'terminal_id': 'x',
              'exit_code': null,
              'signal': 'SIGTERM\x1b[31mRED\x1b[0m\x1b[2J',
            },
          }),
        ]),
      )!.single['signal'],
      'SIGTERMRED',
    );
  });

  test('each terminal of a call keeps its own output, and a malformed one '
      'leaves the rest of the update', () {
    final transcript = fold([
      const PromptAction('t1', 'shell', 0),
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'x', 'data': '1'},
      }),
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'y', 'data': '2'},
      }),
      _terminalUpdate(
        {
          'terminal_output_delta': {'terminal_id': 'x', 'data': 3},
          'terminal_exit': {'terminal_id': 'y', 'exit_code': 0},
        },
        {'status': 'completed'},
      ),
    ]);

    expect(
      transcript.entries.whereType<ToolEntry>().single.call.status,
      'completed',
    );
    expect(_terminalsOf(transcript), [
      {'id': 'x', 'output': '1', 'exited': false},
      {'id': 'y', 'output': '2', 'exited': true, 'exitCode': 0},
    ]);
  });

  test('a tool call that names no terminal has none', () {
    final transcript = fold([
      const PromptAction('t1', 'tools', 0),
      _terminalUpdate({
        'claudeCode': {'toolName': 'Read'},
      }),
    ]);

    expect(
      transcript.entries.whereType<ToolEntry>().single.call.terminals,
      isNull,
    );
  });

  test('a field of a terminal sent malformed leaves it out, the rest '
      'read', () {
    expect(
      _terminalsOf(
        fold([
          const PromptAction('t1', 'shell', 0),
          _terminalUpdate({
            'terminal_info': {'terminal_id': 'x', 'cwd': 7},
            'terminal_output': {'terminal_id': 9, 'data': 'no'},
            'terminal_exit': {'terminal_id': 'x', 'exit_code': 'one'},
          }),
          _terminalUpdate({
            'terminal_output_delta': {'terminal_id': 'x', 'data': 'yes'},
            'terminal_exit': {'terminal_id': 'x', 'signal': 3},
          }),
        ]),
      ),
      [
        {'id': 'x', 'output': 'yes', 'exited': false},
      ],
    );
  });

  test("an exit code is carried as the agent's number, a float included", () {
    expect(
      _terminalsOf(
        fold([
          const PromptAction('t1', 'shell', 0),
          _terminalUpdate({
            'terminal_exit': {'terminal_id': 'x', 'exit_code': 2.5},
          }),
        ]),
      )!.single['exitCode'],
      2.5,
    );
  });

  test('an exit code that is no finite number leaves the exit out, and the '
      "update's output still folds", () {
    for (final code in [double.infinity, double.nan, double.negativeInfinity]) {
      expect(
        _terminalsOf(
          fold([
            const PromptAction('t1', 'shell', 0),
            _terminalUpdate({
              'terminal_output_delta': {'terminal_id': 'x', 'data': 'out'},
              'terminal_exit': {'terminal_id': 'x', 'exit_code': code},
            }),
          ]),
        ),
        [
          {'id': 'x', 'output': 'out', 'exited': false},
        ],
        reason: '$code',
      );
    }
  });

  test('terminal content with no terminal id is a malformed update, and '
      'leaves the identical state', () {
    final state = fold([const PromptAction('t1', 'shell', 0)]);

    expect(
      identical(
        reduceTranscript(
          state,
          _terminalUpdate({}, {
            'content': [
              {'type': 'terminal'},
            ],
          }),
        ),
        state,
      ),
      isTrue,
    );
  });

  test('an update that changes no terminal keeps the identical list', () {
    final before = fold([
      const PromptAction('t1', 'shell', 0),
      _terminalUpdate({
        'terminal_output_delta': {'terminal_id': 'x', 'data': 'a'},
      }),
    ]);
    final after = reduceTranscript(
      before,
      _terminalUpdate({}, {'status': 'completed'}),
    );

    expect(
      identical(
        after.entries.whereType<ToolEntry>().single.call.terminals,
        before.entries.whereType<ToolEntry>().single.call.terminals,
      ),
      isTrue,
    );
  });

  group('tester: terminal metadata boundaries', () {
    test(
      'whole output resets parser and truncation before same-update delta and exit',
      () {
        final before = fold([
          const PromptAction('t1', 'shell', 0),
          _terminalUpdate({
            'terminal_output_delta': {
              'terminal_id': 'x',
              'data': '${'a' * 30001}\x1b]unfinished',
            },
          }),
        ]);
        expect(_terminalsOf(before)!.single['truncated'], isTrue);
        expect(_terminalsOf(before)!.single.containsKey('escape'), isTrue);
        final after = reduceTranscript(
          before,
          _terminalUpdate({
            'terminal_info': {'terminal_id': 'x', 'cwd': 'workspace'},
            'terminal_output': {'terminal_id': 'x', 'data': '界\r'},
            'terminal_output_delta': {'terminal_id': 'x', 'data': 'X'},
            'terminal_exit': {
              'terminal_id': 'x',
              'exit_code': 0.5,
              'signal': '\x1b[31mSIGTERM\x1b[0m',
            },
          }),
        );
        final terminal = _terminalsOf(after)!.single;
        expect(terminal['output'], 'X ');
        expect(terminal['cwd'], 'workspace');
        expect(terminal['exited'], isTrue);
        expect(terminal['exitCode'], 0.5);
        expect(terminal['signal'], 'SIGTERM');
        expect(terminal.containsKey('escape'), isFalse);
        expect(terminal.containsKey('truncated'), isFalse);
        expect(_terminalsOf(before)!.single.containsKey('escape'), isTrue);
      },
    );

    test(
      'a thousand deltas keep previous snapshots and another terminal intact',
      () {
        final before = fold([
          _terminalUpdate({
            'terminal_output_delta': {'terminal_id': 'x', 'data': 'x'},
          }),
          _terminalUpdate({
            'terminal_output_delta': {'terminal_id': 'y', 'data': 'untouched'},
          }),
        ]);
        final original = (before.entries.single as ToolEntry).call.terminals!;
        var state = before;
        for (var i = 0; i < 1000; i++) {
          state = reduceTranscript(
            state,
            _terminalUpdate({
              'terminal_output_delta': {
                'terminal_id': 'x',
                'data': '\x1b[31m界\x1b[0m',
              },
            }),
          );
        }
        final terminals = (state.entries.single as ToolEntry).call.terminals!;
        expect(terminals.first.output, 'x${'界' * 1000}');
        expect(original.first.output, 'x');
        expect(identical(terminals.last, original.last), isTrue);
        expect(terminals.last.output, 'untouched');
        expect(() => terminals.clear(), throwsUnsupportedError);
      },
    );
  });
}
