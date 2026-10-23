/**
 * The prompt's keys in the window: vim mode, other layouts, the queue's
 * headers, selection, option and cmd with the arrows, and held matches.
 */
import { describe, expect, test } from 'bun:test';
import { serveChord } from '../../../src/server/server.ts';
import {
  withChild,
  openOther,
  pickAgent,
  readyAgent,
} from '../app/child_window.tsx';
import { matchFiles } from '../../../src/ui/prompt/mentions.ts';
import stripAnsi from 'strip-ansi';
import stringWidth from 'string-width';
import { FileList, Queue } from '../../../src/ui/prompt/Prompt.tsx';
import { draw } from '../harness.tsx';
import type { EditorMode } from '../../../src/settings.ts';
import {
  CTRL_C,
  CTRL_G,
  ESC,
  promptRow,
  ready,
  send,
  TAB,
  until,
  UP,
  DOWN,
  type Window,
  withWindow,
} from '../app/render.tsx';

import { files } from './prompt_window.tsx';

test('/vim turns vim mode on, marks it under the box and keeps it', () => {
  const saved: EditorMode[] = [];

  return withWindow(
    async (window) => {
      await ready(window);
      await window.type('/vim');
      await window.press('\r');
      await window.shows('Vim mode on: Esc for normal mode, i to insert');
      await window.shows('-- INSERT --');
      expect(saved).toStrictEqual(['vim']);
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      // Typing is vim's in normal mode: i goes back to insert mode.
      await window.type('i');
      await window.shows('-- INSERT --');
      await window.type('/vim');
      await window.press('\r');
      await window.shows('Vim mode off');
      await until(
        'the mark to go',
        () => !window.frame().includes('-- INSERT'),
      );
      expect(saved).toStrictEqual(['vim', 'normal']);
    },
    {
      saveEditorMode: (mode) => {
        saved.push(mode);

        return Promise.resolve();
      },
    },
  );
});

test('in vim mode Esc goes to normal mode, and a second Esc interrupts the turn', () =>
  withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.shows('Working.');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      expect(
        !window.frame().includes('Interrupted by user'),
        'the first Esc interrupted',
      ).toBeTruthy();
      await window.press(ESC);
      await window.shows('Interrupted by user');
    },
    { vim: true },
  ));

test("a Russian layout's ctrl+о breaks the line as ctrl+j does", () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('hello');
    await window.shows('› hello');
    // The kitty keyboard protocol's ctrl+о, as a Russian layout sends it.
    await window.press('\x1b[1086;5u');
    await window.type('world');
    await until('the draft on two lines', () => {
      const lines = window.frame().split('\n');
      const first = lines.findIndex((line) => line.includes('› hello'));

      return first >= 0 && lines[first + 1]!.includes('world');
    });
  }));

test('in normal mode d i ц deletes the word, as d i w does', () =>
  withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('please text');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      await window.press('0');

      // On a Russian layout, d i w are в ш ц.
      for (const key of 'вшц') {
        await window.press(key);
      }

      await window.shows('›  text');
    },
    { vim: true },
  ));

test('a prompt edited and sent from normal mode reaches the agent', () =>
  withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('please text');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      await window.type('0');
      await window.type('dw');
      await window.shows('› text');
      await window.press('\r');
      await window.shows('This reply came in chunks.');
      // The box is empty and in insert mode again for the next prompt.
      await window.shows('-- INSERT --');
    },
    { vim: true },
  ));

