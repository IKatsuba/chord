/**
 * /new in the window: the agents it lists, and the agent it opens for main
 * beside main's own work.
 */
import { describe, expect, test } from 'bun:test';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { serveChord } from '../../../src/server/server.ts';
import type { Caller } from '../../../src/server/tools.ts';
import { parseRecord, type RecordEntry } from '../../../src/session/record.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  CTRL_C,
  DOWN,
  ESC,
  isAlive,
  ready,
  send,
  until,
  UP,
  withWindow,
  type Window,
} from './render.tsx';

test('/new and a space lists the agents chord can start, after /clear as before it (U6)', () =>
  withWindow(
    async (window) => {
      const listed = async () => {
        await window.type('/new ');
        await until('the agents listed', () =>
          /^ {2}fake\s*$/m.test(window.frame()),
        );
        await window.press(CTRL_C);
      };

      await ready(window);
      await listed();
      await send(window, '/clear');
      await ready(window);
      await listed();
    },
    { columns: 120, rows: 40 },
  ));

test("/new opens an agent of main's runtime for main, idle, and goes to it; main's transcript draws the call (U6)", () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));
      await window.type('/new');
      await window.shows('Open a new agent beside main and go to it');
      expect(window.frame()).not.toContain('/clear (new)');
      await window.press('\r');
      await window.shows('╭─ fake ');
      await window.shows('    fake ');
      // Idle, with no first prompt (Q187).
      expect(window.frame()).not.toContain('in chunks');
      expect(window.frame()).not.toContain('Working');
      // Main's transcript has the call, its line saying how it opened.
      await window.press(DOWN);
      await until('main picked in the list', async () => {
        if (window.frame().includes('  ❯ main ')) {
          return true;
        }

        await window.press(UP);

        return false;
      });

      await window.press('\r');
      await until('main in view', () => !window.frame().includes('╭─ fake '));
      await window.shows('Open(fake) · fake');
      await window.shows('⎿  opened with /new');
      await window.shows('This reply came in chunks.');
    },
    { columns: 120, rows: 40 },
  ));

test("/new codex opens a codex agent for main beside main's running turn, which goes on (U6)", () =>
  withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await send(window, '/new codex');
      await window.shows('╭─ codex ');
      await until(
        "codex's row beside main's, still working",
        () =>
          /^ {4}codex\s+codex/m.test(window.frame()) &&
          /^ {4}main\s.*working/m.test(window.frame()),
      );
    },
    {
      columns: 120,
      rows: 40,
      runtimes: ['fake', 'codex'],
      // Both runtimes on the fake, so codex starts with no codex installed.
      startupOf: () => ({ agentCommand: fakeAgentCommand() }),
    },
  ));

describe('CHD-565 /new with a list of offered agents', () => {
  const start = {
    runtimes: ['fake', 'codex', 'zed'],
    listed: ['zed', 'codex'].map((name) => ({
      name,
      title: undefined,
      start: name,
      from: 'settings' as const,
    })),
    offered: ['zed', 'codex'],
    startupOf: () => ({ agentCommand: fakeAgentCommand() }),
  };

  test("the completion lists the list, in its order, without the window's agent", () =>
    withWindow(
      async (window) => {
        await ready(window);
        await window.type('/new ');
        await until('the agents listed', () =>
          /^ {2}zed\s/m.test(window.frame()),
        );

        const frame = window.frame();

        expect(frame.indexOf('  zed')).toBeLessThan(frame.indexOf('  codex'));
        expect(frame).not.toMatch(/^ {2}fake\s/m);
        await window.press(CTRL_C);
      },
      { columns: 80, rows: 24, ...start },
    ));

  test('/new with a name outside the list still opens it', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await window.type('/new fake');
        await window.press('\r');
        await window.shows('╭─ fake ');
      },
      { columns: 120, rows: 40, ...start },
    ));
});

