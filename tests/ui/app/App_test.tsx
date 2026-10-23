/**
 * The window on the fake agent: its header, a turn, its notifications, the
 * keys that quit, clear and edit, the slash commands, and sessions in tabs.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import { draw } from '../harness.tsx';
import { type ResumableTab } from '../../../src/session/sessions.ts';
import { App } from '../../../src/ui/app/App.tsx';
import * as ansi from '../../../src/ui/theme/Ansi.tsx';
import { editInEditor } from '../../../src/editor.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_C,
  CTRL_D,
  CTRL_G,
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
} from './render.tsx';
import manifest from '../../../package.json' with { type: 'json' };

import { OSC9, writes, reported } from './app_window.tsx';

const VERSION = manifest.version;

describe('CHD-382 U2 tester: cancellation and error reports', () => {
  test('a blocked child wins over a working main', () => {
    const log: string[] = [];

    return withChild(
      async (window) => {
        await openOther(window);
        await readyAgent(window);
        await send(window, 'slow');
        await window.shows('esc to interrupt');
        await pickAgent(window, 'other');
        await until('the second agent', () => window.pids.length === 2);
        await readyAgent(window);
        await send(window, 'permission');
        await asked(window);
        expect(statusReports(log).at(-1)).toStrictEqual({
          state: 'blocked',
          kind: 'permission',
          app: 'chord',
          msg: 'other needs your permission: Write notes.txt',
          title: 'slow',
        });
        // Q183: main has no attention while the child owns permission keys,
        // so returning to main to cancel it is not a reachable person path.
        await quitAll(window);
      },
      { columns: 80, rows: 24, log },
    );
  });

  for (const columns of [80, 120]) {
    test(`Esc returns a cancelled turn to idle without done at ${columns} columns`, () => {
      const log: string[] = [];

      return withWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'slow');
          await until(
            'working report',
            () => statusReports(log).at(-1)?.state === 'working',
          );

          const from = statusReports(log).length;

          await window.press(ESC);
          await window.shows('Interrupted by user');
          await until(
            'idle after cancel',
            () => statusReports(log).at(-1)?.state === 'idle',
          );
          expect(statusReports(log).slice(from)).toStrictEqual([
            { state: 'idle', app: 'chord', title: 'slow' },
          ]);
        },
        { columns, rows: columns === 80 ? 24 : 40, log },
      );
    });

    test(`a failed turn reports error until a key at ${columns} columns`, () => {
      const log: string[] = [];

      return withWindow(
        async (window) => {
          await readyAgent(window);
          await send(window, 'error');
          await until(
            'failed turn report',
            () => statusReports(log).at(-1)?.state === 'error',
          );
          expect(statusReports(log).at(-1)).toStrictEqual({
            state: 'error',
            app: 'chord',
            msg: "fake's turn failed",
            title: 'error',
          });
          await window.type('x');
          await until(
            'idle after seeing failure',
            () => statusReports(log).at(-1)?.state === 'idle',
          );
        },
        { columns, rows: columns === 80 ? 24 : 40, log },
      );
    });
  }
});

test('the header names the agent and the directory', () =>
  withWindow(async (window) => {
    await window.shows('chord');
    // The model, which the ` · ` comes with, follows the session up.
    await window.shows('fake · ');
  }));

test("the transcript opens with the header: chord's version, the agent and its model, the directory and the keys", () =>
  withWindow(async (window) => {
    await window.shows('fake · Fake Large with a 1M context window');

    const lines = window.frame().split('\n');
    const at = (text: string) => lines.findIndex((line) => line.includes(text));

    expect(lines[at('chord v')] ?? '').toContain(`chord v${VERSION}`);
    // The window's first row, not on the prompt with empty rows above it.
    expect(at('chord v')).toStrictEqual(0);
    expect(at('chord v') + 1).toStrictEqual(at('fake · Fake Large'));
    expect(at('chord v') + 3).toStrictEqual(at('? for shortcuts · /help'));
    // The mark stands to the left of the text.
    expect(lines[at('chord v')] ?? '').toContain('▄     chord');

    await send(window, 'text');
    await window.shows('This reply came in chunks.');

    const after = window.frame().split('\n');
    const row = (text: string) =>
      after.findIndex((line) => line.includes(text));

    // The transcript grows down from the header while it fits.
    expect(row('chord v')).toStrictEqual(0);
    expect(row('› text')).toStrictEqual(row('? for shortcuts · /help') + 2);
    expect(after[row('⏺ Hello') + 1]?.trim()).toStrictEqual('');
    expect(after[row('⏺ Hello') + 2]?.trim()).toStrictEqual('');
    expect(
      !window.frame().includes('resumed'),
      'a fresh session resumed',
    ).toBeTruthy();
  }));

test("a test's first prompt goes once the window has its session, with a notice where Starting would be", async () => {
  let opened!: (frame: () => string) => void;
  const held = new Promise<() => string>((resolve) => (opened = resolve));
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  let began = false;
  const running = withWindow(
    async (window) => {
      began = true;

      await send(window, 'text');
      await window.shows('Hello, world. This reply came in chunks.');
    },
    {
      columns: 120,
      // A keybindings problem says so in the status line in place of
      // `Starting fake…`.
      keybindings: JSON.stringify({
        bindings: [
          { context: 'Chat', bindings: { 'ctrl+o': 'chat:externalEditor' } },
        ],
      }),
      heldOpen: (frame) => {
        opened(frame);

        return gate;
      },
    },
  );

  try {
    // The session is open and the test's to see, the window not yet on it,
    // with nothing on screen to say it is still starting.
    const frame = await held;

    await until('the notice in the status line', () =>
      frame().includes('keybindings.json'),
    );
    // A timer of until's 20 ms, set after withWindow's own look was, fires
    // after it: by then that look has seen the notice and answered.
    await new Promise((resolve) => setTimeout(resolve, 20));
    expect(began, 'the test began before the window had its session').toBe(
      false,
    );
  } finally {
    release();
    await running;
  }
});

test('a warning chord was started with is in the transcript before anything else', () =>
  withWindow(
    async (window) => {
      await window.shows(
        '⏺ .chord/settings.json: unknown key "theme", ignored',
      );
      await send(window, 'text');
      expect(
        window.frame().indexOf('unknown key') <
          window.frame().indexOf('› text'),
      ).toBeTruthy();
    },
    { warnings: ['.chord/settings.json: unknown key "theme", ignored'] },
  ));

test('a streamed chunk draws again only the entry it lands in', async () => {
  // Every block of a reply is drawn through `Ansi`, so its calls with a
  // reply's words count how often that reply was drawn.
  const drawn = spyOn(ansi, 'Ansi');
  const draws = (words: string) =>
    drawn.mock.calls.filter(([{ text }]) => text.includes(words)).length;

  try {
    await withWindow(async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await send(window, 'markdown');
      // The reply waits inside its first code fence, its turn still running.
      await window.shows('const session = await openSession');

      const earlier = draws('This reply came in chunks.');
      const streamed = draws('Reading the session layer');

      // A draft drawn on every key leaves the transcript alone too.
      await window.type('a draft');
      await window.shows('a draft');
      await window.shows('deno task check');

      expect(draws('This reply came in chunks.')).toStrictEqual(earlier);
      expect(draws('Reading the session layer')).toBeGreaterThan(streamed);
    });
  } finally {
    drawn.mockRestore();
  }
});

test('Esc interrupts the turn and the prompt is usable again', () =>
  withWindow(async (window) => {
    await send(window, 'slow');
    await window.shows('Working.');
    await window.shows('esc to interrupt');
    await window.press(ESC);
    await window.shows('Interrupted by user');
    await until(
      'the spinner to go',
      () => !window.frame().includes('Working…'),
    );
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
  }));

test('a finished turn writes the notification to stdout, once', () =>
  withWindow(
    async (window) => {
      const bytes = '\x1b]9;fake is waiting for your input\x07';

      await send(window, 'hello');
      await window.shows('This reply came in chunks.');
      await until('the notification', () => writes(window, bytes) === 1);
      await new Promise((resolve) => setTimeout(resolve, 300));
      expect(writes(window, bytes)).toStrictEqual(1);
    },
    { notifications: OSC9 },
  ));

test("the fake's permission request writes its notification, and the turn's end another", () =>
  withWindow(
    async (window) => {
      const bytes = '\x1b]9;fake needs your permission: Write notes.txt\x07';

      await send(window, 'permission');
      await asked(window);
      expect(writes(window, bytes)).toStrictEqual(1);
      await window.press('1');
      await until(
        'the turn to end',
        () => writes(window, '\x1b]9;fake is waiting for your input\x07') === 1,
      );
      expect(writes(window, bytes)).toStrictEqual(1);
    },
    { notifications: OSC9 },
  ));

test('a turn interrupted with Esc writes no notification', () =>
  withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await window.press(ESC);
      await window.shows('Interrupted by user');
      await new Promise((resolve) => setTimeout(resolve, 500));
      expect(
        !window.written().some((written) => written.includes('\x1b]9;')),
        'a notification was written',
      ).toBeTruthy();
    },
    { notifications: OSC9 },
  ));

test('a failed turn is an error line, and the prompt still works', () =>
  withWindow(async (window) => {
    await send(window, 'error');
    await window.shows('About to fail.');
    await window.shows('The fake agent failed on purpose.');
    await send(window, 'text');
    await window.shows('This reply came in chunks.');
  }));

test('ctrl+c warns once, then quits and stops the agent', () =>
  withWindow(async (window) => {
    await window.press(CTRL_C);
    await window.shows('Press ctrl+c again to quit');
    expect(
      window.session()?.agentPids.size === 1,
      'quit on the first press',
    ).toBeTruthy();
    await window.press(CTRL_C);
    await until(
      'the agent to stop',
      () => window.session()?.agentPids.size === 0,
    );
  }));

test('keys start nothing while the agent is still closing', () => {
  const { promise: heldClose, resolve: release } =
    Promise.withResolvers<void>();
  const ran: string[] = [];

  return withWindow(
    async (window) => {
      try {
        await ready(window);
        await window.press(CTRL_D);
        await window.shows('Stopping fake…');
        await window.type('!');
        await window.type('echo shutdown-race');
        await window.press('\r');
      } finally {
        // Before anything fails, or the window's own close would wait on it.
        release();
      }

      await until(
        'the agent to stop',
        () => window.session()?.agentPids.size === 0,
      );
      expect(ran).toStrictEqual([]);
    },
    {
      heldClose,
      shell: (command) => {
        ran.push(command);

        return { stop: () => {}, ended: new Promise(() => {}) };
      },
    },
  );
});

/**
 * Off the alternate screen and out of raw mode before the editor ran; both
 * back, and then `drawn`, after. Each pair in the order OpenTUI gives them.
 */
