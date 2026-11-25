// The original's transcript/permissions_test.ts and the permission cases of
// reducer_test.ts that M1 covers. Left for later: forms, links and boxes of
// questions (elicitation), subagents' and task agents' requests, the agent's
// own cycles, and chord's own save box.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _ended = <TranscriptAction>[
  PromptAction('t1', 'hi', 0),
  ResultAction('t1', TurnAnswered('end_turn')),
];

final _options = [
  for (final (id, name, kind) in [
    ('allow', 'Allow', 'allow_once'),
    ('always', 'Always', 'allow_always'),
    ('deny', 'Deny', 'reject_once'),
  ])
    acp.PermissionOption.fromJson({'optionId': id, 'name': name, 'kind': kind}),
];

/// The `permission` scenario up to its request.
final _asked = <TranscriptAction>[
  const PromptAction('t1', 'permission', 100),
  update('t1', {
    'sessionUpdate': 'tool_call',
    'toolCallId': 'write-4',
    'title': 'Write notes.txt',
    'kind': 'edit',
    'status': 'pending',
  }),
  PermissionRequestedAction(
    't1',
    PermissionWait(
      'p1',
      toolCallId: 'write-4',
      title: 'Write notes.txt',
      kind: 'edit',
      locations: [
        acp.ToolCallLocation.fromJson({'path': 'notes.txt'}),
      ],
      options: _options,
    ),
    at: 150,
  ),
];

Map<String, Object?> _turn(Transcript state) => describedTurn(state.turn);

