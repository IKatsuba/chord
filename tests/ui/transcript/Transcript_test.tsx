import { expect, test } from 'bun:test';
import chalk from 'chalk';
import stripAnsi from 'strip-ansi';
import { COMPACT_ERROR } from '../../fixtures/compactions.ts';
import {
  CTRL_O,
  DOWN,
  END,
  leader,
  left,
  ready,
  send,
  until,
  UP,
  type Window,
  withWindow,
} from '../app/render.tsx';

const SHIFT_UP = '\x1b[1;2A';
const PAGE_UP = '\x1b[5~';
const HOME = '\x1b[H';

test('Enter sends the prompt and the reply streams in', () =>
  withWindow(async (window) => {
    await send(window, 'text');
    // Every frame drawn, not the last: the reply can stream in and end
    // between two of the test's looks.
    await until('"Working…" drawn', () =>
      window.written().some((frame) => frame.includes('Working…')),
    );
    await window.shows('Hello, world. This reply came in chunks.');
    await until('the spinner to go', () => !window.frame().includes('Working'));
    // The prompt is empty again and takes the next one.
    await send(window, 'thought');
    await window.shows('Here is the answer.');
  }));

test('a reply draws as markdown, not as its marks', () =>
  withWindow(
    async (window) => {
      await send(window, 'markdown');
      // Mid-stream, inside the open code fence, the code is already a block.
      await window.shows(
        "│ const session = await openSession({ agent: 'claude', cwd }); │",
      );
      expect(window.frame()).toContain('Working…');
      // Inside the open fence in the list, the code is a box under its item.
      await window.shows('  │ deno task check │');
      expect(window.frame()).toContain('Working…');
      await window.shows('│ deno task compile --all');

      const frame = window.frame();

      for (const mark of ['**', '# ', '```', '| ---']) {
        expect(!frame.includes(mark), `"${mark}" is on screen`).toBeTruthy();
      }

      expect(frame).toContain('│ A closed agent counts as gone');
      expect(frame).toContain('│ │ await session.close();');
      expect(frame).toContain('│ Module        │ Holds');
      expect(frame).toContain('- starts turns with startTurn and cancels');
    },
    { rows: 54 },
  ));

test('a transcript taller than the window keeps its newest lines', () =>
  withWindow(
    async (window) => {
      // Any prompt that is not a scenario name plays the text reply.
      for (let turn = 1; turn <= 8; turn++) {
        await send(window, `turn ${turn}`);
        await until(`reply ${turn}`, () => {
          const frame = window.frame();
          const prompt = frame.indexOf(`› turn ${turn}`);

          return (
            frame.indexOf('came in chunks.', prompt) > prompt &&
            !frame.includes('Working')
          );
        });
      }

      const lines = window.frame().split('\n');
      const top = lines.findIndex((line) => line.startsWith('╭'));

      expect(lines.length).toStrictEqual(24);
      // The header has scrolled away with nothing left above the transcript.
      expect(
        !window.frame().includes('chord v'),
        'the header stayed',
      ).toBeTruthy();
      expect(lines[0]!).toContain('› turn 4');
      // The newest reply sits one blank row above the prompt box.
      expect(lines[top - 2]!).toContain('⏺ Hello, world.');
      expect(lines[top - 1]!.trim()).toStrictEqual('');
      expect(lines[top + 1]!).toContain('│ ›');
      expect(
        lines[top + 2]!.startsWith('╰'),
        'the prompt box lost a row',
      ).toBeTruthy();
    },
    { rows: 24 },
  ));

test('pgup scrolls back while a reply streams, and end comes back', () =>
  withWindow(
    async (window) => {
      await send(window, 'long');
      await window.shows('30. Line 30 of 200');
      await window.press(PAGE_UP);
      await window.shows('lines below · end to jump to the bottom');

      const reading = window.frame().split('\n')[1];

      // The stream goes on below; the rule says so and the lines stay. A
      // frame can take in several lines at once on a loaded machine, so the
      // count may pass any one number without drawing it (CHD-408).
      const below = () =>
        Number(/new output · (\d+) lines? below/.exec(window.frame())?.[1]);

      await window.shows('↓ new output ·');
      await until('20 new lines below', () => below() >= 20);
      expect(window.frame().split('\n')[1]).toStrictEqual(reading);

      await window.press(END);
      await until('the bottom', () => !window.frame().includes('lines below'));
      expect(
        window.frame().split('\n')[1] !== reading,
        'end did not move',
      ).toBeTruthy();
    },
    { rows: 24 },
  ));

