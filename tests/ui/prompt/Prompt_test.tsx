import { describe, expect, test } from 'bun:test';
import { matchFiles } from '../../../src/ui/prompt/mentions.ts';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import stringWidth from 'string-width';
import { FileList, Queue } from '../../../src/ui/prompt/Prompt.tsx';
import { draw } from '../harness.tsx';
import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { ClipboardReader } from '../../../src/images.ts';
import type { EditorMode } from '../../../src/settings.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';
import {
  asked,
  CTRL_C,
  CTRL_G,
  CTRL_R,
  DOWN,
  ESC,
  leader,
  promptRow,
  quitAll,
  ready,
  send,
  statusRow,
  TAB,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

const LEFT = '\x1b[D';
const CTRL_V = '\x16';
const CTRL_W = '\x17';
const CTRL_Y = '\x19';
const CTRL_Z = '\x1a';

test('Enter during a turn queues the prompt, and the queue runs in order', () =>
  withWindow(async (window) => {
    await send(window, 'plan');
    await window.shows('esc to interrupt');
    await send(window, 'text');
    await send(window, 'thought');

    // Under the working line, and not in the transcript yet.
    const queued = window.frame();
    const working = queued.indexOf('Working…');

    expect(working >= 0, queued).toBeTruthy();
    expect(queued.indexOf('› text') > working, queued).toBeTruthy();
    expect(
      queued.indexOf('› thought') > queued.indexOf('› text'),
      queued,
    ).toBeTruthy();
    expect(!queued.includes('came in chunks'), queued).toBeTruthy();

    await window.shows('Here is the answer.');
    await until('the turn to end', () => !window.frame().includes('Working'));

    const done = window.frame();

    expect(
      done.indexOf('Step 3 done.') < done.indexOf('› text') &&
        done.indexOf('› text') < done.indexOf('came in chunks') &&
        done.indexOf('came in chunks') < done.indexOf('› thought') &&
        done.indexOf('› thought') < done.indexOf('Here is the answer.'),
      done,
    ).toBeTruthy();
  }));

test('Esc with a queue puts the queued prompts back in the box', () =>
  withWindow(async (window) => {
    await send(window, 'slow');
    await window.shows('esc to interrupt');
    await send(window, 'text');
    await send(window, 'thought');
    await window.type('half');
    await window.press(ESC);
    await window.shows('Interrupted by user');
    await until(
      'the spinner to go',
      () => !window.frame().includes('Working…'),
    );
    await window.shows('› text');
    expect(window.frame()).toContain('  thought');
    expect(window.frame()).toContain('  half');
    // Neither queued prompt ran.
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(
      !window.frame().includes('came in chunks'),
      window.frame(),
    ).toBeTruthy();
    expect(
      !window.frame().includes('Here is the answer'),
      window.frame(),
    ).toBeTruthy();
  }));

test('ctrl+g hands the draft to the editor and takes its text back', () => {
  const edited: string[] = [];

  return withWindow(
    async (window) => {
      await window.type('first line');
      await window.shows('› first line');
      await window.press(CTRL_G);
      await window.shows('appended by the editor');
      expect(edited).toStrictEqual(['first line']);
      expect(window.frame()).toContain('› first line');
      // The cursor is at the end: typing goes after the editor's line.
      await window.type(' and more');
      await window.shows('appended by the editor and more');
    },
    {
      editor: (draft) => {
        edited.push(draft);

        return Promise.resolve({ text: `${draft}\nappended by the editor` });
      },
    },
  );
});

test('ctrl+g mid-turn edits the next prompt and leaves the turn alone', () =>
  withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.type('next');
      await window.press(CTRL_G);
      await window.shows('› edited next');
      await window.shows('esc to interrupt');
    },
    { editor: (draft) => Promise.resolve({ text: `edited ${draft}` }) },
  ));

test('a failing editor leaves the draft and says so in the status line', () =>
  withWindow(
    async (window) => {
      await window.type('kept as typed');
      await window.press(CTRL_G);
      await window.shows('vi exited with code 1; the draft is unchanged');
      expect(window.frame()).toContain('› kept as typed');
      // Touching the draft again puts the message away.
      await window.type('!');
      await until(
        'the message to go',
        () => !window.frame().includes('exited with code'),
      );
      await window.shows('› kept as typed!');
    },
    {
      editor: () =>
        Promise.resolve({
          failed: 'vi exited with code 1; the draft is unchanged',
        }),
    },
  ));

test("the editor's text with a character the box cannot hold is refused, and the draft stays (CHD-323)", () =>
  withWindow(
    async (window) => {
      await window.type('keep this draft');
      await window.press(CTRL_G);
      await window.shows(
        'The prompt cannot hold U+000C from the editor; the draft is unchanged',
      );
      expect(window.frame()).toContain('› keep this draft');
      await window.type('!');
      await window.shows('› keep this draft!');
    },
    { editor: () => Promise.resolve({ text: 'bad\u000cinput' }) },
  ));

