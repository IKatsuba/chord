// The original's tests/session/transcript/permissions_test.ts, its forms
// and links: what waits in `asking`, the record each answer leaves, and a
// form left open, or asked, between turns.
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'fold.dart';

const _form = FormWait(
  'e1',
  'Set up the deploy target',
  schema: {'type': 'object', 'properties': <String, Object?>{}},
);

const _asked = <TranscriptAction>[
  PromptAction('t1', 'form', 0),
  ElicitationRequestedAction('t1', _form),
];

const _ended = <TranscriptAction>[
  PromptAction('t1', 'one', 0),
  ResultAction('t1', TurnAnswered('end_turn')),
];

List<Map<String, Object?>> askingOf(Transcript state) => [
  for (final wait in state.asking) describedElicitation(wait),
];

void main() {
  test('a form asked for waits apart from the turn, which keeps working', () {
    final transcript = fold(_asked);
    expect(askingOf(transcript), [describedElicitation(_form)]);
    expect(transcript.turn, isA<Working>());
    // Asked again, it is the same form.
    expect(fold([_asked[1]], transcript), same(transcript));
  });

  test('each answer to a form leaves its record, and the form goes', () {
    for (final (answer, outcome) in const [
      (ElicitationAccepted({'name': 'web-app'}), 'accepted'),
      (ElicitationDeclined(), 'declined'),
      (ElicitationCancelled(), 'cancelled'),
      // Its turn ended or the session closed under it.
      (ElicitationWithdrawn(), 'cancelled'),
    ]) {
      final transcript = fold([
        ..._asked,
        ElicitationSettledAction('t1', 'e1', answer),
      ]);
      expect(transcript.asking, isEmpty);
      expect(describedEntry(transcript.entries.last), {
        'turnId': 't1',
        'kind': 'elicitation',
        'wait': describedElicitation(_form),
        'outcome': outcome,
        if (answer is ElicitationAccepted) 'content': {'name': 'web-app'},
      });
    }
  });

  test('a turn that ends under an open form leaves it open, asked between '
      'turns now, and records nothing of it', () {
    final transcript = fold([
      ..._asked,
      const ResultAction('t1', TurnAnswered('end_turn')),
    ]);
    expect(askingOf(transcript), [
      {...describedElicitation(_form), 'between': true},
    ]);
    expect(transcript.entries.whereType<ElicitationEntry>(), isEmpty);

    final answered = fold([
      const ElicitationSettledAction('t1', 'e1', ElicitationDeclined()),
    ], transcript);
    expect(answered.asking, isEmpty);
    expect(
      (answered.entries.last as ElicitationEntry).outcome,
      ElicitationOutcome.declined,
    );
  });

  test('a form asked by a turn that is no longer current is not shown, nor '
      'one under a cancel', () {
    expect(
      fold(const [
        PromptAction('t2', 'next', 0),
        ElicitationRequestedAction('t1', _form),
      ]).asking,
      isEmpty,
    );
    expect(
      fold(const [
        PromptAction('t1', 'form', 0),
        CancelAction('t1', 1),
        ElicitationRequestedAction('t1', _form),
      ]).asking,
      isEmpty,
    );
  });

  test('a form asked with no turn running is shown, and its answer '
      'recorded', () {
    final wait = _form.asked(at: 5, between: true);
    final asked = fold([..._ended, ElicitationRequestedAction('t1', wait)]);
    expect(asked.asking, [same(wait)]);
    expect(asked.turn, isA<Idle>());

    final answered = fold([
      const ElicitationSettledAction('t1', 'e1', ElicitationDeclined()),
    ], asked);
    expect(answered.asking, isEmpty);
    expect(
      (answered.entries.last as ElicitationEntry).outcome,
      ElicitationOutcome.declined,
    );
  });

  test('a permission and form before the first turn settle independently', () {
    final waiting = fold([
      const PermissionRequestedAction(
        'session',
        PermissionWait('p'),
        at: 10,
        between: true,
      ),
      ElicitationRequestedAction('session', _form.asked(at: 10, between: true)),
    ]);
    final answered = fold([
      const PermissionSettledAction('session', 'p', Rejected()),
    ], waiting);
    expect(answered.turn, isA<Idle>());
    expect(answered.asking, hasLength(1));

    final done = fold([
      const ElicitationSettledAction(
        'session',
        'e1',
        ElicitationAccepted(<String, Object?>{}),
      ),
    ], answered);
    expect(done.asking, isEmpty);
    expect(
      [for (final e in done.entries) describedEntry(e)['kind']],
      ['permission', 'elicitation'],
    );
  });

  test('a link waits as a form does, and an unknown id settles nothing', () {
    const link = LinkWait('l1', 'Sign in', 'https://example.com/sign-in');
    final transcript = fold(const [
      PromptAction('t1', 'link', 0),
      ElicitationRequestedAction('t1', link),
      ElicitationSettledAction('t1', 'nope', ElicitationDeclined()),
    ]);
    expect(askingOf(transcript), [
      {
        'id': 'l1',
        'message': 'Sign in',
        'mode': 'url',
        'url': 'https://example.com/sign-in',
      },
    ]);
    expect(transcript.entries, hasLength(1));
  });
}
