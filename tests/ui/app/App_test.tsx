/**
 * The window on the fake agent: its header, a turn, its notifications, the
 * keys that quit, clear and edit, the slash commands, and a child beside main.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import { draw } from '../harness.tsx';
import { type Resumable } from '../../../src/session/sessions.ts';
import { App } from '../../../src/ui/app/App.tsx';
import * as ansi from '../../../src/ui/theme/Ansi.tsx';
import { editInEditor } from '../../../src/editor.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import {
  asked,
  CTRL_C,
  CTRL_D,
  CTRL_G,
  DOWN,
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
          title: 'agentother',
        });
        // Q194: ↓ from the permission's last choice reaches the list.
        await window.press(DOWN);
        await window.press(DOWN);
        await window.press(DOWN);
        await window.shows('❯ other');
        await window.press(UP);
        await window.press('\r');
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

test("the window's first row is its header's", () =>
  withWindow(
    async (window) => {
      const first = () => window.frame().split('\n')[0] ?? '';

      await window.shows('chord v');
      expect(first()).toContain(`chord v${VERSION}`);
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
