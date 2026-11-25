// Vim's normal mode, from chord's tests/ui/prompt/vim_test.ts, case for
// case over grapheme offsets; the original's (line, column) cursors are
// kept as written and converted.
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// Normal mode, as Esc leaves it.
const normal = VimState(mode: VimMode.normal);

/// The offset of [line], [column] in [text].
int offset(String text, int line, int column) {
  final lines = text.split('\n');
  var at = 0;
  for (var i = 0; i < line; i++) {
    at += lines[i].length + 1;
  }
  return at + column;
}

/// [at] in [text] as a (line, column).
(int, int) position(String text, int at) {
  final before = text.substring(0, at).split('\n');
  return (before.length - 1, before.last.length);
}

typedef Played = ({String text, int cursor, VimState state});

/// [keys], a key each, played from [text] at [line], [column].
Played play(
  String text,
  (int, int) at,
  List<String> keys, {
  VimState state = normal,
  bool image = false,
}) {
  var now = (text: text, cursor: offset(text, at.$1, at.$2), state: state);
  for (final key in keys) {
    final step = vimStep(
      now.state,
      (text: now.text, cursor: now.cursor),
      key,
      atoms: image ? wholeImage : null,
    );
    if (step.edge != null) throw StateError('$key walked history');
    now = (
      text: step.value?.text ?? now.text,
      cursor: step.value?.cursor ?? now.cursor,
      state: step.state,
    );
  }
  return now;
}

/// A range touching `[Image #1]` takes all of it.
(int, int) wholeImage(String text, int start, int end) {
  const placeholder = '[Image #1]';
  final at = text.indexOf(placeholder);
  if (at < 0) return (start, end);
  final last = at + placeholder.length;
  if (end <= at || start >= last) return (start, end);
  return (start < at ? start : at, end > last ? end : last);
}

/// What [keys] leave: the text and the cursor as a (line, column).
(String, (int, int)) after(String text, (int, int) at, String keys) {
  final played = play(text, at, keys.split(''));
  return (played.text, position(played.text, played.cursor));
}

const fox = 'the quick brown fox';

