import 'package:chord/acp/upstream_turns.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

const done = TurnAnswered('end_turn');
const failed = TurnFailed('gone');
const cancelledResult = TurnAnswered('cancelled');
const lead = {'name': 'lead', 'reachable': true};

/// Plays [inputs] from nothing: what was sent, and where it left the table.
({Turns turns, List<String> sends}) play(List<TurnInput> inputs) {
  var turns = noTurns;
  final sends = <String>[];
  for (final input in inputs) {
    final step = reduceTurns(turns, input);
    turns = step.turns;
    sends.addAll(step.sends.map(said));
  }
  return (turns: turns, sends: sends);
}

/// A send, as a line the tests compare.
String said(TurnSend send) => switch (send) {
  TurnAnswer(:final requestId, :final result) =>
    'answer ${_id(requestId)} ${identical(result, done)
        ? 'done'
        : identical(result, failed)
        ? 'failed'
        : identical(result, cancelledResult)
        ? 'cancelled'
        : '?'}',
  TurnCancelled(:final requestId) => 'cancelled ${_id(requestId)}',
  TurnSessionGone(:final requestId, :final turnId) =>
    'session_gone ${_id(requestId)} $turnId',
  TurnMessage(:final text, :final from) =>
    'message $text${from == null ? '' : ' from ${from['name']}'}',
};

String _id(Object? id) => id is String ? '"$id"' : '$id';

TurnInput bind(Object? requestId, String turnId) => TurnBind(requestId, turnId);
TurnInput prompt(String turnId, [String? text]) =>
    TurnPrompt(turnId, text ?? turnId);
TurnInput message(String turnId, [String? text]) =>
    TurnPrompt(turnId, text ?? turnId, from: lead);
TurnInput result(String turnId, [TurnResult ended = done]) =>
    TurnEnded(turnId, ended);
const disconnected = TurnsDisconnected();
const closing = TurnsClosing();

