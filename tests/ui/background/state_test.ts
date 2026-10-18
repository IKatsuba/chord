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

test("a stop's hint stays while the ❯ stays on its item, and goes once it moves or the view closes", () => {
  const a = { key: 1, id: 'a' };
  const open = reduceBackground(
    reduceBackground(initialBackground, { type: 'background_opened' }),
    { type: 'background_focused', focus: a },
  );
  const hinted = reduceBackground(open, {
    type: 'background_hinted',
    hint: 'could not stop: Session not found',
  });

  expect(hinted.backgroundView?.hint).toBe('could not stop: Session not found');
  expect(
    reduceBackground(hinted, { type: 'background_focused', focus: a })
      .backgroundView?.hint,
  ).toBe('could not stop: Session not found');
  expect(
    reduceBackground(hinted, {
      type: 'background_focused',
      focus: { key: 1, id: 'b' },
    }).backgroundView,
  ).toStrictEqual({ focus: { key: 1, id: 'b' } });
  expect(
    reduceBackground(hinted, { type: 'background_closed' }).backgroundView,
  ).toBe(undefined);
  // With the view closed there is nothing to say it on.
  expect(
    reduceBackground(initialBackground, {
      type: 'background_hinted',
      hint: 'x',
    }),
  ).toStrictEqual(initialBackground);
});
