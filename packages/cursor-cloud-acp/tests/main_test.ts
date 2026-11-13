import { afterEach, expect, spyOn, test } from 'bun:test';
import { main } from '../src/main.ts';

const stderr = spyOn(process.stderr, 'write').mockImplementation(() => true);

afterEach(() => stderr.mockClear());

// Only words that never reach the keychain or Cursor: a test runs none.
test.each<[readonly string[]]>([
  [['frob']],
  [['login', 'now']],
  [['status', '--json']],
  [['serve']],
])('%p is refused with the usage and status 2', async (args) => {
  expect(await main(args)).toBe(2);
  expect(stderr.mock.calls).toEqual([
    ['Usage: cursor-cloud-acp [login | logout | status]\n'],
  ]);
});
