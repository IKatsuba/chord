// The original's reducer_test.ts, the cases M1's core covers, with the fake
// agent's scenarios written out as the updates they send. Left for later:
// tool calls (tools_test), permissions (permissions_test), and the cases of
// subagents, messages, cycles, steering, forks and the fx scenarios.
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/sign_in.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _t1 = 't1';
const _t2 = 't2';

/// The `text` scenario: four chunks, then `end_turn`.
final _text = <TranscriptAction>[
  const PromptAction(_t1, 'text', 100),
  say(_t1, 'Hello'),
  say(_t1, ', world'),
  say(_t1, '. This reply'),
  say(_t1, ' came in chunks.'),
  const ResultAction(_t1, TurnAnswered('end_turn')),
];

List<(String, String)> _steps(int done, [int from = 0]) => [
  for (final (i, step) in [
    'Read the code',
    'Write the change',
    'Run the tests',
  ].indexed.skip(from))
    (step, i < done ? 'completed' : (i == done ? 'in_progress' : 'pending')),
];

/// The `plan` scenario: a plan advanced step by step, then finished.
final _plan = <TranscriptAction>[
  const PromptAction(_t1, 'plan', 100),
  plan(_t1, _steps(0)),
  say(_t1, 'Planning.'),
  plan(_t1, _steps(1)),
  plan(_t1, _steps(2)),
  plan(_t1, _steps(3)),
  const ResultAction(_t1, TurnAnswered('end_turn')),
];

