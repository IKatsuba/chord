import { expect, test } from 'bun:test';
import {
  initialBackground,
  reduceBackground,
} from '../../../src/ui/background/state.ts';

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