test('ctrl+g while a permission is asked opens no editor', () => {
  let opened = 0;

  return withWindow(
    async (window) => {
      await window.type('permission');
      await window.press('\r');
      await asked(window);
      await window.press(CTRL_G);
      await new Promise((resolve) => setTimeout(resolve, 100));
      expect(opened).toStrictEqual(0);
      await window.press(ESC);
    },
    {
      editor: () => {
        opened++;

        return Promise.resolve({ text: 'never' });
      },
    },
  );
});

test('\\ before Enter breaks the line, and the prompt goes as one', () =>
  withWindow(async (window) => {
    for (const line of ['one \\', 'two \\']) {
      await window.type(line);
      await window.press('\r');
    }

    await window.type('three');
    await window.shows('│   three');
    expect(
      !window.frame().includes('Working'),
      'a line was sent alone',
    ).toBeTruthy();

    const box = window
      .frame()
      .split('\n')
      .filter((line) => line.startsWith('│'));

    expect(box.length).toStrictEqual(3);
    expect(box[0]!).toContain('› one ');
    expect(
      !window.frame().includes('\\'),
      'the \\ stayed in the draft',
    ).toBeTruthy();
    await window.press('\r');
    await window.shows('came in chunks.');

    const lines = window.frame().split('\n');
    const sent = lines.findIndex((line) => line.includes('› one'));

    expect(lines[sent + 1]!).toContain('  two');
    expect(lines[sent + 2]!).toContain('  three');
  }));

test('a pasted block of lines is one prompt', () =>
  withWindow(async (window) => {
    await window.paste('a\nb\nc');
    await window.shows('│   c');
    expect(
      !window.frame().includes('Working'),
      'the paste was sent',
    ).toBeTruthy();
    await window.press('\r');
    await window.shows('came in chunks.');
    // One prompt, so one reply.
    expect(window.frame().split('came in chunks.').length).toStrictEqual(2);
  }));

test('a scrolled box marks the rows hidden above and below it (CHD-302 part 3)', () =>
  withWindow(
    async (window) => {
      const rows = Array.from({ length: 12 }, (_, at) => `row ${at + 1}`);
      const box = () =>
        window
          .frame()
          .split('\n')
          .filter((line) => line.startsWith('│'));

      await window.paste(rows.join('\n'));
      await window.shows('row 12');
      // Eight rows at 24, the cursor on the last: the start is scrolled out.
      // The marks are read from the textarea once it has drawn, a frame on.
      await until('the marks', () => box()[0]?.includes('│ ↑ row 5') ?? false);
      expect(box().length).toStrictEqual(8);
      expect(box()[7]!).toContain('│   row 12');
      expect(
        !window.frame().includes('›'),
        'a hidden prompt start is marked',
      ).toBeTruthy();

      for (const _ of rows) {
        await window.press(UP);
      }

      await until('the start', () => box()[0]?.includes('› row 1') ?? false);
      expect(box()[7]!).toContain('│ ↓ row 8');
    },
    { rows: 24 },
  ));

test('↑ and ↓ walk the prompts sent, and give the draft back', () =>
  withWindow(async (window) => {
    for (const prompt of ['first', 'second']) {
      await send(window, prompt);
      await until('the turn to end', () => !window.frame().includes('Working'));
    }

    const box = () =>
      window
        .frame()
        .split('\n')
        .find((line) => line.startsWith('│ ›'));

    await window.type('draft');
    await window.press(UP);
    await until('second', () => box()?.includes('› second') ?? false);
    await window.press(UP);
    await until('first', () => box()?.includes('› first') ?? false);
    // The oldest stays put.
    await window.press(UP);
    expect(box()!).toContain('› first');
    await window.press(DOWN);
    await until('second', () => box()?.includes('› second') ?? false);
    await window.press(DOWN);
    await until('the draft', () => box()?.includes('› draft') ?? false);
  }));

test("a / opens chord's commands and the agent's, and typing filters", () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('/');
    // The agent's arrive after the session is up, and are read again here.
    await window.shows('/echo');

    // A quarter of the window's rows: the list scrolls to the rest.
    for (const name of ['/clear', '/config', '/context', '/cost', '/exit']) {
      expect(window.frame()).toContain(name);
    }

    expect(window.frame()).toContain('Repeat what follows the command');
    expect(
      !statusRow(window).includes('? for shortcuts'),
      'the status stayed',
    ).toBeTruthy();
    await window.type('gr');
    await until('the list to filter', () => !window.frame().includes('/echo'));
    expect(window.frame()).toContain('/greet');
    expect(window.frame()).toContain('Say hello from the fake agent');
    await window.press(ESC);
    await window.shows('› /gr');
    await until('the list to close', () => !window.frame().includes('/greet'));
  }));

