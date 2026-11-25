import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// The draft of the CTUI-164 captures, the cursor before ` zeta`.
const _draft = 'alpha beta gamma\ndelta epsilon zeta';

/// [text] with the cursor at [cursor], counting its notifications in
/// [notes].
(TextAreaController, List<int>) _area(String text, [int? cursor]) {
  final c = TextAreaController(text: text);
  if (cursor != null) c.cursor = cursor;
  final notes = [0];
  c.addListener(() => notes[0]++);
  return (c, notes);
}

/// The text with `|` typed at the cursor, as the captures show it.
String _typed(TextAreaController c) => (c..insert('|')).text;

TextAreaLayout _wide(TextAreaController c) =>
    c.layout(width: 120, maxHeight: 10);

void main() {
  _testerSelectionCases();
  group('line edges step as OpenTUI does', () {
    test('line start at a line\'s start goes to the previous line\'s end', () {
      final (c, _) = _area(_draft, 17);
      c.moveToLineStart();
      expect(_typed(c), 'alpha beta gamma|\ndelta epsilon zeta');
    });

    test('line end at a line\'s end goes to the next line\'s start', () {
      final (c, _) = _area(_draft, 16);
      c.moveToLineEnd();
      expect(_typed(c), 'alpha beta gamma\n|delta epsilon zeta');
    });

    test('delete to line start at a line\'s start joins the lines', () {
      final (c, _) = _area(_draft, 17);
      c.deleteToLineStart();
      expect(_typed(c), 'alpha beta gamma|delta epsilon zeta');
    });

    test('delete to line end at a line\'s end deletes nothing', () {
      final (c, notes) = _area(_draft, 16);
      c.deleteToLineEnd();
      expect((c.text, c.cursor, notes.single), (_draft, 16, 0));
    });

    test('at the text\'s ends they stay', () {
      final (c, notes) = _area(_draft, 0);
      c
        ..moveToLineStart()
        ..deleteToLineStart();
      c.cursor = _draft.length;
      notes[0] = 0;
      c.moveToLineEnd();
      expect((c.text, c.cursor, notes.single), (_draft, _draft.length, 0));
    });

    test('mid-line they keep to the line, as before', () {
      final (c, _) = _area(_draft, 30);
      c.moveToLineStart();
      expect(c.cursor, 17);
      c.cursor = 20;
      c.moveToLineEnd();
      expect(c.cursor, 35);
    });

    test('row moves with no layout keep to the line and never step', () {
      final (c, notes) = _area(_draft, 17);
      c.moveToRowStart(null);
      c.cursor = 16;
      notes[0] = 0;
      c.moveToRowEnd(null);
      expect((c.cursor, notes.single), (16, 0));
      c.cursor = 20;
      c.moveToRowStart(null);
      expect(c.cursor, 17);
      c.moveToRowEnd(null);
      expect(c.cursor, 35);
    });
  });

  group('new moves and deletes', () {
    test('moveToStart and moveToEnd go to the text\'s ends', () {
      final (c, _) = _area(_draft, 30);
      c.moveToStart();
      expect(c.cursor, 0);
      c.moveToEnd();
      expect(c.cursor, 35);
    });

    test('deleteWordAfter deletes to where moveWordRight lands', () {
      final (c, _) = _area('one two.three', 0);
      c.deleteWordAfter();
      expect(_typed(c), '|two.three');
      final (d, _) = _area('abc   def', 3);
      d.deleteWordAfter();
      expect(_typed(d), 'abc| def');
    });

    test('deleteWordAfter takes a line break on the way', () {
      final (c, _) = _area('$_draft\nomega', 30);
      c.deleteWordAfter();
      expect(_typed(c), 'alpha beta gamma\ndelta epsilon|omega');
      final (d, _) = _area(_draft, 16);
      d.deleteWordAfter();
      expect(_typed(d), 'alpha beta gamma|delta epsilon zeta');
    });

    test('deleteWordAfter at the end deletes nothing', () {
      final (c, notes) = _area(_draft);
      c.deleteWordAfter();
      expect((c.text, notes.single), (_draft, 0));
    });

    test('deleteLine takes the break after, as OpenTUI does', () {
      final (c, _) = _area('$_draft\nomega', 30);
      c.deleteLine();
      expect(_typed(c), 'alpha beta gamma\n|omega');
    });

    test('deleteLine on the last line takes the break before', () {
      final (c, _) = _area('$_draft\nomega', 39);
      c.deleteLine();
      expect(_typed(c), 'alpha beta gamma\ndelta epsilon zeta|');
    });

    test('deleteLine on the only line leaves the text empty', () {
      final (c, notes) = _area('alpha', 2);
      c.deleteLine();
      expect((_typed(c), notes.single), ('|', 2));
      final (e, n) = _area('');
      e.deleteLine();
      expect((e.text, n.single), ('', 0));
    });

    test('deleteLine on an empty line between two', () {
      final (c, _) = _area('a\n\nb', 2);
      c.deleteLine();
      expect(_typed(c), 'a\n|b');
    });
  });

  group('TextSelection', () {
    test('start and end order the ends', () {
      const s = TextSelection(baseOffset: 5, extentOffset: 2);
      expect((s.start, s.end, s.isCollapsed), (2, 5, false));
      const c = TextSelection.collapsed(offset: 3);
      expect((c.baseOffset, c.extentOffset, c.isCollapsed), (3, 3, true));
      expect(c, const TextSelection(baseOffset: 3, extentOffset: 3));
    });
  });

  group('selection', () {
    test('is collapsed at the cursor when nothing is selected', () {
      final (c, _) = _area(_draft, 30);
      expect(c.selection, const TextSelection.collapsed(offset: 30));
      expect((c.hasSelection, c.selectedText), (false, ''));
    });

    test('selectAll selects the text, the cursor at its end', () {
      final (c, notes) = _area(_draft, 30);
      c.selectAll();
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 35));
      expect((c.cursor, c.selectedText, notes.single), (35, _draft, 1));
      c.selectAll();
      expect(notes.single, 1);
    });

    test('selectAll on no text selects nothing and does not notify', () {
      final (c, notes) = _area('');
      c.selectAll();
      expect((c.hasSelection, notes.single), (false, 0));
    });

    test('setting it clamps both ends and puts the cursor at the extent', () {
      final (c, notes) = _area('abc', 0);
      c.selection = const TextSelection(baseOffset: 9, extentOffset: -1);
      expect(c.selection, const TextSelection(baseOffset: 3, extentOffset: 0));
      expect((c.cursor, c.selectedText, notes.single), (0, 'abc', 1));
    });

    test('setting the cursor collapses it, even at the same offset', () {
      final (c, notes) = _area(_draft);
      c.selectAll();
      c.cursor = 35;
      expect((c.hasSelection, c.cursor, notes.single), (false, 35, 2));
    });

    test('setting the text or replacing it collapses it', () {
      final (c, _) = _area(_draft);
      c
        ..selectAll()
        ..text = _draft;
      expect(c.hasSelection, isFalse);
      c
        ..selectAll()
        ..replace(_draft, 35);
      expect(c.hasSelection, isFalse);
    });

    test('selecting moves extend from the cursor, leaving the base', () {
      final (c, notes) = _area(_draft, 30);
      c.moveLeft(select: true);
      c.moveWordLeft(select: true);
      expect(
        c.selection,
        const TextSelection(baseOffset: 30, extentOffset: 23),
      );
      expect(c.selectedText, 'epsilon');
      c.moveToLineEnd(select: true);
      expect(
        c.selection,
        const TextSelection(baseOffset: 30, extentOffset: 35),
      );
      c.moveToStart(select: true);
      expect(c.selection.start, 0);
      c.moveToEnd(select: true);
      c.moveWordRight(select: true);
      c.moveRight(select: true);
      expect(c.selectedText, ' zeta');
      expect(notes.single, 5);
    });

    test('line and row selections take the same steps', () {
      final (c, _) = _area(_draft, 17);
      c.moveToLineStart(select: true);
      expect(
        c.selection,
        const TextSelection(baseOffset: 17, extentOffset: 16),
      );
      final (d, _) = _area(_draft, 20);
      d.moveToRowStart(_wide(d), select: true);
      expect(d.selectedText, 'del');
      d.moveToRowEnd(_wide(d), select: true);
      expect(d.selectedText, 'ta epsilon zeta');
    });

    test('a selection back at its base is no selection', () {
      final (c, _) = _area(_draft, 30);
      c
        ..moveLeft(select: true)
        ..moveRight(select: true);
      expect(c.hasSelection, isFalse);
      expect(c.cursor, 30);
    });

    test('vertical selection keeps the goal column', () {
      final (c, _) = _area('abcdef\nab\nabcdef', 5);
      expect(
        c.moveDown(c.layout(width: 20, maxHeight: 9), select: true),
        isTrue,
      );
      expect(c.cursor, 9);
      expect(
        c.moveDown(c.layout(width: 20, maxHeight: 9), select: true),
        isTrue,
      );
      expect(c.selection, const TextSelection(baseOffset: 5, extentOffset: 15));
    });

    test('vertical selection at an edge changes nothing', () {
      final (c, notes) = _area(_draft, 3);
      c.moveRight(select: true);
      notes[0] = 0;
      expect(c.moveUp(_wide(c), select: true), isFalse);
      expect(c.selection, const TextSelection(baseOffset: 3, extentOffset: 4));
      expect(notes.single, 0);
    });

    test('selecting alone adds no undo step', () {
      final c = TextAreaController();
      for (final g in 'ab'.split('')) {
        c.insert(g);
      }
      c.selectAll();
      c.undo();
      expect((c.text, c.hasSelection), ('a', false));
    });

    test('undo and redo with nothing to restore still collapse it', () {
      for (final restore in <void Function(TextAreaController)>[
        (c) => c.undo(),
        (c) => c.redo(),
      ]) {
        final (c, notes) = _area('abc');
        c.selectAll();
        restore(c);
        expect((c.text, c.cursor, c.hasSelection), ('abc', 3, false));
        expect(notes.single, 2);
        restore(c);
        expect(notes.single, 2);
        expect(_typed(c), 'abc|');
      }
    });

    test('replacing a selection is one undo step', () {
      final (c, _) = _area(_draft, 30);
      c
        ..moveWordLeft(select: true)
        ..insert('x');
      expect(c.text, 'alpha beta gamma\ndelta x zeta');
      c.undo();
      expect((c.text, c.cursor, c.hasSelection), (_draft, 23, false));
      c.redo();
      expect(c.text, 'alpha beta gamma\ndelta x zeta');
    });

    test('deleteBefore deletes the selection only', () {
      final (c, _) = _area(_draft, 30);
      c
        ..moveLeft(select: true)
        ..deleteBefore(5);
      expect(_typed(c), 'alpha beta gamma\ndelta epsilo| zeta');
    });

    test('an empty insert keeps the selection', () {
      final (c, notes) = _area(_draft);
      c
        ..selectAll()
        ..insert('');
      expect((c.hasSelection, notes.single), (true, 1));
    });

    test('continueLine collapses before it breaks the line', () {
      final (c, _) = _area(r'a\', 2);
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      expect(c.continueLine(), isTrue);
      expect((c.text, c.hasSelection), ('a\n', false));
    });
  });

  group('after selecting all, as the original\'s capture', () {
    // original-select-all-edits.txt: cmd+a, the key, then '|' typed.
    final cases = <String, void Function(TextAreaController)>{
      'backspace': (c) => c.backspace(),
      'delete': (c) => c.delete(),
      'ctrl+w': (c) => c.deleteWordBefore(),
      'alt+d': (c) => c.deleteWordAfter(),
      'paste': (c) => c.insert('PASTED'),
      'super+a again': (c) => c.selectAll(),
    };
    final shown = <String, String>{
      'backspace': '|',
      'delete': '|',
      'ctrl+w': '|',
      'alt+d': '|',
      'paste': 'PASTED|',
      'super+a again': '|',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('$key replaces or deletes the selection', () {
        final (c, _) = _area(_draft, 30);
        c.selectAll();
        value(c);
        expect(_typed(c), shown[key]);
      });
    }

    final moves = <String, (void Function(TextAreaController), String)>{
      'left': ((c) => c.moveLeft(), '|$_draft'),
      'alt+left': ((c) => c.moveWordLeft(), '|$_draft'),
      'ctrl+a': ((c) => c.moveToLineStart(), '|$_draft'),
      'super+left': ((c) => c.moveToRowStart(_wide(c)), '|$_draft'),
      'home': ((c) => c.moveToStart(), '|$_draft'),
      'right': ((c) => c.moveRight(), '$_draft|'),
      'alt+right': ((c) => c.moveWordRight(), '$_draft|'),
      'ctrl+e': ((c) => c.moveToLineEnd(), '$_draft|'),
      'super+right': ((c) => c.moveToRowEnd(_wide(c)), '$_draft|'),
      'end': ((c) => c.moveToEnd(), '$_draft|'),
      'up': (
        (c) => c.moveUp(_wide(c)),
        'alpha beta gamma|\ndelta epsilon zeta',
      ),
      'shift+enter': ((c) => c.newline(), '$_draft\n|'),
      'ctrl+u': ((c) => c.deleteToLineStart(), 'alpha beta gamma\n|'),
      'ctrl+k': ((c) => c.deleteToLineEnd(), '|'),
      'ctrl+shift+d': ((c) => c.deleteLine(), 'alpha beta gamma|'),
    };
    for (final MapEntry(:key, value: (move, expected)) in moves.entries) {
      test('$key acts as the original does', () {
        final (c, _) = _area(_draft, 30);
        c.selectAll();
        move(c);
        expect(_typed(c), expected);
      });
    }

    test('ctrl+k deleting nothing keeps the selection, unnotified', () {
      final (c, notes) = _area(_draft);
      c.selectAll();
      c.deleteToLineEnd();
      expect((c.hasSelection, notes.single), (true, 1));
    });

    test('down on the last row collapses and reports the edge', () {
      final (c, notes) = _area(_draft);
      c.selectAll();
      expect(c.moveDown(_wide(c)), isFalse);
      expect((c.hasSelection, c.cursor, notes.single), (false, 35, 2));
    });

    test('ctrl+z collapses and undoes the last edit', () {
      final c = TextAreaController();
      for (final g in _draft.split('')) {
        c.insert(g);
      }
      c.cursor = 30;
      c.selectAll();
      c.undo();
      expect(_typed(c), 'alpha beta gamma\ndelta epsilon zet|');
    });
  });
}

