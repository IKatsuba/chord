import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/closing.dart';
import 'package:chord/ui/app/state.dart';
import 'package:test/test.dart';

void main() {
  test("a first x on a busy team's lead names its members, which close with "
      'it', () {
    expect(
      teamCloseArmedLine('bugfix', 3, 'x'),
      'bugfix and its 3 members are working · x again to stop them and close',
    );
    expect(
      teamCloseArmedLine('bugfix', 1, 'x'),
      'bugfix and its member are working · x again to stop them and close',
    );
  });
  test('Ctrl+C asks once more before quitting, counting nothing', () {
    expect(ctrlCArmedLine(), 'Press ctrl+c again to quit');
    expect(quitWindowMs, 2000);
  });
  test('arming, expiry and repeated arming are plain reducer transitions', () {
    const idle = AppState();
    final armed = reduceWindow(idle, const QuitArmedAction());
    expect(armed.quitArmed, isTrue);
    expect(reduceWindow(armed, const QuitArmedAction()), same(armed));
    final expired = reduceWindow(armed, const QuitDisarmedAction());
    expect(expired.quitArmed, isFalse);
    expect(reduceWindow(expired, const QuitDisarmedAction()), same(expired));
    expect(reduceWindow(expired, const QuitArmedAction()).quitArmed, isTrue);
  });
  test('clearing a draft disarms without changing running or queued work', () {
    final running = reduceApp(
      const AppState(),
      const Transcribed(PromptAction('turn', 'hello', 0)),
    );
    final queued = reduceApp(running, const Queued('next', 'later'));
    final armed = reduceWindow(queued, const QuitArmedAction());
    final cleared = reduceWindow(armed, const DraftClearedAction());
    expect(cleared.quitArmed, isFalse);
    expect(cleared.transcript, same(queued.transcript));
    expect(cleared.queue, same(queued.queue));
    expect(reduceWindow(cleared, const DraftClearedAction()), same(cleared));
  });
  test('session events retain an armed quit', () {
    final armed = reduceWindow(const AppState(), const QuitArmedAction());
    expect(reduceApp(armed, const Queued('next', 'later')).quitArmed, isTrue);
  });

  group('tester: pure quit state isolation', () {
    test('every quit transition preserves all unrelated state references', () {
      final connected = reduceApp(
        AppState.starting,
        const Connected('session', AgentState.empty),
      );
      final running = reduceApp(
        connected,
        const Transcribed(PromptAction('turn', '界🙂e\u0301', 0)),
      );
      final queued = reduceApp(running, const Queued('next', 'later'));
      var state = AppState(
        start: queued.start,
        agent: queued.agent,
        transcript: queued.transcript,
        queue: queued.queue,
        attended: 'request',
      );
      final original = state;
      for (final action in const <AppAction>[
        QuitArmedAction(),
        QuitDisarmedAction(),
        QuitArmedAction(),
        DraftClearedAction(),
      ]) {
        state = reduceWindow(state, action);
        expect(state.start, same(original.start));
        expect(state.agent, same(original.agent));
        expect(state.transcript, same(original.transcript));
        expect(state.queue, same(original.queue));
        expect(state.attended, original.attended);
      }
      expect(original.quitArmed, isFalse);
    });

    test('cancelled turns and late agent events cannot disarm a quit', () {
      var state = reduceWindow(AppState.starting, const QuitArmedAction());
      for (final event in const <ConversationEvent>[
        Connected('session', AgentState.empty),
        Transcribed(PromptAction('turn', 'prompt', 0)),
        Transcribed(ResultAction('turn', TurnAnswered('cancelled'))),
        Queued('next', 'queued'),
        QueueWithdrawn([QueuedPrompt('next', 'queued')]),
        Gone('The agent exited.'),
        Closing(),
        ConnectFailed('late'),
      ]) {
        state = reduceApp(state, event);
        expect(state.quitArmed, isTrue, reason: '$event');
      }
      expect(
        reduceWindow(state, const QuitDisarmedAction()).quitArmed,
        isFalse,
      );
    });

    test(
      'a thousand repeated transitions stay independent between sessions',
      () {
        var first = reduceApp(const AppState(), const Queued('first', 'one'));
        final second = reduceApp(
          const AppState(),
          const Queued('second', 'two'),
        );
        for (var i = 0; i < 1000; i++) {
          first = reduceWindow(first, const QuitArmedAction());
          expect(reduceWindow(first, const QuitArmedAction()), same(first));
          first = reduceWindow(first, const QuitDisarmedAction());
        }
        expect(first.quitArmed, isFalse);
        expect(first.queue.single.turnId, 'first');
        expect(second.quitArmed, isFalse);
        expect(second.queue.single.turnId, 'second');
      },
    );
  });
}