test("Enter on an agent's command sends it, from part of its name", () =>
  withWindow(async (window) => {
    await window.type('/');
    await window.shows('/echo');
    await window.type('gr');
    await window.press('\r');
    await window.shows('› /greet');
    await window.shows('Hello from the fake agent.');
  }));

test('↓ and Tab complete the highlighted name, and its words follow', () =>
  withWindow(async (window) => {
    await window.type('/');
    await window.shows('/echo');

    // clear, config, context, cost, echo: the fifth in the list.
    for (let step = 0; step < 4; step++) {
      await window.press(DOWN);
    }

    await window.press(TAB);
    await until(
      'the name',
      () => promptRow(window)?.includes('› /echo') ?? false,
    );
    await until('the list to close', () => !window.frame().includes('/exit'));
    await window.type('two words');
    await window.press('\r');
    await window.shows('› /echo two words');
    await window.shows('⏺ two words');
  }));

/** Makes `paths` in the window's working directory, empty. */
async function files(window: Window, ...paths: string[]) {
  for (const path of paths) {
    await mkdir(join(window.dir, path, '..'), { recursive: true });
    await writeFile(join(window.dir, path), '');
  }
}

test('an @ opens the files, typing narrows them and Tab adds one', () =>
  withWindow(async (window) => {
    await files(window, 'README.md', 'src/ui/state.ts', 'src/main.ts');
    await ready(window);
    await window.type('see @');
    await window.shows('src/ui/state.ts');
    expect(window.frame()).toContain('README.md');
    expect(
      !statusRow(window).includes('? for shortcuts'),
      'the status stayed',
    ).toBeTruthy();
    await window.type('stt');
    await until('the list to narrow', () => !window.frame().includes('README'));
    await window.press(TAB);
    await until(
      'the path',
      () => promptRow(window)?.includes('› see @src/ui/state.ts') ?? false,
    );
    await until('the list to close', () => !window.frame().includes('main.ts'));
  }));

test('Enter in the finder adds the file rather than sending', () =>
  withWindow(async (window) => {
    await files(window, 'README.md', 'src/main.ts');
    await window.type('@');
    await window.shows('src/main.ts');
    // README.md, then src/main.ts.
    await window.press(DOWN);
    await window.press('\r');
    await until(
      'the path',
      () => promptRow(window)?.includes('› @src/main.ts') ?? false,
    );
    expect(!window.frame().includes('⏺'), 'the prompt was sent').toBeTruthy();
  }));

test("Enter before a path's match is back picks the file its whole query matches, not the last list's first", () => {
  // The match for the whole path is held, so Enter comes while it runs.
  let release: (found: readonly string[]) => void = () => {};

  const held = (files: readonly string[], query: string) =>
    query === 'mentions.ts'
      ? new Promise<readonly string[]>((resolve) => {
          release = resolve;
        })
      : matchFiles(files, query);

  return withWindow(
    async (window) => {
      // docs/mentions.txt comes first for "mentions.t", and the "s" leaves it.
      await files(window, 'docs/mentions.txt', 'src/ui/prompt/mentions.ts');
      await window.type('@');
      await window.shows('docs/mentions.txt');

      for (const key of 'mentions.ts') {
        await window.type(key);
      }

      await window.press('\r');
      // Waiting: the list for "mentions.t" stays, nothing is picked yet.
      expect(promptRow(window)).toContain('› @mentions.ts');
      release(['src/ui/prompt/mentions.ts']);
      await until(
        'the path',
        () =>
          promptRow(window)?.includes('› @src/ui/prompt/mentions.ts') ?? false,
      );
      expect(!window.frame().includes('⏺'), 'the prompt was sent').toBeTruthy();
    },
    { match: held },
  );
});

test('the searching marker takes the last row, never the highlighted file, and the list never grows for it', async () => {
  const rowsOf = async (files: string[], highlighted: number) => {
    const drawn = await draw(
      <FileList
        finder={{
          mention: { query: 'x', line: 0, column: 0 },
          files,
          highlighted,
          top: 0,
          pending: true,
          searching: true,
        }}
        rows={6}
      />,
      { columns: 40, rows: 10 },
    );
    const rows = stripAnsi(drawn.frame())
      .split('\n')
      .map((row) => row.trim())
      .filter((row) => row !== '');

    await drawn.unmount();

    return rows;
  };

  const eight = Array.from({ length: 8 }, (_, at) => `file${at}.ts`);

  // The highlight on the sixth file: the list moves a row, file5 stays above.
  expect(await rowsOf(eight, 5)).toStrictEqual([
    'file1.ts',
    'file2.ts',
    'file3.ts',
    'file4.ts',
    'file5.ts',
    'searching…',
  ]);
  expect(await rowsOf(eight, 0)).toStrictEqual([
    'file0.ts',
    'file1.ts',
    'file2.ts',
    'file3.ts',
    'file4.ts',
    'searching…',
  ]);
  // A short list keeps its height: the marker takes its last row.
  expect(await rowsOf(eight.slice(0, 3), 0)).toStrictEqual([
    'file0.ts',
    'file1.ts',
    'searching…',
  ]);
  expect(await rowsOf(eight.slice(0, 3), 2)).toStrictEqual([
    'file1.ts',
    'file2.ts',
    'searching…',
  ]);
});

