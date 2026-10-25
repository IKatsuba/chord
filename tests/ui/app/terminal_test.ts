import { afterEach, describe, expect, jest, test } from 'bun:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { createElement } from 'react';
import { draw } from '../harness.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CTRL_D,
  CTRL_G,
  DOWN,
  quitAll,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from './render.tsx';
import {
  type SelectionHandle,
  startMatch,
  useSelection,
  useSessionVar,
} from '../../../src/ui/app/terminal.ts';
import type { Copy } from '../../../src/ui/app/selection.ts';
import type { ClipboardWriteResult } from '@opentui/core';
import {
  initialAppState,
  type WindowedAction,
} from '../../../src/ui/app/state.ts';
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
          resume: { sessionId: resumed, cwd, record: record.path },
          startupOf: () => start,
        },
      );
    } finally {
      await rm(stateDir, { recursive: true, force: true });
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test('a quit keeps it while the agent is still closing, and after', () => {
    const { promise: heldClose, resolve: release } =
      Promise.withResolvers<void>();

    let id: string | undefined;

    return withWindow(
      async (window) => {
        try {
          await ready(window);

          id = window.session()?.id;

          assert(id !== undefined);
          await send(window, 'text');
          await until('the id', () => last(window) === id);
          await window.press(CTRL_D);
          await window.shows('Stopping fake…');
          await new Promise((resolve) => setTimeout(resolve, 300));
          expect(told(window)).toStrictEqual(['', id]);
        } finally {
          release();
        }

        await until(
          'the agent to stop',
          () => window.session()?.agentPids.size === 0,
        );
        expect(told(window)).toStrictEqual(['', id]);
      },
      { heldClose },
    );
  });

  test("a child picked and prompted leaves it the main session's; the editor leaves it too", async () => {
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;

    server.admit = (caller) => {
      if (caller.role === 'person') {
        main = caller;
      }

      return admit(caller);
    };

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          const id = window.session()?.id;

          assert(id !== undefined);
          await send(window, 'text');
          await until('the id', () => last(window) === id);
          assert(main !== undefined);
          await main.window.open(main.key, {
            agent: 'fake',
            name: 'helper',
            prompt: 'text',
          });
          await window.shows('helper');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ helper ─');
          await window.shows('? for shortcuts');
          await send(window, 'text');
          await until(
            "the child's reply",
            () => window.frame().split('came in chunks.').length >= 3,
          );
          await window.press(CTRL_G);
          await window.shows('from the editor');
          expect(told(window)).toStrictEqual(['', id]);
        },
        {
          server,
          editor: (draft) =>
            Promise.resolve({ text: `${draft}from the editor` }),
        },
      );
    } finally {
      await server.close();
    }
  });

  test('a record that cannot be written holds nothing back: the id goes once the write has failed', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-state-'));
    // A file where the state directory should be: no record can go in it.
    const stateDir = join(dir, 'state');

    await writeFile(stateDir, '');

    try {
      await withWindow(
        async (window) => {
          await ready(window);

          const id = window.session()?.id;

          await send(window, 'text');
          await window.shows("Could not keep this session's record");
          await until('the id', () => last(window) === id);
        },
        { stateDir },
      );
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  test('a session opened again with no record and nothing replayed says its id once it is open', async () => {
    const cwd = await mkdtemp(join(tmpdir(), 'chord-cwd-'));
    const id = crypto.randomUUID();
    // An agent that resumes, and cannot load, so nothing is replayed.
    const start = {
      agentCommand: fakeAgentCommand(undefined, '--resume-only', '--no-load'),
    };

    try {
      await withWindow(
        async (window) => {
          await until('the id', () => last(window) === id);
        },
        {
          resume: { sessionId: id, cwd },
          startupOf: () => start,
        },
      );
    } finally {
      await rm(cwd, { recursive: true, force: true });
    }
  });

  test('the hook says an id only once its prompt is recorded, a later value overtaking a write still held, and none again for an equal one', async () => {
    let tell: ReturnType<typeof useSessionVar> = () => {};

    const Probe = () => {
      tell = useSessionVar(false);

      return createElement('text', null, 'x');
    };

    const drawn = await draw(createElement(Probe));
    const sent = () =>
      drawn
        .written()
        .join('')
        .split(VAR)
        .slice(1)
        .map((value) =>
          Buffer.from(
            value.slice(0, value.indexOf('\x07')),
            'base64',
          ).toString(),
        );
    const settle = () => new Promise((resolve) => setTimeout(resolve, 50));

    try {
      const flushing = Promise.withResolvers<void>();

      tell(undefined, Promise.resolve());
      await settle();
      expect(sent()).toStrictEqual(['']);

      // Held: its line is not in the record yet.
      tell('a', flushing.promise);
      await settle();
      expect(sent()).toStrictEqual(['']);
      flushing.resolve();
      await settle();
      expect(sent()).toStrictEqual(['', 'a']);

      tell('a', Promise.resolve());
      await settle();
      expect(sent()).toStrictEqual(['', 'a']);

      // A write still held is overtaken by none, and says nothing after.
      const late = Promise.withResolvers<void>();

      tell('b', late.promise);
      tell(undefined, Promise.resolve());
      late.resolve();
      await settle();
      expect(sent()).toStrictEqual(['', 'a', '']);
    } finally {
      await drawn.unmount();
    }
  });
});

