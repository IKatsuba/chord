import { expect, test } from 'bun:test';
import { CHORD_WAIT_MS } from '../../../src/ui/shortcuts/bindings.ts';
import { SHORTCUTS } from '../../../src/ui/shortcuts/keys.ts';
import {
  CTRL_G,
  CTRL_R,
  ESC,
  promptRow,
  ready,
  statusRow,
  until,
  withWindow,
} from '../app/render.tsx';

test('? on an empty prompt opens the shortcuts, esc and ? close them', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('?');
      await window.shows('ctrl + o for verbose output');

      const frame = window.frame();

      for (const { key, does } of SHORTCUTS) {
        expect(frame).toContain(`${key} ${does}`);
      }

      expect(!frame.includes('› ?'), 'the ? went into the draft').toBeTruthy();
      await window.press(ESC);
      await until(
        'the panel to close',
        () => !window.frame().includes('ctrl + o'),
      );
      await window.type('?');
      await window.shows('ctrl + o');
      await window.type('?');
      await until(
        'the panel to close',
        () => !window.frame().includes('ctrl + o'),
      );
      expect(
        !window.frame().includes('› ?'),
        'the ? went into the draft',
      ).toBeTruthy();
    },
    // Tall enough for the whole panel; a short window scrolls it, below.
    { rows: 40 },
  ));

const PAGE_UP = '\x1b[5~';
const PAGE_DOWN = '\x1b[6~';
const HOME = '\x1b[H';
const END = '\x1b[F';
const SHIFT_DOWN = '\x1b[1;2B';
/** An SGR wheel report, `up` or down, at the 0-based cell `x`, `y`. */
const wheel = (x: number, y: number, up: boolean) =>
  `\x1b[<${up ? 64 : 65};${x + 1};${y + 1}M`;
const BELOW = '── ↓ 2 lines below · pagedown to scroll ──';
const ABOVE = '── ↑ 2 lines above · pageup to scroll ──';
const LAST = 'tab enter to add a file';

test("at 80x24 the panel shows what fits, a rule saying what is below, and every scroll key reaches the rest (CHD-378, the owner's Q217)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('?');
      await window.shows(BELOW);

      // The rule takes the last row; the panel's last entry is past it.
      expect(window.frame().split('\n').at(-1)).toContain(BELOW);
      expect(window.frame()).not.toContain(LAST);

      const seen = new Set(
        SHORTCUTS.filter(({ key, does }) =>
          window.frame().includes(`${key} ${does}`),
        ),
      );

      await window.press(PAGE_DOWN);
      await window.shows(ABOVE);
      expect(window.frame()).toContain(LAST);
      expect(window.frame()).not.toContain(BELOW);

      for (const shortcut of SHORTCUTS) {
        if (window.frame().includes(`${shortcut.key} ${shortcut.does}`)) {
          seen.add(shortcut);
        }
      }

      // Between the two ends, both rules, each with its own count.
      expect(seen.size).toStrictEqual(SHORTCUTS.length);
      await window.press(HOME);
      await window.shows(BELOW);
      await window.press(SHIFT_DOWN);
      await window.shows('── ↑ 1 line above · pageup to scroll ──');
      // The rule above takes a row of the room too.
      expect(window.frame()).toContain(BELOW);
      await window.press(END);
      await window.shows(ABOVE);
      await window.press(PAGE_UP);
      await window.shows(BELOW);
      expect(window.frame()).not.toContain('lines above');
    },
    { columns: 80, rows: 24 },
  ));

test('the wheel over the panel scrolls it, and it opens again at the top', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('?');
      await window.shows(BELOW);
      await window.press(wheel(10, 10, false));
      await window.press(wheel(10, 10, false));
      await window.shows(ABOVE);
      await window.press(ESC);
      await until('the panel to close', () => !window.frame().includes(ABOVE));
      await window.type('?');
      await window.shows(BELOW);
      expect(window.frame()).not.toContain('lines above');
    },
    { columns: 80, rows: 24 },
  ));

test('a panel that fits has no rule', () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('?');
      await window.shows(LAST);
      expect(window.frame()).not.toContain('to scroll ──');
    },
    { columns: 120, rows: 40 },
  ));

test('? anywhere but an empty prompt is text', () =>
  withWindow(async (window) => {
    await ready(window);

    // A key at a time, as a person types, so the ? arrives on its own.
    for (const key of 'why?') {
      await window.type(key);
    }

    await window.shows('› why?');
    expect(
      !window.frame().includes('ctrl + o'),
      'the panel opened',
    ).toBeTruthy();
  }));

/**
 * On "Russian – PC", as a terminal reporting every key sends it: the key
 * where a US layout has `/` types `.`, and with shift `,`, where US has `?`.
 */