test('Esc puts the finder away and keeps what was typed', () =>
  withWindow(async (window) => {
    await files(window, 'README.md');
    await window.type('@REA');
    await window.shows('README.md');
    await window.press(ESC);
    await until('the list to close', () => !window.frame().includes('README'));
    expect(
      promptRow(window)?.includes('› @REA'),
      'the draft went',
    ).toBeTruthy();
  }));

test('a finder put away and brought back finds files made meanwhile', () =>
  withWindow(async (window) => {
    await files(window, 'old.ts');
    await window.type('@');
    await window.shows('old.ts');
    await window.press(ESC);
    await until('the list to close', () => !window.frame().includes('old.ts'));
    await files(window, 'new.ts');
    await window.type('new');
    await window.shows('new.ts');
  }));

const BACKSPACE = '\x7f';

test('! on an empty prompt turns to bash mode, and backspace leaves it', () =>
  withWindow(async (window) => {
    await ready(window);
    await window.type('!');
    await window.shows('! for bash mode');
    // The ! is the mode's mark in the gutter, not the command's first letter.
    expect(
      promptRow(window)?.includes('│ ! '),
      'no ! in the gutter',
    ).toBeTruthy();
    await window.type('ls');
    await window.press(BACKSPACE);
    await window.press(BACKSPACE);
    await window.shows('! for bash mode');
    await window.press(BACKSPACE);
    await ready(window);
    expect(
      promptRow(window)?.includes('│ › '),
      'still in bash mode',
    ).toBeTruthy();
  }));

test("a command's output draws, then goes to the agent with the next prompt", () =>
  withWindow(
    async (window) => {
      await window.type('!');
      await window.shows('! for bash mode');
      await window.type('echo hi; echo oops >&2; exit 3');
      await window.press('\r');
      await window.shows('Exit code 3');
      expect(window.frame()).toContain('! echo hi; echo oops >&2; exit 3');
      expect(window.frame()).toContain('⎿  hi');
      expect(window.frame()).toContain('oops');
      // As in Claude Code, the box is a prompt again once the command has run.
      await ready(window);

      await send(window, 'text');
      // The command is a code span in the reply's markdown.
      await window.shows('Received echo hi; echo oops >&2; exit 3: hi');
      await window.shows('This reply came in chunks.');
      await until('the turn to end', () => !window.frame().includes('Working'));

      // Held once: the prompt after does not carry it again.
      await send(window, 'text');
      await until('the turn to end', () => !window.frame().includes('Working'));
      expect(window.frame().split('Received').length).toStrictEqual(2);
    },
    { rows: 60 },
  ));

test('output held by a queued prompt that Esc takes back goes with it once sent', () =>
  withWindow(
    async (window) => {
      await send(window, 'slow');
      await window.shows('esc to interrupt');
      await window.type('!');
      await window.shows('! for bash mode');
      await window.type('echo held');
      await window.press('\r');
      await window.shows('⎿  held');
      await send(window, 'text');
      await window.press(ESC);
      await window.shows('Interrupted by user');
      await until(
        'the spinner to go',
        () => !window.frame().includes('Working…'),
      );
      await window.shows('› text');

      // The recalled prompt, sent again, takes the output the first never did.
      await window.press('\r');
      await window.shows('Received echo held: held');
      await window.shows('This reply came in chunks.');
      expect(window.frame().split('Received').length).toStrictEqual(2);
    },
    { rows: 60 },
  ));

test('Esc stops a long command, and ↑ brings it back in bash mode', () =>
  withWindow(async (window) => {
    await window.type('!');
    await window.shows('! for bash mode');
    await window.type('echo started; sleep 30');
    await window.press('\r');
    await window.shows('Running… (esc to stop)');
    await window.shows('started');
    await window.press(ESC);
    await window.shows('Stopped by the user');
    await window.press(UP);
    await window.shows('! for bash mode');
    expect(
      promptRow(window)?.includes('! echo started; sleep 30'),
      'the command did not come back',
    ).toBeTruthy();
  }));