function assertHandedOver(log: readonly string[], drawn: string) {
  const editor = log.findIndex((chunk) => chunk.startsWith('editor: '));
  const before = log.slice(0, editor);
  const after = log.slice(editor);
  const entered = before.findLastIndex((chunk) =>
    chunk.includes('\x1b[?1049h'),
  );
  const left = before.findLastIndex((chunk) => chunk.includes('\x1b[?1049l'));
  const cooked = before.lastIndexOf('raw off');
  const raw = after.indexOf('raw on');
  const enter = after.findIndex((chunk) => chunk.includes('\x1b[?1049h'));
  // The first write by which the text is out, once the terminal is back.
  const back = Math.max(raw, enter);
  const shown = after.findIndex(
    (_, at) =>
      at > back &&
      after
        .slice(back, at + 1)
        .join('')
        .includes(drawn),
  );

  expect(editor >= 0, 'the editor did not run').toBeTruthy();
  expect(left > entered, 'the alternate screen was not left').toBeTruthy();
  expect(cooked > before.lastIndexOf('raw on'), 'raw mode was on').toBeTruthy();
  expect(raw > 0, 'raw mode did not come back').toBeTruthy();
  expect(enter > 0, 'the alternate screen did not come back').toBeTruthy();
  expect(shown > back, 'the window was not drawn once back').toBeTruthy();
}

