// The original's tests/session/transcript/plans_test.ts: a plan by id,
// `plan_update` and `plan_removed`, its entries the live list, its markdown
// or file the reply, and an approved plan shown once.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/replay.dart' show PreparedHistory, recordActions;
import 'package:chord/session/transcript/subagents.dart' show subagentsIn;
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

Map<String, Object?> _step(String status) => {
  'content': 'Read the code',
  'priority': 'high',
  'status': status,
};

UpdateAction _items(String planId, String status, [String turnId = 't1']) =>
    update(turnId, {
      'sessionUpdate': 'plan_update',
      'plan': {
        'type': 'items',
        'planId': planId,
        'entries': [_step(status)],
      },
    });

UpdateAction _markdown(
  String content, {
  String planId = 'm',
  String turnId = 't1',
}) => update(turnId, {
  'sessionUpdate': 'plan_update',
  'plan': {'type': 'markdown', 'planId': planId, 'content': content},
});

UpdateAction _removed(String planId) =>
    update('t1', {'sessionUpdate': 'plan_removed', 'planId': planId});

List<Map<String, Object?>> _plan(Transcript state) => [
  for (final step in state.plan)
    {'content': step.content, 'priority': step.priority, 'status': step.status},
];

List<(String, String?)> _shown(Transcript state) => [
  for (final entry in state.entries)
    switch (entry) {
      UserEntry(:final text) => ('user', text),
      AssistantEntry(:final text) => ('assistant', text.text),
      _ => (describedEntry(entry)['kind'] as String, null),
    },
];

Map<String, Object?> _text(String value) => {
  'type': 'content',
  'content': {'type': 'text', 'text': value},
};

UpdateAction _call(
  String id,
  List<Map<String, Object?>>? content, {
  String kind = 'switch_mode',
  String turnId = 't1',
  String status = 'completed',
}) => update(turnId, {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': id,
  'kind': kind,
  'status': status,
  'content': ?content,
});

List<Object?> _contents(List<TranscriptAction> actions) => [
  for (final entry in fold(actions).entries)
    if (entry is ToolEntry)
      [
        for (final item in entry.call.content ?? const <acp.ToolCallContent>[])
          item.toJson(),
      ],
];

