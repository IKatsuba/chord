/**
 * A start that fails as the window draws it: the step, the agent's own
 * words, the ways in it offers and chord's way on (CHD-435, CHD-454).
 */
import { describe, expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { waysOf } from '../../../src/session/sign_in.ts';
import { openSession } from '../../../src/session/session.ts';
import { serveChord } from '../../../src/server/server.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { ready, send, until, withWindow } from './render.tsx';
import { SignInBlock } from '../../../src/ui/app/SignIn.tsx';
import { StartFailureBlock } from '../../../src/ui/app/StartFailure.tsx';
import { TRACEBACK_ERROR } from '../../fixtures/fake_agent/options.ts';
import { draw } from '../harness.tsx';
import { failedFrame, failedFrameShowing } from './start_failure.tsx';

for (const columns of [80, 120]) {
  test(`a start the agent refuses for want of a login hangs its ways in and chord's way on under the failure at ${columns} columns (CHD-435)`, async () => {
    const frame = await failedFrame(columns, '--auth-required', 'methods');
    const rows = frame.split('\n');

    expect(frame.replace(/\s+/g, ' ')).toContain(
      "⏺ codex did not start: Authentication required: run `fake login` from your terminal, or set FAKE_API_KEY ⎿ codex offers these sign-ins: Log in with the fake · Run `fake login` in the terminal Log in with SSO chord does not sign agents in. Sign in with codex's own CLI in a terminal, or set its API key where it offers one.",
    );
    // Each way in sits two in under the block's text.
    expect(
      rows.find((row) => row.includes('Log in with SSO'))?.indexOf('Log'),
    ).toStrictEqual(
      (rows.find((row) => row.includes('codex offers'))?.indexOf('codex') ??
        0) + 2,
    );
  });
}

test("a start that needs a login, its agent offering no ways in, says chord's way on alone (CHD-435)", async () => {
  const read = (await failedFrame(120, '--auth-required', 'bare')).replace(
    /\s+/g,
    ' ',
  );

  expect(read).toContain(
    "⏺ codex did not start: Authentication required ⎿ chord does not sign agents in. Sign in with codex's own CLI in a terminal, or set its API key where it offers one.",
  );
  expect(read).not.toContain('offers this');
});

for (const columns of [80, 120]) {
  test(`an agent that exits before initialize says so with its code and hangs the end of its stderr under it at ${columns} columns (CHD-454)`, async () => {
    const frame = await failedFrameShowing(
      columns,
      TRACEBACK_ERROR,
      '--start-fails',
      'traceback',
    );
    const read = frame.replace(/\s+/g, ' ');

    expect(read).toContain(
      '⏺ codex did not start: it exited with code 1 before answering initialize. ⎿ The end of its stderr: … +116 lines from .module_58 import run',
    );
    expect(read).toContain(`from .module_60 import run ${TRACEBACK_ERROR}`);

    // The tail sits two in under the block's text, and keeps its own indent.
    const rows = frame.split('\n');
    const heading = rows.find((row) => row.includes('The end of its stderr:'))!;
    const frame58 = rows.find((row) =>
      row.includes('from .module_58 import run'),
    )!;

    expect(frame58.indexOf('from')).toBe(heading.indexOf('The') + 2 + 4);
  });
}

test('an agent that serves no ACP sessions, or one that refuses its session another way, says which (CHD-454)', async () => {
  expect(
    (
      await failedFrameShowing(
        120,
        'not at this version.',
        '--start-fails',
        'notacp',
      )
    ).replace(/\s+/g, ' '),
  ).toContain(
    '⏺ codex did not start: it does not serve ACP sessions: not an ACP agent, or not at this version.',
  );

  // Its message may break after a `.` (Q157): read with no whitespace.
  const alias = (
    await failedFrameShowing(120, 'entry)', '--start-fails', 'alias')
  ).replace(/\s+/g, '');

  expect(alias).toContain(
    '⏺codexdidnotstart:itrefusedsession/new:session/newrequires`agentAlias`(aliasofaconfigured[agents.<alias>]entry)',
  );
  // Not zeroclaw: no way on chord knows.
  expect(alias).not.toContain('Set a default agent');
  expect(alias).not.toContain('⎿');
});

describe('the block under a start failure, by what chord knows (CHD-454)', () => {
  const block = async (node: React.ReactNode) => {
    const drawn = await draw(<box>{node}</box>, { columns: 80, rows: 12 });

    try {
      return drawn.frame().replace(/\s+/g, ' ').trim();
    } finally {
      await drawn.unmount();
    }
  };

  test("a registry agent's names the pin chord ran, a sign-in's first", async () => {
    expect(
      await block(
        <StartFailureBlock
          agent='agoragentic-acp'
          failure={{
            step: 'session/new',
            code: -32601,
            pinned: 'agoragentic-mcp@1.3.0',
          }}
        />,
      ),
    ).toBe(
      '⎿ chord ran agoragentic-mcp@1.3.0, the version the ACP Registry names.',
    );
    expect(
      await block(
        <SignInBlock
          agent='qoder'
          signIn={{ message: 'Authentication required', ways: [] }}
          pinned='@qoder-ai/qodercli@0.2.14'
        />,
      ),
    ).toBe(
      "⎿ chord ran @qoder-ai/qodercli@0.2.14, the version the ACP Registry names. chord does not sign agents in. Sign in with qoder's own CLI in a terminal, or set its API key where it offers one.",
    );
  });

  test("zeroclaw's -32602 says how to set a default agent, and nothing else of it does", async () => {
    const way =
      'Set a default agent: [acp] default_agent = "<alias>" in ZeroClaw\'s config, or start it with zeroclaw acp --agent <alias>.';

    expect(
      await block(
        <StartFailureBlock
          agent='zeroclaw'
          failure={{ step: 'session/new', code: -32602 }}
        />,
      ),
    ).toBe(`⎿ ${way}`);
    expect(
      await block(
        <StartFailureBlock
          agent='zeroclaw'
          failure={{ step: 'session/new', code: -32601 }}
        />,
      ),
    ).toBe('');
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
  for (const kind of ['methods', 'linkother']) {
    test(`${kind} child failure reaches the parent with the appropriate agent-facing note at both terminal widths`, async () => {
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

            for (const columns of [80, 120]) {
              await window.resize({ columns });

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
            }
          },
          {
            columns: 80,
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

  for (const step of [
    'initialize',
    'session/load',
    'session/resume',
  ] as const) {
    test(`${step} names the actual failure without a custom-command pin at both terminal widths`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, '/new codex');

          const headline =
            step === 'initialize'
              ? 'it closed its connection before answering initialize.'
              : `it refused ${step}: The fake could not open its session.`;

          for (const columns of [80, 120]) {
            await window.resize({ columns });

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
          }
        },
        {
          columns: 80,
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
    test(`a ${shape} child gives its parent the compact failure note`, async () => {
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

            expect(note).toContain(`parser (codex) did not start: ${headline}`);
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
            columns: 80,
            rows: 40,
            server,
            runtimes: ['fake', 'codex'],
            startupOf: (agent) => ({
              agentCommand:
                agent === 'codex'
                  ? shape === 'closed'
                    ? closed()
                    : fakeAgentCommand(undefined, '--start-fails', 'traceback')
                  : fakeAgentCommand(),
            }),
          },
        );
      } finally {
        await server.close();
      }
    });
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
