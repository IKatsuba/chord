/**
 * An agent that never answers its start, stopped with its window when it
 * closes or quits (CHD-489).
 */
import { describe, expect, test } from 'bun:test';
import { withChild, pickAgent, readyAgent } from './child_window.tsx';
import { execFile } from 'node:child_process';
import { AgentExitError } from '../../../src/acp/process.ts';
import { openSession } from '../../../src/session/session.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  DOWN,
  isAlive,
  quitAll,
  ready,
  send,
  until,
  withWindow,
} from './render.tsx';

describe('an agent that never answers its start is stopped with its window (CHD-489)', () => {
  /** The pids of every process whose command line holds `tag`. */
  function tagged(tag: string): Promise<number[]> {
    // pgrep exits 1 when nothing matches, which is an answer too.
    return new Promise((resolve) => {
      execFile('pgrep', ['-f', tag], (_error, stdout) =>
        resolve(stdout.split('\n').filter(Boolean).map(Number)),
      );
    });
  }

  /** The wedged fake under `tag`: it never answers `initialize`. */
  const wedged = (tag: string) =>
    fakeAgentCommand(undefined, '--hang', 'start', tag);

  test("a tab's agent still starting is gone once its window has closed", async () => {
    const tag = `chord-wedged-${crypto.randomUUID()}`;
    const command = fakeAgentCommand();

    await withWindow(
      async (window) => {
        await ready(window);
        await window.type('/new codex');
        await window.press('\r');
        await until(
          'the wedged agent',
          async () => (await tagged(tag)).length > 0,
        );
        await window.shows('Starting codex…');
      },
      {
        runtimes: ['fake', 'codex'],
        startupOf: (agent) => ({
          agentCommand: agent === 'codex' ? wedged(tag) : command,
        }),
      },
    );

    expect(await tagged(tag)).toStrictEqual([]);
  });

  for (const [what, failure] of [
    ['its agent did not exit', () => new AgentExitError([4242])],
    [
      'its agent did not start, and did not exit',
      () =>
        new AggregateError(
          [new Error('given up'), new AgentExitError([4242])],
          'The agent did not start, and did not exit.',
        ),
    ],
  ] as const) {
    test(`a window fails when a start given up says ${what}`, async () => {
      const command = fakeAgentCommand();
      // codex's start never comes, and gives up saying its agent stayed.
      const openWith: typeof openSession = (options) =>
        options.agent === 'codex'
          ? new Promise((_resolve, reject) =>
              options.signal?.addEventListener('abort', () =>
                reject(failure()),
              ),
            )
          : openSession(options);

      await expect(
        withWindow(
          async (window) => {
            await ready(window);
            await window.type('/new codex');
            await window.press('\r');
            await window.shows('Starting codex…');
          },
          {
            runtimes: ['fake', 'codex'],
            openWith,
            startupOf: () => ({ agentCommand: command }),
          },
        ),
      ).rejects.toThrow('an agent still starting did not stop with its window');
    });
  }

  test('a child still starting is gone once its window has closed', async () => {
    const tag = `chord-wedged-${crypto.randomUUID()}`;
    const server = serveChord();
    const admit = server.admit.bind(server);
    let main: Parameters<typeof admit>[0] | undefined;
    const command = fakeAgentCommand();

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

          if (main === undefined) {
            throw new Error('main was not admitted');
          }

          await main.window.open(main.key, {
            agent: 'codex',
            name: 'foreign',
            prompt: 'text',
          });
          await window.shows('foreign');
          await until(
            'the wedged agent',
            async () => (await tagged(tag)).length > 0,
          );
        },
        {
          server,
          runtimes: ['fake', 'codex'],
          agentCommand: command,
          startupOf: (agent) => ({
            agentCommand: agent === 'codex' ? wedged(tag) : command,
          }),
        },
      );
    } finally {
      await server.close();
    }

    expect(await tagged(tag)).toStrictEqual([]);
  });
});

