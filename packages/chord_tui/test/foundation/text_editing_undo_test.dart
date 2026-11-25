import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  test('undo restores whole graphemes and the cursor before an edit', () {
    final c = TextAreaController(text: 'e')..cursor = 1;
    c.insert('\u0301');
    c.undo();
    expect((c.text, c.cursor), ('e', 1));
    c.redo();
    expect((c.text, c.cursor), ('e\u0301', 1));
    c.newline();
    c.insert('界\r\n👩‍💻');
    c.undo();
    expect((c.text, c.cursor), ('e\u0301\n', 2));
    c.undo();
    expect((c.text, c.cursor), ('e\u0301', 1));
  });

  test('cuts undo once, with settled notifications and a restored cursor', () {
    final c = TextAreaController(text: 'one\ntwo')..cursor = 5;
    final seen = <(String, int)>[];
    c.addListener(() => seen.add((c.text, c.cursor)));
    c.deleteToLineEnd();
    c.undo();
    c.redo();
    expect(seen, [('one\nt', 5), ('one\ntwo', 5), ('one\nt', 5)]);
  });

  test('cursor moves and no-op edits keep redo, a new edit drops it', () {
    final c = TextAreaController(text: 'a');
    c.insert('b');
    c.undo();
    c.cursor = 0;
    c.backspace();
    c.insert('');
    c.redo();
    expect((c.text, c.cursor), ('ab', 2));
    c.undo();
    c.insert('x');
    c.redo();
    expect(c.text, 'xa');
  });

  test('vertical moves preserve the cursor from which an edit is undone', () {
    final c = TextAreaController(text: 'ab\ncd');
    c.moveUp(c.layout(width: 10, maxHeight: 3));
    c.backspace();
    c.undo();
    expect((c.text, c.cursor), ('ab\ncd', 2));
  });

  test('replacement and clear reset both stacks even if text is unchanged', () {
    for (final replace in <void Function(TextAreaController)>[
      (c) => c.text = c.text,
      (c) => c.text = 'replacement',
      (c) => c.clear(),
    ]) {
      final c = TextAreaController(text: 'a');
      c.insert('b');
      c.insert('c');
      c.undo();
      replace(c);
      final state = (c.text, c.cursor);
      c.undo();
      c.redo();
      expect((c.text, c.cursor), state);
    }
  });

  test('keeps only the last hundred edits', () {
    final c = TextAreaController();
    for (var i = 0; i < 105; i++) {
      c.insert('x');
    }
    for (var i = 0; i < 105; i++) {
      c.undo();
    }
    expect(c.text, 'xxxxx');
    for (var i = 0; i < 105; i++) {
      c.redo();
    }
    expect(c.text.length, 105);
  });
  group('tester U2 undo edit boundaries', () {
    test('each named edit restores its pre-edit cursor and text', () {
      for (final edit in <void Function(TextAreaController)>[
        (c) => c.insert('界👩‍💻e\u0301\r\n'),
        (c) => c.newline(),
        (c) => c.backspace(),
        (c) => c.delete(),
        (c) => c.deleteBefore(2),
        (c) => c.deleteWordBefore(),
        (c) => c.deleteToLineStart(),
        (c) => c.deleteToLineEnd(),
      ]) {
        final c = TextAreaController(text: 'one two\nend')..cursor = 5;
        final before = (c.text, c.cursor);
        edit(c);
        final after = (c.text, c.cursor);
        expect(after, isNot(before));
        c.undo();
        expect((c.text, c.cursor), before);
        c.undo();
        expect((c.text, c.cursor), before);
        c.redo();
        expect((c.text, c.cursor), after);
        c.redo();
        expect((c.text, c.cursor), after);
        c.dispose();
      }
    });

    test('continuation and grapheme joins are one reversible edit each', () {
      final c = TextAreaController(text: 'a\\z')..cursor = 2;
      addTearDown(c.dispose);
      expect(c.continueLine(), isTrue);
      expect((c.text, c.cursor), ('a\nz', 2));
      c.undo();
      expect((c.text, c.cursor), ('a\\z', 2));
      c.redo();
      expect((c.text, c.cursor), ('a\nz', 2));
      c.text = '👩\n‍💻';
      c.cursor = 2;
      final before = (c.text, c.cursor);
      c.backspace();
      expect((c.text, c.cursor), ('👩‍💻', 1));
      c.undo();
      expect((c.text, c.cursor), before);
      c.redo();
      expect((c.text, c.cursor), ('👩‍💻', 1));
    });

    test('empty history and no-op edits neither notify nor discard redo', () {
      final c = TextAreaController();
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);
      c.undo();
      c.redo();
      expect(notifications, 0);
      c.insert('x');
      c.undo();
      final count = notifications;
      c.backspace();
      c.delete();
      c.deleteBefore(0);
      c.deleteWordBefore();
      c.deleteToLineStart();
      c.deleteToLineEnd();
      c.insert('');
      expect(c.continueLine(), isFalse);
      c.cursor = 0;
      expect(notifications, count);
      c.redo();
      expect((c.text, c.cursor), ('x', 1));
      expect(notifications, count + 1);
    });

    test('a thousand edits retain exactly one hundred reversible steps', () {
      final c = TextAreaController();
      addTearDown(c.dispose);
      for (var i = 0; i < 1000; i++) {
        c.insert('界');
      }
      for (var i = 0; i < 101; i++) {
        c.undo();
      }
      expect((c.length, c.cursor), (900, 900));
      c.insert('🙂');
      final branched = c.text;
      c.redo();
      expect(c.text, branched);
      c.undo();
      expect((c.length, c.cursor), (900, 900));
    });
  });
}
