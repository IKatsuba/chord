import { expect, test } from 'bun:test';
import {
  anchorAt,
  indicator,
  initialScroll,
  pageRows,
  reduceScroll,
  rowsBelow,
  type Scroll,
  type ScrollAction,
  type ScrollStep,
  topOf,
} from '../../../src/ui/transcript/scroll.ts';

function measured(content: number, view: number, top?: number): ScrollAction {
  return {
    type: 'scroll_measured',
    content,
    view,
    ...(top === undefined ? {} : { top }),
  };
}

function after(scroll: Scroll, ...steps: ScrollStep[]): Scroll {
  return steps.reduce(
    (state, step) => reduceScroll(state, { type: 'scrolled', step }),
    scroll,
  );
}

/** The design's 120×40 mock: 90 rows of transcript in a 33-row area. */
const tall = reduceScroll(initialScroll, measured(90, 33));

/** The text of the indicator, without its colours. */
function rule(scroll: Scroll, width: number): string {
  return indicator(scroll, width, 'end')
    .map(({ text }) => text)
    .join('');
}

test('a page is the view less two rows', () => {
  expect(pageRows(tall)).toStrictEqual(31);
  expect(pageRows(reduceScroll(initialScroll, measured(90, 2)))).toStrictEqual(
    1,
  );
});

test('the view follows the bottom until a key moves it up', () => {
  expect(tall.following).toStrictEqual(true);
  expect(rowsBelow(tall)).toStrictEqual(undefined);

  const back = after(tall, 'page_up');

  expect(back.following).toStrictEqual(false);
  // Rows 27 to 58 show, and the rule covers row 59.
  expect(back.top).toStrictEqual(26);
  expect(rowsBelow(back)).toStrictEqual(32);
  expect(after(tall, 'line_up').top).toStrictEqual(56);
  expect(after(tall, 'top').top).toStrictEqual(0);
});

test('new rows below do not move the view, and count as below', () => {
  const back = after(tall, 'page_up');
  const grown = reduceScroll(back, measured(130, 33));

  expect(grown.top).toStrictEqual(26);
  expect(rowsBelow(grown)).toStrictEqual(72);
  // While following, growing changes nothing but the size.
  expect(reduceScroll(tall, measured(130, 33)).following).toStrictEqual(true);
});

test('the way back down follows again once it reaches the bottom', () => {
  const back = after(tall, 'page_up', 'page_up');

  expect(after(back, 'page_down').following).toStrictEqual(false);
  expect(after(back, 'page_down', 'page_down').following).toStrictEqual(true);
  expect(after(tall, 'line_up', 'line_down').following).toStrictEqual(true);
  expect(after(tall, 'top', 'bottom').following).toStrictEqual(true);
  // Down from the bottom is nothing.
  expect(after(tall, 'page_down')).toStrictEqual(tall);
});

test('up at the top, or with nothing to scroll, does nothing', () => {
  const top = after(tall, 'top');

  expect(after(top, 'line_up')).toStrictEqual(top);
  expect(after(top, 'page_up')).toStrictEqual(top);

  const short = reduceScroll(initialScroll, measured(10, 33));

  for (const step of ['page_up', 'line_up', 'top'] as const) {
    expect(after(short, step)).toStrictEqual(short);
  }
});

test('a view that comes to fit everything follows again', () => {
  const back = { ...after(tall, 'page_up'), news: true };
  const fits = reduceScroll(back, measured(30, 33));

  expect(fits.following).toStrictEqual(true);
  expect(fits.news).toStrictEqual(false);
});

test('a relayout keeps the row it is given, within the transcript', () => {
  const back = after(tall, 'page_up');

  expect(reduceScroll(back, measured(100, 33, 40)).top).toStrictEqual(40);
  expect(reduceScroll(back, measured(50, 33, 40)).top).toStrictEqual(17);
  // A shorter transcript pulls the view down only as far as its bottom.
  expect(reduceScroll(back, measured(50, 33)).top).toStrictEqual(17);
  // Nothing measured differently is the same state.
  expect(reduceScroll(back, measured(90, 33))).toStrictEqual(back);
});

test('the bottom clears the news', () => {
  const back = { ...after(tall, 'page_up'), news: true };

  expect(after(back, 'bottom').news).toStrictEqual(false);
});

test('the rule says how much is below, and the key back', () => {
  const back = after(tall, 'page_up');

  expect(rule(back, 78)).toStrictEqual(
    '── ↓ 32 lines below · end to jump to the bottom ' + '─'.repeat(30),
  );
  expect(indicator(tall, 78, 'end')).toStrictEqual([]);
  expect(rule({ ...back, top: 57 }, 30)).toStrictEqual(
    '── ↓ 1 line below ' + '─'.repeat(12),
  );
});

test('the rule names new output in words and in the accent', () => {
  const back = { ...after(tall, 'page_up'), news: true };
  const segments = indicator(back, 118, 'end');

  expect(segments.map(({ accent }) => accent)).toStrictEqual([
    false,
    true,
    false,
  ]);
  expect(segments[1]!.text).toStrictEqual('↓ new output');
  expect(
    segments
      .map(({ text }) => text)
      .join('')
      .slice(0, 64),
  ).toStrictEqual(
    '── ↓ new output · 32 lines below · end to jump to the bottom ───',
  );
  expect(segments.map(({ text }) => text).join('').length).toStrictEqual(118);
});

test('a narrow rule drops the key before the count', () => {
  const back = { ...after(tall, 'page_up'), news: true };

  expect(rule(back, 40)).toStrictEqual(
    '── ↓ new output · 32 lines below ' + '─'.repeat(7),
  );
});

test('an anchor is the entry a row falls in, and how far in', () => {
  const entries = [
    { top: 0, height: 2 },
    { top: 2, height: 10 },
    { top: 12, height: 3 },
  ];

  expect(anchorAt(0, entries)).toStrictEqual({ entry: 0, within: 0 });
  expect(anchorAt(5, entries)).toStrictEqual({ entry: 1, within: 3 });
  expect(anchorAt(14, entries)).toStrictEqual({ entry: 2, within: 2 });
  expect(anchorAt(3, [])).toStrictEqual(undefined);

  // The entry has moved down and folded to one row.
  const relaid = [
    { top: 0, height: 4 },
    { top: 4, height: 1 },
    { top: 5, height: 3 },
  ];

  expect(topOf({ entry: 1, within: 3 }, relaid)).toStrictEqual(4);
  expect(topOf({ entry: 2, within: 2 }, relaid)).toStrictEqual(7);
  expect(topOf({ entry: 3, within: 0 }, relaid)).toStrictEqual(undefined);
});

test('a drag holds a following view where it is, and the bottom follows again (CHD-172)', () => {
  const following: Scroll = { ...initialScroll, content: 100, view: 20 };
  const held = reduceScroll(following, { type: 'scroll_held' });

  expect(held).toStrictEqual({ ...following, following: false, top: 80 });
  // New output measured under the drag leaves the view where it was.
  expect(reduceScroll(held, measured(130, 20)).top).toBe(80);
  expect(after(held, 'bottom').following).toBe(true);
  // A view scrolled back, or one that fits, is left as it is.
  expect(reduceScroll(held, { type: 'scroll_held' })).toBe(held);

  const short: Scroll = { ...initialScroll, content: 10, view: 20 };

  expect(reduceScroll(short, { type: 'scroll_held' })).toBe(short);
});
