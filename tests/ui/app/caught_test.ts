import { expect, test } from 'bun:test';
import { caughtByBoundary, quietCaught } from '../../../src/ui/app/caught.ts';

/** `quietCaught` over a log that keeps what reaches it. */
function logged() {
  const calls: unknown[][] = [];

  return { calls, log: quietCaught((...data) => calls.push(data)) };
}

test("React's one log of the error the boundary caught is dropped, and its next goes through (CHD-468)", () => {
  const { calls, log } = logged();
  const caught = new Error('the window broke');
  const info = { componentStack: '\n    at Throws' };

  caughtByBoundary(caught);
  log(caught, info);
  expect(calls).toStrictEqual([]);
  log(caught, info);
  expect(calls).toStrictEqual([[caught, info]]);
});

test('another error, the same message in another error, and any other call pass through unchanged (CHD-468)', () => {
  const { calls, log } = logged();
  const caught = new Error('the window broke');
  const twin = new Error('the window broke');
  const other = new Error('a session failed');

  caughtByBoundary(caught);
  log(twin);
  log(other, 'and more');
  log('a message about', caught);
  log();
  expect(calls).toStrictEqual([
    [twin],
    [other, 'and more'],
    ['a message about', caught],
    [],
  ]);
  // Still marked: only a call that leads with it is dropped.
  log(caught);
  expect(calls).toHaveLength(4);
});

test('a thrown value that is no Error is matched as itself (CHD-468)', () => {
  const { calls, log } = logged();

  caughtByBoundary('gone');
  log('gone', {});
  log('gone');
  expect(calls).toStrictEqual([['gone']]);
});
