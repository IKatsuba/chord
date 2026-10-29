/**
 * The window resumed: past sessions drawn and answered in, models read where
 * a session works, and what a click gives the keys.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import { frontState, type AppState } from '../../../src/ui/app/state.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import { RECEIVED } from '../prompt/prompt_window.tsx';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import * as fileSystem from 'node:fs/promises';
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import stripAnsi from 'strip-ansi';
import { join } from 'node:path';
import { draw } from '../harness.tsx';
import { openSession, type Session } from '../../../src/session/session.ts';
import {
  earlierSessions,
  readRecords,
  summaryOf,
} from '../../../src/session/sessions.ts';
import type { RecordEntry } from '../../../src/session/record.ts';
import { serveChord } from '../../../src/server/server.ts';
import { App } from '../../../src/ui/app/App.tsx';
import { terminalOptions } from '../../../src/ui/app/renderer.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_D,
  CTRL_R,
  ESC,
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
  let quitWith: string | undefined;
  const id = crypto.randomUUID();
  // An id chord has no record of: the fake agent loads it and replays.
  const app = await draw(
    <App
      agent='fake'
      cwd={dir}
      stateDir={stateDir}
      agentCommand={fakeAgentCommand()}
      resume={{ sessionId: id, cwd: dir }}
      onQuit={(session) => {
        quitWith = session?.sessionId;
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
    expect(quitWith).toStrictEqual(id);

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
            await readyAgent(window);
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
      withChild(
        async (window) => {
          await openOther(window);
          await readyAgent(window);
          await window.type('abcdef');
          await pickAgent(window, 'other');
          await clickBox(window);
          await pickAgent(window, 'main');
          expect(promptRow(window)).toMatch(/^│ ›\s*│$/);
          await window.press('\x1b[A');
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
          await readyAgent(window);
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

describe('CHD-493 U1 tester: sessions-only resume with legacy windows', () => {
  test('a legacy window stays untouched and absent from the picker at both widths', async () => {
    const stateDir = await mkdtemp(join(tmpdir(), 'chord-legacy-picker-'));
    const path = join(stateDir, 'windows', 'w-old.json');
    let legacy = '';

    try {
      await mkdir(join(stateDir, 'windows'));
      await withWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'text');
          await window.shows('came in chunks.');

          const sessionId = window.session()?.id;

          expect(sessionId).toBeDefined();
          await until(
            'the session record that made this window listable',
            async () =>
              (await readRecords(stateDir)).some(
                (record) =>
                  record.sessionId === sessionId && record.cwd === window.dir,
              ),
          );

          legacy = JSON.stringify({
            id: 'w-old',
            at: Date.now(),
            front: 0,
            tabs: [{ agent: 'fake', sessionId, cwd: window.dir }],
          });

          await writeFile(path, legacy);
          await send(window, '/clear');
          await send(window, '/resume');
          await window.shows('Resume a session');

          for (const columns of [80, 120]) {
            await window.resize({ columns });

            const frame = window.frame();

            expect(frame).toContain(
              "fake's earlier sessions in this directory.",
            );
            expect(frame).not.toContain('saved windows');
            expect(frame).not.toContain('▣');
            expect(frame).not.toContain('w-old');
            expect(frame).toContain('text');
          }

          await window.press(ESC);
        },
        { stateDir, columns: 80, rows: 24 },
      );
      expect(await readFile(path, 'utf8')).toBe(legacy);
    } finally {
      await rm(stateDir, { recursive: true });
    }
  });
});

describe('CHD-493 U7 tester: legacy storage is never opened', () => {
  for (const columns of [80, 120]) {
    for (const legacy of ['missing', 'malformed', 'unreadable'] as const) {
      test(`${legacy} windows are ignored through failed resume, clear and picker at ${columns} columns`, async () => {
        const dir = await mkdtemp(join(tmpdir(), 'chord-ignored-windows-'));
        const stateDir = join(dir, 'state');
        const windows = join(stateDir, 'windows');
        const id = 'w-still-an-opaque-id';
        const path = join(windows, `${id}.json`);
        const bytes = '{this is not a window record\n';

        if (legacy !== 'missing') {
          await mkdir(windows, { recursive: true });
          await writeFile(path, bytes);
        }

        if (legacy === 'unreadable') {
          await chmod(path, 0);
          await chmod(windows, 0);
        }

        const operations = [
          spyOn(fileSystem, 'readFile'),
          spyOn(fileSystem, 'readdir'),
          spyOn(fileSystem, 'opendir'),
          spyOn(fileSystem, 'open'),
          spyOn(fileSystem, 'writeFile'),
          spyOn(fileSystem, 'appendFile'),
          spyOn(fileSystem, 'mkdir'),
          spyOn(fileSystem, 'stat'),
          spyOn(fileSystem, 'lstat'),
          spyOn(fileSystem, 'access'),
          spyOn(fileSystem, 'rename'),
          spyOn(fileSystem, 'unlink'),
          spyOn(fileSystem, 'rm'),
        ];

        try {
          await withWindow(
            async (window) => {
              await window.shows('fake did not start:');
              await until('the fake agent refusal', () =>
                window
                  .frame()
                  .replace(/\s+/g, '')
                  .includes(`itrefusedsession/load:Resourcenotfound:${id}`),
              );
              expect(window.frame()).not.toContain('was a window');
              await send(window, '/clear');
              await until(
                'the replacement session',
                () => window.session() !== undefined,
              );
              await ready(window);
              await send(window, 'text');
              await window.shows('came in chunks.');
              await until('a normal session record', async () =>
                (await readRecords(stateDir)).some(
                  (record) => record.sessionId === window.session()?.id,
                ),
              );

              const recorded = window.session()?.id;

              await send(window, '/clear');
              await until(
                'another session before listing the saved one',
                () =>
                  window.session() !== undefined &&
                  window.session()?.id !== recorded,
              );
              await ready(window);
              await send(window, '/resume');
              await window.shows('Resume a session');
              expect(window.frame()).not.toContain(id);
              await window.press(ESC);
            },
            {
              stateDir,
              resume: { sessionId: id, cwd: dir },
              whileStarting: true,
              columns,
              rows: columns === 80 ? 24 : 40,
            },
          );

          const touched = operations.flatMap((operation) =>
            operation.mock.calls.map((args) => String(args[0])),
          );

          // A normal record must be observed too, so this is an active spy.
          expect(
            touched.some((path) => path.startsWith(join(stateDir, 'records'))),
          ).toBe(true);
          expect(
            touched.filter(
              (path) => path === windows || path.startsWith(windows + '/'),
            ),
          ).toEqual([]);
        } finally {
          for (const operation of operations) {
            operation.mockRestore();
          }

          if (legacy === 'unreadable') {
            await chmod(windows, 0o700);
            await chmod(path, 0o600);
          }

          try {
            if (legacy === 'missing') {
              await expect(fileSystem.stat(windows)).rejects.toHaveProperty(
                'code',
                'ENOENT',
              );
            } else {
              expect(await readFile(path, 'utf8')).toBe(bytes);
            }
          } finally {
            await rm(dir, { recursive: true });
          }
        }
      });
    }
  }
});

describe("an agent's title for a session in /resume and a resumed header (CHD-445)", () => {
  const TITLE =
    "Fix the tokenizer's handling of a quoted string at the end of a line, then rerun the printer tests";

  /** The colour escape a frame's row draws `text` in. */
  const paintOf = (frame: string, text: string) => {
    const row = frame.split('\n').find((line) => line.includes(text)) ?? '';
    // eslint-disable-next-line no-control-regex
    const escapes = row.slice(0, row.indexOf(text)).match(/\x1b\[[0-9;]*m/g);

    return escapes?.at(-1);
  };

  for (const columns of [80, 120]) {
    test(`/resume names a session by its title after a child's name, a long one wrapped under its own start and highlighted whole, at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/resume');
          await window.shows('Resume a session');

          const rows = window
            .frame()
            .split('\n')
            .map((row) => stripAnsi(row));
          const first = rows.findIndex((row) =>
            row.includes('Fix the tokenizer'),
          );
          const start = rows[first]!.indexOf('Fix the tokenizer');
          // The row's further lines: nothing before the title's column but
          // the frame, and text from it.
          const further: string[] = [];

          for (const row of rows.slice(first + 1)) {
            if (!/^│\s*$/.test(row.slice(0, start)) || row[start] === ' ') {
              break;
            }

            further.push(row);
          }

          expect(further.length).toBeGreaterThan(0);
          expect(
            [rows[first]!, ...further]
              .map((row) => row.slice(start).replace(/\s*│\s*$/, ''))
              .join(' '),
          ).toStrictEqual(TITLE);

          const shown = rows.join('\n');

          expect(shown).not.toContain('look at the tokenizer');
          expect(shown).toContain('parser · Run the parser tests');
          expect(shown).toContain('an untitled first prompt');

          // The highlight is on every line of the wrapped row.
          const tail = further
            .at(-1)!
            .slice(start)
            .replace(/\s*│\s*$/, '');

          expect(paintOf(window.frame(), tail)).toStrictEqual(
            paintOf(window.frame(), 'Fix the tokenizer'),
          );
        },
        {
          columns,
          rows: 40,
          readRecords: (stateDir) => {
            const cwd = join(stateDir, '..');
            const record = (id: string, at: number, more: object) => ({
              path: join(stateDir, `${id}.jsonl`),
              sessionId: id,
              agent: 'fake',
              cwd,
              lastUsedAt: Date.now() - at * 60_000,
              prompt: 'look at the tokenizer',
              ...more,
            });

            return Promise.resolve([
              record('titled', 1, { title: TITLE }),
              record('child', 2, {
                parent: 'titled',
                name: 'parser',
                title: 'Run the parser tests',
              }),
              record('untitled', 3, { prompt: 'an untitled first prompt' }),
            ]);
          },
        },
      ));
  }

  for (const [columns, name] of [
    [80, undefined],
    [120, 'parser'],
  ] as const) {
    test(`a resumed session's header names it by its title${name === undefined ? '' : " after the child's name"}, wrapped under its own start, at ${columns} columns`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
      const sessions: Session[] = [];
      const app = await draw(
        <App
          agent='fake'
          cwd={dir}
          stateDir={join(dir, 'state')}
          agentCommand={fakeAgentCommand()}
          resume={{
            sessionId: crypto.randomUUID(),
            cwd: dir,
            lastUsedAt: Date.now() - 2 * 60 * 60_000,
            prompt: 'look at the tokenizer',
            title: TITLE,
            ...(name === undefined ? {} : { name }),
          }}
          open={async (options) => {
            const session = await openSession(options);

            sessions.push(session);

            return session;
          }}
        />,
        { columns, rows: 40 },
      );

      try {
        await until('the past', () => app.frame().includes('Hello, world.'));

        const rows = stripAnsi(app.frame()).split('\n');
        const at = rows.findIndex((row) => row.includes('resumed · '));
        const start = rows[at]!.indexOf('resumed · ');
        const said = [rows[at]!, rows[at + 1]!].map((row) =>
          row.slice(start).trimEnd(),
        );

        expect(said.join(' ')).toStrictEqual(
          `resumed · 2 hours ago · ${name === undefined ? '' : `${name} · `}${TITLE}`,
        );
        // Under its own start: nothing before it on the second line.
        expect(rows[at + 1]!.slice(0, start).trim()).toStrictEqual('');
        expect(app.frame()).not.toContain('look at the tokenizer');
      } finally {
        await app.unmount();

        for (const session of sessions) {
          await session.close();
        }

        await rm(dir, { recursive: true });
      }
    });
  }

  test('a title taller than the picker is read a line a press at 80×24, the picker no taller than with titles that fit, and a resize of the height shows it from its first line', () => {
    const words = Array.from({ length: 160 }, (_, at) => `word${at}`);

    return withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/resume');
        await window.shows('Resume a session');

        const height = () =>
          stripAnsi(window.frame())
            .split('\n')
            .filter((row) => row.startsWith('│')).length;
        const before = height();

        await window.shows('word0');
        expect(window.frame()).not.toContain('word159');
        // Onto the tall row, then a line a press until its end is in sight.
        await window.press('j');

        for (
          let press = 0;
          press < 40 && !window.frame().includes('word159');
          press++
        ) {
          await window.press('j');
          expect(height()).toBeLessThanOrEqual(before);
        }

        expect(window.frame()).toContain('word159');
        expect(window.frame()).not.toContain('word0 ');

        // A resize of the height alone shows the row from its first line.
        await window.resize({ rows: 30 });
        await window.shows('word0 ');
        expect(window.frame()).toContain('❯');
      },
      {
        columns: 80,
        rows: 24,
        readRecords: (stateDir) => {
          const cwd = join(stateDir, '..');
          const record = (id: string, at: number, more: object) => ({
            path: join(stateDir, `${id}.jsonl`),
            sessionId: id,
            agent: 'fake',
            cwd,
            lastUsedAt: Date.now() - at * 60_000,
            prompt: 'a first prompt',
            ...more,
          });

          return Promise.resolve([
            record('short', 1, { title: 'Fix the tokenizer' }),
            record('tall', 2, { title: words.join(' ') }),
            record('after', 3, { title: 'docs · Fix the parser' }),
          ]);
        },
      },
    );
  });
});

