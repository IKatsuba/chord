/**
 * The window resumed: past sessions drawn and answered in, models read where
 * a session works, and what a click gives the keys.
 */
import { describe, expect, test } from 'bun:test';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { draw } from '../harness.tsx';
import { openSession, type Session } from '../../../src/session/session.ts';
import { readRecords } from '../../../src/session/sessions.ts';
import { serveChord } from '../../../src/server/server.ts';
import { App } from '../../../src/ui/app/App.tsx';
import { terminalOptions } from '../../../src/ui/app/renderer.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_D,
  CTRL_R,
  ESC,
  leader,
  left,
  promptRow,
  ready,
  send,
  until,
  type Window,
  withWindow,
} from './render.tsx';

test('a resumed session draws its past, answers in the same session, and is named on quit', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const stateDir = join(dir, 'state');
  const sessions: Session[] = [];
  let quitWith: string[] | undefined;
  const id = crypto.randomUUID();
  // An id chord has no record of: the fake agent loads it and replays.
  const app = await draw(
    <App
      agent='fake'
      cwd={dir}
      stateDir={stateDir}
      agentCommand={fakeAgentCommand()}
      resume={{ sessionId: id, cwd: dir }}
      onQuit={(tabs) => {
        quitWith = tabs.map(({ sessionId }) => sessionId);
      }}
      open={async (options) => {
        const session = await openSession(options);

        sessions.push(session);

        return session;
      }}
    />,
  );
  const frame = () => app.frame();

  try {
    await until('the past', () => frame().includes('Hello, world.'));

    const past = frame();

    expect(past).toContain('› tools');
    // The agent's replay is all chord knows of it: no record says when.
    expect(past).toContain('resumed · tools');
    expect(past.indexOf('resumed') < past.indexOf('› tools')).toBeTruthy();
    expect(past).toContain('Read(README.md)');
    expect(past).toContain('Read it.');
    expect(past).toContain('› text');

    await app.write('/greet');
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('\r');
    await until('the answer', () => frame().includes('from the fake agent'));
    expect(sessions.length).toStrictEqual(1);
    expect(sessions[0]?.id).toStrictEqual(id);

    await app.write(CTRL_D);
    await until('the quit', () => quitWith !== undefined);
    expect(quitWith).toStrictEqual([id]);

    // The window kept the session, the past the agent replayed included, so
    // the command printed on quit finds it.
    await until('the record', async () =>
      (await readRecords(stateDir)).some(
        (record) => record.sessionId === id && record.prompt === 'tools',
      ),
    );
  } finally {
    await app.unmount();

    for (const session of sessions) {
      await session.close();
    }

    await rm(dir, { recursive: true });
  }
});

test("a runtime's models are read where the resumed session works: never started where its command is refused, read where it is not (CHD-466)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const here = join(dir, 'here');
  const there = join(dir, 'there');
  const start = { agentCommand: fakeAgentCommand() };
  const refused = 'codex not started: refused there';

  await mkdir(here);
  await mkdir(there);

  /**
   * The window's frame once `/model codexmodels` has been answered with
   * `answer`, in a window that resumes one session in `cwd`, whose files
   * start codex as `startupOf` says.
   */
  const modelsAsked = async (
    cwd: string,
    startupOf: (agent: string) => typeof start | { refused: string },
    answer: string,
  ) => {
    const server = serveChord();
    let frame = '';

    try {
      await withWindow(
        async (window) => {
          await until('the past', () => window.frame().includes('Read it.'));
          await window.type('codexmodels');
          await window.press('\r');
          await window.shows('Codex read:');
          await window.shows(answer);

          frame = window.frame();
        },
        {
          resume: { sessionId: crypto.randomUUID(), cwd },
          startupOf,
          server,
          runtimes: ['fake', 'codex'],
          rows: 80,
          columns: 160,
        },
      );
    } finally {
      await server.close();
    }

    return frame;
  };

  try {
    // Nothing is read there: were the command line's place asked, the fake
    // would start as codex and its models would show.
    const thereFrame = await modelsAsked(
      there,
      (agent) => (agent === 'codex' ? { refused } : start),
      refused,
    );

    expect(thereFrame).toContain(refused);
    expect(thereFrame).not.toContain('Fake Small');

    expect(await modelsAsked(here, () => start, 'Fake Small')).not.toContain(
      refused,
    );
  } finally {
    await rm(dir, { recursive: true });
  }
});

