/**
 * /fork in the window: a top-level agent beside main, of no one, that
 * starts from the conversation so far (CHD-101).
 */
import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { quote } from 'shell-quote';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { openSession, type Session } from '../../../src/session/session.ts';
import type { WindowedState } from '../../../src/ui/app/state.ts';
import { reduceTranscript } from '../../../src/session/transcript/reducer.ts';
import {
  emptyTranscript,
  type TranscriptAction,
} from '../../../src/session/transcript/types.ts';
import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  parseRecord,
  recordActions,
  type RecordEntry,
} from '../../../src/session/record.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  isAlive,
  quitAll,
  ready,
  send,
  until,
  UP,
  withWindow,
  type Window,
} from './render.tsx';

const FORKS = fakeAgentCommand(undefined, '--fork');

/** Back on main, its box without a name. */
async function pickMain(window: Window) {
  await window.press(DOWN);
  await until('main picked in the list', async () => {
    if (window.frame().includes('  ❯ main ')) {
      return true;
    }

    await window.press(UP);

    return false;
  });

  await window.press('\r');
  await until('main in view', () => !/╭─ \S/.test(window.frame()));
}

describe('/fork opens a fork beside main (CHD-101)', () => {
  test('it is picked at once, listed after main as a fork, and main says where it went', () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows('This reply came in chunks.');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
        await window.type('/fork');
        await window.shows('Fork the conversation into a new agent');
        await window.press('\r');
        await window.shows('╭─ fork ');
        await window.shows('forked from main');
        await window.shows('    fork  fork · fake');
        // Its view: the conversation as it stood, then where it parted.
        await window.shows('── forked from main · ');

        expect(window.frame()).toContain('This reply came in chunks.');
        await send(window, 'thought');
        await window.shows('Here is the answer.');

        // Its record keeps where it parted and its own turns, never the
        // conversation copied above it, which the agent already has.
        const dir = join(window.dir, 'state', 'records');
        const records = await Promise.all(
          (await readdir(dir)).map(async (file) =>
            parseRecord(await readFile(join(dir, file), 'utf8')),
          ),
        );
        const fork = records.find((entries) =>
          entries.some((entry) => entry.type === 'forked'),
        );

        expect(
          fork?.flatMap((entry) =>
            entry.type === 'prompt' ? [entry.prompt] : [],
          ),
        ).toStrictEqual(['thought']);
        await pickMain(window);
        await window.shows('⎿  Forked into fork');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test('a second is fork 2, a named one keeps its name, and a fork forks too', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await send(window, '/fork parser');
        await window.shows('╭─ parser ');
        await window.shows('forked from fork');
        await pickMain(window);
        await send(window, '/fork');
        await window.shows('╭─ fork 2 ');
        await window.shows('forked from main');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test("main's /clear leaves the forks open, and /clear on a fork clears it alone, no one told (CHD-476)", () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows('This reply came in chunks.');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await window.shows('── forked from main · ');
        await send(window, '/clear');
        await until(
          "the fork's view empty",
          () => !window.frame().includes('── forked from main · '),
        );

        expect(window.frame()).toContain('╭─ fork ');
        await pickMain(window);

        expect(window.frame()).not.toContain('The person cleared');
        await send(window, '/clear');
        await until(
          "main's transcript cleared",
          () => !window.frame().includes('This reply came in chunks.'),
        );

        expect(window.frame()).toContain('    fork  fork · fake');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  test('a fork that opens an agent is told it works only from main, as a failed call', async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork');
          await window.shows('╭─ fork ');
          await send(window, 'agentnames');
          await window.shows('Quoted agent names refused.');

          expect(window.frame()).toContain(
            'This tool works only from main and its agents, not from a fork.',
          );
          // Nothing was opened: the list is main and the fork alone.
          expect(
            window
              .frame()
              .split('\n')
              .filter((row) => /^ {4}\S/.test(row)),
          ).toHaveLength(2);
        },
        { agentCommand: FORKS, server, columns: 120, rows: 40 },
      );
    } finally {
      await server.close();
    }
  });

  test("main's close_agent cannot close a fork, which is not its child", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork parser');
          await window.shows('╭─ parser ');
          await pickMain(window);
          await send(window, 'agentclose');
          await window.shows('parser is closed, so I will run the tests');

          expect(window.frame()).toContain('    parser  fork · fake');
        },
        { agentCommand: FORKS, server, columns: 120, rows: 40 },
      );
    } finally {
      await server.close();
    }
  });

  test("a fork's monitors are its own, and list_sessions names it apart from main, as the caller", async () => {
    const server = serveChord();

    try {
      await withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork');
          await window.shows('╭─ fork ');
          await send(window, 'monitor');
          await window.shows('I will hear from the dev server when it errs.');

          expect(window.frame()).not.toContain('This session has closed');
          await send(window, 'chordtools');
          await window.shows('list_sessions:');

          const said = window.frame().replace(/\s+/g, ' ');

          // Two sessions, the fork's marked as the caller's, main's with no
          // fork among its agents.
          expect(said.match(/"you": true/g)).toHaveLength(1);
          expect(said).not.toContain('"name": "fork"');
        },
        { agentCommand: FORKS, server, columns: 120, rows: 60 },
      );
    } finally {
      await server.close();
    }
  });

  test('a fork closed by x before it is up is not picked, and the command says so on its source', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/fork');
        await window.shows('    fork  fork · fake');
        await window.press(DOWN);
        await until('the fork picked in the list', async () => {
          if (window.frame().includes('  ❯ fork ')) {
            return true;
          }

          await window.press(DOWN);

          return false;
        });

        await window.press('x');
        await window.shows('Could not fork: it was closed before it started');

        expect(window.frame()).not.toContain('fork · fake');
        expect(window.frame()).not.toContain('╭─ fork');
      },
      {
        agentCommand: ['env', 'CHORD_FAKE_HANG_FORK=1', ...FORKS],
        columns: 120,
        rows: 40,
      },
    ));

  test('x closes a fork, and the list goes with it', () =>
    withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/fork');
        await window.shows('╭─ fork ');
        await window.press(DOWN);
        await window.shows('  ❯ fork ');
        await window.press('x');
        await until(
          'the fork closed',
          () => !window.frame().includes('fork · fake'),
        );
        await until('main in view', () => !/╭─ \S/.test(window.frame()));

        // It has no parent: main is told nothing.
        expect(window.frame()).not.toContain('The person closed');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));

  for (const [why, line, agentCommand] of [
    [
      'an agent that does not fork',
      'This agent does not fork sessions',
      fakeAgentCommand(),
    ],
    [
      'a fork the agent refuses',
      'Could not fork:',
      ['env', 'CHORD_FAKE_REFUSE_FORK=1', ...FORKS],
    ],
  ] as const) {
    test(`${why} is refused under the command, nothing opened`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/fork');
          await window.shows(line);

          expect(window.frame()).not.toContain('fork · fake');
          expect(window.frame()).not.toContain('╭─ fork');
        },
        { agentCommand: [...agentCommand], columns: 120, rows: 40 },
      ));
  }

  test('while main works, or with an ordinary child picked, it is refused', () =>
    withWindow(
      async (window) => {
        // Held until a steer or the cancel, however slow the machine.
        await send(window, 'texttillsteeredheld');
        await window.shows('This reply came in chunks.');
        await send(window, '/fork');
        await window.shows('main is working · /fork once its turn ends');
        await window.press('\u001b');
        await until(
          'the turn to end',
          () => !window.frame().includes('esc to interrupt'),
        );
        await send(window, '/new');
        await window.shows('╭─ fake ');
        await send(window, '/fork');
        await window.shows('/fork forks main or a fork');
        expect(window.frame()).not.toContain('fork · fake');
      },
      { agentCommand: FORKS, columns: 120, rows: 40 },
    ));
});

