// The original's tools_test.ts and the tool cases of reducer_test.ts that
// M1 covers, the fake agent's `tools`, `unordered`, `edit` and `calls`
// written out as the updates they send. Left for later: the terminal cases
// (unit 10's foldTerminals), calls cut off by a steer (`cut`), and chord's
// own MCP calls.
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/tools.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _t1 = 't1';
const _t2 = 't2';

UpdateAction _call(String turnId, Map<String, Object?> fields) =>
    update(turnId, {'sessionUpdate': 'tool_call', ...fields});

UpdateAction _change(String turnId, Map<String, Object?> fields) =>
    update(turnId, {'sessionUpdate': 'tool_call_update', ...fields});

Map<String, Object?> _text(String text) => {
  'type': 'content',
  'content': {'type': 'text', 'text': text},
};

/// The `tools` scenario.
final _tools = <TranscriptAction>[
  const PromptAction(_t1, 'tools', 100),
  _call(_t1, {
    'toolCallId': 'read-1',
    'title': 'Read README.md',
    'kind': 'read',
    'status': 'pending',
    'locations': [
      {'path': 'README.md'},
    ],
    'rawInput': {'path': 'README.md'},
  }),
  _change(_t1, {'toolCallId': 'read-1', 'status': 'in_progress'}),
  _change(_t1, {
    'toolCallId': 'read-1',
    'status': 'completed',
    'content': [_text('# chord')],
    'rawOutput': {'lines': 1},
  }),
  say(_t1, 'Read it.'),
  const ResultAction(_t1, TurnAnswered('end_turn')),
];

List<Map<String, Object?>> _calls(Transcript state) => [
  for (final entry in state.entries)
    if (entry is ToolEntry) describedCall(entry.call),
];

