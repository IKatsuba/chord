/**
 * The window on the fake agent: its header, a turn, its notifications, and
 * the keys that quit, clear and edit.
 */
import { describe, expect, spyOn, test } from 'bun:test';
import assert from 'node:assert/strict';
import { openSession, type Session } from '../../../src/session/session.ts';
import { frontState, type AppState } from '../../../src/ui/app/state.ts';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from './child_window.tsx';
import * as ansi from '../../../src/ui/theme/Ansi.tsx';
import { editInEditor } from '../../../src/editor.ts';
import {
  asked,
  CTRL_C,
  CTRL_D,
  CTRL_G,
  CTRL_X,
  DOWN,
  END,
  ESC,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  statusReports,
  statusRow,
  TAB,
  until,
  UP,
  type Window,
  withWindow,
} from './render.tsx';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import { pixelClipboard, RECEIVED } from '../prompt/prompt_window.tsx';
import { STEER_REFUSED, UNSTEERED } from '../../../src/ui/status/Status.tsx';
import manifest from '../../../package.json' with { type: 'json' };

import { OSC9, writes } from './app_window.tsx';
import { clipboard } from './selecting.ts';

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
      await window.shows('bun quality');

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

test("main's /clear puts its queued prompt back with its image, which goes when it is sent again (CHD-476)", () =>
  withWindow(
    async (window) => {
      await send(window, 'costwait');
      await window.shows('Working until stopped.');

      // Typed key by key: pasted, the path would be read at once.
      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await window.shows('› see [Image #1]');
      await send(window, '/clear');
      await until('the queued prompt back in the box', () =>
        window.frame().includes('│ › see [Image #1]'),
      );
      // Enter sends once the fresh session is up; before, it waits.
      await until('sent to the fresh session', async () => {
        if (!window.frame().includes('│ › see [Image #1]')) {
          return true;
        }

        await window.press('\r');

        return false;
      });

      await window.shows(RECEIVED);
    },
    {
      readImage: () =>
        Promise.resolve({
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        }),
    },
  ));