void main() {
  _turnInputs();

  group('tester U3 turn lifecycle boundaries', () {
    test(
      'a thousand queued prompts settle once after disconnect and late results',
      () {
        var turns = noTurns;
        for (var i = 0; i < 1000; i++) {
          turns = reduceTurns(turns, TurnBind(i, 'turn-$i')).turns;
        }
        final queued = turns;
        turns = reduceTurns(turns, const TurnPrompt('turn-0', 'work')).turns;
        final lost = reduceTurns(turns, const TurnsDisconnected());
        expect(lost.sends, hasLength(999));
        expect(
          lost.sends.whereType<TurnSessionGone>().map((s) => s.requestId),
          orderedEquals(Iterable<int>.generate(999, (i) => i + 1)),
        );
        expect(lost.turns.bound, {'turn-0': 0});
        expect(queued.bound, hasLength(1000));
        expect(queued.running, isNull);
        final closed = reduceTurns(lost.turns, const TurnsClosing());
        expect(
          closed.sends.single,
          isA<TurnCancelled>().having((s) => s.requestId, 'request', 0),
        );
        turns = closed.turns;
        for (var i = 0; i < 1000; i++) {
          final late = reduceTurns(turns, TurnEnded('turn-$i', done));
          expect(late.sends, isEmpty);
          turns = late.turns;
        }
        expect(turns.bound, isEmpty);
        expect(turns.running, isNull);
        expect(turns.lost, isNull);
        expect(turns.steered, isEmpty);
      },
    );

    test('an old result preserves a newer steered turn and its origin', () {
      final old = play([bind(null, 'old'), prompt('old'), disconnected]).turns;
      final steered = reduceTurns(old, const TurnSteered('steer')).turns;
      final running = reduceTurns(
        steered,
        const TurnPrompt('steer', '界👩‍💻e\u0301\u001b[31m'),
      );
      expect(running.sends, isEmpty);
      final ended = reduceTurns(running.turns, const TurnEnded('old', done));
      expect(
        ended.sends.single,
        isA<TurnAnswer>().having((s) => s.requestId, 'request', isNull),
      );
      expect(sessionStateOf(ended.turns, asking: false), (
        state: SessionStateKind.running,
        origin: TurnOrigin.client,
      ));
      expect(old.lost, 'old');
      expect(old.bound, {'old': null});
      expect(steered.steered, {'steer'});
    });
  });
  group('the table, row by row', () {
    test('a bound prompt runs as the client\'s and says nothing', () {
      final (:turns, :sends) = play([bind(1, 'a'), prompt('a')]);
      expect(turns.running, (turnId: 'a', origin: TurnOrigin.client));
      expect(sends, isEmpty);
    });

    test('an unbound prompt runs as a message, and the client is told', () {
      final (:turns, :sends) = play([message('m', 'report')]);
      expect(turns.running, (turnId: 'm', origin: TurnOrigin.message));
      expect(sends, ['message report from lead']);
    });

    test('a steered message changes nothing and gets no result', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        prompt('a'),
        const TurnPrompt('s', 'also', from: lead, into: 'a'),
      ]);
      expect(turns.running, (turnId: 'a', origin: TurnOrigin.client));
      expect(sends, ['message also from lead']);
    });

    test('a prompt while a cycle runs replaces it', () {
      final (:turns, sends: _) = play([
        const TurnByAgent('c'),
        bind(1, 'a'),
        prompt('a'),
      ]);
      expect(turns.running, (turnId: 'a', origin: TurnOrigin.client));
    });

    test('a message while a cycle runs replaces it too, and is told', () {
      final (:turns, :sends) = play([
        const TurnByAgent('c'),
        message('m', 'hi'),
      ]);
      expect(turns.running, (turnId: 'm', origin: TurnOrigin.message));
      expect(sends, ['message hi from lead']);
    });

    test('a bound result answers once, with what it ended with', () {
      final (:turns, :sends) = play([bind(1, 'a'), prompt('a'), result('a')]);
      expect(turns.running, isNull);
      expect(turnOf(turns, 1), isNull);
      expect(sends, ['answer 1 done']);
    });

    test('a failed result is that prompt\'s error', () {
      expect(play([bind(1, 'a'), prompt('a'), result('a', failed)]).sends, [
        'answer 1 failed',
      ]);
    });

    test('an unbound result answers nothing', () {
      final (:turns, :sends) = play([message('m'), result('m')]);
      expect(turns.running, isNull);
      expect(sends.where((s) => s.startsWith('answer')), isEmpty);
    });

    test('a result of another turn leaves the running one', () {
      final (:turns, sends: _) = play([
        bind(1, 'a'),
        prompt('a'),
        result('old'),
      ]);
      expect(turns.running, (turnId: 'a', origin: TurnOrigin.client));
    });

    test('a withdrawn queue answers each bound cancelled, and skips the '
        'rest', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        bind(2, 'b'),
        const TurnsWithdrawn(['a', 'b', 'stranger']),
      ]);
      expect(sends, ['cancelled 1', 'cancelled 2']);
      expect(turns.bound, isEmpty);
    });

    test('a withdrawn queue with no ids answers nothing', () {
      final (:turns, :sends) = play([bind(1, 'a'), const TurnsWithdrawn([])]);
      expect(sends, isEmpty);
      expect(turnOf(turns, 1), 'a');
    });

    test('a cycle runs as the agent\'s', () {
      expect(play([const TurnByAgent('c')]).turns.running, (
        turnId: 'c',
        origin: TurnOrigin.agent,
      ));
    });

    test('a turn the agent took for a steer runs as its, until the '
        'message\'s prompt', () {
      final started = play([const TurnByAgent('own')]);
      expect(started.turns.running, (turnId: 'own', origin: TurnOrigin.agent));
      expect(reduceTurns(started.turns, message('m')).turns.running, (
        turnId: 'm',
        origin: TurnOrigin.message,
      ));
    });

    test('disconnected: the running bound stays for its result, queued '
        'answer gone', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        prompt('a'),
        bind(2, 'b'),
        disconnected,
      ]);
      expect(turns.running, isNull);
      expect(turnOf(turns, 1), 'a');
      expect(sends, ['session_gone 2 b']);
      expect(reduceTurns(turns, result('a', failed)).sends.map(said), [
        'answer 1 failed',
      ]);
    });

    test('a second disconnect does not take the running one for queued', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        prompt('a'),
        disconnected,
        disconnected,
      ]);
      expect(sends, isEmpty);
      expect(turnOf(turns, 1), 'a');
    });

    test('closing answers every binding cancelled and empties the table', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        prompt('a'),
        bind(2, 'b'),
        closing,
      ]);
      expect(sends, ['cancelled 1', 'cancelled 2']);
      expect(identical(turns, noTurns), isTrue);
    });

    test('unbind: a send refused leaves nothing to answer', () {
      final (:turns, :sends) = play([bind(1, 'a'), const TurnUnbind('a')]);
      expect(turnOf(turns, 1), isNull);
      expect(sends, isEmpty);
    });
  });

  group('interleavings', () {
    test('a message\'s turn with A and B queued, A cancelled: each answers '
        'its own', () {
      final (:turns, :sends) = play([
        message('monitor', 'event'),
        bind('A', 'a'),
        bind('B', 'b'),
        const TurnsWithdrawn(['a']),
        result('monitor'),
        prompt('b'),
        result('b'),
      ]);
      expect(sends, [
        'message event from lead',
        'cancelled "A"',
        'answer "B" done',
      ]);
      expect(turns.bound, isEmpty);
    });

    test('A and B queued behind a message, its result answers neither', () {
      final (:turns, :sends) = play([
        message('monitor'),
        bind('A', 'a'),
        bind('B', 'b'),
        result('monitor'),
      ]);
      expect(sends.where((s) => s.startsWith('answer')), isEmpty);
      expect(turnOf(turns, 'A'), 'a');
      expect(turnOf(turns, 'B'), 'b');
    });

    test('prompts bound out of order answer by their turn, not by '
        'arrival', () {
      expect(
        play([
          bind('first', 'a'),
          bind('second', 'b'),
          prompt('b'),
          result('b'),
          prompt('a'),
          result('a'),
        ]).sends,
        ['answer "second" done', 'answer "first" done'],
      );
    });

    test('a cycle ends with its own result, with a prompt queued behind '
        'it', () {
      final (:turns, :sends) = play([
        const TurnByAgent('c'),
        bind(1, 'a'),
        result('c'),
      ]);
      expect(sends, isEmpty);
      expect(turns.running, isNull);
      expect(turnOf(turns, 1), 'a');
    });

    test('a steered message in a client\'s turn leaves its answer alone', () {
      expect(
        play([
          bind(1, 'a'),
          prompt('a'),
          const TurnPrompt('s', 'also', from: lead, into: 'a'),
          result('a'),
        ]).sends,
        ['message also from lead', 'answer 1 done'],
      );
    });

    test('a session/cancel: queued withdrawn, the running answered on its '
        'result', () {
      expect(
        play([
          bind(1, 'a'),
          prompt('a'),
          bind(2, 'b'),
          const TurnsWithdrawn(['b']),
          result('a', cancelledResult),
        ]).sends,
        ['cancelled 2', 'answer 1 cancelled'],
      );
    });

    test('an answered request is out of the table: a late cancel finds no '
        'turn', () {
      expect(
        turnOf(play([bind(1, 'a'), prompt('a'), result('a')]).turns, 1),
        isNull,
      );
    });

    test('closing after a result does not answer twice', () {
      expect(play([bind(1, 'a'), prompt('a'), result('a'), closing]).sends, [
        'answer 1 done',
      ]);
    });

    test('a result after closing answers nothing more', () {
      expect(play([bind(1, 'a'), prompt('a'), closing, result('a')]).sends, [
        'cancelled 1',
      ]);
    });

    test('a result after a withdrawal answers nothing more', () {
      expect(
        play([
          bind(1, 'a'),
          const TurnsWithdrawn(['a']),
          result('a'),
        ]).sends,
        ['cancelled 1'],
      );
    });

    test('the same request id over string and number stays apart', () {
      final (:turns, sends: _) = play([bind(1, 'a'), bind('1', 'b')]);
      expect(turnOf(turns, 1), 'a');
      expect(turnOf(turns, '1'), 'b');
    });

    test('a null request id binds and answers as any other', () {
      expect(play([bind(null, 'a'), prompt('a'), result('a')]).sends, [
        'answer null done',
      ]);
    });
  });

  group('a turn the client steered', () {
    TurnInput steered(String turnId) => TurnSteered(turnId);

    test('run as its own turn it is the client\'s, answers nothing and is '
        'not told back', () {
      final (:turns, :sends) = play([steered('s'), prompt('s', 'mine')]);
      expect(turns.running, (turnId: 's', origin: TurnOrigin.client));
      expect(turns.steered, isEmpty);
      expect(sends, isEmpty);
      expect(play([steered('s'), prompt('s'), result('s')]).sends, isEmpty);
    });

    test('taken into a running turn it changes nothing and is not told '
        'back', () {
      final (:turns, :sends) = play([
        bind(1, 'a'),
        prompt('a'),
        steered('s'),
        const TurnPrompt('s', 'mine', into: 'a'),
      ]);
      expect(turns.running, (turnId: 'a', origin: TurnOrigin.client));
      expect(turns.steered, isEmpty);
      expect(sends, isEmpty);
    });

    test('a send refused or a queue withdrawn leaves nothing steered', () {
      expect(
        play([steered('s'), const TurnUnbind('s')]).turns.steered,
        isEmpty,
      );
      expect(
        play([
          steered('s'),
          const TurnsWithdrawn(['s']),
        ]).turns.steered,
        isEmpty,
      );
    });

    test('another\'s prompt is still a message', () {
      expect(play([steered('s'), message('m', 'report')]).sends, [
        'message report from lead',
      ]);
    });
  });

  group('the session state', () {
    test('running by who began it, idle with no turn, and no origin '
        'then', () {
      SessionState of(List<TurnInput> inputs) =>
          sessionStateOf(play(inputs).turns, asking: false);
      expect(of([bind(1, 'a'), prompt('a')]), (
        state: SessionStateKind.running,
        origin: TurnOrigin.client,
      ));
      expect(of([message('m')]), (
        state: SessionStateKind.running,
        origin: TurnOrigin.message,
      ));
      expect(of([const TurnByAgent('c')]), (
        state: SessionStateKind.running,
        origin: TurnOrigin.agent,
      ));
      expect(of([bind(1, 'a'), prompt('a'), result('a')]), (
        state: SessionStateKind.idle,
        origin: null,
      ));
      expect(of([bind(1, 'a'), prompt('a'), disconnected]), (
        state: SessionStateKind.idle,
        origin: null,
      ));
    });

    test('an open ask requires action, with the running origin if a turn '
        'runs', () {
      expect(sessionStateOf(play([message('m')]).turns, asking: true), (
        state: SessionStateKind.requiresAction,
        origin: TurnOrigin.message,
      ));
      expect(sessionStateOf(noTurns, asking: true), (
        state: SessionStateKind.requiresAction,
        origin: null,
      ));
    });

    test('on the wire: requires_action keeps the origin, idle has none', () {
      expect(
        sessionStateParams('s', (
          state: SessionStateKind.requiresAction,
          origin: TurnOrigin.agent,
        )),
        {'sessionId': 's', 'state': 'requires_action', 'origin': 'agent'},
      );
      expect(
        sessionStateParams('s', (state: SessionStateKind.idle, origin: null)),
        {'sessionId': 's', 'state': 'idle'},
      );
    });
  });

  group('late results and independent tables', () {
    test('a lost turn answers without clearing a newer running turn', () {
      final (:turns, :sends) = play([
        bind('old request', 'old'),
        prompt('old'),
        disconnected,
        bind('new request', 'new'),
        prompt('new'),
        result('old', failed),
        result('old', failed),
      ]);
      expect(sends, ['answer "old request" failed']);
      expect(turns.running, (turnId: 'new', origin: TurnOrigin.client));
      expect(turnOf(turns, 'new request'), 'new');
      expect(reduceTurns(turns, result('new')).sends.map(said), [
        'answer "new request" done',
      ]);
    });

    test('closing one table never removes equal ids in another session', () {
      final first = play([bind(1, 'same'), prompt('same')]).turns;
      final second = play([bind(1, 'same'), prompt('same')]).turns;
      expect(reduceTurns(first, closing).sends.map(said), ['cancelled 1']);
      expect(turnOf(second, 1), 'same');
      expect(reduceTurns(second, result('same')).sends.map(said), [
        'answer 1 done',
      ]);
      expect(noTurns.bound, isEmpty);
    });
  });
}