test('a long transcript mounts its tail, more on the way up without the view moving, and the tail again at the bottom', () =>
  withWindow(
    async (window) => {
      await send(window, 'steps');
      await window.shows('150 steps read.');
      await until('the turn to end', () => !window.frame().includes('Working'));

      // The prompt, 150 calls and the reply: the 40 newest are mounted.
      expect(window.mounted('step-150.ts')).toBe(true);
      expect(window.mounted('step-112.ts')).toBe(true);
      expect(window.mounted('step-111.ts')).toBe(false);
      expect(window.mounted('step-1.ts')).toBe(false);

      const top = () => window.frame().split('\n').slice(0, 5).join('\n');

      // Up a page at a time until older calls mount; every frame drawn after
      // the page that mounted them shows the page it moved to.
      for (let page = 0; !window.mounted('step-111.ts'); page++) {
        expect(page < 10, 'nothing more mounted').toBeTruthy();

        const drawn = window.written().length;

        await window.press(PAGE_UP);
        await until('the page drawn', () => window.written().length > drawn);

        const moved = window.written()[drawn]!;

        if (window.mounted('step-111.ts')) {
          for (const frame of window.written().slice(drawn)) {
            expect(frame.split('\n').slice(0, 5).join('\n')).toStrictEqual(
              moved.split('\n').slice(0, 5).join('\n'),
            );
          }
        }
      }

      expect(window.mounted('step-52.ts')).toBe(true);
      expect(window.mounted('step-51.ts')).toBe(false);
      expect(window.frame()).toContain('lines below');

      const reading = top();

      await window.press(END);
      await until('the tail alone', () => !window.mounted('step-111.ts'));
      expect(window.mounted('step-112.ts')).toBe(true);
      expect(top() !== reading, 'end did not move').toBeTruthy();

      // The same window held again backfills again, page after page, up to
      // the very first entry.
      for (let page = 0; !window.frame().includes('chord v'); page++) {
        expect(page < 30, 'the first entry not reached').toBeTruthy();

        const drawn = window.written().length;

        await window.press(PAGE_UP);
        await until('the page drawn', () => window.written().length > drawn);
      }

      expect(window.frame()).toContain('› steps');
      expect(window.mounted('step-1.ts')).toBe(true);
      await window.press(END);
      await until('the tail alone', () => !window.mounted('step-1.ts'));

      // Home mounts the whole transcript and goes to its first row.
      await window.press(HOME);
      await window.shows('chord v');
      expect(window.frame()).toContain('› steps');
      expect(window.frame()).toContain('step-1.ts');
      await window.press(END);
      await until('the tail alone', () => !window.mounted('step-1.ts'));
      expect(window.mounted('step-111.ts')).toBe(false);
    },
    { rows: 24 },
  ));

test('shift+↑ scrolls a line and leaves the prompt alone', () =>
  withWindow(
    async (window) => {
      await send(window, 'long');
      await window.shows('25. Line 25 of 200');
      await window.press(SHIFT_UP);
      await window.shows('end to jump to the bottom');
      // History would have put the last prompt back in the box.
      expect(
        !window.frame().includes('│ › long'),
        'shift+↑ walked history',
      ).toBeTruthy();
    },
    { rows: 24 },
  ));

test('the wheel scrolls a line a step, and leaves the draft and history alone', () =>
  withWindow(
    async (window) => {
      // Reports as the terminal sends them with SGR mouse mode on, steps
      // at once: 64 and 65 are the wheel up and down, 66 and 67 sideways.
      const wheel = (code: number, steps = 1) =>
        window.press(`\x1b[<${code};10;10M`.repeat(steps));

      await send(window, 'long');
      await window.shows('30. Line 30 of 200');
      // Stopped, so nothing more comes in while the view moves.
      await window.press('\x1b');
      await until('the turn to end', () => !window.frame().includes('Working'));
      await window.type('a draft I am still typing');

      const bottom = window.frame();

      // As shift+↑: the rule takes a row of the view as it appears.
      await wheel(64);
      await window.shows('↓ 2 lines below');

      await wheel(64, 11);

      await window.shows('↓ 13 lines below');
      expect(window.frame()).toContain('│ › a draft I am still typing');

      await wheel(65, 12);

      await until('the bottom', () => !window.frame().includes('lines below'));
      expect(window.frame()).toStrictEqual(bottom);

      // The horizontal wheel moves nothing.
      await wheel(66);
      await wheel(67);
      expect(window.frame()).toStrictEqual(bottom);

      await window.press('\x03');
      await window.press(UP);
      await window.shows('│ › long');
    },
    { rows: 24 },
  ));