test('ctrl+r finds an earlier prompt, steps older, and Enter takes it', () =>
  withWindow(async (window) => {
    for (const prompt of ['fix auth', 'text', 'explain auth']) {
      await send(window, prompt);
      await until('the turn to end', () => !window.frame().includes('Working'));
    }

    await window.type('half typed');
    await window.press(CTRL_R);
    await window.shows('search prompts:');
    // Nothing typed yet: the box still shows the draft.
    expect(
      promptRow(window)?.includes('› half typed'),
      'the draft went',
    ).toBeTruthy();
    await window.type('auth');
    await until(
      'the newest match',
      () => promptRow(window)?.includes('› explain auth') ?? false,
    );
    expect(window.frame()).toContain('search prompts: auth');
    await window.press(CTRL_R);
    await until(
      'the older match',
      () => promptRow(window)?.includes('› fix auth') ?? false,
    );
    await window.press(CTRL_R);
    await window.shows('no matching prompt: auth');
    expect(
      promptRow(window)?.includes('› fix auth'),
      'the match went',
    ).toBeTruthy();

    await window.press('\r');
    await until(
      'the search to close',
      () => !window.frame().includes('matching prompt'),
    );
    // Taken to edit, not sent: typing goes on from its end.
    await window.type(' now');
    expect(
      promptRow(window)?.includes('› fix auth now'),
      'not editable',
    ).toBeTruthy();
  }));

/**
 * Sends `before` and `auth` as one paste, searches for `auth`, and expects
 * the box's row to mark all of `auth` inverse and nothing before it.
 */
async function markedAfter(window: Window, before: string): Promise<void> {
  await window.paste(`${before}auth`);
  await window.press('\r');
  await until('the turn to end', () => !window.frame().includes('Working'));
  await window.press(CTRL_R);
  await window.type('auth');
  await window.shows('search prompts: auth');

  // The frame's escapes are written only while chalk sees colour.
  chalk.level = 3;

  const frame = (() => {
    try {
      return window.frame();
    } finally {
      chalk.level = 0;
    }
  })();
  const row = frame.split('\n').find((line) => line.includes('› '))!;

  expect(row).toContain('\x1b[7mauth\x1b[0m');
  expect(row.slice(row.indexOf('› '), row.indexOf('\x1b[7m'))).not.toContain(
    '\x1b',
  );
}

test('ctrl+r marks the query inverse after a tab, drawn as its spaces (CHD-306)', () =>
  withWindow((window) => markedAfter(window, 'say a\t')));

test('ctrl+r marks the query inverse after a decomposed accent or a joined emoji (CHD-306, CHD-319)', () =>
  withWindow(async (window) => {
    await markedAfter(window, 'say e\u0301 ');
    await window.press(ESC);
    await markedAfter(window, 'say 👩‍💻 ');
  }));

/**
 * Sends `slow`, queues `permission` and opens a search for `slow` while the
 * first turn runs, so the permission is asked with the search open.
 */
async function askedWhileSearching(window: Window): Promise<void> {
  await send(window, 'slow');
  await window.shows('esc to interrupt');
  await send(window, 'permission');
  await window.type('draft');
  await window.press(CTRL_R);
  await window.type('slow');
  await until(
    'the match',
    () => promptRow(window)?.includes('› slow') ?? false,
  );
  await asked(window);
  expect(
    !window.frame().includes('search prompts'),
    'still searching',
  ).toBeTruthy();
  expect(
    promptRow(window)?.includes('› draft'),
    'the draft did not come back',
  ).toBeTruthy();
}

test('a permission asked during a search takes Enter alone', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press('\r');
    await window.shows('Permission: allow.');
    expect(
      promptRow(window)?.includes('› draft'),
      'Enter took the match',
    ).toBeTruthy();
    expect(
      !promptRow(window)?.includes('slow'),
      'Enter took the match',
    ).toBeTruthy();
  }));

test('a number key answers a permission asked during a search', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press('2');
    await window.shows('Permission: always.');
    expect(
      promptRow(window)?.includes('› draft'),
      'the draft went',
    ).toBeTruthy();
    expect(!window.frame().includes('draft2'), 'typed into it').toBeTruthy();
  }));

test('Esc on a permission asked during a search rejects it, nothing more', () =>
  withWindow(async (window) => {
    await askedWhileSearching(window);
    await window.press(ESC);
    await window.shows('Permission: deny.');
    expect(
      !window.frame().includes('Interrupted'),
      'Esc interrupted the turn',
    ).toBeTruthy();
    // The draft takes keys again, from its end.
    await window.type('!');
    expect(
      promptRow(window)?.includes('› draft!'),
      'the draft took no keys',
    ).toBeTruthy();
  }));

test('Esc leaves a search with the draft as it was', () =>
  withWindow(async (window) => {
    await send(window, 'text');
    await until('the turn to end', () => !window.frame().includes('Working'));
    await window.type('draft');
    await window.press(CTRL_R);
    await window.type('tex');
    await until(
      'the match',
      () => promptRow(window)?.includes('› text') ?? false,
    );
    await window.press(ESC);
    await until(
      'the draft',
      () => promptRow(window)?.includes('› draft') ?? false,
    );
    expect(
      !window.frame().includes('search prompts'),
      'still searching',
    ).toBeTruthy();
    // The draft takes keys again, from where its cursor was.
    await window.type('!');
    expect(
      promptRow(window)?.includes('› draft!'),
      'the draft took no keys',
    ).toBeTruthy();
  }));