void main() {
  const start = PromptAction('t1', 'plan', 0);

  group('CTUI-69 tester: plan identity and isolation', () {
    test(
      'malformed saved plans are omitted without losing valid plan history',
      () {
        final past = recordActions([
          {
            'type': 'prompt',
            'turnId': 't1',
            'prompt': 'plan',
            'images': 0,
            'at': 0,
          },
          {
            'type': 'update',
            'turnId': 't1',
            'update': {
              'sessionUpdate': 'plan_update',
              'plan': {'type': 'markdown', 'planId': 'm', 'content': 'kept'},
            },
          },
          for (final invalid in <Map<String, Object?>>[
            {
              'sessionUpdate': 'plan_update',
              'plan': {'type': 'markdown', 'planId': 'm', 'content': 3},
            },
            {
              'sessionUpdate': 'plan_update',
              'plan': {
                'type': 'items',
                'planId': 'p',
                'entries': [false],
              },
            },
            {'sessionUpdate': 'plan_removed', 'planId': 3},
          ])
            {'type': 'update', 'turnId': 't1', 'update': invalid},
        ]);
        expect(past.omitted, isTrue);
        final restored = PreparedHistory.fromJson(past.toJson());
        final entries = fold(
          restored.actions,
        ).entries.whereType<AssistantEntry>().toList();
        expect(entries, hasLength(1));
        expect(entries.single.planId, 'm');
        expect(entries.single.text.text, 'kept');
      },
    );

    test(
      'the live id survives unrelated folds and a settled turn until removed',
      () {
        final states = <Transcript>[];
        var state = fold([start, _items('p', 'pending')]);
        for (final action in <TranscriptAction>[
          say('t1', 'reply'),
          think('t1', 'thought'),
          update('t1', {
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'plan',
          }),
          update('t1', {
            'sessionUpdate': 'usage_update',
            'used': 3,
            'size': 100,
          }),
          _call('read', [_text('output')], kind: 'read'),
          const ElicitationRequestedAction('t1', FormWait('e', 'Form')),
          const ElicitationSettledAction('t1', 'e', ElicitationDeclined()),
          const ResultAction('t1', TurnAnswered('end_turn')),
          const PromptAction('t2', 'continue', 5),
        ]) {
          state = fold([action], state);
          states.add(state);
          expect(state.planId, 'p');
          expect(_plan(state), [_step('pending')]);
        }
        final removed = fold([_removed('p')], state);
        expect(removed.planId, isNull);
        expect(removed.plan, isEmpty);
        expect(removed.entries, state.entries);
        expect(states.first.planId, 'p');
      },
    );

    test(
      'markdown and file ids survive replay, in-place replacement and selective removal',
      () {
        final raw = <Map<String, Object?>>[
          {
            'type': 'prompt',
            'turnId': 't1',
            'prompt': 'plan',
            'images': 0,
            'at': 0,
          },
          for (final plan in [
            {'type': 'markdown', 'planId': 'm', 'content': '界🙂e\u0301'},
            {'type': 'file', 'planId': 'f', 'uri': 'file:///plan.md'},
          ])
            {
              'type': 'update',
              'turnId': 't1',
              'update': {'sessionUpdate': 'plan_update', 'plan': plan},
            },
        ];
        final replayed = PreparedHistory.fromJson(recordActions(raw).toJson());
        final initial = fold(replayed.actions);
        expect(replayed.omitted, isFalse);
        expect(
          initial.entries.whereType<AssistantEntry>().map(
            (entry) => entry.planId,
          ),
          ['m', 'f'],
        );
        final original = initial.entries.whereType<AssistantEntry>().first;
        final updated = fold([
          _markdown('rewritten', turnId: 't2'),
          say('t2', 'ordinary'),
        ], initial);
        final plans = updated.entries
            .whereType<AssistantEntry>()
            .where((entry) => entry.planId != null)
            .toList();
        expect(plans.map((entry) => entry.planId), ['m', 'f']);
        expect(plans.first.turnId, original.turnId);
        expect(plans.first.identity, same(original.identity));
        expect(original.text.text, '界🙂e\u0301');
        final withoutMarkdown = fold([_removed('m')], updated);
        expect(_shown(withoutMarkdown), [
          ('user', 'plan'),
          ('assistant', 'file:///plan.md'),
          ('assistant', 'ordinary'),
        ]);
        final withoutFile = fold([_removed('f')], withoutMarkdown);
        expect(_shown(withoutFile), [
          ('user', 'plan'),
          ('assistant', 'ordinary'),
        ]);
      },
    );

    test('malformed updates and removals preserve the valid state', () {
      final valid = fold([start, _items('p', 'pending'), _markdown('kept')]);
      for (final malformed in <Map<String, Object?>>[
        {
          'sessionUpdate': 'plan_update',
          'plan': {'type': 'markdown', 'content': 'missing id'},
        },
        {
          'sessionUpdate': 'plan_update',
          'plan': {'type': 'markdown', 'planId': 'm', 'content': 3},
        },
        {
          'sessionUpdate': 'plan_update',
          'plan': {'type': 'file', 'planId': 'm', 'uri': false},
        },
        {
          'sessionUpdate': 'plan_update',
          'plan': {
            'type': 'items',
            'planId': 'p',
            'entries': [3],
          },
        },
        {
          'sessionUpdate': 'plan_update',
          'plan': {
            'type': 'items',
            'planId': 'p',
            'entries': [
              {'content': 3, 'priority': 'high', 'status': 'pending'},
            ],
          },
        },
        {'sessionUpdate': 'plan_removed', 'planId': 3},
      ]) {
        expect(fold([update('t1', malformed)], valid), same(valid));
        expect(valid.planId, 'p');
        expect(_plan(valid), [_step('pending')]);
      }
    });

    test(
      'removing a child plan with the same id never removes its parent plan',
      () {
        final state = fold([
          start,
          _items('shared', 'pending'),
          update('t1', {
            'sessionUpdate': 'subagent_update',
            'sessionId': 'child',
            'title': 'Child',
          }),
          UpdateAction(
            't1',
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'plan_update',
              'plan': {
                'type': 'items',
                'planId': 'shared',
                'entries': [_step('completed')],
              },
            }),
            subagentId: 'child',
          ),
        ]);
        final removed = fold([
          UpdateAction(
            't1',
            acp.SessionUpdate.fromJson({
              'sessionUpdate': 'plan_removed',
              'planId': 'shared',
            }),
            subagentId: 'child',
          ),
        ], state);
        expect(removed.planId, 'shared');
        expect(_plan(removed), [_step('pending')]);
        expect(subagentsIn(removed.entries).single.plan, isEmpty);
        expect(subagentsIn(removed.entries).single.planId, isNull);
      },
    );
  });

  test('a plan by id: entries are the live list, markdown the reply', () {
    expect(_plan(fold([start, _items('p', 'pending')])), [_step('pending')]);
    expect(
      _plan(fold([start, _items('p', 'pending'), _items('p', 'completed')])),
      [_step('completed')],
    );
    expect(_plan(fold([start, _items('p', 'pending'), _removed('q')])), [
      _step('pending'),
    ]);
    expect(
      _plan(fold([start, _items('p', 'pending'), _removed('p')])),
      isEmpty,
    );

    final state = fold([
      start,
      _markdown('1. Read'),
      say('t1', 'Shall I go on?'),
      _markdown('1. Read\n2. Write'),
    ]);
    expect(state.plan, isEmpty);
    expect(_shown(state), [
      ('user', 'plan'),
      ('assistant', '1. Read\n2. Write'),
      ('assistant', 'Shall I go on?'),
    ]);

    final other = update('t1', {
      'sessionUpdate': 'plan_update',
      'plan': {'type': 'file', 'planId': 'f', 'uri': 'file:///plan.md'},
    });
    final kept = fold([
      start,
      _markdown('1. Read'),
      say('t1', 'Shall I go on?'),
      other,
      _items('p', 'pending'),
      _removed('m'),
    ]);
    expect(_plan(kept), [_step('pending')]);
    expect(_shown(kept), [
      ('user', 'plan'),
      ('assistant', 'Shall I go on?'),
      ('assistant', 'file:///plan.md'),
    ]);
    expect(_shown(fold([start, other, _removed('f')])), [('user', 'plan')]);
  });

  test("a plan's reply takes no chunk after it, and an older plan update "
      'forgets the id', () {
    final state = fold([start, _markdown('1. Read'), say('t1', ' and more')]);
    expect(_shown(state), [
      ('user', 'plan'),
      ('assistant', '1. Read'),
      ('assistant', ' and more'),
    ]);
    final older = fold([
      start,
      _items('p', 'pending'),
      update('t1', {
        'sessionUpdate': 'plan',
        'entries': [_step('completed')],
      }),
    ]);
    expect(older.planId, isNull);
    // So removing the id-addressed plan leaves the older one's list.
    expect(_plan(fold([_removed('p')], older)), [_step('completed')]);
  });

  test("an approved plan shows once: a markdown plan_update takes it from the "
      "turn's mode switch that carries it", () {
    const plan = '# Route\n\n1. Read.\n2. Move.\n';
    UpdateAction exit(String id, String text, [String turnId = 't1']) =>
        _call(id, [_text(text)], turnId: turnId, status: 'pending');
    final approved = _markdown(plan.trim(), planId: 'plan-mode');
    List<Object?> contents(List<TranscriptAction> actions) => [
      for (final entry in fold(actions).entries)
        if (entry is ToolEntry)
          {
            'id': entry.call.id,
            'content': [
              for (final item
                  in entry.call.content ?? const <acp.ToolCallContent>[])
                item.toJson(),
            ],
          }
        else if (entry is AssistantEntry)
          {'plan': entry.text.text},
    ];

    expect(contents([start, exit('e1', plan), approved]), [
      {'id': 'e1', 'content': <Object?>[]},
      {'plan': plan.trim()},
    ]);
    // Only the latest switch of the turn, and only when its text is the plan.
    expect(
      contents([start, exit('e1', plan), exit('e2', 'Another.'), approved]),
      [
        {
          'id': 'e1',
          'content': [_text(plan)],
        },
        {
          'id': 'e2',
          'content': [_text('Another.')],
        },
        {'plan': plan.trim()},
      ],
    );
    expect(
      contents([
        const PromptAction('t0', 'plan', 0),
        exit('e0', plan, 't0'),
        start,
        approved,
      ]),
      [
        {
          'id': 'e0',
          'content': [_text(plan)],
        },
        {'plan': plan.trim()},
      ],
    );
  });

  group('CHD-432 tester: plan deduplication boundaries', () {
    UpdateAction plan(String content) => _markdown(content, planId: 'p');

    test('matching split text is removed while diff and image blocks keep '
        'their order and data', () {
      const diff = {
        'type': 'diff',
        'path': 'notes/plan.md',
        'oldText': 'old',
        'newText': 'new',
      };
      const image = {
        'type': 'content',
        'content': {'type': 'image', 'data': 'AA==', 'mimeType': 'image/png'},
      };
      expect(
        _contents([
          start,
          _call('exit', [
            _text('  # Plan'),
            diff,
            _text('\nRead and write.  '),
            image,
          ]),
          plan('# Plan\nRead and write.'),
        ]),
        [
          [diff, image],
        ],
      );
    });

    test('only the latest matching mode switch loses its text and a later '
        'ordinary call is untouched', () {
      expect(
        _contents([
          start,
          _call('first', [_text('Plan')]),
          _call('latest', [_text('Plan')]),
          _call('read', [_text('Plan')], kind: 'read'),
          plan('Plan'),
        ]),
        [
          [_text('Plan')],
          <Object?>[],
          [_text('Plan')],
        ],
      );
    });

    test('file and item plans leave matching call text alone', () {
      for (final alternative in [
        update('t1', {
          'sessionUpdate': 'plan_update',
          'plan': {'type': 'file', 'planId': 'p', 'uri': 'file:///plan.md'},
        }),
        update('t1', {
          'sessionUpdate': 'plan_update',
          'plan': {
            'type': 'items',
            'planId': 'p',
            'entries': [
              {'content': 'Plan', 'priority': 'medium', 'status': 'pending'},
            ],
          },
        }),
      ]) {
        expect(
          _contents([
            start,
            _call('exit', [_text('file:///plan.md')]),
            alternative,
          ]),
          [
            [_text('file:///plan.md')],
          ],
        );
      }
    });

    test('blank plans and plans differing in internal whitespace keep the '
        'call content', () {
      for (final (said, proposed) in const [
        ('   ', ' '),
        ('Read  and write', 'Read and write'),
      ]) {
        expect(
          _contents([
            start,
            _call('exit', [_text(said)]),
            plan(proposed),
          ]),
          [
            [_text(said)],
          ],
        );
      }
    });
  });

  test("a subagent's plan by id is its own: kept with its id, removed by it, "
      "never its parent's", () {
    UpdateAction from(Map<String, Object?> json) =>
        UpdateAction('t1', acp.SessionUpdate.fromJson(json), subagentId: 'a');
    final spawned = update('t1', {
      'sessionUpdate': 'subagent_update',
      'sessionId': 'a',
      'title': 'Find',
    });
    final items = from({
      'sessionUpdate': 'plan_update',
      'plan': {
        'type': 'items',
        'planId': 'p',
        'entries': [_step('pending')],
      },
    });
    Subagent child(Transcript state) => subagentsIn(state.entries).single;

    final listed = fold([start, spawned, items]);
    expect(listed.plan, isEmpty);
    expect(listed.planId, isNull);
    expect(child(listed).planId, 'p');
    expect(child(listed).plan, hasLength(1));
    final kept = fold([
      from({'sessionUpdate': 'plan_removed', 'planId': 'q'}),
    ], listed);
    expect(child(kept).plan, hasLength(1));
    final gone = fold([
      from({'sessionUpdate': 'plan_removed', 'planId': 'p'}),
    ], listed);
    expect(child(gone).plan, isEmpty);
    expect(child(gone).planId, isNull);
  });
}
