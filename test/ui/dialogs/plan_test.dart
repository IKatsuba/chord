// From the original's tests/ui/dialogs/plan_test.ts: the box's own keys,
// and the Note row's text, edited at its end (CTUI-178).
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/plan.dart';
import 'package:chord/ui/dialogs/questions.dart' show AskKey;
import 'package:test/test.dart';

void main() {
  test("each agent's choices: cursor's yes and no; grok's, and its way out "
      'of plan mode', () {
    expect(planChoices(PlanAgent.cursor).map((c) => c.label), [
      'Yes, accept the plan',
      'No, keep planning',
    ]);
    expect(planChoices(PlanAgent.grok).map((c) => c.label), [
      'Yes, start implementing',
      'No, keep planning',
      'No, and leave plan mode',
    ]);
  });

  test('the question names the agent, and says so when grok wrote no plan', () {
    const wait = PlanWait('p', PlanAgent.grok, toolCallId: 'c');
    expect(
      planQuestion(
        'grok',
        const PlanWait('p', PlanAgent.grok, toolCallId: 'c', plan: '# R'),
      ),
      'grok has a plan. Do you want to proceed?',
    );
    expect(
      planQuestion('grok', wait),
      'grok has written no plan. Do you want to proceed?',
    );
  });

  group('a key in the plan box', () {
    test('up down and j k move, the Note row past the last choice; up '
        'leaves it', () {
      var state = openPlanBox;
      for (final (key, row) in [
        ('j', 1),
        ('down', 2),
        ('down', 2),
        ('up', 1),
        ('k', 0),
        ('k', 0),
      ]) {
        state = planKey(PlanAgent.cursor, state, key).state;
        expect(state.row, row, reason: key);
      }
    });

    test("shift with an arrow is the window's scroll, and moves nothing", () {
      for (final row in [0, 2]) {
        for (final key in ['shift+up', 'shift+down']) {
          expect(
            planKey(PlanAgent.cursor, (row: row, note: ''), key).state.row,
            row,
          );
        }
      }
    });

    test('a digit picks its choice; enter the one under the ❯; esc keeps '
        'planning with no note', () {
      expect(planKey(PlanAgent.grok, openPlanBox, '3').answer, isA<PlanLeft>());
      expect(planKey(PlanAgent.cursor, openPlanBox, '9').answer, isNull);
      expect(
        planKey(PlanAgent.cursor, openPlanBox, 'enter').answer,
        isA<PlanAccepted>(),
      );
      final escaped = planKey(PlanAgent.grok, (
        row: 3,
        note: 'typed',
      ), 'escape').answer;
      expect(escaped, isA<PlanKept>().having((k) => k.note, 'note', isNull));
    });

    test('on the Note row the box takes no digit or j k, and enter keeps '
        'planning with the note', () {
      const onNote = (row: 2, note: 'keep 2');
      for (final key in ['1', 'j', 'k', 'down']) {
        final step = planKey(PlanAgent.cursor, onNote, key);
        expect((step.state, step.answer), (onNote, null));
      }
      expect(
        planKey(PlanAgent.cursor, onNote, 'enter').answer,
        isA<PlanKept>().having((k) => k.note, 'note', 'keep 2'),
      );
      // Nothing but spaces is no note.
      expect(
        planKey(PlanAgent.cursor, (row: 2, note: '  '), 'enter').answer,
        isA<PlanKept>().having((k) => k.note, 'note', isNull),
      );
    });

    test('a note typed stays on the choices and goes with keep planning '
        'alone', () {
      const typed = (row: 0, note: 'smaller');
      expect(
        planKey(PlanAgent.grok, typed, '2').answer,
        isA<PlanKept>().having((k) => k.note, 'note', 'smaller'),
      );
      expect(planKey(PlanAgent.grok, typed, '1').answer, isA<PlanAccepted>());
      expect(planKey(PlanAgent.grok, typed, '3').answer, isA<PlanLeft>());
    });

    test('on the Note row typing appends; backspace, shift+backspace and '
        'alt+backspace take a character, ctrl+w a word, ctrl+u all', () {
      PlanBoxState? key(
        PlanBoxState state,
        String input, [
        AskKey k = const AskKey(),
      ]) => planNoteKey(state, input, k);
      var state = key((row: 2, note: 'keep '), '2')!;
      expect(state, (row: 2, note: 'keep 2'));
      for (final k in const [
        AskKey(backspace: true),
        AskKey(backspace: true, shift: true),
        AskKey(backspace: true, meta: true),
      ]) {
        state = key((row: 2, note: 'ab👩'), '', k)!;
        expect(state.note, 'ab', reason: '$k');
      }
      expect(
        key(
          (row: 2, note: 'keep it small'),
          'w',
          const AskKey(ctrl: true),
        )!.note,
        'keep it ',
      );
      expect(
        key((row: 2, note: 'keep it'), 'u', const AskKey(ctrl: true))!.note,
        '',
      );
      // A line break typed or pasted into the row is a space.
      expect(key((row: 2, note: 'a'), '\nb')!.note, 'a b');
    });

    test(
      'nothing else on the Note row edits it, cmd with a letter included',
      () {
        const state = (row: 2, note: 'keep');
        for (final (input, k) in const [
          ('a', AskKey(superKey: true)),
          ('z', AskKey(superKey: true)),
          ('z', AskKey(superKey: true, shift: true)),
          ('k', AskKey(ctrl: true)),
          ('b', AskKey(meta: true)),
          ('', AskKey(leftArrow: true)),
          ('', AskKey(enter: true)),
          ('', AskKey(tab: true)),
          ('', AskKey(escape: true)),
        ]) {
          expect(planNoteKey(state, input, k), isNull, reason: '$input $k');
        }
      },
    );

    test('a paste goes into the note on its row, one line, and nowhere '
        'else', () {
      expect(planPaste(PlanAgent.cursor, (row: 2, note: 'a '), 'b\nc'), (
        row: 2,
        note: 'a b c',
      ));
      expect(planPaste(PlanAgent.cursor, openPlanBox, 'b'), openPlanBox);
    });
  });

  test("the hint names the choices' count, and on the Note row what enter "
      'does there', () {
    expect(
      planHint(PlanAgent.cursor, openPlanBox),
      'Enter to pick · 1–2 · ↑↓ to move · Esc to keep planning',
    );
    expect(
      planHint(PlanAgent.grok, openPlanBox),
      'Enter to pick · 1–3 · ↑↓ to move · Esc to keep planning',
    );
    expect(
      planHint(PlanAgent.grok, (row: 3, note: '')),
      'Enter to keep planning with this note · ↑ to the options · Esc to '
      'keep planning',
    );
  });

  test("the Note's lines wrap at its spaces, never cut, a cell left for the "
      'cursor', () {
    expect(noteLines('', 10), ['']);
    expect(noteLines('one two three four', 10), [
      'one two',
      'three four',
      // A full line leaves the cursor's cell to the next.
      '',
    ]);
    // No line starts with the space it broke at, however narrow.
    expect(noteLines('test it; step 40 keep it small', 9), [
      'test it;',
      'step 40',
      'keep it',
      'small',
    ]);
    // The spaces typed last stay, so the cursor is after them.
    expect(noteLines('keep it ', 10), ['keep it ']);
    expect(noteLines('abcdefghijkl', 5).join(), 'abcdefghijkl');
  });
}
