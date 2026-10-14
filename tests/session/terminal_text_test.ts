import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import {
  COLUMN_LIMIT,
  EMPTY_TEXT,
  PARAMS_LIMIT,
  plainText,
  type TerminalText,
  writeText,
} from '../../src/session/terminal_text.ts';
import { SHELL_OUTPUT } from '../fixtures/terminals.ts';

/** `pieces` written one after another, with no bound to speak of. */
function written(...pieces: readonly string[]): TerminalText {
  return pieces.reduce(
    (text, piece) => writeText(text, piece, Infinity),
    EMPTY_TEXT,
  );
}

/** Output as each kind of control leaves it, and what a screen shows. */
const FIXTURES: readonly (readonly [string, string, string])[] = [
  ['colours', 'a \x1b[1;31mred\x1b[0m b\x1b[38;5;208m!', 'a red b!'],
  [
    'an OSC 8 link',
    'see \x1b]8;id=1;https://example.com\x1b\\here\x1b]8;;\x07.',
    'see here.',
  ],
  ['a progress line', 'get 1/3\rget 2/3\rget 3/3\ndone\n', 'get 3/3\ndone\n'],
  ['a shorter rewrite', 'abcdef\rXY\r\n', 'XYcdef\n'],
  ['erase in line', 'abcdef\x1b[3D\x1b[K\n12345\x1b[2D\x1b[1K', 'abc\n    5'],
  ['a cleared line', 'loading…\x1b[2K\rok', 'ok'],
  ['backspace', 'abc\b\bX\n', 'aXc\n'],
  [
    'progress over several lines',
    'a 0%\nb 0%\n\x1b[2A\ra 50%\x1b[1B\rb 100%\x1b[3A\x1b[9B',
    'a 50%\nb 100%\n',
  ],
  [
    'a column kept across lines',
    'ab\nlong line\x1b[AX',
    'ab       X\nlong line',
  ],
  ['a column', 'abcdef\x1b[3G!\x1b[C?\x1b[100D<', '<b!d?f'],
  ['an nF escape', 'a\x1b(Bb\x1b#8c', 'abc'],
  ['C1 controls', 'a\x9b31mb\x85c\x90q#0\x9cd\x9d0;t\x9ce\x9e.\x9cf', 'abcdef'],
  ['an OSC an escape breaks off', '\x1b]8;;https://a\x1bbvisible', 'visible'],
  ['an escape with an intermediate', '\x1b 0visible', 'visible'],
  ['a CAN inside an escape', 'a\x1b[3\x18b', 'ab'],
  ['C0 inside a CSI', 'a\x1b[3\r1mb', 'b'],
  ['bells and other C0', 'a\x07b\x00c\x0bd\x0ce\x7f', 'abcde'],
  ['a private CSI', 'a\x1b[?25lb\x1b[>1;2Kc', 'abc'],
  [
    'tabs',
    'a\tb\n界\tc\nabcdefgh\td',
    'a       b\n界      c\nabcdefgh        d',
  ],
  ['wide characters overwritten', '界界\rx\n界界\x1b[3Gy', 'x 界\n界y '],
  ['a combining mark', 'cafe\u0301\rC', 'Cafe\u0301'],
  // Split by code point or between a surrogate's halves, these are read
  // back as the one character they make whole.
  ['a joined emoji written over', 'ab\r👩‍💻Z\tz', '👩‍💻Z     z'],
  ['a joined emoji over a wide one', 'x界\r👩‍💻Z', '👩‍💻Z'],
  ['flags written over', 'abcd\r🇺🇸🇬🇧Z\n🇺🇸\x1b[m🇬🇧\tz', '🇺🇸🇬🇧Z\n🇺🇸🇬🇧    z'],
  ['a mark after an escape', 'ab\ra\x1b[m\u0301b', 'a\u0301b'],
  ['the shell scenario', SHELL_OUTPUT.join(''), ''],
];

for (const [name, output, shown] of FIXTURES) {
  if (shown !== '') {
    test(`${name} read as a screen would leave them`, () => {
      expect(plainText(output)).toStrictEqual(shown);
    });
  }

  test(`${name} fold the same split at every position`, () => {
    const whole = written(output);

    for (let at = 0; at <= output.length; at++) {
      expect(
        written(output.slice(0, at), output.slice(at)),
        `split at ${at}`,
      ).toStrictEqual(whole);
    }

    expect(written(...output), 'a character a delta').toStrictEqual(whole);
  });
}

