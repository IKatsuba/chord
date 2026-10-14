import { expect, test } from 'bun:test';
import { formatElapsed } from '../../src/session/elapsed.ts';

test('elapsed time reads as seconds, then minutes, then hours', () => {
  expect(formatElapsed(-5)).toStrictEqual('0s');
  expect(formatElapsed(12_999)).toStrictEqual('12s');
  expect(formatElapsed(65_000)).toStrictEqual('1m 5s');
  expect(formatElapsed(3_725_000)).toStrictEqual('1h 2m');
});
