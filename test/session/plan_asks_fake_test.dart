// A plan through the session layer, on the original's fake agent
// (tests/fixtures/fake_agent/scenarios/plans.ts), from its
// tests/session/plan_asks_test.ts.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

final class _Agent {
  _Agent() {
    final dir = Directory.systemTemp.createTempSync('chord-plans-');
    conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(),
        cwd: dir.path,
        open: fakeSessionOpener(),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
      ),
    );
    conversation.listen((event) {
      events.add(event);
      state = reduceApp(state, event);
    });
    addTearDown(() async {
      await conversation.close();
      dir.deleteSync(recursive: true);
    });
    conversation.start();
  }

  late final Conversation conversation;
  final events = <ConversationEvent>[];
  var state = AppState.starting;

  Future<void> until(bool Function() matches) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!matches()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  List<PlanWait> get asked => [
    for (final event in events)
      if (event case Transcribed(action: PlanRequestedAction(:final plan)))
        plan,
  ];

  List<PlanAnswer> get settled => [
    for (final event in events)
      if (event case Transcribed(action: PlanSettledAction(:final answer)))
        answer,
  ];

  /// The answers the fake says it heard, newest last.
  List<Object?> get heard => [
    for (final entry in state.transcript.entries)
      if (entry is AssistantEntry &&
          entry.text.text.startsWith('Plan answer: '))
        jsonDecode(entry.text.text.substring('Plan answer: '.length)),
  ];

  Future<void> up() => until(() => state.start.phase == StartPhase.connected);
}