describe('Tab sends the oldest queued message into the running turn (CHD-535)', () => {
  /** `text` typed into the box, there before the next key. */
  const draft = async (window: Window, text: string) => {
    await window.type(text);
    await until(
      `"${text}" in the box`,
      () => promptRow(window)?.includes(text) ?? false,
    );
  };

  /** How many times `text` is on the screen. */
  const saidCount = (window: Window, text: string) =>
    window.frame().split(text).length - 1;

  /** The rows under the working line that read `› text`. */
  const queuedRows = (window: Window, text: string) =>
    window
      .frame()
      .split('\n')
      .filter((row) => row.trimEnd().endsWith(`› ${text}`));

  test('on an agent that steers, the oldest goes in, then the next, the draft left as it is', () =>
    withWindow(
      async (window) => {
        await send(window, 'readsheld');
        await window.shows('esc to interrupt');
        await send(window, 'Use the second parser instead');
        await send(window, 'Then update the changelog');
        await draft(window, 'and keep the old one');
        await window.press(TAB);
        await until(
          'the first read in the turn',
          () => saidCount(window, 'Read the message from nobody.') === 1,
        );

        expect(queuedRows(window, 'Then update the changelog')).toHaveLength(1);
        expect(promptRow(window)).toContain('and keep the old one');
        await window.press(TAB);
        await until(
          'the second read in the turn',
          () => saidCount(window, 'Read the message from nobody.') === 2,
        );

        expect(window.frame()).toContain('› Use the second parser instead');
        expect(window.frame()).toContain('› Then update the changelog');
        expect(window.frame()).toContain('esc to interrupt');
        expect(promptRow(window)).toContain('and keep the old one');
        await window.press(ESC);
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        rows: 60,
      },
    ));

  test('on an agent that does not, it stays queued, the draft stays, and the status line says why', () =>
    withWindow(async (window) => {
      await send(window, 'readsheld');
      await window.shows('esc to interrupt');
      await send(window, 'Use the second parser instead');
      await draft(window, 'and keep the old one');
      await window.press(TAB);
      await until('the note', () => statusRow(window).includes(UNSTEERED));

      expect(queuedRows(window, 'Use the second parser instead')).toHaveLength(
        1,
      );
      expect(promptRow(window)).toContain('and keep the old one');
      await until(
        'the note to go',
        () => !statusRow(window).includes(UNSTEERED),
      );
      await window.press(ESC);
    }));

  test('refused while the turn runs, it is back in its row and the status line says so', () =>
    withWindow(
      async (window) => {
        await send(window, 'readsheld');
        await window.shows('esc to interrupt');
        await send(window, 'Use the second parser instead');
        await window.press(TAB);
        await until('the note', () =>
          statusRow(window).includes(STEER_REFUSED),
        );

        expect(
          queuedRows(window, 'Use the second parser instead'),
        ).toHaveLength(1);
        expect(window.frame()).not.toContain('› into the running turn:');
        await window.press(ESC);
      },
      {
        agentCommand: fakeAgentCommand(
          undefined,
          '--steering',
          'claude',
          '--steer-refuse',
        ),
      },
    ));

  test("one held behind Claude's open calls waits in the queue saying so, and Esc takes it back to the box", () =>
    withWindow(
      async (window) => {
        await send(window, 'bashcut');
        await window.shows('Running…');
        await send(window, 'Skip the slow tests');
        await window.press(TAB);
        await window.shows('› after the running calls: Skip the slow tests');
        await window.press(ESC);
        await window.shows('Interrupted by user');
        await until(
          'the prompt back in the box',
          () => promptRow(window)?.includes('Skip the slow tests') ?? false,
        );
        expect(window.frame()).not.toContain('after the running calls');
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
      },
    ));

  test('one the agent leaves unanswered shows as going into the turn, Esc leaves it, and refused late it goes as the next turn', () =>
    withWindow(
      async (window) => {
        // Held until the cancel, however slow the machine (CHD-526).
        await send(window, 'texttillsteeredheld');
        await window.shows('This reply came in chunks.');
        await send(window, 'Use the second parser instead');
        await window.press(TAB);
        await window.shows(
          '› into the running turn: Use the second parser instead',
        );
        await window.press(ESC);
        await window.shows('Interrupted by user');

        expect(promptRow(window)).not.toContain('Use the second parser');
        await until(
          'the refused steer to go as the next turn',
          () => !window.frame().includes('into the running turn'),
        );
        await window.shows('› Use the second parser instead');
        expect(statusRow(window)).not.toContain(STEER_REFUSED);
        await window.press(ESC);
      },
      {
        agentCommand: fakeAgentCommand(
          undefined,
          '--steering',
          'claude',
          '--steer-late',
        ),
      },
    ));

  test('Esc at once after Tab leaves it with the agent: not back in the box, and refused late it goes as the next turn, once', () =>
    withWindow(
      async (window) => {
        await send(window, 'texttillsteeredheld');
        await window.shows('This reply came in chunks.');
        await send(window, 'Use the second parser instead');
        await window.press(TAB);
        // Before the row says it is going into the turn.
        await window.press(ESC);
        await window.shows('Interrupted by user');

        expect(promptRow(window)).not.toContain('Use the second parser');
        await until(
          'the refused message to go as the next turn',
          () => saidCount(window, '› Use the second parser instead') === 1,
        );
        await window.press('\r');

        expect(promptRow(window)).not.toContain('Use the second parser');
        expect(saidCount(window, '› Use the second parser instead')).toBe(1);
        await window.press(ESC);
      },
      {
        agentCommand: fakeAgentCommand(
          undefined,
          '--steering',
          'claude',
          '--steer-late',
        ),
      },
    ));

  test("queued with an image file read and a file's link, it goes in with both (the owner's Q215, Q216)", () =>
    withWindow(
      async (window) => {
        await writeFile(join(window.dir, 'a.ts'), '');
        await send(window, 'readsheld');
        await window.shows('esc to interrupt');

        // Typed key by key: pasted, the path would be read at once.
        for (const key of 'see /shots/a.png @a.ts ') {
          await window.press(key);
        }

        await window.press('\r');
        await window.shows('› see [Image #1] @a.ts');
        await window.press(TAB);
        await window.shows(RECEIVED);
        await window.shows('Received a link: a.ts');
        await window.press(ESC);
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        readImage: () =>
          Promise.resolve({
            mediaType: 'image/png',
            data: PIXEL_PNG,
            bytes: PIXEL_BYTES.length,
          }),
      },
    ));
});