describe('CHD-445 U2 tester: an open resume picker keeps its title snapshot', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`reopen refreshes a renamed title after Esc at ${columns}×${rows}`, () => {
      let title = 'First recorded title';
      let reads = 0;

      return withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/resume');
          await window.shows(title);

          title = 'Newest recorded title';

          await window.resize({ rows: rows + 1 });
          expect(window.frame()).toContain('First recorded title');
          expect(window.frame()).not.toContain(title);
          expect(reads).toBe(1);
          await window.press(ESC);
          await until(
            'resume picker closed',
            () => !window.frame().includes('Resume a session'),
          );
          await send(window, '/resume');
          await window.shows(title);
          expect(window.frame()).not.toContain('First recorded title');
          expect(reads).toBe(2);
          await window.press(ESC);
          await until(
            'resume picker closed',
            () => !window.frame().includes('Resume a session'),
          );
          expect(window.frame()).not.toContain('Resume a session');
        },
        {
          columns,
          rows,
          readRecords: (stateDir) => {
            reads++;

            return Promise.resolve([
              {
                path: join(stateDir, 'earlier.jsonl'),
                sessionId: 'earlier',
                agent: 'fake',
                cwd: join(stateDir, '..'),
                lastUsedAt: Date.now() - 60_000,
                prompt: 'Original prompt stays hidden',
                title,
              },
            ]);
          },
        },
      );
    });
  }
});