void main() {
  test('h and l move along the line and stop at its ends', () {
    expect(after(fox, (0, 4), 'l'), (fox, (0, 5)));
    expect(after(fox, (0, 4), 'h'), (fox, (0, 3)));
    expect(after(fox, (0, 0), 'h'), (fox, (0, 0)));
    // Normal mode stands on the last character, never after it.
    expect(after(fox, (0, 18), 'l'), (fox, (0, 18)));
  });

  test('j and k move between lines, keeping the column where it fits', () {
    const text = 'first line\nab\nthird line';
    expect(after(text, (0, 6), 'j'), (text, (1, 1)));
    expect(after(text, (1, 1), 'k'), (text, (0, 1)));
    expect(after(text, (0, 6), 'jj'), (text, (2, 6)));
  });

  test('k on the first line and j on the last walk on', () {
    const text = 'one\ntwo';
    final up = vimStep(normal, (text: text, cursor: 1), 'k');
    expect(up.edge, TextAreaDirection.up);
    expect(up.value, isNull);
    expect(up.state, normal);
    expect(
      vimStep(normal, (text: text, cursor: 5), 'j').edge,
      TextAreaDirection.down,
    );
    expect(
      vimStep(normal, (text: text, cursor: 1), 'up').edge,
      TextAreaDirection.up,
    );
  });

  test('w, b and e move by words', () {
    expect(after(fox, (0, 0), 'w'), (fox, (0, 4)));
    expect(after(fox, (0, 10), 'b'), (fox, (0, 4)));
    expect(after(fox, (0, 0), 'e'), (fox, (0, 2)));
    expect(after(fox, (0, 2), 'e'), (fox, (0, 8)));
  });

  test('0, ^ and \$ go to the start, the first word and the end', () {
    const text = '  indented line';
    expect(after(text, (0, 9), '0'), (text, (0, 0)));
    expect(after(text, (0, 9), '^'), (text, (0, 2)));
    expect(after(text, (0, 0), r'$'), (text, (0, 14)));
  });

  test('a count moves that many times', () {
    expect(after(fox, (0, 0), '3w'), (fox, (0, 16)));
    expect(after(fox, (0, 0), '4l'), (fox, (0, 4)));
    expect(after(fox, (0, 16), '2b'), (fox, (0, 4)));
    expect(after('a\nb\nc\nd', (0, 0), '2j'), ('a\nb\nc\nd', (2, 0)));
  });

  test('a count waits for its motion, and Esc drops it', () {
    final half = play(fox, (0, 0), ['2']);
    expect(half.state.pending, ['2']);
    expect(half.cursor, 0);
    expect(play(fox, (0, 0), ['2', 'd']).state.pending, ['2', 'd']);
  });

  test('x deletes the character under the cursor, a count that many', () {
    expect(after(fox, (0, 0), 'x'), ('he quick brown fox', (0, 0)));
    expect(after(fox, (0, 4), '3x'), ('the ck brown fox', (0, 4)));
    // On the last character the cursor steps back onto the new last.
    expect(after('ab', (0, 1), 'x'), ('a', (0, 0)));
  });

  test('dw deletes to the next word, and counts either side', () {
    expect(after(fox, (0, 4), 'dw'), ('the brown fox', (0, 4)));
    expect(after(fox, (0, 0), 'd2w'), ('brown fox', (0, 0)));
    expect(after(fox, (0, 0), '2dw'), ('brown fox', (0, 0)));
  });

  test('dd deletes the line, a count that many', () {
    const text = 'one\ntwo\nthree';
    expect(after(text, (1, 1), 'dd'), ('one\nthree', (1, 0)));
    expect(after(text, (0, 0), '2dd'), ('three', (0, 0)));
    expect(after(text, (2, 2), 'dd'), ('one\ntwo', (1, 0)));
    expect(after('only', (0, 2), 'dd'), ('', (0, 0)));
  });

  test('D deletes to the end of the line', () {
    expect(after(fox, (0, 10), 'D'), ('the quick ', (0, 9)));
  });

  test('cw and C change, leaving insert mode at the gap', () {
    final changed = play(fox, (0, 4), ['c', 'w']);
    expect(changed.text, 'the  brown fox');
    expect(changed.cursor, 4);
    expect(changed.state.mode, VimMode.insert);
    final rest = play(fox, (0, 4), ['C']);
    expect(rest.text, 'the ');
    expect(rest.cursor, 4);
    expect(rest.state.mode, VimMode.insert);
  });

  test('i, a, I and A go to insert mode before, after, at the start, at '
      'the end', () {
    const text = '  word here';
    int insert(String keys) {
      final played = play(text, (0, 4), keys.split(''));
      expect(played.state.mode, VimMode.insert, reason: keys);
      expect(played.text, text, reason: keys);
      return played.cursor;
    }

    expect(insert('i'), 4);
    expect(insert('a'), 5);
    expect(insert('I'), 2);
    expect(insert('A'), 11);
  });

  test('o and O open a line below and above, in insert mode', () {
    final below = play('one\ntwo', (0, 1), ['o']);
    expect(below.text, 'one\n\ntwo');
    expect(position(below.text, below.cursor), (1, 0));
    expect(below.state.mode, VimMode.insert);
    final above = play('one\ntwo', (0, 1), ['O']);
    expect(above.text, '\none\ntwo');
    expect(above.cursor, 0);
  });

  test('p puts back what was deleted, after the cursor or below the line', () {
    expect(after(fox, (0, 4), 'dwp'), ('the bquick rown fox', (0, 10)));
    expect(after('one\ntwo\nthree', (0, 0), 'ddp'), (
      'two\none\nthree',
      (1, 0),
    ));
    // The last line's dd takes the line, not the break before it.
    expect(after('one\ntwo', (1, 0), 'ddP'), ('two\none', (0, 0)));
    expect(
      play('one\ntwo', (1, 0), ['d', 'd']).state.register,
      const VimRegister('two\n', linewise: true),
    );
  });

  test('y yanks into the register and p puts it back: a word, a line, a '
      'text object', () {
    expect(
      play(fox, (0, 4), ['y', 'w']).state.register,
      const VimRegister('quick '),
    );
    expect(after(fox, (0, 4), 'ywp'), ('the qquick uick brown fox', (0, 10)));
    expect(after('one\ntwo', (0, 0), 'yyp'), ('one\none\ntwo', (1, 0)));
    expect(
      play('one\ntwo', (0, 0), ['y', 'y']).state.register,
      const VimRegister('one\n', linewise: true),
    );
    // A text object: the word under the cursor, put at the line's end.
    expect(after(fox, (0, 6), r'yiw$p'), ('the quick brown foxquick', (0, 23)));
  });

  test(
    'dd keeps a blank line in the register, at the start of a count too',
    () {
      expect(after('one\n\ntwo', (1, 0), 'ddp'), ('one\ntwo\n', (2, 0)));
      expect(after('\none\ntwo', (0, 0), '2ddp'), ('two\n\none', (1, 0)));
      expect(after('one\n', (1, 0), 'ddP'), ('\none', (0, 0)));
    },
  );

  test('a counted dd that reaches the last line leaves no blank line', () {
    expect(after('a\nb\nc', (1, 0), '2dd'), ('a', (0, 0)));
    expect(after('a\nb\nc', (1, 0), '5dd'), ('a', (0, 0)));
    expect(after('a\n  b\nc\nd', (2, 0), 'dj'), ('a\n  b', (1, 2)));
    expect(after('a\nb\nc', (1, 0), '2ddp'), ('a\nb\nc', (1, 0)));
  });

  test('a counted change that reaches the last line keeps its line', () {
    for (final keys in [
      ['2', 'c', 'c'],
      ['c', 'j'],
    ]) {
      final changed = play('a\nb\nc', (1, 0), keys);
      expect(changed.text, 'a\n', reason: '$keys');
      expect(position(changed.text, changed.cursor), (1, 0));
      expect(changed.state.mode, VimMode.insert);
    }
  });

  test('u asks the caller to undo, changing nothing itself', () {
    final step = vimStep(normal, (text: fox, cursor: 4), 'u');
    expect(step.undo, isTrue);
    expect(step.value, isNull);
    expect(step.taken, isTrue);
  });

  test('Esc steps back onto the character insert mode was after', () {
    expect(
      vimEscape(const VimState(), (text: 'abc', cursor: 3)).value?.cursor,
      2,
    );
    expect(vimEscape(const VimState(), (text: '', cursor: 0)).value, isNull);
    expect(
      vimEscape(const VimState(), (text: 'ab\ncd', cursor: 3)).value,
      isNull,
    );
    expect(
      vimEscape(const VimState(), (text: 'abc', cursor: 3)).state.mode,
      VimMode.normal,
    );
  });

  test('x and dw take a placeholder whole, never half of it', () {
    const text = 'see [Image #1] here';
    final cut = play(text, (0, 8), ['x'], image: true);
    expect(cut.text, 'see  here');
    expect(cut.state.register, const VimRegister('[Image #1]'));
    expect(play(text, (0, 5), ['d', 'w'], image: true).text, 'see  here');
    // Text around it goes as text.
    expect(play(text, (0, 0), ['d', 'w'], image: true).text, text.substring(4));
    // Without the atoms a placeholder is only text.
    expect(play(text, (0, 8), ['x']).text, 'see [Imae #1] here');
  });

  test('keys normal mode does not take change nothing', () {
    for (final key in ['v', ':', '/', 'q', 'G', '.']) {
      final step = vimStep(normal, (text: fox, cursor: 4), key);
      expect(step.taken, isFalse, reason: key);
      expect(step.value, isNull, reason: key);
      expect(step.state, normal, reason: key);
    }
    // After f, any character is the one to find.
    expect(after(fox, (0, 0), 'f/'), (fox, (0, 0)));
    expect(after(fox, (0, 0), 'fq'), (fox, (0, 4)));
    expect(vimTakes(const VimState(pending: ['f']), '/'), isTrue);
    expect(vimTakes(normal, '/'), isFalse);
  });

  test('a text object follows an operator', () {
    expect(after(fox, (0, 6), 'diw'), ('the  brown fox', (0, 4)));
    expect(play(fox, (0, 6), ['c', 'i', 'w']).state.mode, VimMode.insert);
  });

  test('a key event reads as the key normal mode names', () {
    expect(vimKeyOf(const KeyEvent('d')), 'd');
    expect(vimKeyOf(const KeyEvent('left')), 'left');
    expect(vimKeyOf(const KeyEvent('backspace')), 'backspace');
    expect(vimKeyOf(const KeyEvent('w', ctrl: true)), isNull);
    expect(vimKeyOf(const KeyEvent('tab')), isNull);
    expect(vimKeyOf(const KeyEvent('D', shift: true)), 'D');
    // A composed grapheme is one key, as `r` takes it whole.
    expect(vimKeyOf(const KeyEvent('👩‍💻')), '👩‍💻');
    expect(vimKeyOf(const KeyEvent('e\u0301')), 'e\u0301');
  });

  group('yank counts, cursors and registers', () {
    for (final keys in ['2yw', 'y2w']) {
      test('$keys counts words without moving the cursor or the text', () {
        final result = play('one two three', (0, 0), keys.split(''));
        expect(result.text, 'one two three');
        expect(result.cursor, 0);
        expect(result.state.register, const VimRegister('one two '));
      });
    }

    for (final keys in ['2yy', 'y2y']) {
      test('$keys keeps the linewise register for repeated puts', () {
        final result = play('one\ntwo\nthree', (0, 0), keys.split(''));
        expect(result.text, 'one\ntwo\nthree');
        expect(result.cursor, 0);
        expect(
          result.state.register,
          const VimRegister('one\ntwo\n', linewise: true),
        );
        expect(
          play(result.text, (0, 0), ['p', 'p'], state: result.state).text,
          'one\none\none\ntwo\ntwo\ntwo\nthree',
        );
      });
    }

    test('a last-line yank puts below the last line', () {
      final result = play('one\ntwo', (1, 1), ['y', 'y']);
      expect(result.text, 'one\ntwo');
      expect(position(result.text, result.cursor), (1, 1));
      expect(result.state.register, const VimRegister('two\n', linewise: true));
      expect(
        play(result.text, (1, 1), ['p'], state: result.state).text,
        'one\ntwo\ntwo',
      );
    });

    test('an empty-line yank stays linewise and leaves the cursor', () {
      final result = play('one\n\ntwo', (1, 0), ['y', 'y']);
      expect(position(result.text, result.cursor), (1, 0));
      expect(result.state.register, const VimRegister('\n', linewise: true));
      expect(
        play(result.text, (1, 0), ['p'], state: result.state).text,
        'one\n\n\ntwo',
      );
    });

    test('a word text object leaves an interior cursor where it began', () {
      final result = play('one two three', (0, 5), ['y', 'i', 'w']);
      expect(result.cursor, 5);
      expect(result.state.register, const VimRegister('two'));
    });

    test('separate states keep their own yank, a pending operator too', () {
      final pending = play('alpha beta', (0, 1), ['y']);
      final other = play('gamma delta', (0, 1), ['y', 'i', 'w']);
      final first = play(
        'alpha beta',
        (0, 1),
        ['i', 'w'],
        state: pending.state,
      );
      expect(first.state.register, const VimRegister('alpha'));
      expect(other.state.register, const VimRegister('gamma'));
      expect(
        play(first.text, (0, 9), ['p'], state: first.state).text,
        'alpha betaalpha',
      );
    });
  });

  group('the rest of NORMAL_KEYS', () {
    test('~ toggles case and moves on', () {
      expect(after('abc', (0, 0), '~~'), ('ABc', (0, 2)));
    });

    test('r replaces under the cursor, a count that many', () {
      expect(after('abcd', (0, 1), 'rx'), ('axcd', (0, 1)));
      expect(after('abcd', (0, 1), '2ry'), ('ayyd', (0, 2)));
    });

    test('J joins the next line with one space', () {
      expect(after('one\n   two', (0, 1), 'J'), ('one two', (0, 3)));
    });

    test('t and T stop before, ; and , repeat the last find', () {
      expect(after(fox, (0, 0), 'tk'), (fox, (0, 7)));
      expect(after(fox, (0, 18), 'Tq'), (fox, (0, 5)));
      expect(after(fox, (0, 0), 'fo;'), (fox, (0, 17)));
      expect(after(fox, (0, 0), 'fo;,'), (fox, (0, 12)));
    });

    test('s and S change a character and a line, X deletes before, Y yanks '
        'the line', () {
      final s = play(fox, (0, 0), ['s']);
      expect((s.text, s.state.mode), ('he quick brown fox', VimMode.insert));
      final whole = play('one\ntwo', (1, 1), ['S']);
      expect((whole.text, whole.state.mode), ('one\n', VimMode.insert));
      expect(after(fox, (0, 4), 'X'), ('thequick brown fox', (0, 3)));
      expect(
        play('one\ntwo', (0, 0), ['Y']).state.register,
        const VimRegister('one\n', linewise: true),
      );
    });

    test('W, B and E move by blank-separated words', () {
      const text = 'a.b c-d e';
      expect(after(text, (0, 0), 'W'), (text, (0, 4)));
      expect(after(text, (0, 4), 'E'), (text, (0, 6)));
      expect(after(text, (0, 8), 'B'), (text, (0, 4)));
    });
  });

  group('review: finds beside the cursor, atoms across lines, space', () {
    test('a first t finds the target beside the cursor; ; looks past it', () {
      expect(after('abcb', (0, 0), 'tb'), ('abcb', (0, 0)));
      final cut = play('abcb', (0, 0), ['d', 't', 'b']);
      expect(cut.text, 'bcb');
      expect(cut.state.register, const VimRegister('a'));
      expect(after('abcb', (0, 0), 'tb;'), ('abcb', (0, 2)));
      expect(after('bcba', (0, 3), 'Tb'), ('bcba', (0, 3)));
    });

    /// An atom over [2, 5): `X\nY` in 'a X\nY b', `[\n]` in 'ab[\n]cd'.
    (int, int) across(String text, int start, int end) => end <= 2 || start >= 5
        ? (start, end)
        : (start < 2 ? start : 2, end > 5 ? end : 5);

    test('dd and cc take an atom that reaches past their lines whole', () {
      final dd = vimStep(normal, (text: 'a X\nY b', cursor: 0), 'd');
      final step = vimStep(
        dd.state,
        (text: 'a X\nY b', cursor: 0),
        'd',
        atoms: across,
      );
      expect(step.value?.text, ' b');
      expect(step.state.register, const VimRegister('a X\nY'));
      final cc = vimStep(
        vimStep(normal, (text: 'a X\nY b', cursor: 0), 'c').state,
        (text: 'a X\nY b', cursor: 0),
        'c',
        atoms: across,
      );
      expect(cc.value?.text, ' b');
      expect(cc.state.mode, VimMode.insert);
    });

    test('J takes an atom it cuts into whole', () {
      final step = vimStep(
        normal,
        (text: 'ab[\n]cd', cursor: 0),
        'J',
        atoms: across,
      );
      expect(step.value?.text, 'ab cd');
    });

    test('a space is a key: f finds it, alone normal mode takes none', () {
      expect(vimKeyOf(const KeyEvent(' ')), ' ');
      expect(vimTakes(normal, ' '), isFalse);
      expect(after(fox, (0, 0), 'f '), (fox, (0, 3)));
    });
  });

  test('r replaces a grapheme with a whole one, an emoji too', () {
    final one = play('abc', (0, 0), ['r', '🙂']);
    expect((one.text, one.cursor), ('🙂bc', 0));
    final three = play('abcd', (0, 0), ['3', 'r', '🙂']);
    expect((three.text, three.cursor), ('🙂🙂🙂d', 2));
  });

  test('after f, t or r normal mode takes the next key as the character '
      'it is', () {
    for (final key in ['f', 'F', 't', 'T', 'r']) {
      expect(vimTakesCharacter(VimState(pending: [key])), isTrue, reason: key);
    }
    expect(vimTakesCharacter(const VimState()), isFalse);
    expect(vimTakesCharacter(const VimState(pending: ['d', 'i'])), isFalse);
  });
}