test('a command found by ctrl+r comes back in bash mode', () =>
  withWindow(async (window) => {
    await window.type('!');
    await window.shows('! for bash mode');
    await window.type('echo found');
    await window.press('\r');
    await window.shows('⎿  found');
    await ready(window);
    await window.press(CTRL_R);
    await window.type('found');
    await until(
      'the command',
      () => promptRow(window)?.includes('! echo found') ?? false,
    );
    await window.press(TAB);
    await window.shows('! for bash mode');
    expect(
      promptRow(window)?.includes('! echo found'),
      'not in bash mode',
    ).toBeTruthy();
  }));

/** A clipboard holding the one-pixel PNG, counting its reads. */
function pixelClipboard(): ClipboardReader & { reads: number } {
  const read = Object.assign(
    () => {
      read.reads++;

      return Promise.resolve({
        image: {
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        },
      });
    },
    { reads: 0 },
  );

  return read;
}

/** Waits for the session to be up, so the agent has said what it takes. */
async function connected(window: Window): Promise<void> {
  await until(
    'the session to start',
    () => !window.frame().includes('Starting'),
  );
}

const RECEIVED = `Received an image: image/png, ${PIXEL_BYTES.length} bytes`;

test('ctrl+v puts the clipboard image in the prompt and sends it with the text', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('ctrl+v on an empty clipboard says so in the status line', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('No image in the clipboard');
      expect(!window.frame().includes('[Image #')).toBeTruthy();
      await window.type('x');
      await until(
        'the message to go',
        () => !window.frame().includes('No image in the clipboard'),
      );
    },
    {
      clipboard: () => Promise.resolve({ failed: 'No image in the clipboard' }),
    },
  ));

test('ctrl+v says when the agent takes no images, and reads nothing', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('fake does not take images');
      expect(clipboard.reads).toStrictEqual(0);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

/** A clipboard holding no image, counting its reads. */
function emptyClipboard(): ClipboardReader & { reads: number } {
  const read = Object.assign(
    () => {
      read.reads++;

      return Promise.resolve({ failed: 'No image in the clipboard' });
    },
    { reads: 0 },
  );

  return read;
}

test('an empty bracketed paste puts the clipboard image at the cursor', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      // cmd+V of an image-only clipboard, as Ghostty sends it.
      await window.paste('');
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('an empty bracketed paste cut across two reads is still one', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('\x1b[200~\x1b[2');
      await window.type('01~');
      await window.shows('› [Image #1]');
    },
    { clipboard: pixelClipboard() },
  ));

test('an empty bracketed paste of an empty clipboard changes nothing and says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.type('keep');
      await window.shows('› keep');

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
      // The draft and its cursor are as they were.
      await window.type('s');
      await window.shows('› keeps');
    },
    { clipboard },
  );
});

test('an empty bracketed paste says when the agent takes no images, only of an image', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste('');
      await window.shows('fake does not take images');
      expect(clipboard.reads).toStrictEqual(1);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

test('an empty bracketed paste of nothing to an agent that takes no images says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await connected(window);

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
    },
    {
      clipboard,
      agentCommand: fakeAgentCommand(undefined, '--no-images'),
    },
  );
});

test('a bracketed paste of text is the text, and reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste('hello there');
      await window.shows('› hello there');
      expect(!window.frame().includes('[Image #'), window.frame()).toBeTruthy();
      expect(clipboard.reads).toStrictEqual(0);
    },
    { clipboard },
  );
});

test('a bracketed paste of an image path goes in as the image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.paste("'/shots/my shot.png' ");
      await window.shows('› [Image #1]');
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

test('in normal mode an empty bracketed paste puts the image at the cursor, as ctrl+v does', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      await window.paste('');
      await window.shows('› kee [Image #1] p');
      expect(clipboard.reads).toStrictEqual(1);
      await window.press(CTRL_V);
      await until('the second read', () => clipboard.reads === 2);
      await window.shows('[Image #2]');
    },
    { clipboard, vim: true },
  );
});

test('in normal mode an empty bracketed paste of an empty clipboard changes nothing and says nothing', () => {
  const clipboard = emptyClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');

      const before = window.frame();

      await window.paste('');
      await until('the clipboard read', () => clipboard.reads === 1);
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(window.frame()).toStrictEqual(before);
    },
    { clipboard, vim: true },
  );
});

test('in normal mode a bracketed paste of text reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await window.shows('-- INSERT --');
      await window.type('keep');
      await window.press(ESC);
      await window.shows('-- NORMAL --');
      // Dropped: Ink ran it as normal mode's keys, so a pasted x deleted.
      await window.paste('x');
      await new Promise((resolve) => setTimeout(resolve, 200));

      const draft = window
        .frame()
        .split('\n')
        .find((line) => line.includes('› '));

      expect(draft?.replace(/│/g, '').trim()).toStrictEqual('› keep');
      expect(clipboard.reads).toStrictEqual(0);
    },
    { clipboard, vim: true },
  );
});