const RUSSIAN_QUESTION = '\x1b[46:44:47;2;44u';

test('the key of ? opens the shortcuts on any layout, and is text after a draft', () =>
  withWindow(async (window) => {
    await ready(window);
    await window.press(RUSSIAN_QUESTION);
    await window.shows('ctrl + o for verbose output');
    expect(
      !window.frame().includes('› ,'),
      'the , went into the draft',
    ).toBeTruthy();
    await window.press(ESC);
    await until(
      'the panel to close',
      () => !window.frame().includes('ctrl + o'),
    );

    // ч, as the same terminal sends it, then the key of ? types its comma.
    await window.press('\x1b[1095::120;1;1095u');
    await window.press(RUSSIAN_QUESTION);
    await window.shows('› ч,');
    expect(
      !window.frame().includes('ctrl + o'),
      'the panel opened',
    ).toBeTruthy();
  }));

test('typing with the shortcuts open puts them away', () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('?');
    await window.shows('ctrl + o');
    await window.type('a');
    await window.shows('› a');
    expect(
      !window.frame().includes('ctrl + o'),
      'the panel stayed',
    ).toBeTruthy();
  }));

test('the header and the status line name the key help is rebound to', () =>
  withWindow(
    async (window) => {
      await until('the rebound hint on the status line', () =>
        statusRow(window).includes('h for shortcuts'),
      );
      expect(window.frame()).toContain('h for shortcuts · /help');
      expect(
        !window.frame().includes('?'),
        'the unbound ? is still named',
      ).toBeTruthy();
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Chat',
            bindings: { '?': null, h: 'help:toggle' },
          },
        ],
      }),
    },
  ));

test('with help unbound the header says /help alone', () =>
  withWindow(
    async (window) => {
      await window.shows('/help');
      await until('the session up', () => statusRow(window).includes('Fake'));
      expect(
        !window.frame().includes('for shortcuts'),
        'a dead key is named',
      ).toBeTruthy();
    },
    {
      keybindings: JSON.stringify({
        bindings: [{ context: 'Chat', bindings: { '?': null } }],
      }),
    },
  ));

/** A keybindings file that sends on ctrl+s and edits on ctrl+e. */
const REBOUND = JSON.stringify({
  bindings: [
    {
      context: 'Chat',
      bindings: {
        enter: null,
        'ctrl+s': 'chat:submit',
        'ctrl+g': null,
        'ctrl+e': 'chat:externalEditor',
      },
    },
  ],
});

const CTRL_S = '\x13';

test('a prompt goes on the send key the keybindings file binds, not Enter', () =>
  withWindow(
    async (window) => {
      await window.type('text');
      await window.shows('› text');
      await window.press('\r');
      await new Promise((resolve) => setTimeout(resolve, 300));
      expect(
        !window.frame().includes('Hello, world'),
        'Enter still sends',
      ).toBeTruthy();
      await window.press(CTRL_S);
      await window.shows('Hello, world. This reply came in chunks.');
    },
    { keybindings: REBOUND },
  ));

test('the shortcuts panel names the keys the file binds', () =>
  withWindow(
    async (window) => {
      await window.type('?');
      await window.shows('ctrl + s to send');
      expect(window.frame()).toContain('ctrl + e to edit in $EDITOR');
      expect(
        !window.frame().includes('ctrl + g'),
        'the old key is still named',
      ).toBeTruthy();
    },
    { keybindings: REBOUND },
  ));

test('Enter bound to a newline breaks the line, and a chord opens the editor', () => {
  const edited: string[] = [];

  return withWindow(
    async (window) => {
      await window.type('one');
      await window.press('\r');
      await window.type('two');
      await window.shows('  two');
      expect(window.frame()).toContain('› one');
      await window.press('\x18');
      await window.shows('ctrl+x …');
      await window.press('\x0b');
      await window.shows('from the editor');
      expect(edited).toStrictEqual(['one\ntwo']);
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Chat',
            bindings: {
              enter: 'chat:newline',
              'ctrl+s': 'chat:submit',
              'ctrl+x ctrl+k': 'chat:externalEditor',
            },
          },
        ],
      }),
      editor: (draft) => {
        edited.push(draft);

        return Promise.resolve({ text: 'from the editor' });
      },
    },
  );
});

