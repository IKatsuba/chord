/**
 * A reply in the window as a person copies it: what OpenTUI wrapped joins
 * again in the copy, at any width (CHD-396).
 */
import { expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import { left, send, withWindow, type Window } from '../app/render.tsx';

const HEADING =
  'A heading long enough that at eighty columns it has to wrap onto a second row of its own';

const QUOTE =
  'A quote whose paragraph is long enough to wrap inside its bar at eighty columns, and at a hundred and twenty too, once it runs on.';

/**
 * What a drag copies from the first cell of `first` to the end of `last`,
 * the rows a block starts and ends on.
 */
async function drag(
  window: Window,
  first: string,
  last: string,
): Promise<string> {
  const rows = stripAnsi(window.frame()).split('\n');
  const from = rows.findIndex((row) => row.includes(first));
  const to = rows.findIndex((row) => row.includes(last));
  const end = rows[to]!.indexOf(last) + last.length;

  await window.press(left(rows[from]!.indexOf(first), from, 'down'));

  for (let y = from + 1; y < to; y++) {
    await window.press(left(3, y, 'drag'));
  }

  await window.press(left(end, to, 'drag'));
  await window.press(left(end, to, 'up'));

  return window.selected();
}

for (const columns of [80, 120]) {
  test(`a wrapped heading and quote copy as one line each at ${columns} columns`, () =>
    withWindow(
      async (window) => {
        await send(window, 'markdownwrap');
        await window.shows('break here.');

        // At 80 columns both wrap: the copy is the same as at 120.
        expect(await drag(window, 'A heading long', 'its own')).toStrictEqual(
          HEADING,
        );
        expect(await drag(window, 'A quote whose', 'runs on.')).toStrictEqual(
          QUOTE,
        );
      },
      { columns, rows: 40 },
    ));
}