void main() {
  test('a reply is one block, and the turn works until its result', () {
    final seen = states(_text);

    expect(described(fold(_text))['entries'], [
      {'turnId': _t1, 'kind': 'user', 'text': 'text'},
      {
        'turnId': _t1,
        'kind': 'assistant',
        'text': 'Hello, world. This reply came in chunks.',
      },
    ]);
    expect(describedTurn(seen.first.turn), {
      'status': 'working',
      'turnId': _t1,
      'since': 100,
    });
    // The last chunk is not the end of the turn; the result is.
    expect(seen[seen.length - 2].turn, isA<Working>());
    expect(fold(_text).turn, isA<Idle>());
  });

  test('thought is kept apart from the reply', () {
    final state = fold([
      const PromptAction(_t1, 'thought', 100),
      think(_t1, 'Considering'),
      think(_t1, ' the question.'),
      say(_t1, 'Here is'),
      say(_t1, ' the answer.'),
      const ResultAction(_t1, TurnAnswered('end_turn')),
    ]);

    expect(described(state)['entries'], [
      {'turnId': _t1, 'kind': 'user', 'text': 'thought'},
      {'turnId': _t1, 'kind': 'thought', 'text': 'Considering the question.'},
      {'turnId': _t1, 'kind': 'assistant', 'text': 'Here is the answer.'},
    ]);
  });

  test('a new message id starts a new block; a missing one runs on', () {
    final state = fold([
      const PromptAction(_t1, 'p', 100),
      say(_t1, 'one', messageId: 'm1'),
      say(_t1, ' more'),
      say(_t1, ' and', messageId: 'm1'),
      say(_t1, 'two', messageId: 'm2'),
    ]);

    expect(described(state)['entries'], [
      {'turnId': _t1, 'kind': 'user', 'text': 'p'},
      {
        'turnId': _t1,
        'kind': 'assistant',
        'text': 'one more and',
        'messageId': 'm1',
      },
      {'turnId': _t1, 'kind': 'assistant', 'text': 'two', 'messageId': 'm2'},
    ]);
  });

  test("a chunk of another turn starts its own block, not the last one's", () {
    final state = fold([..._text, const PromptAction(_t2, 'again', 200)]);
    final late = fold([say(_t1, ' Late.')], state);

    expect(described(late)['entries'], [
      ...(described(state)['entries'] as List),
      {'turnId': _t1, 'kind': 'assistant', 'text': ' Late.'},
    ]);
    expect(describedTurn(late.turn), {
      'status': 'working',
      'turnId': _t2,
      'since': 200,
    });
  });

  test('a chunk that is not text, or is empty, changes nothing', () {
    final state = fold(_text.take(2).toList());

    for (final action in [
      update(_t1, {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'image', 'data': '', 'mimeType': 'image/png'},
      }),
      say(_t1, ''),
    ]) {
      expect(identical(reduceTranscript(state, action), state), isTrue);
    }
  });

  test('a plan replaces the plan', () {
    final plans = states(
      _plan,
    ).map((s) => s.plan.map((e) => e.status).join(' ')).toList();

    expect(plans, contains('completed in_progress pending'));
    expect(plans, contains('completed completed completed'));
  });

  test('a finished plan moves into the transcript at the end', () {
    final state = described(fold(_plan));

    expect(state['plan'], isEmpty);
    expect((state['entries'] as List).last, {
      'turnId': _t1,
      'kind': 'plan',
      'entries': [
        ['Read the code', 'medium', 'completed'],
        ['Write the change', 'medium', 'completed'],
        ['Run the tests', 'medium', 'completed'],
      ],
    });
  });

  test('an unfinished plan stays live after its turn', () {
    final state = fold([
      ..._plan.take(4),
      const ResultAction(_t1, TurnAnswered('end_turn')),
    ]);

    expect(state.turn, isA<Idle>());
    expect(state.plan.map((e) => e.status), [
      'completed',
      'in_progress',
      'pending',
    ]);
    expect(state.entries.whereType<FinishedPlanEntry>(), isEmpty);
  });

  test('an empty plan clears it, and a plan of fewer steps replaces it', () {
    final dropped = fold([..._plan.take(3), plan(_t1, _steps(0, 1))]);

    expect(dropped.plan.map((e) => e.content), [
      'Write the change',
      'Run the tests',
    ]);
    expect(fold([plan(_t1, [])], dropped).plan, isEmpty);
  });

  test('usage and the mode reach the state', () {
    final state = fold([
      const PromptAction(_t1, 'status', 100),
      update(_t1, {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      }),
      update(_t1, {
        'sessionUpdate': 'usage_update',
        'used': 1200,
        'size': 200000,
        'cost': {'amount': 0.01, 'currency': 'USD'},
      }),
      say(_t1, 'Status sent.'),
      const ResultAction(_t1, TurnAnswered('end_turn')),
    ]);

    expect(described(state)['mode'], 'plan');
    // No cost: M1 shows what the agent reports of the window, no price.
    expect(described(state)['usage'], {'used': 1200, 'size': 200000});
  });

  test("usage is carried as the agent's numbers, floats included", () {
    final state = fold([
      update(_t1, {
        'sessionUpdate': 'usage_update',
        'used': 1200.5,
        'size': 200000.0,
      }),
    ]);

    expect(described(state)['usage'], {'used': 1200.5, 'size': 200000.0});
    expect(state.usage!.used, isA<double>());
  });

  group('CTUI-160: a prompt refused for want of a login', () {
    for (final account in <AccountState?>[
      null,
      noAccount,
      const AccountPending(),
      const AccountFailed(),
      const AccountHeard({'state': 'unauthenticated'}),
      const AccountHeard({'state': 'authenticated'}),
    ]) {
      test('its error entry keeps the sign-in, account $account', () {
        final signIn = SignIn('Authentication required', const [
          (name: 'Log in', description: 'with a browser'),
        ], account: account);
        final state = fold([
          const PromptAction(_t1, 'hello', 100),
          ResultAction(
            _t1,
            TurnFailed(
              'Authentication required',
              code: authRequired,
              signIn: signIn,
            ),
          ),
        ]);
        final entry = state.entries.whereType<ErrorEntry>().single;
        expect(entry.message, 'Authentication required');
        expect(entry.code, authRequired);
        expect(entry.signIn, same(signIn));
        expect(entry.signIn!.account, same(account));
        expect(state.turn, isA<Idle>());
      });
    }

    test('any other failure keeps none', () {
      final state = fold([
        const PromptAction(_t1, 'hello', 100),
        const ResultAction(_t1, TurnFailed('failed', code: authRequired)),
      ]);
      expect(state.entries.whereType<ErrorEntry>().single.signIn, isNull);
    });
  });

  test('a failed turn is an entry, and the next turn starts clean', () {
    final failed = fold([
      const PromptAction(_t1, 'error', 100),
      say(_t1, 'About to fail.'),
      const ResultAction(
        _t1,
        TurnFailed('The fake agent failed on purpose.', code: -32603),
      ),
    ]);

    expect((described(failed)['entries'] as List).skip(1), [
      {'turnId': _t1, 'kind': 'assistant', 'text': 'About to fail.'},
      {
        'turnId': _t1,
        'kind': 'error',
        'message': 'The fake agent failed on purpose.',
        'code': -32603,
      },
    ]);
    expect(failed.turn, isA<Idle>());

    final next = fold([
      for (final action in _text)
        switch (action) {
          PromptAction(:final text, :final at) => PromptAction(_t2, text, at),
          UpdateAction(:final update) => UpdateAction(_t2, update),
          ResultAction(:final result) => ResultAction(_t2, result),
          _ => action,
        },
    ], failed);

    expect(next.entries, hasLength(5));
    expect(next.entries.last, isA<AssistantEntry>());
    expect(next.turn, isA<Idle>());
  });

  test('a cancel mid-stream keeps what came and marks the turn', () {
    final actions = <TranscriptAction>[
      const PromptAction(_t1, 'slow', 100),
      say(_t1, 'Working'),
      say(_t1, '.'),
      const CancelAction(_t1, 150),
      say(_t1, '.'),
      const ResultAction(_t1, TurnAnswered('cancelled')),
    ];
    final seen = states(actions);

    expect(describedTurn(seen[3].turn), {
      'status': 'cancelling',
      'turnId': _t1,
      'since': 100,
      'cancelledAt': 150,
    });
    expect((described(fold(actions))['entries'] as List).skip(1), [
      {'turnId': _t1, 'kind': 'assistant', 'text': 'Working..'},
      {'turnId': _t1, 'kind': 'cancelled'},
    ]);
    expect(fold(actions).turn, isA<Idle>());
  });

  test('a cancel again, or for another turn, changes nothing', () {
    final working = fold(_text.take(2).toList());
    final cancelling = reduceTranscript(working, const CancelAction(_t1, 150));

    expect(
      identical(
        reduceTranscript(cancelling, const CancelAction(_t1, 160)),
        cancelling,
      ),
      isTrue,
    );
    expect(
      identical(
        reduceTranscript(working, const CancelAction(_t2, 150)),
        working,
      ),
      isTrue,
    );
    expect(
      identical(
        reduceTranscript(Transcript.empty, const CancelAction(_t1, 150)),
        Transcript.empty,
      ),
      isTrue,
    );
  });

  test('a stop reason other than end_turn is drawn as stopped', () {
    final state = fold([
      ..._text.take(2),
      const ResultAction(_t1, TurnAnswered('max_tokens')),
    ]);

    expect((described(state)['entries'] as List).last, {
      'turnId': _t1,
      'kind': 'stopped',
      'reason': 'max_tokens',
    });
    expect(state.turn, isA<Idle>());
  });

  test("a result for a turn not running draws its ending, the turn's own "
      'state untouched', () {
    final working = fold([const PromptAction(_t2, 'p', 200)]);
    final failed = reduceTranscript(
      working,
      const ResultAction(_t1, TurnFailed('The agent exited.')),
    );

    expect((described(failed)['entries'] as List).last, {
      'turnId': _t1,
      'kind': 'error',
      'message': 'The agent exited.',
    });
    expect(identical(failed.turn, working.turn), isTrue);
    expect(
      identical(
        reduceTranscript(
          working,
          const ResultAction(_t1, TurnAnswered('end_turn')),
        ),
        working,
      ),
      isTrue,
    );
  });

  test('an end_turn result keeps the identical entries, so it is no news', () {
    final working = fold(_text.take(5).toList());
    final settled = reduceTranscript(working, _text.last);

    expect(identical(settled.entries, working.entries), isTrue);
    expect(settled.turn, isA<Idle>());
  });

  test("chord's failures and warnings are entries of their own", () {
    final state = fold([
      const FailedAction(_t1, 'Could not send.'),
      const WarnedAction(_t1, 'Careful.'),
    ]);

    expect(described(state)['entries'], [
      {'turnId': _t1, 'kind': 'error', 'message': 'Could not send.'},
      {'turnId': _t1, 'kind': 'warning', 'message': 'Careful.'},
    ]);
  });

  test('the agent going away changes nothing in M1, with no subagents', () {
    final working = fold(_text.take(3).toList());

    expect(
      identical(
        reduceTranscript(working, const DisconnectedAction(_t1, at: 300)),
        working,
      ),
      isTrue,
    );
  });

  group('identity', () {
    test('an update of a kind not drawn leaves the identical state', () {
      final state = fold(_text.take(3).toList());

      for (final json in [
        {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'x'},
        },
        {'sessionUpdate': 'available_commands_update', 'availableCommands': []},
        {'sessionUpdate': 'something_new', 'whatever': 1},
      ]) {
        expect(
          identical(reduceTranscript(state, update(_t1, json)), state),
          isTrue,
        );
      }
    });

    test('a chunk leaves every entry but the last the identical object', () {
      final before = fold(_text.take(3).toList());
      final after = reduceTranscript(before, say(_t1, '!'));

      expect(identical(after.entries.first, before.entries.first), isTrue);
      expect(identical(after.entries.last, before.entries.last), isFalse);
      expect(identical(after.turn, before.turn), isTrue);
    });

    test(
      'a malformed update leaves the identical state, and the next draws',
      () {
        final state = fold(_text.take(2).toList());

        for (final json in <Map<String, Object?>>[
          {'sessionUpdate': 'plan', 'entries': 'not a list'},
          {
            'sessionUpdate': 'plan',
            'entries': ['not a step'],
          },
          {
            'sessionUpdate': 'plan',
            'entries': [<String, Object?>{}],
          },
          {
            'sessionUpdate': 'plan',
            'entries': [
              {'content': 'Read', 'priority': 'high', 'status': 3},
            ],
          },
          {
            'sessionUpdate': 'plan',
            'entries': [
              {'content': 7, 'priority': 'high', 'status': 'completed'},
            ],
          },
          {
            'sessionUpdate': 'plan',
            'entries': [
              {'content': 'Read', 'status': 'completed'},
            ],
          },
          {'sessionUpdate': 'agent_message_chunk'},
          {
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text'},
          },
          {'sessionUpdate': 'usage_update', 'used': '1200', 'size': 1},
          {'sessionUpdate': 'current_mode_update'},
          {'sessionUpdate': 7},
        ]) {
          expect(
            identical(reduceTranscript(state, update(_t1, json)), state),
            isTrue,
            reason: '$json',
          );
        }

        final next = reduceTranscript(
          reduceTranscript(
            state,
            update(_t1, {'sessionUpdate': 'plan', 'entries': 'x'}),
          ),
          say(_t1, ', world'),
        );

        expect((described(next)['entries'] as List).last, {
          'turnId': _t1,
          'kind': 'assistant',
          'text': 'Hello, world',
        });
      },
    );

    test('a plan step with a field malformed never reaches state, so the '
        'result after it settles', () {
      final working = fold(_text.take(2).toList());
      final after = reduceTranscript(
        working,
        update(_t1, {
          'sessionUpdate': 'plan',
          'entries': [<String, Object?>{}],
        }),
      );
      final settled = fold([
        say(_t1, ', world'),
        const ResultAction(_t1, TurnAnswered('end_turn')),
      ], after);

      expect(identical(after, working), isTrue);
      expect(settled.turn, isA<Idle>());
      expect(settled.plan, isEmpty);
      expect((described(settled)['entries'] as List).last, {
        'turnId': _t1,
        'kind': 'assistant',
        'text': 'Hello, world',
      });
    });
  });

  group('tester: transcript core boundaries', () {
    test(
      'a thousand interleaved chunks keep snapshots and sessions separate',
      () {
        final seed = fold([
          const PromptAction(_t1, 'first', 100),
          say(_t1, 'seed'),
        ]);
        var left = seed;
        var right = seed;
        for (var i = 0; i < 1000; i++) {
          left = reduceTranscript(left, say(_t1, '界'));
          right = reduceTranscript(right, say(_t1, '👩‍💻'));
        }
        expect((seed.entries.last as AssistantEntry).text.text, 'seed');
        expect(
          (left.entries.last as AssistantEntry).text.text,
          'seed${'界' * 1000}',
        );
        expect(
          (right.entries.last as AssistantEntry).text.text,
          'seed${'👩‍💻' * 1000}',
        );
        expect(identical(left.entries.first, seed.entries.first), isTrue);
        expect(identical(right.entries.first, seed.entries.first), isTrue);
      },
    );

    test('chunk boundaries preserve markdown, combining marks and escapes', () {
      const text =
          '# Heading\n```dart\n界 e\u0301 👩‍💻\n```\n\x1b[31mred\x1b[0m';
      final state = fold([
        const PromptAction(_t1, 'markdown', 100),
        for (final unit in text.codeUnits) say(_t1, String.fromCharCode(unit)),
        const ResultAction(_t1, TurnAnswered('end_turn')),
      ]);
      expect((state.entries.last as AssistantEntry).text.text, text);
      expect(state.entries, hasLength(2));
    });

    test('switching back from thought starts another reply block', () {
      final state = fold([
        say(_t1, 'before', messageId: 'same'),
        think(_t1, 'thinking'),
        say(_t1, 'after', messageId: 'same'),
      ]);
      expect(state.entries.map((e) => (e as ChunkEntry).text.text), [
        'before',
        'thinking',
        'after',
      ]);
      expect(state.entries.map((e) => e.runtimeType), [
        AssistantEntry,
        ThoughtEntry,
        AssistantEntry,
      ]);
    });

    test('a malformed later plan step cannot replace a live plan', () {
      final before = fold([
        const PromptAction(_t1, 'plan', 100),
        plan(_t1, [('keep', 'in_progress')]),
      ]);
      final after = reduceTranscript(
        before,
        update(_t1, {
          'sessionUpdate': 'plan',
          'entries': [
            {'content': 'valid', 'priority': 'medium', 'status': 'completed'},
            {'content': 'invalid', 'priority': 7, 'status': 'completed'},
          ],
        }),
      );
      expect(identical(after, before), isTrue);
      final next = fold([
        say(_t1, 'still alive'),
        const ResultAction(_t1, TurnAnswered('end_turn')),
      ], after);
      expect(next.plan.single.content, 'keep');
      expect(next.turn, isA<Idle>());
      expect((next.entries.last as AssistantEntry).text.text, 'still alive');
    });

    test('a completed plan precedes each non-success ending', () {
      for (final result in <TurnResult>[
        const TurnAnswered('cancelled'),
        const TurnAnswered('max_tokens'),
        const TurnFailed('failed', code: 7),
      ]) {
        final before = fold([
          const PromptAction(_t1, 'plan', 100),
          plan(_t1, [('done', 'completed')]),
        ]);
        final after = reduceTranscript(before, ResultAction(_t1, result));
        expect(after.entries[1], isA<FinishedPlanEntry>());
        expect(after.entries, hasLength(3));
        expect(
          identical(
            (after.entries[1] as FinishedPlanEntry).entries,
            before.plan,
          ),
          isTrue,
        );
        expect(after.plan, isEmpty);
        expect(after.turn, isA<Idle>());
        expect(before.plan, hasLength(1));
      }
    });
  });
}