test('ctrl+j unbound breaks no line, and bound to send it sends', async () => {
  const edited: string[] = [];

  await withWindow(
    async (window) => {
      await window.type('abcd');
      await window.shows('› abcd');
      await window.press('\n');
      await window.press(CTRL_G);
      await window.shows('from the editor');
      expect(edited).toStrictEqual(['abcd']);
    },
    {
      keybindings: JSON.stringify({
        bindings: [{ context: 'Chat', bindings: { 'ctrl+j': null } }],
      }),
      editor: (draft) => {
        edited.push(draft);

        return Promise.resolve({ text: 'from the editor' });
      },
    },
  );

  await withWindow(
    async (window) => {
      // A paste keeps its line breaks whatever ctrl+j is.
      await window.paste('one\ntwo');
      await window.shows('  two');
      expect(window.frame()).toContain('› one');
      await window.press('\n');
      await window.shows('Hello, world. This reply came in chunks.');
    },
    {
      keybindings: JSON.stringify({
        bindings: [{ context: 'Chat', bindings: { 'ctrl+j': 'chat:submit' } }],
      }),
    },
  );
});

test("a chord's first key leaves the draft as it was", () => {
  const edited: string[] = [];

  return withWindow(
    async (window) => {
      await window.type('abcd');
      await window.shows('› abcd');
      await window.press('\x01');
      await window.press('\x0b');
      await window.shows('ctrl+k …');
      await window.press('\x05');
      await until('the editor to open', () => edited.length === 1);
      expect(edited).toStrictEqual(['abcd']);
      await window.shows('› abcd');
      // Left to time out, the first key still cuts nothing.
      await window.press('\x01');
      await window.press('\x0b');
      await window.shows('ctrl+k …');
      await until(
        'the chord to time out',
        () => !window.frame().includes('ctrl+k …'),
        CHORD_WAIT_MS + 2000,
      );
      // ctrl+e alone is the box's end of line again.
      await window.press('\x05');
      await window.shows('› abcd');
      expect(edited).toStrictEqual(['abcd']);
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Chat',
            bindings: { 'ctrl+k ctrl+e': 'chat:externalEditor' },
          },
        ],
      }),
      editor: (draft) => {
        edited.push(draft);

        return Promise.resolve({ text: draft });
      },
    },
  );
});

test("an open list's chord leaves the draft as it was, and a closed one's key edits", () => {
  const edited: string[] = [];

  return withWindow(
    async (window) => {
      await window.type('/mod');
      await window.shows('/model');
      // Left to time out, the first key cuts nothing while the list is open.
      // The list stands where the status line would say a key is waited for.
      await window.press('\x01');
      await window.press('\x0b');
      await new Promise((resolve) => setTimeout(resolve, CHORD_WAIT_MS + 500));
      // The cursor, drawn on the `/`, splits the row's text.
      expect(promptRow(window)!).toContain('mod');
      await window.shows('/model');
      await window.press('\x01');
      await window.press('\x0b');
      await window.press('\x05');
      await until(
        'the list to close',
        () => !window.frame().includes("Switch the agent's model"),
      );
      await window.press(CTRL_G);
      await until('the editor to open', () => edited.length === 1);
      expect(edited).toStrictEqual(['/mod']);
      // With no list open, ctrl+k is the box's: it cuts the line.
      await window.press('\x03');
      await window.type('abcd');
      await window.shows('› abcd');
      await window.press('\x01');
      await window.press('\x0b');
      await until(
        'the line to be cut',
        () => !(promptRow(window)?.includes('abcd') ?? true),
      );
      expect(
        !window.frame().includes('ctrl+k …'),
        'the box waited',
      ).toBeTruthy();
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Autocomplete',
            bindings: { 'ctrl+k ctrl+e': 'autocomplete:dismiss' },
          },
        ],
      }),
      editor: (draft) => {
        edited.push(draft);

        return Promise.resolve({ text: draft });
      },
    },
  );
});

test('the search line types past a chord it could not finish', () =>
  withWindow(
    async (window) => {
      await window.press(CTRL_R);
      await window.shows('search prompts:');
      await window.press('\x0b');
      await window.type('a');
      await window.shows('no matching prompt: a');
      expect(
        !window.frame().includes('ctrl+k …'),
        'the search waited',
      ).toBeTruthy();
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Chat',
            bindings: { 'ctrl+k ctrl+e': 'chat:externalEditor' },
          },
        ],
      }),
    },
  ));

test("a keybindings file's problem is said in the status line, and the rest applies", () =>
  withWindow(
    async (window) => {
      await window.shows(
        'keybindings.json: ctrl+o already bound to app:toggleTranscript, not to chat:externalEditor',
      );
      await window.type('text');
      await until(
        'the problem to go once the draft is touched',
        () => !window.frame().includes('keybindings.json'),
      );
      await window.press(CTRL_S);
      await window.shows('Hello, world. This reply came in chunks.');
    },
    {
      columns: 120,
      keybindings: JSON.stringify({
        bindings: [
          {
            context: 'Chat',
            bindings: {
              'ctrl+o': 'chat:externalEditor',
              'ctrl+s': 'chat:submit',
            },
          },
        ],
      }),
    },
  ));
