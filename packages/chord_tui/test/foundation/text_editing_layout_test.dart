import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// Each row as `line.piece start..end "text"`, with `!` on the last.
List<String> _rowsOf(TextAreaLayout l) => [
  for (final r in l.rows)
    '${r.line}.${r.piece} ${r.start}..${r.end} "${r.text}"${r.last ? "!" : ""}',
];

String _sixLines() => [for (var i = 1; i <= 6; i++) 'line $i'].join('\n');

void main() {
  group('tester CTUI-163: visual row cursor membership', () {
    for (final width in [0, 1, 2, 3, 4, 7, 80, 120]) {
      test('every grapheme offset stays in its shown row at width $width', () {
        for (final text in [
          '',
          '界👩‍💻é\tAB\nZ',
          'ab界é👩‍💻cd\n\nend',
          '\x1b[31mAB\x1b[0m',
          'e\n\u0301',
          'abcdef' * 30,
        ]) {
          final c = TextAreaController(text: text);
          final positions = <int, List<int>>{};
          for (var at = 0; at <= c.length; at++) {
            c.cursor = at;
            final row = c.layout(width: width, maxHeight: 1).cursorRow;
            (positions[row] ??= []).add(at);
          }
          for (final members in positions.values) {
            for (final at in members) {
              c.cursor = at;
              c.moveToRowStart(c.layout(width: width, maxHeight: 0));
              expect(c.cursor, members.first, reason: 'start at $at in $text');
              c.moveToRowStart(c.layout(width: width, maxHeight: 24));
              expect(c.cursor, members.first);
              c.cursor = at;
              c.moveToRowEnd(c.layout(width: width, maxHeight: 40));
              expect(c.cursor, members.last, reason: 'end at $at in $text');
              c.moveToRowEnd(c.layout(width: width, maxHeight: 1));
              expect(c.cursor, members.last);
              expect(c.text, text);
            }
          }
          c.dispose();
        }
      });
    }

    test(
      'a thousand edits and a resize invalidate an earlier layout for both moves',
      () {
        final c = TextAreaController(text: 'old layout');
        final stale = c.layout(width: 80, maxHeight: 24);
        for (var i = 0; i < 1000; i++) {
          c.text = '界👩‍💻é edit $i';
        }
        c.text = 'abcdefghij';
        c.cursor = 5;
        c.layout(width: 4, maxHeight: 1);
        c.moveToRowStart(stale);
        expect(c.cursor, 4);
        c.cursor = 5;
        c.moveToRowEnd(stale);
        expect(c.cursor, 7);
        expect(stale.rows.first.text, 'old layout');
        c.dispose();
      },
    );
  });
  _testerLayoutCases();
  group('TextAreaController.layout', () {
    test('is kept as lastLayout, null before the first', () {
      final c = TextAreaController(text: 'ab');
      expect(c.lastLayout, isNull);
      final l = c.layout(width: 10, maxHeight: 3);
      expect(c.lastLayout, same(l));
      c.insert('c');
      // An edit does not lay out: the last layout stays until the next.
      expect(c.lastLayout, same(l));
    });

    test('gives no text one empty row', () {
      final l = TextAreaController().layout(width: 10, maxHeight: 3);
      expect(_rowsOf(l), ['0.0 0..0 ""!']);
      expect(
        (l.cursorRow, l.cursorColumn, l.height, l.rowOffset),
        (0, 0, 1, 0),
      );
      expect(l.shownRows, l.rows);
    });

    test('wraps by grapheme at the cell, not by word', () {
      final l = TextAreaController(
        text: 'ab cdef g',
      ).layout(width: 4, maxHeight: 9);
      expect(_rowsOf(l), [
        '0.0 0..4 "ab c"',
        '0.1 4..8 "def "',
        '0.2 8..9 "g"!',
      ]);
    });

    test('keeps every space and counts a tab four cells', () {
      final l = (TextAreaController(
        text: 'a\tb   c d',
      )..cursor = 0).layout(width: 5, maxHeight: 9);
      expect(_rowsOf(l), [
        '0.0 0..2 "a\t"',
        '0.1 2..7 "b   c"',
        '0.2 7..9 " d"!',
      ]);
      final c = TextAreaController(text: 'a\tb')..cursor = 2;
      expect(c.layout(width: 9, maxHeight: 1).cursorColumn, 5);
    });

    test('moves a wide grapheme that does not fit to the next row', () {
      final l = (TextAreaController(
        text: 'ab界c',
      )..cursor = 0).layout(width: 3, maxHeight: 9);
      // "界c" fills its row, so an empty row follows for the cursor.
      expect(_rowsOf(l), ['0.0 0..2 "ab"', '0.1 2..4 "界c"', '0.2 4..4 ""!']);
    });

    test('keeps a grapheme wider than the row whole, on its own', () {
      final c = TextAreaController(text: 'a界b')..cursor = 0;
      final l = c.layout(width: 1, maxHeight: 9);
      expect(_rowsOf(l), [
        '0.0 0..1 "a"',
        '0.1 1..2 "界"',
        '0.2 2..3 "b"',
        '0.3 3..3 ""!',
      ]);
      c.cursor = 2;
      final at = c.layout(width: 1, maxHeight: 9);
      expect((at.cursorRow, at.cursorColumn), (2, 0));
    });

    test('keeps combining marks and joined emoji whole', () {
      final l = TextAreaController(
        text: 'é👩‍💻x',
      ).layout(width: 2, maxHeight: 9);
      expect(_rowsOf(l), [
        '0.0 0..1 "é"',
        '0.1 1..2 "👩‍💻"',
        '0.2 2..3 "x"!',
      ]);
    });

    test('puts an offset shared by two rows on the second', () {
      final c = TextAreaController(text: 'abcdef')..cursor = 3;
      final l = c.layout(width: 3, maxHeight: 9);
      expect((l.cursorRow, l.cursorColumn), (1, 0));
    });

    test('gives a line that fills its last row an empty row after it', () {
      final c = TextAreaController(text: 'abc\nxy')..cursor = 3;
      final l = c.layout(width: 3, maxHeight: 9);
      expect(_rowsOf(l), ['0.0 0..3 "abc"', '0.1 3..3 ""', '1.0 4..6 "xy"!']);
      expect((l.cursorRow, l.cursorColumn), (1, 0));
      // Wherever the cursor is.
      for (final at in [0, 2, 5]) {
        c.cursor = at;
        expect(_rowsOf(c.layout(width: 3, maxHeight: 9)), _rowsOf(l));
      }
      // At the end of the text the empty row is the last.
      final end = TextAreaController(
        text: 'abc',
      ).layout(width: 3, maxHeight: 9);
      expect(_rowsOf(end), ['0.0 0..3 "abc"', '0.1 3..3 ""!']);
      expect(end.cursorRow, 1);
    });

    test('draws a cursor before a break on its own line', () {
      final c = TextAreaController(text: 'ab\ncd')..cursor = 2;
      var l = c.layout(width: 9, maxHeight: 9);
      expect((l.cursorRow, l.cursorColumn), (0, 2));
      c.cursor = 3;
      l = c.layout(width: 9, maxHeight: 9);
      expect((l.cursorRow, l.cursorColumn), (1, 0));
    });

    test('keeps an empty last line after a final break', () {
      final l = TextAreaController(text: 'a\n').layout(width: 9, maxHeight: 9);
      expect(_rowsOf(l), ['0.0 0..1 "a"', '1.0 2..2 ""!']);
      expect(l.cursorRow, 1);
    });

    test('shows no row without room, keeping text and cursor', () {
      final c = TextAreaController(text: 'abc\ndef')..cursor = 2;
      for (final (width, height) in [(0, 3), (5, 0), (-1, -1)]) {
        final l = c.layout(width: width, maxHeight: height);
        expect(l.height, 0);
        expect(l.shownRows, isEmpty);
        expect(l.rows, isNotEmpty);
      }
      expect((c.text, c.cursor), ('abc\ndef', 2));
    });
  });

  group('TextAreaController scrolling', () {
    test('grows to the content, then scrolls to reveal the cursor', () {
      final c = TextAreaController(text: 'a\nb');
      expect(c.layout(width: 20, maxHeight: 4).height, 2);
      c.text = _sixLines();
      final l = c.layout(width: 20, maxHeight: 4);
      expect(
        (l.height, l.rowOffset, l.cursorRow, l.cursorColumn),
        (4, 2, 5, 6),
      );
      expect([for (final r in l.shownRows) r.line], [2, 3, 4, 5]);
      expect(
        [for (final r in l.shownRows) r.last],
        [false, false, false, true],
      );
      expect(c.rowOffset, 2);
    });

    test('moves only as far as reveals the cursor', () {
      final c = TextAreaController(text: _sixLines());
      var l = c.layout(width: 20, maxHeight: 4);
      for (var i = 0; i < 3; i++) {
        expect(c.moveUp(l), isTrue);
        l = c.layout(width: 20, maxHeight: 4);
        expect((l.rowOffset, l.cursorColumn), (2, 6));
      }
      expect(c.moveUp(l), isTrue);
      l = c.layout(width: 20, maxHeight: 4);
      expect((l.rowOffset, l.cursorRow), (1, 1));
      expect(l.shownRows.first.text, 'line 2');
    });

    test('clamps the offset when rows go away', () {
      final c = TextAreaController(text: _sixLines());
      c.layout(width: 20, maxHeight: 4);
      c.text = 'one';
      expect(c.layout(width: 20, maxHeight: 4).rowOffset, 0);
    });

    test('keeps the logical cursor on a new width and reveals it', () {
      final c = TextAreaController(text: 'abcdefghij\nk')..cursor = 9;
      var l = c.layout(width: 20, maxHeight: 2);
      expect((l.cursorRow, l.rowOffset), (0, 0));
      l = c.layout(width: 2, maxHeight: 2);
      expect(c.cursor, 9);
      expect((l.cursorRow, l.cursorColumn, l.rowOffset), (4, 1, 3));
    });

    test('does not notify while it lays out', () {
      final c = TextAreaController(text: _sixLines());
      var notes = 0;
      c.addListener(() => notes++);
      c.layout(width: 20, maxHeight: 2);
      c.layout(width: 3, maxHeight: 1);
      expect(notes, 0);
    });
  });

  group('TextAreaController.moveUp and moveDown', () {
    test('keep the column through short rows', () {
      final c = TextAreaController(text: 'abcdef\nab\nabcdef')..cursor = 5;
      var l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveDown(l), isTrue);
      expect(c.cursor, 9); // the end of "ab"
      l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveDown(l), isTrue);
      expect(c.cursor, 15); // column 5 again
    });

    test('stop before a wide grapheme rather than in its second cell', () {
      final c = TextAreaController(text: 'abcd\n界界')..cursor = 3;
      final l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveDown(l), isTrue);
      expect(c.cursor, 6); // after the first 界, at cell 2
    });

    test('move by visual row inside a wrapped line', () {
      final c = TextAreaController(text: 'abcdefgh')..cursor = 6;
      var l = c.layout(width: 3, maxHeight: 9);
      expect((l.cursorRow, l.cursorColumn), (2, 0));
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 3);
      // From column 2 up: the end of a row its line goes on from is the
      // next row's start, so the cursor stops a grapheme before it.
      c.cursor = 8;
      l = c.layout(width: 3, maxHeight: 9);
      expect((l.cursorRow, l.cursorColumn), (2, 2));
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 5);
      l = c.layout(width: 3, maxHeight: 9);
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 2);
    });

    test('leave a cursor on the first or last row and its goal alone', () {
      final c = TextAreaController(text: 'abcdef\nab')..cursor = 5;
      var notes = 0;
      c.addListener(() => notes++);
      var l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveUp(l), isFalse);
      expect(c.moveDown(l), isTrue);
      l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveDown(l), isFalse);
      expect(c.cursor, 9);
      l = c.layout(width: 20, maxHeight: 9);
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 5); // the goal survived the edge attempt
      expect(notes, 2);
    });

    test('forget the goal on an edit, a cursor move or a new width', () {
      TextAreaController down() {
        final c = TextAreaController(text: 'abcdef\nab\nabcdef')..cursor = 5;
        c.moveDown(c.layout(width: 20, maxHeight: 9));
        return c;
      }

      final edited = down()..insert('c');
      edited.moveDown(edited.layout(width: 20, maxHeight: 9));
      expect(edited.cursor, 14); // column 3, not 5

      final moved = down()..moveLeft();
      moved.moveDown(moved.layout(width: 20, maxHeight: 9));
      expect(moved.cursor, 11);

      final resized = down();
      resized.moveDown(resized.layout(width: 19, maxHeight: 9));
      expect(resized.cursor, 12);
    });

    test('lay out again when given a layout older than the text', () {
      final c = TextAreaController(text: 'ab\ncd')..cursor = 1;
      final stale = c.layout(width: 20, maxHeight: 9);
      c.text = 'x\nabcdef\nabcdef';
      c.cursor = 6;
      expect(c.moveDown(stale), isTrue);
      expect(c.cursor, 13);
    });

    test('lay out at the latest width when given an older layout', () {
      final c = TextAreaController(text: 'abcdef')..cursor = 1;
      final wide = c.layout(width: 20, maxHeight: 9);
      c.layout(width: 3, maxHeight: 9);
      expect(c.moveDown(wide), isTrue);
      expect(c.cursor, 4);
      // And back: a narrow layout after a wide one moves in the wide rows.
      final narrow = c.layout(width: 3, maxHeight: 9);
      c.layout(width: 20, maxHeight: 9);
      expect(c.moveUp(narrow), isFalse);
      expect(c.cursor, 4);
    });

    test('go up from a full line'
        's end and back to it', () {
      final c = TextAreaController(text: 'abc');
      var l = c.layout(width: 3, maxHeight: 9);
      expect(_rowsOf(l), ['0.0 0..3 "abc"', '0.1 3..3 ""!']);
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 0);
      l = c.layout(width: 3, maxHeight: 9);
      expect(_rowsOf(l), ['0.0 0..3 "abc"', '0.1 3..3 ""!']);
      expect(c.moveDown(l), isTrue);
      expect(c.cursor, 3);
      expect(c.layout(width: 3, maxHeight: 9).cursorRow, 1);
    });

    test('reach a full line'
        's end from below', () {
      final c = TextAreaController(text: 'abc\nxyz');
      var l = c.layout(width: 3, maxHeight: 9);
      // abc, its empty row, xyz, its empty row: the cursor on the last.
      expect((l.rows.length, l.cursorRow), (4, 3));
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 4); // the start of xyz, goal 0
      l = c.layout(width: 3, maxHeight: 9);
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 3); // the empty row after abc
      expect(c.layout(width: 3, maxHeight: 9).cursorRow, 1);
    });

    test(
      'forget the goal on a cursor assignment or move that changes nothing',
      () {
        TextAreaController down() {
          final c = TextAreaController(text: 'abcdef\nab\nabcdef')..cursor = 5;
          c.moveDown(c.layout(width: 20, maxHeight: 9));
          expect(c.cursor, 9);
          return c;
        }

        void expectColumn2(TextAreaController c) {
          c.moveDown(c.layout(width: 20, maxHeight: 9));
          expect(c.cursor, 12);
        }

        expectColumn2(down()..cursor = 9);
        // Already at its line's end, with no layout to step in.
        expectColumn2(down()..moveToRowEnd(null));
        expectColumn2(down()..deleteToLineEnd());
        // An edit that changes nothing forgets it too.
        expectColumn2(down()..deleteBefore(0));
      },
    );

    test('notify once per move, with the cursor settled', () {
      final c = TextAreaController(text: 'ab\ncd');
      final seen = <int>[];
      c.addListener(() => seen.add(c.cursor));
      c.moveUp(c.layout(width: 20, maxHeight: 9));
      expect(seen, [2]);
    });
  });
}

