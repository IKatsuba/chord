/**
 * The window's slash commands and the keys around a child beside main:
 * /clear, /cost, /context, /status, /help and /exit, a child's notices,
 * and a start that fails.
 */
import { describe, expect, test } from 'bun:test';
import { withChild, openOther, readyAgent } from './child_window.tsx';
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
  TAB,
  until,
  UP,
  withWindow,
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
