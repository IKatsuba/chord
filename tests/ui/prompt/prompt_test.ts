import { expect, test } from 'bun:test';
import {
  continued,
  endOf,
  gutterMark,
  promptRows,
  type Row,
  shownRows,
} from '../../../src/ui/prompt/prompt.ts';

test('Enter after a \\ breaks the line there instead of sending', () => {
  expect(continued('one \\', [0, 5])).toStrictEqual({
    text: 'one \n',
    cursor: [1, 0],
  });
  // Mid-text and on a later line, the rest moves down with the cursor.
  expect(continued('a\nb\\c', [1, 2])).toStrictEqual({
    text: 'a\nb\nc',
    cursor: [2, 0],
  });
});

test('Enter anywhere but after a \\ sends', () => {
  expect(continued('one', [0, 3])).toStrictEqual(undefined);
  expect(continued('a \\ b', [0, 5])).toStrictEqual(undefined);
  expect(continued('\\', [0, 0])).toStrictEqual(undefined);
  expect(continued('', [0, 0])).toStrictEqual(undefined);
  expect(continued('a', [3, 0])).toStrictEqual(undefined);
});

test('a recalled prompt puts the cursor at its end', () => {
  expect(endOf('')).toStrictEqual([0, 0]);
  expect(endOf('one')).toStrictEqual([0, 3]);
  expect(endOf('one\ntwo!\n')).toStrictEqual([2, 0]);
});

test('the box grows to a third of the window, between 3 and 10 rows', () => {
  expect(promptRows(24)).toStrictEqual(8);
  expect(promptRows(40)).toStrictEqual(10);
  expect(promptRows(6)).toStrictEqual(3);
});

const row = (line: number, piece = 0, last = false): Row => ({
  line,
  piece,
  last,
});

test('› marks the row where the prompt starts and no other', () => {
  const shown = [row(0), row(0, 1), row(1, 0, true)];

  expect(shown.map((it) => gutterMark(it, shown))).toStrictEqual(['›', '', '']);
});

test('a scrolled box marks the rows hidden above and below it', () => {
  // Rows 3 to 5 of a seven-line prompt.
  const middle = [row(3), row(4), row(5)];

  expect(middle.map((it) => gutterMark(it, middle))).toStrictEqual([
    '↑',
    '',
    '↓',
  ]);

  // Scrolled to the end, where nothing is hidden below.
  const end = [row(4), row(5), row(6, 0, true)];

  expect(end.map((it) => gutterMark(it, end))).toStrictEqual(['↑', '', '']);

  // Scrolled into the wrapped first line: the prompt's start is out of sight.
  const wrapped = [row(0, 1), row(1), row(2)];

  expect(wrapped.map((it) => gutterMark(it, wrapped))).toStrictEqual([
    '↑',
    '',
    '↓',
  ]);
});

test('the rows shown are those from the top the box is scrolled to', () => {
  // Six lines, the second wrapped in two, four rows high, scrolled by three.
  const sources = [0, 1, 1, 2, 3, 4, 5];
  const wraps = [0, 0, 1, 0, 0, 0, 0];

  expect(shownRows(sources, wraps, 3, 4)).toStrictEqual([
    row(2),
    row(3),
    row(4),
    row(5, 0, true),
  ]);
  expect(shownRows(sources, wraps, 0, 4)).toStrictEqual([
    row(0),
    row(1),
    row(1, 1),
    row(2),
  ]);
  // An empty box still has its first row.
  expect(shownRows([], [], 0, 3)).toStrictEqual([row(0, 0, true)]);
});
