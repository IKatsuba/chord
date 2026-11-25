// The original's tests/session/terminal_text_test.ts, whole: its 23
// fixtures read as a screen would leave them, and folded the same split at
// every position and a character a delta.
import 'package:chord/session/terminal_text.dart';
import 'package:test/test.dart';

/// What the `shell` scenario's command writes, piece by piece.
const shellOutput = [
  'Task test deno test\n',
  'running 3 tests\n1/3',
  '\r2/3\r3/3\n\x1b[3',
  '2mok\x1b[0m | 2 passed\n\x1b]8;;https://example.com/failed',
  '\x1b\\\x1b[31mFAILED\x1b[0m\x1b]8;;\x1b\\ | 1 failed\n',
];

/// [text] as plain values, every field.
Map<String, Object?> described(TerminalText text) => {
  'output': text.output,
  if (text.cursor case final cursor?)
    'cursor': {'row': cursor.row, 'column': cursor.column},
  if (text.escape case final escape?)
    'escape': switch (escape) {
      EscapeOpen(:final intermediates) => {
        'kind': 'escape',
        if (intermediates) 'intermediates': true,
      },
      CsiOpen(:final params, :final ignored) => {
        'kind': 'csi',
        'params': params,
        if (ignored) 'ignored': true,
      },
      StringOpen() => {'kind': 'string'},
    },
  if (text.truncated) 'truncated': true,
};

/// [pieces] written one after another, with no bound to speak of.
Map<String, Object?> written(Iterable<String> pieces) => described(
  pieces.fold(
    TerminalText.empty,
    (text, piece) => writeText(text, piece, double.infinity),
  ),
);

/// Output as each kind of control leaves it, and what a screen shows.
const fixtures = <(String, String, String)>[
  ('colours', 'a \x1b[1;31mred\x1b[0m b\x1b[38;5;208m!', 'a red b!'),
  (
    'an OSC 8 link',
    'see \x1b]8;id=1;https://example.com\x1b\\here\x1b]8;;\x07.',
    'see here.',
  ),
  ('a progress line', 'get 1/3\rget 2/3\rget 3/3\ndone\n', 'get 3/3\ndone\n'),
  ('a shorter rewrite', 'abcdef\rXY\r\n', 'XYcdef\n'),
  ('erase in line', 'abcdef\x1b[3D\x1b[K\n12345\x1b[2D\x1b[1K', 'abc\n    5'),
  ('a cleared line', 'loading…\x1b[2K\rok', 'ok'),
  ('backspace', 'abc\b\bX\n', 'aXc\n'),
  (
    'progress over several lines',
    'a 0%\nb 0%\n\x1b[2A\ra 50%\x1b[1B\rb 100%\x1b[3A\x1b[9B',
    'a 50%\nb 100%\n',
  ),
  (
    'a column kept across lines',
    'ab\nlong line\x1b[AX',
    'ab       X\nlong line',
  ),
  ('a column', 'abcdef\x1b[3G!\x1b[C?\x1b[100D<', '<b!d?f'),
  ('an nF escape', 'a\x1b(Bb\x1b#8c', 'abc'),
  ('C1 controls', 'a\x9b31mb\x85c\x90q#0\x9cd\x9d0;t\x9ce\x9e.\x9cf', 'abcdef'),
  ('an OSC an escape breaks off', '\x1b]8;;https://a\x1bbvisible', 'visible'),
  ('an escape with an intermediate', '\x1b 0visible', 'visible'),
  ('a CAN inside an escape', 'a\x1b[3\x18b', 'ab'),
  ('C0 inside a CSI', 'a\x1b[3\r1mb', 'b'),
  ('bells and other C0', 'a\x07b\x00c\x0bd\x0ce\x7f', 'abcde'),
  ('a private CSI', 'a\x1b[?25lb\x1b[>1;2Kc', 'abc'),
  ('tabs', 'a\tb\n界\tc\nabcdefgh\td', 'a       b\n界      c\nabcdefgh        d'),
  ('wide characters overwritten', '界界\rx\n界界\x1b[3Gy', 'x 界\n界y '),
  ('a combining mark', 'café\rC', 'Café'),
  // Split by code point or between a surrogate's halves, these are read
  // back as the one character they make whole.
  ('a joined emoji written over', 'ab\r👩‍💻Z\tz', '👩‍💻Z     z'),
  ('a joined emoji over a wide one', 'x界\r👩‍💻Z', '👩‍💻Z'),
  (
    'flags written over',
    'abcd\r🇺🇸🇬🇧Z\n🇺🇸\x1b[m🇬🇧\tz',
    '🇺🇸🇬🇧Z\n🇺🇸🇬🇧    z',
  ),
  ('a mark after an escape', 'ab\ra\x1b[ḿb', 'áb'),
  ('the shell scenario', '', ''),
];