describe('CHD-385 tester: incoming queue headers', () => {
  const from = {
    name: 'sssssssssssssss',
    runtime: 'fake',
    reachable: true,
  } as const;
  const text =
    'When the README section is finished, add the new flag to docs/FEATURES.md.';

  test('the 80-column cut preserves the held header and both ends of the text', async () => {
    const drawn = await draw(
      <Queue
        queue={[{ turnId: 'held', from, text, afterAnswer: true }]}
        limit={4}
      />,
      { columns: 80, rows: 24 },
    );

    try {
      const row = stripAnsi(drawn.frame()).trim();

      expect(row).toStartWith(
        '← from @sssssssssssssss · fake · after your answer: When',
      );
      expect(row).toContain('...');
      expect(row).toEndWith('FEATURES.md.');
      expect(stringWidth(row)).toBeLessThanOrEqual(78);

      await drawn.resize({ columns: 120, rows: 40 });

      expect(stripAnsi(drawn.frame())).toContain(
        '← from @sssssssssssssss · fake · after your answer: ',
      );
    } finally {
      await drawn.unmount();
    }
  });

  test('empty and multiline messages keep distinct headers beside a queued prompt', async () => {
    const drawn = await draw(
      <Queue
        queue={[
          { turnId: 'empty', from, text: '' },
          {
            turnId: 'lines',
            from: { name: 'chord' },
            text: 'first line\nsecond line',
            afterAnswer: true,
          },
          { turnId: 'person', text: 'person queued this' },
        ]}
        limit={4}
      />,
      { columns: 80, rows: 24 },
    );

    try {
      const shown = stripAnsi(drawn.frame());

      expect(shown).toContain('← from @sssssssssssssss · fake:');
      expect(shown).toContain('← from chord · after your answer: first line …');
      expect(shown).not.toContain('second line');
      expect(shown).toContain('› person queued this');
      expect(shown.split('\n')).toHaveLength(3);
    } finally {
      await drawn.unmount();
    }
  });

  test('below the header width the sender survives and the body gives way', async () => {
    const drawn = await draw(
      <Queue
        queue={[{ turnId: 'held', from, text, afterAnswer: true }]}
        limit={4}
      />,
      { columns: 32, rows: 24 },
    );

    try {
      const shown = stripAnsi(drawn.frame());

      expect(shown).toContain('← from @sssssssssssssss');
      expect(shown).not.toContain('When');
      expect(shown.split('\n')).toHaveLength(1);
      expect(stringWidth(shown)).toBeLessThanOrEqual(32);
    } finally {
      await drawn.unmount();
    }
  });
});

test('shift+← selects nothing in the draft, which only a drag selects (CHD-172)', () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('abc');
    await window.shows('› abc');
    await window.press('\x1b[1;2D');
    await window.type('x');
    // Nothing was selected for the key to replace.
    await window.shows('› abcx');
    expect(window.selected()).toStrictEqual('');
  }));

describe('option and cmd with ← and → (CHD-386)', () => {
  const CTRL_A = '\x01';
  const CTRL_E = '\x05';

  /** The box's text after `keys`, with an X typed where they left the cursor. */
  async function landed(window: Window, keys: readonly string[]) {
    await ready(window);
    await window.type('one two three');
    await window.shows('› one two three');

    for (const key of keys) {
      await window.press(key);
    }

    await window.type('X');
    await until('the X typed', () => promptRow(window)?.includes('X') === true);

    return promptRow(window);
  }

  for (const [name, keys, expected] of [
    ['option+← as CSI 1;3D', ['\x1b[1;3D'], 'one two Xthree'],
    ['option+← as ESC b', ['\x1bb'], 'one two Xthree'],
    ['option+→ as CSI 1;3C', [CTRL_A, '\x1b[1;3C'], 'one Xtwo three'],
    ['option+→ as ESC f', [CTRL_A, '\x1bf'], 'one Xtwo three'],
    ['kitty option+→ as CSI 102;3u', [CTRL_A, '\x1b[102;3u'], 'one Xtwo three'],
    ['kitty option+← as CSI 98;3u', ['\x1b[98;3u'], 'one two Xthree'],
    ['cmd+← as CSI 1;9D', ['\x1b[1;9D'], 'Xone two three'],
    ['cmd+→ as CSI 1;9C', [CTRL_A, '\x1b[1;9C'], 'one two threeX'],
    ['cmd+← as ctrl+a', [CTRL_A], 'Xone two three'],
    ['cmd+→ as ctrl+e', [CTRL_A, CTRL_E], 'one two threeX'],
  ] as const) {
    test(`${name} moves the cursor`, () =>
      withWindow(async (window) => {
        expect(await landed(window, keys)).toContain(`› ${expected}`);
      }));
  }
});