void main() {
  test('a permission request holds the turn until it is answered', () {
    final actions = [
      ..._asked,
      const PermissionSettledAction('t1', 'p1', Chosen('allow')),
      update('t1', {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'write-4',
        'status': 'completed',
      }),
      say('t1', 'Permission: allow.'),
      const ResultAction('t1', TurnAnswered('end_turn')),
    ];
    final turns = [for (final s in states(actions)) _turn(s)['status']];

    expect(turns, [
      'working',
      'working',
      'awaiting_permission',
      'working',
      'working',
      'working',
      'idle',
    ]);

    final waiting = states(actions)[2].turn as AwaitingPermission;

    expect(waiting.since, 100);
    expect(waiting.permissions.map((p) => p.toolCallId), ['write-4']);
    expect(describedWait(waiting.permissions.single)['locations'], [
      {'path': 'notes.txt'},
    ]);
    expect(waiting.permissions.single.options.map((o) => o.optionId), [
      'allow',
      'always',
      'deny',
    ]);
    // A request with no deadline counts from its turn.
    expect(waiting.permissions.single.at, isNull);

    final state = fold(actions);
    final answer = state.entries.whereType<PermissionEntry>().single;

    expect(
      [answer.title, answer.option?.optionId],
      ['Write notes.txt', 'allow'],
    );
    expect(
      state.entries.whereType<ToolEntry>().single.call.status,
      'completed',
    );
  });

  test('a rejected permission leaves a record with no option', () {
    final state = fold([
      ..._asked,
      const PermissionSettledAction('t1', 'p1', Rejected()),
    ]);

    expect((described(state)['entries'] as List).last, {
      'turnId': 't1',
      'kind': 'permission',
      'title': 'Write notes.txt',
    });
    expect(_turn(state)['status'], 'working');
  });

  test('a choice of an option the request did not offer records none', () {
    final state = fold([
      ..._asked,
      const PermissionSettledAction('t1', 'p1', Chosen('invented')),
    ]);

    expect(state.entries.whereType<PermissionEntry>().single.option, isNull);
  });

  test('cancelling while a permission waits ends the turn cancelled, and '
      'the withdrawn request leaves no record', () {
    final actions = [
      ..._asked,
      const CancelAction('t1', 200),
      const PermissionSettledAction('t1', 'p1', Withdrawn()),
      const ResultAction('t1', TurnAnswered('cancelled')),
    ];
    final seen = states(actions);

    expect(_turn(seen[3]), {
      'status': 'cancelling',
      'turnId': 't1',
      'since': 100,
      'cancelledAt': 200,
    });
    // Cancelling, the turn no longer waits, so the late withdrawal finds
    // nothing.
    expect(identical(seen[4], seen[3]), isTrue);
    expect(fold(actions).entries.last, isA<CancelledEntry>());
    expect(fold(actions).entries.whereType<PermissionEntry>(), isEmpty);
    expect(fold(actions).turn, isA<Idle>());
  });

  test('a generic permission review stays on its call after the box is '
      'answered or withdrawn', () {
    const review = PermissionReview('caution', 'review rationale');

    for (final answer in const [Chosen('allow'), Withdrawn()]) {
      final state = fold([
        const PromptAction('turn', 'request', 1000),
        update('turn', {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'tool',
          'title': 'Reviewed action',
          'status': 'pending',
        }),
        const PermissionRequestedAction(
          'turn',
          PermissionWait(
            'ask',
            toolCallId: 'tool',
            deadlineAt: 310000,
            review: review,
          ),
          at: 10000,
        ),
        PermissionSettledAction('turn', 'ask', answer),
      ]);

      expect(
        describedCall(
          state.entries.whereType<ToolEntry>().single.call,
        )['review'],
        {'outcome': 'caution', 'reason': 'review rationale'},
      );
      expect(state.turn, isA<Working>());
    }
  });

  test('a timed request counts from when it was asked, and its record keeps '
      'the review', () {
    const review = PermissionReview('failed', 'unavailable');
    final asked = fold([
      const PromptAction('t1', 'p', 1000),
      const PermissionRequestedAction(
        't1',
        PermissionWait('ask', deadlineAt: 310000, review: review),
        at: 10000,
      ),
    ]);
    final wait = (asked.turn as AwaitingPermission).permissions.single;

    expect([wait.at, wait.deadlineAt], [10000, 310000]);
    expect((asked.turn as AwaitingPermission).since, 1000);
    expect(
      (described(
                fold([
                  const PermissionSettledAction('t1', 'ask', Rejected()),
                ], asked),
              )['entries']
              as List)
          .last,
      {
        'turnId': 't1',
        'kind': 'permission',
        'review': {'outcome': 'failed', 'reason': 'unavailable'},
      },
    );
  });

  test("the session's own agent asking with no turn running waits between "
      "turns, and its answer goes at the transcript's end", () {
    const permission = PermissionWait('p1', toolCallId: 'w1');
    final asked = fold([
      ..._ended,
      const PermissionRequestedAction(
        't1',
        permission,
        at: 5000,
        between: true,
      ),
    ]);

    expect(_turn(asked), {
      'status': 'awaiting_permission',
      'turnId': 't1',
      'since': 5000,
      'permissions': [
        {'id': 'p1', 'toolCallId': 'w1', 'options': <Object?>[]},
      ],
      'between': true,
    });

    final answered = fold([
      const PermissionSettledAction('t1', 'p1', Rejected()),
    ], asked);

    expect(answered.turn, isA<Idle>());
    expect((described(answered)['entries'] as List).last, {
      'turnId': 't1',
      'kind': 'permission',
    });
  });

  test('a request between turns that meets a turn starting waits in that '
      'turn', () {
    final asked = fold([
      ..._ended,
      const PromptAction('t2', 'next', 6000),
      const PermissionRequestedAction(
        't1',
        PermissionWait('p1'),
        at: 6500,
        between: true,
      ),
    ]);

    expect(_turn(asked), {
      'status': 'awaiting_permission',
      'turnId': 't2',
      'since': 6000,
      'permissions': [
        {'id': 'p1', 'options': <Object?>[]},
      ],
    });
  });

  test('a request left open as its turn ends waits between turns, and a '
      'prompt takes it into the new turn', () {
    final left = fold([
      ..._asked,
      const ResultAction('t1', TurnAnswered('end_turn')),
    ]);

    expect(_turn(left)['between'], isTrue);
    expect(_turn(left)['turnId'], 't1');
    expect(_turn(left)['since'], 100);

    final next = fold([const PromptAction('t2', 'next', 300)], left);

    expect(
      _turn(next),
      {..._turn(left), 'turnId': 't2', 'since': 300}..remove('between'),
    );
    expect(
      fold([
        const PermissionSettledAction('t2', 'p1', Chosen('allow')),
      ], next).turn,
      isA<Working>(),
    );
  });

  test('duplicate requests are ignored and settling out of order keeps the '
      'first wait time', () {
    const first = PermissionRequestedAction(
      'old',
      PermissionWait('one'),
      at: 100,
      between: true,
    );
    const second = PermissionRequestedAction(
      'later',
      PermissionWait('two'),
      at: 200,
      between: true,
    );
    final waiting = fold([..._ended, first, second, first]);

    expect(_turn(waiting)['since'], 100);
    expect((waiting.turn as AwaitingPermission).permissions.map((p) => p.id), [
      'one',
      'two',
    ]);

    final partly = fold([
      const PermissionSettledAction('later', 'two', Rejected()),
    ], waiting);

    expect(_turn(partly)['between'], isTrue);
    expect(_turn(partly)['since'], 100);
    expect((partly.turn as AwaitingPermission).permissions.map((p) => p.id), [
      'one',
    ]);
    expect(
      fold([
        const PermissionSettledAction('old', 'one', Withdrawn()),
      ], partly).turn,
      isA<Idle>(),
    );
    expect(partly.entries.whereType<PermissionEntry>(), hasLength(1));
  });

  test('two requests in one turn wait in order, the first shown', () {
    final both = fold([
      ..._asked,
      const PermissionRequestedAction('t1', PermissionWait('p2'), at: 160),
      const PermissionRequestedAction('t1', PermissionWait('p2'), at: 170),
    ]);

    expect((both.turn as AwaitingPermission).permissions.map((p) => p.id), [
      'p1',
      'p2',
    ]);

    final one = fold([
      const PermissionSettledAction('t1', 'p2', Chosen('allow')),
    ], both);

    expect((one.turn as AwaitingPermission).permissions.map((p) => p.id), [
      'p1',
    ]);
  });

  test("a request for a turn not running, or one that is cancelling, is not "
      'shown', () {
    final working = fold([const PromptAction('t2', 'p', 100)]);
    final cancelling = fold([const CancelAction('t2', 150)], working);

    for (final state in [working, cancelling, Transcript.empty]) {
      expect(
        identical(
          reduceTranscript(
            state,
            const PermissionRequestedAction('t1', PermissionWait('p')),
          ),
          state,
        ),
        isTrue,
      );
    }
  });

  test('an answer to a request not waiting changes nothing', () {
    final asked = fold(_asked);

    for (final state in [asked, fold(_ended)]) {
      expect(
        identical(
          reduceTranscript(
            state,
            const PermissionSettledAction('t1', 'other', Rejected()),
          ),
          state,
        ),
        isTrue,
      );
    }
  });

  test('proposed diff content stays on its permission until answered and '
      'is not recorded as applied', () {
    final diff = {
      'type': 'diff',
      'path': '/project/a.ts',
      'oldText': 'old',
      'newText': 'new',
    };
    final waiting = fold([
      const PromptAction('t1', 'edit', 0),
      PermissionRequestedAction(
        't1',
        PermissionWait(
          'diff-ask',
          title: 'Update a.ts',
          content: [acp.ToolCallContent.fromJson(diff)],
        ),
      ),
    ]);
    final wait = (waiting.turn as AwaitingPermission).permissions.single;

    expect(describedWait(wait)['content'], [diff]);
    expect(waiting.entries.whereType<ToolEntry>(), isEmpty);

    final answered = fold([
      const PermissionSettledAction('t1', 'diff-ask', Withdrawn()),
    ], waiting);

    expect(answered.turn, isA<Working>());
    expect(answered.entries.whereType<ToolEntry>(), isEmpty);
  });

  test('a cancel while a request waits keeps its turn start', () {
    final state = fold([..._asked, const CancelAction('t1', 400)]);

    expect(_turn(state), {
      'status': 'cancelling',
      'turnId': 't1',
      'since': 100,
      'cancelledAt': 400,
    });
  });

  group('tester: permission lifecycle boundaries', () {
    test(
      'fractional and huge deadlines survive turn completion and a new prompt',
      () {
        for (final deadline in <num>[0.5, 1700000000000.5, 1e300]) {
          final presentation = permissionPresentation({
            'chord/permission': {'deadlineAt': deadline},
          });
          final waiting = fold([
            const PromptAction('t1', 'p', 100),
            PermissionRequestedAction(
              't1',
              PermissionWait('p', deadlineAt: presentation.deadlineAt),
              at: 150,
            ),
            const ResultAction('t1', TurnAnswered('end_turn')),
            const PromptAction('t2', 'next', 200),
          ]);
          final turn = waiting.turn as AwaitingPermission;
          expect(turn.permissions.single.deadlineAt, deadline);
          expect(turn.permissions.single.at, 150);
          expect(turn.turnId, 't2');
          expect(turn.since, 200);
          expect(turn.between, isFalse);
        }
      },
    );
    test('duplicate and stale reviewed requests cannot change a tool', () {
      const firstReview = PermissionReview('caution', 'first');
      const replacementReview = PermissionReview('failed', 'duplicate');
      final waiting = fold([
        ..._asked.take(2),
        const PermissionRequestedAction(
          't1',
          PermissionWait('p1', toolCallId: 'write-4', review: firstReview),
        ),
      ]);
      final duplicate = reduceTranscript(
        waiting,
        const PermissionRequestedAction(
          't1',
          PermissionWait(
            'p1',
            toolCallId: 'write-4',
            review: replacementReview,
          ),
        ),
      );
      expect(identical(duplicate, waiting), isTrue);
      expect(
        identical(
          waiting.entries.whereType<ToolEntry>().single.call.review,
          firstReview,
        ),
        isTrue,
      );
      final cancelling = reduceTranscript(
        waiting,
        const CancelAction('t1', 200),
      );
      final stale = reduceTranscript(
        cancelling,
        const PermissionRequestedAction(
          't1',
          PermissionWait(
            'p2',
            toolCallId: 'write-4',
            review: replacementReview,
          ),
        ),
      );
      expect(identical(stale, cancelling), isTrue);
      expect(identical(stale.entries, waiting.entries), isTrue);
    });

    test('wait snapshots stay immutable and withdrawal makes no news', () {
      final first = fold(_asked);
      final original = (first.turn as AwaitingPermission).permissions;
      final both = reduceTranscript(
        first,
        const PermissionRequestedAction('t1', PermissionWait('p2'), at: 160),
      );
      final waits = (both.turn as AwaitingPermission).permissions;
      expect(original.map((p) => p.id), ['p1']);
      expect(waits.map((p) => p.id), ['p1', 'p2']);
      expect(identical(original.single, waits.first), isTrue);
      expect(() => waits.clear(), throwsUnsupportedError);
      final after = reduceTranscript(
        both,
        const PermissionSettledAction('unrelated', 'p1', Withdrawn()),
      );
      expect(identical(after.entries, both.entries), isTrue);
      expect((after.turn as AwaitingPermission).permissions.single.id, 'p2');
      expect(waits, hasLength(2));
      expect(
        identical(
          reduceTranscript(
            after,
            const PermissionSettledAction('t1', 'p1', Rejected()),
          ),
          after,
        ),
        isTrue,
      );
    });

    test(
      'an answer selects the exact option among options of the same kind',
      () {
        final offered = [
          for (final id in ['one', 'two'])
            acp.PermissionOption.fromJson({
              'optionId': id,
              'name': id,
              'kind': 'allow_once',
            }),
        ];
        final waiting = fold([
          const PromptAction('t1', 'p', 100),
          PermissionRequestedAction(
            't1',
            PermissionWait('p', options: offered),
          ),
          const ResultAction('t1', TurnFailed('failed')),
        ]);
        expect((waiting.turn as AwaitingPermission).between, isTrue);
        final answered = reduceTranscript(
          waiting,
          const PermissionSettledAction('t2', 'p', Chosen('two')),
        );
        final record = answered.entries.whereType<PermissionEntry>().single;
        expect(identical(record.option, offered[1]), isTrue);
        expect(record.turnId, 't2');
        expect(answered.turn, isA<Idle>());
        expect(
          answered.entries.whereType<ErrorEntry>().single.message,
          'failed',
        );
      },
    );
  });
}
