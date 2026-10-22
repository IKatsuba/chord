/**
 * The prompt in the window: a prompt queued during a turn and the queue in
 * order, Esc taking one back, and history.
 */
import { describe, expect, test } from 'bun:test';
import { matchFiles } from '../../../src/ui/prompt/mentions.ts';
import stripAnsi from 'strip-ansi';
import { FileList } from '../../../src/ui/prompt/Prompt.tsx';
import { draw } from '../harness.tsx';
import {
  asked,
  CTRL_G,
  CTRL_R,
  DOWN,
  ESC,
  promptRow,
  ready,
  send,
  statusRow,
  TAB,
  until,
  UP,
  withWindow,
} from '../app/render.tsx';

import { LEFT, BACKSPACE, files } from './prompt_window.tsx';

describe('CHD-480 tester: editing a search result with held controls', () => {
  for (const columns of [80, 120]) {
    test(`ctrl+r restores the cursor across control and wide cells at ${columns} columns`, () =>
      withWindow(
        async (window) => {
          await window.paste('verbatim search a\u000cb\t中c');
          await window.press('\r');
          await window.shows('"search a\\u000cb\\u0009中c"');
          await window.press(CTRL_R);
          await window.type('search');
          await window.press('\r');
          await window.press(LEFT);
          await window.type('!');
          await window.press('\r');
          await window.shows('"search a\\u000cb\\u0009中!c"');
        },
        { columns, rows: columns === 80 ? 24 : 40 },
      ));
  }
});

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

// The textarea's column counts cells, chord's cursor the string: after text
// whose cells and length differ, the cursor still lands at its end, and `\`
// before Enter still breaks the line (CHD-480).
test("the cursor lands at the end of the editor's text, and after a control character typing goes there", () =>
  withWindow(
    async (window) => {
      await window.press(CTRL_G);
      await window.shows('› verbatim a^Lb中c');
      await window.type('!');
      await window.shows('› verbatim a^Lb中c!');
      await window.press('\r');
      await window.shows('"a\\u000cb中c!"');
    },
    { editor: () => Promise.resolve({ text: 'verbatim a\u000cb中c' }) },
  ));

test('a recalled prompt with a control character, a tab and a wide character is edited at its end', () =>
  withWindow(async (window) => {
    await window.paste('verbatim a\u000cb\t中c');
    await window.press('\r');
    await window.shows('"a\\u000cb\\u0009中c"');
    await window.press(UP);
    await window.type('!');
    await window.press('\r');
    await window.shows('"a\\u000cb\\u0009中c!"');
  }));

test('\\ before Enter breaks the line after a control character', () =>
  withWindow(async (window) => {
    await window.paste('verbatim a\u000cb\\');
    await window.press('\r');
    await window.type('next');
    await window.press('\r');
    await window.shows('"a\\u000cb\\u000anext"');
  }));

// OpenTUI 0.6.6's box holds a control character, drawn as Vim does, and
// chord sends it as written (CHD-480).
test("a control character in the editor's text is held, drawn as ^L, and sent as written", () =>
  withWindow(
    async (window) => {
      await window.type('draft');
      await window.press(CTRL_G);
      await window.shows('› verbatim from^Leditor');
      await window.press('\r');
      await window.shows('"from\\u000ceditor"');
    },
    { editor: () => Promise.resolve({ text: 'verbatim from\u000ceditor' }) },
  ));

test('a pasted control character is held, and ↑ and ctrl+r bring the prompt back as written', () =>
  withWindow(async (window) => {
    await window.paste('verbatim pasted\u000cform\u007ffeed');
    await window.shows('› verbatim pasted^Lform^?feed');
    await window.press('\r');
    await window.shows('"pasted\\u000cform\\u007ffeed"');
    await window.press(UP);
    await window.shows('› verbatim pasted^Lform^?feed');
    await window.press('\r');
    await until(
      'the recalled prompt to be answered too',
      () => window.frame().split('"pasted\\u000cform\\u007ffeed"').length === 3,
    );
    await window.press(CTRL_R);
    await window.type('pasted');
    await window.shows('search prompts: pasted');
    await window.press('\r');
    await window.shows('› verbatim pasted^Lform^?feed');
    await window.press('\r');
    await until(
      'the found prompt to be answered too',
      () => window.frame().split('"pasted\\u000cform\\u007ffeed"').length === 4,
    );
  }));

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