describe('CHD-489 tester: startup cleanup across close and quit', () => {
  /** Process lookup errors must not count as proof that an agent exited. */
  function processes(tag: string): Promise<number[]> {
    return new Promise((resolve, reject) => {
      execFile('pgrep', ['-f', tag], (error, stdout) => {
        if (error !== null && error.code !== 1) {
          reject(error);

          return;
        }

        resolve(stdout.split('\n').filter(Boolean).map(Number));
      });
    });
  }

  {
    for (const quit of [false, true]) {
      test(`${quit ? 'quit' : 'close'} stops a selected child before initialize replies`, async () => {
        const tag = `chord-start-qa-${crypto.randomUUID()}`;
        const server = serveChord();
        const admit = server.admit.bind(server);
        let main: Parameters<typeof admit>[0] | undefined;
        const command = fakeAgentCommand();

        server.admit = (caller) => {
          if (caller.role === 'person') {
            main = caller;
          }

          return admit(caller);
        };

        try {
          await withWindow(
            async (window) => {
              await readyAgent(window);
              {
                if (main === undefined) {
                  throw new Error('main was not admitted');
                }

                await main.window.open(main.key, {
                  agent: 'codex',
                  name: 'starting-child',
                  prompt: 'text',
                });
                await window.shows('starting-child');
                await window.press(DOWN);
                await window.press(DOWN);
                await window.press('\r');
              }

              await window.shows('Starting codex…');
              await until(
                'the tagged agent exists',
                async () => (await processes(tag)).length > 0,
              );

              if (quit) {
                await quitAll(window);
              } else {
                await window.press(DOWN);
                await window.press('x');
              }

              await until(
                'the starting agent stops after the action',
                async () => (await processes(tag)).length === 0,
              );

              if (!quit) {
                expect(window.frame()).not.toContain('Starting codex…');
                await send(window, 'text');
                await window.shows('came in chunks.');
              }
            },
            {
              server,
              columns: quit ? 120 : 80,
              rows: quit ? 40 : 24,
              runtimes: ['fake', 'codex'],
              agentCommand: command,
              startupOf: (agent) => ({
                agentCommand:
                  agent === 'codex'
                    ? fakeAgentCommand(undefined, '--hang', 'start', tag)
                    : command,
              }),
            },
          );
          expect(await processes(tag)).toStrictEqual([]);
        } finally {
          await server.close();
        }
      });
    }
  }

  test('quit stops the main agent before initialize replies', async () => {
    const tag = `chord-main-start-qa-${crypto.randomUUID()}`;

    await withWindow(
      async (window) => {
        await window.shows('Starting codex…');
        await until(
          'the main agent exists before initialize',
          async () => (await processes(tag)).length > 0,
        );
        await quitAll(window);
        await until(
          'quit stopped the starting main',
          async () => (await processes(tag)).length === 0,
        );
      },
      {
        agent: 'codex',
        runtimes: ['codex'],
        whileStarting: true,
        columns: 120,
        rows: 40,
        startupOf: () => ({
          agentCommand: fakeAgentCommand(undefined, '--hang', 'start', tag),
        }),
      },
    );
    expect(await processes(tag)).toEqual([]);
  });

  for (const stopFailed of [false, true]) {
    test(`a start rejected before teardown ${stopFailed ? 'reports its nested cleanup error' : 'accepts an ordinary refusal'}`, async () => {
      const failure = stopFailed
        ? new AggregateError(
            [new AggregateError([new AgentExitError([4242])], 'inner')],
            'early cleanup failure',
          )
        : new Error('ordinary startup refusal');
      const command = fakeAgentCommand();
      const result = withChild(
        async (window) => {
          await readyAgent(window);
          await send(window, 'agentother');
          await pickAgent(window, 'other');
          await window.shows('codex did not start:');
        },
        {
          runtimes: ['fake', 'codex'],
          agentCommand: fakeAgentCommand(undefined, '--child-runtime', 'codex'),
          startupOf: () => ({ agentCommand: command }),
          openWith: (options) =>
            options.agent === 'codex'
              ? Promise.reject(failure)
              : openSession(options),
        },
      );

      if (stopFailed) {
        await expect(result).rejects.toThrow(
          'an agent still starting did not stop with its window',
        );
      } else {
        await result;
      }
    });
  }

  test('a successful start delivered during unmount still has its agent reaped', async () => {
    const command = fakeAgentCommand();
    const pids: number[] = [];
    let initialized = false;

    await withChild(
      async (window) => {
        await readyAgent(window);
        await send(window, 'agentother');
        await pickAgent(window, 'other');
        await until(
          'the child initializes before its open is delivered',
          () => initialized,
        );
        await window.shows('Starting codex…');
        expect(pids.length).toBeGreaterThan(0);
      },
      {
        runtimes: ['fake', 'codex'],
        agentCommand: fakeAgentCommand(undefined, '--child-runtime', 'codex'),
        startupOf: () => ({ agentCommand: command }),
        openWith: async (options) => {
          const session = await openSession(options);

          if (options.agent === 'codex') {
            pids.push(...session.agentPids);

            initialized = true;

            await new Promise<void>((resolve) => {
              if (options.signal?.aborted) {
                resolve();
              } else {
                options.signal?.addEventListener('abort', () => resolve(), {
                  once: true,
                });
              }
            });
          }

          return session;
        },
      },
    );

    for (const pid of pids) {
      expect(await isAlive(pid)).toBe(false);
    }
  });
});
