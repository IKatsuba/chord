import { describe, expect, spyOn, test } from 'bun:test';
import { mkdir, mkdtemp, rm, writeFile, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { draw } from '../harness.tsx';
import { openSession, type Session } from '../../../src/session/session.ts';
import {
  readRecords,
  type ResumableTab,
} from '../../../src/session/sessions.ts';
import { readPast } from '../../../src/session/record.ts';
import { serveChord } from '../../../src/server/server.ts';
import { App } from '../../../src/ui/app/App.tsx';
import * as ansi from '../../../src/ui/theme/Ansi.tsx';
import { terminalOptions } from '../../../src/ui/app/renderer.tsx';
import { editInEditor } from '../../../src/editor.ts';
import { fakeAgentCommand, gatedCommand } from '../../fixtures/fake.ts';
import {
  asked,
  DOWN,
  CTRL_C,
  CTRL_D,
  CTRL_G,
  CTRL_R,
  CTRL_X,
  ESC,
  inputAsked,
  isAlive,
  leader,
  left,
  promptRow,
  quitAll,
  ready,
  send,
  statusReports,
  TAB,
  until,
  UP,
  type Window,
  withWindow,
} from './render.tsx';
import manifest from '../../../package.json' with { type: 'json' };

const VERSION = manifest.version;

describe('CHD-382 U2 tester: cancellation and error reports', () => {
  test('a blocked tab behind wins over a working front tab', () => {
    const log: string[] = [];

    return withWindow(
      async (window) => {
        await ready(window);
        await leader(window, 'c');
        await until('the second agent', () => window.pids.length === 2);
        await ready(window);
        await send(window, 'permission');
        await asked(window);
        await leader(window, '1');
        await send(window, 'slow');
        await window.shows('esc to interrupt');
        expect(statusReports(log).at(-1)).toStrictEqual({
          state: 'blocked',
          kind: 'permission',
          app: 'chord',
          msg: 'fake (2) needs your permission: Write notes.txt',
        });
        await window.press(ESC);
        await window.shows('Interrupted by user');
        expect(statusReports(log).at(-1)?.state).toBe('blocked');
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
          await ready(window);
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
            { state: 'idle', app: 'chord' },
          ]);
        },
        { columns, rows: columns === 80 ? 24 : 40, log },
      );
    });

    test(`a failed turn reports error until a key at ${columns} columns`, () => {
      const log: string[] = [];

      return withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'error');
          await until(
            'failed turn report',
            () => statusReports(log).at(-1)?.state === 'error',
          );
          expect(statusReports(log).at(-1)).toStrictEqual({
            state: 'error',
            app: 'chord',
            msg: "fake's turn failed",
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

const OSC9 = {
  channel: 'osc9',
  env: { termProgram: 'iTerm.app', tmux: false },
} as const;

/** The writes to stdout that carry `bytes`. */
function writes(window: Window, bytes: string): number {
  return window.written().filter((written) => written.startsWith(bytes)).length;
}

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

/** The rows `/name` reported, from its line to the end of its block. */
async function reported(window: Window, name: string): Promise<string> {
  await window.type(name);
  await window.press('\r');
  await window.shows(`› ${name}`);

  const lines = window.frame().split('\n');
  const at = lines.findLastIndex((line) => line.includes(`› ${name}`));
  const block = lines.slice(at + 1);
  const end = block.findIndex((line) => line.trim() === '');

  return block.slice(0, end < 0 ? undefined : end).join('\n');
}

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

test('several resumed sessions open as tabs in order, the first in front, each on its own agent where it works', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const here = join(dir, 'here');
  const there = join(dir, 'there');
  const sessions: Session[] = [];
  const opened: {
    agent: string;
    id?: string | undefined;
    cwd: string;
    servers: string[];
  }[] = [];
  const ids = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  const start = { agentCommand: fakeAgentCommand() };
  const place = (cwd: string, server: string) => ({
    cwd,
    startupOf: () => start,
    mcpServers: [
      {
        server: { name: server, command: 'true', args: [], env: [] },
        from: '.mcp.json',
      },
    ],
    mcpIgnored: [],
  });
  const atHere = place(here, 'here-server');
  const atThere = place(there, 'there-server');

  await mkdir(here);
  await mkdir(there);

  // Ids chord has no record of: the fake agent loads each and replays.
  const app = await draw(
    <App
      agent='fake'
      cwd={here}
      home={undefined}
      stateDir={join(dir, 'state')}
      agentCommand={fakeAgentCommand()}
      mcpServers={atHere.mcpServers}
      resumes={[
        {
          agent: 'fake',
          resume: { sessionId: ids[0]!, cwd: here },
          place: atHere,
        },
        {
          agent: 'fake2',
          resume: { sessionId: ids[1]!, cwd: there },
          place: atThere,
        },
        {
          agent: 'fake',
          resume: { sessionId: ids[2]!, cwd: there },
          place: atThere,
        },
      ]}
      open={async (options) => {
        opened.push({
          agent: options.agent,
          id: options.resume?.sessionId,
          cwd: options.cwd,
          servers: (options.mcpServers ?? []).map(({ name }) => name),
        });

        const session = await openSession(options);

        sessions.push(session);

        return session;
      }}
    />,
    { columns: 120 },
  );

  const frame = () => app.frame();

  try {
    await until('three sessions', () => sessions.length === 3);
    await until('the past', () => frame().includes('Read it.'));
    expect(opened).toStrictEqual([
      { agent: 'fake', id: ids[0], cwd: here, servers: ['here-server'] },
      { agent: 'fake2', id: ids[1], cwd: there, servers: ['there-server'] },
      { agent: 'fake', id: ids[2], cwd: there, servers: ['there-server'] },
    ]);
    expect(frame()).toMatch(/1 fake .*2 fake2 .*3 fake/);
    expect(frame()).toContain(here);
    expect(
      !frame().includes(there),
      'the front tab is not the first',
    ).toBeTruthy();

    // Each tab has its own past, and works where its session does: `/new`
    // opens beside it there, on that directory's servers.
    await app.write(CTRL_X);
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('2');
    await until('the second tab', () => frame().includes(there));
    await until('its past', () => frame().includes('Read it.'));
    await app.write('/new');
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('\r');
    await until('a fourth session', () => sessions.length === 4);
    expect(opened.at(-1)).toStrictEqual({
      agent: 'fake2',
      id: undefined,
      cwd: there,
      servers: ['there-server'],
    });
  } finally {
    await app.unmount();

    for (const session of sessions) {
      await session.close();
    }

    await rm(dir, { recursive: true });
  }
});

test("a runtime's models are read where the asking session works: never started where its command is refused, read where it is not (CHD-466)", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const here = join(dir, 'here');
  const there = join(dir, 'there');
  const sessions: Session[] = [];
  const server = serveChord();
  const start = { agentCommand: fakeAgentCommand() };
  const refused = 'codex not started: refused there';
  // Codex starts on the fake here; there, its command was refused.
  const atHere = {
    cwd: here,
    startupOf: () => start,
    mcpServers: [],
    mcpIgnored: [],
  };
  const atThere = {
    ...atHere,
    cwd: there,
    startupOf: (agent: string) => (agent === 'codex' ? { refused } : start),
  };

  await mkdir(here);
  await mkdir(there);

  const app = await draw(
    <App
      agent='fake'
      cwd={here}
      home={undefined}
      stateDir={join(dir, 'state')}
      agentCommand={fakeAgentCommand()}
      startupOf={atHere.startupOf}
      server={server}
      runtimes={['fake', 'codex']}
      resumes={[
        {
          agent: 'fake',
          resume: { sessionId: crypto.randomUUID(), cwd: there },
          place: atThere,
        },
        {
          agent: 'fake',
          resume: { sessionId: crypto.randomUUID(), cwd: here },
          place: atHere,
        },
      ]}
      open={async (options) => {
        const session = await openSession(options);

        sessions.push(session);

        return session;
      }}
    />,
    { rows: 80, columns: 160 },
  );

  const frame = () => app.frame();
  const ask = async () => {
    await app.write('codexmodels');
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('\r');
  };

  try {
    await until('two sessions', () => sessions.length === 2);
    await until('the past', () => frame().includes('Read it.'));
    expect(frame()).toContain(there);

    // Asked first there, nothing is read: were the window's place asked,
    // the fake would start as codex and its models would show.
    await ask();
    await until('the answer there', () => frame().includes('Codex read:'));
    expect(frame()).toContain(refused);
    expect(frame()).not.toContain('Fake Small');

    await app.write(CTRL_X);
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('2');
    await until('the second tab', () => !frame().includes(there));
    await ask();
    await until('the answer here', () => frame().includes('Codex read:'));
    await until('its models', () => frame().includes('Fake Small'));
    expect(frame()).not.toContain(refused);

    // What was read here is not what the tab there is told.
    await app.write(CTRL_X);
    await new Promise((resolve) => setTimeout(resolve, 50));
    await app.write('1');
    await until('the first tab', () => frame().includes(there));
    await ask();
    await until(
      'the second answer there',
      () => frame().split('Codex read:').length === 3,
    );
    expect(frame()).not.toContain('Fake Small');
  } finally {
    await app.unmount();

    for (const session of sessions) {
      await session.close();
    }

    await server.close();
    await rm(dir, { recursive: true });
  }
});

test("a window record's tabs open with its front tab in front and its note said, and quitting names their places and the front", async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));
  const here = join(dir, 'here');
  const there = join(dir, 'there');
  const sessions: Session[] = [];
  const ids = [crypto.randomUUID(), crypto.randomUUID(), crypto.randomUUID()];
  const start = { agentCommand: fakeAgentCommand() };
  const place = (cwd: string) => ({
    cwd,
    startupOf: () => start,
    mcpServers: [],
    mcpIgnored: [],
  });
  let quit: { tabs: readonly ResumableTab[]; front: number } | undefined;

  await mkdir(here);
  await mkdir(there);

  const app = await draw(
    <App
      agent='fake'
      cwd={here}
      home={undefined}
      stateDir={join(dir, 'state')}
      agentCommand={fakeAgentCommand()}
      resumes={[
        {
          agent: 'fake',
          resume: { sessionId: ids[0]!, cwd: here },
          place: place(here),
        },
        {
          agent: 'fake2',
          resume: { sessionId: ids[1]!, cwd: here },
          place: place(here),
        },
        {
          agent: 'fake',
          resume: { sessionId: ids[2]!, cwd: there },
          place: place(there),
        },
      ]}
      resumedFront={2}
      resumedNote='Not reopened: fake tab gone, its record is gone'
      onQuit={(tabs, front) => {
        quit = { tabs, front };
      }}
      open={async (options) => {
        const session = await openSession(options);

        sessions.push(session);

        return session;
      }}
    />,
    { columns: 120 },
  );

  const frame = () => app.frame();

  try {
    await until('three sessions', () => sessions.length === 3);
    await until('the third in front', () => frame().includes(there));
    await until('the note', () =>
      frame().includes('Not reopened: fake tab gone'),
    );
    // Every past is in, so each tab had a prompt and is resumable.
    await until('the past', () => frame().includes('Read it.'));
    await new Promise((resolve) => setTimeout(resolve, 200));
    await app.write(CTRL_D);
    await until('the quit', () => quit !== undefined);
    expect(quit).toStrictEqual({
      tabs: [
        { agent: 'fake', sessionId: ids[0]!, cwd: here },
        { agent: 'fake2', sessionId: ids[1]!, cwd: here },
        { agent: 'fake', sessionId: ids[2]!, cwd: there },
      ],
      front: 2,
    });
  } finally {
    await app.unmount();

    for (const session of sessions) {
      await session.close();
    }

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

test("an agent's own cycle after its turn shows it working until its end is marked, then the window is as after a turn (CHD-426)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecycle');
      await window.shows(
        'The build runs in the background; I will read it after.',
      );
      await until('the turn over', () => !window.frame().includes('Working…'));
      // The cycle: the agent at work again with no prompt of the person's.
      await window.shows('Working…');
      await window.shows('The build passed.');
      await until('the cycle over', () => !window.frame().includes('Working…'));
      expect(window.frame()).toContain(
        'The background build ended; reading its log. The build passed.',
      );
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

test("a permission asked in the agent's own cycle is held: a digit typed is the draft's, ctrl+x a answers it, and the cycle works on to its end (the owner's Q48, CHD-426)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecycleask');
      await window.shows('main asks · between turns');
      await window.shows('ctrl+x a to answer');
      expect(window.frame()).not.toContain('❯ 1. Allow');

      await window.type('1');
      expect(promptRow(window)).toContain('› 1');
      expect(window.frame()).not.toContain('Permission: allow.');

      await leader(window, 'a');
      await window.shows('❯ 1. Allow');
      await window.press('1');
      await window.shows('Permission: allow.');
      await until('the cycle over', () => !window.frame().includes('Working…'));
      expect(promptRow(window)).toContain('› 1');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

describe('CHD-426 U1 tester: inputs during autonomous work', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const kind of ['form', 'link'] as const) {
      test(`${kind} stays held and answering returns to the running cycle at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await ready(window);
            await send(window, 'claudecyclebare');
            await window.shows('The build passed.');
            await window.shows('Working…');

            const session = window.session()!;
            const answer = session.elicitations.handler(
              kind === 'form'
                ? {
                    sessionId: session.id,
                    mode: 'form',
                    message: 'Cycle details',
                    requestedSchema: {
                      type: 'object',
                      properties: { note: { type: 'string', title: 'Note' } },
                    },
                  }
                : {
                    sessionId: session.id,
                    mode: 'url',
                    message: 'Cycle approval',
                    url: 'https://example.com/cycle',
                    elicitationId: 'cycle-window-link',
                  },
              new AbortController().signal,
            );

            await window.shows('between turns');
            await window.shows('ctrl+x a to answer');
            await window.type('1');
            expect(promptRow(window)).toContain('› 1');
            await leader(window, 'a');
            await window.shows('Esc to cancel');
            await window.press(ESC);
            expect(await answer).toMatchObject({ action: 'cancel' });
            await window.shows('Working…');
            await until(
              'the held input is gone',
              () => !window.frame().includes('between turns'),
            );
            expect(promptRow(window)).toContain('› 1');
          },
          {
            columns,
            rows,
            agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
          },
        ));
    }
  }
});

test("Esc in the agent's own cycle stops it: the working line goes, and a prompt after it is a turn as any (CHD-426 U2)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'claudecyclebare');
      await window.shows('The build passed.');
      await window.shows('Working…');
      await window.press(ESC);
      await until(
        'the cycle stopped',
        () => !window.frame().includes('Working…'),
      );
      await send(window, 'text');
      await window.shows('Hello, world. This reply came in chunks.');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--adapter', 'claude'),
      columns: 120,
      rows: 40,
    },
  ));

describe('CHD-426 U2 tester: held inputs and cancellation silence', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`Esc stays quiet while held form and link are withdrawn at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'claudecyclebare');
          await window.shows('The build passed.');

          const before = writes(
            window,
            '\x1b]9;fake is waiting for your input\x07',
          );
          const session = window.session()!;
          const withdrawn = new AbortController();
          const responses = [
            session.elicitations.handler(
              {
                sessionId: session.id,
                mode: 'form',
                message: 'Cancel cycle form',
                requestedSchema: { type: 'object', properties: {} },
              },
              withdrawn.signal,
            ),
            session.elicitations.handler(
              {
                sessionId: session.id,
                mode: 'url',
                message: 'Cancel cycle link',
                url: 'https://example.com/cancel',
                elicitationId: 'cancel-cycle-link',
              },
              withdrawn.signal,
            ),
          ];

          await window.shows('between turns');
          await window.press(ESC);
          await window.shows('Cancel heard with no turn.');
          withdrawn.abort();
          expect(await Promise.all(responses)).toEqual([
            { action: 'cancel' },
            { action: 'cancel' },
          ]);
          await until(
            'the cycle and held boxes are gone',
            () =>
              !window.frame().includes('Working…') &&
              !window.frame().includes('between turns'),
          );
          expect(
            writes(window, '\x1b]9;fake is waiting for your input\x07'),
          ).toBe(before);
          await window.press(ESC);
          await send(window, 'cancels');
          await window.shows('Cancels with no turn: 1.');
        },
        {
          columns,
          rows,
          notifications: OSC9,
          agentCommand: fakeAgentCommand(
            undefined,
            '--adapter',
            'claude',
            '--say-cancels',
          ),
        },
      ));
  }
});

