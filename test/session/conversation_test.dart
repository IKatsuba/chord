// The original's conversation tests (tests/session/conversation_test.ts,
// conversation_between_test.ts), the cases of the person's prompts M1
// covers, on a scripted session under fake time. Left for later: messages
// from other agents, steering, cycles, clear and resume, renames, monitors,
// tasks, costs, and setting modes, models and options.
import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/connection.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'transcript/fold.dart';

/// [events] in short words, to compare in order.
List<String> _said(List<ConversationEvent> events) => [
  for (final event in events)
    switch (event) {
      Transcribed(:final action) => switch (action) {
        PromptAction(:final turnId, :final text) => 'prompt $turnId $text',
        SelfStartedAction(:final turnId) => 'self started $turnId',
        UpdateAction(:final turnId, :final update) =>
          'update $turnId ${update.kind}',
        PermissionRequestedAction(:final turnId, :final between) =>
          'asked $turnId${between ? ' between' : ''}',
        PermissionSettledAction(:final turnId, :final answer) =>
          'settled $turnId ${answer.runtimeType}',
        ElicitationRequestedAction(:final turnId, :final elicitation) =>
          'elicited $turnId${elicitation.between ? ' between' : ''}',
        ElicitationSettledAction(:final turnId, :final answer) =>
          'elicitation settled $turnId ${answer.runtimeType}',
        PlanRequestedAction(:final turnId) => 'plan $turnId',
        PlanSettledAction(:final turnId, :final answer) =>
          'plan settled $turnId ${answer.runtimeType}',
        CancelAction(:final turnId) => 'cancel $turnId',
        SubagentStoppingAction(:final subagentId, :final stopping) =>
          'stopping $subagentId $stopping',
        CycleStartedAction(:final turnId) => 'cycle $turnId',
        UsageAction(:final turnId) => 'usage $turnId',
        ServedAction(:final turnId, :final call) =>
          'served $turnId ${call.tool.wire}',
        DisconnectedAction(:final turnId) => 'disconnected $turnId',
        LeftOpenAction(:final turnId) => 'left open $turnId',
        MonitorsLeftAction(:final turnId) => 'monitors left $turnId',
        ForkedAction(:final from) => 'forked from $from',
        ResultAction(:final turnId, :final result) => switch (result) {
          TurnAnswered(:final stopReason) => 'result $turnId $stopReason',
          TurnFailed(:final message) => 'failed $turnId $message',
        },
        ShellStartedAction() ||
        ShellOutputAction() ||
        ShellEndedAction() ||
        ShellReplayedAction() ||
        FailedAction() ||
        WarnedAction() => '$action',
      },
      HistoryReplayed() => 'history',
      Connected(:final sessionId) => 'connected $sessionId',
      ConnectFailed(:final message) => 'connect failed $message',
      AgentStateChanged() => 'state',
      Queued(:final turnId, :final text, :final afterAnswer) =>
        'queued $turnId $text${afterAnswer ? ' after answer' : ''}',
      QueueWithdrawn(:final prompts) =>
        'withdrawn ${[for (final p in prompts) p.text].join(',')}',
      Gone(:final reason) => 'gone $reason',
      SettingNoted() => 'setting',
      ModePending() => 'mode',
      Cleared() => 'cleared',
      Closing() => 'closing',
      RetiredUpdate(:final turnId) => 'retired update $turnId',
      RetiredUsage(:final figures) => 'retired usage ${figures.turnId}',
      Renamed(:final title) => 'renamed $title',
      RanTyped(:final call) => 'ran ${call.tool.wire}',
      AgentClosed(:final id) => 'agent closed $id',
      MonitorsChanged(:final running) => 'monitors ${running.length}',
    },
];

/// A scripted conversation started and connected, under [async].
Scripted _started(FakeAsync async) {
  final s = Scripted();
  s.conversation.start();
  async.flushMicrotasks();
  return s;
}

