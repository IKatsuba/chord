import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

({VimValue value, VimState state}) play(
  String text,
  int cursor,
  List<String> keys, {
  VimAtoms? atoms,
}) {
  var value = (text: text, cursor: cursor);
  var state = const VimState(mode: VimMode.normal);
  for (final key in keys) {
    final step = vimStep(state, value, key, atoms: atoms);
    value = step.value ?? value;
    state = step.state;
  }
  return (value: value, state: state);
}

void main() {
  group('tester: vim grapheme and history boundaries', () {
    for (final glyph in ['界', '🙂', '👩‍💻', 'é']) {
      test('x and X remove whole $glyph at either edge', () {
        final first = play('${glyph}z', 0, ['x']);
        expect(first.value, (text: 'z', cursor: 0));
        expect(first.state.register, VimRegister(glyph));
        final last = play('z$glyph', 1, ['x']);
        expect(last.value, (text: 'z', cursor: 0));
        expect(last.state.register, VimRegister(glyph));
        expect(play('${glyph}z', 1, ['X']).value, (text: 'z', cursor: 0));
        expect(
          vimEscape(const VimState(), (text: glyph, cursor: 1)).value?.cursor,
          0,
        );
      });
    }

    test('find and repeat count whole graphemes without crossing a line', () {
      expect(play('a🙂b🙂c', 0, ['f', '🙂']).value.cursor, 1);
      expect(play('a🙂b🙂c', 0, ['f', '🙂', ';']).value.cursor, 3);
      expect(play('a🙂b🙂c', 0, ['f', '🙂', ';', ',']).value.cursor, 1);
      expect(play('a🙂b🙂c', 0, ['2', 'f', '🙂']).value.cursor, 3);
      expect(play('a\n🙂', 0, ['f', '🙂']).value.cursor, 0);
      expect(play('a🙂b', 0, ['d', 't', '🙂']).value.text, '🙂b');
    });

    test(
      'replacement accepts a whole grapheme without splitting its units',
      () {
        for (final glyph in ['界', '🙂', '👩‍💻', 'é']) {
          expect(play('abc', 0, ['r', glyph]).value, (
            text: '${glyph}bc',
            cursor: 0,
          ));
          expect(play('abc', 0, ['2', 'r', glyph]).value, (
            text: '$glyph${glyph}c',
            cursor: 1,
          ));
        }
      },
    );

    test(
      'line registers retain Unicode and repeated put cursor stays a grapheme offset',
      () {
        final yank = play('界👩‍💻é\nz', 0, ['y', 'y', 'p']);
        expect(yank.value, (text: '界👩‍💻é\n界👩‍💻é\nz', cursor: 4));
        expect(
          yank.state.register,
          const VimRegister('界👩‍💻é\n', linewise: true),
        );
        final cut = play('z\n界👩‍💻é', 2, ['d', 'd', 'P']);
        expect(cut.value, (text: '界👩‍💻é\nz', cursor: 0));
      },
    );

    test(
      'atoms receive grapheme ranges across a line and register their full text',
      () {
        final seen = <(int, int)>[];
        (int, int) atoms(String text, int from, int to) {
          seen.add((from, to));
          return to <= 1 || from >= 4
              ? (from, to)
              : (from < 1 ? from : 1, to > 4 ? to : 4);
        }

        final cut = play('a👩‍💻\néz', 1, ['x'], atoms: atoms);
        expect(seen, [(1, 2)]);
        expect(cut.value, (text: 'az', cursor: 1));
        expect(cut.state.register, const VimRegister('👩‍💻\né'));
        for (final command in ['d', 'c']) {
          final lines = play('a👩‍💻\néz', 0, [
            command,
            command,
          ], atoms: atoms);
          expect(lines.value.text, 'z');
          expect(lines.state.register, const VimRegister('a👩‍💻\né'));
        }
      },
    );

    test('every normal key and named motion is safe on an empty value', () {
      for (final key in [
        ...vimNormalKeys.characters,
        'left',
        'right',
        'up',
        'down',
        'backspace',
      ]) {
        final step = vimStep(const VimState(mode: VimMode.normal), (
          text: '',
          cursor: 0,
        ), key);
        expect(step.taken, isTrue, reason: key);
        if (step.value case final value?) {
          expect(
            value.cursor,
            inInclusiveRange(0, value.text.characters.length),
            reason: key,
          );
        }
      }
    });

    test(
      'replacement refuses newline or multiple graphemes and clears pending',
      () {
        for (final key in ['\n', 'ab']) {
          final result = play('abc', 0, ['r', key]);
          expect(result.value, (text: 'abc', cursor: 0));
          expect(result.state.pending, isEmpty);
        }
      },
    );

    test('event keys retain one whole grapheme and reject modifiers', () {
      for (final key in ['界', '🙂', '👩‍💻', 'é']) {
        expect(vimKeyOf(KeyEvent(key)), key);
        expect(vimKeyOf(KeyEvent(key, ctrl: true)), isNull);
      }
    });

    test('replace with no change retains the notification contract', () {
      final c = TextAreaController(text: '界🙂é');
      var notifications = 0;
      c.addListener(() => notifications++);
      c.replace(c.text, c.cursor);
      expect(notifications, 0);
    });

    test('one thousand grouped replacements undo and redo as one edit', () {
      final c = TextAreaController(text: 'before')..cursor = 2;
      c.beginUndoGroup();
      for (var i = 0; i < 1000; i++) {
        c.replace('界🙂é $i', 3);
      }
      c.endUndoGroup();
      expect(c.text, '界🙂é 999');
      c.undo();
      expect((c.text, c.cursor), ('before', 2));
      c.redo();
      expect((c.text, c.cursor), ('界🙂é 999', 3));
      c.undo();
      c.beginUndoGroup();
      c.endUndoGroup();
      c.redo();
      expect(c.text, '界🙂é 999');
    });
  });
}