test("/cost while a turn runs says that turn is counted when it ends, beside the earlier turns' estimate, and no longer once it has ended (CHD-405)", () =>
  withWindow(
    async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));
      await send(window, 'slow');
      await window.shows('Working');

      const during = await reported(window, '/cost');

      expect(during).toContain('Total cost:   $');
      expect(during).toContain("(chord's estimate)");
      expect(during).toMatch(
        /Total cost:.*\n\s+This turn: {4}counted when it ends/,
      );

      await window.press(ESC);
      await until(
        'the turn to end',
        () => !window.frame().includes('Working…'),
      );
      expect(await reported(window, '/cost')).not.toContain('This turn:');
    },
    {
      agentCommand: fakeAgentCommand(undefined, '--tokens-only'),
      rows: 60,
    },
  ));

describe('CHD-405 N2 tester: held requests do not imply running spend', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`cost has no current-turn row while a between-turn permission remains open at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'leftask');
          await window.shows('main asks · between turns');

          const cost = await reported(window, '/cost');

          expect(cost).toContain('fake has not reported');
          expect(cost).not.toContain('This turn:');
          expect(window.frame()).toContain('ctrl+x a to answer');
          expect(window.frame()).not.toContain('❯ 1. Allow');
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(undefined, '--no-usage'),
        },
      ));
  }
});

describe('CHD-405 N2 tester: cycle-held permission cost', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`a held cycle has a current-turn row until its end, while a plain held request does not at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await ready(window);
          await send(window, 'claudecycleask');
          await window.shows('main asks · between turns');
          expect(await reported(window, '/cost')).toContain(
            'counted when it ends',
          );
          await leader(window, 'a');
          await window.shows('❯ 1. Allow');
          await window.press('1');
          await window.shows('Permission: allow.');
          await until(
            'the cycle ended',
            () => !window.frame().includes('Working…'),
          );
          expect(await reported(window, '/cost')).not.toContain('This turn:');
          await send(window, 'leftask');
          await window.shows('main asks · between turns');
          expect(await reported(window, '/cost')).not.toContain('This turn:');
        },
        {
          columns,
          rows,
          agentCommand: fakeAgentCommand(
            undefined,
            '--adapter',
            'claude',
            '--no-usage',
          ),
        },
      ));
  }
});

