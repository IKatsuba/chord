// A session's spend: each turn's figures as the conversation reports them,
// kept in the record as the original writes them, and read back so a
// resumed window has them.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';

List<TurnFigures> _figures(Iterable<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(action: UsageAction(:final figures))) figures,
];

void _costs(Scripted s, num amount) => s.session.say({
  'sessionUpdate': 'usage_update',
  'used': 10,
  'size': 100,
  'cost': {'amount': amount, 'currency': 'USD'},
});

void main() {
  _cycleCosts();
  _childCostsInHistory();
  group('tester: CTUI-29 spend replay and live ownership', () {
    test(
      'replayed repeated usage replaces one turn rather than adding its correction twice',
      () {
        final header = {
          'type': 'session',
          'version': 1,
          'sessionId': 's',
          'agent': 'fake',
          'cwd': '/w',
          'at': 1,
        };
        Map<String, Object?> usage(num tokens, num amount) => {
          'type': 'usage',
          'turnId': 'one',
          'usage': {'inputTokens': tokens},
          'cost': {'amount': amount, 'currency': 'USD'},
          'model': 'm',
        };
        final history = recordActions([
          header,
          {'type': 'opened', 'at': 2},
          usage(10, 0.1),
          usage(10, 0.3),
        ]);
        final state = reduceApp(
          AppState.starting,
          HistoryReplayed(history.actions, state: AgentState.empty),
        );
        expect(state.spent!.turns, {
          'history-one': {'inputTokens': 10},
        });
        expect(state.spent!.costs, hasLength(1));
        expect(state.spent!.costs!['history-one']!.cost.cost?.amount, 0.3);
        final copied = recordActions([
          header,
          {'type': 'opened', 'at': 3},
          ...historyEntries(history.actions),
        ]);
        final again = reduceApp(
          AppState.starting,
          HistoryReplayed(copied.actions, state: AgentState.empty),
        );
        expect(again.spent!.turns.values.single, {'inputTokens': 10});
        expect(again.spent!.costs!.values.single.cost.cost?.amount, 0.3);
      },
    );

    test(
      'record projection keeps fractional cutoff, currency and sparse zero token fields',
      () {
        final figures = TurnFigures(
          turnId: 'history-before',
          usage: const {'inputTokens': 0, 'thoughtTokens': 0.5},
          total: true,
          model: '界😀é',
          cost: const TurnCost(
            cost: (amount: 0.125, currency: 'EUR'),
            estimated: true,
            before: (until: 7.25),
          ),
        );
        final history = recordActions([
          {'type': 'usage', ...figures.toJson()},
        ]);
        final read = history.actions.whereType<UsageAction>().single.figures;
        expect(read.usage, figures.usage);
        expect(read.total, isTrue);
        expect(read.model, figures.model);
        expect(read.cost, figures.cost);
        expect(read.cost.before?.until, 7.25);
      },
    );

    test(
      'a cancelled answer retains the usage the agent actually reported',
      () {
        fakeAsync((async) {
          final s = Scripted();
          s.conversation.start();
          async.flushMicrotasks();
          s.conversation.send('cancelled work');
          async.flushMicrotasks();
          _costs(s, 0.125);
          s.conversation.interrupt();
          s.session.turns.single.answer(
            const TurnAnswered(
              'cancelled',
              usage: {'inputTokens': 10, 'outputTokens': 0},
            ),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          final figures = _figures(s.events).single;
          expect(figures.usage, {'inputTokens': 10, 'outputTokens': 0});
          expect(figures.cost.cost?.amount, 0.125);
          final state = s.events.fold(AppState.starting, reduceApp);
          expect(state.spent!.turns.values.single, figures.usage);
          expect(s.session.cancels, 1);
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
    test(
      'clearing after one turn removes its spend and keeps the replacement independent',
      () {
        fakeAsync((async) {
          final s = Scripted();
          s.conversation.start();
          async.flushMicrotasks();
          s.conversation.send('first');
          async.flushMicrotasks();
          _costs(s, 0.2);
          s.session.turns.single.answer(
            const TurnAnswered('end_turn', usage: {'inputTokens': 10}),
          );
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          expect(
            s.events.fold(AppState.starting, reduceApp).spent!.costs,
            hasLength(1),
          );
          s.conversation.clear();
          async.flushMicrotasks();
          final state = s.events.fold(AppState.starting, reduceApp);
          expect(state.spent, isNull);
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  });
  test("a turn's answer gives its figures, its cost what the session's moved "
      'by, and a late cost says them again', () {
    fakeAsync((async) {
      final s = Scripted();
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.send('first');
      async.flushMicrotasks();
      _costs(s, 0.01);
      s.session.turns.single.answer(
        const TurnAnswered(
          'end_turn',
          usage: {'inputTokens': 10, 'outputTokens': 2},
        ),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      final first = _figures(s.events).single;
      expect(first.usage, {'inputTokens': 10, 'outputTokens': 2});
      expect(first.cost.cost?.amount, 0.01);
      // Its cost moves after its end, as Claude's can.
      _costs(s, 0.03);
      async.flushMicrotasks();
      final late = _figures(s.events).last;
      expect(late.turnId, first.turnId);
      expect(late.cost.cost?.amount, closeTo(0.03, 1e-12));
      final state = s.events.fold(AppState.starting, reduceApp);
      expect(state.spent!.turns[first.turnId], {
        'inputTokens': 10,
        'outputTokens': 2,
      });
      expect(
        state.spent!.costs![first.turnId]!.cost.cost?.amount,
        closeTo(0.03, 1e-12),
      );
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a usage line is written as the original writes it, and read back as '
      "the turn's figures", () {
    final figures = TurnFigures(
      turnId: 't1',
      usage: const {'inputTokens': 10},
      model: 'm',
      cost: const TurnCost(
        cost: (amount: 0.01, currency: 'USD'),
        estimated: true,
      ),
    );
    final line = {'type': 'usage', ...figures.toJson()};
    expect(line, {
      'type': 'usage',
      'turnId': 't1',
      'usage': {'inputTokens': 10},
      'model': 'm',
      'cost': {'amount': 0.01, 'currency': 'USD'},
      'estimated': true,
    });
    final history = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'fake',
        'cwd': '/w',
        'at': 1,
      },
      {'type': 'opened', 'at': 2},
      line,
      {
        'type': 'usage',
        'turnId': 't2',
        'usage': <String, Object?>{},
        'uncounted': true,
      },
    ]);
    final read = history.actions.whereType<UsageAction>().toList();
    expect(read.map((a) => a.turnId), ['history-t1', 'history-t2']);
    expect(read.first.figures.cost, figures.cost);
    expect(read.first.figures.model, 'm');
    expect(read.last.figures.cost.uncounted, isTrue);
    expect(history.omitted, isFalse);
    expect(historyEntries(history.actions).where((e) => e['type'] == 'usage'), [
      {
        'type': 'usage',
        'turnId': 'history-t1',
        'usage': {'inputTokens': 10},
        'model': 'm',
        'cost': {'amount': 0.01, 'currency': 'USD'},
        'estimated': true,
      },
      {
        'type': 'usage',
        'turnId': 'history-t2',
        'usage': <String, num>{},
        'uncounted': true,
      },
    ]);
  });

  test('what a record spent before it kept turn costs is one figure, up to '
      'its first opening', () {
    Map<String, Object?> cost(num amount) => {
      'type': 'update',
      'turnId': 'old',
      'update': {
        'sessionUpdate': 'usage_update',
        'used': 1,
        'size': 2,
        'cost': {'amount': amount, 'currency': 'USD'},
      },
    };
    final history = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'fake',
        'cwd': '/w',
        'at': 1,
      },
      cost(0.2),
      cost(0.5),
      {'type': 'opened', 'at': 7},
      cost(0.9),
    ]);
    final before = history.actions.whereType<UsageAction>().single.figures;
    expect(before.turnId, 'history-before');
    expect(before.usage, isEmpty);
    expect(before.cost.cost?.amount, 0.5);
    expect(before.cost.before?.until, 7);
    // A record from before the lines: all its costs, with no time.
    final older = recordActions([
      {
        'type': 'session',
        'version': 1,
        'sessionId': 's',
        'agent': 'fake',
        'cwd': '/w',
        'at': 1,
      },
      cost(0.4),
    ]).actions.whereType<UsageAction>().single.figures;
    expect(older.cost.cost?.amount, 0.4);
    expect(older.cost.before?.until, isNull);
  });

  test('a replayed past gives the window its spend', () {
    final state = reduceApp(
      AppState.starting,
      HistoryReplayed([
        UsageAction(
          'history-t1',
          TurnFigures(
            turnId: 'history-t1',
            usage: const {'inputTokens': 5},
            cost: const TurnCost(cost: (amount: 0.2, currency: 'USD')),
          ),
        ),
      ], state: AppState.starting.agent),
    );
    expect(state.spent!.turns['history-t1'], {'inputTokens': 5});
    expect(state.spent!.costs!['history-t1']!.cost.cost?.amount, 0.2);
  });

  test('the recording writes each usage line', () async {
    final writes = <String>[];
    final recording = FileRecording(
      'state',
      failed: fail,
      uuid: () => 'fixture',
      append: (_, text) async => writes.add(text),
    );
    recording.opened(
      const RecordingSession(
        sessionId: 's',
        agent: 'fake',
        cwd: '/w',
        record: null,
        history: [],
        state: AgentState.empty,
      ),
    );
    recording.sent('t', 'hello', 0, [], 1);
    recording.heard(
      Transcribed(
        UsageAction(
          't',
          TurnFigures(
            turnId: 't',
            usage: const {'outputTokens': 3},
            total: true,
          ),
        ),
      ),
    );
    await recording.flushed();
    expect(
      parseRecord(
        writes.join(),
      ).cast<Map<String, Object?>>().where((e) => e['type'] == 'usage'),
      [
        {
          'type': 'usage',
          'turnId': 't',
          'usage': {'outputTokens': 3},
          'total': true,
        },
      ],
    );
    recording.heard(const Closing());
    await recording.flushed();
  });
  test(
    "an agent whose answers give its running total has an old record's "
    'turns read as that total, at the last model; another keeps its rows',
    () {
      UsageAction usage(String turn, num input, String model, {bool? total}) =>
          UsageAction(
            turn,
            TurnFigures(
              turnId: turn,
              usage: {'inputTokens': input},
              model: model,
              total: total ?? false,
            ),
          );
      AppState replay(String agent, List<TranscriptAction> past) {
        late AppState state;
        fakeAsync((async) {
          final s = Scripted();
          s.session.agent = agent;
          s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
          s.session.prepared = PreparedHistory(
            rawHasPast: true,
            omitted: false,
            actions: past,
          );
          s.conversation.start();
          async.flushMicrotasks();
          state = s.events.fold(AppState.starting, reduceApp);
          s.conversation.close();
          async.flushMicrotasks();
        });
        return state;
      }

      final old = [
        usage('history-a', 100, 'm1'),
        usage('history-b', 150, 'm2'),
      ];
      final dirac = replay('dirac', old).spent!;
      expect(dirac.total, {'inputTokens': 150});
      expect(dirac.totalModel, 'm2');
      expect(dirac.turns, isEmpty);
      final other = replay('scripted', [
        ...old,
        usage('history-c', 7, 'm3', total: true),
      ]).spent!;
      expect(other.turns.keys, ['history-a', 'history-b']);
      expect(other.total, {'inputTokens': 7});
    },
  );
}

void _cycleCosts() {
  test("an agent's own cycle has its own cost row, the turn before keeping "
      'its own', () {
    fakeAsync((async) {
      final s = Scripted();
      s.session.ownCycles = true;
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.send('first');
      async.flushMicrotasks();
      _costs(s, 0.01);
      s.session.turns.single.answer();
      async.elapse(const Duration(seconds: 2));
      s.session.chunk('The build passed.');
      s.session.say({
        'sessionUpdate': 'usage_update',
        'used': 10,
        'size': 100,
        'cost': {'amount': 0.03, 'currency': 'USD'},
        '_meta': {
          '_claude/origin': {'kind': 'task-notification'},
        },
      });
      async.flushMicrotasks();

      final cycle = [
        for (final event in s.events)
          if (event case Transcribed(action: CycleStartedAction(:final turnId)))
            turnId,
      ].single;
      final figures = _figures(s.events);
      expect([for (final f in figures) f.turnId], ['turn-1', cycle]);
      expect(figures.first.cost.cost?.amount, 0.01);
      expect(figures.last.cost.cost?.amount, closeTo(0.02, 1e-12));
      final state = s.events.fold(AppState.starting, reduceApp);
      expect(state.spent!.costs!.keys, containsAll(['turn-1', cycle]));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
}

void _childCostsInHistory() {
  test("a resumed session's first turn counts its cost from the session's "
      "own last figure, not a subagent's", () {
    fakeAsync((async) {
      UpdateAction usage(num amount, [String? from]) => UpdateAction(
        'history-1',
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'usage_update',
          'used': 10,
          'size': 100,
          'cost': {'amount': amount, 'currency': 'USD'},
        }),
        subagentId: from,
      );
      final s = Scripted();
      // An agent whose cost counts from the session's start, so its past
      // gives the first turn's baseline.
      s.session.agent = 'opencode';
      // Resumed from a record chord kept, which the past goes on from.
      s.session.record = 'kept';
      s.session.prepared = PreparedHistory(
        rawHasPast: true,
        omitted: false,
        actions: [usage(1.0), usage(5.0, 'a')],
      );
      s.conversation.start();
      async.flushMicrotasks();
      s.conversation.send('next');
      async.flushMicrotasks();
      _costs(s, 1.5);
      s.session.turns.single.answer();
      async.flushMicrotasks();
      final figures = _figures(s.events);
      expect(figures.single.cost.cost?.amount, closeTo(0.5, 1e-12));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
}
