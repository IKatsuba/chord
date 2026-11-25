// The original's tests/session/conversation_cycle_test.ts, an agent's own
// cycle after its turn (CHD-426), on a scripted session under fake time:
// Claude's unmarked cycle after the quiet, codebuddy's markers, a prompt
// taking one over, Esc in one and a clear during one.
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/reports.dart' show runningTurn;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

/// [events] by kind and turn, as far as cycles go.
List<String> _said(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(:final action))
      switch (action) {
        CycleStartedAction() => 'cycle',
        PromptAction(:final turnId) => 'prompt $turnId',
        UpdateAction(:final turnId, :final update) => '${update.kind} $turnId',
        CancelAction(:final turnId) => 'cancel $turnId',
        ResultAction(:final turnId, result: TurnAnswered(:final stopReason)) =>
          'result $turnId $stopReason',
        _ => '${action.runtimeType}',
      }
    else if (event case RetiredUsage(:final figures))
      'retired usage ${figures.turnId}'
    else if (event is Cleared)
      'cleared',
];

/// The id chord gave the cycle the events began.
String _cycleOf(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(action: CycleStartedAction(:final turnId)))
      turnId,
].single;

const _autonomousUsage = {
  'sessionUpdate': 'usage_update',
  'used': 10,
  'size': 100,
  '_meta': {
    '_claude/origin': {'kind': 'task-notification'},
  },
};

/// A connected conversation whose first turn has answered and settled.
Scripted _afterTurn(FakeAsync async, {bool claude = true}) {
  final s = Scripted();
  s.session.ownCycles = claude;
  s.conversation.start();
  async.flushMicrotasks();
  s.conversation.send('build');
  async.flushMicrotasks();
  s.session.turns.single.answer();
  async.flushMicrotasks();
  return s;
}