describe('CHD-493 U6 tester: person-opened agents keep main and its menu', () => {
  const command = fakeAgentCommand();
  const states = new WeakMap<Window, () => WindowedState>();
  const connected = (window: Window) =>
    until('the shown session is ready', () => {
      const all = states.get(window)!();

      return all.sessions[all.front]?.connection.status === 'ready';
    });

  type Options = NonNullable<Parameters<typeof withWindow>[1]>;

  async function run(
    columns: number,
    body: (
      window: Window,
      callers: Caller[],
      sessions: Session[],
    ) => Promise<void>,
    options: Options = {},
  ) {
    const server = serveChord();
    const admit = server.admit.bind(server);
    const callers: Caller[] = [];
    const sessions: Session[] = [];
    let state: WindowedState;

    server.admit = (caller) => {
      callers.push(caller);

      return admit(caller);
    };

    try {
      await withWindow(
        (window) => {
          states.set(window, () => state);

          return body(window, callers, sessions);
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          agentCommand: command,
          runtimes: ['fake', 'codex'],
          listed: ['fake', 'codex'].map((name) => ({
            name,
            title: undefined,
            start: 'fake',
            from: 'settings' as const,
          })),
          startupOf: () => ({ agentCommand: command }),
          ...options,
          server,
          onState: (all) => {
            state = all;
          },
          openWith: async (settings) => {
            const session = await openSession(settings);

            sessions.push(session);

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  }

  async function go(window: Window, name: string) {
    await window.press(DOWN);
    await until(`the agents list picks ${name}`, async () => {
      const rows = window.frame().split('\n');
      const current = rows.findIndex((row) => /^ {2}❯ /.test(row));
      const wanted = rows.findIndex(
        (row) =>
          row.startsWith(`    ${name} `) || row.startsWith(`  ❯ ${name} `),
      );

      if (wanted !== -1 && current === wanted) {
        return true;
      }

      await window.press(current < wanted ? DOWN : UP);

      return false;
    });

    await window.press('\r');
  }

  async function records(window: Window): Promise<RecordEntry[][]> {
    const dir = join(window.dir, 'state', 'records');

    return Promise.all(
      (await readdir(dir)).map(async (file) =>
        parseRecord(await readFile(join(dir, file), 'utf8')),
      ),
    );
  }

  for (const columns of [80, 120]) {
    test(`/resume keeps /new's agent menu without a preceding /clear at ${columns} columns`, async () => {
      let cwd = '';
      const target = crypto.randomUUID();

      await run(
        columns,
        async (window) => {
          cwd = window.dir;

          await connected(window);
          await send(window, '/resume');
          await window.shows('Resume a session');
          await window.press('\r');
          await until(
            'the picked session is connected',
            () => window.session()?.id === target,
          );
          await connected(window);
          await window.type('/new ');
          await window.shows('codex');
          await window.press(CTRL_C);
          await send(window, '/new codex');
          await window.shows('╭─ codex ');
          await connected(window);
        },
        {
          readRecords: () =>
            Promise.resolve([
              {
                path: join(cwd, 'earlier.jsonl'),
                sessionId: target,
                agent: 'fake',
                cwd,
                prompt: 'earlier menu check',
                lastUsedAt: 0,
              },
            ]),
        },
      );
    });

    test(`a child invokes bare /new on main's runtime and settings mode while main keeps working at ${columns} columns`, () =>
      run(
        columns,
        async (window, callers, sessions) => {
          await connected(window);

          const main = sessions[0]!;

          await main.setModel('fake-small');
          await main.setEffort('high');
          await main.setMode('plan');
          await send(window, 'costwait');
          await window.shows('Working until stopped.');
          await send(window, '/new codex');
          await window.shows('╭─ codex ');
          await connected(window);
          await until(
            'codex is connected',
            () =>
              sessions.length === 2 &&
              sessions[1]?.models()?.current === 'fake-large',
          );

          const child = sessions[1]!;

          expect(child.efforts()?.current).toBe('medium');
          await until(
            'the settings mode applied',
            () => child.modes()?.current === 'acceptEdits',
          );
          expect(child.models()?.current).toBe('fake-large');
          expect(window.frame()).not.toContain('Hello, world.');
          expect(window.frame()).toMatch(/main\s+fake.*working/m);
          await send(window, '/new');
          await window.shows('╭─ fake ');
          await connected(window);
          await until(
            'the second child is connected',
            () => sessions.length === 3,
          );
          expect(
            callers
              .filter(({ role }) => role === 'child')
              .every(({ key }) => key === callers[0]?.key),
          ).toBe(true);

          const children = Object.entries(
            states.get(window)!().sessions,
          ).filter(([key]) => Number(key) !== callers[0]?.key);

          expect(children).toHaveLength(2);
          expect(
            children.flatMap(([, state]) =>
              state.transcript.entries.filter((entry) => entry.kind === 'user'),
            ),
          ).toEqual([]);
          expect(await isAlive([...main.agentPids][0]!)).toBe(true);
          await go(window, 'main');
          await window.press(ESC);
          await window.shows('Interrupted by user');
          await send(window, 'text');
          await window.shows('This reply came in chunks.');
          await until(
            'main records the calls and the aside before its next prompt',
            async () => {
              const own =
                (await records(window)).find((record) =>
                  record.some(
                    (entry) =>
                      entry.type === 'session' && entry.sessionId === main.id,
                  ),
                ) ?? [];
              const calls = own.filter(
                (entry) =>
                  entry.type === 'ran' && entry.call.tool === 'open_agent',
              );
              const informed = own.some(
                (entry) =>
                  entry.type === 'prompt' &&
                  entry.prompt.includes(
                    'The person opened @codex (codex) with /new;',
                  ) &&
                  entry.prompt.includes('It reports to you'),
              );

              return calls.length === 2 && informed;
            },
          );
        },
        {
          startupOf: () => ({
            agentCommand: command,
            starting: {
              model: { id: 'fake-small', from: 'settings' },
              effort: { id: 'high', from: 'settings' },
              mode: { id: 'acceptEdits', from: 'settings' },
            },
          }),
        },
      ));

    test(`unknown and refused runtimes leave the invoking child and its work at ${columns} columns`, () =>
      run(
        columns,
        async (window, _callers, sessions) => {
          await connected(window);
          await send(window, '/new');
          await window.shows('╭─ fake ');
          await connected(window);
          await send(window, 'text');
          await window.shows('This reply came in chunks.');
          await send(window, '/new nonexistent-runtime');
          await window.shows('No agent named nonexistent-runtime;');
          expect(window.frame()).toContain('╭─ fake ');
          expect(window.frame()).toContain('This reply came in chunks.');
          await send(window, '/new codex');
          await window.shows('codex refused by the test settings');
          expect(window.frame()).toContain('╭─ fake ');
          expect(sessions).toHaveLength(2);
        },
        {
          startupOf: (agent) =>
            agent === 'codex'
              ? { refused: 'codex refused by the test settings' }
              : { agentCommand: command },
        },
      ));
  }

  test('eight idle children fill the cap in their invoking view; x frees a place and /clear reaps the rest', () =>
    run(80, async (window, _callers, sessions) => {
      await connected(window);

      for (let count = 1; count <= 8; count++) {
        await send(window, '/new');
        await window.shows(`╭─ fake${count === 1 ? '' : ` ${count}`} `);
        await connected(window);
        await until(
          'the new child connected',
          () => sessions.length === count + 1,
        );
      }

      await send(window, '/new');
      await window.shows(
        'This session has 8 agents open; close_agent one first',
      );
      expect(window.frame()).toContain('╭─ fake 8 ');
      expect(sessions).toHaveLength(9);
      await window.press(DOWN);
      await window.press('x');
      await until(
        'the eighth child stopped',
        () => sessions[8]?.agentPids.size === 0,
      );
      await window.press('\r');
      await send(window, '/new');
      await until(
        'a replacement child connected',
        () => sessions.length === 10,
      );
      await connected(window);
      await go(window, 'main');
      await send(window, '/clear');
      await until('every retired child stopped', () =>
        sessions.slice(0, 10).every((session) => session.agentPids.size === 0),
      );
      await connected(window);
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      expect(window.frame()).not.toMatch(/^ {4}fake\s/m);
    }));

  test('the fake child messages main through its admitted MCP identity and main can message and close it', () =>
    run(120, async (window, callers, sessions) => {
      await connected(window);
      await send(window, '/new');
      await window.shows('╭─ fake ');
      await connected(window);
      await send(window, 'agentchild');
      await window.shows('I will run the parser tests on each change.');

      const main = callers.find(({ role }) => role === 'person')!;

      expect(
        main.window.tell(main, 'fake', 'text', () => {}),
      ).not.toHaveProperty('error');
      await window.shows('← from @main');
      await go(window, 'main');
      await window.shows('← from @fake · fake');
      await window.shows('All 214 parser tests pass now.');
      expect(main.window.close(main, 'fake')).not.toHaveProperty('error');
      await until('the child exited', () => sessions[1]?.agentPids.size === 0);
      await until(
        'the closed child row to leave the list',
        () => !/^ {4}fake\s/m.test(window.frame()),
      );
      expect(window.frame()).not.toMatch(/^ {4}fake\s/m);
    }));

  for (const behavior of ['failed', 'hung'] as const) {
    test(`a ${behavior} /new start can be left by /clear without an agent remaining`, () =>
      run(
        80,
        async (window, _callers, sessions) => {
          await connected(window);
          await send(window, '/new codex');
          await window.shows(
            behavior === 'hung' ? 'Starting codex' : 'codex did not start:',
          );
          await go(window, 'main');

          if (behavior === 'failed') {
            await window.shows('did not start:');
          }

          await send(window, '/clear');
          await connected(window);
          expect(window.frame()).not.toContain('╭─ codex ');
          await until('the original sessions have stopped', () =>
            sessions.every(
              (session, index) =>
                index === sessions.length - 1 || session.agentPids.size === 0,
            ),
          );
        },
        {
          startupOf: (agent) => ({
            agentCommand:
              agent === 'codex'
                ? fakeAgentCommand(
                    undefined,
                    ...(behavior === 'hung'
                      ? ['--hang', 'start']
                      : ['--hang', 'invalid']),
                  )
                : command,
          }),
        },
      ));
  }
});
