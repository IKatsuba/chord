import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/prompt/prompt.dart';
import 'package:chord/ui/app/keys.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart' as history;
import 'package:chord/ui/start_state.dart';
import 'package:test/test.dart';

KeyContext context(
  StartPhase phase, {
  bool closing = false,
  bool bash = false,
}) => KeyContext(
  state: AppState(
    start: StartState(phase: phase),
    closing: closing,
    bash: bash,
  ),
  history: const history.History(prompts: ['earlier']),
  rows: 24,
);

void main() {
  group('tester: CTUI-76 startup submission classification', () {
    for (final phase in [StartPhase.idle, StartPhase.starting]) {
      test(
        'every local command bypasses only the startup prompt gate in $phase',
        () {
          for (final text in [
            '/clear',
            '/config',
            '/context',
            '/cost',
            '/effort high',
            '/fast',
            '/fork',
            '/help',
            '/mcp',
            '/model',
            '/new fake',
            '/rename 界🙂e\u0301',
            '/resume',
            '/status',
            '/team',
            '/theme',
            '/vim',
            '/exit',
          ]) {
            final steps = submitSteps(text, context(phase));
            expect(steps, hasLength(1), reason: text);
            expect((steps.single as Send).text, text);
            expect(submitSteps(text, context(phase, closing: true)), isEmpty);
          }
        },
      );
      test(
        'ordinary, unknown and escaped slash prompts remain held in $phase',
        () {
          for (final text in [
            '界🙂e\u0301',
            '/unadvertised-command args',
            '\x1b[31m/help',
            'hello\n/help',
          ]) {
            expect(submitSteps(text, context(phase)), isEmpty, reason: text);
          }
        },
      );
    }
  });

  _testerFailedStartSubmitBoundaries();
  test(
    'failed startup delegates unchanged input to the existing command owner',
    () {
      for (final text in [
        '/resume',
        '/res',
        '/clear',
        '/help',
        '/status',
        '/exit',
        '/model',
        '/config',
        '/effort',
        '/effort high',
        '/fast',
        '/cost',
        ' ordinary text ',
      ]) {
        final steps = submitSteps(text, context(StartPhase.failed));
        expect(steps, hasLength(1), reason: text);
        expect((steps.single as Send).text, text);
      }
    },
  );

  test('while the agent starts a prompt waits and chord\'s own commands '
      'run; closing and blank submissions stay guarded', () {
    for (final phase in [StartPhase.idle, StartPhase.starting]) {
      expect(submitSteps('ordinary text', context(phase)), isEmpty);
      for (final text in ['/resume', '/clear', '/help', '/model', '/mcp']) {
        final steps = submitSteps(text, context(phase));
        expect(steps, hasLength(1), reason: '$phase $text');
        expect((steps.single as Send).text, text);
      }
    }
    for (final phase in StartPhase.values) {
      expect(submitSteps('/resume', context(phase, closing: true)), isEmpty);
      expect(submitSteps('  ', context(phase)), isEmpty);
    }
  });

  test('failed startup retains the existing local shell submission order', () {
    final steps = submitSteps(
      'echo fixture',
      context(StartPhase.failed, bash: true),
    );
    expect(steps, hasLength(4));
    expect((steps[0] as HistoryStep).history.prompts.last, '!echo fixture');
    expect(steps[1], isA<Dispatch>());
    expect((steps[2] as ShowDraft).text, '');
    expect((steps[3] as RunShellCommand).command, 'echo fixture');
    expect(
      submitSteps(
        'echo fixture',
        context(StartPhase.failed, bash: true, closing: true),
      ),
      isEmpty,
    );
  });
}

void _testerFailedStartSubmitBoundaries() {
  group('tester: U52a failed startup submit boundaries', () {
    test(
      'Unicode multiline commands and escape bytes reach the classifier unchanged',
      () {
        final h = history.History(prompts: const ['earlier']);
        final newline = String.fromCharCode(10);
        final escape = String.fromCharCode(27);
        for (final text in [
          '/resume 界🙂é',
          '/help$newline界🙂é',
          '  /status  arg${String.fromCharCodes([13, 10])}next  ',
          '$escape[31m/resume$escape[0m',
        ]) {
          final state = AppState(
            start: const StartState(phase: StartPhase.failed),
            draft: text,
            cursor: endOf(text),
          );
          final steps = submitSteps(
            text,
            KeyContext(state: state, history: h, rows: 24),
          );
          expect(steps, hasLength(1));
          expect((steps.single as Send).text, text);
          expect(state.draft, text);
          expect(state.cursor, endOf(text));
          expect(h.prompts, ['earlier']);
        }
      },
    );

    test(
      'failed Unicode whitespace stays inert without recording or clearing',
      () {
        for (final text in [
          '',
          String.fromCharCodes([32, 9, 13, 10, 32]),
          String.fromCharCodes([160, 8195]),
        ]) {
          expect(submitSteps(text, context(StartPhase.failed)), isEmpty);
          expect(
            submitSteps(text, context(StartPhase.failed, bash: true)),
            isEmpty,
          );
        }
      },
    );

    test('command continuation edits before failed-start delegation', () {
      const prefix = '/help 界🙂é';
      final backslash = String.fromCharCode(92);
      final value = '$prefix${backslash}tail';
      final cursor = endOf('$prefix$backslash');
      final state = AppState(
        start: const StartState(phase: StartPhase.failed),
        draft: value,
        cursor: cursor,
      );
      final steps = submitSteps(
        value,
        KeyContext(state: state, history: const history.History(), rows: 24),
      );
      expect(steps, hasLength(1));
      expect(
        (steps.single as ShowDraft).text,
        '$prefix${String.fromCharCode(10)}tail',
      );
      expect((steps.single as ShowDraft).cursor, cursor);
      expect(state.draft, value);
    });

    test(
      'an already running local command still blocks shell submit after startup failure',
      () {
        final state = AppState(
          start: const StartState(phase: StartPhase.failed),
          bash: true,
          transcript: const Transcript(
            entries: [
              ShellEntry(
                'running',
                ShellRun(command: 'existing', running: true),
              ),
            ],
          ),
        );
        final h = history.History(prompts: const ['!existing']);
        final steps = submitSteps(
          'echo next',
          KeyContext(state: state, history: h, rows: 24),
        );
        expect(steps, isEmpty);
        expect(h.prompts, ['!existing']);
      },
    );
  });
}
