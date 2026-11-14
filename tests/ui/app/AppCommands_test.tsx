/**
 * The window's slash commands and the keys around a child beside main:
 * /clear, /cost, /context, /status, /help and /exit, a child's notices,
 * and a start that fails.
 */
import { describe, expect, test } from 'bun:test';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { RecordEntry } from '../../../src/session/record.ts';
import { openSession } from '../../../src/session/session.ts';
import {
  earlierSessions,
  readRecords,
  summaryOf,
} from '../../../src/session/sessions.ts';
import { draw } from '../harness.tsx';
import { type Resumable } from '../../../src/session/sessions.ts';
import { App } from '../../../src/ui/app/App.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_D,
  ESC,
  inputAsked,
  isAlive,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  statusReports,
  TAB,
  until,
  UP,
  withWindow,
  type Window,
} from './render.tsx';
import manifest from '../../../package.json' with { type: 'json' };

import { OSC9, writes, reported } from './app_window.tsx';

const VERSION = manifest.version;

test('/clear starts a new session with an empty transcript', () =>
  withWindow(async (window) => {
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
    await until('the turn to end', () => !window.frame().includes('Working'));

    const first = window.session();

    await window.type('/cl');
    await window.press('\r');
    await until('a new session', () => window.session() !== first);
    await ready(window);
    expect(
      !window.frame().includes('› text'),
      'the transcript stayed',
    ).toBeTruthy();
    expect(
      !window.frame().includes('in chunks'),
      'the reply stayed',
    ).toBeTruthy();
    expect(
      !promptRow(window)?.includes('/cl'),
      'the draft stayed',
    ).toBeTruthy();
    await until('the first agent to stop', () => first?.agentPids.size === 0);
    // The new session takes prompts, and history kept the command.
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
    await until('the turn to end', () => !window.frame().includes('Working'));
    await window.press(UP);
    await until(
      'the recalled prompt',
      () => promptRow(window)?.includes('› text') ?? false,
    );
    await window.press(UP);
    await until(
      'the command',
      () => promptRow(window)?.includes('› /clear') ?? false,
    );
    // A recalled command is history's: no list opens over it.
    expect(!window.frame().includes('/config'), 'the list opened').toBeTruthy();
  }));

test('/cost, /context and /status report what the agent said', () =>
  withWindow(
    async (window) => {
      await window.shows('Fake Large with a 1M context window');
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await window.shows('% context used');
      await send(window, 'tools');
      await until(
        'the second turn to report',
        () =>
          window.frame().includes('1% context used') &&
          !window.frame().includes('Working'),
      );

      const cost = await reported(window, '/cost');

      expect(cost).toContain('⎿  Total cost:   $0.0250');
      expect(cost).toContain('Tokens in:    2,000');
      expect(cost).toContain('Tokens out:   400');
      expect(cost).toContain('Cache read:   1,600');
      expect(cost).toMatch(/Session time: \d+s/);

      const context = await reported(window, '/context');

      expect(context).toContain('⎿  Used: 4,000 of 1,000,000 tokens (1%)');
      expect(context).toContain('Free: 996,000 tokens (99%)');

      const status = await reported(window, '/status');

      expect(status).toContain('⎿  Agent:     fake');
      expect(status).toContain(
        'Model:     Fake Large with a 1M context window',
      );
      expect(status).toContain('Mode:      Default');
      expect(status).toMatch(/Session: {3}[0-9a-f-]{36}/);
      expect(status).toContain('Directory:');
    },
    { rows: 60 },
  ));

test('/cost says so when the agent reports no usage', () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));

      const cost = await reported(window, '/cost');

      expect(cost).toContain(
        '⎿  fake has not reported what this session has used.',
      );
      expect(!cost.includes('$0'), cost).toBeTruthy();
      expect(await reported(window, '/context')).toContain(
        'fake has not reported how full its context window is.',
      );
    },
    { agentCommand: fakeAgentCommand(undefined, '--no-usage') },
  ));