describe('CHD-373 S4 tester: whole-spend reports in the window', () => {
  const table = (window: Window) => {
    const lines = window.frame().split('\n');
    const start = lines.findLastIndex((line) => line.includes('This window'));

    expect(start).toBeGreaterThanOrEqual(0);

    return lines.slice(start).filter((line) => line.trim() !== '');
  };

  const row = (window: Window, name: string) =>
    table(window).find((line) => line.trimStart().startsWith(name)) ?? '';
  const teamBreakdown = (window: Window) => {
    const shown = table(window);

    return shown
      .slice(
        shown.findIndex((line) => line.trimStart().startsWith('bugfix')),
        shown.findIndex((line) =>
          line.trimStart().startsWith('Count the cost'),
        ),
      )
      .join(' ');
  };

  const showCost = async (window: Window, total?: string) => {
    await send(window, '/cost');
    await window.shows('This window');

    if (total) {
      await until('current cost snapshot', () =>
        row(window, 'Total').includes(total),
      );
    }
  };

  const rootTurns = async (window: Window, prompt: string, count: number) => {
    await until('root usage recorded', async () => {
      const records = await readRecords(join(window.dir, 'state'));
      const record = records.find(
        (each) => each.parent === undefined && each.prompt === prompt,
      );

      if (!record) {
        return false;
      }

      const lines = await readPast(record.path);

      return (
        new Set(
          lines.flatMap((entry) =>
            entry.type === 'usage' ? [entry.turnId] : [],
          ),
        ).size >= count
      );
    });
  };

  async function onWindow(
    body: (window: Window) => Promise<void>,
    columns: number,
    flags: string[] = [],
    more: NonNullable<Parameters<typeof withWindow>[1]> = {},
  ) {
    const server = serveChord();

    try {
      await withWindow(body, {
        columns,
        rows: columns === 80 ? 24 : 40,
        server,
        runtimes: ['fake'],
        agentCommand: fakeAgentCommand(undefined, ...flags),
        ...more,
      });
    } finally {
      await server.close();
    }
  }

  for (const columns of [80, 120]) {
    test(`closed child, clear history and closed tab remain in /cost at ${columns} columns`, () =>
      onWindow(async (window) => {
        await ready(window);
        await send(window, 'agentcost');
        await window.shows('Waiting on parser.');
        await rootTurns(window, 'agentcost', 1);
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('Working until stopped.');
        await window.press('x');
        await window.shows('x again to stop');
        await window.press('x');
        await window.shows('The person closed parser');
        await rootTurns(window, 'agentcost', 2);
        await until(
          'parser process closed',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window, '$0.0350');
        expect(row(window, 'parser')).toContain('$0.0100');
        expect(row(window, 'parser')).toContain('closed');
        expect(row(window, 'Total')).toContain('$0.0350');

        await send(window, '/clear');
        await ready(window);
        await send(window, 'text');
        await rootTurns(window, 'text', 1);
        await showCost(window, '$0.0475');
        expect(row(window, 'before /clear')).toContain('$0.0250');
        expect(row(window, 'parser')).toContain('$0.0100');
        expect(row(window, 'Total')).toContain('$0.0475');

        await leader(window, 'c');
        await ready(window);
        await send(window, 'text');
        await until('second tab turn recorded', async () => {
          const records = await readRecords(join(window.dir, 'state'));
          const texts = records.filter(
            (each) => each.parent === undefined && each.prompt === 'text',
          );

          return (
            texts.length === 2 &&
            (await Promise.all(texts.map((each) => readPast(each.path)))).every(
              (entries) => entries.some((entry) => entry.type === 'usage'),
            )
          );
        });

        await leader(window, 'k');
        await window.shows('Closed 2 fake');
        await showCost(window, '$0.0600');
        expect(row(window, '2 fake')).toContain('$0.0125');
        expect(row(window, '2 fake')).toContain('closed');
        expect(row(window, 'Total')).toContain('$0.0600');
      }, columns));

    test(`a closed child's ended task stays under its owner and is added once at ${columns} columns`, () =>
      onWindow(async (window) => {
        await ready(window);
        await send(window, 'agenttask');
        await window.shows('Waiting on parser.');
        await rootTurns(window, 'agenttask', 1);
        await window.shows('1 task asking');
        await until('parser spawning turn recorded', async () => {
          const records = await readRecords(join(window.dir, 'state'));
          const parser = records.find((record) => record.name === 'parser');

          if (!parser) {
            return false;
          }

          const past = await readPast(parser.path);
          const prompt = past.find((entry) => entry.type === 'prompt');

          return (
            prompt?.type === 'prompt' &&
            past.some(
              (entry) =>
                entry.type === 'result' && entry.turnId === prompt.turnId,
            )
          );
        });

        await leader(window, 'a');
        await window.shows('between turns');
        await leader(window, 'a');
        await window.shows('Agent(Fix the tokenizer)');
        await window.shows('Esc to reject');
        await window.press('1');
        await window.shows('Received the message from Fix the tokenizer');
        // The early progress message precedes the task's report and usage.
        await window.shows('← from Fix the tokenizer · fake · report');
        await window.press(DOWN);
        await window.shows('❯ parser');
        await window.press('x');
        await until(
          'child close decision',
          () =>
            window.frame().includes('x again to stop') ||
            window.frame().includes('The person closed parser'),
        );

        if (window.frame().includes('x again to stop')) {
          await window.press('x');
        }

        await window.shows('The person closed parser');
        await rootTurns(window, 'agenttask', 2);
        await until(
          'parser process closed',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window);

        const parser = row(window, 'parser');
        const task = row(window, 'Fix the tokenizer');
        const amount = (line: string) => {
          const matched = line.match(/\$(\d+\.\d+)/);

          expect(matched).not.toBeNull();

          return Number(matched![1]);
        };

        expect(parser).toContain('closed');
        expect(task).toContain('$0.0125');
        expect(task).toContain('ended');
        expect(task.indexOf('Fix the tokenizer')).toBe(
          parser.indexOf('parser') + 2,
        );
        expect(amount(row(window, 'Total'))).toBeCloseTo(
          amount(row(window, 'main')) + amount(parser) + 0.0125,
          9,
        );
      }, columns));

    test(`an agent that exits without usage stays not reported rather than zero at ${columns} columns`, () =>
      onWindow(async (window) => {
        await ready(window);
        await send(window, 'agentexit');
        await window.shows('Received the message from chord.');
        await window.shows('parser exited');
        await rootTurns(window, 'agentexit', 2);
        expect(window.pids.length).toBeGreaterThanOrEqual(2);
        await until(
          'exited parser reaped',
          async () => !(await isAlive(window.pids[1]!)),
        );
        await showCost(window);

        const parser = row(window, 'parser');
        const total = row(window, 'Total');
        const main = row(window, 'main');

        expect(parser).toContain('not reported');
        expect(parser).not.toContain('$0.0000');
        expect(total).toContain('not reported');
        expect(Number(total.match(/\$(\d+\.\d+)/)?.[1])).toBeCloseTo(
          Number(main.match(/\$(\d+\.\d+)/)?.[1]),
          9,
        );
      }, columns));

    test(`a team's task is owned by tester and kept out of the run subtotal at ${columns} columns`, async () => {
      const team = await readFile(
        new URL('../../fixtures/teams/fake/bugfix.md', import.meta.url),
        'utf8',
      );

      await onWindow(
        async (window) => {
          await ready(window);
          await send(window, 'team');
          await window.shows('Team(bugfix)');
          await window.shows('1 task running');
          await until('all team members recorded', async () => {
            const records = await readRecords(join(window.dir, 'state'));

            return ['tester', 'coder'].every((name) =>
              records.some((record) => record.name === name),
            );
          });

          await until('team task cost recorded', async () => {
            const records = await readRecords(join(window.dir, 'state'));
            const task = records.find(
              (record) => record.name === 'Count the cost',
            );

            return (
              task !== undefined &&
              (await readPast(task.path)).some(
                (entry) =>
                  entry.type === 'update' &&
                  entry.update.sessionUpdate === 'usage_update' &&
                  entry.update.cost?.amount === 0.01,
              )
            );
          });

          await showCost(window);

          const run = row(window, 'bugfix');
          const task = row(window, 'Count the cost');
          const amount = (line: string) => {
            const matched = line.match(/\$(\d+\.\d+)/);

            expect(matched).not.toBeNull();

            return Number(matched![1]);
          };

          expect(run).not.toContain('Count the cost');
          expect(task).toContain('running');
          expect(task).toMatch(/Count the cost\s+—\s+—/);

          if (columns === 80) {
            expect(run).toContain('team run: lead');

            for (const member of ['lead', 'tester', 'coder']) {
              expect(teamBreakdown(window)).toContain(member + ' ');
            }
          }

          if (columns === 120) {
            expect(task).toContain('task agent of tester');
          }

          expect(task.indexOf('Count the cost')).toBe(
            run.indexOf('bugfix') + 2,
          );
          expect(amount(row(window, '1 fake'))).toBeCloseTo(
            amount(row(window, 'main')) + amount(run),
            9,
          );

          // Pick tester in the real list and close its still-running task with it.
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press(DOWN);
          await window.shows('╭─ tester · bugfix');
          await window.press('x');
          await window.shows('x again to stop');
          await window.press('x');
          await until('tester closed in the records', async () => {
            const records = await readRecords(join(window.dir, 'state'));
            const lead = records.find((record) => record.name === 'bugfix');
            const tester = records.find((record) => record.name === 'tester');

            if (!lead || !tester) {
              return false;
            }

            const header = (await readPast(tester.path))[0];

            return (
              header?.type === 'session' &&
              (await readPast(lead.path)).some(
                (entry) => entry.type === 'closed' && entry.agent === header.id,
              )
            );
          });

          await window.press(ESC);
          await send(window, '/cost');
          await window.shows('This window');
          await until('ended task in cost snapshot', () =>
            row(window, 'Count the cost').includes('$0.0100'),
          );

          const ended = row(window, 'Count the cost');
          const keptRun = row(window, 'bugfix');

          expect(ended).toContain('ended');

          if (columns === 120) {
            expect(ended).toContain('task agent of tester');
          }

          expect(amount(row(window, '1 fake'))).toBeCloseTo(
            amount(row(window, 'main')) + amount(keptRun) + 0.01,
            9,
          );
          expect(amount(row(window, 'Total'))).toBeCloseTo(
            amount(row(window, '1 fake')),
            9,
          );

          if (columns === 80) {
            expect(keptRun).toMatch(/team run(, ended)?: lead/);

            for (const member of ['lead', 'tester', 'coder']) {
              expect(teamBreakdown(window)).toContain(member + ' ');
            }
          }
        },
        columns,
        ['--tester-plays', 'taskcost'],
        {
          teams: { bugfix: team },
          startupOf: () => ({
            agentCommand: fakeAgentCommand(
              undefined,
              '--tester-plays',
              'taskcost',
            ),
          }),
        },
      );
    });

    test(`an estimated session beside a silent agent keeps the estimate and missing note at ${columns} columns`, () =>
      onWindow(
        async (window) => {
          await ready(window);
          await send(window, 'text');
          await rootTurns(window, 'text', 1);
          await send(window, '/new silent');
          await ready(window);
          await send(window, 'text');
          await window.shows('This reply came in chunks.');
          await until(
            'silent turn ended',
            () => !window.frame().includes('Working…'),
          );
          await showCost(window);

          const estimate = row(window, '1 fake');
          const total = row(window, 'Total');

          expect(estimate).toContain('~$');
          expect(row(window, '2 silent')).toContain('not reported');
          expect(total).toContain('~$');
          expect(total).toContain('not reported');

          const estimatedAmount = Number(estimate.match(/\$(\d+\.\d+)/)?.[1]);
          const totalAmount = Number(total.match(/\$(\d+\.\d+)/)?.[1]);

          expect(Number.isFinite(estimatedAmount)).toBe(true);
          expect(totalAmount).toBeCloseTo(estimatedAmount, 9);
          expect(estimate).toContain("chord's estimate");
        },
        columns,
        ['--tokens-only'],
        {
          runtimes: ['fake', 'silent'],
          startupOf: (agent) => ({
            agentCommand:
              agent === 'silent'
                ? fakeAgentCommand(undefined, '--no-usage')
                : fakeAgentCommand(undefined, '--tokens-only'),
          }),
        },
      ));
  }

  test('a resumed legacy record says Before and Not counted without silently turning unknown spend into zero', async () => {
    let seeded = false;

    await onWindow(
      async (window) => {
        await ready(window);
        await send(window, '/resume');
        await window.shows('legacy seed');
        await window.press('\r');
        await window.shows('› legacy seed');
        await ready(window);
        await send(window, 'text');
        await rootTurns(window, 'legacy seed', 2);
        await send(window, '/cost');
        await window.shows('Not counted:');

        const shown = window.frame();

        expect(shown).toContain('Before:');
        expect(shown).toContain('$0.0400 as last reported');
        expect(shown).toContain('1 turn');
        expect(shown).toContain('Total cost:');
        expect(shown).toContain('$0.0400');
      },
      120,
      ['--resume-only', '--cost-from', '0.04'],
      {
        readRecords: async (stateDir) => {
          if (!seeded) {
            seeded = true;

            const dir = join(stateDir, 'records');
            const id = crypto.randomUUID();
            const entries = [
              {
                type: 'session',
                version: 1,
                sessionId: id,
                agent: 'fake',
                cwd: stateDir.slice(0, -'/state'.length),
                at: 1,
              },
              {
                type: 'prompt',
                turnId: 'legacy',
                prompt: 'legacy seed',
                images: 0,
                at: 1,
              },
              {
                type: 'update',
                turnId: 'legacy',
                update: {
                  sessionUpdate: 'usage_update',
                  used: 10,
                  size: 100,
                  cost: { amount: 0.04, currency: 'USD' },
                },
              },
              { type: 'usage', turnId: 'legacy', usage: { totalTokens: 2000 } },
              {
                type: 'result',
                turnId: 'legacy',
                result: { status: 'completed', stopReason: 'end_turn' },
                at: 2,
              },
            ];

            await mkdir(dir, { recursive: true });
            await writeFile(
              join(dir, `${id}.jsonl`),
              entries.map((entry) => JSON.stringify(entry)).join('\n') + '\n',
            );
          }

          return readRecords(stateDir);
        },
      },
    );
  });
});