test("a keybinding on option+← takes it from the textarea's word move (CHD-386)", () =>
  withWindow(
    async (window) => {
      await ready(window);
      await window.type('one two three');
      await window.shows('› one two three');
      await window.press('\x1b[1;3D');
      await window.type('X');
      await until('the draft on two lines', () => {
        const lines = window.frame().split('\n');
        const first = lines.findIndex((line) =>
          line.includes('› one two three'),
        );

        return first >= 0 && lines[first + 1]!.includes('X');
      });
    },
    {
      keybindings: JSON.stringify({
        bindings: [
          { context: 'Chat', bindings: { 'alt+left': 'chat:newline' } },
        ],
      }),
    },
  ));

describe('CHD-386 tester: cursor move boundaries', () => {
  test('a cancelled main draft survives visiting an empty child and remains editable', () =>
    withChild(
      async (window) => {
        await openOther(window);
        await send(window, 'slow');
        await window.shows('esc to interrupt');
        await window.type('one two');
        await window.press(ESC);
        await window.shows('Interrupted by user');
        await window.press('\x1b[1;3D');
        await window.type('X');
        await window.shows('› one Xtwo');
        await pickAgent(window, 'other');
        await until('the second agent', () => window.pids.length === 2);
        await readyAgent(window);
        // Q183: keep the child empty so the existing list keys can return.
        expect(promptRow(window)).toMatch(/^│ ›\s*│$/);
        await pickAgent(window, 'main');
        await window.shows('› one Xtwo');
        await window.type('Y');
        expect(promptRow(window)).toContain('› one XYtwo');
      },
      { columns: 80, rows: 24 },
    ));

  test('cmd arrows stay on the current hard line in a multiline draft', () => {
    const drafts: string[] = [];

    return withWindow(
      async (window) => {
        await readyAgent(window);
        await window.paste('first line\nsecond line\nthird line');
        await window.press(UP);
        await window.press('\x1b[1;9D');
        await window.type('X');
        await window.press('\x1b[1;9C');
        await window.type('Y');
        await window.press(CTRL_G);
        expect(drafts).toStrictEqual(['first line\nXsecond lineY\nthird line']);
      },
      {
        columns: 80,
        rows: 24,
        editor: (draft) => {
          drafts.push(draft);

          return Promise.resolve({ text: draft });
        },
      },
    );
  });

  test('shift with alt arrows leaves selection and the cursor alone', () =>
    withWindow(async (window) => {
      await readyAgent(window);
      await window.type('one two');
      await window.press('\x1b[1;4D');
      await window.press('\x1b[1;4C');
      await window.type('X');
      await window.shows('› one twoX');
      expect(window.selected()).toStrictEqual('');
    }));

  for (const [context, action] of [
    ['Chat', 'chat:newline'],
    ['Global', 'app:toggleTranscript'],
  ] as const) {
    test(`${context} chord prefix takes alt+left before the word move`, () =>
      withWindow(
        async (window) => {
          await readyAgent(window);
          await window.type('one two');
          await window.press('\x1b[1;3D');
          // A wrong continuation drops the chord without moving the cursor.
          await window.press('z');
          await window.type('X');
          await window.shows('› one twoX');
        },
        {
          keybindings: JSON.stringify({
            bindings: [{ context, bindings: { 'alt+left q': action } }],
          }),
        },
      ));
  }

  test('a Global single binding takes cmd+left before the line move', () =>
    withWindow(
      async (window) => {
        await readyAgent(window);
        await window.type('one two');
        await window.press('\x1b[1;9D');
        await window.type('X');
        await window.shows('› one twoX');
      },
      {
        keybindings: JSON.stringify({
          bindings: [
            {
              context: 'Global',
              bindings: { 'cmd+left': 'app:toggleTranscript' },
            },
          ],
        }),
      },
    ));

  test('vim normal mode keeps its own arrow movement for modified arrows', () =>
    withWindow(
      async (window) => {
        await window.shows('-- INSERT --');
        await window.type('one two');
        await window.press(ESC);
        await window.shows('-- NORMAL --');
        await window.press('\x1b[1;3D');
        await window.press('\x1b[1;9D');
        await window.press('a');
        await window.shows('-- INSERT --');
        await window.type('X');
        // Vim names both presses Left, so these move two characters.
        await window.shows('› one tXwo');
      },
      { vim: true },
    ));

  test('cmd arrows use the wrapped visual line at 80 columns', () => {
    const drafts: string[] = [];

    return withWindow(
      async (window) => {
        await readyAgent(window);
        await window.type(`${'a'.repeat(74)} tail`);
        await window.press('\x1b[1;9D');
        await window.type('X');
        await window.press('\x1b[1;9C');
        await window.type('Y');
        await window.press(CTRL_G);
        // OpenTUI wraps before the space; it belongs to the second row.
        expect(drafts).toStrictEqual([`${'a'.repeat(74)}X tailY`]);
      },
      {
        columns: 80,
        rows: 24,
        editor: (draft) => {
          drafts.push(draft);

          return Promise.resolve({ text: draft });
        },
      },
    );
  });
});

