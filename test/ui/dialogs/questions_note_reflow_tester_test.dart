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

FormWait _wait() {
  final [message] = enricherRelay(m1Enrichers).fromAgent({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'elicitation/create',
    'params': {...claudeQuestionsForm, 'sessionId': 's'},
  });
  return FormWait(
    'tester-note',
    claudeQuestionsForm['message'] as String,
    schema: recordOf(claudeQuestionsForm['requestedSchema']),
    questions: questionsOf(recordOf(message['params'])),
  );
}

TextAreaController _controller(WidgetTester t) {
  TextAreaController? found;
  void visit(Element e) {
    if (e.widget case TextArea(:final controller?)) found = controller;
    e.visitChildren(visit);
  }

  visit(t.host.rootElement);
  return found!;
}

void main() {
  group('tester CTUI-174: Note reflow and focus', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'Unicode Note survives growth, resize and complete shrink $size',
        (t) async {
          final wait = _wait();
          final focus = FocusNode();
          addTearDown(focus.dispose);
          AskState? kept;
          await t.pumpWidget(
            LayoutBuilder(
              builder: (_, constraints) => Column(
                children: [
                  QuestionBox(
                    wait: wait,
                    questions: wait.questions!,
                    agent: 'fake',
                    windowRows: constraints.maxHeight,
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
            ),
            size: size,
          );
          focus.requestFocus();
          await t.pump();
          await t.press('down down');
          final note = '界🙂e\u0301 abc ' * 30;
          await t.type(note);
          expect(kept!.answers['question_0']!.own, note);
          for (final next in [const Size(80, 24), const Size(120, 40), size]) {
            await t.resize(next);
            final c = _controller(t);
            final layout = c.lastLayout!;
            final top = t.screen.lines.indexWhere(
              (line) => line.contains('❯ Note'),
            );
            expect(top, greaterThanOrEqualTo(0));
            for (final (i, row) in layout.shownRows.indexed) {
              expect(t.screen.lines[top + i], contains(row.text.trimRight()));
            }
            expect(
              t.screen.buffer.cursor?.y,
              top + layout.cursorRow - layout.rowOffset,
            );
          }
          // Backspaces cross every row-count transition, including the final
          // move back to the full question above an empty Note.
          final count = _controller(t).length;
          for (var i = 0; i < count; i++) {
            await t.press('backspace');
          }
          await t.type('after shrink');
          expect(kept!.answers['question_0']!.own, 'after shrink');
          await t.press('up down');
          await t.type('!');
          expect(kept!.answers['question_0']!.own, 'after shrink!');
          await t.pumpWidget(const SizedBox());
          expect(focus.attached, isFalse);
        },
      );
    }
  });
}