describe('ctrl+x b picks a code block, and its keys copy it or put it in the prompt (CHD-394)', () => {
  const HINT = '↑ ↓ another block · c copy · r put in the prompt · esc done';
  const LONG =
    'bun dev chord --fake --qa capture && tmux capture-pane -t chord-qa -p > /tmp/screen.txt\n\necho done';

  test('the newest block on screen is picked, ↑ moves the pick, and c copies the block picked', () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await window.press(CTRL_X);

        expect(statusRow(window)).toContain('b a code block');
        await window.press('b');
        await until('the pick', () => statusRow(window).includes(HINT));
        // ↑ is the pick's, not history's.
        await window.press(UP);
        expect(promptRow(window)).not.toContain('markdowncode');
        await window.press('c');
        await until('the copy', () => copies.length === 1);

        expect(copies[0]!.text).toStrictEqual(LONG);
        await window.shows(`copied ${LONG.length} chars to clipboard`);
        expect(promptRow(window)).not.toContain('c');
      },
      { columns: 80, rows: 40, copy },
    );
  });

  test('r puts the picked command into the prompt in bash mode, and does nothing on a block with no [run]', () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press('r');
        await window.shows('│ ! bun dev check');

        // The typescript box, first on screen, has no [run].
        await window.press('\x15');
        await window.press('\x7f');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press(UP);
        await window.press(UP);
        await until('the typescript box picked', () =>
          statusRow(window).includes('↑ ↓ another block · c copy · esc done'),
        );
        await window.press('r');
        expect(statusRow(window)).toContain(
          '↑ ↓ another block · c copy · esc done',
        );
        expect(promptRow(window)).not.toContain('!');
      },
      { columns: 80, rows: 40 },
    ));

  test("the pick's line stands alone, before bash mode and a mode other than the default", () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press('r');
        await window.shows('│ ! bun dev check');
        await until('bash mode', () =>
          statusRow(window).includes('! for bash mode'),
        );
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));

        expect(statusRow(window)).not.toContain('bash mode');
        await window.press(ESC);
        await window.press('\x15');
        await window.press('\x7f');
        await window.press('\x1b[Z');
        await until('accept edits', () =>
          statusRow(window).includes('⏵⏵ accept edits on'),
        );
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));

        expect(statusRow(window)).not.toContain('accept edits');
      },
      { columns: 80, rows: 40 },
    ));

  test('in a window too narrow for its first item, the pick keeps the whole items after it that fit', () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('   after.');
        await leader(window, 'b');
        // 16 cells: `ctrl + p ctrl + n block` is too wide, `y copy` fits.
        await until('the pick', () => statusRow(window).includes('y copy'));

        expect(statusRow(window)).not.toContain('ctrl + p');
      },
      {
        columns: 20,
        rows: 40,
        keybindings: JSON.stringify({
          bindings: [
            {
              context: 'CodeBlock',
              bindings: {
                up: null,
                'ctrl+p': 'codeBlock:previous',
                down: null,
                'ctrl+n': 'codeBlock:next',
                c: null,
                y: 'codeBlock:copy',
                r: null,
                p: 'codeBlock:prompt',
                escape: null,
                'ctrl+q': 'codeBlock:cancel',
              },
            },
          ],
        }),
      },
    ));

  test('esc ends the pick with nothing done, and any other key ends it and does its own', () =>
    withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press(ESC);
        await until('the pick to end', () => !statusRow(window).includes(HINT));
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press('x');
        await window.shows('› x');
        expect(statusRow(window)).not.toContain(HINT);
      },
      { columns: 80, rows: 40 },
    ));

  test("picked again at once after a copy, the line says the pick's keys, not the copy's note", () => {
    const { copies, copy } = clipboard();

    return withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press('c');
        await window.shows('copied 13 chars to clipboard');
        await leader(window, 'b');
        // Within the copy note's 3 s: the frame after b says the pick's keys.
        await until(
          'the leader line to go',
          () => !statusRow(window).includes('ctrl+x …'),
        );

        expect(statusRow(window)).toContain(HINT);
        expect(statusRow(window)).not.toContain('copied');
        expect(copies).toHaveLength(1);
      },
      { columns: 80, rows: 40, copy },
    );
  });

  test("the picked box's buttons are bold until the pick ends, where the window draws with no colour", () => {
    // A row as a terminal would be sent it, its colours written.
    const row = (window: Window, marker: string) => {
      const level = chalk.level;

      chalk.level = 3;

      try {
        return (
          window
            .frame()
            .split('\n')
            .find((line) => stripAnsi(line).includes(marker)) ?? ''
        );
      } finally {
        chalk.level = level;
      }
    };

    const LISTED = '┌─ sh ─[copy]─[run]─┐';

    return withWindow(
      async (window) => {
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));

        // Its buttons bold, which no border is; with no colour, its border
        // the terminal's own foreground, not the grey of every other box.
        expect(row(window, LISTED)).toContain('\x1b[1m[copy]');
        expect(row(window, LISTED)).not.toContain('38;5;244');
        expect(row(window, '┌─ typescript')).toContain('38;5;244');
        expect(row(window, '┌─ typescript')).not.toContain('\x1b[1m');
        await window.press(ESC);
        await until(
          'the bold to go',
          () => !row(window, LISTED).includes('\x1b[1m'),
        );
      },
      { columns: 80, rows: 40 },
    );
  });

  test('↑ to a block out of view scrolls the transcript to show it', () =>
    withWindow(
      async (window) => {
        await send(window, 'markdown');
        await window.shows('built $bin');
        await leader(window, 'b');
        await until('the pick', () =>
          statusRow(window).includes('another block'),
        );
        // The quoted ts block, the reply's first, is scrolled off at 24 rows.
        expect(window.frame()).not.toContain('┌ ts');

        for (let up = 0; up < 3; up++) {
          await window.press(UP);
        }

        await window.shows('┌ ts');
        expect(window.frame()).toContain('await session.close();');
        // Down to the ts box: its border, label and [copy] are the view's
        // top row, the whole box in view.
        await window.press(DOWN);
        await until('the ts box on top', () =>
          (window.frame().split('\n')[0] ?? '').includes('┌─ ts'),
        );
        expect(window.frame().split('\n')[0]).toContain('[copy]');
      },
      { columns: 80, rows: 24 },
    ));

  test("in a long history, ctrl+x b reaches the newest code past the mounted tail, and ↑ crosses into it from the tail's", () => {
    const { copies, copy } = clipboard();
    const BUILT =
      'bun dev compile --all\nfor bin in dist/*/chord; do echo "built $bin"; done';
    // Enough turns of plain text that the code reply leaves the tail of
    // entries mounted while following (TAIL_ENTRIES).
    // Each turn ends on a reply of its own, which `verbatim` gives back as
    // sent, so the next goes only once that one is drawn: 22 turns are 44
    // entries after the code reply's two, past the 40 of the tail.
    const plain = async (window: Window) => {
      for (let turn = 0; turn < 22; turn++) {
        await send(window, `verbatim turn ${turn}`);
        await window.shows(`"turn ${turn}"`);
        await until(
          `turn ${turn} to end`,
          () => !window.frame().includes('esc to interrupt'),
        );
      }
    };

    return withWindow(
      async (window) => {
        await send(window, 'markdown');
        await window.shows('built $bin');
        await plain(window);
        expect(window.frame()).not.toContain('[copy]');

        // No code in the mounted tail: the transcript's newest is picked,
        // mounted and shown.
        await leader(window, 'b');
        await window.shows('┌─ sh ───');
        await until('the pick', () => statusRow(window).includes(HINT));
        await window.press('c');
        await until('the copy', () => copies.length === 1);
        expect(copies[0]!.text).toStrictEqual(BUILT);

        // A code reply in the tail; ↑ from it goes back past the tail.
        await window.press(END);
        await send(window, 'markdowncode');
        await window.shows('A paragraph after.');
        await leader(window, 'b');
        await until('the pick', () => statusRow(window).includes(HINT));

        for (let up = 0; up < 3; up++) {
          await window.press(UP);
        }

        await window.press('c');
        await until('the second copy', () => copies.length === 2);
        expect(copies[1]!.text).toStrictEqual(BUILT);
      },
      { columns: 80, rows: 24, copy },
    );
  });

  test('with no code block in the transcript, ctrl+x b says so', () =>
    withWindow(async (window) => {
      await send(window, 'text');
      await window.shows('This reply came in chunks.');
      await leader(window, 'b');
      await until('the note', () =>
        statusRow(window).includes('No code block to pick'),
      );
    }));
});