void _testerSelectionCases() {
  group('tester CTUI-164: selection boundaries', () {
    const source = '界e\u0301👩‍💻🇺🇦\n\n\x1b[31mZ\x1b[0m';

    test('character selection keeps whole graphemes at every boundary', () {
      final clusters = source.characters.toList();
      final c = TextAreaController(text: source);
      addTearDown(c.dispose);
      for (var at = 0; at <= clusters.length; at++) {
        c.cursor = at;
        c.moveLeft(select: true);
        expect(c.selection.baseOffset, at);
        expect(c.selectedText, at == 0 ? '' : clusters[at - 1]);
        c.cursor = at;
        c.moveRight(select: true);
        expect(c.selection.baseOffset, at);
        expect(c.selectedText, at == clusters.length ? '' : clusters[at]);
        expect(c.text, source);
      }
    });

    for (final (name, erase) in <(String, void Function(TextAreaController))>[
      ('backspace', (c) => c.backspace()),
      ('delete', (c) => c.delete()),
      ('word before', (c) => c.deleteWordBefore()),
      ('word after', (c) => c.deleteWordAfter()),
      ('delete before zero', (c) => c.deleteBefore(0)),
    ]) {
      test('$name cuts only the selected grapheme in either direction', () {
        final clusters = source.characters.toList();
        for (var at = 0; at < clusters.length; at++) {
          for (final reversed in [false, true]) {
            final c = TextAreaController(text: source);
            c.selection = TextSelection(
              baseOffset: reversed ? at + 1 : at,
              extentOffset: reversed ? at : at + 1,
            );
            final seen = <(String, int, bool)>[];
            c.addListener(() => seen.add((c.text, c.cursor, c.hasSelection)));
            erase(c);
            final expected = [
              ...clusters.take(at),
              ...clusters.skip(at + 1),
            ].join();
            expect(c.text, expected, reason: '$name at $at reversed $reversed');
            expect(c.hasSelection, isFalse);
            expect(seen, [(expected, c.cursor, false)]);
            c.undo();
            expect(
              (c.text, c.cursor, c.hasSelection),
              (source, reversed ? at : at + 1, false),
            );
            c.redo();
            expect((c.text, c.hasSelection), (expected, false));
            c.dispose();
          }
        }
      });
    }

    test('replacing a break can join graphemes and notifies settled state', () {
      final c = TextAreaController(text: 'a\n\u0301Z');
      addTearDown(c.dispose);
      c.selection = const TextSelection(baseOffset: 2, extentOffset: 1);
      final seen = <(String, int, String)>[];
      c.addListener(() => seen.add((c.text, c.cursor, c.selectedText)));
      c.insert('\u0300');
      expect((c.text, c.cursor, c.length), ('a\u0300\u0301Z', 1, 2));
      expect(seen, [('a\u0300\u0301Z', 1, '')]);
      c.undo();
      expect((c.text, c.cursor, c.hasSelection), ('a\n\u0301Z', 1, false));
    });

    test('blank-line selecting moves include just the adjacent break', () {
      final c = TextAreaController(text: '界\n\n👩‍💻');
      addTearDown(c.dispose);
      c.cursor = 2;
      c.moveToLineStart(select: true);
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 1));
      expect(c.selectedText, '\n');
      c.cursor = 2;
      c.moveToLineEnd(select: true);
      expect(c.selection, const TextSelection(baseOffset: 2, extentOffset: 3));
      expect(c.selectedText, '\n');
      c.selection = const TextSelection(baseOffset: 3, extentOffset: 2);
      c.deleteToLineEnd();
      expect(c.selection, const TextSelection(baseOffset: 3, extentOffset: 2));
      expect(c.text, '界\n\n👩‍💻');
    });

    for (final (width, height) in [(0, 0), (1, 1), (80, 24), (120, 40)]) {
      test('selection survives layout and resize from $width by $height', () {
        final c = TextAreaController(text: source);
        addTearDown(c.dispose);
        c.selection = TextSelection(baseOffset: c.length, extentOffset: 0);
        final selection = c.selection;
        c.layout(width: width, maxHeight: height);
        c.layout(width: 3, maxHeight: 1);
        expect((c.selection, c.selectedText), (selection, source));
        c.moveRight();
        expect((c.cursor, c.hasSelection), (c.length, false));
      });
    }

    test('a thousand selection changes add no undo step or stale row goal', () {
      final c = TextAreaController(text: '界👩‍💻e\u0301\nxy');
      addTearDown(c.dispose);
      final old = c.layout(width: 120, maxHeight: 40);
      for (var i = 0; i < 1000; i++) {
        c.selection = TextSelection(
          baseOffset: 0,
          extentOffset: i.isEven ? 2 : 3,
        );
      }
      c.layout(width: 1, maxHeight: 1);
      c.moveToRowStart(old, select: true);
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
      c.undo();
      expect(
        (c.text, c.cursor, c.hasSelection),
        ('界👩‍💻e\u0301\nxy', 3, false),
      );
    });
  });
}