describe('CHD-492 U2 tester: cancelled turns and unprompted clears', () => {
  const values = (window: Window) =>
    window
      .written()
      .join('')
      .split('\x1b]1337;SetUserVar=chord_session=')
      .slice(1)
      .map((value) =>
        Buffer.from(value.slice(0, value.indexOf('\x07')), 'base64').toString(
          'utf8',
        ),
      );

  for (const columns of [80, 120]) {
    test(`a cancelled first turn retains its id and two unprompted clears stay empty at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);

          const original = window.session()?.id;

          assert(original !== undefined);
          expect(values(window)).toStrictEqual(['']);
          await send(window, 'slow');
          await window.shows('esc to interrupt');
          await until(
            'cancelled turn id published',
            () => values(window).at(-1) === original,
          );
          await window.press('\x1b');
          await window.shows('Interrupted by user');
          expect(values(window)).toStrictEqual(['', original]);

          let previous = original;

          for (let n = 0; n < 2; n++) {
            await send(window, '/clear');
            await until('a new unprompted session', () => {
              const id = window.session()?.id;

              return id !== undefined && id !== previous;
            });

            await ready(window);

            previous = window.session()!.id;

            await until(
              'the clear published',
              () => values(window).at(-1) === '',
            );
            expect(values(window)).toStrictEqual(['', original, '']);
          }

          await send(window, 'text');
          await until(
            'only the prompted new id published',
            () => values(window).at(-1) === previous,
          );
          await window.shows('came in chunks.');
          expect(values(window)).toStrictEqual(['', original, '', previous]);
        },
        { columns, rows: columns === 80 ? 24 : 40 },
      ));
  }
});

describe("a code block's copy goes the selection's way (CHD-394)", () => {
  test('its text is written as given, one copy at a time, a newer one superseding it, and nothing with no write', async () => {
    const written: string[] = [];
    const answers: ((result: ClipboardWriteResult) => void)[] = [];
    const copy: Copy = (text) => {
      written.push(text);

      return new Promise((resolve) => answers.push(resolve));
    };

    let handle: SelectionHandle | undefined;
    let without: SelectionHandle | undefined;

    const Probe = () => {
      handle = useSelection({
        state: initialAppState,
        dispatch: () => {},
        copy,
        copyOnSelect: false,
        size: '80x24',
      });
      without = useSelection({
        state: initialAppState,
        dispatch: () => {},
        copy: undefined,
        copyOnSelect: false,
        size: '80x24',
      });

      return createElement('text', null, 'x');
    };

    const drawn = await draw(createElement(Probe));
    const host = (status: 'written') =>
      ({
        host: { status },
        terminal: { status: 'skipped' },
      }) as unknown as ClipboardWriteResult;

    try {
      assert(handle !== undefined && without !== undefined);

      const first = handle.copyText('bun test\n');
      const second = handle.copyText('echo hi');

      expect(written).toStrictEqual(['bun test\n', 'echo hi']);
      answers[0]!(host('written'));
      answers[1]!(host('written'));
      expect(await first).toBeUndefined();
      expect(await second).toStrictEqual({ kind: 'copied', chars: 7 });
      expect(await without.copyText('echo hi')).toBeUndefined();
      expect(await handle.copyText('')).toBeUndefined();
      expect(written).toHaveLength(2);
    } finally {
      drawn.unmount();
    }
  });
});

describe('CHD-394 U1 tester: block copy outcomes', () => {
  test('whitespace and Unicode are preserved, terminal-only writes and rejected writes return the shared feedback without dispatch', async () => {
    const writes: string[] = [];
    const actions: WindowedAction[] = [];
    let handle: SelectionHandle | undefined;
    let outcome: 'terminal' | 'throw' = 'terminal';
    const copy: Copy = (text) => {
      writes.push(text);

      if (outcome === 'throw') {
        throw new Error('clipboard\nnot available');
      }

      return Promise.resolve({
        host: { status: 'failed', error: 'no host clipboard' },
        terminal: { status: 'attempted' },
      } as unknown as ClipboardWriteResult);
    };

    const Probe = () => {
      handle = useSelection({
        state: initialAppState,
        dispatch: (action) => actions.push(action),
        copy,
        copyOnSelect: false,
        size: '80x24',
      });

      return createElement('text', null, 'copy');
    };

    const screen = await draw(createElement(Probe));

    try {
      assert(handle !== undefined);

      actions.length = 0;

      expect(await handle.copyText('é👍🏽\n')).toStrictEqual({
        kind: 'sent',
        chars: 3,
      });
      expect(await handle.copyText(' \n')).toStrictEqual({
        kind: 'sent',
        chars: 2,
      });

      outcome = 'throw';

      expect(await handle.copyText('echo hi')).toStrictEqual({
        kind: 'failed',
        reason: 'clipboard not available',
      });
      expect(writes).toStrictEqual(['é👍🏽\n', ' \n', 'echo hi']);
      expect(actions).toStrictEqual([]);
    } finally {
      await screen.unmount();
    }
  });

  test('unmount aborts an outstanding block copy and its late completion is silent', async () => {
    const response = Promise.withResolvers<ClipboardWriteResult>();
    let signal: AbortSignal | undefined;
    let handle: SelectionHandle | undefined;
    const Probe = () => {
      handle = useSelection({
        state: initialAppState,
        dispatch: () => {},
        copy: (_text, abort) => {
          signal = abort;

          return response.promise;
        },
        copyOnSelect: false,
        size: '80x24',
      });

      return createElement('text', null, 'copy');
    };

    const screen = await draw(createElement(Probe));

    assert(handle !== undefined);

    const pending = handle.copyText('echo late');

    await screen.unmount();
    expect(signal?.aborted).toBe(true);
    response.resolve({
      host: { status: 'written' },
      terminal: { status: 'skipped' },
    } as unknown as ClipboardWriteResult);
    expect(await pending).toBeUndefined();
    expect(await handle.copyText('after close')).toBeUndefined();
  });
});

describe("a code block's copy says what came of it (CHD-394)", () => {
  test('it starts by taking over a selection copy, then notes its own result; one taken over by a later says nothing', async () => {
    const answers: ((result: ClipboardWriteResult) => void)[] = [];
    const copy: Copy = () => new Promise((resolve) => answers.push(resolve));
    const seen: WindowedAction[] = [];
    let handle: SelectionHandle | undefined;

    const Probe = () => {
      handle = useSelection({
        state: initialAppState,
        dispatch: (action) => seen.push(action),
        copy,
        copyOnSelect: false,
        size: '80x24',
      });

      return createElement('text', null, 'x');
    };

    const drawn = await draw(createElement(Probe));
    const written = {
      host: { status: 'written' },
      terminal: { status: 'skipped' },
    } as unknown as ClipboardWriteResult;

    try {
      assert(handle !== undefined);
      handle.copyBlock('bun test');
      handle.copyBlock('echo hi');
      answers[0]!(written);
      answers[1]!(written);
      await until(
        'the second note',
        () => seen.filter((a) => a.type === 'block_copy_noted').length > 0,
      );

      expect(seen).toStrictEqual([
        { type: 'block_copy_started' },
        { type: 'block_copy_started' },
        {
          type: 'block_copy_noted',
          result: { kind: 'copied', chars: 7 },
        },
      ]);
      handle.copyBlock('');
      expect(seen).toHaveLength(3);
    } finally {
      drawn.unmount();
    }
  });
});

describe('CHD-394 U3 tester: delayed copy replacement', () => {
  test('a block aborts an older clipboard write and its late failure cannot overwrite the block note', async () => {
    const first = Promise.withResolvers<ClipboardWriteResult>();
    const second = Promise.withResolvers<ClipboardWriteResult>();
    const signals: AbortSignal[] = [];
    const events: WindowedAction[] = [];
    let handle: SelectionHandle | undefined;
    const copy: Copy = (_text, signal) => {
      signals.push(signal);

      return signals.length === 1 ? first.promise : second.promise;
    };

    const Probe = () => {
      handle = useSelection({
        state: initialAppState,
        dispatch: (action) => events.push(action),
        copy,
        copyOnSelect: false,
        size: '80x24',
      });

      return createElement('text', null, 'copy');
    };

    const screen = await draw(createElement(Probe));

    try {
      assert(handle !== undefined);

      const old = handle.copyText('old selection');

      handle.copyBlock('echo new');
      expect(signals[0]?.aborted).toBe(true);
      expect(signals[1]?.aborted).toBe(false);
      second.resolve({
        host: { status: 'written' },
        terminal: { status: 'skipped' },
      } as unknown as ClipboardWriteResult);
      await until('the block copy completes', () =>
        events.some((event) => event.type === 'block_copy_noted'),
      );
      first.reject(new Error('late old failure'));
      expect(await old).toBeUndefined();
      expect(events).toStrictEqual([
        { type: 'block_copy_started' },
        { type: 'block_copy_noted', result: { kind: 'copied', chars: 8 } },
      ]);
    } finally {
      await screen.unmount();
    }
  });
});