test('an empty bracketed paste on the search line reads no clipboard', () => {
  const clipboard = pixelClipboard();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_R);
      await window.shows('search prompts:');
      await window.paste('');
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(clipboard.reads).toStrictEqual(0);
      expect(!window.frame().includes('[Image #'), window.frame()).toBeTruthy();
    },
    { clipboard },
  );
});

test('deleting the placeholder sends the prompt without its image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.shows('› [Image #1]');
      await window.press(CTRL_C);
      await send(window, 'text');
      await window.shows('came in chunks');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test('backspace after a placeholder takes it whole, image and all', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await window.shows('› what is [Image #1]');
      await window.type('this?');
      await window.shows('› what is [Image #1] this?');

      // Back past ` this?`, to just after the `]`.
      for (let step = 0; step < 6; step++) {
        await window.press(LEFT);
      }

      await window.press(BACKSPACE);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image #'),
      );
      // The cursor is where the placeholder was, not where the textarea left it.
      await window.type('x');
      await window.press('\r');
      await window.shows('› what is x this?');
      await window.shows('came in chunks');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test('a pasted path to an image file goes in as the image', () => {
  const asked: string[] = [];

  return withWindow(
    async (window) => {
      await connected(window);
      // One write, as a terminal pastes a dropped file.
      await window.type("'/shots/my shot.png' ");
      await window.shows('› [Image #1]');
      expect(asked).toStrictEqual(['/shots/my shot.png']);
      await window.type('see');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    {
      readImage: (path) => {
        asked.push(path);

        return Promise.resolve({
          mediaType: 'image/png',
          data: PIXEL_PNG,
          bytes: PIXEL_BYTES.length,
        });
      },
    },
  );
});

test('a typed path to an image file goes as the image when sent', () =>
  withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.shows('› see /shots/a.png');
      await window.press('\r');
      await window.shows('› see [Image #1]');
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

/** A file reader that holds each read until the test lets it go. */
function heldReader() {
  const waiting: (() => void)[] = [];

  return {
    waiting,
    readImage: () =>
      new Promise<{ mediaType: string; data: string; bytes: number }>(
        (resolve) =>
          waiting.push(() =>
            resolve({
              mediaType: 'image/png',
              data: PIXEL_PNG,
              bytes: PIXEL_BYTES.length,
            }),
          ),
      ),
  };
}

test('a draft typed while a typed path is read stays once the prompt goes', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await until('the read', () => reader.waiting.length === 1);
      await window.type(' next');
      reader.waiting[0]?.();
      await window.shows('› see [Image #1]');
      await window.shows(RECEIVED);
      await window.shows('› see /shots/a.png next');
    },
    { readImage: reader.readImage },
  );
});

test('Enter again while a typed path is read sends the prompt once', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await window.press('\r');
      await until('the read', () => reader.waiting.length > 0);
      reader.waiting.forEach((release) => release());
      await window.shows(RECEIVED);
      await until('the turn to end', () => !window.frame().includes('Working'));
      expect(reader.waiting.length).toStrictEqual(1);
      expect(window.frame().split(RECEIVED).length).toStrictEqual(2);
    },
    { readImage: reader.readImage },
  );
});

test('a typed path read while another tab comes forward goes from its own tab', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);

      for (const key of 'see /shots/a.png') {
        await window.press(key);
      }

      await window.press('\r');
      await until('the read', () => reader.waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      reader.waiting[0]?.();
      await leader(window, '1');
      await window.shows('› see [Image #1]');
      await window.shows(RECEIVED);
      expect(
        !window.frame().includes('see /shots/a.png'),
        'the draft stayed',
      ).toBeTruthy();
      await leader(window, '2');
      await until('the second tab', () => !window.frame().includes(RECEIVED));
      expect(
        !window.frame().includes('[Image #1]'),
        'the image went to tab 2',
      ).toBeTruthy();
      await quitAll(window);
    },
    { columns: 120, rows: 40, readImage: reader.readImage },
  );
});

