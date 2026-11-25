import 'package:chord/notify.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:test/test.dart';

const up = Connected('s', AgentState.empty);
ConversationEvent prompt(String turnId) =>
    Transcribed(PromptAction(turnId, 'hello', 0));
ConversationEvent ended(String turnId) =>
    Transcribed(ResultAction(turnId, const TurnAnswered('end_turn')));
ConversationEvent failed(String turnId) =>
    Transcribed(ResultAction(turnId, const TurnFailed('boom')));
ConversationEvent asked(String turnId, String id, {String? title}) =>
    Transcribed(
      PermissionRequestedAction(
        turnId,
        PermissionWait(id, title: title ?? 'Write notes.txt'),
      ),
    );
ConversationEvent settled(String turnId, String id) =>
    Transcribed(PermissionSettledAction(turnId, id, const Chosen('allow')));
const gone = Transcribed(DisconnectedAction(''));

/// [events] heard in turn, a second apart from [from], [front] or behind.
AgentWait heard(
  List<ConversationEvent> events, {
  AgentWait wait = idle,
  num from = 0,
  bool front = false,
}) {
  var now = from;
  for (final event in events) {
    wait = heardWait(wait, event, now, front: front).wait;
    now += 1000;
  }
  return wait;
}

void main() {
  test('a permission is a wait from when it came; a second is the same '
      'wait', () {
    final wait = heard([up, prompt('t1'), asked('t1', 'p1')]);
    expect(wait.asking?.on, const PermissionAsk(title: 'Write notes.txt'));
    expect(wait.asking?.since, 2000);
    expect(wait.working, 0);
    final again = heardWait(wait, asked('t1', 'p2'), 9000);
    expect(again.started, isNull);
    expect(again.wait.asking?.since, 2000);
  });

  test('a wait is said once, as notify classes it', () {
    final wait = heard([up, prompt('t1')]);
    expect(
      heardWait(wait, asked('t1', 'p1'), 0).started,
      const PermissionAsk(title: 'Write notes.txt'),
    );
    expect(heardWait(wait, ended('t1'), 0).started, const TurnEnded());
  });

  test('an answered permission stops the wait, and the turn goes on', () {
    final wait = heard([
      up,
      prompt('t1'),
      asked('t1', 'p1'),
      settled('t1', 'p1'),
    ]);
    expect(wait.asking, isNull);
    expect(wait.working, 0);
  });

  test('once one request is answered, the wait names the next, from when '
      'it began', () {
    final wait = heard([
      up,
      asked('t1', 'p1', title: 'one'),
      asked('t1', 'p2', title: 'two'),
      settled('t1', 'p1'),
    ]);
    expect(wait.asking?.on, const PermissionAsk(title: 'two'));
    expect(wait.asking?.since, 1000);
  });

  test('a turn ending behind is unseen; in front it is not, and both have '
      'ended', () {
    final behind = heard([up, prompt('t1'), ended('t1')]);
    expect(
      (behind.unseen?.kind, behind.unseen?.since, behind.unseen?.repliedAt),
      (UnseenKind.replied, 2000, 2000),
    );
    expect(behind.working, isNull);
    expect(behind.stopped, 2000);
    final front = heard([up, prompt('t1'), ended('t1')], front: true);
    expect(front.unseen, isNull);
    expect(front.ended, (failure: null));
    // The next turn's start leaves the last one's end behind.
    expect(heard([prompt('t2')], wait: front).ended, isNull);
  });

  test('a failed turn or an agent that never came up is failed, each with '
      'its cause', () {
    final turn = heard([up, prompt('t1'), failed('t1')]);
    final start = heard([const ConnectFailed('no such agent')]);
    final later = heard([prompt('t2'), ended('t2')], wait: turn, from: 5000);
    expect(
      (turn.unseen?.kind, turn.unseen?.failure, turn.unseen?.failedAt),
      (UnseenKind.failed, Failure.turn, 2000),
    );
    expect(turn.ended, (failure: Failure.turn));
    expect(failureOf(start), Failure.start);
    expect(start.ended, (failure: Failure.start));
    // A reply after it does not hide the failure, nor move when it began.
    expect(
      (later.unseen?.failure, later.unseen?.since, later.unseen?.failedAt),
      (Failure.turn, 2000, 2000),
    );
  });

  test('an exit is news even with no turn running, and the agent stays '
      'exited', () {
    final wait = heard([up, gone], from: 5000);
    expect(failureOf(wait), Failure.exited);
    expect(wait.exited, isTrue);
    expect(wait.unseen?.since, 6000);
    // A failed turn after it is the exit's.
    expect(heard([failed('t1')], wait: wait).unseen?.failure, Failure.exited);
  });

  test('an exit after a failed turn, or one that cuts it short, is the '
      'cause', () {
    for (final events in [
      [up, prompt('t1'), failed('t1'), gone],
      [up, prompt('t1'), gone, failed('t1')],
    ]) {
      final wait = heard(events);
      expect(
        (wait.unseen?.failure, failureOf(wait), wait.exited),
        (Failure.exited, Failure.exited, true),
      );
    }
  });

  test('a cancelled turn, or one a queued prompt follows, is not news', () {
    final cancelled = heard([
      up,
      prompt('t1'),
      const Transcribed(CancelAction('t1', 0)),
      ended('t1'),
    ]);
    final queued = heard([
      up,
      prompt('t1'),
      const Queued('t2', 'next'),
      ended('t1'),
    ]);
    expect((cancelled.unseen, cancelled.ended), (null, null));
    expect((queued.unseen, queued.ended), (null, null));
  });

  test('a turn ending leaves its permissions waiting', () {
    final wait = heard([up, prompt('t1'), asked('t1', 'p1'), ended('t1')]);
    expect(wait.asking?.since, 2000);
    expect(wait.unseen?.kind, UnseenKind.replied);
  });

  test('/clear starts over with nothing waiting', () {
    final wait = heard([up, prompt('t1'), asked('t1', 'p1'), const Cleared()]);
    expect(identical(wait, idle), isTrue);
    expect(wait.watch.live, isFalse);
  });

  test("an agent's own cycle works as a turn does until its end", () {
    final wait = heard([
      up,
      const Transcribed(CycleStartedAction('c1', 500)),
    ], front: true);
    expect(wait.working, 500);
    final done = heard([ended('c1')], wait: wait, from: 4000);
    expect(
      (done.working, done.stopped, done.ended),
      (null, 4000, (failure: null)),
    );
  });

  test('it keeps when it last stopped: when it came up, then each end', () {
    final upOnly = heard([up], from: 3000);
    expect(upOnly.stopped, 3000);
    final running = heard([prompt('t1')], wait: upOnly, from: 5000);
    expect(running.stopped, 3000);
    // A reconnect keeps an existing stop.
    expect(heard([up], wait: running, from: 9000).stopped, 3000);
  });

  test('a connection after an exit is the agent up again', () {
    final exited = heard([up, prompt('t1'), gone], front: true);
    expect((exited.exited, exited.ended), (true, (failure: Failure.exited)));
    final again = heard([up], wait: exited, front: true);
    expect((again.exited, again.ended), (false, null));
    final behind = heard([up, gone]);
    expect(heard([up], wait: behind).unseen, isNull);
    // A failed turn stays news across a connection with no exit.
    final turn = heard([up, prompt('t1'), failed('t1')]);
    expect(heard([up], wait: turn).unseen?.failure, Failure.turn);
  });

  group('tester: wait history and independent sessions', () {
    test('failure time differs from the first unseen reply time', () {
      final replied = heard([up, prompt('one'), ended('one')]);
      final failure = heard(
        [prompt('two'), failed('two')],
        wait: replied,
        from: 61000,
      );
      expect(failure.unseen?.since, 2000);
      expect(failure.unseen?.failedAt, 62000);
      expect(failureOf(failure), Failure.turn);
      final later = heard(
        [prompt('three'), failed('three')],
        wait: failure,
        from: 90000,
      );
      expect(later.unseen?.failedAt, 62000);
    });

    test('new replies keep news order but refresh reply age', () {
      final first = heard([up, prompt('one'), ended('one')]);
      final next = heard(
        [prompt('two'), ended('two')],
        wait: first,
        from: 9000,
      );
      expect(next.unseen?.since, 2000);
      expect(next.unseen?.repliedAt, 10000);
      expect(next.stopped, 10000);
    });

    test('reconnect without exit preserves failed turn and startup news', () {
      for (final before in [
        heard([up, prompt('turn'), failed('turn')]),
        heard([const ConnectFailed('refused')]),
      ]) {
        final after = heard([up, up], wait: before, from: 9000);
        expect(identical(after.unseen, before.unseen), isTrue);
        expect(after.ended, before.ended);
        expect(failureOf(after), failureOf(before));
      }
    });

    test(
      'reconnect and clear cannot change another session with the same ids',
      () {
        final other = heard([up, asked('turn', 'p'), gone]);
        var own = heard([up, asked('turn', 'p'), gone]);
        for (var i = 0; i < 3; i++) {
          own = heard([up, up], wait: own, from: 9000 + i * 3000);
          expect((own.exited, own.unseen, own.ended), (false, null, null));
          expect(own.asking?.on, const PermissionAsk(title: 'Write notes.txt'));
          expect(other.exited, isTrue);
          expect(failureOf(other), Failure.exited);
          own = heard([gone], wait: own);
        }
        own = heard([const Cleared()], wait: own);
        expect(identical(own, idle), isTrue);
        expect(other.watch.asking, {'p'});
        expect(other.asking?.since, 1000);
      },
    );

    test(
      'cancelled result after reconnect cannot revive a historical exit',
      () {
        final wait = heard([
          gone,
          up,
          prompt('cancelled'),
          const Transcribed(CancelAction('cancelled', 3000)),
          const Transcribed(
            ResultAction('cancelled', TurnAnswered('cancelled')),
          ),
        ]);
        expect(
          (wait.exited, wait.unseen, wait.ended, wait.working),
          (false, null, null, null),
        );
        expect(wait.watch.cancelled, isEmpty);
      },
    );
  });
}