test('the cursor is held only where it is not at the end', () => {
  expect(written('a\nb')).toStrictEqual({ output: 'a\nb' });
  expect(written('abc\r')).toStrictEqual({
    output: 'abc',
    cursor: { row: 0, column: 0 },
  });
  expect(written('a\nb\n\x1b[2A')).toStrictEqual({
    output: 'a\nb\n',
    cursor: { row: 2, column: 0 },
  });
});

test('the cursor stays within the lines kept', () => {
  expect(plainText('a\x1b[99Ab')).toStrictEqual('ab');
  expect(plainText('a\nb\x1b[99A\rc\x1b[99B\rd')).toStrictEqual('c\nd');
  expect(plainText('\x1b[99Da')).toStrictEqual('a');
});

test('a cursor move stops at the margin, however far it is sent', () => {
  const far = '9'.repeat(PARAMS_LIMIT);

  expect(plainText(`\x1b[${far}CX`)).toStrictEqual(
    `${' '.repeat(COLUMN_LIMIT)}X`,
  );
  expect(plainText(`\x1b[${far}GX`)).toStrictEqual(
    `${' '.repeat(COLUMN_LIMIT)}X`,
  );
  expect(
    plainText(`界\x1b[${far}GX\x1b[${far}C\x1b[${far}CY\tZ`),
  ).toStrictEqual(`界${' '.repeat(COLUMN_LIMIT - 2)}XYZ`);
  expect(
    written(...Array(100).fill(`\x1b[${far}C`), 'X').output.length,
  ).toStrictEqual(COLUMN_LIMIT + 1);
  expect(plainText(`${'\t'.repeat(COLUMN_LIMIT)}X`).length).toStrictEqual(
    COLUMN_LIMIT + 1,
  );
  // Text itself runs past it, and a move from there goes no way back.
  expect(plainText(`${'a'.repeat(COLUMN_LIMIT + 5)}\x1b[CX`)).toStrictEqual(
    `${'a'.repeat(COLUMN_LIMIT + 5)}X`,
  );
});

test('an escape a delta ends inside is held as its kind, never its body', () => {
  expect(written('ok\x1b').escape).toStrictEqual({ kind: 'escape' });
  expect(written('ok\x1b ').escape).toStrictEqual({
    kind: 'escape',
    intermediates: true,
  });
  expect(written('ok\x1b[3').escape).toStrictEqual({
    kind: 'csi',
    params: '3',
  });
  expect(written('ok\x1b]8;;https://example.com').escape).toStrictEqual({
    kind: 'string',
  });
  expect(written('ok\x1b]8;;https://example.com\x1b').escape).toStrictEqual({
    kind: 'escape',
  });
  expect(written('ok\x1b[3').output).toStrictEqual('ok');

  const params = written(`\x1b[${'1;'.repeat(100)}`).escape;

  assert(params?.kind === 'csi');
  expect(params.params.length).toStrictEqual(PARAMS_LIMIT);
  expect(params.ignored).toStrictEqual(true);
  expect(plainText(`\x1b[${'1'.repeat(100)}Dab`)).toStrictEqual('ab');
});

test('a write past the bound keeps the last lines, from a line start', () => {
  const text = writeText(EMPTY_TEXT, 'one\ntwo\nthree\n', 10);

  expect(text).toStrictEqual({ output: 'three\n', truncated: true });
  // Cut once, it stays cut, however short what follows.
  expect(writeText(text, 'x', 10).truncated).toStrictEqual(true);
});

test('a line longer than the bound alone is cut within it, never mid-character', () => {
  expect(writeText(EMPTY_TEXT, 'abcdefghij\r', 4)).toStrictEqual({
    output: 'ghij',
    cursor: { row: 0, column: 0 },
    truncated: true,
  });
  expect(writeText(EMPTY_TEXT, 'ae\u0301e\u0301', 3).output).toStrictEqual(
    'e\u0301',
  );
  // A cluster that cannot fit whole goes whole, however many marks it has.
  expect(writeText(EMPTY_TEXT, `a${'\u0301'.repeat(100)}`, 4)).toStrictEqual({
    output: '',
    truncated: true,
  });
  expect(
    writeText(EMPTY_TEXT, `ab${'\u0301'.repeat(100)}c`, 4).output,
  ).toStrictEqual('c');
  // The cursor moves back by the cells dropped, so it stays at the end.
  expect(writeText(EMPTY_TEXT, '界界abc', 4)).toStrictEqual({
    output: '界abc',
    truncated: true,
  });
});
