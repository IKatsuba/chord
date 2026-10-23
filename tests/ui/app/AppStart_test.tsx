/**
 * An agent that never answers its start, stopped with its window when it
 * closes or quits (CHD-489).
 */
import { describe, expect, test } from 'bun:test';
import { execFile } from 'node:child_process';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { SignInBlock } from '../../../src/ui/app/SignIn.tsx';
import { waysOf } from '../../../src/session/sign_in.ts';
import { draw } from '../harness.tsx';
import { AgentExitError } from '../../../src/acp/process.ts';
import { openSession } from '../../../src/session/session.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { TRACEBACK_ERROR } from '../../fixtures/fake_agent/options.ts';
import { StartFailureBlock } from '../../../src/ui/app/StartFailure.tsx';
import {
  DOWN,
  isAlive,
  leader,
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

  for (const child of [false, true]) {
    for (const quit of [false, true]) {
      test(`${quit ? 'quit' : 'close'} stops a selected ${child ? 'child' : 'tab'} before initialize replies`, async () => {
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
              await ready(window);

              if (child) {
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
              } else {
                await send(window, '/new codex');
              }

              await window.shows('Starting codex…');
              await until(
                'the tagged agent exists',
                async () => (await processes(tag)).length > 0,
              );

              if (quit) {
                await quitAll(window);
              } else if (child) {
                await window.press(DOWN);
                await window.press('x');
              } else {
                await leader(window, 'k');
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

  for (const stopFailed of [false, true]) {
    test(`a start rejected before teardown ${stopFailed ? 'reports its nested cleanup error' : 'accepts an ordinary refusal'}`, async () => {
      const failure = stopFailed
        ? new AggregateError(
            [new AggregateError([new AgentExitError([4242])], 'inner')],
            'early cleanup failure',
          )
        : new Error('ordinary startup refusal');
      const command = fakeAgentCommand();
      const result = withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/new codex');
          await window.shows('codex did not start:');
        },
        {
          runtimes: ['fake', 'codex'],
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

    await withWindow(
      async (window) => {
        await ready(window);
        await send(window, '/new codex');
        await until(
          'the child initializes before its open is delivered',
          () => initialized,
        );
        await window.shows('Starting codex…');
        expect(pids.length).toBeGreaterThan(0);
      },
      {
        runtimes: ['fake', 'codex'],
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

describe('CHD-435 tester: method layout', () => {
  for (const columns of [80, 120]) {
    test(`long descriptions hang at their method column and only names gain bold at ${columns} columns`, async () => {
      const level = chalk.level;
      const description =
        'Description begins ' +
        'long words and 日本語 '.repeat(12) +
        'description ends.';
      const signIn = {
        message: 'Authentication required',
        ways: waysOf([
          { id: 'empty', name: ' ', description: ' ' },
          { id: 'description', name: '', description: 'Description only' },
          { id: 'long', name: 'Method name', description },
          { id: 'name', name: 'Name only' },
        ]),
      };

      chalk.level = 3;

      const drawn = await draw(
        <box>
          <SignInBlock agent='fake' signIn={signIn} />
        </box>,
        { columns, rows: 24 },
      );

      try {
        const frame = drawn.frame();
        const rows = stripAnsi(frame).split('\n');
        const method = rows.find((row) => row.includes('Method name'))!;
        const start = method.indexOf('Method name');
        const tail = rows.find((row) => row.includes('description ends.'))!;

        expect(
          rows
            .find((row) => row.includes('Description only'))
            ?.indexOf('Description'),
        ).toBe(start);
        expect(tail.search(/\S/)).toBe(start);
        expect(frame).toContain('\x1b[1mMethod name\x1b[0m');
        expect(frame).toContain('\x1b[1mName only\x1b[0m');
        expect(frame).not.toContain('\x1b[1mDescription');
        expect(stripAnsi(frame).replace(/\s+/g, ' ')).toContain(
          'Description only Method name · Description begins',
        );
        expect(signIn.ways).toHaveLength(3);
      } finally {
        await drawn.unmount();

        chalk.level = level;
      }
    });
  }
});

describe('CHD-435 tester: child start failure notes', () => {
  for (const columns of [80, 120]) {
    for (const kind of ['methods', 'linkother']) {
      test(`${kind} child failure reaches the parent with the appropriate agent-facing note at ${columns} columns`, async () => {
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

              if (main === undefined) {
                throw new Error('main was not admitted');
              }

              const parent = window.session();
              const prompts: string[] = [];

              if (parent === undefined) {
                throw new Error('parent session missing');
              }

              const prompt = parent.prompt.bind(parent);

              parent.prompt = (text, ...args) => {
                prompts.push(text);

                return prompt(text, ...args);
              };

              await main.window.open(main.key, {
                agent: 'codex',
                name: 'parser',
                prompt: 'text',
              });
              await until('the parent to receive the failed-child note', () =>
                window
                  .frame()
                  .replace(/\s+/g, ' ')
                  .includes('It takes no messages; open_agent starts another.'),
              );

              await until(
                'the failed-child note to reach the real parent prompt',
                () =>
                  prompts.some((text) =>
                    text.includes(
                      'It takes no messages; open_agent starts another.',
                    ),
                  ),
              );

              const frame = window.frame().replace(/\s+/g, ' ');
              const note = prompts.join('\n');

              expect(frame).toContain('parser (codex) did not start:');

              if (kind === 'methods') {
                expect(note).toContain(
                  'It offers: Log in with the fake (Run `fake login` in the terminal), Log in with SSO.',
                );
                expect(note).toContain(
                  "chord does not sign agents in: the person signs in with codex's own CLI in a terminal, or sets its API key where it offers one.",
                );
              } else {
                expect(frame).toContain('The fake could not open its session.');
                expect(frame).not.toContain('the person signs in');
                expect(frame).not.toContain('It offers:');
              }
            },
            {
              columns,
              rows: 40,
              server,
              runtimes: ['fake', 'codex'],
              agentCommand: fakeAgentCommand(undefined, '--echo-messages'),
              startupOf: (agent) => ({
                agentCommand:
                  agent === 'codex'
                    ? fakeAgentCommand(undefined, '--auth-required', kind)
                    : fakeAgentCommand(undefined, '--echo-messages'),
              }),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }
});

describe('CHD-435 tester: filtered methods', () => {
  test('all blank methods leave the fixed guidance without an offers heading', async () => {
    const drawn = await draw(
      <box>
        <SignInBlock
          agent='fake'
          signIn={{
            message: 'Authentication required',
            ways: waysOf([{ id: 'empty', name: ' ', description: ' ' }]),
          }}
        />
      </box>,
      { columns: 120, rows: 10 },
    );

    try {
      const frame = stripAnsi(drawn.frame()).replace(/\s+/g, ' ');

      expect(frame).not.toContain('offers this');
      expect(frame).toContain(
        "⎿ chord does not sign agents in. Sign in with fake's own CLI",
      );
    } finally {
      await drawn.unmount();
    }
  });
});

describe('CHD-454 tester: real startup failure screens and notes', () => {
  const closed = () => [
    'sh',
    '-c',
    'printf "  raw diagnostic\\n" >&2; exec 1>&-; exec sleep 30',
  ];

  for (const columns of [80, 120]) {
    for (const step of [
      'initialize',
      'session/load',
      'session/resume',
    ] as const) {
      test(`${step} names the actual failure without a custom-command pin at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await send(window, '/new codex');

            const headline =
              step === 'initialize'
                ? 'it closed its connection before answering initialize.'
                : `it refused ${step}: The fake could not open its session.`;

            await until('the structured headline', () =>
              window.frame().replace(/\s+/g, ' ').includes(headline),
            ).catch((error: Error) => {
              throw new Error(`${error.message}\n${window.frame()}`);
            });

            const frame = window.frame().replace(/\s+/g, ' ');

            expect(frame).not.toContain('chord ran');
            expect(frame.split('⎿')[0]).not.toContain('raw diagnostic');

            if (step === 'initialize') {
              expect(frame).toContain('The end of its stderr: raw diagnostic');
            }
          },
          {
            columns,
            rows: 40,
            runtimes: ['fake', 'codex'],
            openWith: (options) =>
              openSession(
                options.agent === 'codex'
                  ? {
                      ...options,
                      agentCommand:
                        step === 'initialize'
                          ? closed()
                          : fakeAgentCommand(
                              undefined,
                              '--auth-required',
                              'linkother',
                              ...(step === 'session/resume'
                                ? ['--resume-only', '--no-load']
                                : []),
                            ),
                      ...(step === 'initialize'
                        ? {}
                        : {
                            resume: {
                              sessionId: crypto.randomUUID(),
                              cwd: options.cwd,
                            },
                          }),
                    }
                  : options,
              ),
          },
        ));
    }

    for (const shape of ['closed', 'traceback']) {
      test(`a ${shape} child gives its parent the compact failure note at ${columns} columns`, async () => {
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

              const parent = window.session();
              const prompts: string[] = [];

              if (main === undefined || parent === undefined) {
                throw new Error('main missing');
              }

              const prompt = parent.prompt.bind(parent);

              parent.prompt = (text, ...args) => {
                prompts.push(text);

                return prompt(text, ...args);
              };

              await main.window.open(main.key, {
                agent: 'codex',
                name: 'parser',
                prompt: 'text',
              });
              await until('the compact failed-child note', () =>
                prompts.some((text) =>
                  text.includes(
                    'It takes no messages; open_agent starts another.',
                  ),
                ),
              );

              const note = prompts.join('\n');
              const headline =
                shape === 'closed'
                  ? 'it closed its connection before answering initialize.'
                  : 'it exited with code 1 before answering initialize.';

              expect(note).toContain(
                `parser (codex) did not start: ${headline}`,
              );
              expect(note).toContain(
                shape === 'closed'
                  ? 'Its stderr ended: "raw diagnostic".'
                  : `Its stderr ended: "${TRACEBACK_ERROR}".`,
              );
              expect(note).not.toContain('The end of its stderr:');
              expect(note).not.toContain('module_59.py');
              expect(note).not.toContain('chord ran');
            },
            {
              columns,
              rows: 40,
              server,
              runtimes: ['fake', 'codex'],
              startupOf: (agent) => ({
                agentCommand:
                  agent === 'codex'
                    ? shape === 'closed'
                      ? closed()
                      : fakeAgentCommand(
                          undefined,
                          '--start-fails',
                          'traceback',
                        )
                    : fakeAgentCommand(),
              }),
            },
          );
        } finally {
          await server.close();
        }
      });
    }
  }

  test('the cut marker is dim and long stderr wraps at the tail column, with its truncation mark', async () => {
    const level = chalk.level;

    chalk.level = 3;

    const drawn = await draw(
      <box>
        <StartFailureBlock
          agent='fake'
          failure={{
            step: 'initialize',
            exit: { code: 1 },
            stderr: {
              cut: 3,
              lines: ['    ' + 'x'.repeat(1020) + '…', 'final diagnostic'],
            },
          }}
        />
      </box>,
      { columns: 80, rows: 24 },
    );

    try {
      const frame = drawn.frame();
      const rows = stripAnsi(frame).split('\n');
      const first = rows.findIndex((row) => row.includes('xxxxx'));
      const tailColumn = rows
        .find((row) => row.includes('final diagnostic'))!
        .indexOf('final');

      expect(frame).toContain('\x1b[2m… +3 lines\x1b[0m');
      // OpenTUI puts the indent on a blank row before a word wider than
      // the available row, then wraps the word at the tail column.
      expect(rows[first - 1]?.trim()).toBe('');
      expect(rows[first]!.indexOf('x')).toBe(tailColumn);
      expect(rows[first + 1]!.indexOf('x')).toBe(tailColumn);
      expect(rows.some((row) => row.trimEnd().endsWith('…'))).toBe(true);
    } finally {
      await drawn.unmount();

      chalk.level = level;
    }
  });
});