describe('CHD-394 U4 tester: rebound keys and tall picks', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`rebound actions own the pick, preserve a typed draft and release keys afterwards at ${columns} columns`, () => {
      const { copies, copy } = clipboard();

      return withWindow(
        async (window) => {
          await send(window, 'markdowncode');
          await window.shows('A paragraph after.');
          await window.type('kept draft');
          await window.shows('› kept draft');
          await leader(window, 'k');
          await window.shows(
            columns === 80
              ? 'y copy · p prompt · ctrl + q done'
              : 'y copy · p put in the prompt · ctrl + q done',
          );
          await window.press('\x10');
          await window.press('\x0e');
          await window.press('y');
          await until('rebound copy', () => copies.length === 1);
          expect(copies[0]?.text).toBe('bun dev check');
          expect(promptRow(window)).toContain('kept draft');
          await leader(window, 'k');
          await window.press('p');
          await window.shows('The prompt holds a draft · ctrl+c clears it');
          expect(promptRow(window)).toContain('kept draft');
          await leader(window, 'k');
          await window.press('\x11');
          await until(
            'the rebound cancel ends picking',
            () => !statusRow(window).includes('y copy'),
          );
          await window.type('z');
          await window.shows('› kept draftz');
        },
        {
          columns,
          rows,
          copy,
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'Global',
                bindings: { 'ctrl+x b': null, 'ctrl+x k': 'codeBlock:pick' },
              },
              {
                context: 'CodeBlock',
                bindings: {
                  c: null,
                  y: 'codeBlock:copy',
                  r: null,
                  p: 'codeBlock:prompt',
                  up: null,
                  'ctrl+p': 'codeBlock:previous',
                  down: null,
                  'ctrl+n': 'codeBlock:next',
                  escape: null,
                  'ctrl+q': 'codeBlock:cancel',
                },
              },
            ],
          }),
        },
      );
    });

    test(`a taller-than-view box lands its top border on top and copies every hidden line at ${columns} columns`, () => {
      const { copies, copy } = clipboard();
      const body = Array.from(
        { length: 50 },
        (_, index) => `printf tall-line-${index}`,
      ).join('\n');

      return withWindow(
        async (window) => {
          await window.paste('/echo ```sh\n' + body + '\n```');
          await window.press('\r');
          await window.shows('printf tall-line-49');
          await until(
            'the echoed code turn ends',
            () => !statusRow(window).includes('esc to interrupt'),
          );
          await leader(window, 'b');
          await until('the tall box top is shown', () =>
            (window.frame().split('\n')[0] ?? '').includes('┌─ sh'),
          );
          expect(window.frame()).toContain('printf tall-line-0');
          expect(window.frame()).not.toContain('printf tall-line-49');
          await window.press('c');
          await until('all hidden lines copied', () => copies.length === 1);
          expect(copies[0]?.text).toBe(body);
        },
        { columns, rows, copy },
      );
    });
  }
});