void main() {
  test('a tool call is one entry through all its updates', () {
    expect(
      states(_tools).expand(
        (s) => s.entries.whereType<ToolEntry>().map((e) => e.call.status),
      ),
      ['pending', 'in_progress', 'completed', 'completed', 'completed'],
    );
    expect(_calls(fold(_tools)), [
      {
        'id': 'read-1',
        'title': 'Read README.md',
        'kind': 'read',
        'status': 'completed',
        'locations': [
          {'path': 'README.md'},
        ],
        'content': [_text('# chord')],
        'rawInput': {'path': 'README.md'},
        'rawOutput': {'lines': 1},
      },
    ]);
    expect(
      [for (final e in described(fold(_tools))['entries'] as List) e['kind']],
      ['user', 'tool', 'assistant'],
    );
  });

  test('an update before its call, a repeated call and a stale status', () {
    const call = {
      'toolCallId': 'grep-2',
      'title': 'Search for TODO',
      'kind': 'search',
      'status': 'pending',
    };
    final state = fold([
      const PromptAction(_t1, 'unordered', 100),
      _change(_t1, {'toolCallId': 'grep-2', 'status': 'in_progress'}),
      _call(_t1, call),
      _call(_t1, call),
      _change(_t1, {
        'toolCallId': 'grep-2',
        'status': 'completed',
        'content': [_text('src/main.tsx:1: TODO')],
      }),
      _change(_t1, {'toolCallId': 'grep-2', 'status': 'in_progress'}),
      say(_t1, 'Searched.'),
    ]);

    expect(
      [for (final e in described(state)['entries'] as List) e['kind']],
      ['user', 'tool', 'assistant'],
    );
    expect(_calls(state), [
      {
        'id': 'grep-2',
        'title': 'Search for TODO',
        'kind': 'search',
        'status': 'completed',
        'content': [_text('src/main.tsx:1: TODO')],
      },
    ]);
  });

  test('tool updates in any order, any number of times, make one call', () {
    final events = _tools.sublist(1, 4);
    final expected = described(fold(_tools))['entries'] as List;

    for (final order in [
      events.reversed.toList(),
      events.expand((e) => [e, e]).toList(),
      [...events, ...events],
      [events[2], events[0], events[1]],
    ]) {
      expect(
        (described(fold([_tools.first, ...order]))['entries'] as List).take(2),
        expected.take(2),
      );
    }
  });

  test('an edit keeps its diff', () {
    final diff = {
      'type': 'diff',
      'path': 'src/greeting.ts',
      'oldText': 'old',
      'newText': 'new',
    };
    final state = fold([
      const PromptAction(_t1, 'edit', 100),
      _call(_t1, {
        'toolCallId': 'edit-3',
        'title': 'Edit src/greeting.ts',
        'kind': 'edit',
        'status': 'pending',
        'content': [diff],
      }),
      _change(_t1, {'toolCallId': 'edit-3', 'status': 'completed'}),
    ]);

    expect(_calls(state).single['content'], [diff]);
    expect(_calls(state).single['status'], 'completed');
  });

  test("a later turn's call of the same id is its own entry", () {
    final first = fold([
      const PromptAction(_t1, 'calls', 100),
      _call(_t1, {'toolCallId': 'c', 'title': 'Read', 'status': 'completed'}),
      const ResultAction(_t1, TurnAnswered('end_turn')),
    ]);
    // A call of the same id updates the latest of that id, wherever it is.
    final state = fold([
      const PromptAction(_t2, 'again', 200),
      _call(_t2, {'toolCallId': 'c2', 'title': 'Other'}),
      _change(_t2, {'toolCallId': 'c', 'rawOutput': 'late'}),
    ], first);
    final tools = state.entries.whereType<ToolEntry>().toList();

    expect(
      [for (final t in tools) (t.turnId, t.call.id)],
      [(_t1, 'c'), (_t2, 'c2')],
    );
    expect(tools.first.call.rawOutput, 'late');
  });

  test('a field an update leaves out is kept; one it sends replaces it, '
      '[] and null included', () {
    final start = fold([
      const PromptAction(_t1, 'p', 100),
      _call(_t1, {
        'toolCallId': 'c',
        'title': 'Run',
        'kind': 'execute',
        'locations': [
          {'path': 'a', 'line': 3},
        ],
        'content': [_text('one')],
        'rawInput': {'command': 'ls'},
        'rawOutput': 'out',
      }),
    ]);
    final kept = fold([
      _change(_t1, {'toolCallId': 'c', 'title': '', 'kind': ''}),
    ], start);
    final replaced = fold([
      _change(_t1, {
        'toolCallId': 'c',
        'title': 'Run ls',
        'content': <Object?>[],
        'locations': <Object?>[],
        'rawInput': null,
      }),
    ], start);

    expect(_calls(kept), _calls(start));
    expect(_calls(replaced).single, {
      'id': 'c',
      'title': 'Run ls',
      'kind': 'execute',
      'locations': <Object?>[],
      'content': <Object?>[],
      'rawOutput': 'out',
    });
    expect(
      fold([
        _change(_t1, {'toolCallId': 'c', 'rawInput': null}),
      ], start).entries.whereType<ToolEntry>().single.call.rawInput,
      isNull,
    );
  });

  test("a location's line is carried as the agent's number", () {
    final state = fold([
      _call(_t1, {
        'toolCallId': 'c',
        'locations': [
          {'path': 'a', 'line': 3.0},
        ],
      }),
    ]);

    expect(_calls(state).single['locations'], [
      {'path': 'a', 'line': 3.0},
    ]);
  });

  test("a call's title keeps every line and its length", () {
    final title = '`cat <<EOF\n${'x' * 5000}`';
    final state = fold([
      const PromptAction(_t1, 'heredoc', 0),
      _call(_t1, {
        'toolCallId': 'c1',
        'title': 'Bash',
        'kind': 'execute',
        'status': 'pending',
      }),
      _change(_t1, {'toolCallId': 'c1', 'title': title}),
    ]);

    expect(state.entries.whereType<ToolEntry>().single.call.title, title);
  });

  test("an MCP call and a Guardian review chord's enrichers filed are kept, "
      'and kept through updates that file none', () {
    final state = fold([
      const PromptAction(_t1, 'p', 100),
      _call(_t1, {
        'toolCallId': 'c',
        'title': 'mcp',
        '_meta': {
          mcpCallKey: {
            'server': 'docs',
            'tool': 'search',
            'arguments': {'q': 'x'},
          },
          guardianReviewKey: 'inProgress',
        },
      }),
      _change(_t1, {
        'toolCallId': 'c',
        '_meta': {guardianReviewKey: 'approved'},
      }),
      _change(_t1, {'toolCallId': 'c', 'status': 'completed'}),
    ]);

    expect(_calls(state).single, {
      'id': 'c',
      'title': 'mcp',
      'status': 'completed',
      'guardian': 'approved',
      'mcp': {
        'server': 'docs',
        'tool': 'search',
        'input': {'q': 'x'},
      },
    });
  });

  test(
    'a filing without a tool, or a review that is not a string, is none',
    () {
      final state = fold([
        _call(_t1, {
          'toolCallId': 'c',
          '_meta': {
            mcpCallKey: {'arguments': 1},
            guardianReviewKey: 3,
          },
        }),
        _call(_t1, {
          'toolCallId': 'd',
          '_meta': {
            mcpCallKey: {'tool': 'search'},
          },
        }),
        _call(_t1, {'toolCallId': 'e', '_meta': 'not a map'}),
      ]);

      expect(_calls(state), [
        {'id': 'c'},
        {
          'id': 'd',
          'mcp': {'tool': 'search', 'input': null},
        },
        {'id': 'e'},
      ]);
    },
  );

  test('a status only moves forward, and a finished one never moves back', () {
    expect(nextStatus(null, 'pending'), 'pending');
    expect(nextStatus('in_progress', null), 'in_progress');
    expect(nextStatus('in_progress', 'pending'), 'in_progress');
    expect(nextStatus('pending', 'completed'), 'completed');
    expect(nextStatus('completed', 'failed'), 'completed');
    expect(nextStatus('failed', 'in_progress'), 'failed');
    expect(nextStatus('pending', 'something_new'), 'something_new');
    expect(nextStatus('something_new', 'pending'), 'pending');
  });

  test('a malformed tool update leaves the identical state, and the next '
      'draws', () {
    final state = fold(_tools.take(2).toList());

    for (final fields in <Map<String, Object?>>[
      {},
      {'toolCallId': 7},
      {'toolCallId': 'read-1', 'title': 3},
      {'toolCallId': 'read-1', 'status': false},
      {'toolCallId': 'read-1', 'content': 'not a list'},
      {
        'toolCallId': 'read-1',
        'content': [<String, Object?>{}],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {'type': 'content'},
        ],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 7},
          },
        ],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {
            'type': 'content',
            'content': {'text': 'x'},
          },
        ],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {'type': 'diff', 'path': 'a', 'newText': 3},
        ],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {'type': 'diff', 'newText': 'n'},
        ],
      },
      {
        'toolCallId': 'read-1',
        'content': [
          {'type': 'diff', 'path': 'a', 'oldText': 1, 'newText': 'n'},
        ],
      },
      {
        'toolCallId': 'read-1',
        'locations': [
          {'line': 1},
        ],
      },
      {
        'toolCallId': 'read-1',
        'locations': [
          {'path': 'a', 'line': 'one'},
        ],
      },
    ]) {
      expect(
        identical(reduceTranscript(state, _change(_t1, fields)), state),
        isTrue,
        reason: '$fields',
      );
    }

    expect(_calls(fold([_tools[2]], state)).single['status'], 'in_progress');
    expect(_calls(fold([_tools[3]], state)).single['content'], [
      _text('# chord'),
    ]);
  });

  test('content of a kind chord does not know is kept as it came', () {
    final item = {'type': 'terminal', 'terminalId': 'term-1', 'extra': true};
    final image = {
      'type': 'content',
      'content': {'type': 'image', 'data': '', 'mimeType': 'image/png'},
    };
    final state = fold([
      _call(_t1, {
        'toolCallId': 'c',
        'content': [item, image],
      }),
    ]);

    expect(_calls(state).single['content'], [item, image]);
  });

  test('a tool update leaves every other entry the identical object', () {
    final before = fold(_tools.take(5).toList());
    final after = reduceTranscript(before, _tools[3]);

    expect(identical(after.entries.first, before.entries.first), isTrue);
    expect(identical(after.entries.last, before.entries.last), isTrue);
    expect(identical(after.entries[1], before.entries[1]), isFalse);
  });

  group('tester: tool merge boundaries', () {
    test(
      'only the latest duplicate id changes and keeps its original turn',
      () {
        const review = PermissionReview('caution', 'Check the change');
        const older = ToolEntry(_t1, ToolCall('same', title: 'older'));
        const latest = ToolEntry(
          _t2,
          ToolCall('same', title: 'latest', review: review),
        );
        final before = Transcript(entries: [older, latest]);
        final after = reduceTranscript(
          before,
          _change('late', {'toolCallId': 'same', 'status': 'completed'}),
        );
        expect(identical(after.entries.first, older), isTrue);
        final changed = after.entries.last as ToolEntry;
        expect(changed.turnId, _t2);
        expect(changed.call.title, 'latest');
        expect(changed.call.status, 'completed');
        expect(identical(changed.call.review, review), isTrue);
        expect(latest.call.status, isNull);
      },
    );

    test(
      'a malformed tail cannot partially change fields or earlier content',
      () {
        final before = fold(_tools.take(2).toList());
        final after = reduceTranscript(
          before,
          _change(_t1, {
            'toolCallId': 'read-1',
            'title': 'must not land',
            'status': 'completed',
            'rawOutput': 'must not land',
            'content': [
              _text('valid prefix'),
              {'type': 'diff', 'path': 'a', 'newText': false},
            ],
          }),
        );
        expect(identical(after, before), isTrue);
        final next = reduceTranscript(after, _tools[2]);
        expect(_calls(next).single['status'], 'in_progress');
        expect(_calls(next).single['title'], 'Read README.md');
        expect(_calls(next).single.containsKey('rawOutput'), isFalse);
      },
    );

    test('a thousand replacements retain one call and leave old snapshots', () {
      final before = fold([
        _call(_t1, {
          'toolCallId': 'c',
          'status': 'failed',
          'content': [_text('initial')],
          'rawOutput': 'old',
          'locations': [
            {'path': 'a'},
          ],
        }),
        say(_t1, 'after tool'),
      ]);
      final oldCall = (before.entries.first as ToolEntry).call;
      var state = before;
      for (var i = 0; i < 1000; i++) {
        state = reduceTranscript(
          state,
          _change(_t2, {
            'toolCallId': 'c',
            'status': 'pending',
            'content': [_text('界 e\u0301 👩‍💻\x1b[31m $i')],
            'rawOutput': null,
          }),
        );
      }
      final call = (state.entries.first as ToolEntry).call;
      expect(state.entries, hasLength(2));
      expect(identical(state.entries.last, before.entries.last), isTrue);
      expect(identical(call.locations, oldCall.locations), isTrue);
      expect(call.status, 'failed');
      expect(call.rawOutput, isNull);
      expect(_calls(state).single['content'], [
        _text('界 e\u0301 👩‍💻\x1b[31m 999'),
      ]);
      expect(_calls(before).single['content'], [_text('initial')]);
      expect(oldCall.rawOutput, 'old');
      expect(() => call.content!.clear(), throwsUnsupportedError);
      expect(() => call.locations!.clear(), throwsUnsupportedError);
    });
  });
}