test('/help opens the shortcuts and /exit quits', () =>
  withWindow(async (window) => {
    await window.type('/help');
    await window.press('\r');
    await window.shows('ctrl + o for verbose output');
    expect(
      !promptRow(window)?.includes('/help'),
      'the draft stayed',
    ).toBeTruthy();
    await window.press(ESC);
    await window.type('/exit');
    await window.press('\r');
    await until(
      'the agent to stop',
      () => window.session()?.agentPids.size === 0,
    );
  }));

test("the window's first row is its header's", () =>
  withWindow(
    async (window) => {
      const first = () => window.frame().split('\n')[0] ?? '';

      await window.shows('chord v');
      expect(first()).toContain(`chord v${VERSION}`);
    },
    { columns: 120, rows: 40 },
  ));

test("a child's permission is a notice while main is shown, and ctrl+x a goes to it", () =>
  withChild(
    async (window) => {
      const bytes = '\x1b]9;docs needs your permission: Write notes.txt\x07';

      await ready(window);
      await send(window, 'agentsheldgated');
      await window.shows('● docs needs your permission · ctrl+x a to go');
      // The notification goes out once the renderer is idle, after this frame.
      await until('the notification', () => writes(window, bytes) === 1);
      // The window never goes there by itself, so a digit typed here is a draft.
      await window.type('1');
      await until(
        'the digit in the draft',
        () => promptRow(window)?.includes('1') ?? false,
      );
      expect(!window.frame().includes('Do you want to proceed?')).toBeTruthy();
      await leader(window, 'a');
      await asked(window);
      await window.press('1');
      await until(
        'the permission answered',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      expect(writes(window, bytes)).toStrictEqual(1);
      await quitAll(window);
    },
    { columns: 120, rows: 40, notifications: OSC9 },
  ));

test('ctrl+x a with nothing waiting says so', () =>
  withWindow(async (window) => {
    await ready(window);
    await leader(window, 'a');
    await window.shows('Nothing waits on you');
  }));

test('/clear stops the command the session runs, as the session it ran in goes', () => {
  const stops = new Map<string, number>();

  return withWindow(
    async (window) => {
      await ready(window);
      await window.type('!');
      await window.type('sleep 60');
      await window.press('\r');
      await window.shows('sleep 60');
      expect(stops.get('sleep 60') ?? 0).toStrictEqual(0);
      await send(window, '/clear');
      await until('the command stopped', () => stops.get('sleep 60') === 1);
    },
    {
      columns: 120,
      rows: 40,
      shell: (command) => {
        const { promise: ended, resolve } = Promise.withResolvers<{
          stopped: boolean;
        }>();

        return {
          stop: () => {
            stops.set(command, (stops.get(command) ?? 0) + 1);
            resolve({ stopped: true });
          },
          ended,
        };
      },
    },
  );
});

test('ctrl+d with the session working quits at once, with its one session to resume and no agent left', async () => {
  let resumable: Resumable | undefined;

  await withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await window.press(CTRL_D);
      await until('the quit', () => resumable !== undefined);
      expect(resumable?.agent).toStrictEqual('fake');
      await until('the agent to stop', () =>
        Promise.all(window.pids.map(isAlive)).then((alive) =>
          alive.every((each) => !each),
        ),
      );
    },
    {
      columns: 120,
      rows: 40,
      // Slow enough that its turn still runs at the press.
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
      onQuit: (session) => (resumable = session),
    },
  );
});

