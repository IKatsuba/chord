import 'package:chord/session/context.dart' as context;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/state.dart';
import 'package:test/test.dart';

void main() {
  test(
    'local command keeps turn idle, stable identity and late events still',
    () {
      var state = reduceTranscript(
        Transcript.empty,
        const ShellStartedAction('s', 'ls'),
      );
      final identity = state.entries.single.identity;
      for (final action in [
        const ShellOutputAction('s', false, 'a\n'),
        const ShellOutputAction('s', true, 'oops\n'),
        const ShellOutputAction('s', false, 'b\n'),
        const ShellEndedAction('s', code: 2),
      ]) {
        state = reduceTranscript(state, action);
        expect(state.entries.single.identity, same(identity));
        expect(state.turn, isA<Idle>());
      }
      final run = (state.entries.single as ShellEntry).run;
      expect(
        (run.stdout, run.stderr, run.running, run.code),
        ('a\nb\n', 'oops\n', false, 2),
      );
      expect(
        reduceTranscript(state, const ShellOutputAction('s', false, 'late')),
        same(state),
      );
      expect(
        reduceTranscript(state, const ShellEndedAction('missing')),
        same(state),
      );
      expect(runningShell(state), isNull);
    },
  );
  test(
    'each stream is bounded by UTF16 units and replay creates fresh occurrence',
    () {
      var state = reduceTranscript(
        Transcript.empty,
        const ShellStartedAction('s', 'yes'),
      );
      final before = state.entries.single.identity;
      for (final stderr in [false, true]) {
        state = reduceTranscript(
          state,
          ShellOutputAction('s', stderr, 'x' * (context.outputLimit - 1)),
        );
        state = reduceTranscript(state, ShellOutputAction('s', stderr, 'yz'));
      }
      final run = (state.entries.single as ShellEntry).run;
      expect(run.stdout.length, context.outputLimit);
      expect(run.stderr.length, context.outputLimit);
      expect(run.stdout, endsWith('y'));
      expect(run.truncated, isTrue);
      state = reduceTranscript(state, ShellReplayedAction('replay', run));
      expect(state.entries.last.identity, isNot(same(before)));
      expect((state.entries.last as ShellEntry).run, same(run));
    },
  );
  test(
    'only current ended runs are held, in completion order, consumed exactly',
    () {
      var state = const AppState();
      for (final action in [
        const ShellStartedAction('first', 'a'),
        const ShellStartedAction('second', 'b'),
        const ShellEndedAction('second', code: 2),
        const ShellEndedAction('first', code: 0),
      ]) {
        state = reduceApp(state, Transcribed(action));
      }
      expect(state.held, ['second', 'first']);
      expect(
        heldContext(state.transcript, state.held),
        startsWith('<bash-input>b</bash-input>'),
      );
      final sameState = reduceApp(
        state,
        const Transcribed(ShellEndedAction('first')),
      );
      expect(sameState, same(state));
      state = reduceWindow(state, ContextSentAction(['second']));
      expect(state.held, ['first']);
      state = reduceApp(state, const Cleared());
      expect(state.held, isEmpty);
      expect(
        reduceApp(state, const Transcribed(ShellEndedAction('first'))),
        same(state),
      );
    },
  );
}