void main() {
  group(
    'a plan through the session layer, on the fake',
    skip: fakeAgentSkip,
    () {
      for (final (scenario, answer, outcome) in <(String, PlanAnswer, Object)>[
        ('cursorplan', const PlanAccepted(), {'outcome': 'accepted'}),
        (
          'cursorplan',
          const PlanKept('Keep it small.'),
          {'outcome': 'rejected', 'reason': 'Keep it small.'},
        ),
        ('grokplan', const PlanAccepted(), {'outcome': 'approved'}),
        (
          'grokplan',
          const PlanKept('More tests.'),
          {'outcome': 'revise', 'feedback': 'More tests.'},
        ),
        ('grokplan', const PlanLeft(), {'outcome': 'abandoned'}),
      ]) {
        test(
          '$scenario: ${answer.runtimeType} reaches the agent as $outcome',
          () async {
            final agent = _Agent();
            await agent.up();
            agent.conversation.send(scenario);
            await agent.until(() => agent.asked.length == 1);
            // Drawn under the call it names, asked.
            final call = agent.state.transcript.entries
                .whereType<ToolEntry>()
                .single
                .call;
            expect(call.plan?.wait.id, agent.asked.single.id);
            expect(agent.state.transcript.planAsks.single.answer, isNull);
            agent.conversation.answerPlan(agent.asked.single.id, answer);
            await agent.until(() => agent.heard.isNotEmpty);
            expect(agent.heard.single, outcome);
            expect(agent.settled.single, same(answer));
            expect(agent.state.transcript.planAsks.single.answer, same(answer));
          },
        );
      }

      test("cursor's plan comes whole, its todos and phases", () async {
        final agent = _Agent();
        await agent.up();
        agent.conversation.send('cursorplan');
        await agent.until(() => agent.asked.length == 1);
        final plan = agent.asked.single;
        expect(plan.agent, PlanAgent.cursor);
        expect(plan.name, 'Route updates by session');
        expect(
          plan.overview,
          'Split the session routing out of the connection.',
        );
        expect(plan.todos?.map((t) => (t.id, t.status)), [
          ('read', 'completed'),
          ('move', 'in_progress'),
          ('test', 'pending'),
        ]);
        expect(plan.phases?.single.name, 'Move');
        expect(plan.phases?.single.todos.map((t) => t.id), ['move', 'test']);
        agent.conversation.answerPlan(plan.id, const PlanCancelled());
        await agent.until(() => agent.heard.isNotEmpty);
        expect(agent.heard.single, {'outcome': 'cancelled'});
      });

      test('the person interrupting the turn answers it cancelled, never a '
          'yes', () async {
        final agent = _Agent();
        await agent.up();
        agent.conversation.send('grokplan');
        await agent.until(() => agent.asked.length == 1);
        agent.conversation.interrupt();
        await agent.until(() => agent.settled.isNotEmpty);
        expect(agent.settled.single, isA<PlanCancelled>());
        await agent.until(() => agent.state.transcript.turn is Idle);
        agent.conversation.send('planheard');
        await agent.until(() => agent.heard.isNotEmpty);
        expect(agent.heard.last, {'outcome': 'cancelled'});
      });

      for (final scenario in [
        'cursorplanbad',
        'cursorplanearly',
        'grokplanwrong',
      ]) {
        test(
          '$scenario: answered cancelled at once, never put to the person',
          () async {
            final agent = _Agent();
            await agent.up();
            agent.conversation.send(scenario);
            await agent.until(() => agent.heard.isNotEmpty);
            expect(agent.heard.single, {'outcome': 'cancelled'});
            expect(agent.asked, isEmpty);
          },
        );
      }

      test('a request after the person interrupted the turn is answered '
          'cancelled, never shown', () async {
        final agent = _Agent();
        await agent.up();
        agent.conversation.send('cursorplanlate');
        await agent.until(
          () =>
              agent.state.transcript.entries.whereType<ToolEntry>().isNotEmpty,
        );
        agent.conversation.interrupt();
        await agent.until(() => agent.state.transcript.turn is Idle);
        expect(agent.asked, isEmpty);
        agent.conversation.send('planheard');
        await agent.until(() => agent.heard.isNotEmpty);
        expect(agent.heard.last, {'outcome': 'cancelled'});
      });

      test('one waiting when the conversation closes goes; the agent is never '
          'told a yes', () async {
        final agent = _Agent();
        await agent.up();
        agent.conversation.send('cursorplan');
        await agent.until(() => agent.asked.length == 1);
        await agent.conversation.close();
        expect(agent.heard, isEmpty);
      });
    },
  );

  group(
    'tester: plans belong to their live fake session',
    skip: fakeAgentSkip,
    () {
      test(
        'one cancelled ask cannot answer another session or a later ask',
        () async {
          final first = _Agent(), second = _Agent();
          await Future.wait([first.up(), second.up()]);
          first.conversation.send('cursorplan');
          second.conversation.send('grokplan');
          await first.until(
            () => first.asked.length == 1 && second.asked.length == 1,
          );
          final old = first.asked.single.id;
          first.conversation.interrupt();
          await first.until(() => first.state.transcript.turn is Idle);
          second.conversation.answerPlan(old, const PlanAccepted());
          expect(second.settled, isEmpty);
          second.conversation.answerPlan(
            second.asked.single.id,
            const PlanKept('More tests.'),
          );
          await second.until(() => second.heard.isNotEmpty);
          expect(second.heard.single, {
            'outcome': 'revise',
            'feedback': 'More tests.',
          });
          first.conversation.send('cursorplan');
          await first.until(() => first.asked.length == 2);
          first.conversation.answerPlan(old, const PlanAccepted());
          expect(first.settled, hasLength(1));
          first.conversation.answerPlan(
            first.asked.last.id,
            const PlanAccepted(),
          );
          await first.until(() => first.heard.isNotEmpty);
          expect(first.heard.last, {'outcome': 'accepted'});
        },
      );

      for (final scenario in ['cursorplan', 'grokplan']) {
        test('$scenario loses approval when its fake process exits', () async {
          final dir = Directory.systemTemp.createTempSync('plan-exit-tester-');
          final pids = <int>[];
          final events = <ConversationEvent>[];
          final conversation =
              Conversation(
                  ({required onTraffic, required cancellationToken}) =>
                      openSession(
                        agent: 'fake',
                        command: fakeAgentCommand(),
                        cwd: dir.path,
                        open: fakeSessionOpener(pids.add),
                        onTraffic: onTraffic,
                        cancellationToken: cancellationToken,
                      ),
                )
                ..listen(events.add)
                ..start();
          addTearDown(() async {
            await conversation.close();
            dir.deleteSync(recursive: true);
          });
          Future<void> until(bool Function() check) async {
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (!check()) {
              if (DateTime.now().isAfter(deadline)) {
                fail('plan exit did not settle');
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          }

          await until(() => events.any((e) => e is Connected));
          conversation.send(scenario);
          await until(
            () => events.any(
              (e) => e is Transcribed && e.action is PlanRequestedAction,
            ),
          );
          final asked = [
            for (final e in events)
              if (e case Transcribed(action: PlanRequestedAction(:final plan)))
                plan,
          ].single;
          expect(pids, hasLength(1));
          expect(Process.killPid(pids.single, ProcessSignal.sigkill), isTrue);
          await until(
            () => events.any(
              (e) => e is Transcribed && e.action is PlanSettledAction,
            ),
          );
          final settled = [
            for (final e in events)
              if (e case Transcribed(action: PlanSettledAction(:final answer)))
                answer,
          ];
          expect(settled, hasLength(1));
          expect(
            settled.single,
            anyOf(isA<PlanCancelled>(), isA<PlanWithdrawn>()),
          );
          conversation.answerPlan(asked.id, const PlanAccepted());
          expect([
            for (final e in events)
              if (e case Transcribed(action: PlanSettledAction(:final answer)))
                answer,
          ], settled);
        });
      }
    },
  );
}