void main() {
  test('a prompt before the session is up, or once closing, is refused', () {
    fakeAsync((async) {
      final s = Scripted();

      expect(s.conversation.send('early'), isFalse);
      s.conversation.start();
      async.flushMicrotasks();
      expect(_said(s.events), ['connected s1']);
      expect(s.conversation.send('now'), isTrue);
      s.conversation.close();
      async.flushMicrotasks();
      expect(s.conversation.send('late'), isFalse);
    });
  });

  test('an idle prompt plays at once; its result comes at once with nothing '
      'queued', () {
    fakeAsync((async) {
      final s = _started(async);

      s.conversation.send('hello');
      async.flushMicrotasks();
      s.session.chunk('Hi.');
      s.session.turns.single.answer();
      async.flushMicrotasks();

      expect(_said(s.since(1)), [
        'prompt turn-1 hello',
        'update turn-1 agent_message_chunk',
        'result turn-1 end_turn',
      ]);
      expect(s.session.turns.single.text, 'hello');
    });
  });

  group('the queue and its settle wait', () {
    test('a prompt sent during a turn waits; after the answer nothing plays '
        'at 999 ms of quiet, and it plays at 1 000 ms', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('first');
        async.flushMicrotasks();
        s.conversation.send('second');
        async.flushMicrotasks();
        s.session.turns.first.answer();
        async.elapse(const Duration(milliseconds: 999));

        expect(_said(s.since(1)), [
          'prompt turn-1 first',
          'queued turn-2 second',
        ]);
        expect(s.session.turns, hasLength(1));

        async.elapse(const Duration(milliseconds: 1));

        expect(_said(s.since(3)), [
          'result turn-1 end_turn',
          'prompt turn-2 second',
        ]);
        expect(s.session.turns, hasLength(2));
      });
    });

    test("a chatty agent's tail folds under its turn, and the next plays at "
        'the 5 000 ms cap', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('first');
        async.flushMicrotasks();
        s.conversation.send('second');
        s.session.turns.first.answer();
        async.flushMicrotasks();

        for (var at = 500; at < 5000; at += 500) {
          async.elapse(const Duration(milliseconds: 500));
          s.session.chunk('.');
        }

        expect(s.session.turns, hasLength(1));
        expect(_said(s.events).where((e) => e.startsWith('update')).toSet(), {
          'update turn-1 agent_message_chunk',
        });

        async.elapse(const Duration(milliseconds: 500));

        expect(s.session.turns, hasLength(2));
        // After the cap, what the agent says folds under the new turn: the
        // original's bounded heuristic, as updates carry no prompt id.
        s.session.chunk('late');
        expect(_said(s.events).last, 'update turn-2 agent_message_chunk');
      });
    });

    test('a late update after an immediate resend with nothing queued folds '
        'under the new turn', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('first');
        async.flushMicrotasks();
        s.session.turns.first.answer();
        async.flushMicrotasks();
        s.conversation.send('second');
        async.flushMicrotasks();
        s.session.chunk(' Late, after the answer.');

        expect(_said(s.events).last, 'update turn-2 agent_message_chunk');
      });
    });

    test('Esc during the wait takes the queue back and ends the wait with the '
        'result at once, with no session/cancel', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('first');
        async.flushMicrotasks();
        s.conversation.send('second');
        s.conversation.send('third');
        s.session.turns.first.answer();
        async.elapse(const Duration(milliseconds: 300));

        final from = s.events.length;

        s.conversation.interrupt();
        async.flushMicrotasks();

        expect(_said(s.since(from)), [
          'withdrawn second,third',
          'result turn-1 end_turn',
        ]);
        expect(s.session.cancels, 0);
        async.elapse(const Duration(seconds: 6));
        expect(s.session.turns, hasLength(1));
      });
    });
  });

  group('interrupting', () {
    test('Esc on a running turn takes the queue back, marks it cancelling and '
        'sends session/cancel; the agent ends it cancelled', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('slow');
        async.flushMicrotasks();
        s.conversation.send('next');
        s.conversation.interrupt();
        async.flushMicrotasks();

        expect(_said(s.since(1)), [
          'prompt turn-1 slow',
          'queued turn-2 next',
          'withdrawn next',
          'cancel turn-1',
        ]);
        expect(s.session.cancels, 1);

        s.session.turns.single.answer(const TurnAnswered('cancelled'));
        async.flushMicrotasks();
        expect(_said(s.events).last, 'result turn-1 cancelled');
        expect(s.session.turns, hasLength(1));
      });
    });

    test('a cancel the agent ignores stays Interrupting with no timer; Esc '
        'again sends session/cancel again and changes no state', () {
      fakeAsync((async) {
        final s = _started(async);
        var state = AppState.starting;

        s.conversation.listen((e) => state = reduceApp(state, e));
        s.conversation.send('ignorescancel');
        async.flushMicrotasks();
        s.conversation.interrupt();
        async.elapse(const Duration(minutes: 1));

        final cancelling = state;

        expect(cancelling.transcript.turn, isA<Cancelling>());

        s.conversation.interrupt();
        async.flushMicrotasks();

        expect(s.session.cancels, 2);
        expect(identical(state, cancelling), isTrue);
      });
    });

    test('a queued prompt is taken back alone, the running one stopped '
        'alone, the queue left', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('one');
        async.flushMicrotasks();
        s.conversation.send('two');
        s.conversation.send('three');
        s.conversation.cancelPrompt('turn-2');
        s.conversation.cancelPrompt('turn-1');
        s.conversation.cancelPrompt('gone');
        async.flushMicrotasks();

        expect(_said(s.since(1)).skip(3), ['withdrawn two', 'cancel turn-1']);
        expect(s.session.cancels, 1);

        s.session.turns.first.answer(const TurnAnswered('cancelled'));
        async.elapse(const Duration(seconds: 1));

        expect(_said(s.events).last, 'prompt turn-3 three');
      });
    });
  });

  group('permissions', () {
    test('a request in a turn waits in it; choosing answers the agent and '
        'records it', () async {
      fakeAsync((async) {
        final s = _started(async);
        String? answered;

        s.conversation.send('permission');
        async.flushMicrotasks();
        s.session.ask().then((r) => answered = r.optionId);
        async.flushMicrotasks();

        final id = s.session.permissions.pending().single.id;

        s.conversation.choose(id, 'allow');
        async.flushMicrotasks();

        expect(_said(s.since(2)), ['asked turn-1', 'settled turn-1 Chosen']);
        expect(answered, 'allow');
      });
    });

    test("rejecting answers the agent's reject option", () {
      fakeAsync((async) {
        final s = _started(async);
        String? answered;

        s.conversation.send('permission');
        async.flushMicrotasks();
        s.session.ask().then((r) => answered = r.optionId);
        async.flushMicrotasks();
        s.conversation.reject(s.session.permissions.pending().single.id);
        async.flushMicrotasks();

        expect(_said(s.events).last, 'settled turn-1 Rejected');
        expect(answered, 'deny');
      });
    });

    test('a request withdrawn by the transport is settled withdrawn', () {
      fakeAsync((async) {
        final s = _started(async);
        final token = CancellationToken();

        s.conversation.send('permission');
        async.flushMicrotasks();
        s.session.ask(token: token).ignore();
        async.flushMicrotasks();
        token.cancel();
        async.flushMicrotasks();

        expect(_said(s.events).last, 'settled turn-1 Withdrawn');
      });
    });

    test('a request left open as its turn ends holds the queue; once '
        'answered, what waited plays after the quiet wait', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('leftask');
        async.flushMicrotasks();
        s.session.ask().ignore();
        async.flushMicrotasks();
        s.session.turns.first.answer();
        async.flushMicrotasks();
        s.conversation.send('next');
        async.elapse(const Duration(seconds: 10));

        expect(_said(s.since(2)), [
          'asked turn-1',
          'result turn-1 end_turn',
          'queued turn-2 next after answer',
        ]);

        s.conversation.choose(
          s.session.permissions.pending().single.id,
          'allow',
        );
        async.elapse(const Duration(milliseconds: 999));

        expect(_said(s.events).last, 'queued turn-2 next');

        async.elapse(const Duration(milliseconds: 1));

        expect(_said(s.events).last, 'prompt turn-2 next');
      });
    });

    test('a request asked with no turn running waits between turns, and a '
        'prompt sent then waits for its answer', () {
      fakeAsync((async) {
        final s = _started(async);

        s.session.ask().ignore();
        async.flushMicrotasks();
        s.conversation.send('next');
        async.flushMicrotasks();

        expect(_said(s.since(1)), [
          'asked session between',
          'queued turn-1 next after answer',
        ]);

        s.conversation.reject(s.session.permissions.pending().single.id);
        async.elapse(const Duration(seconds: 1));

        expect(_said(s.events).last, 'prompt turn-1 next');
      });
    });

    test('a request arriving while a prompt waits behind the turn marks it '
        'waiting for the answer only between turns', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('one');
        async.flushMicrotasks();
        s.conversation.send('two');
        s.session.ask().ignore();
        async.flushMicrotasks();

        expect(_said(s.events).last, 'asked turn-1');
      });
    });
  });

  group('the agent going', () {
    test('an exit mid-turn fails the turn once, whichever is heard first, '
        'and reduces to the same state', () {
      Map<String, Object?> play(bool resultFirst) {
        late Map<String, Object?> transcript;

        fakeAsync((async) {
          final s = _started(async);
          var state = AppState.starting;

          s.conversation.listen((e) => state = reduceApp(state, e));
          s.conversation.send('crash');
          async.flushMicrotasks();
          if (resultFirst) {
            s.session.turns.single.answer(
              const TurnFailed('The agent exited: oom'),
            );
            async.flushMicrotasks();
            s.session.exit('oom');
          } else {
            s.session.words = 'oom';
            s.session.exit('oom');
          }
          async.flushMicrotasks();

          expect(_said(s.events).where((e) => e.startsWith('failed')), [
            'failed turn-1 The agent exited: oom',
          ]);
          expect(_said(s.events), contains('gone The agent exited.'));
          transcript = described(state.transcript);
        });

        return transcript;
      }

      expect(play(true), play(false));
      expect((play(true)['entries'] as List).last, {
        'turnId': 'turn-1',
        'kind': 'error',
        'message': 'The agent exited: oom',
      });
    });

    test('each queued prompt then plays and fails the same way', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.send('crash');
        async.flushMicrotasks();
        s.conversation.send('two');
        s.conversation.send('three');
        s.session.exit('oom');
        async.elapse(const Duration(seconds: 3));

        expect(_said(s.events).where((e) => e.startsWith('failed')), [
          'failed turn-1 The agent exited: oom',
          'failed turn-2 The agent exited: oom',
          'failed turn-3 The agent exited: oom',
        ]);
      });
    });

    test('after an idle exit send stays enabled: the prompt is drawn and '
        "fails at once, and Gone carries the agent's stderr", () {
      fakeAsync((async) {
        final s = _started(async);

        s.onTraffic(Traffic.stderr('warming up\nout of memory\n'));
        s.session.exit('out of memory');
        async.flushMicrotasks();

        final gone = s.events.whereType<Gone>().single;

        expect(gone.stderrLines, ['warming up', 'out of memory']);
        expect(_said(s.since(1)), [
          'disconnected session',
          'gone The agent exited.',
        ]);
        expect(s.conversation.send('again'), isTrue);
        async.flushMicrotasks();
        expect(_said(s.events).skip(3), [
          'prompt turn-1 again',
          'failed turn-1 The agent exited: out of memory',
        ]);
      });
    });
  });

  test("the agent's state is told after the updates that may move it", () {
    fakeAsync((async) {
      final s = _started(async);

      s.session.say({
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      });
      s.session.say({
        'sessionUpdate': 'config_option_update',
        'configOptions': [],
      });
      s.session.say({
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [],
      });
      s.session.chunk('x');

      expect(_said(s.since(1)), [
        'update session current_mode_update',
        'state',
        'update session config_option_update',
        'state',
        'update session available_commands_update',
        'state',
        'update session agent_message_chunk',
      ]);
    });
  });

  test('a session that does not open says why', () {
    fakeAsync((async) {
      final s = Scripted(fails: const FormatException('bad command'));

      s.conversation.start();
      async.flushMicrotasks();

      expect(_said(s.events), ['connect failed bad command']);
    });
  });

  test('closing emits Closing, aborts the wait, closes the session, and '
      'nothing is emitted after', () {
    fakeAsync((async) {
      final s = _started(async);

      s.conversation.send('first');
      async.flushMicrotasks();
      s.conversation.send('second');
      s.session.turns.first.answer();
      async.flushMicrotasks();

      final from = s.events.length;
      final closed = s.conversation.close();

      expect(identical(s.conversation.close(), closed), isTrue);
      async.elapse(const Duration(seconds: 6));
      s.session.chunk('after');
      s.session.exit();
      async.flushMicrotasks();

      expect(_said(s.since(from)), ['closing']);
      expect(s.session.closes, 1);
      expect(s.session.turns, hasLength(1));
    });
  });

  group('a listener that acts as it hears', () {
    test('closing as it hears Closing is the one close', () {
      fakeAsync((async) {
        final s = _started(async);
        final futures = <Future<void>>[];

        s.conversation.listen((e) {
          if (e is Closing) futures.add(s.conversation.close());
        });

        final closed = s.conversation.close();
        async.flushMicrotasks();

        expect(futures, hasLength(1));
        expect(identical(futures.single, closed), isTrue);
        expect(s.session.closes, 1);
        expect(_said(s.events).where((e) => e == 'closing'), hasLength(1));
      });
    });

    test('sending as it hears Closing is refused', () {
      fakeAsync((async) {
        final s = _started(async);
        bool? sent;

        s.conversation.listen((e) {
          if (e is Closing) sent = s.conversation.send('late');
        });
        s.conversation.close();
        async.flushMicrotasks();

        expect(sent, isFalse);
        expect(s.session.turns, isEmpty);
      });
    });

    test('closing as it hears a prompt keeps the prompt from the agent', () {
      fakeAsync((async) {
        final s = _started(async);

        s.conversation.listen((e) {
          if (e case Transcribed(action: PromptAction())) {
            s.conversation.close();
          }
        });
        s.conversation.send('hello');
        async.flushMicrotasks();

        expect(s.session.turns, isEmpty);
        expect(s.session.closes, 1);
      });
    });

    test("closing as it hears an event ends that event's delivery; the "
        'others hear only Closing', () {
      fakeAsync((async) {
        final s = Scripted();
        final second = <String>[];

        s.conversation.listen((e) {
          if (e is Connected) s.conversation.close();
        });
        s.conversation.listen((e) => second.add(_said([e]).single));
        s.conversation.start();
        async.flushMicrotasks();

        expect(second, ['closing']);
      });
    });

    test('a request withdrawn as its event is heard is settled withdrawn '
        'once, and the queue does not stick', () {
      final errors = <Object>[];

      runZonedGuarded(() {
        fakeAsync((async) {
          final s = _started(async);
          final token = CancellationToken();

          s.conversation.listen((e) {
            if (e case Transcribed(action: PermissionRequestedAction())) {
              token.cancel();
            }
          });
          s.session.ask(token: token).ignore();
          async.flushMicrotasks();

          expect(_said(s.since(1)), [
            'asked session between',
            'settled session Withdrawn',
          ]);
          expect(s.session.permissions.pending(), isEmpty);

          s.conversation.send('next');
          async.flushMicrotasks();

          expect(_said(s.events).last, 'prompt turn-1 next');
        });
      }, (error, _) => errors.add(error));

      expect(errors, isEmpty);
    });
  });

  test('a listener that throws does not stop the others; its error goes to '
      'the zone', () {
    final errors = <Object>[];

    runZonedGuarded(() {
      fakeAsync((async) {
        final s = Scripted();
        final heard = <String>[];

        s.conversation.listen((_) => throw StateError('listener'));
        s.conversation.listen((e) => heard.add(_said([e]).single));
        s.conversation.start();
        async.flushMicrotasks();

        expect(heard, ['connected s1']);
      });
    }, (error, _) => errors.add(error));

    expect(errors, [isA<StateError>()]);
  });

  group('tester: conversation lifecycle boundaries', () {
    test(
      'closing during startup cancels opening and closes a late session once',
      () {
        fakeAsync((async) {
          final opening = Completer<ScriptedSession>();
          final session = ScriptedSession();
          CancellationToken? token;
          var opens = 0;
          final conversation = Conversation(({
            required onTraffic,
            required cancellationToken,
          }) {
            opens++;
            token = cancellationToken;
            return opening.future;
          });
          final events = <ConversationEvent>[];
          conversation.listen(events.add);
          conversation.start();
          conversation.start();
          final closed = conversation.close();
          expect(token!.isCancelled, isTrue);
          expect(conversation.send('too late'), isFalse);
          opening.complete(session);
          async.flushMicrotasks();
          expect(opens, 1);
          expect(session.closes, 1);
          expect(events, [isA<Closing>()]);
          expect(identical(conversation.close(), closed), isTrue);
          session.chunk('late');
          session.exit();
          async.flushMicrotasks();
          expect(events, hasLength(1));
        });
      },
    );

    test(
      'two between-turn permissions release the queue only after the last answer',
      () {
        fakeAsync((async) {
          final s = _started(async);
          s.session.ask(toolCallId: 'one').ignore();
          s.session.ask(toolCallId: 'two').ignore();
          async.flushMicrotasks();
          final ids = s.session.permissions.pending().map((p) => p.id).toList();
          s.conversation.send('queued');
          s.conversation.choose(ids[1], 'allow');
          async.elapse(const Duration(seconds: 10));
          expect(s.session.turns, isEmpty);
          s.conversation.reject(ids[0]);
          async.elapse(const Duration(milliseconds: 999));
          expect(s.session.turns, isEmpty);
          async.elapse(const Duration(milliseconds: 1));
          expect(s.session.turns.single.text, 'queued');
          expect(s.session.permissions.pending(), isEmpty);
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );

    test(
      'a thousand updates fold literally and close cancels the queued timer',
      () {
        fakeAsync((async) {
          final s = _started(async);
          var state = AppState.starting;
          s.conversation.listen((event) => state = reduceApp(state, event));
          s.conversation.send('first');
          async.flushMicrotasks();
          s.conversation.send('queued');
          const chunk = '界 e\u0301 👩‍💻\x1b[31m';
          for (var i = 0; i < 1000; i++) {
            s.session.chunk(chunk);
          }
          expect(
            (state.transcript.entries.last as AssistantEntry).text.text,
            chunk * 1000,
          );
          s.session.turns.single.answer();
          async.flushMicrotasks();
          s.conversation.close();
          async.elapse(const Duration(seconds: 10));
          expect(s.session.turns, hasLength(1));
          expect(s.session.closes, 1);
          expect(_said(s.events).last, 'closing');
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
  });
}