test('ctrl+g leaves the alternate screen and raw mode, and comes back drawn', () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await window.type('draft');
      await window.shows('› draft');
      await window.press(CTRL_G);
      await window.shows('from the editor');
      assertHandedOver(log, 'from the editor');
      // The key goes on working once it is back.
      await window.type('!');
      await window.shows('from the editor!');
    },
    {
      log,
      editor: (draft) => {
        log.push(`editor: ${draft}`);

        return Promise.resolve({ text: `${draft}\nfrom the editor` });
      },
    },
  );
});

test('an editor killed by a signal keeps the draft and gives the terminal back', () => {
  const log: string[] = [];
  const message = 'printf was stopped by SIGTERM; the draft is unchanged';

  return withWindow(
    async (window) => {
      await ready(window);
      await window.type('kept');
      await window.shows('› kept');
      await window.press(CTRL_G);
      await window.shows(message);
      assertHandedOver(log, message);
      expect(
        !window.frame().includes('overwritten'),
        'the half-written file came back',
      ).toBeTruthy();
      // The draft is the one typed: a key goes on the end of it.
      await window.type('!');
      await window.shows('› kept!');
    },
    {
      log,
      editor: (draft) => {
        log.push(`editor: ${draft}`);

        // A scripted editor that writes the file and is then killed, as one
        // that crashes half-way through a save would be.
        return editInEditor(draft, {
          env: (name) =>
            name === 'EDITOR'
              ? 'printf overwritten > "$1"; kill -TERM $$ #'
              : undefined,
          shell: ['/bin/sh', '-c'],
        });
      },
    },
  );
});