/**
 * A transcript with a folded call near its start and a page of replies
 * after it, scrolled back a page and on until a prompt below the call is
 * the view's top row, which it returns.
 */
async function backToAPrompt(window: Window): Promise<string> {
  await send(window, 'calls');
  await window.shows('Two calls worked, one failed.');

  for (let turn = 1; turn <= 10; turn++) {
    await send(window, `turn ${turn}`);
    await until(`reply ${turn}`, () => {
      const frame = window.frame();

      return (
        frame.indexOf('came in chunks.', frame.indexOf(`› turn ${turn}`)) > 0 &&
        !frame.includes('Working')
      );
    });
  }

  const top = () => window.frame().split('\n')[0]!;

  await window.press(PAGE_UP);

  // Then line by line, so a prompt lands exactly on the top row.
  for (let step = 0; step < 4 && !top().includes('› turn'); step++) {
    await window.press(SHIFT_UP);
  }

  expect(top()).toContain('› turn');

  return top();
}

test('ctrl+o while scrolled back keeps the entry on top in view', () =>
  withWindow(
    async (window) => {
      const top = await backToAPrompt(window);

      const drawn = window.written().length;

      // The call's output above the view opens, four rows more of it, and
      // no frame drawn meanwhile moved the view.
      await window.press(CTRL_O);
      await window.press(CTRL_O);
      await window.press(CTRL_O);

      for (const frame of window.written().slice(drawn)) {
        expect(frame.split('\n')[0]).toStrictEqual(top);
      }

      expect(window.frame()).toContain('lines below');
      // It did open: at the top, the call shows all its output.
      await window.press('\x1b[H');
      await window.shows('.parse(Deno.args)');
    },
    { rows: 24 },
  ));

test('a resize while scrolled back keeps the entry on top in view', () =>
  withWindow(
    async (window) => {
      const top = await backToAPrompt(window);

      await window.resize({ columns: 60 });
      await until(
        'the window to narrow',
        () => window.frame().split('\n')[0]!.trim() === top.trim(),
      );
      expect(window.frame()).toContain('lines below');
      await window.resize({ columns: 100, rows: 30 });
      await until(
        'the window to widen',
        () => window.frame().split('\n')[0]!.trim() === top.trim(),
      );
      expect(window.frame()).toContain('lines below');
    },
    { rows: 24 },
  ));

test('two sessions scrolled back to the same row each keep their own entry on top', () =>
  withWindow(
    async (window) => {
      // Stopped, so nothing more comes in while the view moves.
      const stopped = async () => {
        await send(window, 'long');
        await window.shows('60. Line 60 of 200');
        await window.press('\x1b');
        await until(
          'the turn to end',
          () => !window.frame().includes('Working'),
        );
      };

      // The top, then the same rows down in each: one row, other entries.
      const back = async () => {
        await window.press('\x1b[H');
        await window.press('\x1b[1;2B'.repeat(30));
        await window.shows('lines below');
      };

      const top = () => window.frame().split('\n').slice(1, 4).join('\n');

      await stopped();
      await leader(window, 'c');
      await ready(window);
      await send(window, 'calls');
      await window.shows('Two calls worked, one failed.');
      await stopped();
      await back();

      const second = top();

      // With both open, so the strip of sessions is drawn for both.
      await leader(window, '1');
      await back();

      const first = top();

      expect(first).not.toStrictEqual(second);
      await leader(window, '2');
      await until('the second session', () => top() === second);
      await leader(window, '1');
      await until('the first session', () => top() === first);
    },
    { rows: 24, columns: 100 },
  ));

