import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

const _gated = {
  'sessionUpdate': 'plan_update',
  'planId': 'p1',
  'entries': <Object?>[],
};
const _linkChunk = {
  'sessionUpdate': 'user_message_chunk',
  'content': {'type': 'resource_link', 'name': 'a.ts', 'uri': 'file:///a.ts'},
};
const _from = {'name': 'lead', 'reachable': true};

/// A record holding what the window's projection merges or omits.
List<Map<String, Object?>> _record() => [
  {
    'type': 'session',
    'version': 1,
    'sessionId': 's',
    'agent': 'a',
    'cwd': '/w',
    'at': 0,
  },
  {
    'type': 'prompt',
    'turnId': 't1',
    'prompt': '<message from="chord">\nA note.\n</message>\n\nFix it',
    'images': 1,
    'at': 1,
  },
  {'type': 'update', 'turnId': 't1', 'update': _gated},
  {'type': 'update', 'turnId': 't1', 'update': _linkChunk},
  {
    'type': 'update',
    'turnId': 't1',
    'update': {'sessionUpdate': 'agent_message_chunk', 'content': {}},
    'subagentId': 'c1',
  },
  {
    'type': 'result',
    'turnId': 't1',
    'result': {'status': 'completed', 'stopReason': 'end_turn'},
  },
  {
    'type': 'prompt',
    'turnId': 't2',
    'prompt': '<message from="lead">\nReport back.\n</message>',
    'images': 0,
    'at': 2,
    'from': _from,
  },
  {'type': 'renamed', 'title': 'Fix the parser', 'at': 3},
  {
    'type': 'left_open',
    'agents': [
      {'name': 'tester'},
    ],
  },
];

List<Map<String, Object?>> _json(List<PastEvent>? past) => [
  for (final event in past!) event.toJson(),
];

const _expected = [
  {'type': 'prompt', 'text': 'Fix it [Image #1]'},
  {'type': 'update', 'update': _gated},
  {'type': 'update', 'update': _linkChunk},
  {
    'type': 'update',
    'update': {'sessionUpdate': 'agent_message_chunk', 'content': {}},
    'subagentId': 'c1',
  },
  {'type': 'prompt', 'text': 'Report back.', 'from': _from},
  {'type': 'renamed', 'title': 'Fix the parser'},
  {
    'type': 'left_open',
    'agents': [
      {'name': 'tester'},
    ],
  },
];

