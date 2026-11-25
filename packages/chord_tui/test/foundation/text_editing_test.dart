import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// [text] with the cursor at [cursor], counting its notifications in
/// [notes].
(TextAreaController, List<int>) _area(String text, [int? cursor]) {
  final c = TextAreaController(text: text);
  if (cursor != null) c.cursor = cursor;
  final notes = [0];
  c.addListener(() => notes[0]++);
  return (c, notes);
}

/// Where repeated [move]s from [from] land, until the cursor stops.
List<int> _stops(
  String text,
  int from,
  void Function(TextAreaController) move,
) {
  final (c, _) = _area(text, from);
  final stops = [from];
  for (;;) {
    move(c);
    if (c.cursor == stops.last) return stops;
    stops.add(c.cursor);
  }
}

void main() {
  _testerControllerCases();
  group('TextAreaController', () {
    group('normalizes line breaks', () {
      test('in the constructor, the text setter and insert', () {
        expect(TextAreaController(text: 'a\r\nb\rc').text, 'a\nb\nc');
        final (c, _) = _area('');
        c.text = 'x\r\ny';
        expect(c.text, 'x\ny');
        c.insert('\r\n1\r2');
        expect(c.text, 'x\ny\n1\n2');
        expect(c.cursor, 7);
      });

      test('counting one grapheme per break', () {
        final c = TextAreaController(text: 'a\r\nb');
        expect(c.length, 3);
        expect(c.cursor, 3);
      });
    });

    group('notifies', () {
      test('once per change, the cursor already settled', () {
        final (c, notes) = _area('ab');
        final seen = <int>[];
        c.addListener(() => seen.add(c.cursor));
        c.insert('cd');
        c.backspace();
        c.moveWordLeft();
        c.newline();
        expect(notes.single, 4);
        expect(seen, [4, 3, 0, 1]);
      });

      test('never for a change that changes nothing', () {
        final (c, notes) = _area('one\ntwo', 0);
        c
          ..moveLeft()
          ..moveWordLeft()
          ..moveToLineStart()
          ..deleteToLineStart()
          ..deleteBefore(0)
          ..deleteBefore(3)
          ..deleteWordBefore()
          ..backspace();
        expect(c.continueLine(), isFalse);
        c.cursor = 7;
        notes[0] = 0;
        c
          ..moveRight()
          ..moveWordRight()
          ..moveToLineEnd()
          ..deleteToLineEnd()
          ..delete()
          ..text = 'one\ntwo'
          ..text = 'one\r\ntwo';
        expect(notes.single, 0);
      });

      test('when text equal to its own is set with the cursor elsewhere', () {
        final (c, notes) = _area('ab', 0);
        c.text = 'ab';
        expect(c.cursor, 2);
        expect(notes.single, 1);
      });
    });

    group('moves by word as OpenTUI does', () {
      final table = <(String, List<int>, List<int>)>[
        ('one two', [0, 4, 7], [7, 4, 0]),
        ('one.two', [0, 4, 7], [7, 4, 0]),
        ('one_two', [0, 7], [7, 0]),
        ('one  two', [0, 4, 8], [8, 5, 4, 0]),
        ('hello, world!', [0, 6, 13], [13, 7, 6, 0]),
        // Measured from the installed OpenTUI edit buffer as well.
        ('a...b', [0, 2, 4, 5], [5, 4, 3, 2, 0]),
        ('a, b', [0, 2, 4], [4, 3, 2, 0]),
        (' lead', [0, 5], [5, 1, 0]),
        (r'ab\cd', [0, 3, 5], [5, 3, 0]),
        ('one\ntwo', [0, 4, 7], [7, 3, 0]),
        ('one \ntwo', [0, 4, 5, 8], [8, 4, 0]),
        ('x\n\ny', [0, 2, 3, 4], [4, 2, 1, 0]),
        ('a  \n  b', [0, 2, 4, 6, 7], [7, 6, 5, 3, 2, 0]),
      ];
      for (final (text, right, left) in table) {
        test('in "$text"', () {
          expect(_stops(text, 0, (c) => c.moveWordRight()), right);
          expect(_stops(text, text.length, (c) => c.moveWordLeft()), left);
        });
      }

      test('stopping at a line break', () {
        final (c, _) = _area('one\ntwo', 0);
        c.moveWordRight();
        expect(c.cursor, 4);
        c.cursor = 3;
        c.moveWordRight();
        expect(c.cursor, 4);
        c.moveWordLeft();
        c.moveWordLeft();
        expect(c.cursor, 0);
        for (final from in [4, 5, 6, 7]) {
          c.cursor = from;
          c.moveWordLeft();
          expect(c.cursor, 3, reason: 'from $from');
        }
      });

      test('taking text beyond ASCII as words, whole graphemes', () {
        // 界面 and an accented e and a joined emoji are word graphemes.
        const text = '界面 é👩‍💻 x';
        expect(text.characters.length, 7);
        expect(_stops(text, 0, (c) => c.moveWordRight()), [0, 3, 6, 7]);
        expect(_stops(text, 7, (c) => c.moveWordLeft()), [7, 6, 3, 0]);
      });
    });

    group('deletes by word', () {
      test('back to where a word move left lands', () {
        final (c, _) = _area('hello, world!');
        c.deleteWordBefore();
        expect(c.text, 'hello, ');
        c.deleteWordBefore();
        expect(c.text, 'hello,');
        c.cursor = 3;
        c.deleteWordBefore();
        expect(c.text, 'lo,');
        expect(c.cursor, 0);
      });

      test('over a line break as the move does', () {
        final (c, _) = _area('one\ntwo');
        c.deleteWordBefore();
        expect(c.text, 'one');
      });

      test('leaving the base controller\'s rule as it was', () {
        final base = TextEditingController(text: 'hello, world!');
        base.deleteWordBefore();
        expect(base.text, 'hello, ');
      });
    });

    group('deleteBefore', () {
      test('deletes up to the count, whole graphemes', () {
        final (c, notes) = _area('ab界é');
        c.deleteBefore(2);
        expect(c.text, 'ab');
        c.deleteBefore(9);
        expect(c.text, '');
        expect(notes.single, 2);
      });

      test('rejects a negative count', () {
        final (c, notes) = _area('ab');
        expect(() => c.deleteBefore(-1), throwsArgumentError);
        expect(c.text, 'ab');
        expect(notes.single, 0);
      });
    });

    group('lines', () {
      test('cursorLine and cursorColumn count from zero', () {
        final (c, _) = _area('ab\n界é\n', 0);
        expect((c.cursorLine, c.cursorColumn), (0, 0));
        c.cursor = 5;
        expect((c.cursorLine, c.cursorColumn), (1, 2));
        c.cursor = 6;
        expect((c.cursorLine, c.cursorColumn), (2, 0));
      });

      test('line start and end are the logical line\'s', () {
        final (c, _) = _area('one\ntwo three\nx', 6);
        c.moveToLineStart();
        expect(c.cursor, 4);
        c.moveToLineEnd();
        expect(c.cursor, 13);
      });

      test('cuts stay inside the line and keep its breaks', () {
        final (c, _) = _area('one\ntwo three\nx', 8);
        c.deleteToLineEnd();
        expect(c.text, 'one\ntwo \nx');
        c.deleteToLineStart();
        expect(c.text, 'one\n\nx');
        expect(c.cursor, 4);
      });

      test('the base controller still cuts the whole buffer', () {
        final base = TextEditingController(text: 'one\ntwo')..cursor = 5;
        base.deleteToStart();
        expect(base.text, 'wo');
        base.deleteToEnd();
        expect(base.text, '');
      });

      test('backspace and delete join lines', () {
        final (c, _) = _area('one\ntwo', 4);
        c.backspace();
        expect(c.text, 'onetwo');
        c.newline();
        c.moveLeft();
        c.delete();
        expect(c.text, 'onetwo');
      });

      test('a final break keeps an empty last line', () {
        final c = TextAreaController(text: 'a\n');
        expect((c.cursorLine, c.cursorColumn), (1, 0));
      });
    });

    group('newline and continueLine', () {
      test('newline breaks mid-line, the cursor on the new line', () {
        final (c, notes) = _area('onetwo', 3);
        c.newline();
        expect(c.text, 'one\ntwo');
        expect((c.cursor, c.cursorLine, c.cursorColumn), (4, 1, 0));
        expect(notes.single, 1);
      });

      test('continueLine turns a backslash before the cursor into a break', () {
        final (c, notes) = _area(r'one\two', 4);
        expect(c.continueLine(), isTrue);
        expect(c.text, 'one\ntwo');
        expect((c.cursor, c.cursorLine, c.cursorColumn), (4, 1, 0));
        expect(notes.single, 1);
      });

      test('continueLine changes nothing without a backslash right before', () {
        final (c, notes) = _area(r'one\ two', 5);
        expect(c.continueLine(), isFalse);
        c.cursor = 0;
        notes[0] = 0;
        expect(c.continueLine(), isFalse);
        expect(c.text, r'one\ two');
        expect(notes.single, 0);
      });
    });

    group('keeps whole graphemes across edits', () {
      test('a combining mark typed after a letter joins it', () {
        final (c, notes) = _area('e');
        c.insert('\u0301');
        expect((c.text, c.length, c.cursor), ('e\u0301', 1, 1));
        expect(notes.single, 1);
        c.backspace();
        expect(c.text, '');
      });

      test('a joiner and its emoji compose into one grapheme', () {
        final (c, _) = _area('👩');
        c.insert('\u200d');
        c.insert('💻');
        expect((c.length, c.cursor), (1, 1));
        c.moveLeft();
        expect(c.cursor, 0);
      });

      test('regional indicators pair as they arrive', () {
        final (c, _) = _area('\u{1F1FA}');
        c.insert('\u{1F1E6}');
        expect((c.length, c.cursor), (1, 1));
        c.cursor = 0;
        c.insert('\u{1F1E9}');
        // The new indicator pairs with the first; the second is left alone.
        expect(c.text.characters.toList(), ['\u{1F1E9}\u{1F1FA}', '\u{1F1E6}']);
        expect((c.length, c.cursor), (2, 1));
      });

      test('deleting what parts two graphemes joins them', () {
        // A mark after a break stands alone; with the break gone it joins.
        final (c, notes) = _area('a\n\u0301', 1);
        expect(c.length, 3);
        c.delete();
        expect((c.text, c.length, c.cursor), ('a\u0301', 1, 1));
        expect(notes.single, 1);
        // A word cut over the break too, the cursor at the joined end.
        final (d, _) = _area('e\n\u0301', 2);
        d.deleteWordBefore();
        expect((d.text, d.length, d.cursor), ('e\u0301', 1, 1));
      });

      test('a cursor inside a joined grapheme moves to its end', () {
        final (c, _) = _area('e\n\u0301', 2);
        c.backspace();
        expect((c.text, c.cursor), ('e\u0301', 1));
      });
    });

    test('moves by grapheme over a break', () {
      final (c, _) = _area('a\n界', 1);
      c.moveRight();
      expect(c.cursor, 2);
      c.moveRight();
      expect(c.cursor, 3);
      c
        ..moveLeft()
        ..moveLeft();
      expect(c.cursor, 1);
    });

    test('assigning the cursor clamps it', () {
      final (c, _) = _area('ab');
      c.cursor = 9;
      expect(c.cursor, 2);
      c.cursor = -3;
      expect(c.cursor, 0);
    });
  });
}

