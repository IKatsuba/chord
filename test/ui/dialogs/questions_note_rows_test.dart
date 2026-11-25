// cmd+← and cmd+→ in a question's Note go to the shown row's start or end,
// as the prompt's do (docs/guide.md 259-262; the original's questions.ts
// 204-212 hands them to the Note's textarea, and not ctrl+a or ctrl+e).
import 'package:characters/characters.dart';
import 'package:chord/session/enrich.dart';
import 'package:chord/session/enrichers.dart';
import 'package:chord/session/questions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/questions.dart';
import 'package:chord/ui/dialogs/questions_box.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/questions.dart';

/// [form] asked as the enrichers read it.
FormWait _asked(Map<String, Object?> form) {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...form, 'sessionId': 's'},
  });
  final params = recordOf(message['params']);
  return FormWait(
    'e1',
    form['message'] as String,
    schema: recordOf(form['requestedSchema']),
    questions: questionsOf(params),
  );
}

TextAreaController _noteController(WidgetTester t) {
  TextAreaController? found;
  void visit(Element e) {
    if (e.widget case TextArea(:final controller?)) found = controller;
    e.visitChildren(visit);
  }

  visit(t.host.rootElement);
  return found!;
}

void main() {
  group('tester CTUI-163: exact Note row endpoints', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('Unicode Note row endpoints and insertion are exact at $size', (
        t,
      ) async {
        final note = '界👩‍💻éabcdef ' * 24;
        AskState? kept;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final wait = _asked(claudeQuestionForm);
        await t.pumpWidget(
          Column(
            children: [
              QuestionBox(
                wait: wait,
                questions: wait.questions!,
                agent: 'fake',
                windowRows: size.height,
                held: false,
                between: false,
                attendKey: 'ctrl+x a',
                focusNode: focus,
                filled: AskState(
                  step: 0,
                  row: 2,
                  answers: {'question_0': QuestionAnswer(own: note)},
                  noteCursors: {'question_0': 1},
                ),
                onFill: (state) => kept = state,
                now: () => 0,
                onAnswer: (_) {},
              ),
            ],
          ),
          size: size,
        );
        focus.requestFocus();
        await t.pump();
        final c = _noteController(t);
        final row = c.lastLayout!.rows[1];
        c.cursor = row.start + 1;
        await t.pump();
        await t.press('super+left');
        expect(kept!.noteCursors['question_0'], row.start);
        expect(c.lastLayout!.cursorColumn, 0);
        await t.press('super+right');
        final end = row.end - 1;
        expect(kept!.noteCursors['question_0'], end);
        expect(c.lastLayout!.cursorRow, 1);
        final expectedColumn = cellWidth(
          note.characters.skip(row.start).take(end - row.start).join(),
        );
        expect(c.lastLayout!.cursorColumn, expectedColumn);
        await t.type('X');
        expect(
          kept!.answers['question_0']!.own,
          '${note.characters.take(end).join()}X${note.characters.skip(end).join()}',
        );
        await t.press('backspace');
        expect(kept!.answers['question_0']!.own, note);
        await t.press('super+right');
        expect(kept!.noteCursors['question_0'], end);
        // Resizing gives the same keys the new displayed row's endpoints.
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        final current = c.lastLayout!.rows[c.lastLayout!.cursorRow];
        await t.press('super+left');
        expect(kept!.noteCursors['question_0'], current.start);
      });
    }
  });
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('CTUI-163: cmd+left/right in a wrapped Note row at $size', (
      t,
    ) async {
      final note = List.generate(120, (i) => 'n$i').join(' ');
      AskState? kept;
      final focus = FocusNode();
      final wait = _asked(claudeQuestionsForm);
      await t.pumpWidget(
        Column(
          children: [
            QuestionBox(
              wait: wait,
              questions: wait.questions!,
              agent: 'fake',
              windowRows: size.height,
              held: false,
              between: false,
              attendKey: 'ctrl+x a',
              focusNode: focus,
              filled: AskState(
                step: 0,
                row: 2,
                answers: {'question_0': QuestionAnswer(own: note)},
                noteCursors: {'question_0': note.length ~/ 2},
              ),
              onFill: (state) => kept = state,
              now: () => 0,
              onAnswer: (_) {},
            ),
          ],
        ),
        size: size,
      );
      focus.requestFocus();
      await t.pump();
      int cursor() => kept!.noteCursors['question_0']!;
      final middle = note.length ~/ 2;
      await t.press('cmd+left');
      final start = cursor();
      expect(start, greaterThan(0));
      expect(start, lessThanOrEqualTo(middle));
      await t.press('cmd+right');
      final end = cursor();
      expect(end, greaterThanOrEqualTo(middle));
      expect(end, lessThan(note.length));
      // Typed there, it lands before the row's last character.
      await t.type('X');
      expect(kept!.answers['question_0']!.own, endsWith(note.substring(end)));
      expect(kept!.answers['question_0']!.own.substring(end, end + 1), 'X');
      await t.press('backspace');
      expect(kept!.answers['question_0']!.own, note);
    });

    // CTUI-174: a Note typed until its third row pushes the question's
    // text out above; the editor, built anew in another place, keeps its
    // focus and draws every row, the cursor's included.
    testWidgets('CTUI-174: a typed Note draws all its rows at $size', (
      t,
    ) async {
      const note =
          'alpha bravo charlie delta echo foxtrot golf hotel india juliet '
          'kilo lima mike november oscar papa quebec romeo sierra tango '
          'uniform victor whiskey';
      AskState? kept;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final wait = _asked(claudeQuestionsForm);
      await t.pumpWidget(
        Column(
          children: [
            QuestionBox(
              wait: wait,
              questions: wait.questions!,
              agent: 'fake',
              windowRows: size.height,
              held: false,
              between: false,
              attendKey: 'ctrl+x a',
              focusNode: focus,
              filled: const AskState(step: 0, row: 0, answers: {}),
              onFill: (state) => kept = state,
              now: () => 0,
              onAnswer: (_) {},
            ),
          ],
        ),
        size: size,
      );
      focus.requestFocus();
      await t.pump();
      await t.press('down down');
      await t.type(note);
      expect(kept!.answers['question_0']!.own, note);
      final c = _noteController(t);
      final layout = c.lastLayout!;
      final top = t.screen.lines.indexWhere((l) => l.contains('❯ Note  '));
      for (final (i, row) in layout.shownRows.indexed) {
        expect(t.screen.lines[top + i], contains(row.text.trimRight()));
      }
      expect(layout.cursorRow - layout.rowOffset, layout.height - 1);
      expect(
        t.screen.lines[top + layout.height - 1],
        contains(note.substring(note.length - 5)),
      );
      expect(t.screen.buffer.cursor?.y, top + layout.height - 1);
    });
  }
}