test('a clipboard image read while another tab comes forward goes into its own draft', () => {
  const waiting: (() => void)[] = [];
  const clipboard: ClipboardReader = () =>
    new Promise((resolve) =>
      waiting.push(() =>
        resolve({
          image: {
            mediaType: 'image/png',
            data: PIXEL_PNG,
            bytes: PIXEL_BYTES.length,
          },
        }),
      ),
    );

  return withWindow(
    async (window) => {
      await connected(window);
      await window.type('what is');
      await window.press(CTRL_V);
      await until('the read', () => waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      waiting[0]?.();
      await leader(window, '1');
      await window.shows('› what is [Image #1]');
      await leader(window, '2');
      await until('the second tab', () => !window.frame().includes('what is'));
      expect(
        !window.frame().includes('[Image #1]'),
        'the image went to tab 2',
      ).toBeTruthy();
      await quitAll(window);
    },
    { columns: 120, rows: 40, clipboard },
  );
});

test('a pasted image path read while another tab comes forward goes into its own draft (CHD-128)', () => {
  const reader = heldReader();

  return withWindow(
    async (window) => {
      await connected(window);
      await window.paste("'/shots/a.png'");
      await until('the read', () => reader.waiting.length === 1);
      await leader(window, 'c');
      await until('the second agent', () => window.pids.length === 2);
      await ready(window);
      await window.type('tab two draft');
      await window.shows('› tab two draft');
      reader.waiting[0]?.();
      // The finish has no mark of its own on tab 2; a pause lets it land.
      await new Promise((resolve) => setTimeout(resolve, 200));
      expect(promptRow(window)).toContain('› tab two draft');
      expect(window.frame()).not.toContain('[Image #');
      await leader(window, '1');
      await window.shows('› [Image #1]');
      expect(window.frame()).not.toContain('/shots/a.png');
      await window.press('\r');
      await window.shows(RECEIVED);
      await leader(window, '2');
      await window.shows('› tab two draft');
      expect(window.frame()).not.toContain('Received an image');
      expect(window.frame()).not.toContain('[Image #');
      // A draft left in the box would take ctrl+d as a key, not a quit.
      await window.press(CTRL_C);
      await until(
        'the draft to clear',
        () => !window.frame().includes('tab two draft'),
      );
      await quitAll(window);
    },
    { columns: 120, rows: 40, readImage: reader.readImage },
  );
});

test('a recalled prompt sends its image again', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.press(CTRL_V);
      await window.type('once');
      await window.press('\r');
      await window.shows(RECEIVED);
      await until('the turn to end', () => !window.frame().includes('Working'));
      await window.press(UP);
      await window.shows('› [Image #1] once');
      await window.press('\r');
      await until(
        'the second acknowledgement',
        () => window.frame().split(RECEIVED).length > 2,
      );
    },
    { clipboard: pixelClipboard() },
  ));

test('an interrupt gives a queued prompt back with its image', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await send(window, 'slow');
      await window.press(CTRL_V);
      await window.type('later');
      await window.press('\r');
      await window.shows('[Image #1] later');
      await window.press(ESC);
      await window.shows('› [Image #1] later');
      await until(
        'the turn to end',
        () => !window.frame().includes('Interrupting'),
      );
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

test('ctrl+w straight after a paste takes the placeholder whole (CHD-302 part 3)', () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('cut');
      await window.press(CTRL_V);
      await window.shows('› cut [Image #1]');
      // The paste's own trailing space is in the word ctrl+w takes.
      await window.press(CTRL_W);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image'),
      );
      await window.type('x');
      await window.press('\r');
      await window.shows('› cut x');
      expect(!window.frame().includes('Received an image')).toBeTruthy();
    },
    { clipboard: pixelClipboard() },
  ));

test("the placeholder ctrl+w took is the textarea's to undo and redo, and comes back with its image", () =>
  withWindow(
    async (window) => {
      await connected(window);
      await window.type('cut');
      await window.press(CTRL_V);
      await window.shows('› cut [Image #1]');
      await window.press(CTRL_W);
      await until(
        'the placeholder to go',
        () => !window.frame().includes('Image'),
      );
      await window.press(CTRL_Z);
      await window.shows('› cut [Image #1]');
      await window.press(CTRL_Y);
      await until(
        'the placeholder to go again',
        () => !window.frame().includes('Image'),
      );
      await window.press(CTRL_Z);
      await window.shows('› cut [Image #1]');
      await window.press('\r');
      await window.shows(RECEIVED);
    },
    { clipboard: pixelClipboard() },
  ));

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
  test('a cancelled turn and another session keep independent editable drafts', () =>
    withWindow(
      async (window) => {
        await send(window, 'slow');
        await window.shows('esc to interrupt');
        await window.type('one two');
        await window.press(ESC);
        await window.shows('Interrupted by user');
        await window.press('\x1b[1;3D');
        await window.type('X');
        await window.shows('› one Xtwo');
        await leader(window, 'c');
        await until('the second agent', () => window.pids.length === 2);
        await ready(window);
        await window.type('other draft');
        await window.press('\x1b[1;9D');
        await window.type('Y');
        await window.shows('› Yother draft');
        await leader(window, '1');
        await window.shows('› one Xtwo');
        await leader(window, '2');
        await window.shows('› Yother draft');
      },
      { columns: 80, rows: 24 },
    ));

  test('cmd arrows stay on the current hard line in a multiline draft', () => {
    const drafts: string[] = [];

    return withWindow(
      async (window) => {
        await ready(window);
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
      await ready(window);
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
          await ready(window);
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
        await ready(window);
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
        await ready(window);
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