void _testerControllerCases() {
  group('tester: controller settled edit boundaries', () {
    for (final (label, edit) in <(String, void Function(TextAreaController))>[
      (
        'backspace',
        (c) {
          c.cursor = 2;
          c.backspace();
        },
      ),
      (
        'delete',
        (c) {
          c.cursor = 1;
          c.delete();
        },
      ),
      (
        'deleteBefore',
        (c) {
          c.cursor = 2;
          c.deleteBefore(1);
        },
      ),
      (
        'word deletion',
        (c) {
          c.cursor = 2;
          c.deleteWordBefore();
        },
      ),
    ]) {
      test('$label joins a split emoji before notifying', () {
        final c = TextAreaController(text: '👩\u200d\n💻!');
        final seen = <(String, int, int)>[];
        c.addListener(() {
          expect(c.length, c.text.characters.length);
          expect(c.beforeCursor + c.afterCursor, c.text);
          expect(c.beforeCursor.characters.length, c.cursor);
          seen.add((c.text, c.length, c.cursor));
        });
        edit(c);
        expect(seen.last, ('👩\u200d💻!', 2, 1));
        expect(seen.where((s) => s.$1 == '👩\u200d💻!'), hasLength(1));
        c.dispose();
      });
    }

    test('inserting between flags repairs every affected cluster', () {
      final c = TextAreaController(text: '🇺🇦🇩🇪')..cursor = 1;
      final seen = <(String, String, int)>[];
      c.addListener(() {
        seen.add((c.beforeCursor, c.afterCursor, c.length));
      });
      c.insert('\u{1F1EB}');
      expect(c.text.characters.toList(), [
        '🇺🇦',
        '\u{1F1EB}\u{1F1E9}',
        '\u{1F1EA}',
      ]);
      expect(c.cursor, 2);
      expect(seen, [('🇺🇦\u{1F1EB}\u{1F1E9}', '\u{1F1EA}', 3)]);
      c.dispose();
    });

    test(
      'CRLF payload inserted mid-line settles once with trailing empty line',
      () {
        final c = TextAreaController(text: '界tail')..cursor = 1;
        final seen = <(String, int, int, int)>[];
        c.addListener(
          () => seen.add((c.text, c.cursor, c.cursorLine, c.cursorColumn)),
        );
        c.insert('e\u0301\r\n👩‍💻\r');
        expect(seen, [('界e\u0301\n👩‍💻\ntail', 5, 2, 0)]);
        c.text = '界e\u0301\r\n👩‍💻\r';
        expect((c.cursorLine, c.cursorColumn), (2, 0));
        expect(seen, hasLength(2));
        c.dispose();
      },
    );

    test('continued carries the original later-line and EOF cases', () {
      for (final (source, cursor, expected, line) in [
        ('one \\', 5, 'one \n', 1),
        ('a\nb\\c', 4, 'a\nb\nc', 2),
      ]) {
        final c = TextAreaController(text: source)..cursor = cursor;
        var notes = 0;
        c.addListener(() => notes++);
        expect(c.continueLine(), isTrue);
        expect((c.text, c.cursorLine, c.cursorColumn), (expected, line, 0));
        expect(notes, 1);
        c.dispose();
      }
      for (final (source, cursor) in [
        ('one', 3),
        ('a \\ b', 5),
        ('\\', 0),
        ('', 0),
      ]) {
        final c = TextAreaController(text: source)..cursor = cursor;
        var notes = 0;
        c.addListener(() => notes++);
        expect(c.continueLine(), isFalse);
        expect((c.text, c.cursor, notes), (source, cursor, 0));
        c.dispose();
      }
    });

    test(
      'logical cuts on blank lines join backward and keep the forward break',
      () {
        final c = TextAreaController(text: '界\n\n👩‍💻')..cursor = 2;
        var notes = 0;
        c.addListener(() => notes++);
        c
          ..deleteToLineStart()
          ..deleteToLineEnd()
          ..moveToLineStart()
          ..moveToLineEnd();
        expect((c.text, c.cursor, notes), ('界\n👩‍💻', 1, 3));
        c.delete();
        expect((c.text, c.cursor, notes), ('界👩‍💻', 1, 4));
        c.dispose();
      },
    );

    test('word deletion and movement agree at every Unicode boundary', () {
      const text = '界e\u0301..👩‍💻  🇺🇦\nx_y!';
      final clusters = text.characters.toList();
      for (var cursor = 0; cursor <= clusters.length; cursor++) {
        final moved = TextAreaController(text: text)..cursor = cursor;
        moved.moveWordLeft();
        final c = TextAreaController(text: text)..cursor = cursor;
        c.deleteWordBefore();
        expect(
          c.text,
          clusters.take(moved.cursor).join() + clusters.skip(cursor).join(),
          reason: 'cursor $cursor',
        );
        expect(c.cursor, moved.cursor, reason: 'cursor $cursor');
        c.dispose();
        moved.dispose();
      }
    });

    test(
      'empty no-op edits do not notify and rejected counts preserve state',
      () {
        final c = TextAreaController();
        var notes = 0;
        c.addListener(() => notes++);
        c
          ..insert('')
          ..clear()
          ..delete()
          ..backspace()
          ..deleteBefore(99)
          ..deleteWordBefore()
          ..deleteToStart()
          ..deleteToEnd()
          ..moveWordLeft()
          ..moveWordRight()
          ..moveLeft()
          ..moveRight();
        c.cursor = -1;
        c.text = '';
        expect(() => c.deleteBefore(-1), throwsArgumentError);
        expect((c.text, c.cursor, notes), ('', 0, 0));
        c.dispose();
      },
    );
  });
}