/** The last program status the terminal was told, its fields as written. */
function lastStatus(
  log: readonly string[],
): Record<string, string> | undefined {
  return statusReports(log).at(-1);
}

test("the terminal hears chord work, then done with the notification's words, then idle at the next key (CHD-382)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await until(
        'idle to be reported',
        () => lastStatus(log)?.state === 'idle',
      );
      expect(lastStatus(log)).toStrictEqual({ state: 'idle', app: 'chord' });
      await send(window, 'slow');
      await until(
        'working to be reported',
        () => lastStatus(log)?.state === 'working',
      );
      await until(
        'done to be reported',
        () => lastStatus(log)?.state === 'done',
      );
      expect(lastStatus(log)).toStrictEqual({
        state: 'done',
        app: 'chord',
        msg: 'fake is waiting for your input',
      });

      const sent = statusReports(log).length;

      await window.type('x');
      await until(
        'idle to be reported',
        () => lastStatus(log)?.state === 'idle',
      );
      // Each change once: a draw that changes nothing reports nothing.
      expect(statusReports(log).slice(sent)).toStrictEqual([
        { state: 'idle', app: 'chord' },
      ]);
    },
    { log },
  );
});

test('a permission is reported blocked with its kind and words, and the answer goes back to work (CHD-382)', () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await send(window, 'permission');
      await asked(window);
      expect(lastStatus(log)).toStrictEqual({
        state: 'blocked',
        kind: 'permission',
        app: 'chord',
        msg: 'fake needs your permission: Write notes.txt',
      });
      await window.press('1');
      await until(
        'done to be reported',
        () => lastStatus(log)?.state === 'done',
      );
    },
    { log },
  );
});