describe('CHD-445 U2 tester: resumed headers keep the title that was picked', () => {
  for (const columns of [80, 120]) {
    test(`a later fake rename leaves the resumed child header unchanged at ${columns} columns`, async () => {
      const dir = await mkdtemp(join(tmpdir(), 'chord-header-title-'));

      try {
        await withWindow(
          async (window) => {
            await window.shows('parser · Picked title');
            await send(window, 'titledfix');
            await window.shows('Renamed.');
            expect(stripAnsi(window.frame())).toContain(
              'parser · Picked title',
            );
            expect(stripAnsi(window.frame())).not.toContain(
              'resumed · Fix the parser',
            );
          },
          {
            columns,
            rows: 40,
            resume: {
              sessionId: crypto.randomUUID(),
              cwd: dir,
              title: 'Picked title',
              name: 'parser',
              prompt: 'Original prompt',
              lastUsedAt: Date.now() - 60_000,
            },
          },
        );
      } finally {
        await rm(dir, { recursive: true });
      }
    });
  }
});

describe('CHD-445 Q200 tester: task and child titles on resume', () => {
  for (const task of [false, true]) {
    for (const columns of [80, 120]) {
      test(`${task ? 'a task keeps its caller description' : 'a child keeps its agent title after its name'} in the picker and resumed header at ${columns} columns`, async () => {
        const dir = await mkdtemp(join(tmpdir(), 'chord-resume-title-'));
        const path = join(dir, 'record.jsonl');
        const id = crypto.randomUUID();
        const name = task ? 'Run the parser tests' : 'parser';
        const entries: RecordEntry[] = [
          {
            type: 'session',
            version: 1,
            sessionId: id,
            agent: 'fake',
            cwd: dir,
            at: Date.now() - 60_000,
            parent: 'parent-session',
            name,
            ...(task ? { task: 'task-q200' } : {}),
          },
          {
            type: 'prompt',
            turnId: 't1',
            at: Date.now() - 60_000,
            prompt: 'Original work',
            images: 0,
          },
          {
            type: 'update',
            turnId: 't1',
            update: {
              sessionUpdate: 'session_info_update',
              title: 'An earlier agent title',
            },
          },
          {
            type: 'update',
            turnId: 't1',
            update: {
              sessionUpdate: 'session_info_update',
              title: 'Final agent title',
            },
          },
          {
            type: 'result',
            turnId: 't1',
            result: { status: 'completed', stopReason: 'end_turn' },
          },
        ];
        const text =
          entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n';

        try {
          await writeFile(path, text);

          const record = summaryOf(path, text)!;
          const [choice] = earlierSessions([record], {
            agent: 'fake',
            cwd: dir,
          });

          expect(choice?.prompt).toBe(
            `${name} · ${task ? 'Original work' : 'Final agent title'}`,
          );
          expect(choice?.resume.title).toBe(
            task ? undefined : 'Final agent title',
          );
          await withWindow(
            async (window) => {
              await window.shows('resumed ·');
              await window.shows('› Original work');

              const header = stripAnsi(window.frame())
                .split('\n')
                .find((line) => line.includes('resumed ·'))!;

              expect(header).toContain(
                task ? name : `${name} · Final agent title`,
              );
              expect(header).not.toContain('An earlier agent title');

              if (task) {
                expect(header).not.toContain('Final agent title');
                expect(header).not.toContain('Original work');
              }
            },
            {
              columns,
              rows: 40,
              agentCommand: fakeAgentCommand(undefined, '--resume-only'),
              resume: choice!.resume,
            },
          );
        } finally {
          await rm(dir, { recursive: true });
        }
      });
    }
  }
});