describe('CHD-398 tester: held match lifecycle', () => {
  for (const key of ['\r', TAB]) {
    test(`${key === TAB ? 'Tab' : 'Enter'} waits after an empty previous result, then picks the new first row`, async () => {
      let emptyMatched = false;
      let release: (found: readonly string[]) => void = () => {};

      const match = (paths: readonly string[], query: string) =>
        query === 'nonex'
          ? new Promise<readonly string[]>((resolve) => {
              release = resolve;
            })
          : query === 'none'
            ? Promise.resolve([]).then((found) => {
                emptyMatched = true;

                return found;
              })
            : matchFiles(paths, query);

      await withWindow(
        async (window) => {
          await files(window, 'src/target.ts');
          await window.type('@none');
          await until(
            'the previous empty result closes its list',
            () => emptyMatched && !window.frame().includes('src/target.ts'),
          );
          await window.type('x');
          await window.press(key);
          expect(promptRow(window)).toContain('› @nonex');
          expect(window.frame()).not.toContain('⏺');
          release(['src/target.ts']);
          await until(
            'the awaited path',
            () => promptRow(window)?.includes('› @src/target.ts') ?? false,
          );
          expect(window.frame()).not.toContain('⏺');
        },
        { match },
      );
    });
  }

  test('typing changes the awaited mention and a late old result never inserts a path', async () => {
    const releases = new Map<string, (found: readonly string[]) => void>();
    const match = (paths: readonly string[], query: string) =>
      ['al', 'alp'].includes(query)
        ? new Promise<readonly string[]>((resolve) => {
            releases.set(query, resolve);
          })
        : matchFiles(paths, query);

    await withWindow(
      async (window) => {
        await files(window, 'src/alpha.ts');
        await window.type('@al');
        await until('the first held query', () => releases.has('al'));
        await window.press('\r');
        await window.type('p');
        await until('the edited held query', () => releases.has('alp'));
        releases.get('al')?.(['src/alpha.ts']);
        releases.get('alp')?.(['src/alpha.ts']);
        await window.press('');
        expect(promptRow(window)).toContain('› @alp');
        expect(promptRow(window)).not.toContain('@src/alpha.ts');
        expect(window.frame()).not.toContain('⏺');
      },
      { match },
    );
  });

  for (const action of ['switch', 'close'] as const) {
    test(`a pending pick is dropped on child ${action}, even for the same mention`, async () => {
      const releases: ((found: readonly string[]) => void)[] = [];
      const match = (paths: readonly string[], query: string) =>
        query === 'target'
          ? new Promise<readonly string[]>((resolve) => {
              releases.push(resolve);
            })
          : matchFiles(paths, query);
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
        await withChild(
          async (window) => {
            await openOther(window);
            await files(window, 'src/target.ts');
            await window.type('@target');
            await until('the main match is held', () => releases.length > 0);

            if (action === 'switch') {
              await window.press('\r');
            }

            await pickAgent(window, 'other');
            await window.type('@target');
            await until('the child match is held', () => releases.length >= 2);

            if (action === 'close') {
              await window.press(TAB);

              if (main === undefined) {
                throw new Error('main was not admitted');
              }

              // The parent's close_agent path remains reachable while the child
              // keeps a draft; Q183 adds no person-owned list key here.
              await main.window.close(main, 'other');
              await until(
                'the child closed',
                () => !/^ {4}other /m.test(window.frame()),
              );
            }

            for (const release of releases) {
              release(['src/target.ts']);
            }

            await window.press('');
            expect(promptRow(window)).toContain('› @target');
            expect(promptRow(window)).not.toContain('@src/target.ts');

            if (action === 'switch') {
              // Q183: clear the child's draft before using its empty-prompt list.
              await window.press(CTRL_C);
              await pickAgent(window, 'main');

              for (const release of releases) {
                release(['src/target.ts']);
              }

              await window.press('');
              expect(promptRow(window)).toContain('› @target');
              expect(promptRow(window)).not.toContain('@src/target.ts');
            }
          },
          { match, server },
        );
      } finally {
        await server.close();
      }
    });
  }

  test('Esc keeps a pending match dismissed when its result arrives', async () => {
    let started = false;
    let release: (found: readonly string[]) => void = () => {};

    const match = () =>
      new Promise<readonly string[]>((resolve) => {
        release = resolve;
        started = true;
      });

    await withWindow(
      async (window) => {
        await files(window, 'src/target.ts');
        await window.type('@target');
        await until('the dismissed match was started', () => started);
        await window.press(ESC);
        release(['src/target.ts']);
        await window.press('');
        expect(promptRow(window)).toContain('› @target');
        expect(window.frame()).not.toContain('  src/target.ts');
        expect(window.frame()).not.toContain('searching…');
      },
      { match },
    );
  });

  for (const count of [1, 8]) {
    test(`the pending marker keeps the last highlight visible with ${count} files`, async () => {
      const paths = Array.from(
        { length: count },
        (_, index) => `file-${index}.ts`,
      );
      const drawn = await draw(
        <FileList
          finder={{
            mention: { query: 'x', line: 0, column: 0 },
            files: paths,
            highlighted: count - 1,
            top: 0,
            pending: true,
            searching: true,
          }}
          rows={6}
        />,
        { columns: 80, rows: 10 },
      );

      try {
        const rows = stripAnsi(drawn.frame())
          .split('\n')
          .map((row) => row.trim())
          .filter(Boolean);

        expect(rows).toContain(`file-${count - 1}.ts`);
        expect(rows.at(-1)).toBe('searching…');
        expect(rows).toHaveLength(count === 1 ? 2 : 6);
      } finally {
        await drawn.unmount();
      }
    });
  }
});

