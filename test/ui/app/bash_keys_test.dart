import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/status/status.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

KeyContext context(
  AppState state, [
  history.History h = const history.History(),
]) => KeyContext(state: state, history: h, rows: 24);
void main() {
  test(
    'prefix paste and bound typed key enter only from empty ordinary draft',
    () {
      final pasted = changeSteps('!echo hi', 8, context(const AppState()));
      expect((pasted.first as Dispatch).action, isA<BashModeAction>());
      expect((pasted.last as ShowDraft).text, 'echo hi');
      expect(
        keySteps(Chord.parse('!'), context(const AppState())),
        hasLength(2),
      );
      for (final state in [
        const AppState(draft: 'draft'),
        const AppState(bash: true),
      ]) {
        expect(changeSteps('!echo', 5, context(state)).single, isA<Dispatch>());
        expect(keySteps(Chord.parse('!'), context(state)), isEmpty);
      }
    },
  );
  test('empty Backspace leaves mode, CtrlC clears while retaining mode', () {
    for (final key in ['backspace', 'shift+backspace']) {
      final steps = keySteps(
        Chord.parse(key),
        context(const AppState(bash: true)),
      );
      expect(((steps.single as Dispatch).action as BashModeAction).on, isFalse);
      expect(keySteps(Chord.parse(key), context(const AppState())), isEmpty);
    }
    final steps = keySteps(
      Chord.parse('ctrl+c'),
      context(const AppState(bash: true, draft: 'cmd')),
    );
    final cleared = reduceWindow(
      const AppState(bash: true, draft: 'cmd'),
      (steps.first as Dispatch).action,
    );
    expect(cleared.bash, isTrue);
    expect(cleared.draft, '');
  });
  test(
    'shell submit resets mode after recording command and refuses overlap',
    () {
      final steps = submitSteps(
        'echo hi',
        context(const AppState(bash: true, draft: 'echo hi', cursor: 7)),
      );
      expect((steps.first as HistoryStep).history.prompts, ['!echo hi']);
      expect(((steps[1] as Dispatch).action as BashModeAction).on, isFalse);
      expect((steps[2] as ShowDraft).text, '');
      expect((steps.last as RunShellCommand).command, 'echo hi');
      expect(submitSteps(' ', context(const AppState(bash: true))), isEmpty);
      expect(
        submitSteps(
          'echo',
          context(
            const AppState(
              bash: true,
              transcript: Transcript(
                entries: [
                  ShellEntry('s', ShellRun(command: 'one', running: true)),
                ],
              ),
            ),
          ),
        ),
        isEmpty,
      );
      expect(
        keySteps(
          Chord.parse('esc'),
          context(
            const AppState(
              transcript: Transcript(
                entries: [
                  ShellEntry('s', ShellRun(command: 'one', running: true)),
                ],
              ),
            ),
          ),
        ).single,
        isA<StopShellCommand>(),
      );
    },
  );
  test(
    'history restores bash draft and ordinary mode through prefix-preserving walk',
    () {
      const h = history.History(prompts: ['normal', '!old command']);
      final older = olderSteps(
        context(const AppState(bash: true, draft: 'new command'), h),
      );
      expect((older.last as ShowDraft).text, 'old command');
      final restored = newerSteps(
        context(
          const AppState(bash: true, draft: 'old command'),
          (older.first as HistoryStep).history,
        ),
      );
      expect((restored.last as ShowDraft).text, 'new command');
      expect((restored.first as HistoryStep).history.index, isNull);
    },
  );
  test(
    'queued held runs return ahead of newly completed runs without duplication',
    () {
      var state = const AppState(held: ['old']);
      state = reduceApp(state, const Queued('q', 'queued'));
      state = reduceWindow(state, ContextSentAction(['old']));
      state = reduceApp(
        state,
        const Transcribed(ShellStartedAction('new', 'new command')),
      );
      state = reduceApp(
        state,
        const Transcribed(ShellEndedAction('new', code: 0)),
      );
      state = reduceApp(
        state,
        const QueueWithdrawn([QueuedPrompt('q', 'queued')]),
      );
      expect(state.held, ['old', 'new']);
      expect(state.queue, isEmpty);
    },
  );
  test('bash status outranks mode and ordinary hint, notice outranks bash', () {
    final line = statusLine(
      const StatusFacts(bash: true, mode: 'plan', hint: '? for shortcuts'),
      80,
    );
    expect(line.left.single.text, '! for bash mode');
    expect(line.left.single.tone, StatusTone.bash);
    expect(
      statusLine(
        const StatusFacts(bash: true, notice: 'closing'),
        80,
      ).left.single.text,
      'closing',
    );
  });
}