test('ctrl+c clears a draft without arming quit', () =>
  withWindow(async (window) => {
    await window.type('draft');
    await window.shows('› draft');
    await window.press(CTRL_C);
    await until('the draft to go', () => !window.frame().includes('draft'));
    expect(
      !window.frame().includes('Press ctrl+c again'),
      'clearing armed quit',
    ).toBeTruthy();
    // The input still takes text after it was cleared.
    await window.type('next');
    await window.shows('› next');
  }));

test('clearing a draft disarms a quit that was already armed', () =>
  withWindow(async (window) => {
    await window.press(CTRL_C);
    await window.shows('Press ctrl+c again to quit');
    await window.type('draft');
    await window.shows('› draft');
    await window.press(CTRL_C);
    await until('the draft to go', () => !window.frame().includes('draft'));
    expect(
      !window.frame().includes('Press ctrl+c again'),
      'the warning outlived the draft',
    ).toBeTruthy();
    await window.press(CTRL_C);
    await window.shows('Press ctrl+c again to quit');
    expect(
      window.session()?.agentPids.size === 1,
      'quit after clearing',
    ).toBeTruthy();
    await window.press(CTRL_C);
    await until(
      'the agent to stop',
      () => window.session()?.agentPids.size === 0,
    );
  }));

test('ctrl+d quits on an empty prompt, not on a draft', () =>
  withWindow(async (window) => {
    await window.type('draft');
    await window.press(CTRL_D);
    await window.shows('› draft');
    expect(
      !window.frame().includes('draftd'),
      'ctrl+d typed a letter',
    ).toBeTruthy();
    expect(
      window.session()?.agentPids.size === 1,
      'quit with a draft',
    ).toBeTruthy();

    for (let i = 0; i < 'draft'.length; i++) {
      await window.press('\x7f');
    }

    await window.press(CTRL_D);
    await until(
      'the agent to stop',
      () => window.session()?.agentPids.size === 0,
    );
  }));

test('ctrl+c quits mid-turn and stops the agent', () =>
  withWindow(async (window) => {
    await send(window, 'slow');
    await window.shows('esc to interrupt');
    await window.press(CTRL_C);
    await window.press(CTRL_C);
    await until(
      'the agent to stop',
      () => window.session()?.agentPids.size === 0,
    );
  }));

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

const CTRL_N = '\x0e';

