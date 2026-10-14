import { expect, test } from 'bun:test';
import { RGBA, TextAttributes } from '@opentui/core';
import { colour, runs } from '../../../src/ui/theme/text.ts';

test('a string with no escapes is one run with nothing set', () => {
  expect(runs('plain words')).toStrictEqual([
    { text: 'plain words', attributes: 0 },
  ]);
});

test("a run's SGR is read on top of the one before, and a reset sets nothing again", () => {
  const read = runs('\x1b[1mbold\x1b[31m red\x1b[22m red\x1b[0m plain');

  expect(read.map((run) => run.text)).toStrictEqual([
    'bold',
    ' red',
    ' red',
    ' plain',
  ]);
  expect(read[0]?.attributes).toBe(TextAttributes.BOLD);
  expect(read[1]?.attributes).toBe(TextAttributes.BOLD);
  expect(read[1]?.fg).toStrictEqual(RGBA.fromIndex(1));
  expect(read[2]?.attributes).toBe(0);
  expect(read[2]?.fg).toStrictEqual(RGBA.fromIndex(1));
  expect(read[3]).toStrictEqual({
    text: ' plain',
    fg: undefined,
    bg: undefined,
    attributes: 0,
  });
});

test("a colour in T.416's forms and the 256 one are each read whole", () => {
  const [semicolons, colons, spaced, indexed] = runs(
    '\x1b[38;2;1;2;3ma\x1b[38:2:4:5:6mb\x1b[38:2::7:8:9mc\x1b[48;5;196md',
  );

  expect(semicolons?.fg).toStrictEqual(RGBA.fromInts(1, 2, 3));
  expect(colons?.fg).toStrictEqual(RGBA.fromInts(4, 5, 6));
  expect(spaced?.fg).toStrictEqual(RGBA.fromInts(7, 8, 9));
  expect(indexed?.bg).toStrictEqual(RGBA.fromIndex(196));
});

test('an escape that is not SGR is left out, its text kept', () => {
  expect(
    runs('a\x1b]8;;https://example.com\x07link\x1b]8;;\x07\x1b[2Kb').map(
      (run) => run.text,
    ),
  ).toStrictEqual(['a', 'link', 'b']);
});

test("chalk's names stay the terminal's own colours, a hex its own", () => {
  expect(colour('redBright')).toStrictEqual(RGBA.fromIndex(9));
  expect(colour('gray')).toStrictEqual(RGBA.fromIndex(8));
  expect(colour('#ff8800')).toStrictEqual(RGBA.fromHex('#ff8800'));
  expect(colour(undefined)).toBeUndefined();
});

test("chalk's ansi256(n) is the terminal's colour n, not OpenTUI's magenta", () => {
  expect(colour('ansi256(196)')).toStrictEqual(RGBA.fromIndex(196));
  expect(colour('ansi256(43)')).toStrictEqual(RGBA.fromIndex(43));
});
