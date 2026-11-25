import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

bool Function(KeyEvent) normalEditor(TextAreaController c) {
  var state = const VimState(mode: VimMode.normal);
  return (event) {
    if (state.mode == VimMode.insert) {
      if (event.key != 'escape') return false;
      final step = vimEscape(state, (text: c.text, cursor: c.cursor));
      c.endUndoGroup();
      state = step.state;
      if (step.value case final value?) c.cursor = value.cursor;
      return true;
    }
    final key = vimKeyOf(event);
    if (key == null) return false;
    final step = vimStep(state, (text: c.text, cursor: c.cursor), key);
    if (!step.taken) return false;
    if (step.state.mode == VimMode.insert) c.beginUndoGroup();
    if (step.undo) {
      c.undo();
    } else if (step.value case final value?) {
      c.replace(value.text, value.cursor);
    }
    state = step.state;
    return true;
  };
}

void main() {
  group('tester: vim controller integration', () {
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'Unicode deletion and insert group undo through the area $size',
        (t) async {
          final c = TextAreaController(text: '界👩‍💻é')..cursor = 2;
          addTearDown(c.dispose);
          await t.pumpWidget(
            Column(
              children: [
                TextArea(
                  controller: c,
                  autofocus: true,
                  onKey: normalEditor(c),
                ),
              ],
            ),
            size: size,
          );
          await t.press('x');
          expect(c.text, '界👩‍💻');
          await t.press('i');
          await t.paste('é');
          expect(c.text, '界é👩‍💻');
          await t.press('esc u');
          expect(c.text, '界👩‍💻');
          await t.press('u');
          expect((c.text, c.cursor), ('界👩‍💻é', 2));
          await t.resize(const Size(1, 1));
          await t.resize(const Size(0, 0));
          await t.press('x');
          expect(c.text, '界👩‍💻');
          await t.resize(size);
          expect(t.screen.text, contains('界👩‍💻'));
        },
      );

      testWidgets('focus and removal bound normal-mode dispatch $size', (
        t,
      ) async {
        final c = TextAreaController(text: 'abc')..cursor = 0;
        final other = TextAreaController();
        final focus = FocusNode(), elsewhere = FocusNode();
        addTearDown(c.dispose);
        addTearDown(other.dispose);
        addTearDown(focus.dispose);
        addTearDown(elsewhere.dispose);
        await t.pumpWidget(
          Column(
            children: [
              TextArea(
                controller: c,
                focusNode: focus,
                autofocus: true,
                onKey: normalEditor(c),
              ),
              TextArea(controller: other, focusNode: elsewhere),
            ],
          ),
          size: size,
        );
        elsewhere.requestFocus();
        await t.press('x');
        expect((c.text, other.text), ('abc', 'x'));
        focus.requestFocus();
        await t.press('x');
        expect(c.text, 'bc');
        await t.pumpWidget(Text('removed'), size: size);
        await t.press('x');
        expect(c.text, 'bc');
      });

      testWidgets('thousand insert events between frames form one undo $size', (
        t,
      ) async {
        final c = TextAreaController(text: 'a')..cursor = 0;
        addTearDown(c.dispose);
        await t.pumpWidget(
          TextArea(controller: c, autofocus: true, onKey: normalEditor(c)),
          size: size,
        );
        await t.press('i');
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(const KeyEvent('x'));
        }
        await t.pump();
        expect(c.text, '${'x' * 1000}a');
        await t.press('esc u');
        expect(c.text, 'a');
        await t.press('ctrl+y');
        expect(c.text, '${'x' * 1000}a');
      });
    }
  });
}