for (const columns of [80, 120]) {
  test(`↓ ↓ leaves main with its draft set aside, ↑ there brings it back with its cursor, and another agent's ↑ never does (U10) at ${columns} columns`, () =>
    withChild(
      async (window) => {
        await openOther(window);
        await readyAgent(window);
        await window.type('one two');
        await window.press('\x1b[1;3D');
        await window.type('X');
        await window.shows('› one Xtwo');
        // The first ↓ sets it aside; pickAgent's ↓ from the empty box goes
        // into the list.
        await window.press(DOWN);
        await until('the box empty', () =>
          /^│ ›\s*│$/.test(promptRow(window) ?? ''),
        );
        await pickAgent(window, 'other');
        await readyAgent(window);
        await window.press(UP);
        await until('a prompt sent in its place', () =>
          (promptRow(window) ?? '').includes('agentother'),
        );
        expect(window.frame()).not.toContain('Xtwo');
        await window.press(DOWN);
        await until('the box empty again', () =>
          /^│ ›\s*│$/.test(promptRow(window) ?? ''),
        );
        await pickAgent(window, 'main');
        await until('main empty, as it was left', () =>
          /^│ ›\s*│$/.test(promptRow(window) ?? ''),
        );
        await window.press(UP);
        await window.shows('› one Xtwo');
        await window.type('Y');
        expect(promptRow(window)).toContain('› one XYtwo');
      },
      { columns, rows: 30 },
    ));
}