test("one session's first row is its header's, and two sessions' is the tab strip, the header under it", () =>
  withWindow(
    async (window) => {
      const first = () => window.frame().split('\n')[0] ?? '';

      await window.shows('chord v');
      expect(first()).toContain(`chord v${VERSION}`);
      await leader(window, 'c');
      await window.shows('2 fake');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      expect(first()).toContain('1 fake');
      expect(
        !first().includes('chord v'),
        'the header on the strip',
      ).toBeTruthy();
      expect(window.frame().split('\n')[1] ?? '').toContain(
        `chord v${VERSION}`,
      );
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('ctrl+x c opens a second session, and the leader switches between them', () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('Hello, world. This reply came in chunks.');
      expect(
        !window.frame().includes('1 fake'),
        'a strip with one session',
      ).toBeTruthy();
      await leader(window, 'c');
      await window.shows('2 fake');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      expect(
        !window.frame().includes('› text'),
        "the first session's past",
      ).toBeTruthy();
      await send(window, 'the second one');
      await leader(window, '1');
      await window.shows('› text');
      expect(!window.frame().includes('› the second one')).toBeTruthy();
      await leader(window, CTRL_N);
      await window.shows('› the second one');
      expect(!window.frame().includes('› text')).toBeTruthy();
      await leader(window, 'p');
      await window.shows('› text');
      // A number with no tab does nothing.
      await leader(window, '5');
      await until(
        'the leader to go',
        () => !window.frame().includes('ctrl+x …'),
      );
      expect(window.frame()).toContain('› text');
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test("/new opens the agent named on its own settings' model, refuses one chord cannot start, and /status counts the sessions", () =>
  withWindow(
    async (window) => {
      await ready(window);
      // A name the list matches nothing of, so Enter runs it as typed.
      await window.type('/new qqq');
      await window.press('\r');
      await window.shows('No agent named qqq · chord agents lists them');
      expect(window.frame()).toContain('› /new qqq');
      expect(
        !window.frame().includes('1 fake'),
        'a strip with one session',
      ).toBeTruthy();
      expect(window.pids.length).toStrictEqual(1);
      await window.type('/new fake2');
      await window.press('\r');
      await window.shows('2 fake2');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await window.shows('Fake Small');
      // Alone, it is ctrl+x c: the front session's agent again.
      await window.type('/new');
      await window.press('\r');
      await window.shows('3 fake2');
      await until('the third agent', () => window.pids.length === 3);
      await ready(window);

      const status = await reported(window, '/status');

      expect(status).toContain('Agent:     fake2');
      expect(status).toContain('Model:     Fake Small');
      expect(status).toContain('Sessions:  3 open');
      await quitAll(window);
    },
    {
      columns: 120,
      rows: 40,
      startupOf: (agent) =>
        agent === 'fake'
          ? { agentCommand: fakeAgentCommand() }
          : agent === 'fake2'
            ? {
                agentCommand: fakeAgentCommand(),
                starting: {
                  model: { id: 'fake-small', from: 'set in settings' },
                },
              }
            : undefined,
    },
  ));

test("/new opens the agent named on its own settings' effort, and says one its runtime refuses", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('/new fake2');
      await window.press('\r');
      await window.shows('2 fake2');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'effort');
      await window.shows('Effort: high.');
      await window.type('/new fake3');
      await window.press('\r');
      await window.shows('3 fake3');
      await until('the third agent', () => window.pids.length === 3);
      await ready(window);
      await window.shows(
        'Could not start on max effort, set in .chord/settings.json: the ' +
          'agent offers low, medium, high',
      );
      await send(window, 'effort');
      await window.shows('Effort: medium.');
      await quitAll(window);
    },
    {
      columns: 140,
      rows: 40,
      startupOf: (agent) =>
        agent === 'fake'
          ? { agentCommand: fakeAgentCommand() }
          : agent === 'fake2' || agent === 'fake3'
            ? {
                agentCommand: fakeAgentCommand(),
                starting: {
                  effort: {
                    id: agent === 'fake2' ? 'high' : 'max',
                    from: 'set in .chord/settings.json',
                  },
                },
              }
            : undefined,
    },
  ));

test('/new offers a name only the settings define, and Tab and Enter open it', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('/new ');
      await window.shows('from settings');
      // Settings first, then own CLIs PATH has, and those it lacks marked.
      expect(window.frame()).toMatch(/mine +from settings\n.*goose +goose\n/);
      expect(window.frame()).toMatch(/cursor +Cursor · not on PATH/);
      await window.type('mi');
      await window.press('\t');
      await window.shows('› /new mine');
      await window.press('\r');
      await window.shows('2 mine');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await quitAll(window);
    },
    {
      columns: 120,
      rows: 40,
      runtimes: ['fake', 'cursor', 'goose', 'mine'],
      listed: [
        {
          name: 'cursor',
          title: 'Cursor',
          start: 'agent acp',
          from: 'cli',
          found: false,
        },
        {
          name: 'goose',
          title: 'goose',
          start: 'goose acp',
          from: 'cli',
          found: true,
        },
        {
          name: 'mine',
          title: undefined,
          start: 'fake-agent',
          from: 'settings',
        },
      ],
      startupOf: (agent) =>
        agent === 'fake' || agent === 'mine'
          ? { agentCommand: fakeAgentCommand() }
          : undefined,
    },
  ));