test('a thought folds to one line and ctrl+o opens and closes it', () =>
  withWindow(async (window) => {
    await send(window, 'thought');
    await window.shows('Here is the answer.');
    expect(window.frame()).toContain('∴ Thinking…');
    // As in Claude Code the line names no key; the ? panel does.
    expect(
      !window.frame().includes('(ctrl+o'),
      'the thought names its key',
    ).toBeTruthy();
    expect(
      !window.frame().includes('Considering'),
      'the thought was open',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await window.shows('Considering the question.');
    await window.press(CTRL_O);
    await until(
      'the thought to fold',
      () => !window.frame().includes('Considering'),
    );
    // ctrl+o typed nothing into the prompt.
    expect(
      !window.frame().includes('› o'),
      'ctrl+o typed into the draft',
    ).toBeTruthy();
  }));

test('a compaction reads as compacting, then compacted with its summary behind ctrl+o, and a failed one says why', () =>
  withWindow(async (window) => {
    await send(window, 'compact');
    // Within a turn the spinner says it, and the transcript draws nothing.
    await window.shows('Compacting conversation… (');
    expect(
      !window.frame().includes('✻ Compacting'),
      'compacting said twice',
    ).toBeTruthy();
    expect(
      !window.frame().includes('Working…'),
      'the spinner still works',
    ).toBeTruthy();
    await window.shows('⎿  Conversation compacted (ctrl+o for history)');
    expect(
      !window.frame().includes('Compacting conversation'),
      'a finished compaction still runs',
    ).toBeTruthy();
    expect(
      !window.frame().includes('Next: commit'),
      'the summary was open',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await window.shows('Next: commit the change.');
    expect(
      !window.frame().includes('for history'),
      'the open summary still names its key',
    ).toBeTruthy();
    await window.press(CTRL_O);
    await until(
      'the summary to fold',
      () => !window.frame().includes('Next: commit'),
    );
    await send(window, 'compactfail');
    await window.shows(`⎿  Compaction failed: ${COMPACT_ERROR}`);
  }));

test('a drag selects what the agent wrote, and none of the furniture beside it (CHD-172)', () =>
  withWindow(
    async (window) => {
      await send(window, 'edit');
      await window.shows('⏺ Edited.');

      const rows = stripAnsi(window.frame()).split('\n');
      const from = rows.findIndex((row) => row.includes('⏺ Edit(src'));
      const to = rows.findIndex((row) => row.includes('⏺ Edited.'));

      // From the call's name, past the `⎿`, the diff's numbers and signs,
      // to the end of the reply, a report a row as a terminal sends them.
      await window.press(left(rows[from]!.indexOf('Edit('), from, 'down'));

      for (let y = from + 1; y < to; y++) {
        await window.press(left(3, y, 'drag'));
      }

      await window.press(left(20, to, 'drag'));
      await window.press(left(20, to, 'up'));

      expect(window.selected()).toStrictEqual(
        [
          'Edit(src/greeting.ts)',
          'Updated src/greeting.ts with 2 additions and 1 removal',
          '/** Greets someone by name. */',
          'export function greet(name: string): string {',
          '  return "hello " + name;',
          '  return `hello, ${name}`;',
          '}',
          'Edited.',
        ].join('\n'),
      );

      // Painted in the `selection` role, Claude Code's slate even with no
      // colour; the harness writes escapes only while chalk has colour.
      const level = chalk.level;

      chalk.level = 3;

      try {
        expect(window.frame()).toContain('\x1b[48;5;66m');
      } finally {
        chalk.level = level;
      }
    },
    { columns: 100, rows: 30 },
  ));

for (const size of [
  { columns: 120, rows: 40 },
  { columns: 80, rows: 24 },
]) {
  const at = `${size.columns}x${size.rows}`;

  test(`at ${at}, an agent that ends after its turn says so in one line, one that ends in the turn in its own block only (CHD-479)`, () =>
    withWindow(async (window) => {
      await send(window, 'claudebackground');
      await window.shows('The tests run on; I will say when they end.');
      await window.shows('✓ Run the test suite · agent · done in');
      expect(window.frame()).not.toContain('Find the cancel path · agent');
    }, size));

  test(`at ${at}, an agent stopped with x after its turn says the person stopped it (CHD-479)`, () =>
    withWindow(async (window) => {
      await send(window, 'claudebackground');
      await window.shows('The tests run on; I will say when they end.');
      await window.press(DOWN);
      await window.press('\r');
      await window.shows('❯ Run the test suite');
      await window.press('x');
      await window.shows('■ Run the test suite · agent · stopped with x after');
    }, size));
}
