import { afterEach, describe, expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readRecords } from '../../../src/session/sessions.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  quitAll,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from './render.tsx';
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

describe("the terminal is told the main session's id to resume (CHD-492)", () => {
  const VAR = '\x1b]1337;SetUserVar=chord_session=';

  /** Every value the terminal was told, in order, decoded. */
  const told = (window: Window): string[] => {
    const all = window.written().join('');
    const values: string[] = [];

    for (let at = all.indexOf(VAR); at >= 0; at = all.indexOf(VAR, at + 1)) {
      const end = all.indexOf('\x07', at);

      values.push(
        Buffer.from(all.slice(at + VAR.length, end), 'base64').toString(),
      );
    }

    return values;
  };

  const last = (window: Window) => told(window).at(-1);

  test('empty at the start; the id once the first prompt is in the record, said once; unchanged as the agent exits and as chord quits', async () => {
    const stateDir = await mkdtemp(join(tmpdir(), 'chord-state-'));

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          expect(told(window)).toStrictEqual(['']);

          const id = window.session()?.id;

          assert(id !== undefined);
          await send(window, 'text');
          await until('the id', () => last(window) === id);

          // Told only once its prompt is in the record --resume reads.
          const record = (await readRecords(stateDir)).find(
            (each) => each.sessionId === id,
          );

          expect(record?.prompt).toStrictEqual('text');
          await window.shows('came in chunks.');
          await send(window, 'text');
          await until(
            'the second reply',
            () => window.frame().split('came in chunks.').length === 3,
          );
          // An equal value is not said again.
          expect(told(window)).toStrictEqual(['', id]);
          await send(window, 'crash');
          await window.shows('The agent exited');
          expect(told(window)).toStrictEqual(['', id]);
          await quitAll(window);
          expect(told(window)).toStrictEqual(['', id]);
        },
        { stateDir },
      );
    } finally {
      await rm(stateDir, { recursive: true, force: true });
    }
  });

  test('/clear empties it at once and says the new id after its first prompt; a /resume pick says the picked id', () =>
    withWindow(
      async (window) => {
        await ready(window);

        const first = window.session()?.id;

        assert(first !== undefined);
        await send(window, 'text');
        await until('the first id', () => last(window) === first);
        await send(window, '/clear');
        await until('emptied', () => last(window) === '');

        await until(
          'the new session',
          () => ![undefined, first].includes(window.session()?.id),
        );

        const second = window.session()?.id;

        assert(second !== undefined);
        // Nothing to resume until its first prompt.
        expect(last(window)).toStrictEqual('');
        await send(window, 'text');
        await until('the new id', () => last(window) === second);
        await window.type('/resume');
        await window.press('\r');
        await window.shows('Resume a session');
        await window.press('\r');
        await until('the picked id', () => last(window) === first);
      },
      { columns: 120, rows: 40 },
    ));

  test('a window that starts on a resumed session says its id once it is open, with no prompt sent', async () => {
    const stateDir = await mkdtemp(join(tmpdir(), 'chord-state-'));
    const cwd = await mkdtemp(join(tmpdir(), 'chord-cwd-'));
    let id: string | undefined;

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          id = window.session()?.id;

          await send(window, 'text');
          await window.shows('came in chunks.');
        },
        { stateDir },
      );

      const record = (await readRecords(stateDir)).find(
        (each) => each.sessionId === id,
      );

      assert(id !== undefined && record !== undefined);

      const resumed = id;
      const start = { agentCommand: fakeAgentCommand() };

      await withWindow(
        async (window) => {
          await until('the resumed id', () => last(window) === resumed);
          expect(told(window).filter((value) => value !== '')).toStrictEqual([
            resumed,
          ]);
        },
        {
          stateDir,
          resumes: [
            {
              agent: 'fake',
              resume: { sessionId: resumed, cwd, record: record.path },
              place: {
                cwd,
                startupOf: () => start,
                mcpServers: [],
                mcpIgnored: [],
              },
            },
          ],
        },
      );
    } finally {
      await rm(stateDir, { recursive: true, force: true });
      await rm(cwd, { recursive: true, force: true });
    }
  });
});