test('a permission behind is a glyph and a notice, and ctrl+x a goes to it', () =>
  withWindow(
    async (window) => {
      const bytes =
        '\x1b]9;fake (2) needs your permission: Write notes.txt\x07';

      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'permission');
      await asked(window);
      await leader(window, '1');
      await window.shows('2 fake ●');
      await window.shows('● 2 fake needs your permission · ctrl+x a to go');
      expect(writes(window, bytes)).toStrictEqual(1);
      // The window never switches by itself, so a digit typed here is a draft.
      await window.type('1');
      await until(
        'the digit in the draft',
        () => promptRow(window)?.includes('1') ?? false,
      );
      expect(!window.frame().includes('Do you want to proceed?')).toBeTruthy();
      expect(window.frame()).toContain('2 fake ●');
      await leader(window, 'a');
      await asked(window);
      expect(window.frame()).toContain('Waiting for permission');
      await window.press('1');
      await until(
        'the permission answered',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      await until(
        'the turn to end',
        () =>
          !window.frame().includes('2 fake ●') &&
          !window.frame().includes('Working'),
      );
      expect(writes(window, bytes)).toStrictEqual(1);
      await leader(window, 'a');
      await window.shows('No session waits');
      await quitAll(window);
    },
    { columns: 120, rows: 40, notifications: OSC9 },
  ));