describe('CHD-394 U4 tester: unbound pick fallback', () => {
  for (const columns of [80, 120]) {
    test(`with every pick action unbound the neutral line overrides bash and a letter ends picking at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await send(window, 'markdowncode');
          await window.shows('A paragraph after.');
          await window.type('!echo kept');
          await window.shows('│ ! echo kept');
          await leader(window, 'b');
          await window.shows('picking a code block');
          expect(statusRow(window)).not.toContain('bash mode');
          await window.type('z');
          await window.shows('│ ! echo keptz');
          expect(statusRow(window)).not.toContain('picking a code block');
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          keybindings: JSON.stringify({
            bindings: [
              {
                context: 'CodeBlock',
                bindings: {
                  up: null,
                  down: null,
                  c: null,
                  r: null,
                  escape: null,
                },
              },
            ],
          }),
        },
      ));
  }
});

describe('CHD-535 U2 tester: queued ownership through the window', () => {
  for (const outcome of ['injected', 'refused'] as const) {
    for (const columns of [80, 120]) {
      test(`early Esc keeps an image and link owned until late ${outcome} at ${columns} columns`, async () => {
        const release = Promise.withResolvers<void>();
        const outcomes: string[] = [];
        const steers: Parameters<Session['steer']>[] = [];
        const prompts: Parameters<Session['prompt']>[] = [];
        let state: AppState | undefined;
        const text = 'see [Image #1] @a.ts done';
        const users = () =>
          state?.transcript.entries.filter(
            (entry) => entry.kind === 'user' && entry.text === text,
          ) ?? [];

        await withWindow(
          async (window) => {
            try {
              await writeFile(join(window.dir, 'a.ts'), '');
              await send(window, 'texttillsteeredheld');
              await window.shows('This reply came in chunks.');

              for (const key of 'see /shots/a.png @a.ts done') {
                await window.press(key);
              }

              await window.press('\r');
              await window.shows(`› ${text}`);
              await until(
                'image prompt leaves the box',
                () => state?.draft === '',
              );

              const original = state?.queue.find((row) => row.text === text);

              assert(original !== undefined);

              const running = state?.transcript.turn;

              assert(running !== undefined && running.status !== 'idle');

              const runningTurnId = running.turnId;

              await window.type('untouched draft');
              await until(
                'draft ready',
                () => state?.draft === 'untouched draft',
              );
              await window.press(TAB);
              await until(
                'the adapter answered behind the gate',
                () => outcomes.length === 1,
              );
              expect(outcomes).toEqual([outcome]);

              const taken = state?.queue.find(
                (row) => row.turnId === original.turnId,
              );

              expect(taken?.taken).toBe(true);
              expect(taken?.steering).toBeUndefined();
              await window.press(ESC);
              await window.shows('Interrupted by user');
              expect(state?.draft).toBe('untouched draft');
              expect(state?.images).toEqual([]);
              expect(users()).toHaveLength(0);
              release.resolve();
              await until(
                'the one owned message delivered',
                () =>
                  users().length === 1 &&
                  !state?.queue.some((row) => row.turnId === original.turnId),
              );
              expect(users()[0]?.turnId).toBe(
                outcome === 'injected' ? runningTurnId : original.turnId,
              );
              expect(steers).toHaveLength(1);
              expect(steers[0]?.slice(0, 3)).toEqual([
                text,
                [{ mediaType: 'image/png', data: PIXEL_PNG }],
                ['a.ts'],
              ]);
              expect(
                prompts.filter(([prompt]) => prompt.includes(text)),
              ).toHaveLength(outcome === 'refused' ? 1 : 0);

              if (outcome === 'refused') {
                const fallback = prompts.find(([prompt]) =>
                  prompt.includes(text),
                );

                expect([fallback?.[1], fallback?.[2]]).toEqual([
                  steers[0]?.[1],
                  steers[0]?.[2],
                ]);
                await window.shows(RECEIVED);
                await window.shows('Received a link: a.ts');
              }

              expect(statusRow(window)).not.toContain(STEER_REFUSED);
              expect(state?.draft).toBe('untouched draft');
              await window.press('\r');
              await until('only the untouched draft sent', () =>
                prompts.some(([prompt]) => prompt.includes('untouched draft')),
              );
              expect(users()).toHaveLength(1);
              expect(
                prompts.find(([prompt]) =>
                  prompt.includes('untouched draft'),
                )?.[1] ?? [],
              ).toEqual([]);
            } finally {
              release.resolve();
            }
          },
          {
            columns,
            rows: columns === 80 ? 24 : 40,
            agentCommand: fakeAgentCommand(
              undefined,
              '--steering',
              'claude',
              ...(outcome === 'refused' ? ['--steer-refuse'] : []),
            ),
            onState: (all) => {
              state = frontState(all);
            },
            readImage: () =>
              Promise.resolve({
                mediaType: 'image/png',
                data: PIXEL_PNG,
                bytes: PIXEL_BYTES.length,
              }),
            openWith: async (options) => {
              const session = await openSession(options);
              const steer = session.steer.bind(session);
              const prompt = session.prompt.bind(session);

              session.prompt = (...args) => {
                prompts.push(args);

                return prompt(...args);
              };

              session.steer = async (...args) => {
                steers.push(args);

                const result = await steer(...args);

                outcomes.push(result);
                await release.promise;

                return result;
              };

              return session;
            },
          },
        );
      });
    }
  }

  test('a rebound key sends queued FIFO at 80 columns, leaves draft and history alone, and ignores an empty queue', () => {
    const steers: string[] = [];
    let state: AppState | undefined;

    return withWindow(
      async (window) => {
        await send(window, 'readsheld');
        await window.shows('esc to interrupt');
        await window.type('keep this draft');
        await window.press('\x19');
        expect(steers).toEqual([]);
        expect(state?.steerRefused).toBeUndefined();
        await window.press('\x15');
        await send(window, 'first queued');
        await send(window, 'second queued');
        await window.type('keep this draft');
        await window.press(TAB);
        expect(steers).toEqual([]);
        await window.press('\x19');
        await until(
          'first queued accepted',
          () => steers.length === 1 && state?.queue.length === 1,
        );
        await window.press('\x19');
        await until(
          'second queued accepted',
          () => steers.length === 2 && state?.queue.length === 0,
        );
        await window.press('\x19');
        expect(steers).toEqual(['first queued', 'second queued']);
        expect(state?.draft).toBe('keep this draft');
        expect(state?.steerRefused).toBeUndefined();
        await window.press(ESC);
        await window.press('\x15');

        for (const previous of ['second queued', 'first queued', 'readsheld']) {
          await window.press(UP);
          await until(
            'unchanged submission history',
            () => state?.draft === previous,
          );
        }
      },
      {
        columns: 80,
        rows: 24,
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        keybindings: JSON.stringify({
          bindings: [
            {
              context: 'Chat',
              bindings: { tab: null, 'ctrl+y': 'chat:steer' },
            },
          ],
        }),
        onState: (all) => {
          state = frontState(all);
        },
        openWith: async (options) => {
          const session = await openSession(options);
          const steer = session.steer.bind(session);

          session.steer = (...args) => {
            steers.push(args[0]);

            return steer(...args);
          };

          return session;
        },
      },
    );
  });

  test('a clipboard image held behind calls returns on Esc and is submitted once with its link', async () => {
    const image = pixelClipboard();
    const prompts: Parameters<Session['prompt']>[] = [];
    const steers: Parameters<Session['steer']>[] = [];
    let state: AppState | undefined;

    await withWindow(
      async (window) => {
        await writeFile(join(window.dir, 'a.ts'), '');
        await send(window, 'bashcut');
        await window.shows('Running…');
        await window.type('see @a.ts done');
        await window.press('\x16');
        await until(
          'clipboard image in draft',
          () => state?.images.length === 1,
        );
        await window.press('\r');
        await until('image queued', () => state?.queue.length === 1);

        const text = state?.queue[0]?.text;

        assert(text !== undefined);
        await window.press(TAB);
        await window.shows(`› after the running calls: ${text}`);
        await window.press(ESC);
        await window.shows('Interrupted by user');
        await until(
          'held image restored',
          () => state?.draft === text && state.images.length === 1,
        );
        expect(state?.images[0]?.data).toBe(PIXEL_PNG);
        expect(steers).toEqual([]);
        await window.press('\r');
        await window.shows(RECEIVED);
        await window.shows('Received a link: a.ts');
        expect(
          prompts.filter(([prompt]) => prompt.includes(text)),
        ).toHaveLength(1);
        expect(
          prompts.find(([prompt]) => prompt.includes(text))?.slice(1, 3),
        ).toEqual([[{ mediaType: 'image/png', data: PIXEL_PNG }], ['a.ts']]);
        expect(image.reads).toBe(1);
        expect(state?.images).toEqual([]);
      },
      {
        columns: 80,
        rows: 24,
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        clipboard: image,
        onState: (all) => {
          state = frontState(all);
        },
        openWith: async (options) => {
          const session = await openSession(options);
          const prompt = session.prompt.bind(session);
          const steer = session.steer.bind(session);

          session.prompt = (...args) => {
            prompts.push(args);

            return prompt(...args);
          };

          session.steer = (...args) => {
            steers.push(args);

            return steer(...args);
          };

          return session;
        },
      },
    );
  });

  test('Tab during an Enter image-file read sends only the older queue row and leaves the reading draft alone', async () => {
    const release = Promise.withResolvers<void>();
    const steers: Parameters<Session['steer']>[] = [];
    let reading = false;
    let state: AppState | undefined;

    await withWindow(
      async (window) => {
        try {
          await send(window, 'readsheld');
          await window.shows('esc to interrupt');
          await send(window, 'old queued');

          for (const key of 'new /shots/a.png done') {
            await window.press(key);
          }

          await window.press('\r');
          await until('Enter reading the image', () => reading);

          const draft = state?.draft;

          await window.press(TAB);
          await until(
            'only the older row taken',
            () => steers.length === 1 && state?.queue.length === 0,
          );
          expect(steers[0]?.slice(0, 3)).toEqual(['old queued', [], []]);
          expect(state?.draft).toBe(draft);
          release.resolve();
          await until(
            'new image prompt queued',
            () => state?.queue.length === 1,
          );
          await window.press(TAB);
          await until(
            'new image delivered',
            () => steers.length === 2 && state?.queue.length === 0,
          );
          expect(steers[1]?.slice(0, 3)).toEqual([
            'new [Image #1] done',
            [{ mediaType: 'image/png', data: PIXEL_PNG }],
            [],
          ]);
          await window.shows(RECEIVED);
          await window.press(ESC);
        } finally {
          release.resolve();
        }
      },
      {
        columns: 80,
        rows: 24,
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
        onState: (all) => {
          state = frontState(all);
        },
        readImage: async () => {
          reading = true;

          await release.promise;

          return {
            mediaType: 'image/png',
            data: PIXEL_PNG,
            bytes: PIXEL_BYTES.length,
          };
        },
        openWith: async (options) => {
          const session = await openSession(options);
          const steer = session.steer.bind(session);

          session.steer = (...args) => {
            steers.push(args);

            return steer(...args);
          };

          return session;
        },
      },
    );
  });
});

describe('CHD-476 U2 tester: main clear image ownership', () => {
  for (const columns of [80, 120]) {
    test(`main clear restores the queued bitmap and link for exactly one resend at ${columns} columns`, async () => {
      let state: AppState | undefined;
      const prompts: Parameters<Session['prompt']>[] = [];
      const text = 'main [Image #1] @a.ts done';

      await withWindow(
        async (window) => {
          await ready(window);
          await writeFile(join(window.dir, 'a.ts'), '');
          await send(window, 'costwait');
          await window.shows('Working until stopped.');

          const old = window.session()!.id;

          for (const key of 'main /shots/a.png @a.ts done') {
            await window.press(key);
          }

          await window.press('\r');
          await until(
            'main bitmap prompt queued',
            () => state?.queue.length === 1,
          );
          expect(prompts.some((args) => args[0].includes(text))).toBe(false);

          await send(window, '/clear');
          await until(
            'fresh main restores bitmap draft',
            () =>
              state?.draft === text &&
              state.connection.status === 'ready' &&
              window.session()?.id !== old,
          );
          expect(state!.images.map((image) => image.data)).toStrictEqual([
            PIXEL_PNG,
          ]);
          expect(state!.queue).toStrictEqual([]);
          await window.press('\r');
          await window.shows(RECEIVED);
          await window.shows('Received a link: a.ts');

          const delivered = prompts.filter((args) => args[0].includes(text));

          expect(delivered).toHaveLength(1);
          expect(delivered[0]!.slice(1, 3)).toStrictEqual([
            [{ mediaType: 'image/png', data: PIXEL_PNG }],
            ['a.ts'],
          ]);
          expect(state!.images).toStrictEqual([]);
        },
        {
          columns,
          rows: columns === 80 ? 24 : 40,
          onState: (all) => {
            state = frontState(all);
          },
          readImage: () =>
            Promise.resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
          openWith: async (options) => {
            const session = await openSession(options);
            const prompt = session.prompt.bind(session);

            session.prompt = (...args) => {
              prompts.push(args);

              return prompt(...args);
            };

            return session;
          },
        },
      );
    });
  }
});

describe('CHD-559 U3 tester: warm transcript code picking', () => {
  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    test(`cached blocks remain pickable after another reply at ${columns} columns`, () => {
      const { copies, copy } = clipboard();

      return withWindow(
        async (window) => {
          await send(window, 'markdowncode');
          await window.shows('A paragraph after.');
          await leader(window, 'b');
          await window.shows('another block');
          await window.press('c');
          await until('first code copy', () => copies.length === 1);

          expect(copies[0]!.text).toBe('bun dev check');
          await send(window, 'verbatim warm update');
          await window.shows('"warm update"');
          await leader(window, 'b');
          await window.shows('another block');
          await window.press('c');
          await until('cached code copy', () => copies.length === 2);

          expect(copies[1]!.text).toBe(copies[0]!.text);
          await leader(window, 'b');
          await window.shows('another block');
          await window.press(ESC);
          await until(
            'pick cancelled',
            () => !statusRow(window).includes('another block'),
          );
          expect(promptRow(window)).not.toContain('bun dev check');
        },
        { columns, rows, copy },
      );
    });
  }
});