void _turnInputs() {
  group('what the table hears of a conversation', () {
    test('a prompt, steered or not; a result; a cycle and a self-started '
        'turn; a withdrawn queue; the agent gone', () {
      expect(
        turnInputOf(const Transcribed(PromptAction('t', 'hi', 0, into: 'r'))),
        isA<TurnPrompt>()
            .having((input) => input.turnId, 'turnId', 't')
            .having((input) => input.text, 'text', 'hi')
            .having((input) => input.into, 'into', 'r'),
      );
      expect(
        turnInputOf(const Transcribed(ResultAction('t', done))),
        isA<TurnEnded>()
            .having((input) => input.turnId, 'turnId', 't')
            .having((input) => identical(input.result, done), 'result', true),
      );
      expect(
        turnInputOf(const Transcribed(CycleStartedAction('c', 0))),
        isA<TurnByAgent>().having((input) => input.turnId, 'turnId', 'c'),
      );
      expect(
        turnInputOf(const Transcribed(SelfStartedAction('s'))),
        isA<TurnByAgent>().having((input) => input.turnId, 'turnId', 's'),
      );
      expect(
        turnInputOf(
          const QueueWithdrawn([
            QueuedPrompt('a', 'x'),
            QueuedPrompt('b', 'y'),
          ]),
        ),
        isA<TurnsWithdrawn>().having((input) => input.turnIds, 'turnIds', [
          'a',
          'b',
        ]),
      );
      expect(
        turnInputOf(const Gone('The agent exited.')),
        isA<TurnsDisconnected>(),
      );
      expect(turnInputOf(const Closing()), isNull);
      expect(turnInputOf(const Cleared()), isNull);
    });
  });
}
