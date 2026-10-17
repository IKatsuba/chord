import { afterEach, expect, jest, test } from 'bun:test';
import { startMatch } from '../../../src/ui/app/terminal.ts';
import type { WindowedAction } from '../../../src/ui/app/state.ts';
import { SLOW_MATCH_MS } from '../../../src/ui/prompt/state.ts';

const FILES = ['src/main.ts', 'src/ui/state.ts'];

/** A match held until the test lets it come back, with `found`. */
function held() {
  let release: (found: readonly string[] | undefined) => void = () => {};

  const match = () =>
    new Promise<readonly string[] | undefined>((resolve) => {
      release = resolve;
    });

  return { match, release: (found?: readonly string[]) => release(found) };
}

afterEach(() => {
  jest.useRealTimers();
});

test('a match running past 150 ms says so, and its result comes back by dispatch', async () => {
  jest.useFakeTimers({ now: 0 });

  const seen: WindowedAction[] = [];
  const { match, release } = held();

  startMatch(FILES, 'stt', (action) => seen.push(action), match);
  jest.advanceTimersByTime(SLOW_MATCH_MS - 1);
  expect(seen).toStrictEqual([]);
  jest.advanceTimersByTime(1);
  expect(seen).toStrictEqual([{ type: 'match_slow', query: 'stt' }]);

  release(['src/ui/state.ts']);
  await Promise.resolve();
  await Promise.resolve();
  expect(seen.at(-1)).toStrictEqual({
    type: 'files_matched',
    files: FILES,
    query: 'stt',
    matched: ['src/ui/state.ts'],
  });
});

test('a match back within 150 ms never says it is searching', async () => {
  jest.useFakeTimers({ now: 0 });

  const seen: WindowedAction[] = [];
  const { match, release } = held();

  startMatch(FILES, 'stt', (action) => seen.push(action), match);
  jest.advanceTimersByTime(100);
  release(['src/ui/state.ts']);
  await Promise.resolve();
  await Promise.resolve();
  jest.advanceTimersByTime(SLOW_MATCH_MS);
  expect(seen.map((action) => action.type)).toStrictEqual(['files_matched']);
});

test('a match a newer key took the place of drops its result and its marker', async () => {
  jest.useFakeTimers({ now: 0 });

  const seen: WindowedAction[] = [];
  const { match, release } = held();
  const stop = startMatch(FILES, 'st', (action) => seen.push(action), match);

  // The next key's match starts, and this one is let go.
  stop();
  jest.advanceTimersByTime(SLOW_MATCH_MS);
  release(['src/main.ts']);
  await Promise.resolve();
  await Promise.resolve();
  expect(seen).toStrictEqual([]);
});

test('a match fzf cancelled itself comes back as none and dispatches nothing', async () => {
  const seen: WindowedAction[] = [];
  const { match, release } = held();

  startMatch(FILES, 'st', (action) => seen.push(action), match);
  release(undefined);
  await Promise.resolve();
  await Promise.resolve();
  expect(seen).toStrictEqual([]);
});
