// Undo groups and whole-value edits on TextAreaController, which vim's
// normal mode undoes by: one command one step, an insert session one step.
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const fox = 'the quick brown fox';

/// [key] played on [c] in normal mode, its value put in as one edit.
VimState press(TextAreaController c, VimState state, String key) {
  final step = vimStep(state, (text: c.text, cursor: c.cursor), key);
  if (step.undo) {
    c.undo();
  } else if (step.value case final value?) {
    c.replace(value.text, value.cursor);
  }
  return step.state;
}

void main() {
  test('edits in a group undo as one; an empty group adds no step', () {
    final c = TextAreaController(text: 'a');
    c.beginUndoGroup();
    c.insert('b');
    c.insert('c');
    c.endUndoGroup();
    c.beginUndoGroup();
    c.endUndoGroup();
    c.insert('d');
    expect(c.text, 'abcd');
    c.undo();
    expect(c.text, 'abc');
    c.undo();
    expect(c.text, 'a');
    c.redo();
    expect(c.text, 'abc');
  });

  test('a replace that changes nothing does not notify', () {
    final c = TextAreaController(text: '界🙂é');
    var heard = 0;
    c.addListener(() => heard++);
    c.replace(c.text, c.cursor);
    expect(heard, 0);
    c.replace(c.text, 0);
    expect(heard, 1);
  });

  test('replace is one edit that undo takes back, the cursor with it', () {
    final c = TextAreaController(text: fox)..cursor = 4;
    c.replace('the brown fox', 4);
    expect((c.text, c.cursor), ('the brown fox', 4));
    c.undo();
    expect((c.text, c.cursor), (fox, 4));
  });

  test('u undoes one change at a time, back to the start', () {
    final c = TextAreaController(text: fox)..cursor = 4;
    var state = const VimState(mode: VimMode.normal);
    for (final key in ['d', 'w', 'x']) {
      state = press(c, state, key);
    }
    expect(c.text, 'the rown fox');
    state = press(c, state, 'u');
    expect(c.text, 'the brown fox');
    state = press(c, state, 'u');
    expect((c.text, c.cursor), (fox, 4));
    press(c, state, 'u');
    expect(c.text, fox);
  });

  test('what insert mode typed is one undo after Esc, as ctrl+z undoes it', () {
    final c = TextAreaController(text: fox)..cursor = 18;
    var state = const VimState(mode: VimMode.normal);
    // The group begins before the step that enters insert mode.
    c.beginUndoGroup();
    state = press(c, state, 'A');
    expect(state.mode, VimMode.insert);
    for (final char in ' jumps'.split('')) {
      c.insert(char);
    }
    final left = vimEscape(state, (text: c.text, cursor: c.cursor));
    c.endUndoGroup();
    c.cursor = left.value!.cursor;
    expect(c.cursor, 24);
    press(c, left.state, 'u');
    expect(c.text, fox);
  });
}
