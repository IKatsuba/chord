import { describe, expect, test } from 'bun:test';
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

describe('CHD-468 tester: caught-log isolation and pass-through', () => {
  test('two pending errors with the same message are consumed independently', () => {
    const { calls, log } = logged();
    const first = new Error('same message');
    const second = new Error('same message');
    const info = { componentStack: 'details' };

    caughtByBoundary(first);
    caughtByBoundary(second);
    log(second, info);
    log(first, info);
    expect(calls).toStrictEqual([]);
    log(first, info);
    log(second, info);
    expect(calls).toHaveLength(2);
    expect(calls[0]?.[0]).toBe(first);
    expect(calls[1]?.[0]).toBe(second);
    expect(calls[0]?.[1]).toBe(info);
  });

  for (const value of [undefined, null, false, 0, '']) {
    test(`a caught ${String(value)} suppresses one matching argument, not an empty call`, () => {
      const { calls, log } = logged();

      caughtByBoundary(value);
      log();
      log(value, 'caught');
      expect(calls).toStrictEqual([[]]);
      log(value, 'later');
      expect(calls).toStrictEqual([[], [value, 'later']]);
    });
  }

  test('catching the same object again rearms only its next matching log', () => {
    const { calls, log } = logged();
    const error = new Error('caught twice');

    for (let turn = 0; turn < 2; turn++) {
      caughtByBoundary(error);
      log(error, 'caught');
      log(error, 'later');
    }

    expect(calls).toStrictEqual([
      [error, 'later'],
      [error, 'later'],
    ]);
  });

  test('an unrelated logger failure propagates without consuming a pending error', () => {
    const pending = new Error('pending');
    const failure = new Error('logger failed');
    const log = quietCaught(() => {
      throw failure;
    });

    caughtByBoundary(pending);
    expect(() => log('unrelated')).toThrow(failure);
    expect(() => log(pending)).not.toThrow();
    expect(() => log(pending)).toThrow(failure);
  });
});