void main() {
  test('the raw past keeps what the window omits, whole, in order', () {
    final history = recordActions(_record(), past: true);
    expect(_json(history.past), _expected);
  });

  test('without asking for it there is none, and the window\'s projection is '
      'as it was', () {
    final plain = recordActions(_record());
    final withPast = recordActions(_record(), past: true);
    expect(plain.past, isNull);
    expect(
      jsonEncode(plain.toJson()['actions']),
      jsonEncode(withPast.toJson()['actions']),
    );
  });

  test(
    'read from disk through the record worker, it comes out the same',
    () async {
      final dir = Directory.systemTemp.createTempSync('chord-past-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/record.jsonl';
      File(path).writeAsStringSync(_record().map(encodeRecord).join());
      expect(
        _json((await readRecordedHistory(path, past: true)).past),
        _expected,
      );
      expect((await readRecordedHistory(path)).past, isNull);
    },
  );

  test('it crosses as JSON and comes back the same', () {
    final history = recordActions(_record(), past: true);
    final crossed = PreparedHistory.fromJson(
      jsonDecode(jsonEncode(history.toJson())) as Map<String, Object?>,
    );
    expect(_json(crossed.past), _expected);
  });

  test('the window'
      's replay omits a kind chord acp recorded and it does not '
      'draw, saying so', () {
    final history = recordActions(_record());
    expect(history.omitted, isTrue);
    expect(
      history.actions.whereType<UpdateAction>().map((a) => a.update.kind),
      isNot(contains('plan_update')),
    );
  });

  group('a message whose prompt line has no from', () {
    Map<String, Object?> prompt(
      String text, {
      Map<String, Object?>? from,
      String? into,
    }) => {
      'type': 'prompt',
      'turnId': 't',
      'prompt': text,
      'images': 0,
      'at': 1,
      'from': ?from,
      'into': ?into,
    };

    test('is said by the wrapper'
        's sender, its runtime and a task'
        's note', () {
      expect(
        _json(
          recordActions([
            prompt(
              '<message from="tester · codex · report">\nDone.\n</message>',
            ),
            prompt(
              '<message from="lead · claude">\nGo on.\n</message>',
              into: 't0',
            ),
            prompt(
              '<message from="watch" monitor="m1">\nBuild red.\n</message>',
            ),
          ], past: true).past,
        ),
        [
          {
            'type': 'prompt',
            'text': 'Done.',
            'from': {'name': 'tester', 'runtime': 'codex', 'note': 'report'},
          },
          {
            'type': 'prompt',
            'text': 'Go on.',
            'from': {'name': 'lead', 'runtime': 'claude'},
          },
          {
            'type': 'prompt',
            'text': 'Build red.',
            'from': {
              'name': 'watch',
              'monitor': {'id': 'm1'},
            },
          },
        ],
      );
    });

    test('the record'
        's own from wins over the wrapper', () {
      expect(
        _json(
          recordActions([
            prompt(
              '<message from="tester · codex">\nDone.\n</message>',
              from: {'name': 'tester', 'reachable': true},
            ),
          ], past: true).past,
        ),
        [
          {
            'type': 'prompt',
            'text': 'Done.',
            'from': {'name': 'tester', 'reachable': true},
          },
        ],
      );
    });
  });

  group('auxiliary fields of the wrong type', () {
    final odd = <Map<String, Object?>>[
      {
        'type': 'update',
        'turnId': 't',
        'update': {'sessionUpdate': 'agent_message_chunk', 'content': {}},
        'subagentId': 3,
      },
      {
        'type': 'prompt',
        'turnId': 'u',
        'prompt': '<message from="lead">\nGo.\n</message>',
        'images': 0,
        'at': 1,
        'from': 'lead',
      },
    ];

    test('leave the window'
        's replay as it was: omitted, never an error', () async {
      final history = recordActions(odd);
      expect(history.omitted, isTrue);
      expect(history.past, isNull);
      final dir = Directory.systemTemp.createTempSync('chord-past-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/record.jsonl';
      File(path).writeAsStringSync(odd.map(encodeRecord).join());
      expect((await readRecordedHistory(path)).omitted, isTrue);
    });

    test('leave the raw past without what they would misroute', () {
      expect(_json(recordActions(odd, past: true).past), [
        {
          'type': 'prompt',
          'text': 'Go.',
          'from': {'name': 'lead'},
        },
      ]);
    });
  });

  group('tester U9 raw replay boundaries', () {
    test(
      'worker and JSON crossings preserve a thousand whole ordered updates',
      () async {
        final rows = [
          for (var i = 0; i < 1000; i++)
            {
              'type': 'update',
              'turnId': 't',
              'update': {
                'sessionUpdate': i.isEven ? 'plan_update' : 'future_update',
                '_meta': {'sequence': i, 'text': '界👩‍💻e\u0301\u001b[31m'},
                'future': [
                  i,
                  null,
                  {'kept': true},
                ],
              },
              if (i % 3 == 0) 'subagentId': 'child/with/slash',
            },
        ];
        final expected = [
          for (final row in rows)
            {
              'type': 'update',
              'update': row['update'],
              'subagentId': ?row['subagentId'],
            },
        ];
        final dir = Directory.systemTemp.createTempSync('chord-raw-order-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/record.jsonl')
          ..writeAsStringSync(rows.map(encodeRecord).join());
        final read = await readRecordedHistory(file.path, past: true);
        expect(_json(read.past), expected);
        final crossed = PreparedHistory.fromJson(
          jsonDecode(jsonEncode(read.toJson())) as Map<String, Object?>,
        );
        expect(_json(crossed.past), expected);
        expect((await readRecordedHistory(file.path)).past, isNull);
      },
    );

    test('quoted sender fallback and explicit from keep their own facts', () {
      final explicit = {
        'name': 'explicit',
        'reachable': false,
        'runtime': 'future',
        '_meta': {'kept': true},
      };
      final prompts = [
        for (final from in <Map<String, Object?>?>[null, explicit])
          {
            'type': 'prompt',
            'turnId': 't',
            'at': 1,
            'images': 0,
            'prompt':
                '<message from="a &quot;quoted&quot; name · codex · failed">\nbody\n</message>',
            'into': 'running',
            'from': ?from,
          },
      ];
      expect(_json(recordActions(prompts, past: true).past), [
        {
          'type': 'prompt',
          'text': 'body',
          'from': {
            'name': 'a "quoted" name',
            'runtime': 'codex',
            'note': 'failed',
          },
        },
        {'type': 'prompt', 'text': 'body', 'from': explicit},
      ]);
    });

    test(
      'malformed auxiliary entries cannot erase valid later raw events',
      () async {
        final rows = [
          {'type': 'update', 'turnId': 't', 'subagentId': 7, 'update': _gated},
          {'type': 'left_open', 'agents': 'invalid'},
          {'type': 'renamed', 'title': 'kept', 'at': 2},
          {'type': 'update', 'turnId': 't', 'update': _linkChunk},
        ];
        final plain = recordActions(rows);
        final raw = recordActions(rows, past: true);
        expect(_json(raw.past), [
          {'type': 'renamed', 'title': 'kept'},
          {'type': 'update', 'update': _linkChunk},
        ]);
        expect(
          jsonEncode(plain.toJson()['actions']),
          jsonEncode(raw.toJson()['actions']),
        );
        expect(plain.omitted, isTrue);
      },
    );
  });
}