void main() {
  test('a cycle works as a turn does, and keeps the requests it found '
      'waiting held', () {
    final working = reduceTranscript(
      Transcript.empty,
      const CycleStartedAction('c1', 5),
    ).turn;
    expect(working, isA<Working>());
    working as Working;
    expect((working.turnId, working.since, working.cycle), ('c1', 5, true));

    const wait = PermissionWait('p1');
    final held =
        reduceTranscript(
              const Transcript(
                turn: AwaitingPermission('turn-1', 3, [wait], between: true),
              ),
              const CycleStartedAction('c1', 5),
            ).turn
            as AwaitingPermission;
    expect(held.turnId, 'c1');
    expect(held.since, 3);
    expect(held.permissions, [wait]);
    expect(held.between, isTrue);
    expect((held.cycle, held.cycleSince), (true, 5));
  });

  test("Claude's: its work after the turn has gone quiet is a cycle of its "
      'own, ended by the autonomous usage', () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      final from = s.events.length;
      async.elapse(const Duration(milliseconds: 1000));
      s.session.chunk('The build passed.');
      s.session.say(_autonomousUsage);
      async.flushMicrotasks();

      final cycle = _cycleOf(s.events);
      expect(cycle, isNot('turn-1'));
      expect(_said(s.since(from)), [
        'cycle',
        'agent_message_chunk $cycle',
        'usage_update $cycle',
        'result $cycle end_turn',
      ]);
    });
  });

  test("Claude's work within the quiet after its turn is that turn's tail", () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      final from = s.events.length;
      async.elapse(const Duration(milliseconds: 999));
      s.session.chunk('More.');
      async.flushMicrotasks();

      expect(_said(s.since(from)), ['agent_message_chunk turn-1']);
    });
  });

  test("Claude's with no usage to end it stays working: no result comes", () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('The build passed.');
      async.elapse(const Duration(seconds: 10));

      final cycle = _cycleOf(s.events);
      expect(_said(s.events), isNot(contains('result $cycle end_turn')));
    });
  });

  test("an agent that is not Claude's has no unmarked cycle: its work after "
      'the turn folds under that turn', () {
    fakeAsync((async) {
      final s = _afterTurn(async, claude: false);
      final from = s.events.length;
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('The build passed.');
      s.session.say(_autonomousUsage);
      async.flushMicrotasks();

      expect(_said(s.since(from)), [
        'agent_message_chunk turn-1',
        'usage_update turn-1',
      ]);
    });
  });

  test("codebuddy's: its marker starts a cycle and session_end ends it", () {
    fakeAsync((async) {
      final s = _afterTurn(async, claude: false);
      final from = s.events.length;
      s.session.say({
        'sessionUpdate': 'session_info_update',
        '_meta': {'codebuddy.ai/unsolicitedTurn': true},
      });
      s.session.chunk('All checks are green.');
      s.session.say({'sessionUpdate': 'session_end'});
      async.flushMicrotasks();

      final cycle = _cycleOf(s.events);
      expect(_said(s.since(from)), [
        'cycle',
        'session_info_update $cycle',
        'agent_message_chunk $cycle',
        'session_end $cycle',
        'result $cycle end_turn',
      ]);
    });
  });

  test('a prompt sent while a cycle runs goes at once and takes it over; '
      'a late end marker does not end that prompt', () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('Reading the log.');
      async.flushMicrotasks();
      final cycle = _cycleOf(s.events);
      final from = s.events.length;

      expect(s.conversation.send('next'), isTrue);
      async.flushMicrotasks();
      s.session.chunk('On it.');
      s.session.say(_autonomousUsage);
      async.flushMicrotasks();

      expect(s.session.turns, hasLength(2));
      expect(_said(s.since(from)), [
        'prompt turn-2',
        'agent_message_chunk turn-2',
        'usage_update turn-2',
      ]);
      expect(_said(s.events), isNot(contains('result $cycle end_turn')));
    });
  });

  test('Esc sends session/cancel for it, and the cycle ends as a cancelled '
      'turn does; with no cycle and no turn, Esc tells the agent nothing', () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      s.conversation.interrupt();
      async.flushMicrotasks();
      expect(s.session.cancels, 0);

      async.elapse(const Duration(seconds: 2));
      s.session.chunk('Reading the log.');
      async.flushMicrotasks();
      final cycle = _cycleOf(s.events);
      final from = s.events.length;
      s.conversation.interrupt();
      async.flushMicrotasks();

      expect(s.session.cancels, 1);
      expect(_said(s.since(from)).take(2), [
        'cancel $cycle',
        'result $cycle cancelled',
      ]);

      // What it says after its end folds under it, as after a turn.
      s.session.chunk('Stopped.');
      async.flushMicrotasks();
      expect(_said(s.events).last, 'agent_message_chunk $cycle');
    });
  });

  test('a clear during a cycle tells the agent to stop and says what the '
      'cycle cost as the session let go', () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('Reading the log.');
      async.flushMicrotasks();
      final from = s.events.length;
      s.conversation.clear();
      async.flushMicrotasks();

      expect(s.session.cancels, 1);
      final said = _said(s.since(from));
      expect(said, contains('cleared'));
      expect(said, isNot(contains(startsWith('result'))));
    });
  });

  test('a request asked in a cycle is held as between turns; answered, the '
      'cycle works on from its start, and its end leaves no other', () {
    fakeAsync((async) {
      final s = _afterTurn(async);
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('Reading the log.');
      async.flushMicrotasks();
      final cycle = _cycleOf(s.events);
      final started =
          s.events.fold(AppState.starting, reduceApp).transcript.turn
              as Working;

      async.elapse(const Duration(seconds: 1));
      s.session.ask().ignore();
      async.flushMicrotasks();
      final held = s.events.fold(AppState.starting, reduceApp).transcript.turn;
      expect(held, isA<AwaitingPermission>());
      held as AwaitingPermission;
      expect((held.turnId, held.between, held.cycle), (cycle, true, true));
      expect(held.cycleSince, started.since);
      expect(runningTurn(held), cycle);

      s.conversation.choose(s.session.permissions.pending().single.id, 'allow');
      async.flushMicrotasks();
      final working =
          s.events.fold(AppState.starting, reduceApp).transcript.turn
              as Working;
      expect(
        (working.turnId, working.since, working.cycle),
        (cycle, started.since, true),
      );

      s.session.say(_autonomousUsage);
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('More, after the end.');
      async.flushMicrotasks();
      expect(
        [
          for (final e in s.events)
            if (e case Transcribed(action: CycleStartedAction())) e,
        ],
        hasLength(2),
        reason: 'work after the quiet is a new cycle, the answer was not',
      );
      expect(
        s.events.fold(AppState.starting, reduceApp).transcript.turn,
        isA<Working>(),
      );
    });
  });

  test('a request held between turns with no cycle is no turn running', () {
    const wait = PermissionWait('p1');
    expect(
      runningTurn(const AwaitingPermission('t', 0, [wait], between: true)),
      isNull,
    );
    expect(
      runningTurn(
        const AwaitingPermission('c', 0, [wait], between: true, cycle: true),
      ),
      'c',
    );
  });
}