test('a form left half filled in main is as it was on coming back from a child', () =>
  withChild(
    async (window) => {
      await ready(window);
      await openOther(window);
      await send(window, 'form');
      await inputAsked(window);
      await window.type('keep');
      await window.press(TAB);
      await window.type('a@b');
      await window.shows('Contact email  a@b');
      // other's reply is not yet seen, so ctrl+x a goes there.
      await leader(window, 'a');
      await until(
        "main's form gone with main",
        () => !window.frame().includes('Project name'),
      );
      // The status line names main as waiting instead.
      await window.shows('● main asks for input · ctrl+x a');
      await leader(window, 'a');
      await inputAsked(window);
      expect(window.frame()).toContain('Project name   keep');
      expect(window.frame()).toContain('Contact email  a@b');
      // The focus came back too: the next key goes on where the last left off.
      await window.type('.dev');
      await window.shows('Contact email  a@b.dev');
      await window.press(ESC);
      await window.shows('Elicitation answer: cancel');
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('an agent that does not start is an error line', async () => {
  const app = await draw(
    <App
      agent='fake'
      cwd='.'
      // Never chord's own state directory, though nothing is sent here.
      stateDir='/nonexistent/chord-state'
      open={() => Promise.reject(new Error('spawn fake ENOENT'))}
    />,
  );

  try {
    await until('the error line', () =>
      app.frame().includes('fake did not start: spawn fake ENOENT'),
    );
  } finally {
    await app.unmount();
  }
});

describe('CHD-493 U2 tester: aliases retire live per-agent work', () => {
  for (const columns of [80, 120]) {
    test(`/clear drops a running turn and its child at ${columns} columns`, () =>
      withChild(
        async (window) => {
          const main = window.session()!;

          await openOther(window);
          await send(window, 'slow');
          await window.shows('esc to interrupt');
          await send(window, '/clear');
          await readyAgent(window);
          await until('the old main and child stopped', () =>
            Promise.all(window.pids.slice(0, 2).map(isAlive)).then((alive) =>
              alive.every((each) => !each),
            ),
          );
          expect(window.session()).not.toBe(main);
          expect(window.frame()).not.toContain('other ·');
          expect(window.frame()).not.toMatch(/^ {4}other\s/m);
          expect(window.frame()).not.toContain('Working');
          await send(window, 'text');
          await window.shows('This reply came in chunks.');
          expect(window.frame()).not.toContain('› slow');
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          startupOf: () => ({
            agentCommand: fakeAgentCommand(
              undefined,
              '--child-runtime',
              'fake',
              '--step-ms',
              '20',
            ),
          }),
        },
      ));

    test(`/exit stops a hung child without arming at ${columns} columns`, async () => {
      let quit: Resumable | undefined;

      let quits = 0;

      await withChild(
        async (window) => {
          await openOther(window);
          await until('the hung child is working', () =>
            /^ {4}other\s.*working/m.test(window.frame()),
          );
          await send(window, '/exit');
          await until('quit was called', () => quit !== undefined);
          expect(quits).toBe(1);
          expect(quit?.agent).toStrictEqual('fake');
          await until('main and its hung child stopped', () =>
            Promise.all(window.pids.map(isAlive)).then((alive) =>
              alive.every((each) => !each),
            ),
          );
          expect(window.frame()).not.toContain('again to quit');
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          startupOf: (agent) => ({
            agentCommand:
              agent === 'codex'
                ? fakeAgentCommand(undefined, '--hang', 'turn')
                : fakeAgentCommand(undefined, '--child-runtime', 'codex'),
          }),
          onQuit: (resumable) => {
            quits++;

            quit = resumable;
          },
        },
      );
    });
  }
});

describe('CHD-621 tester: sign-in commands reach the agent', () => {
  for (const [columns, rows] of [
    [120, 40],
    [80, 24],
  ] as const) {
    for (const command of ['/login', '/logout']) {
      test(`${command} is an ordinary prompt at ${columns} by ${rows}`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await window.type('?');
            await window.shows('enter to send');
            expect(window.frame()).not.toContain('/login');
            expect(window.frame()).not.toContain('/logout');
            await window.press(ESC);
            await window.type('/lo');
            expect(window.frame()).not.toContain('/login');
            expect(window.frame()).not.toContain('/logout');
            await window.press(ESC);
            await window.press('\x03');
            await send(window, command);
            await window.shows('This reply came in chunks.');
            await until(
              'the command turn to finish',
              () => !window.frame().includes('Working'),
            );
            expect(window.frame()).not.toContain('ChatGPT');
            expect(window.frame()).not.toContain('Grok');
          },
          { columns, rows },
        ));
    }
  }
});

describe('/rename (CHD-629)', () => {
  test("names the session in front: how with no title, then the agent's title once it took it", () =>
    withWindow(
      async (window) => {
        await send(window, 'text');
        await window.shows('This reply came in chunks.');

        expect(await reported(window, '/rename')).toContain(
          '⎿  Name the session: /rename <title>',
        );

        await window.type('/rename Parser test tidy-up');
        await window.press('\r');
        await window.shows('⎿  Renamed to Parser test tidy-up');

        expect(await reported(window, '/rename')).toContain(
          'Name the session: /rename <title>. Now: Parser test tidy-up',
        );
      },
      { agentCommand: fakeAgentCommand(undefined, '--set-title', 'echo') },
    ));

  test("a refusal is an error note in the agent's words; an agent that takes no title is renamed in chord only", async () => {
    await withWindow(
      async (window) => {
        await window.shows('Fake Large with a 1M context window');
        await window.type('/rename Parser test tidy-up');
        await window.press('\r');
        await window.shows(
          'Could not rename: fake refused it: This version of the fake agent cannot rename a session.',
        );
      },
      { agentCommand: fakeAgentCommand(undefined, '--set-title', 'refuse') },
    );
    await withWindow(async (window) => {
      await window.shows('Fake Large with a 1M context window');
      await window.type('/rename Parser test tidy-up');
      await window.press('\r');
      await window.shows(
        'Renamed to Parser test tidy-up in chord only: fake takes no title, and its own may replace it',
      );
    });
  });
});

describe('CHD-629 tester: rename targets and terminal status', () => {
  interface TitleCall {
    sessionId: string;
    title: string;
  }

  const command = fakeAgentCommand(
    undefined,
    '--set-title',
    'echo',
    '--child-runtime',
    'fake',
  );
  const captureTitles =
    (calls: TitleCall[]): typeof openSession =>
    async (options) => {
      const session = await openSession(options);

      return {
        ...session,
        setTitle: (title) => {
          calls.push({ sessionId: session.id, title });

          return session.setTitle(title);
        },
      };
    };

  async function rename(window: Window, title: string) {
    await send(window, `/rename ${title}`);
    await window.shows(`Renamed to ${title}`);
  }

  test('an actual starting session refuses rename without queueing a title request', async () => {
    const calls: TitleCall[] = [];

    await withWindow(
      async (window) => {
        await window.shows('Starting');
        await send(window, '/rename While starting');
        await window.shows(
          'The session is not open yet; rename it once it is.',
        );
        expect(calls).toEqual([]);
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--hang', 'start'),
        whileStarting: true,
        openWith: captureTitles(calls),
      },
    );
  });

  test('an exited session refuses rename before calling setTitle', async () => {
    const calls: TitleCall[] = [];

    await withWindow(
      async (window) => {
        const session = window.session();

        assert(session);
        await session.close();
        await session.exited;
        await send(window, '/rename After exit');
        await window.shows('main has exited; its session cannot be renamed.');
        expect(calls).toEqual([]);
      },
      { agentCommand: command, openWith: captureTitles(calls) },
    );
  });

  test('a real task record resumed as main keeps its task title and refuses rename', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'chord-rename-task-'));
    const path = join(dir, 'task.jsonl');
    const id = crypto.randomUUID();
    const calls: TitleCall[] = [];
    const entries: RecordEntry[] = [
      {
        type: 'session',
        version: 1,
        sessionId: id,
        agent: 'fake',
        cwd: dir,
        at: 0,
        parent: 'parent',
        name: 'Task title',
        task: 'task-id',
      },
      { type: 'prompt', turnId: 't1', at: 1, prompt: 'Do the work', images: 0 },
      {
        type: 'result',
        turnId: 't1',
        result: { status: 'completed', stopReason: 'end_turn' },
      },
    ];

    try {
      const text =
        entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n';

      await writeFile(path, text);

      const record = summaryOf(path, text);

      assert(record);

      const [choice] = earlierSessions([record], { agent: 'fake', cwd: dir });

      assert(choice);
      await withWindow(
        async (window) => {
          expect(window.session()?.resumed?.task).toBe(true);
          await send(window, '/rename New task title');
          await window.shows(
            'main is a task; it keeps the title it was given.',
          );
          expect(calls).toEqual([]);
        },
        {
          agentCommand: fakeAgentCommand(
            undefined,
            '--set-title',
            'echo',
            '--resume-only',
          ),
          resume: choice.resume,
          openWith: captureTitles(calls),
        },
      );
    } finally {
      await rm(dir, { recursive: true });
    }
  });

  for (const columns of [80, 120]) {
    test(`the picked child alone is renamed, while OSC status keeps main's title at ${columns} columns`, async () => {
      const calls: TitleCall[] = [];
      const log: string[] = [];

      await withChild(
        async (window) => {
          await send(window, 'text');
          await window.shows('This reply came in chunks.');

          const mainId = window.session()?.id;

          assert(mainId);
          await rename(window, 'Main title');
          await until(
            'main OSC title',
            () => statusReports(log).at(-1)?.title === 'Main title',
          );
          await openOther(window);
          await pickAgent(window, 'other');
          await readyAgent(window);
          await rename(window, 'Child title');

          expect(calls[0]).toEqual({ sessionId: mainId, title: 'Main title' });
          expect(calls[1]?.title).toBe('Child title');
          expect(calls[1]?.sessionId).not.toBe(mainId);
          expect(statusReports(log).at(-1)?.title).toBe('Main title');
          await until('both recorded titles', async () => {
            const records = await readRecords(join(window.dir, 'state'));

            return (
              records.some(
                (record) =>
                  record.sessionId === mainId && record.title === 'Main title',
              ) &&
              records.some(
                (record) =>
                  record.sessionId === calls[1]?.sessionId &&
                  record.title === 'Child title',
              )
            );
          });

          await pickAgent(window, 'main');
          await readyAgent(window);
          expect(window.frame()).not.toContain('Renamed to Child title');
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          agentCommand: command,
          startupOf: () => ({ agentCommand: command }),
          openWith: captureTitles(calls),
          log,
        },
      );
    });
  }

  test('a late rename answer keeps its note in the original session after a child is picked', () =>
    withChild(
      async (window) => {
        await openOther(window);
        await send(window, '/rename Main waits');
        await window.shows('Renaming to Main waits');
        await until('rename reached the fake', () => {
          return readFile(
            join(window.dir, '.fake-gate', 'titles-heard'),
            'utf8',
          ).then(
            (text) => text.includes('Main waits'),
            () => false,
          );
        });

        await pickAgent(window, 'other');
        await readyAgent(window);
        await mkdir(join(window.dir, '.fake-gate'), { recursive: true });
        await writeFile(join(window.dir, '.fake-gate', 'release'), '');
        await until('main rename recorded', async () =>
          (await readRecords(join(window.dir, 'state'))).some(
            (record) => record.title === 'Main waits',
          ),
        );
        expect(window.frame()).not.toContain('Renamed to Main waits');
        await pickAgent(window, 'main');
        await readyAgent(window);
        await window.shows('Renamed to Main waits');
      },
      {
        agentCommand: fakeAgentCommand(
          undefined,
          '--set-title',
          'hang',
          '--child-runtime',
          'fake',
        ),
        startupOf: () => ({
          agentCommand: fakeAgentCommand(
            undefined,
            '--set-title',
            'hang',
            '--child-runtime',
            'fake',
          ),
        }),
      },
    ));
});
