/**
 * The window on the fake agent: its header, a turn, its notifications, and
 * the keys that quit, clear and edit.
 */
import { describe, expect, spyOn, test } from 'bun:test';
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
  DOWN,
  ESC,
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
import { openSession } from '../../../src/session/session.ts';
import manifest from '../../../package.json' with { type: 'json' };

import { OSC9, writes } from './app_window.tsx';

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

describe('Tab sends the draft into the running turn (CHD-378)', () => {
  const UNSTEERED_NOTE =
    'This agent does not take messages into a running turn · enter queues it';

  /** `text` typed into the box, there before the next key. */
  const draft = async (window: Window, text: string) => {
    await window.type(text);
    await until(
      `"${text}" in the box`,
      () => promptRow(window)?.includes(text) ?? false,
    );
  };

  test("on an agent that steers, the box empties and the person's row is drawn in the turn, which goes on", () =>
    withWindow(
      async (window) => {
        await send(window, 'texttillsteered');
        await window.shows('esc to interrupt');
        await draft(window, 'Use the second parser instead');
        await window.press(TAB);
        await window.shows('Read the message from nobody.');

        expect(promptRow(window)).not.toContain('Use the second parser');
        expect(window.frame()).toContain('› Use the second parser instead');
      },
      {
        agentCommand: fakeAgentCommand(undefined, '--steering', 'claude'),
      },
    ));

  test('on an agent that does not, nothing goes, the draft stays, and the status line says why', () =>
    withWindow(async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await draft(window, 'Use the second parser instead');
      await window.press(TAB);
      await until('the note', () => statusRow(window).includes(UNSTEERED_NOTE));

      expect(promptRow(window)).toContain('Use the second parser instead');
      await until(
        'the note to go',
        () => !statusRow(window).includes(UNSTEERED_NOTE),
      );
      expect(promptRow(window)).toContain('Use the second parser instead');
      await window.press(ESC);
    }));

  test("one held behind Claude's open calls waits in the queue saying so, and Esc takes it back to the box", () =>
    withWindow(
      async (window) => {
        await send(window, 'bashcut');
        await window.shows('Running…');
        await draft(window, 'Skip the slow tests');
        await window.press(TAB);
        await window.shows('› after the running calls: Skip the slow tests');

        expect(promptRow(window)).not.toContain('Skip the slow tests');
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

  test('one the agent leaves unanswered shows in the queue as going into the turn, Esc leaves it, and refused it goes as the next turn', () =>
    withWindow(
      async (window) => {
        await send(window, 'slow');
        await window.shows('esc to interrupt');
        await draft(window, 'Use the second parser instead');
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
        await window.shows('esc to interrupt');
        expect(window.frame()).toContain('› Use the second parser instead');
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
});

describe('CHD-378 U3 tester: steering through the window', () => {
  const put = async (window: Window, text: string) => {
    await window.type(text);
    await until(
      'the draft to be ready',
      () => promptRow(window)?.includes(text) ?? false,
    );
  };

  for (const [columns, rows] of [
    [80, 24],
    [120, 40],
  ] as const) {
    for (const adapter of ['claude', 'codex']) {
      test(`a rebound steer leaves an Enter prompt queued and enters history on ${adapter} at ${columns} columns`, () =>
        withWindow(
          async (window) => {
            await send(window, 'slow');
            await window.shows('esc to interrupt');
            await put(window, 'Next turn only.');
            await window.press('\r');
            await window.shows('› Next turn only.');
            await put(window, 'Change the parser.');
            await window.press('\x13');
            await window.shows('Read the message from nobody.');

            expect(promptRow(window)).not.toContain('Change the parser.');
            expect(window.frame()).toContain('› Change the parser.');
            expect(window.frame()).toContain('› Next turn only.');
            expect(window.frame()).not.toContain('· steered');
            await window.press(UP);
            await until(
              'the steered prompt in history',
              () => promptRow(window)?.includes('Change the parser.') ?? false,
            );
            await window.press(CTRL_C);
            await window.press(ESC);
            await window.shows('Interrupted by user');
            await until(
              'the Enter prompt restored',
              () => promptRow(window)?.includes('Next turn only.') ?? false,
            );
          },
          {
            columns,
            rows,
            agentCommand: fakeAgentCommand(undefined, '--steering', adapter),
            keybindings: JSON.stringify({
              bindings: [
                {
                  context: 'Chat',
                  bindings: { tab: null, 'ctrl+s': 'chat:steer' },
                },
              ],
            }),
          },
        ));
    }

    test(`a call-held steer names the new permission first, then changes to in-flight before its answer at ${columns} columns`, async () => {
      const release = Promise.withResolvers<void>();

      try {
        await withWindow(
          async (window) => {
            await send(window, 'overlapask');
            await window.shows('sleep 2');
            await put(window, 'Also write the docs');
            await window.press(TAB);
            await window.shows(
              '› after the running calls: Also write the docs',
            );
            await asked(window);
            await window.shows('› after your answer: Also write the docs');

            expect(window.frame()).not.toContain('after the running calls');
            await window.press('\r');
            await window.shows('› into the running turn: Also write the docs');
            expect(promptRow(window)).not.toContain('Also write the docs');
            release.resolve();
            await until(
              'the in-flight row to leave',
              () => !window.frame().includes('into the running turn'),
            );
            await window.shows('› Also write the docs');
          },
          {
            columns,
            rows,
            agentCommand: fakeAgentCommand(
              undefined,
              '--steering',
              'claude',
              '--step-ms',
              '100',
            ),
            openWith: async (options) => {
              const session = await openSession(options);
              const steer = session.steer.bind(session);

              return Object.assign(session, {
                steer: async (text: string) => {
                  const outcome = await steer(text);

                  await release.promise;

                  return outcome;
                },
              });
            },
          },
        );
      } finally {
        release.resolve();
      }
    });
  }

  test('a no-steering warning survives typing and Esc while retaining the unsent draft', () =>
    withWindow(async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await put(window, 'Keep this');
      await window.press(TAB);
      await window.shows(
        'This agent does not take messages into a running turn',
      );
      await put(window, ' draft');

      expect(statusRow(window)).toContain('enter queues it');
      await window.press(ESC);
      await window.shows('Interrupted by user');
      expect(statusRow(window)).toContain('enter queues it');
      expect(promptRow(window)).toContain('Keep this draft');
    }));
});