test('a digit after the leader goes to a tab, not to the permission asked', () =>
  withWindow(
    async (window) => {
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await leader(window, '1');
      await send(window, 'permission');
      await asked(window);
      await leader(window, '2');
      await until(
        'the second tab',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      // The first waits on the person, and its tab says so.
      await window.shows('1 fake ●');
      await leader(window, '1');
      await asked(window);
      expect(window.frame()).toContain('2. ');
      await window.press('3');
      await until(
        'the permission answered',
        () => !window.frame().includes('Do you want to proceed?'),
      );
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('ctrl+x w lists the sessions open, and Enter goes to the one highlighted', () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await leader(window, 'w');
      await window.shows('Sessions in ');
      expect(window.frame()).toMatch(/1\. fake {2}◦ idle \d+s {2}text/);
      expect(window.frame()).toMatch(/2\. fake {2}here/);
      expect(window.frame()).toContain(
        'Enter to go · 1–2 to pick · Esc to close',
      );
      // None waits, so the highlight starts after the session in front.
      expect(window.frame()).toMatch(/❯ 1\. fake/);
      await window.press('\r');
      await window.shows('› text');
      expect(
        !window.frame().includes('Sessions in '),
        'the picker stayed open',
      ).toBeTruthy();
      expect(window.pids.length).toStrictEqual(2);

      // Esc leaves the session in front as it was.
      await leader(window, 'w');
      await window.shows('Sessions in ');
      await window.press(ESC);
      await until(
        'the picker to close',
        () => !window.frame().includes('Sessions in '),
      );
      expect(window.frame()).toContain('› text');
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('/resume marks a session open in another tab, and picking it goes there without a second agent', () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      expect(
        !window.frame().includes('› text'),
        "tab 1's past in tab 2",
      ).toBeTruthy();
      await window.type('/resume');
      await window.press('\r');
      await window.shows('Resume a session');
      await window.shows('open in 1');
      await window.press('\r');
      await window.shows('› text');
      expect(!window.frame().includes('Resume a session')).toBeTruthy();
      // Give a second agent the time it would take to start, had one been.
      await new Promise((resolve) => setTimeout(resolve, 500));
      expect(window.pids.length).toStrictEqual(2);
      expect(
        window
          .frame()
          .split('\n')
          .filter((line) => line.includes('› text')).length,
      ).toStrictEqual(1);
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test("/clear in tab 2 starts it afresh and leaves tab 1's transcript", () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'tools');
      await window.shows('Read it.');
      await window.type('/clear');
      await window.press('\r');
      await until('tab 2 cleared', () => !window.frame().includes('› tools'));
      await ready(window);
      await leader(window, '1');
      await window.shows('› text');
      expect(window.frame()).toContain('This reply came in chunks.');
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('ctrl+x k closes an idle session at once, and a busy one on the second press', () =>
  withWindow(
    async (window) => {
      const header = () => window.frame().split('\n')[0] ?? '';

      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'k');
      await window.shows('Closed 2 fake · /resume opens it again');
      // The first comes back as it was left: nothing sent to it.
      expect(
        !window.frame().includes('› text'),
        "the closed session's past",
      ).toBeTruthy();
      expect(
        !header().includes('1 fake'),
        'a strip with one session',
      ).toBeTruthy();
      await until(
        'its agent to stop',
        async () => !(await isAlive(window.pids[1]!)),
      );

      // A busy one asks first and is left as it was.
      await leader(window, 'c');
      await until('the third agent', () => window.pids.length === 3);
      await ready(window);
      await send(window, 'permission');
      await asked(window);
      await leader(window, 'k');
      await window.shows(
        '2 fake waits for your permission · ctrl+x k again to stop it and close',
      );
      expect(header()).toContain('2 fake');
      expect(
        await isAlive(window.pids[2]!),
        'closed on the first press',
      ).toBeTruthy();
      await leader(window, 'k');
      await window.shows('Closed 2 fake · /resume opens it again');
      expect(!header().includes('2 fake'), 'its tab stayed').toBeTruthy();
      expect(!window.frame().includes('Do you want to proceed?')).toBeTruthy();
      await until(
        'its agent to stop',
        async () => !(await isAlive(window.pids[2]!)),
      );
      await quitAll(window);
    },
    { columns: 120, rows: 40 },
  ));

test('ctrl+x k on a session running a command asks first, then stops that command and no other', () => {
  const stops = new Map<string, number>();

  return withWindow(
    async (window) => {
      const header = () => window.frame().split('\n')[0] ?? '';

      await window.type('!');
      await window.type('sleep 61');
      await window.press('\r');
      await window.shows('sleep 61');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await window.type('!');
      await window.type('sleep 60');
      await window.press('\r');
      await window.shows('sleep 60');
      await leader(window, 'k');
      await window.shows(
        '2 fake is working · ctrl+x k again to stop it and close',
      );
      expect(stops.get('sleep 60') ?? 0).toStrictEqual(0);
      await leader(window, 'k');
      await until('its tab to close', () => !header().includes('2 fake'));
      expect(stops.get('sleep 60')).toStrictEqual(1);
      expect(
        stops.get('sleep 61') ?? 0,
        "the other tab's command",
      ).toStrictEqual(0);
      await window.shows('sleep 61');
      await quitAll(window);
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

test('an armed close that has run out asks again rather than closing', () =>
  withWindow(
    async (window) => {
      const header = () => window.frame().split('\n')[0] ?? '';

      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await leader(window, 'k');
      await window.shows(
        '2 fake is working · ctrl+x k again to stop it and close',
      );
      await until(
        'the armed line to go',
        () => !window.frame().includes('again to stop it and close'),
        4000,
      );
      await leader(window, 'k');
      await window.shows(
        '2 fake is working · ctrl+x k again to stop it and close',
      );
      expect(header()).toContain('2 fake');
      expect(
        await isAlive(window.pids[1]!),
        'closed on a press after it ran out',
      ).toBeTruthy();
      await quitAll(window);
    },
    {
      columns: 120,
      rows: 40,
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '200'),
    },
  ));

test('ctrl+d with a session working arms and names it, then quits with each session to resume and no agent left', async () => {
  let resumable: readonly ResumableTab[] | undefined;

  await withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await leader(window, '1');
      await window.shows('› text');
      await window.press(CTRL_D);
      await window.shows('2 fake is working · ctrl+d again to quit');
      expect(resumable).toStrictEqual(undefined);

      for (const pid of window.pids) {
        expect(
          await isAlive(pid),
          `agent ${pid} stopped on the first press`,
        ).toBeTruthy();
      }

      await quitAll(window);
      expect(resumable?.map(({ agent }) => agent)).toStrictEqual([
        'fake',
        'fake',
      ]);
      expect(
        new Set(resumable?.map(({ sessionId }) => sessionId)).size,
      ).toStrictEqual(2);
    },
    {
      columns: 120,
      rows: 40,
      // Slow enough that its turn still runs at the second press.
      agentCommand: fakeAgentCommand(undefined, '--step-ms', '20'),
      onQuit: (tabs) => (resumable = tabs),
    },
  );
});

test('a form left half filled in a session behind is as it was on coming back', () =>
  withWindow(
    async (window) => {
      await send(window, 'form');
      await inputAsked(window);
      await window.type('keep');
      await window.press(TAB);
      await window.type('a@b');
      await window.shows('Contact email  a@b');
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      expect(
        !window.frame().includes('Project name'),
        "tab 1's form in tab 2",
      ).toBeTruthy();
      // Its tab says it waits instead, and the status line names it.
      await window.shows('● 1 fake asks for input · ctrl+x a');
      await leader(window, '1');
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
