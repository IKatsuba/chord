import { expect, test } from 'bun:test';
import {
  initialBackground,
  reduceBackground,
} from '../../../src/ui/background/state.ts';
import {
  frontState,
  initialAppState,
  reduceWindowed,
  windowed,
  type WindowedAction,
} from '../../../src/ui/app/state.ts';

test("the person's prompt in a tab marks when its ended items were cleared, each tab its own", () => {
  const once = reduceBackground(initialBackground, {
    type: 'background_cleared',
    tab: 1,
    at: 100,
  });
  const twice = reduceBackground(once, {
    type: 'background_cleared',
    tab: 2,
    at: 200,
  });

  expect(twice.backgroundCleared).toStrictEqual({ 1: 100, 2: 200 });
  expect(
    reduceBackground(twice, { type: 'background_cleared', tab: 1, at: 300 })
      .backgroundCleared,
  ).toStrictEqual({ 1: 300, 2: 200 });
});

test("another tab's /clear leaves each tab's clearing as it was, so no ended item comes back", () => {
  const both = (
    [
      { type: 'session_opened', key: 2 },
      { type: 'background_cleared', tab: 1, at: 100 },
      { type: 'background_cleared', tab: 2, at: 200 },
      { type: 'in_session', key: 2, action: { type: 'cleared' } },
    ] satisfies WindowedAction[]
  ).reduce(reduceWindowed, windowed(initialAppState, 1));

  expect(frontState(both).backgroundCleared).toStrictEqual({ 1: 100, 2: 200 });
});

test("a stop's hint is said only for the stop x last asked for, while the ❯ has stayed on its row since", () => {
  const a = { key: 1, id: 'a' };
  const b = { key: 1, id: 'b' };
  const hint = 'could not stop: Session not found';
  const run = (...actions: Parameters<typeof reduceBackground>[1][]) =>
    actions.reduce(reduceBackground, initialBackground).backgroundView;
  const asked = (token: string) =>
    ({ type: 'background_stop_asked', focus: a, token }) as const;
  const refused = (token: string) =>
    ({ type: 'background_hinted', token, hint }) as const;
  const opened = [
    { type: 'background_opened' },
    { type: 'background_focused', focus: a },
    asked('t1'),
  ] as const;

  expect(run(...opened, refused('t1'))?.hint).toBe(hint);
  // Kept while the ❯ stays; gone once it moves.
  expect(
    run(...opened, refused('t1'), { type: 'background_focused', focus: a })
      ?.hint,
  ).toBe(hint);
  expect(
    run(...opened, refused('t1'), { type: 'background_focused', focus: b }),
  ).toStrictEqual({ focus: b });
  // An answer after the ❯ left, even if it came back, or after the view
  // closed and opened again, is not said.
  expect(
    run(
      ...opened,
      { type: 'background_focused', focus: b },
      { type: 'background_focused', focus: a },
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  expect(
    run(
      ...opened,
      { type: 'background_closed' },
      { type: 'background_opened' },
      { type: 'background_focused', focus: a },
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  // Nor is an earlier stop's once a later one on the same row was asked.
  expect(
    run(
      ...opened,
      { type: 'background_focused', focus: b },
      { type: 'background_focused', focus: a },
      asked('t2'),
      refused('t1'),
    )?.hint,
  ).toBe(undefined);
  expect(run(refused('t1'))).toBe(undefined);
});