describe('CHD-476 U2 tester: resume refusal image ownership', () => {
  for (const columns of [80, 120]) {
    test(`a busy resume refusal preserves the queued bytes and link for clear and one resend at ${columns} columns`, async () => {
      let state: AppState | undefined;
      const prompts: Parameters<Session['prompt']>[] = [];
      const text = 'main [Image #1] @a.ts done';

      await withWindow(
        async (window) => {
          await ready(window);
          await writeFile(join(window.dir, 'a.ts'), '');
          await send(window, 'costwait');
          await window.shows('Working until stopped.');

          const old = window.session()!.id;

          for (const key of 'main /shots/a.png @a.ts done') {
            await window.press(key);
          }

          await window.press('\r');
          await until(
            'main bitmap prompt queued',
            () => state?.queue.length === 1,
          );
          expect(prompts.some((args) => args[0].includes(text))).toBe(false);

          const queued = state!.queue[0]!;

          await send(window, '/resume');
          await window.shows('A turn is running. Wait for it to end');
          expect(window.frame()).not.toContain('Resume a session');
          expect(state!.queue).toStrictEqual([queued]);
          expect(prompts.some((args) => args[0].includes(text))).toBe(false);

          await send(window, '/clear');
          await until(
            'fresh main restores bitmap draft',
            () =>
              state?.draft === text &&
              state.connection.status === 'ready' &&
              window.session()?.id !== old,
          );
          expect(state!.images.map((image) => image.data)).toStrictEqual([
            PIXEL_PNG,
          ]);
          expect(state!.queue).toStrictEqual([]);
          await window.press('\r');
          await window.shows(RECEIVED);
          await window.shows('Received a link: a.ts');

          const delivered = prompts.filter((args) => args[0].includes(text));

          expect(delivered).toHaveLength(1);
          expect(delivered[0]!.slice(1, 3)).toStrictEqual([
            [{ mediaType: 'image/png', data: PIXEL_PNG }],
            ['a.ts'],
          ]);
          expect(state!.images).toStrictEqual([]);
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          onState: (all) => {
            state = frontState(all);
          },
          readImage: () =>
            Promise.resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
          openWith: async (options) => {
            const session = await openSession(options);
            const prompt = session.prompt.bind(session);

            session.prompt = (...args) => {
              prompts.push(args);

              return prompt(...args);
            };

            return session;
          },
        },
      );
    });
  }
});
