import 'package:chord/acp/connection.dart' show connectAgent;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import '../acp/connection_test.dart' show Harness;

const _start = {
  'sessionUpdate': 'session_info_update',
  '_meta': {'codebuddy.ai/unsolicitedTurn': true},
};
const _end = {'sessionUpdate': 'session_end'};

List<TranscriptAction> _actions(List<ConversationEvent> events) => [
  for (final event in events)
    if (event case Transcribed(:final action)) action,
];

Scripted _afterTurn(FakeAsync async) {
  final s = Scripted();
  s.session.ownCycles = true;
  s.conversation.start();
  async.flushMicrotasks();
  s.conversation.send('first');
  async.flushMicrotasks();
  s.session.turns.single.answer();
  async.flushMicrotasks();
  return s;
}

void main() {
  group('tester: autonomous cycle lane ownership', () {
    test(
      'only the exact initialized Claude adapter starts unmarked cycles',
      () {
        fakeAsync((async) {
          for (final name in [
            '@agentclientprotocol/claude-agent-acp',
            'claude',
            '@agentclientprotocol/claude-agent-acp-other',
            ' @agentclientprotocol/claude-agent-acp',
          ]) {
            final harness = Harness();
            Session? session;
            openSession(
              agent: 'claude',
              command: const ['fixture'],
              cwd: '/project',
              open:
                  ({
                    required command,
                    env,
                    required cwd,
                    required onTraffic,
                    required onPermission,
                    relay,
                    cancellationToken,
                  }) => connectAgent(
                    harness.process,
                    onTraffic: onTraffic,
                    onPermission: onPermission,
                    relay: relay,
                    cancellationToken: cancellationToken,
                  ),
            ).then((value) => session = value);
            async.flushMicrotasks();
            harness.answer(harness.lastRequest('initialize')['id'], {
              'protocolVersion': 1,
              'agentInfo': {'name': name, 'version': '1'},
            });
            async.flushMicrotasks();
            harness.answer(harness.lastRequest('session/new')['id'], {
              'sessionId': 'running',
            });
            async.flushMicrotasks();
            expect(
              session!.startsOwnCycles(),
              name == '@agentclientprotocol/claude-agent-acp',
            );
            session!.close();
            async.flushMicrotasks();
          }
        });
      },
    );

    for (final update in <Map<String, Object?>>[
      {
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'thinking'},
      },
      {'sessionUpdate': 'tool_call', 'toolCallId': 'call', 'title': 'Read'},
      {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call',
        'status': 'completed',
      },
      {'sessionUpdate': 'plan', 'entries': []},
    ]) {
      test(
        '${update['sessionUpdate']} starts an unmarked cycle at the threshold',
        () {
          fakeAsync((async) {
            final s = _afterTurn(async);
            async.elapse(const Duration(milliseconds: 1000));
            s.session.say(update);
            final actions = _actions(s.events);
            final cycle = actions.whereType<CycleStartedAction>().single;
            expect(actions.whereType<UpdateAction>().last.turnId, cycle.turnId);
            s.conversation.close();
            async.flushMicrotasks();
          });
        },
      );
    }

    test('late work and state updates reset the exact quiet threshold', () {
      fakeAsync((async) {
        final s = _afterTurn(async);
        async.elapse(const Duration(milliseconds: 999));
        s.session.chunk('tail one');
        async.elapse(const Duration(milliseconds: 999));
        s.session.say({
          'sessionUpdate': 'session_info_update',
          'title': 'state only',
        });
        async.elapse(const Duration(milliseconds: 999));
        s.session.chunk('tail two');
        expect(_actions(s.events).whereType<CycleStartedAction>(), isEmpty);
        async.elapse(const Duration(milliseconds: 1000));
        s.session.chunk('new cycle');
        expect(
          _actions(s.events).whereType<CycleStartedAction>(),
          hasLength(1),
        );
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test(
      'a thousand updates and duplicate markers keep one cycle and result',
      () {
        fakeAsync((async) {
          final s = _afterTurn(async);
          s.session.say(_start);
          final cycle = _actions(
            s.events,
          ).whereType<CycleStartedAction>().single.turnId;
          final from = s.events.length;
          for (var i = 0; i < 1000; i++) {
            s.session.say(_start);
            s.session.chunk('update $i');
          }
          s.session.say(_end);
          s.session.say(_end);
          final actions = _actions(s.events.skip(from).toList());
          expect(actions.whereType<UpdateAction>(), hasLength(2002));
          expect(
            actions.whereType<UpdateAction>().every((a) => a.turnId == cycle),
            isTrue,
          );
          expect(
            _actions(s.events).whereType<CycleStartedAction>(),
            hasLength(1),
          );
          expect(actions.whereType<ResultAction>().map((a) => a.turnId), [
            cycle,
          ]);
          expect(actions.whereType<PromptAction>(), isEmpty);
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test('marked work during a prompt cannot create an autonomous lane', () {
      fakeAsync((async) {
        final s = Scripted();
        s.session.ownCycles = true;
        s.conversation.start();
        async.flushMicrotasks();
        s.conversation.send('held prompt');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        s.session.say(_start);
        s.session.chunk('reply');
        s.session.say(_end);
        expect(_actions(s.events).whereType<CycleStartedAction>(), isEmpty);
        expect(_actions(s.events).whereType<ResultAction>(), isEmpty);
        s.session.turns.single.answer();
        async.flushMicrotasks();
        expect(_actions(s.events).whereType<ResultAction>(), hasLength(1));
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('two sessions keep their cycle ids and cancellation independent', () {
      fakeAsync((async) {
        final first = _afterTurn(async), second = _afterTurn(async);
        first.session.say(_start);
        second.session.say(_start);
        final a = _actions(
          first.events,
        ).whereType<CycleStartedAction>().single.turnId;
        final b = _actions(
          second.events,
        ).whereType<CycleStartedAction>().single.turnId;
        expect(a, isNot(b));
        first.conversation.interrupt();
        second.session.chunk('still working');
        expect(first.session.cancels, 1);
        expect(second.session.cancels, 0);
        expect(
          _actions(second.events).whereType<UpdateAction>().last.turnId,
          b,
        );
        expect(
          _actions(
            second.events,
          ).whereType<ResultAction>().where((r) => r.turnId == b),
          isEmpty,
        );
        first.conversation.close();
        second.conversation.close();
        async.flushMicrotasks();
      });
    });

    for (final closing in [false, true]) {
      test(
        'reentrant ${closing ? 'close' : 'clear'} on cycle start retires its first update',
        () {
          fakeAsync((async) {
            final old = ScriptedSession(), next = ScriptedSession();
            var opens = 0, retired = false;
            final events = <ConversationEvent>[];
            final conversation = Conversation(
              ({required onTraffic, required cancellationToken}) async =>
                  opens++ == 0 ? old : next,
            );
            conversation.listen((event) {
              events.add(event);
              if (!retired &&
                  event is Transcribed &&
                  event.action is CycleStartedAction) {
                retired = true;
                if (closing) {
                  conversation.close();
                } else {
                  conversation.clear();
                }
              }
            });
            conversation.start();
            async.flushMicrotasks();
            old.say(_start);
            async.flushMicrotasks();
            expect(_actions(events).whereType<UpdateAction>(), isEmpty);
            final settled = events.length;
            old.chunk('retired work');
            old.say(_end);
            async.flushMicrotasks();
            expect(events, hasLength(settled));
            if (!closing) {
              next.say(_start);
              next.chunk('current work');
              final cycles = _actions(
                events,
              ).whereType<CycleStartedAction>().toList();
              expect(cycles, hasLength(2));
              expect(
                _actions(events).whereType<UpdateAction>().last.turnId,
                cycles.last.turnId,
              );
            }
            conversation.close();
            async.flushMicrotasks();
            expect(old.closes, 1);
            if (!closing) expect(next.closes, 1);
          });
        },
      );
    }

    test(
      'an end arriving during cancel and duplicate Esc settle only once',
      () {
        fakeAsync((async) {
          final s = _afterTurn(async);
          s.session.say(_start);
          final cycle = _actions(
            s.events,
          ).whereType<CycleStartedAction>().single.turnId;
          s.session.onCancel = () => s.session.say(_end);
          s.conversation.interrupt();
          s.conversation.interrupt();
          async.flushMicrotasks();
          expect(s.session.cancels, 1);
          expect(
            _actions(s.events).whereType<CancelAction>().map((a) => a.turnId),
            [cycle],
          );
          expect(
            _actions(
              s.events,
            ).whereType<ResultAction>().where((a) => a.turnId == cycle),
            hasLength(1),
          );
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}