test('/clear after a resume starts a new session', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const sessions: Session[] = [];
  const id = crypto.randomUUID();
  const app = await draw(
    <App
      agent='fake'
      cwd={dir}
      stateDir={join(dir, 'state')}
      agentCommand={fakeAgentCommand()}
      resume={{ sessionId: id, cwd: dir }}
      open={async (options) => {
        const session = await openSession(options);

        sessions.push(session);

        return session;
      }}
    />,
  );
  const frame = () => app.frame();

  try {
    await until('the past', () => frame().includes('Read it.'));
    await app.write('/clear');
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('\r');
    await until('a second session', () => sessions.length === 2);
    await until('the past gone', () => !frame().includes('Read it.'));
    expect(sessions[1]?.id !== id).toBeTruthy();
    expect(frame()).toContain('? for shortcuts · /help');
    expect(
      !frame().includes('resumed'),
      'the new session says it resumed',
    ).toBeTruthy();
  } finally {
    await app.unmount();

    for (const session of sessions) {
      await session.close();
    }

    await rm(dir, { recursive: true });
  }
});

/** A left click on the prompt box's text row, as a terminal reports one. */
async function clickBox(window: Window): Promise<void> {
  const y = window
    .frame()
    .split('\n')
    .findLastIndex((line) => line.startsWith('│ ›'));

  expect(y).toBeGreaterThan(0);
  await window.press(left(10, y, 'down'));
  await window.press(left(10, y, 'up'));
}

test('a click on the box while a permission is asked gives the box no keys: the answering key answers it and goes nowhere else (CHD-429)', () =>
  withWindow(async (window) => {
    await ready(window);
    await send(window, 'permission');
    await asked(window);
    await clickBox(window);
    await window.press('1');
    await window.shows('Permission: allow');
    // Nothing typed reached the draft.
    expect(promptRow(window)?.replace(/[│›\s]/g, '')).toStrictEqual('');
  }));

test('a click on the box while ctrl+r searches gives the box no keys: what is typed is the query, and Esc gives the draft back untouched (CHD-429)', () =>
  withWindow(async (window) => {
    await ready(window);
    await send(window, 'fix auth');
    await until('the turn to end', () => !window.frame().includes('Working'));
    await window.press(CTRL_R);
    await window.shows('search prompts:');
    await clickBox(window);
    await window.type('auth');
    await window.shows('search prompts: auth');
    await window.press(ESC);
    await until(
      'the search closed',
      () => !window.frame().includes('search prompts'),
    );
    expect(promptRow(window)?.replace(/[│›\s]/g, '')).toStrictEqual('');
  }));

test('a click on the box while the sessions picker is open gives the box no keys: its digit picks and types nothing (CHD-429)', () =>
  withWindow(async (window) => {
    await ready(window);
    await leader(window, 'w');
    await window.shows('Esc to close');
    await clickBox(window);
    await window.press('1');
    await until(
      'the picker closed',
      () => !window.frame().includes('Esc to close'),
    );
    expect(promptRow(window)?.replace(/[│›\s]/g, '')).toStrictEqual('');
  }));

test('the renderer gives no widget the keys on a click (CHD-429)', () => {
  expect(terminalOptions({ mouse: true }).autoFocus).toStrictEqual(false);
});

describe('CHD-429 tester: mouse focus boundaries', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const [key, outcome] of [
      ['1', 'allow'],
      ['3', 'deny'],
    ] as const) {
      test(`repeated prompt clicks leave ${outcome} exclusively with the permission at ${columns}x${rows}`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'permission');
            await asked(window);
            await clickBox(window);
            await clickBox(window);
            await window.press(key);
            await window.shows(`Permission: ${outcome}.`);
            await window.type('abcdef');
            expect(promptRow(window)?.trimEnd()).toContain('› abcdef');
            expect(promptRow(window)).not.toContain(`› ${key}`);
            await window.press('\x1b[D');
            await window.type('X');
            expect(promptRow(window)).toContain('› abcdeXf');
          },
          { columns, rows },
        ));
    }

    test(`picking after a click preserves a nonempty draft and returns cursor keys at ${columns}x${rows}`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await window.type('abcdef');
          await leader(window, 'w');
          await window.shows('Esc to close');
          await clickBox(window);
          await window.press('1');
          await until(
            'the picker closed',
            () => !window.frame().includes('Esc to close'),
          );
          expect(promptRow(window)).toContain('› abcdef');
          await window.press('\x1b[D');
          await window.type('X');
          expect(promptRow(window)).toContain('› abcdeXf');
        },
        { columns, rows },
      ));

    test(`search after a click owns its query and restores the previous draft at ${columns}x${rows}`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'fix auth');
          await until(
            'the turn ended',
            () => !window.frame().includes('Working'),
          );
          await window.type('draft kept');
          await window.press(CTRL_R);
          await window.shows('search prompts:');
          await clickBox(window);
          await window.type('auth');
          await window.shows('search prompts: auth');
          await window.press(ESC);
          await until(
            'the search closed',
            () => !window.frame().includes('search prompts:'),
          );
          expect(promptRow(window)).toContain('› draft kept');
          expect(promptRow(window)).not.toContain('auth');
        },
        { columns, rows },
      ));
  }
});