test("ctrl+g clears chord's status for the editor and reports it again once back (CHD-382)", () => {
  const log: string[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await window.press(CTRL_G);
      await window.shows('from the editor');

      const editor = log.findIndex((chunk) => chunk.startsWith('editor: '));
      const reports = (chunks: readonly string[]) => statusReports(chunks);

      expect(reports(log.slice(0, editor)).at(-1)).toStrictEqual({
        state: 'clear',
      });
      expect(reports(log.slice(editor))).toStrictEqual([
        { state: 'idle', app: 'chord' },
      ]);
    },
    {
      log,
      editor: (draft) => {
        log.push(`editor: ${draft}`);

        return Promise.resolve({ text: 'from the editor' });
      },
    },
  );
});

describe("a picked child on another runtime is named by its own agent, not the tab's (CHD-488)", () => {
  /**
   * Opens `foreign`, a codex child of main on the fake tab, its agent
   * started by `codex` and given `prompt`, and picks it.
   */
  async function onChild(
    codex: readonly string[],
    prompt: string,
    body: (window: Window) => Promise<void>,
    options: Parameters<typeof withWindow>[1] = {},
  ): Promise<void> {
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
            prompt,
          });
          await window.shows('foreign');
          await window.press(DOWN);
          await window.press(DOWN);
          await window.press('\r');
          await window.shows('╭─ foreign ─');
          await body(window);
        },
        {
          ...options,
          server,
          runtimes: ['fake', 'codex'],
          agentCommand: command,
          startupOf: (agent) => ({
            agentCommand: agent === 'codex' ? [...codex] : command,
          }),
        },
      );
    } finally {
      await server.close();
    }
  }

  test('the status line says the child is starting by its own agent', async () => {
    // The child's agent starts only once the gate is there.
    const gates = await mkdtemp(join(tmpdir(), 'chord-gate-'));
    const gate = join(gates, 'open');

    try {
      await onChild(
        gatedCommand(gate, fakeAgentCommand()),
        'text',
        async (window) => {
          await window.shows('Starting codex…');
          expect(window.frame()).not.toContain('Starting fake…');
          await writeFile(gate, '');
        },
      );
    } finally {
      await rm(gates, { recursive: true, force: true });
    }
  });

  test('a child whose agent did not start says so by its own agent', () =>
    onChild(['sh', '-c', 'exit 1'], 'text', async (window) => {
      await window.shows('codex did not start:');
      expect(window.frame()).not.toContain('fake did not start');
    }));

  test("a form's record names the child's agent as who asked", () =>
    onChild(fakeAgentCommand(), 'text', async (window) => {
      await window.shows('came in chunks.');
      await send(window, 'form');
      await inputAsked(window, 'foreign asks for input');
      await window.press(ESC);
      await window.shows('codex asked');
      expect(window.frame()).not.toContain('fake asked');
    }));

  test("/model and /config name the child's agent", () =>
    onChild(fakeAgentCommand(), 'text', async (window) => {
      await window.type('/model');
      await window.press('\r');
      await until('the model picker', () =>
        /codex offers no models|Switch codex's model/.test(window.frame()),
      );
      expect(window.frame()).not.toMatch(/fake offers|Switch fake's/);
      await window.press(ESC);
      await window.type('/config');
      await window.press('\r');
      await until('the settings picker', () =>
        /codex has no settings|Change codex's settings/.test(window.frame()),
      );
      expect(window.frame()).not.toMatch(/fake has no settings|Change fake's/);
    }));

  test("ctrl+v's refusal names the child's agent", () =>
    onChild(
      fakeAgentCommand(undefined, '--no-images'),
      'text',
      async (window) => {
        await window.shows('came in chunks.');
        await window.press('\x16');
        await window.shows('codex does not take images');
        expect(window.frame()).not.toContain('fake does not take images');
      },
      { clipboard: () => Promise.resolve({ failed: 'not read' }) },
    ));
});