void main() {
  for (final (name, given, shown) in fixtures) {
    final output = name == 'the shell scenario' ? shellOutput.join() : given;

    if (shown.isNotEmpty) {
      test('$name read as a screen would leave them', () {
        expect(plainText(output), shown);
      });
    }

    test('$name fold the same split at every position', () {
      final whole = written([output]);

      for (var at = 0; at <= output.length; at++) {
        expect(
          written([output.substring(0, at), output.substring(at)]),
          whole,
          reason: 'split at $at',
        );
      }

      expect(
        written([for (final rune in output.runes) String.fromCharCode(rune)]),
        whole,
        reason: 'a character a delta',
      );
    });
  }

  test('the cursor is held only where it is not at the end', () {
    expect(written(['a\nb']), {'output': 'a\nb'});
    expect(written(['abc\r']), {
      'output': 'abc',
      'cursor': {'row': 0, 'column': 0},
    });
    expect(written(['a\nb\n\x1b[2A']), {
      'output': 'a\nb\n',
      'cursor': {'row': 2, 'column': 0},
    });
  });

  test('the cursor stays within the lines kept', () {
    expect(plainText('a\x1b[99Ab'), 'ab');
    expect(plainText('a\nb\x1b[99A\rc\x1b[99B\rd'), 'c\nd');
    expect(plainText('\x1b[99Da'), 'a');
  });

  test('a cursor move stops at the margin, however far it is sent', () {
    final far = '9' * paramsLimit;

    expect(plainText('\x1b[${far}CX'), '${' ' * columnLimit}X');
    expect(plainText('\x1b[${far}GX'), '${' ' * columnLimit}X');
    expect(
      plainText('界\x1b[${far}GX\x1b[${far}C\x1b[${far}CY\tZ'),
      '界${' ' * (columnLimit - 2)}XYZ',
    );
    expect(
      (written([...List.filled(100, '\x1b[${far}C'), 'X'])['output'] as String)
          .length,
      columnLimit + 1,
    );
    expect(plainText('${'\t' * columnLimit}X').length, columnLimit + 1);
    // Text itself runs past it, and a move from there goes no way back.
    expect(
      plainText('${'a' * (columnLimit + 5)}\x1b[CX'),
      '${'a' * (columnLimit + 5)}X',
    );
  });

  test('an escape a delta ends inside is held as its kind, never its body', () {
    expect(written(['ok\x1b'])['escape'], {'kind': 'escape'});
    expect(written(['ok\x1b '])['escape'], {
      'kind': 'escape',
      'intermediates': true,
    });
    expect(written(['ok\x1b[3'])['escape'], {'kind': 'csi', 'params': '3'});
    expect(written(['ok\x1b]8;;https://example.com'])['escape'], {
      'kind': 'string',
    });
    expect(written(['ok\x1b]8;;https://example.com\x1b'])['escape'], {
      'kind': 'escape',
    });
    expect(written(['ok\x1b[3'])['output'], 'ok');

    final params = written(['\x1b[${'1;' * 100}'])['escape'] as Map;

    expect(params['kind'], 'csi');
    expect((params['params'] as String).length, paramsLimit);
    expect(params['ignored'], isTrue);
    expect(plainText('\x1b[${'1' * 100}Dab'), 'ab');
  });

  test('a write past the bound keeps the last lines, from a line start', () {
    final text = writeText(TerminalText.empty, 'one\ntwo\nthree\n', 10);

    expect(described(text), {'output': 'three\n', 'truncated': true});
    // Cut once, it stays cut, however short what follows.
    expect(writeText(text, 'x', 10).truncated, isTrue);
  });

  test('a line longer than the bound alone is cut within it, never '
      'mid-character', () {
    expect(described(writeText(TerminalText.empty, 'abcdefghij\r', 4)), {
      'output': 'ghij',
      'cursor': {'row': 0, 'column': 0},
      'truncated': true,
    });
    expect(writeText(TerminalText.empty, 'aéé', 3).output, 'é');
    // A cluster that cannot fit whole goes whole, however many marks it has.
    expect(described(writeText(TerminalText.empty, 'a${'́' * 100}', 4)), {
      'output': '',
      'truncated': true,
    });
    expect(writeText(TerminalText.empty, 'ab${'́' * 100}c', 4).output, 'c');
    // The cursor moves back by the cells dropped, so it stays at the end.
    expect(described(writeText(TerminalText.empty, '界界abc', 4)), {
      'output': '界abc',
      'truncated': true,
    });
  });

  group('tester: terminal text boundaries', () {
    test('zero and one character limits keep whole graphemes only', () {
      for (final data in ['a', '界', '👩‍💻', 'e\u0301', 'a\n', '\x1b[31m界']) {
        final none = writeText(TerminalText.empty, data, 0);
        expect(none.output, '', reason: data);
        expect(none.truncated, isTrue, reason: data);
      }
      for (final (data, expected) in [
        ('a', 'a'),
        ('ab', 'b'),
        ('界', '界'),
        ('👩‍💻', ''),
        ('e\u0301', ''),
        ('👩‍💻Z', 'Z'),
      ]) {
        expect(
          writeText(TerminalText.empty, data, 1).output,
          expected,
          reason: data,
        );
      }
    });

    test('all fixtures fold identically one UTF-16 code unit per delta', () {
      for (final (name, given, _) in fixtures) {
        final data = name == 'the shell scenario' ? shellOutput.join() : given;
        expect(
          written([
            for (final code in data.codeUnits) String.fromCharCode(code),
          ]),
          written([data]),
          reason: name,
        );
      }
    });

    test(
      'branches from an unfinished escape keep their snapshot independent',
      () {
        final before = writeText(TerminalText.empty, '界\r\x1b[', 100);
        final value = described(before);
        final erase = writeText(before, 'KX', 100);
        final right = writeText(before, '2CY', 100);
        expect(erase.output, 'X');
        expect(right.output, '界Y');
        expect(described(before), value);
        expect((before.escape as CsiOpen).params, '');
        expect(before.cursor!.column, 0);
      },
    );
  });
}