void _testerLayoutCases() {
  group('tester: visual layout boundaries', () {
    for (final width in [0, 1, 2, 3, 80, 120]) {
      test('rows preserve source and stable metadata at width $width', () {
        const source = ' e\u0301界👩‍💻\t  x\n\n🇺🇦end\n';
        final c = TextAreaController(text: source);
        final clusters = source.characters.toList();
        final original = c.layout(width: width, maxHeight: 3);
        final metadata = _rowsOf(original);
        for (var cursor = 0; cursor <= c.length; cursor++) {
          c.cursor = cursor;
          final l = c.layout(width: width, maxHeight: 3);
          expect(_rowsOf(l), metadata, reason: 'cursor $cursor');
          expect(l.rows.where((r) => r.last), hasLength(1));
          expect(l.rows.last.last, isTrue);
          for (final row in l.rows) {
            expect(row.text, clusters.sublist(row.start, row.end).join());
          }
          expect(
            [
              for (var line = 0; line < 4; line++)
                l.rows.where((r) => r.line == line).map((r) => r.text).join(),
            ].join('\n'),
            source,
          );
          final row = l.rows[l.cursorRow];
          expect(cursor, inInclusiveRange(row.start, row.end));
          if (l.height > 0) {
            expect(
              l.cursorRow,
              inInclusiveRange(l.rowOffset, l.rowOffset + l.height - 1),
            );
          } else {
            expect(l.shownRows, isEmpty);
          }
        }
        c.dispose();
      });
    }

    test(
      'snapshots stay unchanged after edits and their rows are immutable',
      () {
        final c = TextAreaController(text: 'abcdef\n界');
        final before = c.layout(width: 3, maxHeight: 2);
        final metadata = _rowsOf(before);
        expect(() => before.rows.clear(), throwsUnsupportedError);
        c
          ..clear()
          ..insert('new');
        c.layout(width: 1, maxHeight: 1);
        expect(_rowsOf(before), metadata);
        expect(before.shownRows.map((r) => r.text), ['', '界']);
        c.dispose();
      },
    );

    test('vertical goal survives a tab row without entering the tab', () {
      final c = TextAreaController(text: 'abcdef\n\tX\nabcdef')..cursor = 3;
      var l = c.layout(width: 20, maxHeight: 2);
      expect(c.moveDown(l), isTrue);
      expect(c.cursor, 7);
      l = c.layout(width: 20, maxHeight: 2);
      expect(l.cursorColumn, 0);
      expect(c.moveDown(l), isTrue);
      l = c.layout(width: 20, maxHeight: 2);
      expect(l.cursorColumn, 3);
      expect(c.moveUp(l), isTrue);
      l = c.layout(width: 20, maxHeight: 2);
      expect(c.moveUp(l), isTrue);
      expect(c.cursor, 3);
      c.dispose();
    });

    test('height changes retain the vertical goal through an empty row', () {
      final c = TextAreaController(text: 'abcdef\n\nabcdef')..cursor = 5;
      expect(c.moveDown(c.layout(width: 20, maxHeight: 3)), isTrue);
      expect(c.cursor, 7);
      final short = c.layout(width: 20, maxHeight: 1);
      expect(c.moveDown(short), isTrue);
      expect(c.layout(width: 20, maxHeight: 1).cursorColumn, 5);
      c.dispose();
    });

    test('stale offsets are discarded after graphemes join across a break', () {
      final c = TextAreaController(text: 'e\n\u0301\nabcdef')..cursor = 1;
      final stale = c.layout(width: 20, maxHeight: 2);
      c.delete();
      expect((c.length, c.cursor), (8, 1));
      expect(c.moveDown(stale), isTrue);
      expect((c.cursorLine, c.cursorColumn), (1, 1));
      c.dispose();
    });

    test('a listener observes the settled move and no layout notification', () {
      final c = TextAreaController(text: 'abcd\n界界')..cursor = 3;
      final seen = <(int, int, int)>[];
      c.addListener(() {
        final l = c.layout(width: 80, maxHeight: 24);
        seen.add((c.cursor, l.cursorRow, l.cursorColumn));
      });
      expect(c.moveDown(c.layout(width: 80, maxHeight: 24)), isTrue);
      expect(seen, [(6, 1, 2)]);
      c.layout(width: 120, maxHeight: 40);
      expect(seen, hasLength(1));
      c.dispose();
    });
  });

  group('TextAreaController listeners that edit', () {
    test('an edit answering a geometry notification settles', () {
      final c = TextAreaController(text: 'e');
      var once = true;
      c.addListener(() {
        if (!once) return;
        once = false;
        c.insert('\u0301');
      });
      final before = c.layout(width: 10, maxHeight: 3);
      c.notifyAfterLayout();
      expect((c.text, c.length, c.cursor), ('e\u0301', 1, 1));
      // The layout from before the edit is stale: a move lays out again.
      c.cursor = 0;
      expect(c.moveDown(before), isFalse);
      expect(c.layout(width: 10, maxHeight: 3).rows.single.end, 1);
    });

    test('a move answering a vertical move resets the goal', () {
      final c = TextAreaController(text: 'abcdef\nab\nabcdef')..cursor = 5;
      var once = true;
      c.addListener(() {
        if (!once) return;
        once = false;
        c.moveLeft();
      });
      c.moveDown(c.layout(width: 20, maxHeight: 9));
      expect(c.cursor, 8); // column 1 of "ab"
      c.moveDown(c.layout(width: 20, maxHeight: 9));
      expect(c.cursor, 11); // column 1, the goal the move left behind
    });

    test('an edit answering a vertical move settles its graphemes', () {
      final c = TextAreaController(text: 'ab\ne')..cursor = 1;
      var once = true;
      c.addListener(() {
        if (!once) return;
        once = false;
        c.insert('\u0301');
      });
      c.moveDown(c.layout(width: 20, maxHeight: 9));
      expect((c.text, c.length, c.cursor), ('ab\ne\u0301', 4, 4));
    });
  });

  group('CTUI-163: TextAreaController.moveToRowStart and moveToRowEnd', () {
    /// Where the cursor lands from [at] in [text] laid out at [width].
    (int, int) ends(String text, int at, int width) {
      final c = TextAreaController(text: text)..cursor = at;
      c.moveToRowStart(c.layout(width: width, maxHeight: 9));
      final start = c.cursor;
      c.cursor = at;
      c.moveToRowEnd(c.layout(width: width, maxHeight: 9));
      return (start, c.cursor);
    }

    test('an unwrapped row is its line', () {
      expect(ends('hello world', 4, 40), (0, 11));
      expect(ends('one\ntwo three\nfour', 6, 40), (4, 13));
    });

    test('a wrapped row: its start, and its end before its last grapheme '
        'while the line goes on', () {
      // "abcd" "efgh" "ij"
      expect(ends('abcdefghij', 5, 4), (4, 7));
      expect(ends('abcdefghij', 1, 4), (0, 3));
      // The last row of a line ends at the line's end.
      expect(ends('abcdefghij', 9, 4), (8, 10));
      expect(ends('abcdefghij\nk', 9, 4), (8, 10));
    });

    test('a cursor at a wrap boundary moves in the row it is drawn on, the '
        'next', () {
      expect(ends('abcdefghij', 4, 4), (4, 7));
      expect(ends('abcdefghij', 8, 4), (8, 10));
    });

    test('a second press stays on the row', () {
      final c = TextAreaController(text: 'abcdefghij')..cursor = 1;
      c.moveToRowEnd(c.layout(width: 4, maxHeight: 9));
      expect(c.cursor, 3);
      c.moveToRowEnd(c.layout(width: 4, maxHeight: 9));
      expect(c.cursor, 3);
      c.moveToRowStart(c.layout(width: 4, maxHeight: 9));
      c.moveToRowStart(c.layout(width: 4, maxHeight: 9));
      expect(c.cursor, 0);
    });

    test('wide graphemes are never split, and a lone one has start = end', () {
      // "日本" "語x" at four cells.
      expect(ends('日本語x', 1, 4), (0, 1));
      expect(ends('日本語x', 3, 4), (2, 4));
      // A grapheme wider than the row sits alone: "日" "本" at width 1.
      expect(ends('日本', 0, 1), (0, 0));
      expect(ends('e\u0301e\u0301e\u0301', 1, 2), (0, 1));
    });

    test('a line that fills its last row: the empty row after it is both '
        'ends; the row before ends before its last grapheme', () {
      expect(ends('abcd\nx', 4, 4), (4, 4));
      expect(ends('abcd\nx', 2, 4), (0, 3));
    });

    test('a width of zero moves as the logical line', () {
      expect(ends('abcdefghij\nk', 5, 0), (0, 10));
    });

    test('a stale layout is laid out again at the last width', () {
      final c = TextAreaController(text: 'abcdefghij')..cursor = 1;
      final old = c.layout(width: 4, maxHeight: 9);
      c.insert('zz');
      c.cursor = 6;
      c.moveToRowStart(old);
      expect(c.cursor, 4);
    });

    test('a move forgets the vertical goal', () {
      final c = TextAreaController(text: 'abcdefgh\nab\nabcdefgh')..cursor = 7;
      expect(c.moveDown(c.layout(width: 40, maxHeight: 9)), isTrue);
      expect(c.cursor, 11);
      c.moveToRowStart(c.layout(width: 40, maxHeight: 9));
      expect(c.moveDown(c.layout(width: 40, maxHeight: 9)), isTrue);
      expect(c.cursor, 12);
    });
  });
}