describe('CHD-101 U2 tester: fork routing, records and ownership', () => {
  const entries = (all: WindowedState | undefined, key: number) =>
    all?.sessions[key]?.transcript.entries ?? [];
  const namedRow = (frame: string, name: string) =>
    frame
      .split('\n')
      .findIndex((row) => new RegExp(`^(?: {4}| {2}❯ )${name}\\s`).test(row));
  const pickRow = async (window: Window, name: string) => {
    await window.press(DOWN);
    await until(`the list picks ${name}`, async () => {
      const frame = window.frame();
      const wanted = namedRow(frame, name);
      const picked = frame.split('\n').findIndex((row) => /^ {2}❯ /.test(row));

      if (wanted === picked && wanted !== -1) {
        return true;
      }

      await window.press(picked < wanted ? DOWN : UP);

      return false;
    });
  };

  const choose = async (window: Window, name: string) => {
    await pickRow(window, name);
    await window.press('\r');
    await until(`${name} in view`, () =>
      name === 'main'
        ? !/╭─ \S/.test(window.frame())
        : window.frame().includes(`╭─ ${name} `),
    );
  };

  const peerClient = async (session: Session) => {
    const server = session.chordServer;

    assert(server !== undefined && 'type' in server && server.type === 'http');

    const client = new Client({
      name: 'fork-window-fixture',
      version: '0.0.0',
    });

    await client.connect(
      new StreamableHTTPClientTransport(new URL(server.url), {
        requestInit: {
          headers: Object.fromEntries(
            server.headers.map(({ name, value }) => [name, value]),
          ),
        },
      }),
    );

    return client;
  };

  const answer = (result: Awaited<ReturnType<Client['callTool']>>): unknown => {
    const block = Array.isArray(result.content)
      ? result.content.find((item) => item.type === 'text')
      : undefined;

    assert(block?.type === 'text');

    return JSON.parse(block.text);
  };

  for (const ending of ['switch', 'clear', 'close'] as const) {
    test(`a gated fork refusal after ${ending} reaches only its original live source at 80 columns`, async () => {
      const release = Promise.withResolvers<void>();
      let hold = false;
      let refused = false;
      let all: WindowedState | undefined;

      await withWindow(
        async (window) => {
          try {
            await ready(window);

            const mainKey = all!.front;
            const mainId = all!.sessions[mainKey]!.sessionId;

            await send(window, '/fork origin');
            await window.shows('╭─ origin ');

            const originKey = all!.front;
            const originId = all!.sessions[originKey]!.sessionId;

            if (ending !== 'close') {
              await choose(window, 'main');
            }

            const sourceKey = all!.front;

            hold = true;

            await send(window, '/fork pending');
            await until(
              'the real fake refusal held at its gate',
              () => refused,
            );

            if (ending === 'switch') {
              await choose(window, 'origin');
            } else if (ending === 'clear') {
              await send(window, '/clear');
              await until(
                'main replaced',
                () =>
                  all?.sessions[mainKey]?.sessionId !== mainId &&
                  all?.sessions[mainKey]?.connection.status === 'ready',
              );
            } else {
              await choose(window, 'main');
              await pickRow(window, 'origin');
              await window.press('x');
              await until(
                'source fork closed',
                () => all?.sessions[originKey] === undefined,
              );
            }

            release.resolve();
            await until(
              'the refused candidate removed',
              () => namedRow(window.frame(), 'pending') === -1,
            );

            if (ending === 'switch') {
              await until('failure on original main only', () =>
                JSON.stringify(entries(all, sourceKey)).includes(
                  'Could not fork:',
                ),
              );
              expect(all?.sessions[mainKey]?.sessionId).toBe(mainId);
              expect(all?.sessions[originKey]?.sessionId).toBe(originId);
              expect(all?.front).toBe(originKey);
              expect(JSON.stringify(entries(all, originKey))).not.toContain(
                'Could not fork:',
              );
              await choose(window, 'main');
              await window.shows('Could not fork:');
            } else {
              expect(all?.front).toBe(mainKey);
              expect(JSON.stringify(entries(all, mainKey))).not.toContain(
                'Could not fork:',
              );
              expect(window.frame()).not.toContain('Could not fork:');

              if (ending === 'clear') {
                expect(all?.sessions[originKey]?.sessionId).toBe(originId);
                expect(all?.sessions[mainKey]?.sessionId).not.toBe(mainId);
              }
            }
          } finally {
            release.resolve();
          }
        },
        {
          agentCommand: FORKS,
          columns: 80,
          rows: 24,
          onState: (state) => {
            all = state;
          },
          openWith: async (options) => {
            if (options.fork !== undefined && hold) {
              const result = await openSession({
                ...options,
                agentCommand: ['env', 'CHORD_FAKE_REFUSE_FORK=1', ...FORKS],
              }).then(
                async (session) => {
                  await session.close();

                  throw new Error('the fake did not refuse the fork');
                },
                (error: unknown) => error,
              );

              refused = true;

              await release.promise;

              throw result;
            }

            return openSession(options);
          },
        },
      );
    });
  }

  for (const columns of [80, 120]) {
    test(`copied views diverge and nested dividers replay once without source history at ${columns} columns`, async () => {
      let all: WindowedState | undefined;

      await withWindow(
        async (window) => {
          await send(window, '/echo source-marker');
          await until(
            'main idle',
            () => all?.sessions[all.front]?.transcript.turn.status === 'idle',
          );

          const mainKey = all!.front;
          const snapshot = all!.sessions[mainKey]!.transcript;

          await send(window, '/fork alpha');
          await window.shows('╭─ alpha ');
          await window.shows('── forked from main · ');

          const alphaKey = all!.front;
          const alphaId = all!.sessions[alphaKey]!.sessionId;

          expect(
            entries(all, alphaKey).slice(0, snapshot.entries.length),
          ).toEqual([...snapshot.entries]);
          expect(JSON.stringify(entries(all, alphaKey))).not.toContain(
            '/fork alpha',
          );
          expect(
            entries(all, mainKey).filter((entry) => entry.kind === 'forked'),
          ).toEqual([]);
          await send(window, '/echo fork-marker');
          await until(
            'alpha idle',
            () => all?.sessions[alphaKey]?.transcript.turn.status === 'idle',
          );
          await choose(window, 'main');
          await send(window, '/echo main-later-marker');
          await until(
            'main idle again',
            () => all?.sessions[mainKey]?.transcript.turn.status === 'idle',
          );
          await choose(window, 'alpha');
          expect(JSON.stringify(entries(all, alphaKey))).not.toContain(
            'main-later-marker',
          );
          expect(JSON.stringify(entries(all, mainKey))).not.toContain(
            'fork-marker',
          );
          await send(window, '/fork beta');
          await window.shows('╭─ beta ');
          await window.shows('── forked from alpha · ');

          const betaKey = all!.front;
          const betaId = all!.sessions[betaKey]!.sessionId;
          const dividers = entries(all, betaKey).flatMap((entry) =>
            entry.kind === 'forked' ? [entry] : [],
          );

          expect(dividers.map((entry) => entry.from)).toEqual([
            'main',
            'alpha',
          ]);
          expect(JSON.stringify(entries(all, betaKey))).not.toContain(
            '/fork beta',
          );
          expect(JSON.stringify(entries(all, betaKey))).not.toContain(
            'main-later-marker',
          );
          await send(window, '/echo beta-marker');
          await until(
            'beta idle',
            () => all?.sessions[betaKey]?.transcript.turn.status === 'idle',
          );

          const directory = join(window.dir, 'state', 'records');
          let records: RecordEntry[][] = [];
          const own = (id: string | undefined) =>
            records.find((record) =>
              record.some(
                (entry) => entry.type === 'session' && entry.sessionId === id,
              ),
            );

          await until('both fork records flushed', async () => {
            records = await Promise.all(
              (await readdir(directory)).map(async (file) =>
                parseRecord(await readFile(join(directory, file), 'utf8')),
              ),
            );

            return (
              own(betaId)?.some(
                (entry) =>
                  entry.type === 'prompt' &&
                  entry.prompt.includes('beta-marker'),
              ) ?? false
            );
          });

          for (const [id, from, prompt] of [
            [alphaId, 'main', '/echo fork-marker'],
            [betaId, 'alpha', '/echo beta-marker'],
          ] as const) {
            const record = own(id);

            assert(record !== undefined);
            expect(
              record.flatMap((entry) =>
                entry.type === 'forked' ? [entry.from] : [],
              ),
            ).toEqual([from]);
            expect(
              record.flatMap((entry) =>
                entry.type === 'prompt' ? [entry.prompt] : [],
              ),
            ).toEqual([prompt]);

            const replay = recordActions(record)
              .filter(
                (action): action is TranscriptAction => action.type !== 'usage',
              )
              .reduce(reduceTranscript, emptyTranscript);
            const again = recordActions(record)
              .filter(
                (action): action is TranscriptAction => action.type !== 'usage',
              )
              .reduce(reduceTranscript, emptyTranscript);

            expect(
              replay.entries.filter((entry) => entry.kind === 'forked'),
            ).toHaveLength(1);
            expect(again).toEqual(replay);
            expect(JSON.stringify(replay.entries)).not.toContain(
              'source-marker',
            );
            expect(JSON.stringify(replay.entries)).not.toContain(
              'main-later-marker',
            );
          }
        },
        {
          agentCommand: FORKS,
          columns,
          rows: columns === 80 ? 24 : 40,
          onState: (state) => {
            all = state;
          },
        },
      );
    });
  }

  test('list_sessions uses exact independent IDs and caller markers; peers cannot message or close one another', async () => {
    const server = serveChord();
    const opened: Session[] = [];
    const clients: Client[] = [];

    try {
      await withWindow(
        async (window) => {
          try {
            await ready(window);
            await send(window, '/fork alpha');
            await window.shows('╭─ alpha ');
            await choose(window, 'main');
            await send(window, '/fork beta');
            await window.shows('╭─ beta ');
            expect(opened).toHaveLength(3);

            for (const [caller, session] of opened.entries()) {
              const client = await peerClient(session);

              clients.push(client);
              expect(
                answer(await client.callTool({ name: 'list_sessions' })),
              ).toEqual({
                sessions: opened.map((peer, index) => ({
                  id: peer.id,
                  runtime: 'fake',
                  model: 'fake-large',
                  ...(caller === index ? { you: true } : {}),
                })),
              });

              for (const to of caller === 0
                ? ['alpha', 'beta']
                : ['main', caller === 1 ? 'beta' : 'alpha']) {
                const message = await client.callTool({
                  name: 'send_message',
                  arguments: { to, text: 'peer boundary fixture' },
                });
                const close = await client.callTool({
                  name: 'close_agent',
                  arguments: { to },
                });

                expect(message.isError).toBe(true);
                expect(close.isError).toBe(true);
              }
            }

            for (const session of opened) {
              expect([...session.agentPids]).toHaveLength(1);
            }
          } finally {
            await Promise.all(clients.map((client) => client.close()));
          }
        },
        {
          agentCommand: FORKS,
          server,
          columns: 120,
          rows: 40,
          openWith: async (options) => {
            const session = await openSession(options);

            opened.push(session);

            return session;
          },
        },
      );
    } finally {
      await server.close();
    }
  });

  for (const ending of ['x', 'quit'] as const) {
    test(`main clear preserves a fork's task and monitor; ${ending} reaps both`, async () => {
      const server = serveChord();
      const opened: Session[] = [];
      const clients: Client[] = [];

      try {
        await withWindow(
          async (window) => {
            try {
              await ready(window);
              await send(window, '/fork owner');
              await window.shows('╭─ owner ');

              const fork = opened[1];

              assert(fork !== undefined);

              const client = await peerClient(fork);

              clients.push(client);

              const started = await client.callTool({
                name: 'monitor',
                arguments: {
                  command: quote([
                    process.execPath,
                    '-e',
                    'require("node:fs").writeFileSync("fork-monitor.pid", String(process.pid)); setInterval(() => {}, 1000)',
                  ]),
                  description: 'fork cleanup fixture',
                },
              });

              expect(started.isError).not.toBe(true);
              await until('monitor process recorded', () =>
                existsSync(join(window.dir, 'fork-monitor.pid')),
              );

              const monitorPid = Number(
                await readFile(join(window.dir, 'fork-monitor.pid'), 'utf8'),
              );
              const task = await client.callTool({
                name: 'spawn_task',
                arguments: {
                  agent: 'fake',
                  name: 'fork task',
                  prompt: 'costwait',
                },
              });

              expect(task.isError).not.toBe(true);
              await until(
                'task fake process up',
                () => window.pids.length === 3,
              );

              const taskPid = window.pids[2]!;
              const forkPid = [...fork.agentPids][0]!;

              await choose(window, 'main');
              await send(window, '/clear');
              await until('new main ready', () => opened.length === 4);
              expect(await isAlive(forkPid)).toBe(true);
              expect(await isAlive(taskPid)).toBe(true);
              expect(await isAlive(monitorPid)).toBe(true);

              if (ending === 'x') {
                await pickRow(window, 'owner');
                await window.press('x');
                await window.shows('x again to stop it and close');
                await window.press('x');
                await until(
                  'fork row removed',
                  () => namedRow(window.frame(), 'owner') === -1,
                );
              } else {
                await quitAll(window);
              }

              for (const pid of [forkPid, taskPid, monitorPid]) {
                await until(
                  'owned process reaped',
                  async () => !(await isAlive(pid)),
                );
              }
            } finally {
              await Promise.all(clients.map((client) => client.close()));
            }
          },
          {
            agentCommand: FORKS,
            startupOf: () => ({ agentCommand: FORKS }),
            server,
            columns: 80,
            rows: 24,
            openWith: async (options) => {
              const session = await openSession(options);

              opened.push(session);

              return session;
            },
          },
        );
      } finally {
        await server.close();
      }
    });
  }
});
