import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/plan.dart';
import 'package:chord/ui/dialogs/plan_box.dart';
import 'package:chord/ui/dialogs/questions.dart' show AskKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

int _inverseCells(WidgetTester t) {
  var count = 0;
  for (var y = 0; y < t.screen.buffer.height; y++) {
    for (var x = 0; x < t.screen.buffer.width; x++) {
      if (t.screen.styleAt(x, y).isInverse) count++;
    }
  }
  return count;
}

void main() {
  group('tester CTUI-178: end-only Note boundaries', () {
    test('modified backspace removes code points as the original does', () {
      for (final key in const [
        AskKey(backspace: true),
        AskKey(backspace: true, ctrl: true),
        AskKey(backspace: true, shift: true),
        AskKey(backspace: true, meta: true),
        AskKey(backspace: true, superKey: true),
      ]) {
        var state = (row: 2, note: '界👩‍💻e\u0301');
        for (final expected in [
          '界👩‍💻e',
          '界👩‍💻',
          '界👩‍',
          '界👩',
          '界',
          '',
          '',
        ]) {
          state = planNoteKey(state, '', key)!;
          expect(state.note, expected);
        }
      }
    });

    test('paste normalizes whitespace and remains local to the Note row', () {
      const text = '界\t🙂\r\ne\u0301  tail\n';
      for (final agent in PlanAgent.values) {
        final row = planChoices(agent).length;
        expect(
          planPaste(agent, (row: row, note: 'start '), text).note,
          'start 界 🙂 e\u0301 tail ',
        );
        expect(planPaste(agent, openPlanBox, text), openPlanBox);
      }
    });

    for (final size in const [Size(120, 40), Size(80, 24), Size(80, 12)]) {
      testWidgets('one inverse end cell follows focus and wrapping at $size', (
        t,
      ) async {
        final focus = FocusNode(), outside = FocusNode();
        addTearDown(focus.dispose);
        addTearDown(outside.dispose);
        var shape = openPlanShape;
        await t.pumpWidget(
          Column(
            children: [
              PlanBox(
                wait: const PlanWait(
                  'tester',
                  PlanAgent.cursor,
                  toolCallId: 'c',
                ),
                agent: 'fake',
                onAnswer: (_) {},
                windowRows: size.height,
                maxRows: size.height,
                focusNode: focus,
                onShape: (next) => shape = next,
              ),
              Focus(focusNode: outside, child: Text('outside')),
            ],
          ),
          size: size,
        );
        focus.requestFocus();
        await t.press('down down');
        await t.paste('界🙂e\u0301 alpha bravo charlie delta ' * 12);
        expect(shape.state.note, endsWith('delta '));
        expect(_inverseCells(t), 1);
        final note = shape.state.note;
        await t.press('super+a super+z shift+super+z ctrl+a ctrl+e left right');
        expect(shape.state.note, note);
        await t.type('!');
        expect(shape.state.note, '$note!');
        await t.press('up');
        expect(_inverseCells(t), 0);
        await t.press('down');
        expect(_inverseCells(t), 1);
        outside.requestFocus();
        await t.pump();
        expect(_inverseCells(t), 0);
        focus.requestFocus();
        await t.resize(const Size(80, 24));
        expect(_inverseCells(t), 1);
        expect(shape.state.note, '$note!');
      });
    }
  });
}
